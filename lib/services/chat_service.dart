import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../user_session.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'token_storage.dart';

/// A chat room as returned by `/api/chat/rooms/`.
class ChatRoomInfo {
  final String roomId;
  final String name;
  final List<String> participants;
  final bool isGroup;
  final DateTime? createdAt;

  /// Enriched preview fields from the rooms list (`last_message` +
  /// `unread_count`). Null on older backends — callers fall back to a
  /// per-room fetch when they are missing.
  final ChatApiMessage? lastMessage;
  final int? unreadCount;

  const ChatRoomInfo({
    required this.roomId,
    required this.name,
    required this.participants,
    required this.isGroup,
    required this.createdAt,
    this.lastMessage,
    this.unreadCount,
  });

  factory ChatRoomInfo.fromJson(Map<String, dynamic> json) => ChatRoomInfo(
    roomId: json['room_id'] as String,
    name: json['name'] as String? ?? '',
    participants:
        (json['participants'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    isGroup: json['is_group'] as bool? ?? false,
    createdAt: ChatApiMessage.parseServerTime(
      json['created_at'] as String?,
    ),
    lastMessage: json['last_message'] is Map<String, dynamic>
        ? ChatApiMessage.fromJson(json['last_message'] as Map<String, dynamic>)
        : null,
    unreadCount: (json['unread_count'] as num?)?.toInt(),
  );
}

/// One chat message as returned by the REST API and the WebSocket.
class ChatApiMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderUsername;
  final String content;
  final String messageType;
  final List<String> readBy;
  final DateTime createdAt;
  // Media-only fields (image/file messages). Old messages lack them.
  final String? fileName;
  final int? fileSize;
  // Reply-quote fields (added by the backend alongside `reply_to_id`
  // / `reply_to_text` on the send frame). Old messages lack them.
  final String? replyToId;
  final String? replyToText;

  const ChatApiMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.messageType,
    required this.readBy,
    required this.createdAt,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.replyToText,
  });

  /// Parse a server timestamp defensively: the backend sends UTC ISO
  /// strings, but if one ever arrives without an offset Dart would
  /// parse it as local time — shifting the day for PKT users (UTC+5).
  /// A string with no `Z` or `±hh:mm` offset is assumed to be UTC.
  /// Pure — unit-tested.
  static DateTime? parseServerTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final hasOffset =
        raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    return DateTime.tryParse(hasOffset ? raw : '${raw}Z');
  }

  factory ChatApiMessage.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawSize = json['file_size'];
    return ChatApiMessage(
      id: rawId?.toString() ?? '',
      roomId: json['room_id'] as String? ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderUsername: json['sender_username'] as String? ?? '',
      content: json['content'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      readBy:
          (json['read_by'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      createdAt:
          parseServerTime(json['created_at'] as String?) ?? DateTime.now(),
      fileName: json['file_name'] as String?,
      fileSize: rawSize is num ? rawSize.toInt() : null,
      replyToId: json['reply_to_id']?.toString(),
      replyToText: json['reply_to_text'] as String?,
    );
  }

  /// One-line text for the inbox preview. Media messages carry a URL
  /// in [content], which must never leak into the preview. Pure.
  String get previewText {
    switch (messageType) {
      case 'image':
        return 'Photo';
      case 'voice':
        return 'Voice message';
      case 'file':
        final name = fileName ?? '';
        // Voice notes arrive as file messages — never show the raw
        // `voice_note_<ts>.m4a` file name in the preview.
        final lower = name.toLowerCase();
        if (lower.startsWith('voice_note_') || lower.endsWith('.m4a')) {
          return 'Voice message';
        }
        return name.isNotEmpty ? name : 'File';
      default:
        return content;
    }
  }
}

/// One page of message history from
/// `GET /api/chat/rooms/<room_id>/messages/`.
class MessagePage {
  final String roomId;
  final int count;
  final String? nextBefore;
  final List<ChatApiMessage> messages;

  const MessagePage({
    required this.roomId,
    required this.count,
    required this.nextBefore,
    required this.messages,
  });

  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
    roomId: json['room_id'] as String? ?? '',
    count: json['count'] as int? ?? 0,
    nextBefore: json['next_before'] as String?,
    messages:
        (json['messages'] as List?)
            ?.map((e) => ChatApiMessage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

/// Preview data for one room in the inbox: the latest message and the
/// number of unread messages.
class RoomPreview {
  final String roomId;
  final ChatApiMessage? lastMessage;
  final int unreadCount;

  const RoomPreview({
    required this.roomId,
    required this.lastMessage,
    required this.unreadCount,
  });
}

/// Connection state of a [ChatRoomConnection].
enum ChatConnectionState { connecting, connected, reconnecting, closed, failed }

/// Chat rooms + messages against `/api/chat/` (REST) and
/// `/ws/chat/<room_id>/` (WebSocket).
///
/// Throws [ApiException] with a user-friendly message on failure.
/// There is no REST endpoint for sending a message — sending is
/// WebSocket-only, via [connectRoom].
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const _chat = '/api/chat';

  /// WebSocket base derived from the REST base URL
  /// (`https://…` → `wss://…`, `http://…` → `ws://…`).
  static String get wsBase {
    final base = ApiConfig.baseUrl;
    if (base.startsWith('https://')) {
      return base.replaceFirst('https://', 'wss://');
    }
    return base.replaceFirst('http://', 'ws://');
  }

  String? get _myId => UserSession.instance.userId?.toString();

  /// GET /api/chat/rooms/ — rooms I belong to.
  Future<List<ChatRoomInfo>> listRooms() async {
    final res = await ApiClient.instance.get('$_chat/rooms/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load your chats.'),
        statusCode: res.statusCode,
      );
    }
    final decoded = jsonDecode(res.body);
    final List items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      // Paginated shape, in case the backend enables pagination later.
      items = decoded['results'] as List;
    } else {
      return const [];
    }
    return items
        .map((e) => ChatRoomInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/chat/rooms/<room_id>/ — one room (members only).
  Future<ChatRoomInfo> getRoom(String roomId) async {
    final res = await ApiClient.instance.get('$_chat/rooms/$roomId/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load the chat.'),
        statusCode: res.statusCode,
      );
    }
    return ChatRoomInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/chat/rooms/ — create a room. The creator is added
  /// automatically. A DM (isGroup false) takes at most one extra
  /// participant; every participant ID must be an existing user.
  Future<ChatRoomInfo> createRoom({
    required String name,
    List<String> participantIds = const [],
    bool isGroup = false,
  }) async {
    final res = await ApiClient.instance.post(
      '$_chat/rooms/',
      body: {
        'name': name,
        'participant_ids': participantIds,
        'is_group': isGroup,
      },
    );
    if (res.statusCode != 201) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not create the chat.'),
        statusCode: res.statusCode,
      );
    }
    return ChatRoomInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/chat/rooms/<room_id>/participants/add/ — group rooms
  /// only; the added user must exist.
  Future<ChatRoomInfo> addParticipant(String roomId, String userId) async {
    final res = await ApiClient.instance.post(
      '$_chat/rooms/$roomId/participants/add/',
      body: {'user_id': userId},
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not add the participant.'),
        statusCode: res.statusCode,
      );
    }
    return ChatRoomInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/chat/rooms/<room_id>/participants/remove/ with my own
  /// user ID — i.e. leave the room. Members can only remove
  /// themselves.
  Future<void> leaveRoom(String roomId) async {
    final myId = _myId;
    if (myId == null) {
      throw const ApiException('You are not logged in.');
    }
    final res = await ApiClient.instance.post(
      '$_chat/rooms/$roomId/participants/remove/',
      body: {'user_id': myId},
    );
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not leave the chat.'),
        statusCode: res.statusCode,
      );
    }
  }

  /// POST /api/chat/rooms/<room_id>/read/ — mark the room's messages
  /// as read by me, server-side, so unread badges stay cleared across
  /// devices and app restarts. Best-effort: failures are ignored —
  /// the local stamp ([markRoomReadLocally]) still clears the badge
  /// for this session.
  Future<void> markRoomRead(String roomId) async {
    try {
      await ApiClient.instance.post('$_chat/rooms/$roomId/read/');
    } catch (_) {
      // Best-effort: unread badges still clear locally.
    }
  }

  /// GET /api/chat/rooms/<room_id>/messages/ — the 50 most recent
  /// messages, oldest first. Pass [before] (ISO 8601) to page back.
  Future<MessagePage> listMessages(String roomId, {String? before}) async {
    final path = before == null || before.isEmpty
        ? '$_chat/rooms/$roomId/messages/'
        : '$_chat/rooms/$roomId/messages/?before=${Uri.encodeComponent(before)}';
    final res = await ApiClient.instance.get(path);
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load messages.'),
        statusCode: res.statusCode,
      );
    }
    return MessagePage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/chat/rooms/<room_id>/media/ — upload a photo or file.
  /// Returns the created message (content is the Cloudinary URL).
  /// The size check runs first so oversized files fail fast, before
  /// any upload starts; the backend enforces the same limits.
  Future<ChatApiMessage> uploadMedia(
    String roomId, {
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    validateMediaSize(bytes.length, fileName);
    final res = await ApiClient.instance.uploadMultipart(
      '$_chat/rooms/$roomId/media/',
      field: 'file',
      bytes: bytes,
      filename: fileName,
      mimeType: mimeType ?? mimeTypeFor(fileName),
    );
    if (res.statusCode != 201) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not send the file.'),
        statusCode: res.statusCode,
      );
    }
    return ChatApiMessage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Server size limits (also enforced by the backend): images 10 MB,
  /// other files 25 MB.
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxFileBytes = 25 * 1024 * 1024;

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };

  /// True when [fileName] looks like an image (by extension). Pure.
  static bool isImageFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return false;
    return _imageExtensions.contains(
      fileName.substring(dot + 1).toLowerCase(),
    );
  }

  /// Throws [ApiException] when [byteCount] exceeds the limit for the
  /// file kind. Pure — unit-tested.
  static void validateMediaSize(int byteCount, String fileName) {
    if (isImageFile(fileName)) {
      if (byteCount > maxImageBytes) {
        throw const ApiException(
          'That photo is over 10 MB. Pick a smaller one.',
        );
      }
    } else if (byteCount > maxFileBytes) {
      throw const ApiException('That file is over 25 MB.');
    }
  }

  /// Best-effort MIME type from the file extension, so the server can
  /// tell images from documents. Unknown extensions fall back to a
  /// generic binary type. Pure.
  static String mimeTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip' => 'application/zip',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'opus' => 'audio/ogg',
      'mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };
  }

  /// Human-readable size, e.g. `512 B`, `1.5 KB`, `2.4 MB`. Pure.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return '${kb % 1 == 0 ? kb.toInt() : kb.toStringAsFixed(1)} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb % 1 == 0 ? mb.toInt() : mb.toStringAsFixed(1)} MB';
  }

  /// Locally remembered "read up to" timestamps, one per room. The
  /// backend marks messages read server-side (POST …/read/, see
  /// [markRoomRead]), so `read_by` is checked first; this local stamp
  /// is only a fallback for messages read while offline or before
  /// the server call landed. Opening a thread stamps the room here
  /// ([markRoomReadLocally]); the unread count then only counts
  /// messages newer than the stamp.
  final Map<String, DateTime> _lastReadAt = {};

  /// Short-lived preview cache (30s TTL): the dashboard badge and
  /// the inbox both ask for previews, and navigating back from a
  /// thread refires the fetch — the cache keeps that to one network
  /// round-trip per window. [_previewFetchInFlight] dedupes
  /// concurrent callers into a single fetch.
  Map<String, RoomPreview>? _previewCache;
  DateTime? _previewCacheAt;
  Future<Map<String, RoomPreview>>? _previewFetchInFlight;
  static const _previewCacheTtl = Duration(seconds: 30);

  /// Remember that the user has seen this room's messages up to now.
  void markRoomReadLocally(String roomId) {
    _lastReadAt[roomId] = DateTime.now().toUtc();
    // The cached preview would otherwise keep showing the stale
    // unread count until the TTL expires.
    final preview = _previewCache?[roomId];
    if (preview != null && preview.unreadCount != 0) {
      _previewCache![roomId] = RoomPreview(
        roomId: roomId,
        lastMessage: preview.lastMessage,
        unreadCount: 0,
      );
    }
  }

  /// Count unread messages in [messages] for [myId]: messages from
  /// someone else that I have not read. A message counts as read when
  /// my ID is in its `read_by` list, or when it arrived at or before
  /// the room's local last-read stamp (see [markRoomReadLocally]).
  /// Pure — unit-tested.
  static int countUnread(
    List<ChatApiMessage> messages, {
    required String? myId,
    DateTime? lastReadAt,
  }) {
    if (myId == null) return 0;
    var count = 0;
    for (final m in messages) {
      if (m.senderId == myId) continue;
      if (m.readBy.contains(myId)) continue;
      if (lastReadAt != null && !m.createdAt.isAfter(lastReadAt)) continue;
      count++;
    }
    return count;
  }

  /// Fetch a preview for each room: the latest message + unread count.
  ///
  /// Rooms whose list entry already carries `last_message` +
  /// `unread_count` (enriched rooms list) need no extra call. Only
  /// rooms missing those fields fall back to one `listMessages`
  /// (50 msgs) each, so the inbox stays fast on the new backend and
  /// still works if the backend change deploys later than the
  /// client. Results are cached for 30s (see [_previewCache]) and
  /// concurrent callers share one in-flight fetch. A room that fails
  /// to load gets an empty preview instead of failing the whole
  /// inbox. The fallback unread count is capped at 50 per room.
  Future<Map<String, RoomPreview>> fetchRoomPreviews(
    List<ChatRoomInfo> rooms, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final cache = _previewCache;
    final cacheAt = _previewCacheAt;
    if (!forceRefresh &&
        cache != null &&
        cacheAt != null &&
        now.difference(cacheAt) < _previewCacheTtl &&
        rooms.every((r) => cache.containsKey(r.roomId))) {
      return {for (final r in rooms) r.roomId: cache[r.roomId]!};
    }
    final inFlight = _previewFetchInFlight;
    if (inFlight != null && !forceRefresh) return inFlight;
    final future = _fetchRoomPreviewsFresh(rooms);
    _previewFetchInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_previewFetchInFlight, future)) {
        _previewFetchInFlight = null;
      }
    }
  }

  Future<Map<String, RoomPreview>> _fetchRoomPreviewsFresh(
    List<ChatRoomInfo> rooms,
  ) async {
    final myId = _myId;
    final entries = await Future.wait(
      rooms.map((room) async {
        // Enriched entry: trust the list fields. An unread count
        // above zero with no last message is inconsistent, so fall
        // through to the per-room fetch for that room.
        final enriched =
            room.unreadCount != null &&
            (room.lastMessage != null || room.unreadCount == 0);
        if (enriched) {
          return MapEntry(
            room.roomId,
            RoomPreview(
              roomId: room.roomId,
              lastMessage: room.lastMessage,
              unreadCount: room.unreadCount ?? 0,
            ),
          );
        }
        try {
          final page = await listMessages(room.roomId);
          final msgs = page.messages;
          return MapEntry(
            room.roomId,
            RoomPreview(
              roomId: room.roomId,
              lastMessage: msgs.isEmpty ? null : msgs.last,
              unreadCount: countUnread(
                msgs,
                myId: myId,
                lastReadAt: _lastReadAt[room.roomId],
              ),
            ),
          );
        } catch (_) {
          return MapEntry(
            room.roomId,
            RoomPreview(roomId: room.roomId, lastMessage: null, unreadCount: 0),
          );
        }
      }),
    );
    final result = Map<String, RoomPreview>.fromEntries(entries);
    _previewCache = result;
    _previewCacheAt = DateTime.now();
    return result;
  }

  /// Total unread messages across all my rooms (for the dashboard
  /// badge). When the rooms list already carries `unread_count` for
  /// every room, no per-room fetch is needed at all. Throws
  /// [ApiException] like [listRooms] — callers that only show a
  /// badge should catch and hide it.
  Future<int> fetchTotalUnread() async {
    final rooms = await listRooms();
    if (rooms.isEmpty) return 0;
    if (rooms.every((r) => r.unreadCount != null)) {
      return rooms.fold<int>(0, (sum, r) => sum + (r.unreadCount ?? 0));
    }
    final previews = await fetchRoomPreviews(rooms);
    return previews.values.fold<int>(0, (sum, p) => sum + p.unreadCount);
  }

  /// Open a live WebSocket connection to a room. The caller should
  /// have done a REST call first (e.g. [listMessages]) so an expired
  /// access token is refreshed before the token is read here.
  Future<ChatRoomConnection> connectRoom(String roomId) async {
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('You are not logged in.');
    }
    final connection = ChatRoomConnection._(roomId, token);
    await connection._connect();
    return connection;
  }
}

