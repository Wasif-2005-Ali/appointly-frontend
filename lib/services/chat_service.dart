import 'dart:async';
import 'dart:convert';

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

  const ChatRoomInfo({
    required this.roomId,
    required this.name,
    required this.participants,
    required this.isGroup,
    required this.createdAt,
  });

  factory ChatRoomInfo.fromJson(Map<String, dynamic> json) => ChatRoomInfo(
    roomId: json['room_id'] as String,
    name: json['name'] as String? ?? '',
    participants:
        (json['participants'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    isGroup: json['is_group'] as bool? ?? false,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.tryParse(json['created_at'] as String),
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
  });

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
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      fileName: json['file_name'] as String?,
      fileSize: rawSize is num ? rawSize.toInt() : null,
    );
  }

  /// One-line text for the inbox preview. Media messages carry a URL
  /// in [content], which must never leak into the preview. Pure.
  String get previewText {
    switch (messageType) {
      case 'image':
        return 'Photo';
      case 'file':
        return fileName != null && fileName!.isNotEmpty ? fileName! : 'File';
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
  /// backend has `Message.mark_read()` but never calls it, so `read_by`
  /// only ever contains the sender — without this, every message from
  /// someone else would look unread forever. Opening a thread stamps
  /// the room here ([markRoomReadLocally]); the unread count then only
  /// counts messages newer than the stamp. If the backend starts
  /// marking messages read, this stays harmless: `read_by` is checked
  /// first.
  final Map<String, DateTime> _lastReadAt = {};

  /// Remember that the user has seen this room's messages up to now.
  void markRoomReadLocally(String roomId) {
    _lastReadAt[roomId] = DateTime.now().toUtc();
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
  /// Rooms are fetched in parallel; a room that fails to load gets an
  /// empty preview instead of failing the whole inbox. The messages
  /// endpoint returns the 50 most recent messages, so the unread count
  /// is capped at 50 per room — fine for a small number of rooms.
  Future<Map<String, RoomPreview>> fetchRoomPreviews(
    List<ChatRoomInfo> rooms,
  ) async {
    final myId = _myId;
    final entries = await Future.wait(
      rooms.map((room) async {
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
    return Map.fromEntries(entries);
  }

  /// Total unread messages across all my rooms (for the dashboard
  /// badge). Throws [ApiException] like [listRooms] — callers that
  /// only show a badge should catch and hide it.
  Future<int> fetchTotalUnread() async {
    final rooms = await listRooms();
    if (rooms.isEmpty) return 0;
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
///   4004 room not found).
/// - Send: `{"type": "chat.message", "content": "…",
///   "message_type": "text"}` — the server persists the message and
///   broadcasts it back to the whole room, including the sender.
/// - Receive: `{"type": "chat.message", "message": {…}}`.
/// - History: `{"type": "chat.history", "before": "<iso>|null"}` →
///   `{"type": "chat.history", "messages": […]}` (50 max).
/// - Errors: `{"type": "error", "code": "…", "detail": "…"}`.
///
/// The connection reconnects automatically (up to 3 attempts) when
/// the socket drops unexpectedly; on a 4001 close it refreshes the
/// access token through a REST call first.
class ChatRoomConnection {
  ChatRoomConnection._(this.roomId, String token) : _token = token;

  final String roomId;
  String _token;

  static const _maxAttempts = 3;
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _closed = false;
  int _attempts = 0;

  final _messagesController = StreamController<ChatApiMessage>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _statesController = StreamController<ChatConnectionState>.broadcast();

  Completer<List<ChatApiMessage>>? _historyCompleter;

  /// Live incoming messages (including echoes of my own sends).
  Stream<ChatApiMessage> get messages => _messagesController.stream;

  /// Human-readable error frames and connection problems.
  Stream<String> get errors => _errorsController.stream;

  /// Connection lifecycle events.
  Stream<ChatConnectionState> get states => _statesController.stream;

  bool get isConnected => !_closed && _connected && _channel != null;

  bool _connected = false;

  Uri get _wsUri => Uri.parse(ChatService.wsBase)
      .replace(path: '/ws/chat/$roomId/', queryParameters: {'token': _token});

  Future<void> _connect() async {
    _emit(
      _attempts == 0
          ? ChatConnectionState.connecting
          : ChatConnectionState.reconnecting,
    );
    try {
      _channel = WebSocketChannel.connect(_wsUri);
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _subscription = _channel!.stream.listen(
      _onData,
      onError: (_) => _onSocketClosed(),
      onDone: _onSocketClosed,
      cancelOnError: false,
    );
    // web_socket_channel has no connect callback; the socket is
    // usable as soon as the channel exists. Treat it as connected
    // and let onDone/onError report real failures.
    _connected = true;
    _attempts = 0;
    _emit(ChatConnectionState.connected);
  }

  void _onData(dynamic data) {
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
          _messagesController.add(ChatApiMessage.fromJson(raw));
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

  void _onSocketClosed() {
    // Capture the close code before dropping the channel reference.
    final code = _lastCloseCode;
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_closed) {
      _emit(ChatConnectionState.closed);
      return;
    }
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
    _scheduleReconnect(refreshTokenFirst: code == 4001);
  }

  int? get _lastCloseCode {
    try {
      return _channel?.closeCode;
    } catch (_) {
      return null;
    }
  }

  void _scheduleReconnect({bool refreshTokenFirst = false}) {
    if (_closed) return;
    if (_attempts >= _maxAttempts) {
      _emit(ChatConnectionState.failed);
      _errorsController.add(
        'Live connection lost. Pull to refresh or reopen the chat.',
      );
      return;
    }
    final delay = _retryDelays[_attempts.clamp(0, _retryDelays.length - 1)];
    _attempts++;
    _emit(ChatConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_closed) return;
      if (refreshTokenFirst) {
        // Force a token refresh through the REST client, which
        // refreshes on 401, then read the fresh token.
        try {
          await ChatService.instance.getRoom(roomId);
          final fresh = await TokenStorage.instance.accessToken;
          if (fresh != null && fresh.isNotEmpty) _token = fresh;
        } catch (_) {
          // Refresh failed — reconnect with the old token; the
          // server will close with 4001 again and we give up after
          // the remaining attempts.
        }
      }
      if (!_closed) await _connect();
    });
  }

  /// Send a text message. The server broadcasts it back to the room
  /// (including this client) — callers should render from the
  /// broadcast, not from this call.
  Future<void> sendText(String content, {String messageType = 'text'}) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw const ApiException('Message must not be empty.');
    }
    final channel = _channel;
    if (_closed || channel == null || !_connected) {
      throw const ApiException(
        'Not connected. Please wait a moment and try again.',
      );
    }
    try {
      channel.sink.add(
        jsonEncode({
          'type': 'chat.message',
          'content': text,
          'message_type': messageType,
        }),
      );
    } catch (_) {
      throw const ApiException('Could not send the message. Please try again.');
    }
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
    if (!_statesController.isClosed) _statesController.add(state);
  }

  /// Close the socket and release resources. No reconnect is
  /// attempted after this.
  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Already closed.
    }
    _channel = null;
    _historyCompleter = null;
    await _messagesController.close();
    await _errorsController.close();
    _emit(ChatConnectionState.closed);
    await _statesController.close();
  }
}
