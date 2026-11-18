import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../models/appointment.dart';
import '../../screens/appointment_detail_screen.dart';
import '../../screens/call_screen.dart';
import '../../services/api_client.dart';
import '../../services/appointment_service.dart';
import '../../services/chat_service.dart';
import '../../user_session.dart';
import '../data/chat_db.dart';
import '../models/chat_models.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/chat_misc_widgets.dart';
import '../widgets/chat_popup_menus.dart';
import 'chat_search_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT THREAD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ChatThreadScreen extends StatefulWidget {
  final ChatConversation conversation;
  final List<ChatConversation> allConversations;

  const ChatThreadScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _msgCtrl    = TextEditingController();
  final ScrollController      _scrollCtrl = ScrollController();
  final List<ChatMessage>     _msgs       = [];

  bool _typing = false, _showEmoji = false;
  bool _recording = false;
  ChatMessage? _replyTo;

  // ── Live chat state ────────────────────────────────────────────────────────
  ChatRoomConnection? _connection;
  StreamSubscription? _msgSub, _errSub, _stateSub, _timeoutSub, _readSub;
  bool _loadingHistory = true;
  bool _wsLive = false;
  String? _loadError;
  // Server message IDs already shown (dedupe for the send echo).
  final Set<String> _seenIds = {};
  // Optimistic copies of my sends, replaced when the echo arrives.
  final List<ChatMessage> _pending = [];
  // Outgoing queue: sends made while disconnected wait here and
  // flush IN ORDER on reconnect — never dropped, never lost.
  final List<_QueuedSend> _outgoingQueue = [];
  // IDs of optimistic messages still queued (not yet sent): shown
  // with a clock + "sending…" state.
  final Set<String> _queuedIds = {};
  // sendText() send ids → optimistic message, for echo timeouts.
  final Map<String, ChatMessage> _sendIds = {};
  // Latest connection state (drives the honest banner) + in-flight
  // guard so rapid taps can't launch concurrent connectRoom()s.
  ChatConnectionState _connState = ChatConnectionState.connecting;
  bool _connectingLive = false;
  // Debounced mark-as-read for incoming live messages.
  Timer? _markReadTimer;
  // Message ids already entrance-animated (history never animates).
  final Set<String> _animatedIds = {};
  // Keys per message for jump-to-message from search.
  final Map<String, GlobalKey> _msgKeys = {};
  // Message id highlighted after a search jump.
  String? _highlightId;
  // Recording seconds, scoped to the overlay (not a full rebuild).
  final ValueNotifier<int> _recSecondsNotifier = ValueNotifier<int>(0);
  // Media upload in progress (photo/file). While true, a sending
  // indicator shows above the input bar.
  bool _uploadingMedia = false;
  String _uploadingLabel = '';
  // Pagination cursor from the last history page (`?before=`); null
  // when there is no older history left to load.
  String? _nextBefore;
  bool _loadingOlder = false;
  // Real voice-note recorder (see [_startRecording]).
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;

  late AnimationController _sendCtrl, _recCtrl;
  int _emojiTab    = 0;
  int _recSeconds  = 0;
  Timer? _recTimer;

  String get _convId => widget.conversation.id;

  /// Every other member of the room (for the group-read rule: a
  /// message is read only once ALL of them read it).
  List<String> get _otherMemberIds {
    final myId = UserSession.instance.userId?.toString();
    return widget.conversation.participantIds
        .where((id) => id != myId)
        .toList();
  }

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? "AM" : "PM"}';
  }

  String _mkId() => '${DateTime.now().millisecondsSinceEpoch}${_msgs.length}';

  // ── Theme helpers ──────────────────────────────────────────────────────────
  Color get _bg        => AppStateProvider.of(context).bg;
  Color get _cardBg    => AppStateProvider.of(context).cardBg;
  Color get _border    => AppStateProvider.of(context).border;
  Color get _txtMain   => AppStateProvider.of(context).txtMain;
  Color get _txtSub    => AppStateProvider.of(context).txtSub;
  Color get _accent    => AppStateProvider.of(context).accent;
  List<Color> get _btnGrad  => AppStateProvider.of(context).btnGradient;
  Color get _btnShadow      => AppStateProvider.of(context).btnShadow;
  List<Color> get _hero     => AppStateProvider.of(context).heroGradient;

  @override
  void initState() {
    super.initState();
    _sendCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    // The recording pulse runs ONLY while recording (started in
    // [_startRecording]) — repeating from initState rebuilt the mic
    // button every tick for the whole thread lifetime.
    _recCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _initMessages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reconnect on app resume: a socket dropped while backgrounded
    // should come back now, not on the next 60s long-tail tick.
    if (state == AppLifecycleState.resumed) {
      final conn = _connection;
      if (conn == null) {
        _connectLive();
      } else {
        conn.handleAppResumed();
      }
    }
  }

  /// Scrolled to the top: page in older history (see [_loadOlder]).
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels <=
        _scrollCtrl.position.minScrollExtent + 60) {
      _loadOlder();
    }
  }

  /// Load the next older page of history via `?before=` and prepend
  /// it, keeping the scroll position where the user was. No-op when
  /// there is no older history or a page is already loading.
  Future<void> _loadOlder() async {
    final before = _nextBefore;
    if (before == null || _loadingOlder || _loadingHistory) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await ChatService.instance.listMessages(
        _convId,
        before: before,
      );
      if (!mounted) return;
      final myId = UserSession.instance.userId?.toString();
      final older = page.messages
          .map(
            (m) => ChatMessage.fromApi(
              m,
              currentUserId: myId,
              otherMemberIds: _otherMemberIds,
            ),
          )
          .where((m) => !_seenIds.contains(m.id))
          .toList();
      // Snapshot the scroll geometry before prepending so the view
      // stays on the same message afterwards.
      final oldExtent = _scrollCtrl.hasClients
          ? _scrollCtrl.position.maxScrollExtent
          : 0.0;
      final oldOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
      setState(() {
        _msgs.insertAll(0, older);
        _seenIds.addAll(older.map((m) => m.id));
        // History never entrance-animates.
        _animatedIds.addAll(older.map((m) => m.id));
        _nextBefore = page.nextBefore;
        _loadingOlder = false;
      });
      ChatDB.saveAll(_convId, older).catchError((_) {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final newExtent = _scrollCtrl.position.maxScrollExtent;
        _scrollCtrl.jumpTo(
          (newExtent - oldExtent + oldOffset).clamp(0.0, newExtent),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      _toast(e.message);
    }
  }

  Future<void> _initMessages() async {
    final myId = UserSession.instance.userId?.toString();
    try {
      // REST first: it also refreshes an expired access token, which
      // the WebSocket connection then reuses.
      final page = await ChatService.instance.listMessages(_convId);
      if (!mounted) return;
      final apiMsgs = page.messages
          .map(
            (m) => ChatMessage.fromApi(
              m,
              currentUserId: myId,
              otherMemberIds: _otherMemberIds,
            ),
          )
          .toList();
      setState(() {
        _msgs.addAll(apiMsgs);
        _seenIds.addAll(apiMsgs.map((m) => m.id));
        // History never entrance-animates.
        _animatedIds.addAll(apiMsgs.map((m) => m.id));
        _nextBefore = page.nextBefore;
        _loadingHistory = false;
      });
      // Fill in the inbox tile preview from the latest message.
      if (apiMsgs.isNotEmpty) {
        widget.conversation.lastMsg = apiMsgs.last.previewText;
        widget.conversation.time = apiMsgs.last.time;
      }
      // Heal the cache: upsert the server messages and drop stale
      // orphan undated rows (see ChatDB.syncRoom) so a pre-v3 row
      // with createdAt NULL can't live forever under the wrong day.
      ChatDB.syncRoom(_convId, apiMsgs).catchError((_) {});
      // Mark the room read server-side so the unread badge stays
      // cleared across devices and app restarts (best-effort).
      await ChatService.instance.markRoomRead(_convId);
      _connectLive();
    } on ApiException catch (e) {
      // Offline fallback: show locally cached messages.
      List<ChatMessage> saved = [];
      try {
        saved = await ChatDB.load(_convId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _msgs.addAll(saved);
        _seenIds.addAll(saved.map((m) => m.id));
        _animatedIds.addAll(saved.map((m) => m.id));
        _loadingHistory = false;
        _loadError = saved.isEmpty ? e.message : null;
      });
      if (saved.isNotEmpty) {
        _toast('Offline — showing saved messages.');
        _connectLive();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
  }

  /// Open the live WebSocket connection for this room.
  Future<void> _connectLive() async {
    // In-flight guard: without it, rapid taps launch multiple
    // concurrent connectRoom()s that leak connections, timers and
    // subscriptions.
    if (_connectingLive) return;
    _connectingLive = true;
    try {
      // Cancel the old subscriptions and close the old connection
      // BEFORE replacing them.
      await _msgSub?.cancel();
      await _errSub?.cancel();
      await _stateSub?.cancel();
      await _timeoutSub?.cancel();
      await _readSub?.cancel();
      _msgSub = _errSub = _stateSub = _timeoutSub = _readSub = null;
      final old = _connection;
      _connection = null;
      await old?.close();
      ChatRoomConnection connection;
      try {
        connection = await ChatService.instance.connectRoom(_convId);
      } catch (e) {
        // The connection never opened, so no state event will ever
        // fire — set the failed state here or the reconnect banner
        // never shows and the user has no way to retry. Catch
        // broadly: anything the connect throws (not just
        // ApiException) must land here.
        if (mounted) {
          setState(() => _connState = ChatConnectionState.failed);
          _toast(
            '${e is ApiException ? e.message : 'Could not connect.'} '
            'Live updates are off.',
          );
        }
        return;
      }
      // Mounted check after the await: a post-dispose connection
      // would never be closed.
      if (!mounted) {
        await connection.close();
        return;
      }
      _connection = connection;
      _msgSub = connection.messages.listen(_onLiveMessage);
      _errSub = connection.errors.listen((e) {
        if (mounted) _toast(e);
      });
      _stateSub = connection.states.listen((s) {
        if (!mounted) return;
        setState(() {
          _connState = s;
          _wsLive = s == ChatConnectionState.connected;
        });
        if (s == ChatConnectionState.connected) {
          _flushQueue();
        } else if (s == ChatConnectionState.failed) {
          // Single toast for the failed transition — the service
          // deliberately emits no errors-stream toast here, or the
          // user sees two identical toasts. The text is honest: it
          // does not claim "reconnecting" when the budget is spent
          // (the long-tail retry still runs in the background).
          _toast('Not connected. Tap to retry.');
        }
      });
      _timeoutSub = connection.sendTimeouts.listen(_onSendTimeout);
      _readSub = connection.readReceipts.listen(_onReadReceipt);
      // The connection may already be connected (fast handshake) —
      // sync the banner state now.
      if (mounted) {
        setState(() => _connState = connection.currentState);
      }
    } finally {
      _connectingLive = false;
    }
  }

  /// Manual reconnect from the "Not connected" banner. Reuses the
  /// live connection when there is one; otherwise opens a fresh one.
  /// The banner only hides on `connected` (see the state listener)
  /// — never before the attempt completes.
  Future<void> _reconnectLive() async {
    final conn = _connection;
    if (conn == null) {
      await _connectLive();
      return;
    }
    await conn.reconnect();
  }

  /// Start a real reconnect attempt from a send path: open a fresh
  /// connection when there is none, otherwise reuse the live one.
  /// (Calling `reconnect()` on a null connection is a no-op, so the
  /// old `unawaited(_connection?.reconnect())` silently did nothing
  /// after a failed initial connect.)
  void _kickReconnect() {
    final conn = _connection;
    if (conn == null) {
      unawaited(_connectLive());
    } else {
      unawaited(conn.reconnect());
    }
  }

  /// A message arrived over the WebSocket (from the other side, or the
  /// server echo of my own send).
  void _onLiveMessage(ChatApiMessage apiMsg) {
    if (_seenIds.contains(apiMsg.id)) return;
    final myId = UserSession.instance.userId?.toString();
    final msg = ChatMessage.fromApi(
      apiMsg,
      currentUserId: myId,
      otherMemberIds: _otherMemberIds,
    );
    ChatMessage? toSave;
    String? deleteId;
    setState(() {
      _seenIds.add(apiMsg.id);
      if (msg.fromMe) {
        // Replace my optimistic copy (same text, still pending).
        final idx = _msgs.indexWhere(
          (m) => _pending.contains(m) && m.text == msg.text,
        );
        if (idx >= 0) {
          final old = _msgs[idx];
          _pending.remove(old);
          _queuedIds.remove(old.id);
          // Keep the local rendering (e.g. big emoji) of my message,
          // and the local-only forward flag — the echo would drop
          // them. Prefer the SERVER reply quote when the broadcast
          // carried one; fall back to the local quote.
          _msgs[idx] = ChatMessage(
            id: msg.id,
            text: msg.text,
            fromMe: true,
            time: msg.time,
            createdAt: msg.createdAt,
            type: old.type,
            status: MessageStatus.delivered,
            replyTo: msg.replyTo ?? old.replyTo,
            isForwarded: old.isForwarded,
          );
          toSave = _msgs[idx];
          // The optimistic row (local id) must not survive: the echo
          // saves under the server id, and the stale row would
          // resurface as a duplicate on cache fallback.
          deleteId = old.id;
          return;
        }
      }
      _msgs.add(msg);
      widget.conversation.lastMsg = msg.previewText;
      widget.conversation.time = msg.time;
      toSave = msg;
      if (!msg.fromMe) _scheduleMarkRead();
    });
    if (deleteId != null) ChatDB.delete(deleteId!).catchError((_) {});
    if (toSave != null) ChatDB.save(_convId, toSave!).catchError((_) {});
    _scrollDown();
  }

  /// Mark the room read server-side for incoming live messages
  /// (debounced 2s) — previously only the initial load marked the
  /// room read, so messages arriving in an open thread stayed unread
  /// server-side until the thread was reopened.
  void _scheduleMarkRead() {
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(seconds: 2), () {
      ChatService.instance.markRoomReadLocally(_convId);
      unawaited(ChatService.instance.markRoomRead(_convId));
    });
  }

  /// A send's server echo never arrived (half-open socket): mark the
  /// optimistic message failed — tapping it retries — instead of
  /// leaving it "sending" forever.
  void _onSendTimeout(String sendId) {
    final msg = _sendIds.remove(sendId);
    if (msg == null || !mounted) return;
    setState(() {
      _pending.remove(msg);
      msg.sendFailed = true;
    });
  }

  /// A `chat.read` broadcast: when the PEER read the room, flip my
  /// own messages to read. My own receipts are ignored. Groups need
  /// ALL members to read (see ChatMessage.fromApi), so a single
  /// reader's receipt only flips ticks in 1:1 rooms; in groups the
  /// ticks update on the next REST load via read_by.
  void _onReadReceipt(({String roomId, String readerId}) receipt) {
    if (receipt.roomId != _convId) return;
    final myId = UserSession.instance.userId?.toString();
    if (receipt.readerId == myId) return;
    if (_otherMemberIds.length != 1) return;
    if (!mounted) return;
    var changed = false;
    for (final m in _msgs) {
      if (m.fromMe && m.status != MessageStatus.read) {
        m.status = MessageStatus.read;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() {});
    for (final m in _msgs.where((m) => m.fromMe)) {
      ChatDB.update(_convId, m).catchError((_) {});
    }
  }

  /// Flush the outgoing queue IN ORDER now that the socket is live.
  /// Stops at the first failure — the rest stay queued for the next
  /// reconnect.
  Future<void> _flushQueue() async {
    if (_outgoingQueue.isEmpty) return;
    final conn = _connection;
    if (conn == null || !_wsLive) return;
    while (_outgoingQueue.isNotEmpty) {
      if (!mounted) return;
      final item = _outgoingQueue.first;
      final msg = item.message;
      try {
        final sendId = await conn.sendText(
          msg.text,
          replyToId: item.replyToId,
          replyToText: item.replyToText,
        );
        _sendIds[sendId] = msg;
        setState(() {
          _outgoingQueue.removeAt(0);
          _queuedIds.remove(msg.id);
          _pending.add(msg);
        });
      } on ApiException {
        return; // Stays queued; the next reconnect flushes again.
      }
    }
  }

  /// Enqueue an outgoing message while disconnected: the optimistic
  /// bubble shows immediately with a "sending…" clock, and the send
  /// flushes in order on reconnect. Also kicks off a reconnect.
  void _enqueue(
    ChatMessage msg, {
    String? replyToId,
    String? replyToText,
  }) {
    setState(() {
      if (!_msgs.contains(msg)) _msgs.add(msg);
      _queuedIds.add(msg.id);
      _outgoingQueue.add(
        _QueuedSend(
          message: msg,
          replyToId: replyToId,
          replyToText: replyToText,
        ),
      );
    });
    _scrollDown();
    _kickReconnect();
    _toast('Not connected — message queued, will send on reconnect.');
  }

  /// Retry a failed send (tap the failed bubble). The message goes
  /// back to pending — or back to the queue when still offline.
  Future<void> _retrySend(ChatMessage msg) async {
    if (!msg.sendFailed) return;
    setState(() => msg.sendFailed = false);
    if (_connection == null || !_wsLive) {
      _enqueue(msg);
      return;
    }
    setState(() => _pending.add(msg));
    try {
      final sendId = await _connection!.sendText(msg.text);
      _sendIds[sendId] = msg;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pending.remove(msg);
        msg.sendFailed = true;
      });
      _toast(e.message);
    }
  }

  /// The quoted message's SERVER id, or null when it has none yet
  /// (a local optimistic id is digits-only; server ids are 24-hex).
  /// Replies to not-yet-echoed messages still send the text snippet,
  /// just without the id.
  String? _serverIdOf(ChatMessage? quoted) {
    final id = quoted?.id;
    if (id == null) return null;
    if (RegExp(r'^[0-9a-f]{24}$').hasMatch(id)) return id;
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _errSub?.cancel();
    _stateSub?.cancel();
    _timeoutSub?.cancel();
    _readSub?.cancel();
    _markReadTimer?.cancel();
    _connection?.close();
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _sendCtrl.dispose(); _recCtrl.dispose();
    _recTimer?.cancel();
    _recSecondsNotifier.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  // ── Message sending ────────────────────────────────────────────────────────
  // Sends go over the WebSocket; the server broadcasts the saved message
  // back to the room (including us) and [_onLiveMessage] renders it. The
  // message below is optimistic — it is replaced by the server echo.
  // Replies travel in the frame (reply_to_id / reply_to_text) and the
  // echo carries the server quote back; the local quote is the fallback.
  // Sends made while disconnected are QUEUED ([_enqueue]) and flush in
  // order on reconnect — never dropped.
  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyTo;
    final replyId = _serverIdOf(replyTo);
    final replyText = replyTo?.previewText;
    _sendCtrl.forward().then((_) => _sendCtrl.reverse());
    final msg = ChatMessage(
      id: _mkId(), text: text, fromMe: true,
      time: _fmt(DateTime.now()), createdAt: DateTime.now(),
      type: MessageType.text,
      replyTo: replyTo, status: MessageStatus.sent,
    );
    if (_connection == null || !_wsLive) {
      // Queue it — the typed text lives on in the queued bubble.
      setState(() { _msgCtrl.clear(); _typing = false; _showEmoji = false; _replyTo = null; });
      _enqueue(msg, replyToId: replyId, replyToText: replyText);
      return;
    }
    setState(() { _msgs.add(msg); _pending.add(msg); _msgCtrl.clear(); _typing = false; _showEmoji = false; _replyTo = null; });
    _scrollDown();
    try {
      final sendId = await _connection!.sendText(
        text,
        replyToId: replyId,
        replyToText: replyText,
      );
      _sendIds[sendId] = msg;
    } on ApiException catch (e) {
      if (!mounted) return;
      // Restore the typed text — the input was already cleared, and
      // on the race path the message must not just vanish.
      setState(() {
        _msgs.remove(msg);
        _pending.remove(msg);
        _msgCtrl.text = text;
        _typing = true;
      });
      _toast(e.message);
    }
  }

  Future<void> _sendEmoji(String e) async {
    RecentEmojis.record(e);
    final msg = ChatMessage(id: _mkId(), text: e, fromMe: true, time: _fmt(DateTime.now()), createdAt: DateTime.now(), type: MessageType.emoji);
    if (_connection == null || !_wsLive) {
      setState(() => _showEmoji = false);
      _enqueue(msg);
      return;
    }
    setState(() { _msgs.add(msg); _pending.add(msg); _showEmoji = false; });
    _scrollDown();
    try {
      // Emoji travel as plain text; the server has no emoji type.
      final sendId = await _connection!.sendText(e);
      _sendIds[sendId] = msg;
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() { _msgs.remove(msg); _pending.remove(msg); });
      _toast(err.message);
    }
  }

  // ── Voice notes (real recording) ─────────────────────────────────────────
  // The mic records real audio (AAC .m4a) and uploads it via the same
  // media endpoint as photos/files, so the other side receives it as
  // a file message. Nothing is simulated.
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone permission is needed to record a voice note.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordingPath = path;
      _recSeconds = 0;
      _recSecondsNotifier.value = 0;
      _recCtrl.repeat(reverse: true);
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        // Scoped to the overlay via the notifier — no full-screen
        // setState every second.
        _recSeconds++;
        _recSecondsNotifier.value = _recSeconds;
      });
      setState(() => _recording = true);
    } catch (_) {
      _toast('Could not start recording. Please try again.');
    }
  }

  /// Stop the recorder. When [send] is true, upload the recording as
  /// a voice-note file message; otherwise discard it.
  Future<void> _finishRecording({required bool send}) async {
    _recTimer?.cancel();
    _recCtrl.stop();
    _recCtrl.reset();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final duration = _recSeconds;
    final filePath = path ?? _recordingPath;
    _recordingPath = null;
    setState(() {
      _recording = false;
      _recSeconds = 0;
    });
    if (filePath == null) return;
    if (!send || duration < 1) {
      if (!send) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      } else {
        _toast('Voice note too short.');
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
      return;
    }
    try {
      final bytes = await File(filePath).readAsBytes();
      if (!mounted) return;
      await _sendMedia(
        bytes: bytes,
        fileName:
            'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
        label: 'Sending voice note…',
      );
    } catch (_) {
      if (mounted) _toast('Could not send the voice note. Please try again.');
    } finally {
      try {
        await File(filePath).delete();
      } catch (_) {}
    }
  }

  /// Share a real appointment: sends its details as a text message
  /// over the WebSocket, so the other side actually receives it.
  /// The appointment id is embedded (`📅 Appointment [id]: …`) so
  /// [ChatMessage.fromApi] can render it as a card whose "View
  /// Appointment" button opens the real appointment. While
  /// disconnected the card is queued like any other send.
  Future<void> _shareAppointment(Appointment appt) async {
    final date = DateFormat('EEEE, MMM d').format(appt.dateTime);
    final time = DateFormat('h:mm a').format(appt.dateTime);
    final idPart = appt.id != null ? ' [${appt.id}]' : '';
    final text =
        '📅 Appointment$idPart: ${appt.name} — ${appt.service}\n'
        '$date at $time • ${appt.status.name}';
    final card = ChatMessage(
      id: _mkId(),
      text: text,
      fromMe: true,
      time: _fmt(DateTime.now()),
      createdAt: DateTime.now(),
      type: MessageType.appointment,
      appointmentId: appt.id,
      appointmentTitle: appt.name,
      appointmentDate: date,
      appointmentTime: time,
      status: MessageStatus.sent,
    );
    if (_connection == null || !_wsLive) {
      _enqueue(card);
      return;
    }
    setState(() {
      _msgs.add(card);
      _pending.add(card);
    });
    _scrollDown();
    try {
      final sendId = await _connection!.sendText(text);
      _sendIds[sendId] = card;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.remove(card);
        _pending.remove(card);
      });
      _toast(e.message);
    }
  }

  // ── Media sending ────────────────────────────────────────────────────────
  // Photos and files upload over REST (POST …/media/); the created
  // message comes back in the response and is rendered from it. The
  // server may also broadcast it over the WebSocket — the id is
  // recorded in _seenIds so the echo is dropped. On failure nothing
  // is added to the list, only a snackbar.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      await _sendMedia(bytes: bytes, fileName: picked.name);
    } catch (_) {
      if (mounted) _toast('Could not pick the photo. Please try again.');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final List<int> bytes;
      if (picked.bytes != null) {
        // Web (or withData): bytes come with the result.
        bytes = picked.bytes!;
      } else if (picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      } else {
        return;
      }
      if (!mounted) return;
      await _sendMedia(bytes: bytes, fileName: picked.name);
    } catch (_) {
      if (mounted) _toast('Could not read the file. Please try again.');
    }
  }

  Future<void> _sendMedia({
    required List<int> bytes,
    required String fileName,
    String? label,
  }) async {
    if (_uploadingMedia) return;
    final isImage = ChatService.isImageFile(fileName);
    setState(() {
      _uploadingMedia = true;
      _uploadingLabel =
          label ?? (isImage ? 'Sending photo…' : 'Sending file…');
    });
    try {
      final apiMsg = await ChatService.instance.uploadMedia(
        _convId,
        bytes: bytes,
        fileName: fileName,
      );
      if (!mounted) return;
      final myId = UserSession.instance.userId?.toString();
      final msg = ChatMessage.fromApi(
        apiMsg,
        currentUserId: myId,
        otherMemberIds: _otherMemberIds,
      );
      setState(() {
        _seenIds.add(apiMsg.id);
        _msgs.add(msg);
        widget.conversation.lastMsg = msg.previewText;
        widget.conversation.time = msg.time;
      });
      ChatDB.save(_convId, msg).catchError((_) {});
      _scrollDown();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  /// Open a file message's URL in the browser / external app.
  Future<void> _openFileUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('Could not open the file.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Could not open the file.');
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 80), () {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  });

  // ── Reaction logic ─────────────────────────────────────────────────────────
  void _react(ChatMessage msg, String emoji) {
    setState(() {
      if (msg.myReaction == emoji) {
        final cnt = (msg.reactions[emoji] ?? 1) - 1;
        if (cnt <= 0) msg.reactions.remove(emoji); else msg.reactions[emoji] = cnt;
        msg.myReaction = null;
      } else {
        if (msg.myReaction != null) {
          final old = msg.myReaction!;
          final cnt = (msg.reactions[old] ?? 1) - 1;
          if (cnt <= 0) msg.reactions.remove(old); else msg.reactions[old] = cnt;
        }
        msg.reactions[emoji] = (msg.reactions[emoji] ?? 0) + 1;
        msg.myReaction = emoji;
      }
    });
    ChatDB.update(_convId, msg).catchError((_) {});
    Navigator.pop(context);
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    AppStateProvider.of(context);
    final c = widget.conversation;
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        _buildHeader(c),
        if (_connState != ChatConnectionState.connected) _connectionBanner(),
        if (_loadError != null && _msgs.isEmpty)
          Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.cloud_off_rounded, size: 52, color: _txtSub.withOpacity(0.4)),
              const SizedBox(height: 14),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 14, color: _txtSub)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loadingHistory = true;
                    _loadError = null;
                  });
                  _initMessages();
                },
                child: const Text('Try again'),
              ),
            ]),
          )))
        else if (_loadingHistory)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: DotBackgroundPainter(_accent.withOpacity(0.025)))),
            ListView.builder(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            // Keep a screenful of bubbles on either side built so
            // scrolling through media-heavy history stays smooth.
            cacheExtent: 500,
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final msg = _msgs[i];
              final key = _msgKeys.putIfAbsent(msg.id, () => GlobalKey());
              return Container(
                key: key,
                decoration: _highlightId == msg.id
                    ? BoxDecoration(
                        color: _accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Column(children: [
                  if (_showDateSeparator(i)) _dateSep(_dateLabelForIndex(i)),
                  SwipeableMessage(onReply: () => setState(() => _replyTo = msg), child: _bubble(msg, c, i)),
                ]),
              );
            },
          ),
          if (_loadingOlder)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border),
                  ),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _accent,
                    ),
                  ),
                ),
              ),
            ),
        ])),
        if (_replyTo != null) _replyBar(),
        if (_recording) _recordingOverlay(),
        if (_showEmoji) _emojiKeyboard(),
        if (_uploadingMedia) _uploadingBar(),
        if (!_recording) _inputBar(c),
      ]),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(ChatConversation c) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _hero, stops: const [0.0, 0.35, 0.7, 1.0]),
    ),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
      child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 38, height: 38,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.22))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16))),
        const SizedBox(width: 8),
        Stack(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                  border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
                  boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
              child: Center(child: Text(c.initials,
                  style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)))),
        ]),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(c.service, style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w500)),
        ])),
        // Video call — starts a real call with the other party.
        GestureDetector(onTap: () => _startCall('video'),
            child: Container(width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 17))),
        // Voice call — starts a real call with the other party.
        GestureDetector(onTap: () => _startCall('audio'),
            child: Container(width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: const Icon(Icons.phone_rounded, color: Colors.white, size: 17))),
        ThreadPopupMenu(accent: _accent, cardBg: _cardBg, border: _border, txtMain: _txtMain, onSelect: (v) {
          switch (v) {
            case 'search':    _openSearch(); break;
            case 'mute':
              setState(() => c.isMuted = !c.isMuted);
              ChatDB.saveConversationFlags(
                c.id,
                pinned: c.isPinned,
                muted: c.isMuted,
                archived: c.isArchived,
              ).catchError((_) {});
              _toast(c.isMuted ? 'Muted' : 'Unmuted');
              break;
            case 'starred':   _showStarred(); break;
            case 'clear':     _clearChat(); break;
          }
        }),
      ]),
    )),
  );

  // ── Honest connection-state banner ───────────────────────────────────────
  // Slim banner distinguishing connecting / reconnecting / failed /
  // closed — visible until actually connected, never hidden early.
  Widget _connectionBanner() {
    final failed = _connState == ChatConnectionState.failed;
    final label = switch (_connState) {
      ChatConnectionState.connecting => 'Connecting…',
      ChatConnectionState.reconnecting => 'Reconnecting…',
      ChatConnectionState.failed => 'Not connected',
      ChatConnectionState.closed => 'Connection closed',
      ChatConnectionState.connected => '',
    };
    return Container(
      width: double.infinity,
      color: failed
          ? const Color(0xFFE05C5C).withOpacity(0.12)
          : _cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        if (failed)
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFE05C5C), size: 18)
        else
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _txtSub),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: failed ? const Color(0xFFE05C5C) : _txtSub,
            ),
          ),
        ),
        if (failed)
          TextButton(
            onPressed: _reconnectLive,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Tap to retry',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFE05C5C),
              ),
            ),
          ),
      ]),
    );
  }

  /// Start a real call with the other party in this chat (same flow
  /// as the New Call screen). Group chats and rooms with no known
  /// peer have no single callee, so they toast honestly instead.
  Future<void> _startCall(String callType) async {
    final myId = UserSession.instance.userId?.toString();
    final peerId = widget.conversation.participantIds
        .firstWhere((id) => id != myId, orElse: () => '');
    if (peerId.isEmpty) {
      _toast('Calls are only available in direct chats.');
      return;
    }
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen.outgoing(
          calleeId: peerId,
          calleeName: widget.conversation.name,
          callType: callType,
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) _toast(result);
  }

  // ── Date separator ─────────────────────────────────────────────────────────
  /// A separator goes above the first message and above the first
  /// message of each new (effective) day. Messages without a known
  /// date take their nearest dated neighbour's date (see
  /// [DateSeparators]) — they never silently merge into the previous
  /// day's group.
  bool _showDateSeparator(int i) {
    return DateSeparators.showSeparator(
      _msgs.map((m) => m.createdAt).toList(),
      i,
    );
  }

  /// Label for the separator above message [i]: its effective date.
  String _dateLabelForIndex(int i) {
    final effective = DateSeparators.effectiveDate(
      _msgs.map((m) => m.createdAt).toList(),
      i,
    );
    if (effective == null) return 'Messages';
    return _dateLabel(effective);
  }

  /// "Today" / "Yesterday" / "Nov 18, 2026" for a separator.
  String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(local);
  }

  Widget _dateSep(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Expanded(child: Divider(color: _border, height: 1)),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border, width: 1)),
          child: Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: _txtSub))),
      Expanded(child: Divider(color: _border, height: 1)),
    ]),
  );

  /// True the first time a message is built (live arrivals only —
  /// history ids are pre-marked in [_animatedIds] on load).
  bool _isNewlyArriving(ChatMessage msg) {
    if (_animatedIds.contains(msg.id)) return false;
    _animatedIds.add(msg.id);
    return true;
  }

  // ── Message bubble ─────────────────────────────────────────────────────────
  Widget _bubble(ChatMessage msg, ChatConversation c, int idx) {
    final isMe    = msg.fromMe;
    final isEmoji = msg.type == MessageType.emoji;
    final isVoice = msg.type == MessageType.voice;
    final isAppt  = msg.type == MessageType.appointment;
    final isImage = msg.type == MessageType.image;
    final isFile  = msg.type == MessageType.file;
    final showAv  = !isMe && (idx == 0 || _msgs[idx - 1].fromMe);

    if (msg.isDeleted) {
      return Padding(
        padding: EdgeInsets.only(bottom: 4, top: showAv ? 8 : 0),
        child: Row(mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
          if (!isMe) const SizedBox(width: 38),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: _cardBg.withOpacity(0.7), borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border, width: 1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.block_rounded, size: 14, color: _txtSub.withOpacity(0.5)), const SizedBox(width: 6),
                Text(isMe ? 'You deleted this message' : 'This message was deleted',
                    style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub, fontStyle: FontStyle.italic)),
              ])),
        ]),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      // Entrance animation ONLY for newly arriving messages —
      // history is pre-marked in [_animatedIds] on load, so opening
      // a thread no longer re-animates every bubble.
      duration: _isNewlyArriving(msg)
          ? Duration(milliseconds: 220 + (math.min(idx, 8) * 25))
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(isMe ? (1 - v) * 18 : (1 - v) * -18, 0),
        child: Opacity(opacity: v, child: child),
      ),
      child: GestureDetector(
        onTap: msg.sendFailed ? () => _retrySend(msg) : null,
        onLongPress: () => _msgMenu(msg, c),
        child: Padding(
          padding: EdgeInsets.only(bottom: 4, top: showAv && !isMe ? 8 : 0),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: showAv ? 1.0 : 0.0,
                    child: Container(width: 28, height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.6), c.avatarColor])),
                        child: Center(child: Text(c.initials[0], style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white))))),
                const SizedBox(width: 6),
              ],
              Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                if (msg.isForwarded) Padding(padding: const EdgeInsets.only(bottom: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shortcut_rounded, size: 12, color: _txtSub.withOpacity(0.6)), const SizedBox(width: 4),
                      Text('Forwarded', style: GoogleFonts.dmSans(fontSize: 11, color: _txtSub.withOpacity(0.6), fontStyle: FontStyle.italic)),
                    ])),
                // Appointment card or emoji or media or normal bubble
                if (isAppt)
                  _appointmentBubble(msg, isMe)
                else if (isEmoji)
                  Text(msg.text, style: const TextStyle(fontSize: 40))
                else if (isImage)
                  _imageBubble(msg, isMe)
                else if (isFile)
                  _fileBubble(msg, isMe)
                else
                  _textBubble(msg, c, isMe, isVoice),
                // Reactions
                if (msg.reactions.isNotEmpty)
                  Transform.translate(offset: const Offset(0, -4),
                      child: GestureDetector(
                        onTap: () => _showReactionDetails(msg),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border, width: 1),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]),
                          child: Row(mainAxisSize: MainAxisSize.min,
                              children: msg.reactions.entries.map((e) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    padding: msg.myReaction == e.key ? const EdgeInsets.all(2) : EdgeInsets.zero,
                                    decoration: msg.myReaction == e.key ? BoxDecoration(color: _accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)) : null,
                                    child: Text(e.key, style: const TextStyle(fontSize: 13)),
                                  ),
                                  if (e.value > 1) ...[const SizedBox(width: 2), Text('${e.value}', style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: _txtSub))],
                                ]),
                              )).toList()),
                        ),
                      )),
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (msg.isStarred) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFD700))),
                  // Queued (not yet sent): clock + "sending…" so the
                  // user sees what will go out on reconnect.
                  if (_queuedIds.contains(msg.id)) ...[
                    Icon(Icons.schedule_rounded, size: 11, color: _txtSub.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text('sending…', style: GoogleFonts.dmSans(fontSize: 10, color: _txtSub.withOpacity(0.7))),
                    const SizedBox(width: 6),
                  ],
                  // Failed (echo timed out): tap the bubble to retry.
                  if (msg.sendFailed) ...[
                    const Icon(Icons.error_outline_rounded, size: 12, color: Color(0xFFE05C5C)),
                    const SizedBox(width: 3),
                    Text('Failed — tap to retry', style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFFE05C5C))),
                    const SizedBox(width: 6),
                  ],
                  Text(msg.time, style: GoogleFonts.dmSans(fontSize: 10, color: _txtSub.withOpacity(0.7))),
                  if (isMe) ...[const SizedBox(width: 4), _tick(msg.status)],
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textBubble(ChatMessage msg, ChatConversation c, bool isMe, bool isVoice) => Container(
    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isVoice ? 0.75 : 0.68)),
    decoration: BoxDecoration(
      gradient: isMe ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      color: isMe ? null : _cardBg,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
      ),
      border: isMe ? null : Border.all(color: _border, width: 1.2),
      boxShadow: [BoxShadow(color: (isMe ? _btnShadow : Colors.black).withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // Reply preview
      if (msg.replyTo != null)
        Container(margin: const EdgeInsets.fromLTRB(10, 10, 10, 0), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.15) : _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: isMe ? Colors.white.withOpacity(0.6) : _accent, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(msg.replyTo!.fromMe ? 'You' : c.name.split(' ').first,
                  style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white.withOpacity(0.9) : _accent)),
              Text(msg.replyTo!.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12, color: isMe ? Colors.white.withOpacity(0.7) : _txtSub)),
            ])),
      Padding(
        padding: EdgeInsets.fromLTRB(isVoice ? 12 : 14, 10, isVoice ? 12 : 14, 10),
        child: isVoice
            ? VoiceBubble(
                duration: msg.voiceDuration ?? '0:00',
                isMe: isMe,
                accent: _accent,
                btnGrad: _btnGrad,
                // API voice notes carry the audio URL in `text`;
                // legacy on-device notes have no URL and render
                // statically (see VoiceBubble).
                audioUrl: msg.text.startsWith('http') ? msg.text : null,
              )
            : Text(msg.text, style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w500,
                color: isMe ? Colors.white : _txtMain, height: 1.45)),
      ),
    ]),
  );

  /// Appointment card bubble — new feature
  Widget _appointmentBubble(ChatMessage msg, bool isMe) => Container(
    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
    decoration: BoxDecoration(
      color: isMe ? null : _cardBg,
      gradient: isMe ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
      ),
      border: isMe ? null : Border.all(color: _border, width: 1.2),
      boxShadow: [BoxShadow(color: (isMe ? _btnShadow : Colors.black).withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.2) : _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_month_rounded, color: isMe ? Colors.white : _accent, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appointment', style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600,
                color: isMe ? Colors.white.withOpacity(0.7) : _txtSub)),
            Text(msg.appointmentTitle ?? 'Consultation', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w800,
                color: isMe ? Colors.white : _txtMain)),
          ])),
        ]),
        const SizedBox(height: 10),
        Container(height: 1, color: isMe ? Colors.white.withOpacity(0.2) : _border),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.today_rounded, size: 14, color: isMe ? Colors.white.withOpacity(0.75) : _txtSub),
          const SizedBox(width: 6),
          Text(msg.appointmentDate ?? '', style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isMe ? Colors.white.withOpacity(0.9) : _txtMain)),
          const SizedBox(width: 14),
          Icon(Icons.access_time_rounded, size: 14, color: isMe ? Colors.white.withOpacity(0.75) : _txtSub),
          const SizedBox(width: 6),
          Text(msg.appointmentTime ?? '', style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isMe ? Colors.white.withOpacity(0.9) : _txtMain)),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _openAppointment(msg),
          child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.15) : _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isMe ? Colors.white.withOpacity(0.2) : _accent.withOpacity(0.2)),
              ),
              child: Center(child: Text('View Appointment',
                  style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white : _accent)))),
        ),
      ]),
    ),
  );

  /// Open the appointment behind a shared card. The id is embedded
  /// in the share text. Local lookup first; when the receiver
  /// doesn't have it locally, fetch it from the API; when that fails
  /// too (not a participant, or gone), show a read-only detail view
  /// built from the card's own title/date/time instead of dumping
  /// the user on the appointments list.
  Future<void> _openAppointment(ChatMessage msg) async {
    final id = msg.appointmentId;
    Appointment? appt;
    if (id != null) {
      final matches = AppStateProvider.of(
        context,
      ).appointments.where((a) => a.id == id);
      if (matches.isNotEmpty) appt = matches.first;
    }
    if (appt == null && id != null) {
      try {
        appt = await AppointmentService.instance.getAppointment(id);
      } catch (_) {
        appt = null;
      }
    }
    if (!mounted) return;
    if (appt != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AppointmentDetailScreen(appointment: appt!),
        ),
      );
      return;
    }
    final title = msg.appointmentTitle ?? 'Consultation';
    final date = msg.appointmentDate ?? '';
    final time = msg.appointmentTime ?? '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w800,
            color: _txtMain,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date.isNotEmpty)
              Text(date, style: GoogleFonts.dmSans(color: _txtSub)),
            if (time.isNotEmpty)
              Text(time, style: GoogleFonts.dmSans(color: _txtSub)),
            const SizedBox(height: 8),
            Text(
              'Shared in this chat. The full appointment isn\'t '
              'available on this device.',
              style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.dmSans(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Photo message: the image with rounded corners; tap opens it
  /// full-screen. `msg.text` holds the media URL.
  Widget _imageBubble(ChatMessage msg, bool isMe) => GestureDetector(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullScreenImageView(url: msg.text)),
    ),
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: Border.all(color: _border, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 3), bottomRight: Radius.circular(isMe ? 3 : 18),
        ),
        child: CachedNetworkImage(
          imageUrl: msg.text,
          fit: BoxFit.cover,
          // Chat bubbles are ~68% of screen width; decoding the full
          // upload resolution here is wasted work on every scroll.
          memCacheWidth: 800,
          placeholder: (_, __) => Container(
            height: 180,
            color: _bg,
            child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5)),
          ),
          errorWidget: (_, __, ___) => Container(
            height: 140,
            color: _bg,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.broken_image_rounded, size: 36, color: _txtSub.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text("Couldn't load image", style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
            ]),
          ),
        ),
      ),
    ),
  );

  /// File message: icon + name + size; tap opens the URL externally.
  Widget _fileBubble(ChatMessage msg, bool isMe) => GestureDetector(
    onTap: () => _openFileUrl(msg.text),
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
      decoration: BoxDecoration(
        gradient: isMe ? LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: isMe ? null : _cardBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: isMe ? null : Border.all(color: _border, width: 1.2),
        boxShadow: [BoxShadow(color: (isMe ? _btnShadow : Colors.black).withOpacity(0.09), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.2) : _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.insert_drive_file_rounded, color: isMe ? Colors.white : _accent, size: 20)),
          const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(msg.fileName ?? 'File', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: isMe ? Colors.white : _txtMain)),
            if (msg.fileSize != null) ...[
              const SizedBox(height: 2),
              Text(ChatService.formatFileSize(msg.fileSize!),
                  style: GoogleFonts.dmSans(fontSize: 11.5,
                      color: isMe ? Colors.white.withOpacity(0.75) : _txtSub)),
            ],
          ])),
          const SizedBox(width: 8),
          Icon(Icons.open_in_new_rounded, size: 16,
              color: isMe ? Colors.white.withOpacity(0.75) : _txtSub),
        ]),
      ),
    ),
  );

  Widget _tick(MessageStatus s) {
    switch (s) {
      case MessageStatus.sent:      return Icon(Icons.check_rounded, size: 13, color: _txtSub.withOpacity(0.6));
      case MessageStatus.delivered: return Icon(Icons.done_all_rounded, size: 13, color: _txtSub.withOpacity(0.6));
      case MessageStatus.read:      return Icon(Icons.done_all_rounded, size: 13, color: _accent);
    }
  }

  // ── Media upload indicator ───────────────────────────────────────────────
  Widget _uploadingBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1))),
    child: Row(children: [
      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent)),
      const SizedBox(width: 10),
      Text(_uploadingLabel, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: _txtSub)),
    ]),
  );

  // ── Reply bar ──────────────────────────────────────────────────────────────
  Widget _replyBar() {
    final msg = _replyTo!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1))),
      child: Row(children: [
        Container(width: 3, height: 40, decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.fromMe ? 'You' : widget.conversation.name.split(' ').first,
              style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
          Text(msg.type == MessageType.voice ? '🎤 Voice message' : msg.previewText, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
        ])),
        GestureDetector(onTap: () => setState(() => _replyTo = null),
            child: Icon(Icons.close_rounded, color: _txtSub, size: 20)),
      ]),
    );
  }

  // ── Recording overlay ──────────────────────────────────────────────────────
  // The ticking timer and waveform listen to [_recSecondsNotifier]
  // directly, so the 1s tick rebuilds only this overlay — not the
  // whole thread.
  Widget _recordingOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1)),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -4))]),
      child: Row(children: [
        AnimatedBuilder(animation: _recCtrl, builder: (_, __) => Container(width: 46, height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE05C5C).withOpacity(0.1 + _recCtrl.value * 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.4 + _recCtrl.value * 0.3), width: 2),
            ),
            child: const Icon(Icons.mic_rounded, color: Color(0xFFE05C5C), size: 22))),
        const SizedBox(width: 14),
        Expanded(child: ValueListenableBuilder<int>(
          valueListenable: _recSecondsNotifier,
          builder: (_, secs, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recording...', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFE05C5C))),
            const SizedBox(height: 3),
            AnimatedBuilder(animation: _recCtrl, builder: (_, __) => Row(children: [
              ...List.generate(20, (i) {
                final rng = math.Random(i * 13 + secs);
                final h   = (0.2 + rng.nextDouble() * 0.8) * 18;
                return Container(margin: const EdgeInsets.only(right: 2), width: 3, height: h,
                    decoration: BoxDecoration(color: const Color(0xFFE05C5C).withOpacity(0.4 + _recCtrl.value * 0.5), borderRadius: BorderRadius.circular(2)));
              }),
            ])),
          ]),
        )),
        const SizedBox(width: 12),
        ValueListenableBuilder<int>(
          valueListenable: _recSecondsNotifier,
          builder: (_, secs, __) {
            final mins = secs ~/ 60;
            final s = (secs % 60).toString().padLeft(2, '0');
            return Text('$mins:$s', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFE05C5C)));
          },
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _finishRecording(send: false),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: _txtSub.withOpacity(0.1), borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
              child: Icon(Icons.close_rounded, color: _txtSub, size: 18)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _finishRecording(send: true),
          child: Container(width: 46, height: 46,
              decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19)),
        ),
      ]),
    );
  }

  /// Emojis for the selected tab: tab 0 ("Recent") shows the emojis
  /// actually used this session (falling back to the defaults until
  /// any are sent).
  List<String> get _currentTabEmojis {
    if (_emojiTab == 0 && RecentEmojis.recent.isNotEmpty) {
      return RecentEmojis.recent;
    }
    return emojiCategories[_emojiTab].emojis;
  }

  // ── Emoji keyboard ─────────────────────────────────────────────────────────
  Widget _emojiKeyboard() => Container(
    height: 280,
    decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1))),
    child: Column(children: [
      Container(height: 44, color: _bg, child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          itemCount: emojiCategories.length,
          itemBuilder: (_, i) {
            final sel = _emojiTab == i;
            return GestureDetector(onTap: () => setState(() => _emojiTab = i),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? _accent.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: sel ? Border.all(color: _accent.withOpacity(0.4), width: 1.5) : null,
                    ),
                    child: Text(emojiCategories[i].icon, style: TextStyle(fontSize: sel ? 20 : 17))));
          })),
      Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: _currentTabEmojis.length,
          itemBuilder: (_, i) {
            final e = _currentTabEmojis[i];
            return GestureDetector(onTap: () => _sendEmoji(e),
                child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 22)))));
          })),
    ]),
  );

  // ── Attachment picker ──────────────────────────────────────────────────────
  // Only options that actually work are shown.
  void _showAttach() {
    final rows = [
      [Icons.camera_alt_rounded,       'Camera',      const Color(0xFF4A90D9)],
      [Icons.image_rounded,             'Gallery',     const Color(0xFF7C3AED)],
      [Icons.insert_drive_file_rounded, 'Document',    const Color(0xFFE8805A)],
      [Icons.calendar_month_rounded,    'Appointment', const Color(0xFF3B73C0)],
    ];
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _border, width: 1.2)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
          Text('Share', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: rows.map((r) => _attIcon(r[0] as IconData, r[1] as String, r[2] as Color)).toList()),
        ]),
      ),
    ));
  }

  Widget _attIcon(IconData icon, String label, Color color) => GestureDetector(
    onTap: () {
      Navigator.pop(context);
      switch (label) {
        case 'Camera':
          _pickImage(ImageSource.camera);
        case 'Gallery':
          _pickImage(ImageSource.gallery);
        case 'Document':
          _pickFile();
        case 'Appointment':
          _showAppointmentPicker();
      }
    },
    child: SizedBox(width: 68, child: Column(children: [
      Container(width: 54, height: 54,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, color: color, size: 26)),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center, maxLines: 1,
          style: GoogleFonts.dmSans(fontSize: 10.5, fontWeight: FontWeight.w600, color: _txtSub)),
    ])),
  );

  // ── Appointment picker ───────────────────────────────────────────────────
  // Real upcoming appointments from AppState — never hardcoded.
  void _showAppointmentPicker() {
    final now = DateTime.now();
    final appts = AppStateProvider.of(context).appointments
        .where(
          (a) =>
              a.dateTime.isAfter(now.subtract(const Duration(minutes: 1))) &&
              a.status != ApptStatus.cancelled &&
              a.status != ApptStatus.completed,
        )
        .toList();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: _border, width: 1.2)),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.fromLTRB(0, 10, 0, 16),
              decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18)),
                const SizedBox(width: 14),
                Text('Share Appointment', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900, color: _txtMain)),
              ])),
          const SizedBox(height: 16),
          Divider(color: _border, height: 1),
          if (appts.isEmpty)
            Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.calendar_month_rounded, size: 52, color: _txtSub.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text('No upcoming appointments', style: GoogleFonts.dmSans(fontSize: 15, color: _txtSub)),
            ])))
          else
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: appts.length,
            itemBuilder: (_, i) {
              final a = appts[i];
              final date = DateFormat('EEEE, MMM d').format(a.dateTime);
              final time = DateFormat('h:mm a').format(a.dateTime);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _shareAppointment(a);
                },
                child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _border, width: 1.3),
                        boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
                    child: Row(children: [
                      Container(width: 44, height: 44,
                          decoration: BoxDecoration(color: _accent.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                          child: Icon(Icons.calendar_month_rounded, color: _accent, size: 22)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: _txtMain)),
                        const SizedBox(height: 3),
                        Text('$date  •  $time  •  ${a.status.name}',
                            style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                      ])),
                      Container(width: 34, height: 34,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(11)),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 16)),
                    ])),
              );
            },
          )),
        ]),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _inputBar(ChatConversation c) {
    final vInsets = MediaQuery.of(context).viewInsets.bottom;
    final vPad    = MediaQuery.of(context).viewPadding.bottom;
    final botPad  = vInsets > 0 ? 0.0 : vPad;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + botPad),
      decoration: BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _border, width: 1)),
          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -4))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Emoji toggle
        GestureDetector(
          onTap: () { FocusScope.of(context).unfocus(); setState(() => _showEmoji = !_showEmoji); },
          child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 40, height: 40,
              decoration: BoxDecoration(
                color: _showEmoji ? _accent.withOpacity(0.12) : _bg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _showEmoji ? _accent.withOpacity(0.3) : _border),
              ),
              child: Icon(Icons.emoji_emotions_rounded, color: _showEmoji ? _accent : _txtSub, size: 20)),
        ),
        const SizedBox(width: 8),
        // Text field
        Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _typing ? _accent.withOpacity(0.6) : _border, width: _typing ? 1.8 : 1.5),
                boxShadow: _typing ? [BoxShadow(color: _accent.withOpacity(0.10), blurRadius: 8)] : []),
            child: TextField(
              controller: _msgCtrl,
              onTap: () => setState(() => _showEmoji = false),
              onChanged: (v) {
                // Only rebuild when the boolean actually changes —
                // a setState per keystroke rebuilt the whole
                // Scaffold (incl. the message list) on every key.
                final typing = v.isNotEmpty;
                if (typing != _typing) setState(() => _typing = typing);
              },
              onSubmitted: (_) => _send(),
              maxLines: 4, minLines: 1,
              style: GoogleFonts.dmSans(fontSize: 14, color: _txtMain, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Message ${c.name.split(" ").first}...',
                hintStyle: GoogleFonts.dmSans(color: _txtSub, fontSize: 14),
                border: InputBorder.none, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ))),
        const SizedBox(width: 8),
        // Attach (only when not typing)
        if (!_typing) ...[
          GestureDetector(onTap: _showAttach,
              child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
                  child: Icon(Icons.attach_file_rounded, color: _txtSub, size: 19))),
          const SizedBox(width: 8),
        ],
        // Send / Mic
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 0.88).chain(CurveTween(curve: Curves.easeOut)).animate(_sendCtrl),
          child: _typing
              ? GestureDetector(onTap: _send,
              child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 19)))
              : GestureDetector(
              onLongPressStart: (_) {
                HapticFeedback.heavyImpact();
                _startRecording();
              },
              onLongPressEnd: (_) {
                if (_recording) _finishRecording(send: true);
              },
              child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border, width: 1.5)),
                  child: Icon(Icons.mic_rounded, color: _txtSub, size: 20))),
        ),
      ]),
    );
  }

  // ── Message long-press menu ────────────────────────────────────────────────
  void _msgMenu(ChatMessage msg, ChatConversation c) {
    HapticFeedback.mediumImpact();
    const qe = ['❤️', '😂', '😮', '😢', '🙏', '👍'];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: Container(
        decoration: BoxDecoration(color: _cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _border, width: 1.2)),
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 12), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                child: Text(msg.type == MessageType.voice ? '🎤 Voice message' : msg.previewText,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub))),
            // Quick reactions
            Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: qe.map((e) {
                  final mine = msg.myReaction == e;
                  return GestureDetector(onTap: () => _react(msg, e),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                          width: 44, height: 44,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: mine ? _accent.withOpacity(0.2) : _cardBg,
                              border: Border.all(color: mine ? _accent : _border, width: mine ? 2 : 1)),
                          child: Stack(children: [
                            Center(child: Text(e, style: const TextStyle(fontSize: 21))),
                            if (mine) Positioned(top: 2, right: 2, child: Container(width: 8, height: 8,
                                decoration: BoxDecoration(color: _accent, shape: BoxShape.circle))),
                          ])));
                }).toList())),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('Reactions are only visible on this device.',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _txtSub))),
            Divider(color: _border, height: 1),
            _mAction(Icons.reply_rounded,          'Reply',    () => setState(() => _replyTo = msg)),
            _mAction(Icons.shortcut_rounded,        'Forward',  () => _showForwardSheet(msg)),
            _mAction(Icons.copy_rounded,            'Copy',     () { Clipboard.setData(ClipboardData(text: msg.text)); _toast('Copied'); }),
            _mAction(msg.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                msg.isStarred ? 'Unstar' : 'Star',
                () { setState(() => msg.isStarred = !msg.isStarred); ChatDB.update(_convId, msg).catchError((_) {}); },
                color: msg.isStarred ? const Color(0xFFFFD700) : null),
            _mAction(Icons.delete_outline_rounded, 'Delete', () => _deleteMenu(msg), color: const Color(0xFFE05C5C)),
          ]),
        )),
      )),
    );
  }

  Widget _mAction(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
    leading: Icon(icon, color: color ?? _accent, size: 22),
    title: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600,
        color: color == const Color(0xFFE05C5C) ? color! : _txtMain)),
    onTap: () { Navigator.pop(context); onTap(); },
  );

  // ── Starred messages ───────────────────────────────────────────────────────
  void _showStarred() {
    final starred = _msgs.where((m) => m.isStarred).toList();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
        builder: (_) => Container(
          height: 400, padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 22), const SizedBox(width: 10),
              Text('Starred Messages', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: _txtMain)),
            ])),
            const SizedBox(height: 12),
            if (starred.isEmpty)
              Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.star_outline_rounded, size: 52, color: _txtSub.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text('No starred messages', style: GoogleFonts.dmSans(fontSize: 15, color: _txtSub)),
              ])))
            else
              Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: starred.length,
                  itemBuilder: (_, i) {
                    final m = starred[i];
                    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                        child: Row(children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 16),
                          const SizedBox(width: 10),
                          Expanded(child: Text(m.text, style: GoogleFonts.dmSans(fontSize: 13.5, color: _txtMain))),
                          Text(m.time, style: GoogleFonts.dmSans(fontSize: 10.5, color: _txtSub)),
                        ]));
                  })),
          ]),
        ));
  }

  // ── Clear chat ─────────────────────────────────────────────────────────────
  // Local only: the backend has no delete endpoint, so the server
  // history stays and reloads next time the chat is opened.
  void _clearChat() => showDialog(context: context, builder: (_) => AlertDialog(
    backgroundColor: _cardBg,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text('Clear Chat?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: _txtMain)),
    content: Text('Messages will be cleared on this device only. They stay on the server and reload next time.',
        style: GoogleFonts.dmSans(color: _txtSub)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.dmSans(color: _txtSub, fontWeight: FontWeight.w600))),
      TextButton(onPressed: () {
        Navigator.pop(context);
        setState(() => _msgs.clear());
        ChatDB.clear(_convId).catchError((_) {});
      }, child: Text('Clear', style: GoogleFonts.dmSans(color: const Color(0xFFE05C5C), fontWeight: FontWeight.w700))),
    ],
  ));

  // ── In-chat search (NEW FEATURE) ───────────────────────────────────────────
  /// Search, then jump to the tapped result in this thread.
  Future<void> _openSearch() async {
    final id = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(
          messages: _msgs,
          peerName: widget.conversation.name,
        ),
      ),
    );
    if (id != null && mounted) _scrollToMessage(id);
  }

  /// Jump to a message (from search): scroll it into view and flash
  /// a highlight. Messages far outside the built range need a rough
  /// jump first so the row gets built.
  Future<void> _scrollToMessage(String id) async {
    final idx = _msgs.indexWhere((m) => m.id == id);
    if (idx < 0 || !_scrollCtrl.hasClients) return;
    if (_msgKeys[id]?.currentContext == null) {
      final extent = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.jumpTo(
        (idx / _msgs.length * extent).clamp(0.0, extent),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    setState(() => _highlightId = id);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightId == id) {
        setState(() => _highlightId = null);
      }
    });
  }

  // ── Reaction details ───────────────────────────────────────────────────────
  void _showReactionDetails(ChatMessage msg) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Text('Reactions', style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 4),
            Text('Reactions are only visible on this device.',
                style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
            const SizedBox(height: 16),
            ...msg.reactions.entries.map((e) => ListTile(
              leading: Text(e.key, style: const TextStyle(fontSize: 28)),
              // Reactions are local-only, so only my own reaction is
              // ever attributed — never the peer's name.
              title: Text(e.key == msg.myReaction ? 'You' : 'On this device',
                  style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: _txtMain)),
              subtitle: Text('${e.value} reaction${e.value > 1 ? "s" : ""}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
              trailing: e.key == msg.myReaction ? GestureDetector(
                onTap: () { Navigator.pop(context); _react(msg, e.key); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFE05C5C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE05C5C).withOpacity(0.3))),
                    child: Text('Remove', style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFE05C5C), fontWeight: FontWeight.w600))),
              ) : null,
            )).toList(),
          ]),
        ));
  }

  // ── Forward message ────────────────────────────────────────────────────────
  // Text/emoji/appointment forwards are sent for real over the live
  // connection; the server echo renders them. Forwards to ANOTHER
  // room open a short-lived connection to that room and send the
  // content as a new message there (the backend has no forward
  // endpoint). Media and old device-only voice notes cannot be
  // forwarded yet.
  String? _forwardText(ChatMessage original) {
    switch (original.type) {
      case MessageType.text:
      case MessageType.emoji:
        return original.text;
      case MessageType.appointment:
        final idPart = original.appointmentId != null
            ? ' [${original.appointmentId}]'
            : '';
        return '📅 Appointment$idPart: ${original.appointmentTitle ?? 'Consultation'}'
            ' — ${original.appointmentDate ?? ''} at ${original.appointmentTime ?? ''}';
      case MessageType.image:
      case MessageType.file:
      case MessageType.voice:
        return null;
    }
  }

  void _showForwardSheet(ChatMessage original) {
    // Hoisted out of the builder: filter once, not per row (O(n²)).
    final targets = widget.allConversations
        .where((c) => !c.isArchived)
        .toList();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (ctx) => Container(
          height: MediaQuery.of(ctx).size.height * 0.62,
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.shortcut_rounded, color: Colors.white, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Forward to', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w900, color: _txtMain, letterSpacing: -0.5)),
                Text('Select a conversation', style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
              ])),
              GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _border.withOpacity(0.5), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.close_rounded, color: _txtSub, size: 16))),
            ])),
            Divider(color: _border, height: 1),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: targets.length,
              itemBuilder: (_, i) {
                final c = targets[i];
                return GestureDetector(
                  onTap: () => _forwardTo(c, original),
                  child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _border, width: 1.3),
                          boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: Row(children: [
                        Stack(children: [
                          Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [c.avatarColor.withOpacity(0.7), c.avatarColor]),
                              boxShadow: [BoxShadow(color: c.avatarColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                              child: Center(child: Text(c.initials, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)))),
                          if (c.online) Positioned(bottom: 0, right: 0, child: Container(width: 12, height: 12,
                              decoration: BoxDecoration(color: const Color(0xFF2ECC96), shape: BoxShape.circle, border: Border.all(color: _cardBg, width: 2)))),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: GoogleFonts.dmSans(fontSize: 14.5, fontWeight: FontWeight.w700, color: _txtMain)),
                          Text(c.service, style: GoogleFonts.dmSans(fontSize: 12, color: _txtSub)),
                        ])),
                        Container(width: 36, height: 36, decoration: BoxDecoration(gradient: LinearGradient(colors: _btnGrad), borderRadius: BorderRadius.circular(11),
                            boxShadow: [BoxShadow(color: _btnShadow.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]),
                            child: const Icon(Icons.send_rounded, color: Colors.white, size: 16)),
                      ])),
                );
              },
            )),
          ]),
        ));
  }

  Future<void> _forwardTo(ChatConversation target, ChatMessage original) async {
    Navigator.pop(context);
    final text = _forwardText(original);
    if (text == null || text.isEmpty) {
      _toast('This message can\'t be forwarded yet.');
      return;
    }
    if (target.id != _convId) {
      await _forwardToOtherRoom(target, text);
      return;
    }
    final fwd = ChatMessage(
      id: _mkId(), text: text, fromMe: true,
      time: _fmt(DateTime.now()), createdAt: DateTime.now(),
      type: MessageType.text,
      isForwarded: true, status: MessageStatus.sent,
    );
    if (_connection == null || !_wsLive) {
      _enqueue(fwd);
      return;
    }
    setState(() {
      _msgs.add(fwd);
      _pending.add(fwd);
    });
    _scrollDown();
    try {
      final sendId = await _connection!.sendText(text);
      _sendIds[sendId] = fwd;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.remove(fwd);
        _pending.remove(fwd);
      });
      _toast(e.message);
    }
  }

  /// Forward to ANOTHER room: open a short-lived connection to the
  /// target room, wait for the handshake, send the content as a new
  /// message there, then close it.
  Future<void> _forwardToOtherRoom(ChatConversation target, String text) async {
    ChatRoomConnection? conn;
    try {
      conn = await ChatService.instance.connectRoom(target.id);
      if (conn.currentState == ChatConnectionState.failed) {
        _toast('Could not connect to ${target.name}. Please try again.');
        return;
      }
      if (conn.currentState != ChatConnectionState.connected) {
        // Wait for the handshake (up to 20s) — sendText refuses
        // before `connected`.
        final state = await conn.states
            .firstWhere(
              (s) =>
                  s == ChatConnectionState.connected ||
                  s == ChatConnectionState.failed,
            )
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () => ChatConnectionState.failed,
            );
        if (state != ChatConnectionState.connected) {
          _toast('Could not connect to ${target.name}. Please try again.');
          return;
        }
      }
      await conn.sendText(text);
      if (mounted) _toast('Forwarded to ${target.name}');
    } catch (_) {
      if (mounted) _toast('Could not forward to ${target.name}.');
    } finally {
      await conn?.close();
    }
  }

  // ── Delete menu ────────────────────────────────────────────────────────────
  void _deleteMenu(ChatMessage msg) => showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: BoxDecoration(color: _cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _border, width: 1.2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: _txtSub.withOpacity(0.3), borderRadius: BorderRadius.circular(4))),
            Text('Delete Message?', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w800, color: _txtMain)),
            const SizedBox(height: 8),
            Text('This only deletes the message on this device. It stays on the server and for the other person.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 13, color: _txtSub)),
            const SizedBox(height: 20),
            _delBtn('Delete for me', const Color(0xFFE05C5C), () {
              // Local only: there is no server delete endpoint, so
              // the message stays on the server and for the other
              // side. The label says so honestly.
              setState(() => msg.isDeleted = true);
              ChatDB.update(_convId, msg).catchError((_) {});
            }),
            const SizedBox(height: 10),
            _delBtn('Cancel', _txtSub, () {}, outline: true),
          ])));

  Widget _delBtn(String label, Color color, VoidCallback onTap, {bool outline = false}) =>
      GestureDetector(onTap: () { Navigator.pop(context); onTap(); },
          child: Container(width: double.infinity, height: 50,
              decoration: BoxDecoration(color: outline ? Colors.transparent : color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: outline ? _border : color.withOpacity(0.4), width: 1.5)),
              child: Center(child: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: color)))));

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
    backgroundColor: _accent, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 2),
  ));
}

/// Full-screen photo view: pinch to zoom, back arrow to return.
class _FullScreenImageView extends StatelessWidget {
  final String url;
  const _FullScreenImageView({required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Center(
      child: InteractiveViewer(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_rounded, size: 48, color: Colors.white54),
              SizedBox(height: 12),
              Text(
                "Couldn't load image",
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One queued outgoing send: the optimistic message plus the reply
/// context to send with it when the queue flushes.
class _QueuedSend {
  final ChatMessage message;
  final String? replyToId;
  final String? replyToText;

  _QueuedSend({required this.message, this.replyToId, this.replyToText});
}
