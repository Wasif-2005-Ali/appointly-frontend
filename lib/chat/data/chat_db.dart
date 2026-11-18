import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SQLITE PERSISTENCE
// ─────────────────────────────────────────────────────────────────────────────
class ChatDB {
  static Database? _instance;

  static Future<Database> get _db async {
    if (_instance != null) return _instance!;
    _instance = await openDatabase(
      p.join(await getDatabasesPath(), 'appointly_chat_v3.db'),
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          convId TEXT NOT NULL,
          text TEXT NOT NULL,
          time TEXT NOT NULL,
          fromMe INTEGER NOT NULL,
          type TEXT NOT NULL,
          status TEXT NOT NULL,
          isStarred INTEGER NOT NULL DEFAULT 0,
          isDeleted INTEGER NOT NULL DEFAULT 0,
          isForwarded INTEGER NOT NULL DEFAULT 0,
          myReaction TEXT,
          voiceDuration TEXT,
          replyToId TEXT,
          replyToText TEXT,
          replyToFromMe INTEGER,
          appointmentTitle TEXT,
          appointmentDate TEXT,
          appointmentTime TEXT,
          appointmentId INTEGER,
          createdAt TEXT,
          fileName TEXT,
          fileSize INTEGER
        )
      ''');
        // load() filters by convId — without this every open is a
        // full table scan.
        await db.execute(
          'CREATE INDEX idx_messages_convId ON messages(convId)',
        );
        await db.execute('''
        CREATE TABLE conversation_flags (
          convId TEXT PRIMARY KEY,
          isPinned INTEGER NOT NULL DEFAULT 0,
          isMuted INTEGER NOT NULL DEFAULT 0,
          isArchived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      },
      onUpgrade: (db, oldVersion, _) async {
        // v2: keep the original file name + size for image/file messages
        // so cached media still renders offline.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN fileName TEXT');
          await db.execute('ALTER TABLE messages ADD COLUMN fileSize INTEGER');
        }
        // v3: message creation time (date separators) + appointment
        // id (shared cards), and per-room pin/mute/archive flags.
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN appointmentId INTEGER',
          );
          await db.execute('ALTER TABLE messages ADD COLUMN createdAt TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS conversation_flags (
              convId TEXT PRIMARY KEY,
              isPinned INTEGER NOT NULL DEFAULT 0,
              isMuted INTEGER NOT NULL DEFAULT 0,
              isArchived INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        // v4: index on convId (load() filters by it) + drop stale
        // pre-v3 rows whose createdAt is NULL — they have no date,
        // so they used to group under the previous day's separator.
        // The server re-saves them with real dates on the next load.
        if (oldVersion < 4) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_convId '
            'ON messages(convId)',
          );
          await db.delete(
            'messages',
            where: 'createdAt IS NULL',
          );
        }
      },
    );
    return _instance!;
  }

  static Future<void> save(String convId, ChatMessage m) async {
    final db = await _db;
    await db.insert('messages', _row(convId, m),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Save many messages in one batch (history caching) instead of
  /// one insert per message.
  static Future<void> saveAll(String convId, List<ChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final m in msgs) {
      batch.insert('messages', _row(convId, m),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Heal the room cache after a successful REST load: upsert the
  /// server messages (one batch) and delete stale rows that are not
  /// in the server response AND have no date — those are orphan
  /// pre-v3 rows that can never heal themselves and used to group
  /// under the wrong day. Rows NOT in the response that DO have a
  /// date are kept: the REST load only returns the latest 50, so
  /// older paged-in history must survive. Local-only flags
  /// (starred / deleted / reaction) are preserved across the upsert.
  static Future<void> syncRoom(String convId, List<ChatMessage> server) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'messages',
        columns: ['id', 'isStarred', 'isDeleted', 'myReaction'],
        where: 'convId = ?',
        whereArgs: [convId],
      );
      final flags = {
        for (final r in existing)
          r['id'] as String: (
            starred: (r['isStarred'] as int) == 1,
            deleted: (r['isDeleted'] as int) == 1,
            reaction: r['myReaction'] as String?,
          ),
      };
      final serverIds = server.map((m) => m.id).toSet();
      final batch = txn.batch();
      for (final m in server) {
        final row = _row(convId, m);
        final prev = flags[m.id];
        if (prev != null) {
          row['isStarred'] = prev.starred ? 1 : 0;
          row['isDeleted'] = prev.deleted ? 1 : 0;
          row['myReaction'] = prev.reaction;
        }
        batch.insert('messages', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // Orphan undated rows not in the server response: delete.
      final orphans = await txn.query(
        'messages',
        columns: ['id'],
        where: 'convId = ? AND createdAt IS NULL',
        whereArgs: [convId],
      );
      for (final r in orphans) {
        final id = r['id'] as String;
        if (!serverIds.contains(id)) {
          batch.delete('messages', where: 'id = ?', whereArgs: [id]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Delete one cached message by id — used when the server echo
  /// replaces an optimistic row, so the local-id row can't resurface
  /// as a duplicate on cache fallback.
  static Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, Object?> _row(String convId, ChatMessage m) => {
    'id': m.id,
    'convId': convId,
    'text': m.text,
    'time': m.time,
    'fromMe': m.fromMe ? 1 : 0,
    'type': m.type.name,
    'status': m.status.name,
    'isStarred': m.isStarred ? 1 : 0,
    'isDeleted': m.isDeleted ? 1 : 0,
    'isForwarded': m.isForwarded ? 1 : 0,
    'myReaction': m.myReaction,
    'voiceDuration': m.voiceDuration,
    'replyToId': m.replyTo?.id,
    'replyToText': m.replyTo?.text,
    'replyToFromMe': m.replyTo?.fromMe == true ? 1 : 0,
    'appointmentTitle': m.appointmentTitle,
    'appointmentDate': m.appointmentDate,
    'appointmentTime': m.appointmentTime,
    'appointmentId': m.appointmentId,
    'createdAt': m.createdAt?.toUtc().toIso8601String(),
    'fileName': m.fileName,
    'fileSize': m.fileSize,
  };

  static Future<void> update(String convId, ChatMessage m) async {
    final db = await _db;
    await db.update('messages', {
      'text': m.text,
      'status': m.status.name,
      'isStarred': m.isStarred ? 1 : 0,
      'isDeleted': m.isDeleted ? 1 : 0,
      'myReaction': m.myReaction,
    }, where: 'id = ? AND convId = ?', whereArgs: [m.id, convId]);
  }

  static Future<List<ChatMessage>> load(String convId) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'convId = ?',
      whereArgs: [convId],
      orderBy: 'rowid ASC',
    );
    return rows.map((r) => ChatMessage(
      id: r['id'] as String,
      text: r['text'] as String,
      time: r['time'] as String,
      fromMe: (r['fromMe'] as int) == 1,
      type: MessageType.values.firstWhere(
        (t) => t.name == r['type'],
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (s) => s.name == r['status'],
        orElse: () => MessageStatus.sent,
      ),
      isStarred: (r['isStarred'] as int) == 1,
      isDeleted: (r['isDeleted'] as int) == 1,
      isForwarded: (r['isForwarded'] as int) == 1,
      myReaction: r['myReaction'] as String?,
      voiceDuration: r['voiceDuration'] as String?,
      appointmentTitle: r['appointmentTitle'] as String?,
      appointmentDate: r['appointmentDate'] as String?,
      appointmentTime: r['appointmentTime'] as String?,
      appointmentId: r['appointmentId'] as int?,
      createdAt: r['createdAt'] == null
          ? null
          : DateTime.tryParse(r['createdAt'] as String),
      fileName: r['fileName'] as String?,
      fileSize: r['fileSize'] as int?,
      replyTo: r['replyToId'] != null
          ? ChatMessage(
              id: r['replyToId'] as String,
              text: r['replyToText'] as String? ?? '',
              fromMe: (r['replyToFromMe'] as int? ?? 0) == 1,
              time: '',
              type: MessageType.text,
            )
          : null,
    )).toList();
  }

  static Future<void> clear(String convId) async {
    final db = await _db;
    await db.delete('messages', where: 'convId = ?', whereArgs: [convId]);
  }

  /// Delete ALL cached messages on this device. Server history is
  /// untouched and reloads next time a chat is opened. Conversation
  /// flags (pin/mute/archive) are kept — they are settings, not
  /// messages.
  static Future<void> clearAll() async {
    final db = await _db;
    await db.delete('messages');
  }

  /// Persist a room's pin/mute/archive flags (in-memory only before
  /// v3, so they were lost on every app restart).
  static Future<void> saveConversationFlags(
    String convId, {
    required bool pinned,
    required bool muted,
    required bool archived,
  }) async {
    final db = await _db;
    await db.insert('conversation_flags', {
      'convId': convId,
      'isPinned': pinned ? 1 : 0,
      'isMuted': muted ? 1 : 0,
      'isArchived': archived ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// All saved per-room flags, keyed by room id. Rooms without a row
  /// have no flags set.
  static Future<
    Map<String, ({bool pinned, bool muted, bool archived})>
  >
  loadAllConversationFlags() async {
    final db = await _db;
    final rows = await db.query('conversation_flags');
    return {
      for (final r in rows)
        r['convId'] as String:
            (
              pinned: (r['isPinned'] as int) == 1,
              muted: (r['isMuted'] as int) == 1,
              archived: (r['isArchived'] as int) == 1,
            ),
    };
  }

  /// Returns all starred messages across all conversations
  static Future<List<Map<String, dynamic>>> loadAllStarred() async {
    final db = await _db;
    return await db.query(
      'messages',
      where: 'isStarred = 1 AND isDeleted = 0',
      orderBy: 'rowid DESC',
    );
  }
}