/// A live WebSocket connection to one chat room.
///
/// Protocol (see backend `chat/consumers.py`):
/// - Connect: `wss://<host>/ws/chat/<room_id>/?token=<access JWT>`
///   (close codes: 4001 bad/expired token, 4003 not a member,
///   4004 room not found — though rejected sockets deliver NO close
///   frame live, just a TCP drop, so the client also treats a
///   frameless/null-code drop shortly after connect as auth-suspect).
/// - Send: `{"type": "chat.message", "content": "…",
///   "message_type": "text", "reply_to_id": "…", "reply_to_text": "…"}`
///   — the server persists the message and broadcasts it back to the
///   whole room, including the sender. `reply_to_*` are only sent
///   when replying.
/// - Receive: `{"type": "chat.message", "message": {…}}`.
/// - Read receipts: `{"type": "chat.read", "room_id": "…",
///   "reader_id": "…"}` — surfaced on [readReceipts].
/// - History: `{"type": "chat.history", "before": "<iso>|null"}` →
///   `{"type": "chat.history", "messages": […]}` (50 max).
/// - Errors: `{"type": "error", "code": "…", "detail": "…"}`.
///
/// Reconnect behaviour (true budget, after the fixes below): the
/// socket reconnects automatically with escalating delays (2s, 5s,
/// 10s, 20s, 30s, 30s, 30s — 127s of waiting plus handshake time).
/// Each failure burns exactly ONE attempt (the socket-closed handler
/// is deduped: the stream wires both onError and onDone to it).
/// After the budget is spent the connection enters
/// [ChatConnectionState.failed] and keeps retrying every 60s
/// indefinitely (long-tail) while the connection is alive, so it
/// never silently gives up; the banner stays visible until actually
/// connected. A manual [ChatRoomConnection.reconnect] (or
/// [handleAppResumed]) restarts the cycle immediately. On a 4001
/// close — or an auth-suspect drop — the access token is refreshed
/// through a REST call (capped at 10s) before the first retry; if
/// the server rejected the token AND the refresh fails, the session
/// is reported expired instead of burning the budget on a dead
/// token. The handshake is capped at 20s (a Render cold start can
/// otherwise hang silently forever), the socket sends a ping every
/// 30s so a half-open socket errors promptly, and every send has a
/// 15s echo timeout reported on [sendTimeouts]. The connection is
/// only reported as connected once the WebSocket handshake is
/// confirmed (via the channel's `ready` future or the first inbound
/// frame) — never optimistically — so sends during the handshake
/// window are refused (and trigger a reconnect) instead of being
/// lost.
class ChatRoomConnection {
  ChatRoomConnection._(this.roomId, String token) : _token = token;

