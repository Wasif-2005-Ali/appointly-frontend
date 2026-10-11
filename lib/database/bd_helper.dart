import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/appointment.dart';

enum RegisterResult { success, emailAlreadyExists, error }
enum LoginResult    { success, wrongPassword, emailNotFound, error }

class DBHelper {
  DBHelper._();
  static final DBHelper instance = DBHelper._();
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'appointly.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int v) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name     TEXT NOT NULL,
          email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
          password_hash TEXT NOT NULL,
          profession    TEXT NOT NULL DEFAULT '',
          created_at    TEXT NOT NULL
        )
      ''');
    }
    if (oldV < 3) {
      // Add per-user profile columns to users
      try { await db.execute("ALTER TABLE users ADD COLUMN phone TEXT NOT NULL DEFAULT ''"); } catch (_) {}
      try { await db.execute("ALTER TABLE users ADD COLUMN bio TEXT NOT NULL DEFAULT ''"); } catch (_) {}
      try { await db.execute("ALTER TABLE users ADD COLUMN profile_status TEXT NOT NULL DEFAULT 'Available'"); } catch (_) {}
      try { await db.execute("ALTER TABLE users ADD COLUMN privacy_mode TEXT NOT NULL DEFAULT 'Public'"); } catch (_) {}
      try { await db.execute("ALTER TABLE users ADD COLUMN profile_image BLOB"); } catch (_) {}
      try { await db.execute("ALTER TABLE users ADD COLUMN theme_mode TEXT NOT NULL DEFAULT 'navyLight'"); } catch (_) {}
      // Add user_id to appointments so they are isolated per account
      try { await db.execute("ALTER TABLE appointments ADD COLUMN user_id INTEGER"); } catch (_) {}
      // Add user_id to user_settings
      try { await db.execute("ALTER TABLE user_settings ADD COLUMN user_id INTEGER"); } catch (_) {}
      // ── CRITICAL: clear any stale sessions from the old schema ────────
      // Old sessions had no user_id column, so they could match the new
      // NULL-user_id query and skip the login screen entirely.
      try { await db.delete('user_settings', where: "key = 'session_user_id'"); } catch (_) {}
    }
    if (oldV < 4) {
      try { await db.delete('user_settings', where: "key = 'session_user_id'"); } catch (_) {}
    }
    if (oldV < 6) {
      // Add sequential appointment number per user
      try { await db.execute("ALTER TABLE appointments ADD COLUMN appt_number INTEGER"); } catch (_) {}
    }
    if (oldV < 7) {
      // Add cancellation_note for emergency cancel/reschedule reason
      try { await db.execute("ALTER TABLE appointments ADD COLUMN cancellation_note TEXT NOT NULL DEFAULT ''"); } catch (_) {}
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name      TEXT NOT NULL,
        email          TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash  TEXT NOT NULL,
        profession     TEXT NOT NULL DEFAULT '',
        phone          TEXT NOT NULL DEFAULT '',
        bio            TEXT NOT NULL DEFAULT '',
        profile_status TEXT NOT NULL DEFAULT 'Available',
        privacy_mode   TEXT NOT NULL DEFAULT 'Public',
        profile_image  BLOB,
        theme_mode     TEXT NOT NULL DEFAULT 'navyLight',
        created_at     TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE appointments (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER,
        appt_number INTEGER,
        name        TEXT    NOT NULL,
        service     TEXT    NOT NULL,
        date_time   TEXT    NOT NULL,
        duration    TEXT    NOT NULL DEFAULT '30 min',
        location    TEXT    NOT NULL DEFAULT '',
        note        TEXT    NOT NULL DEFAULT '',
        cancellation_note TEXT NOT NULL DEFAULT '',
        status      TEXT    NOT NULL DEFAULT 'pending',
        color_value INTEGER NOT NULL DEFAULT ${0xFF4A90D9}
      )
    ''');
    await db.execute('''
      CREATE TABLE user_settings (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        key     TEXT NOT NULL,
        value   TEXT NOT NULL,
        UNIQUE(user_id, key)
      )
    ''');
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static String _hash(String pw) => sha256.convert(utf8.encode(pw)).toString();

  Future<RegisterResult> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String profession,
  }) async {
    final db = await database;
    try {
      final id = await db.insert('users', {
        'full_name': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password_hash': _hash(password),
        'profession': profession.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      // Seed sample appointments for this new user
      await _seedAppointmentsForUser(db, id);
      return RegisterResult.success;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return RegisterResult.emailAlreadyExists;
      return RegisterResult.error;
    } catch (_) { return RegisterResult.error; }
  }

  Future<({LoginResult result, Map<String, dynamic>? userRow})> loginUser({
    required String email,
    required String password,
  }) async {
    final db = await database;
    try {
      final rows = await db.query('users',
          where: 'email = ?',
          whereArgs: [email.trim().toLowerCase()],
          limit: 1);
      if (rows.isEmpty) return (result: LoginResult.emailNotFound, userRow: null);
      if (rows.first['password_hash'] != _hash(password))
        return (result: LoginResult.wrongPassword, userRow: null);

      // Seed appointments if this user has none (e.g. accounts created before v3)
      final userId = rows.first['id'] as int;
      final apptCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM appointments WHERE user_id = ?', [userId]),
      ) ?? 0;
      if (apptCount == 0) {
        await _seedAppointmentsForUser(db, userId);
      }

      return (result: LoginResult.success, userRow: Map<String, dynamic>.from(rows.first));
    } catch (_) { return (result: LoginResult.error, userRow: null); }
  }

  Future<Map<String, dynamic>?> getUserById(int id) async {
    final db   = await database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  // ── User profile persistence ───────────────────────────────────────────────
  Future<void> updateUserProfile(int userId, {
    String?      name,
    String?      phone,
    String?      bio,
    String?      profileStatus,
    String?      privacyMode,
    Uint8List?   profileImage,
    bool         clearImage = false,
    String?      themeMode,
  }) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (name          != null) data['full_name']      = name;
    if (phone         != null) data['phone']          = phone;
    if (bio           != null) data['bio']            = bio;
    if (profileStatus != null) data['profile_status'] = profileStatus;
    if (privacyMode   != null) data['privacy_mode']   = privacyMode;
    if (themeMode     != null) data['theme_mode']     = themeMode;
    if (clearImage)             data['profile_image']  = null;
    else if (profileImage != null) data['profile_image'] = profileImage;
    if (data.isEmpty) return;
    await db.update('users', data, where: 'id = ?', whereArgs: [userId]);
  }

  // ── Session ───────────────────────────────────────────────────────────────
  static const _kSession = 'session_user_id';

  Future<void> saveSession(int id) async {
    final db = await database;
    await db.insert(
      'user_settings',
      {'user_id': null, 'key': _kSession, 'value': '$id'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearSession() async {
    final db = await database;
    await db.delete('user_settings',
        where: 'user_id IS NULL AND key = ?', whereArgs: [_kSession]);
  }

  Future<Map<String, dynamic>?> restoreSession() async {
    final db   = await database;
    final rows = await db.query('user_settings',
        where: 'user_id IS NULL AND key = ?',
        whereArgs: [_kSession],
        limit: 1);
    if (rows.isEmpty) return null;
    final id = int.tryParse(rows.first['value'] as String);
    if (id == null) return null;
    return getUserById(id);
  }

  // ── Appointments CRUD (per-user) ───────────────────────────────────────────
  Future<int> insertAppointment(Appointment a, int userId) async {
    final db  = await database;
    // Compute next sequential number for this user
    final rows = await db.rawQuery(
      'SELECT MAX(appt_number) as mx FROM appointments WHERE user_id = ?',
      [userId],
    );
    final maxNum = (rows.first['mx'] as int?) ?? 0;
    a.apptNumber = maxNum + 1;

    final map = a.toMap();
    map['user_id'] = userId;
    return db.insert('appointments', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Appointment>> getAllAppointments(int userId) async {
    final db   = await database;
    final maps = await db.query(
      'appointments',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'date_time ASC',
    );
    return maps.map(Appointment.fromMap).toList();
  }

  Future<Appointment?> getAppointmentById(int id) async {
    final db   = await database;
    final rows = await db.query('appointments', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Appointment.fromMap(rows.first);
  }

  Future<void> updateAppointment(Appointment a) async {
    final db = await database;
    await db.update('appointments', a.toMap(),
        where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> updateAppointmentStatus(int id, ApptStatus s) async {
    final db = await database;
    await db.update('appointments', {'status': s.name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAppointment(int id) async {
    final db = await database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  // ── Per-user Settings ─────────────────────────────────────────────────────
  Future<void> setUserSetting(int userId, String key, String value) async {
    final db = await database;
    await db.insert(
      'user_settings',
      {'user_id': userId, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getUserSetting(int userId, String key) async {
    final db   = await database;
    final rows = await db.query('user_settings',
        where: 'user_id = ? AND key = ?', whereArgs: [userId, key]);
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  // Legacy global settings (kept for compat)
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('user_settings', {'user_id': null, 'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<String?> getSetting(String key) async {
    final db   = await database;
    final rows = await db.query('user_settings',
        where: 'user_id IS NULL AND key = ?', whereArgs: [key]);
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }
  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('user_settings',
        where: 'user_id IS NULL AND key = ?', whereArgs: [key]);
  }
  Future<void> insertOrUpdateSetting(String key, String value) => setSetting(key, value);

  Future<void> saveAvailability(int userId, Map<String, bool> days,
      Map<String, List<List<String>>> slots) async {
    final db = await database;
    // Encode as two JSON strings stored in user_settings
    final daysJson  = days.entries.map((e) => '"${e.key}":${e.value}').join(',');
    final slotsJson = slots.entries.map((e) {
      final arr = e.value.map((s) => '["${s[0]}","${s[1]}"]').join(',');
      return '"${e.key}":[$arr]';
    }).join(',');
    await db.insert('user_settings',
        {'user_id': userId, 'key': 'avail_days',  'value': '{$daysJson}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('user_settings',
        {'user_id': userId, 'key': 'avail_slots', 'value': '{$slotsJson}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> loadAvailability(int userId) async {
    final db = await database;
    final dRows = await db.query('user_settings',
        where: 'user_id = ? AND key = ?', whereArgs: [userId, 'avail_days']);
    final sRows = await db.query('user_settings',
        where: 'user_id = ? AND key = ?', whereArgs: [userId, 'avail_slots']);
    if (dRows.isEmpty || sRows.isEmpty) return null;
    return {'days': dRows.first['value'] as String,
      'slots': sRows.first['value'] as String};
  }

  // ── Seed (per user) ────────────────────────────────────────────────────────
  Future<void> _seedAppointmentsForUser(Database db, int userId) async {
    final now    = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    DateTime dt(int d, int h, int m) {
      final day = sunday.add(Duration(days: d));
      return DateTime(day.year, day.month, day.day, h, m);
    }
    final seeds = [
      _s(userId, 1, 'Sara Nadeem',     'Facial',              dt(0,11, 0),'45 min','Style House, Gulberg',      '',                         ApptStatus.confirmed,0xFF4A90D9),
      _s(userId, 2, 'Shahid Rauf',     'Physiotherapy',       dt(1,10, 0),'60 min','PhysioPlus Clinic',         '',                         ApptStatus.confirmed,0xFF0B2447),
      _s(userId, 3, 'Iqra Butt',       'Hair Coloring',       dt(1,13, 0),'90 min','Style Studio, Gulberg',     '',                         ApptStatus.pending,  0xFF4A90D9),
      _s(userId, 4, 'Asim Nawaz',      'Consultation',        dt(1,16, 0),'30 min','Video Call · Zoom',         '',                         ApptStatus.confirmed,0xFF2A6AB5),
      _s(userId, 5, 'Imran Shah',      'Consultation',        dt(2, 8,30),'30 min','Office Block B, F-6',       '',                         ApptStatus.confirmed,0xFF0B2447),
      _s(userId, 6, 'Lubna Aslam',     'Skin Analysis',       dt(2,12, 0),'45 min','Glow Wellness Center',      '',                         ApptStatus.pending,  0xFF4A90D9),
      _s(userId, 7, 'Faisal Mir',      'Deep Tissue',         dt(2,14, 0),'60 min','ActiveBody Spa',            '',                         ApptStatus.confirmed,0xFF1A5EA8),
      _s(userId, 8, 'Anam Riaz',       'Facial',              dt(2,16,30),'45 min','Beauty Lounge, DHA',        '',                         ApptStatus.confirmed,0xFF2A6AB5),
      _s(userId, 9, 'Aisha Khan',      'Strategy Discussion', dt(3, 9, 0),'45 min','Room 3A, City Office',      'Bring Q3 report',          ApptStatus.confirmed,0xFF4A90D9),
      _s(userId,10, 'Omar Farooq',     'Initial Consultation',dt(3,10, 0),'30 min','Video Call · Zoom',         'Send Zoom link first',     ApptStatus.confirmed,0xFF2ECC96),
      _s(userId,11, 'Zara Malik',      'Hair Coloring & Cut', dt(3,11,30),'90 min','Style Studio, Gulberg',     '',                         ApptStatus.pending,  0xFFF4A24A),
      _s(userId,12, 'Bilal Chaudhry',  'Physiotherapy',       dt(3,13, 0),'60 min','PhysioPlus Clinic',         'Follow-up from last week', ApptStatus.confirmed,0xFF7C3AED),
      _s(userId,13, 'Hina Raza',       'Skin Care Session',   dt(3,14,30),'60 min','Glow Wellness Center',      '',                         ApptStatus.pending,  0xFFE05C5C),
      _s(userId,14, 'Tariq Ahmed',     'Sports Massage',      dt(3,16, 0),'45 min','ActiveBody Spa',            'Deep tissue requested',    ApptStatus.confirmed,0xFF0D9E6A),
      _s(userId,15, 'Sana Qureshi',    'Nail Art Session',    dt(3,17, 0),'30 min','Beauty Lounge, DHA',        'Client cancelled AM',      ApptStatus.cancelled,0xFF8AA0BC),
      _s(userId,16, 'Nadia Hussain',   'Career Coaching',     dt(4,10, 0),'60 min','Video Call · Google Meet',  'Resume review',            ApptStatus.confirmed,0xFF4A90D9),
      _s(userId,17, 'Kamran Iqbal',    'Legal Consultation',  dt(4,14, 0),'45 min','Office Block B, F-6',       '',                         ApptStatus.confirmed,0xFF7C3AED),
      _s(userId,18, 'Ali Rehman',      'Dental Checkup',      dt(5, 9,30),'45 min','SmileCare Clinic',          '',                         ApptStatus.confirmed,0xFFF4A24A),
      _s(userId,19, 'Sara Baig',       'Nutrition Planning',  dt(5,11, 0),'30 min','Wellness Hub, Bahria',      'First appointment',        ApptStatus.pending,  0xFF2ECC96),
      _s(userId,20, 'Fatima Siddiqui', 'Eye Examination',     dt(6,15, 0),'30 min','VisionPlus Eye Center',     '',                         ApptStatus.confirmed,0xFFE05C5C),
      _s(userId,21, 'Usman Tariq',     'Strategy Discussion', now.subtract(const Duration(days:4)),'60 min','Head Office','Completed',     ApptStatus.confirmed,0xFF0D9E6A),
      _s(userId,22, 'Rabia Noor',      'Coaching Session',    now.subtract(const Duration(days:7)),'45 min','Video Call','Great session',  ApptStatus.confirmed,0xFF4A90D9),
    ];
    final batch = db.batch();
    for (final s in seeds) batch.insert('appointments', s);
    await batch.commit(noResult: true);
  }

  static Map<String, dynamic> _s(int userId, int num, String nm, String svc, DateTime dt,
      String dur, String loc, String note, ApptStatus st, int clr) => {
    'user_id':userId,'appt_number':num,'name':nm,'service':svc,
    'date_time':dt.toIso8601String(),
    'duration':dur,'location':loc,'note':note,'status':st.name,'color_value':clr,
  };
}