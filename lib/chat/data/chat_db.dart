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
      version: 1,
      onCreate: (db, _) => db.execute('''
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
          appointmentTime TEXT
        )
      '''),
    );
    return _instance!;
  }

  static Future<void> save(String convId, ChatMessage m) async {
    final db = await _db;
    await db.insert('messages', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

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