  final String roomId;
  String _token;

  // Escalating retry delays; the list length is the attempt budget
  // (2+5+10+20+30+30+30 = 127s of waiting, ~2–3 min with handshakes).
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
  ];

  /// How long a handshake may hang (Render cold start) before the
  /// socket is treated as closed and a reconnect is scheduled.
  static const _handshakeTimeout = Duration(seconds: 20);

  /// How long a send may wait for its server echo before the send
  /// is reported failed on [sendTimeouts].
  static const _echoTimeout = Duration(seconds: 15);

  /// Long-tail retry interval after the escalating budget is spent.
  static const _longTailInterval = Duration(seconds: 60);

  /// How long the token refresh on the reconnect path may take.
  static const _refreshTimeout = Duration(seconds: 10);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _handshakeTimer;
  Timer? _longTailTimer;
  bool _closed = false;
  int _attempts = 0;

  /// Whether any frame arrived on the current socket, and when the
  /// current connect started — used to spot auth-suspect drops.
  bool _gotFrame = false;
  DateTime _connectStartedAt = DateTime.now();

  /// True when the last close was an explicit 4001 token rejection.
  bool _lastCloseWasAuthRejection = false;

  /// True when the server rejected the token and the refresh failed:
  /// the session is dead and retries must not burn the budget.
  bool _sessionExpired = false;

  /// Sends awaiting their server echo, oldest first.
  final List<({String id, String content, Timer timer})> _pendingSends = [];
  int _sendCounter = 0;

  final _messagesController = StreamController<ChatApiMessage>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _statesController = StreamController<ChatConnectionState>.broadcast();
  final _sendTimeoutsController = StreamController<String>.broadcast();
  final _readReceiptsController =
      StreamController<({String roomId, String readerId})>.broadcast();

  Completer<List<ChatApiMessage>>? _historyCompleter;

  /// Live incoming messages (including echoes of my own sends).
  Stream<ChatApiMessage> get messages => _messagesController.stream;

  /// Human-readable error frames and connection problems.
  Stream<String> get errors => _errorsController.stream;

  /// Connection lifecycle events.
  Stream<ChatConnectionState> get states => _statesController.stream;

  /// IDs of my sends whose server echo never arrived within
  /// [_echoTimeout] (half-open socket). The thread marks the
  /// matching optimistic message failed, with a tap-to-retry
  /// affordance.
  Stream<String> get sendTimeouts => _sendTimeoutsController.stream;

  /// Read receipts broadcast by the server when someone reads the
  /// room (`chat.read` frames).
  Stream<({String roomId, String readerId})> get readReceipts =>
      _readReceiptsController.stream;

  /// Latest lifecycle state (so a late subscriber can read it
  /// without waiting for the next event).
  ChatConnectionState _currentState = ChatConnectionState.connecting;
  ChatConnectionState get currentState => _currentState;

  /// True when the server rejected the token and the refresh failed.
  bool get sessionExpired => _sessionExpired;

  bool get isConnected => !_closed && _connected && _channel != null;

  bool _connected = false;

  Uri get _wsUri => Uri.parse(ChatService.wsBase)
      .replace(path: '/ws/chat/$roomId/', queryParameters: {'token': _token});

  Future<void> _connect() async {
    if (_closed) return;
    _emit(
      _attempts == 0
          ? ChatConnectionState.connecting
          : ChatConnectionState.reconnecting,
    );
    _gotFrame = false;
    _connectStartedAt = DateTime.now();
    WebSocketChannel channel;
    try {
      // IOWebSocketChannel (not the generic connect): `pingInterval`
      // makes a half-open socket error promptly instead of losing
      // messages silently, and `connectTimeout` caps the TCP-level
      // handshake wait (Render cold start).
      channel = IOWebSocketChannel.connect(
        _wsUri,
        pingInterval: const Duration(seconds: 30),
        connectTimeout: _handshakeTimeout,
      );
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _onData,
      onError: (_) => _onSocketClosed(),
      onDone: _onSocketClosed,
      cancelOnError: false,
    );
    // Handshake timeout: even with `connectTimeout`, the handshake
    // can hang silently (measured 30s+ with zero client events, no
    // banner, no retry). If neither `ready` nor a first frame
    // arrives in time, treat the socket as closed so the reconnect
    // loop runs.
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(_handshakeTimeout, () {
      if (_closed || _connected || !identical(_channel, channel)) return;
      // Drop the hanging channel WITHOUT awaiting its close — a
      // hanging sink.close() never completes — then run the normal
      // closed path so a reconnect is scheduled.
      unawaited(channel.sink.close().catchError((_) {}));
      _onSocketClosed();
    });
    // Do NOT mark the connection live yet: the handshake has not
    // completed. Confirm it via `ready` (or the first inbound frame,
    // see [_onData]) and only then reset the retry budget and report
    // `connected` — sends before that point would be lost.
    unawaited(
      channel.ready
          .then((_) {
            if (!_closed && identical(_channel, channel)) _markConnected();
          })
          .catchError((_) {
            // Handshake failed — onDone/onError reports it.
          }),
    );
  }

  /// The handshake completed (or the first frame arrived): the socket
  /// is genuinely open. Resets the retry budget — only here, never
  /// when the channel is merely created.
  void _markConnected() {
    if (_closed || _connected) return;
    _connected = true;
    _attempts = 0;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _longTailTimer?.cancel();
    _longTailTimer = null;
    _sessionExpired = false;
    _emit(ChatConnectionState.connected);
  }

  /// Reconnect now, resetting the retry budget. The access token is
  /// refreshed through a REST call first: a manual reconnect usually
  /// follows a token that expired mid-thread, and reconnecting with
  /// the same dead token just fails again. Safe to call while
  /// connecting/reconnecting or after [ChatConnectionState.failed];
  /// a no-op when already connected or closed.
  Future<void> reconnect() async {
    if (_closed || isConnected) return;
    _attempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _longTailTimer?.cancel();
    _longTailTimer = null;
    _sessionExpired = false;
    await _subscription?.cancel();
    _subscription = null;
    await _closeSink();
    _channel = null;
    _connected = false;
    await _refreshToken();
    if (_closed) return;
    await _connect();
  }

  /// Called when the app returns to the foreground: if the socket is
  /// down, start a fresh reconnect cycle now instead of waiting for
  /// the next scheduled attempt.
  void handleAppResumed() {
    if (_closed || isConnected || _sessionExpired) return;
    unawaited(reconnect());
  }

  /// Close the sink without ever hanging: `sink.close()` on a
  /// half-open channel may never complete, so cap the wait at 3s.
  /// Never bare-await `sink.close()` anywhere — a hanging close
  /// wedges [reconnect] and [close] forever.
  Future<void> _closeSink() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {
      // Already closed.
    }
  }

  /// Force a token refresh through the REST client, which refreshes
  /// on 401, then read the fresh token for the next handshake.
  /// Returns false when the refresh failed (or timed out, capped at
  /// [_refreshTimeout]) — the caller decides whether to reconnect
  /// with the old token or report the session expired.
  Future<bool> _refreshToken() async {
    try {
      await ChatService.instance
          .getRoom(roomId)
          .timeout(_refreshTimeout);
      final fresh = await TokenStorage.instance.accessToken;
      if (fresh != null && fresh.isNotEmpty) {
        _token = fresh;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _onData(dynamic data) {
    // Any inbound frame proves the handshake completed.
    _gotFrame = true;
    _markConnected();
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (frame['type'] as String?) {
      case 'chat.message':
        final raw = frame['message'];
        if (raw is Map<String, dynamic>) {
          final msg = ChatApiMessage.fromJson(raw);
          _ackEcho(msg);
          _messagesController.add(msg);
        }
      case 'chat.read':
        final roomId = frame['room_id'] as String?;
        final readerId = frame['reader_id']?.toString();
        if (roomId != null &&
            readerId != null &&
            !_readReceiptsController.isClosed) {
          _readReceiptsController.add((roomId: roomId, readerId: readerId));
        }
      case 'chat.history':
        final completer = _historyCompleter;
        _historyCompleter = null;
        if (completer != null && !completer.isCompleted) {
          final list =
              (frame['messages'] as List?)
                  ?.map(
                    (e) => ChatApiMessage.fromJson(e as Map<String, dynamic>),
                  )
                  .toList() ??
              const <ChatApiMessage>[];
          completer.complete(list);
        }
      case 'error':
        final detail = frame['detail'] as String?;
        if (detail != null && detail.isNotEmpty) {
          _errorsController.add(detail);
        }
    }
  }

  /// Cancel the echo-timeout timer for my oldest unacked send with
  /// matching content — the server echo proves it landed. Only
  /// echoes of my own messages ack a send.
  void _ackEcho(ChatApiMessage msg) {
    if (_pendingSends.isEmpty) return;
    final myId = ChatService.instance._myId;
    if (myId != null && msg.senderId != myId) return;
    for (var i = 0; i < _pendingSends.length; i++) {
      if (_pendingSends[i].content == msg.content) {
        _pendingSends.removeAt(i).timer.cancel();
        return;
      }
    }
  }

  void _onSocketClosed() {
    // DEDUPE: the stream wires BOTH onError and onDone to this
    // handler (with cancelOnError: false), so every failure fires
    // it twice. The first firing nulls [_channel]; a second firing
    // sees null and returns, so one failure burns one retry attempt
    // — not two — and cannot cancel the first firing's timer (which
    // would kill the promised token refresh).
    final channel = _channel;
    if (channel == null) return;
    int? code;
    try {
      code = channel.closeCode;
    } catch (_) {
      code = null;
    }
    final wasConnected = _connected;
    final gotFrame = _gotFrame;
    final sinceConnect = DateTime.now().difference(_connectStartedAt);
    _connected = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_closed) {
      _emit(ChatConnectionState.closed);
      return;
    }
    _lastCloseWasAuthRejection = code == 4001;
    if (code == 4003) {
      _errorsController.add('You are not a member of this chat.');
      _emit(ChatConnectionState.failed);
      return;
    }
    if (code == 4004) {
      _errorsController.add('This chat no longer exists.');
      _emit(ChatConnectionState.failed);
      return;
    }
    // Handshake failure: the backend may close pre-accept, so the
    // client gets an HTTP 403 and no close code is ever delivered —
    // the socket closed before it was ever connected. Live,
    // rejected sockets deliver NO close frame at all (101 then a
    // TCP drop at ~10–21s, no code), so the 4001/4003/4004 design
    // is dead live: treat an abnormal close (null/1006 code)
    // shortly after connect, or a connect that yielded no frames
    // before dropping, as auth-suspect and refresh the token before
    // the first retry — even when the socket had briefly been
    // connected (`wasConnected` is no longer proof of a good
    // token). A drop long after a healthy connect is a network
    // problem, not auth, so it does not refresh.
    final authSuspect =
        code == 4001 ||
        ((code == null || code == 1006) &&
            (!gotFrame ||
                sinceConnect < const Duration(seconds: 25) ||
                !wasConnected));
    _scheduleReconnect(
      refreshTokenFirst: authSuspect && _attempts == 0,
    );
  }

  void _scheduleReconnect({bool refreshTokenFirst = false}) {
    if (_closed) return;
    if (_attempts >= _retryDelays.length) {
      // Budget spent: cancel any pending timer first — the exhausted
      // branch used to emit `failed` without cancelling it, leaving
      // one zombie _connect ~30s later. The toast comes from the
      // thread's state listener ONLY — this branch must not also add
      // to the errors stream, or the user sees two identical toasts.
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _emit(ChatConnectionState.failed);
      _startLongTailRetry();
      return;
    }
    final delay = _retryDelays[_attempts];
    _attempts++;
    _emit(ChatConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_closed) return;
      if (refreshTokenFirst) {
        final ok = await _refreshToken();
        if (!ok && _lastCloseWasAuthRejection) {
          // The server rejected the token (4001) and the refresh
          // failed too — the session is dead. Say so honestly
          // instead of burning the budget on a known-dead token.
          // (A refresh failure after a merely auth-*suspect* close
          // may just be the network, so that path still retries
          // with the old token.)
          _sessionExpired = true;
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _emit(ChatConnectionState.failed);
          _errorsController.add(
            'Your session expired. Please log in again.',
          );
          return;
        }
      }
      if (!_closed) await _connect();
    });
  }

  /// Long-tail retry: after the escalating budget is spent, keep
  /// trying every 60s indefinitely while the connection is alive, so
  /// the chat never silently gives up. A tick skips while a
  /// reconnect cycle is already in progress (pending timer or live
  /// channel). Stops on connect, on manual reconnect, on close, and
  /// when the session is expired.
  void _startLongTailRetry() {
    if (_closed || _sessionExpired || _longTailTimer != null) return;
    _longTailTimer = Timer.periodic(_longTailInterval, (_) async {
      if (_closed ||
          _connected ||
          _sessionExpired ||
          _reconnectTimer != null ||
          _channel != null) {
        return;
      }
      _attempts = 0;
      await _connect();
    });
  }

  /// Send a text message. The server broadcasts it back to the room
  /// (including this client) — callers should render from the
  /// broadcast, not from this call. Returns a local send id: if the
  /// server echo never arrives within the echo timeout, the id is
  /// reported on [sendTimeouts] so the UI can mark the optimistic
  /// message failed. When replying, [replyToId] is the quoted
  /// message's server id and [replyToText] its snippet — both are
  /// sent in the frame so the other side renders the quote.
  Future<String> sendText(
    String content, {
    String messageType = 'text',
    String? replyToId,
    String? replyToText,
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw const ApiException('Message must not be empty.');
    }
    final channel = _channel;
    if (_closed || channel == null || !_connected) {
      // Reconnect-on-send: kick off a fresh attempt instead of
      // silently dropping the message, then refuse loudly so the
      // caller can queue the message and tell the user honestly.
      unawaited(reconnect());
      throw const ApiException(
        'Not connected. Your message will send when reconnected.',
      );
    }
    final frame = <String, dynamic>{
      'type': 'chat.message',
      'content': text,
      'message_type': messageType,
    };
    if (replyToId != null && replyToId.isNotEmpty) {
      frame['reply_to_id'] = replyToId;
    }
    if (replyToText != null && replyToText.isNotEmpty) {
      frame['reply_to_text'] = replyToText;
    }
    try {
      channel.sink.add(jsonEncode(frame));
    } catch (_) {
      throw const ApiException('Could not send the message. Please try again.');
    }
    // Echo timeout: a half-open socket accepts the send but the echo
    // never comes back — without this the optimistic bubble sits in
    // "sending" forever. The timeout is cancelled by [_ackEcho].
    final sendId =
        'send_${_sendCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    final timer = Timer(_echoTimeout, () {
      _pendingSends.removeWhere((p) => p.id == sendId);
      if (!_sendTimeoutsController.isClosed) {
        _sendTimeoutsController.add(sendId);
      }
    });
    _pendingSends.add((id: sendId, content: text, timer: timer));
    return sendId;
  }

  /// Ask the server for message history over the socket (50 max,
  /// oldest first). Prefer the REST [ChatService.listMessages] for
  /// the initial load — it refreshes an expired token for free.
  Future<List<ChatApiMessage>> requestHistory({String? before}) {
    final pending = _historyCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;
    final channel = _channel;
    if (_closed || channel == null || !_connected) {
      return Future.error(
        const ApiException('Not connected. Please try again.'),
      );
    }
    final completer = Completer<List<ChatApiMessage>>();
    _historyCompleter = completer;
    try {
      channel.sink.add(jsonEncode({'type': 'chat.history', 'before': before}));
    } catch (_) {
      _historyCompleter = null;
      return Future.error(
        const ApiException('Could not load history. Please try again.'),
      );
    }
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _historyCompleter = null;
        throw const ApiException(
          'Loading history timed out. Please try again.',
        );
      },
    );
  }

  void _emit(ChatConnectionState state) {
    _currentState = state;
    if (!_statesController.isClosed) _statesController.add(state);
  }

  /// Close the socket and release resources. No reconnect is
  /// attempted after this.
  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _handshakeTimer?.cancel();
    _longTailTimer?.cancel();
    for (final p in _pendingSends) {
      p.timer.cancel();
    }
    _pendingSends.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _closeSink();
    _channel = null;
    _historyCompleter = null;
    await _messagesController.close();
    await _errorsController.close();
    await _sendTimeoutsController.close();
    await _readReceiptsController.close();
    _emit(ChatConnectionState.closed);
    await _statesController.close();
  }
}
