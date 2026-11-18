import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/appointment.dart';

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
      version: 9,
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
    if (oldV < 8) {
      // Remove the fake demo appointments seeded by old builds
      // (_seedAppointmentsForUser, now deleted). The server is the
      // source of truth for appointments; match on name + service so
      // a real local appointment that happens to share a name survives.
      const seeds = [
        ('Sara Nadeem', 'Facial'),
        ('Shahid Rauf', 'Physiotherapy'),
        ('Iqra Butt', 'Hair Coloring'),
        ('Asim Nawaz', 'Consultation'),
        ('Imran Shah', 'Consultation'),
        ('Lubna Aslam', 'Skin Analysis'),
        ('Faisal Mir', 'Deep Tissue'),
        ('Anam Riaz', 'Facial'),
        ('Aisha Khan', 'Strategy Discussion'),
        ('Omar Farooq', 'Initial Consultation'),
        ('Zara Malik', 'Hair Coloring & Cut'),
        ('Bilal Chaudhry', 'Physiotherapy'),
        ('Hina Raza', 'Skin Care Session'),
        ('Tariq Ahmed', 'Sports Massage'),
        ('Sana Qureshi', 'Nail Art Session'),
        ('Nadia Hussain', 'Career Coaching'),
        ('Kamran Iqbal', 'Legal Consultation'),
        ('Ali Rehman', 'Dental Checkup'),
        ('Sara Baig', 'Nutrition Planning'),
        ('Fatima Siddiqui', 'Eye Examination'),
        ('Usman Tariq', 'Strategy Discussion'),
        ('Rabia Noor', 'Coaching Session'),
      ];
      final where = List.filled(seeds.length, '(name = ? AND service = ?)').join(' OR ');
      final args = seeds.expand((s) => [s.$1, s.$2]).toList();
      try { await db.delete('appointments', where: where, whereArgs: args); } catch (_) {}
    }
    if (oldV < 9) {
      // Personal tasks are now persisted (they used to be in-memory
      // only and vanished on restart). One JSON row per task.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS personal_tasks (
          id      TEXT PRIMARY KEY,
          user_id INTEGER,
          data    TEXT NOT NULL
        )
      ''');
      // Index the per-user appointment lookups (getAllAppointments,
      // insertAppointment's MAX query) instead of full table scans.
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_appointments_user_id '
          'ON appointments(user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_personal_tasks_user_id '
          'ON personal_tasks(user_id)');
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
    await db.execute('''
      CREATE TABLE personal_tasks (
        id      TEXT PRIMARY KEY,
        user_id INTEGER,
        data    TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_appointments_user_id ON appointments(user_id)');
    await db.execute(
        'CREATE INDEX idx_personal_tasks_user_id ON personal_tasks(user_id)');
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  // NOTE: registration / login run against the backend API now
  // (AuthService). The old local registerUser/loginUser — which
  // compared an unsalted SHA-256 hash — were deleted, not fixed.

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
  // NOTE: insertAppointment / getAppointmentById had no callers and
  // were deleted. Appointments come from the backend; SQLite only
  // caches them (getAllAppointments) and holds local-only fields.

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
      Map<String, List<List<String>>> slots,
      {int? maxPerDay,
      int? bufferMinutes,
      bool? breakEnabled,
      String? breakStart,
      String? breakEnd,
      int? bookingWindowDays,
      String? status}) async {
    final db = await database;
    final batch = db.batch();
    void put(String key, String value) => batch.insert(
          'user_settings',
          {'user_id': userId, 'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    put('avail_days', jsonEncode(days));
    put('avail_slots', jsonEncode(slots));
    if (maxPerDay != null) put('avail_max_per_day', '$maxPerDay');
    if (bufferMinutes != null) put('avail_buffer_minutes', '$bufferMinutes');
    if (breakEnabled != null) put('avail_break_enabled', breakEnabled ? '1' : '0');
    if (breakStart != null) put('avail_break_start', breakStart);
    if (breakEnd != null) put('avail_break_end', breakEnd);
    if (bookingWindowDays != null) {
      put('avail_booking_window_days', '$bookingWindowDays');
    }
    if (status != null) put('avail_status', status);
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> loadAvailability(int userId) async {
    final db = await database;
    final rows = await db.query('user_settings',
        where: 'user_id = ? AND key LIKE ?',
        whereArgs: [userId, 'avail_%']);
    if (rows.isEmpty) return null;
    final byKey = <String, String>{
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    if (!byKey.containsKey('avail_days') ||
        !byKey.containsKey('avail_slots')) {
      return null;
    }
    return {
      'days': byKey['avail_days']!,
      'slots': byKey['avail_slots']!,
      'maxPerDay': int.tryParse(byKey['avail_max_per_day'] ?? ''),
      'bufferMinutes': int.tryParse(byKey['avail_buffer_minutes'] ?? ''),
      'breakEnabled': byKey['avail_break_enabled'] == '1',
      'breakStart': byKey['avail_break_start'],
      'breakEnd': byKey['avail_break_end'],
      'bookingWindowDays':
          int.tryParse(byKey['avail_booking_window_days'] ?? ''),
      'status': byKey['avail_status'],
    };
  }

  // ── Personal tasks (persisted per user as one JSON row each) ─────────────
  Future<List<Map<String, dynamic>>> getPersonalTasks(int userId) async {
    final db = await database;
    final rows = await db.query('personal_tasks',
        where: 'user_id = ?', whereArgs: [userId]);
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      try {
        out.add(jsonDecode(r['data'] as String) as Map<String, dynamic>);
      } catch (_) {
        // Skip a corrupt row instead of losing the whole list.
      }
    }
    return out;
  }

  /// Replaces the user's whole task list in one batch.
  Future<void> savePersonalTasks(
      int userId, List<Map<String, dynamic>> tasks) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('personal_tasks', where: 'user_id = ?', whereArgs: [userId]);
    for (final t in tasks) {
      batch.insert('personal_tasks', {
        'id': t['id'],
        'user_id': userId,
        'data': jsonEncode(t),
      });
    }
    await batch.commit(noResult: true);
  }
}