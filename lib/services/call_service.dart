import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../user_session.dart';
import 'api_client.dart';
import 'chat_service.dart';
import 'token_storage.dart';

/// Lifecycle of one call, from the local user's point of view.
enum CallState {
  /// No call in progress.
  idle,

  /// Outgoing: the other side is being rung. Incoming: the accept
  /// was sent and the caller is setting up.
  ringing,

  /// The call was accepted; SDP/ICE are being exchanged.
  connecting,

  /// Media is flowing (ICE connected).
  connected,

  /// The call finished (ended, declined, no answer, or failed).
  ended,

  /// The call could not be set up at all (network/auth/media error).
  failed,
}

/// Why a call ended. Read [CallConnection.endReason] when the state
/// becomes [CallState.ended] to show the right message.
class CallEndReason {
  static const ended = 'ended';
  static const declined = 'declined';

  /// The callee was already in another call (`call.rejected` with
  /// `reason: 'busy'`).
  static const busy = 'busy';
  static const noAnswer = 'noAnswer';
  static const connectionLost = 'connectionLost';
  static const failed = 'failed';
}

/// Time-limited TURN credentials for Metered's Open Relay static-auth
/// scheme (https://www.metered.ca/tools/openrelay/ — "TURN Server
/// Credentials API" / static auth): the username is
/// `<unix-expiry>:appointly` and the credential is the base64 HMAC-SHA1
/// of that username under the shared secret `openrelayprojectsecret`.
///
/// The old no-signup credentials (`openrelayproject` /
/// `openrelayproject` on `turn:openrelay.metered.ca`) are dead — the
/// hostname resolves to the 192.0.2.1 TEST-NET sinkhole — so without
/// these credentials phones behind carrier NATs never establish a
/// media path. Kept as a pure top-level function so it is unit-testable
/// (see `test/call_service_test.dart`).
Map<String, String> meteredTurnCredentials({required int expiryUnix}) {
  final username = '$expiryUnix:appointly';
  final digest = Hmac(
    sha1,
    utf8.encode('openrelayprojectsecret'),
  ).convert(utf8.encode(username));
  return {
    'username': username,
    'credential': base64Encode(digest.bytes),
  };
}

/// An incoming call, as pushed by the server on `ws/notify/`
/// (or on an open call socket when already in a call).
class IncomingCall {
  final String callId;
  final String callerId;
  final String callerUsername;
  final String callType; // 'video' | 'audio'
  final DateTime receivedAt;

  const IncomingCall({
    required this.callId,
    required this.callerId,
    required this.callerUsername,
    required this.callType,
    required this.receivedAt,
  });

  factory IncomingCall.fromFrame(Map<String, dynamic> frame) => IncomingCall(
    callId: frame['call_id'] as String,
    callerId: frame['caller_id']?.toString() ?? '',
    callerUsername: frame['caller_username'] as String? ?? '',
    callType: frame['call_type'] as String? ?? 'video',
    receivedAt: DateTime.now(),
  );

  /// Display name for the caller — the email when the server sent
  /// one, otherwise `User #id` (the incoming frame carries no name,
  /// and there is no get-user-by-ID endpoint to resolve one).
  String get displayName =>
      callerUsername.isNotEmpty ? callerUsername : 'User #$callerId';
}

/// One call session as returned by the REST API
/// (`GET /api/call/history/`, `GET /api/call/<call_id>/`) and inside
/// the `session` object of signalling frames.
class CallSessionInfo {
  final String callId;
  final String callerId;
  final String calleeId;
  final String callType;
  final String status; // ringing | connected | ended | rejected | missed
  final DateTime? startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final double? durationSeconds;

  const CallSessionInfo({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.callType,
    required this.status,
    required this.startedAt,
    required this.connectedAt,
    required this.endedAt,
    required this.durationSeconds,
  });

  factory CallSessionInfo.fromJson(Map<String, dynamic> json) =>
      CallSessionInfo(
        callId: json['call_id'] as String,
        callerId: json['caller_id']?.toString() ?? '',
        calleeId: json['callee_id']?.toString() ?? '',
        callType: json['call_type'] as String? ?? 'video',
        status: json['status'] as String? ?? '',
        startedAt: json['started_at'] == null
            ? null
            : DateTime.tryParse(json['started_at'] as String),
        connectedAt: json['connected_at'] == null
            ? null
            : DateTime.tryParse(json['connected_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.tryParse(json['ended_at'] as String),
        durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      );
}

/// Voice/video calls against the backend call app.
///
/// Signalling (see backend `call/consumers.py`):
/// - Notify socket: `wss://<host>/ws/notify/?token=<JWT>` — one
///   persistent connection per session; the server pushes
///   `call.incoming` here. Read-only; clients send nothing.
/// - Call socket: `wss://<host>/ws/call/<call_id>/?token=<JWT>` —
///   one per call. `call_id` is a 32-char UUID4 hex generated by
///   the caller. Close codes: 4001 bad/expired token, 4003 not a
///   participant, 4008 call already in a terminal state.
/// - Caller: connect → `call.initiate` {callee_id, call_type} →
///   `call.initiated` → `call.ringing` when the callee's client is
///   notified → wait for `call.accepted` → SDP offer.
/// - Callee: `call.incoming` → connect to the call socket →
///   `call.accept` (or `call.reject`) → `call.accepted` → wait
///   for `call.sdp_offer` → SDP answer.
/// - Either side: `call.end` → `call.ended` (group broadcast).
/// - The caller cancelling before accept sends `call.cancelled`
///   {call_id} on the notify socket, so the callee's incoming-call
///   UI can dismiss itself instead of ringing the full 30s.
/// - `call.rejected` carries an optional `reason` field: `'busy'`
///   when the callee was already in a call.
/// - When a peer's app dies mid-call the server sends
///   `peer_disconnected` on the call socket.
/// - SDP/ICE frames (`call.sdp_offer`, `call.sdp_answer`,
///   `call.ice_candidate`) are only accepted by the server while
///   the session is CONNECTED, and only from the right party
///   (offer: caller, answer: callee).
/// - Errors arrive as `{"type": "error", "code": "…", "detail": "…"}`.
///
/// The backend has no missed-call timeout: an unanswered call stays
/// RINGING server-side until someone ends it. The caller therefore
/// ends the call locally after [_ringTimeout] ([CallConnection]
/// sends `call.end`, which moves the session to ENDED).
///
/// ICE uses Google's free public STUN servers plus Metered Open
/// Relay TURN servers with time-limited static-auth credentials
/// (see [meteredTurnCredentials] and [CallConnection.iceServers]),
/// so calls can connect across symmetric NATs and mobile data
/// (STUN alone cannot relay media).
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const _callRest = '/api/call';

  /// How long the caller rings before giving up and ending the call.
  static const ringTimeout = Duration(seconds: 30);

  static final _random = Random.secure();

  /// Fresh 32-char UUID4-style hex call ID (caller-generated).
  static String newCallId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? get _myId => UserSession.instance.userId?.toString();

  // ------------------------------------------------------------------
  // Notify socket (persistent, app-level)
  // ------------------------------------------------------------------

  // Escalating retry delays for the notify socket; after the budget
  // (~2–3 min) is spent, a slow 60s retry keeps running until logout
  // so incoming calls never silently die. The budget resets on the
  // first confirmed connection.
  static const _notifyRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 30),
    Duration(seconds: 30),
  ];
  static const _notifySlowRetry = Duration(seconds: 60);

  WebSocketChannel? _notifyChannel;
  StreamSubscription? _notifySubscription;
  Timer? _notifyReconnectTimer;
  bool _notifyWanted = false;
  bool _notifyConnected = false;
  bool _notifySlowMode = false;
  int _notifyAttempts = 0;
  String? _notifyToken;

  /// True when the last notify handshake failed with an auth error
  /// (the backend rejects bad tokens at HTTP level, e.g. 403, never
  /// with close code 4001). Retries are paused until [reconnectNotify]
  /// is called (e.g. after a fresh login).
  bool _notifyAuthFailed = false;
  bool get notifyAuthFailed => _notifyAuthFailed;

  final _incomingController = StreamController<IncomingCall>.broadcast();
  final _notifyErrorsController = StreamController<String>.broadcast();
  final _callCancelledController = StreamController<String>.broadcast();

  /// Incoming calls pushed by the server. The app listens to this
  /// (see `main.dart`) and shows the incoming-call screen.
  Stream<IncomingCall> get incomingCalls => _incomingController.stream;

  /// Call IDs the caller cancelled before accept (`call.cancelled`
  /// on the notify socket). The app listens to this (see `main.dart`)
  /// and dismisses the matching incoming-call screen immediately
  /// instead of letting it ring the full 30s.
  Stream<String> get callCancelled => _callCancelledController.stream;

  /// Problems with the notify connection. Emitted on auth failures
  /// and when the escalating retry budget is spent (a slow 60s retry
  /// keeps running after that). Listen to this to surface the state
  /// and offer a manual retry via [reconnectNotify].
  Stream<String> get notifyErrors => _notifyErrorsController.stream;

  bool get isNotifyConnected => _notifyWanted && _notifyConnected;

  /// The call currently in progress, if any. Used to suppress the
  /// incoming-call dialog while already in a call.
  CallConnection? activeCall;

  bool get hasActiveCall {
    final call = activeCall;
    return call != null &&
        call.state != CallState.idle &&
        call.state != CallState.ended &&
        call.state != CallState.failed;
  }

  /// Open the persistent notify socket. Called after login and after
  /// a session restore (see [AuthService]). Idempotent — calling it
  /// while already connected is a no-op.
  Future<void> connectNotify() async {
    if (_notifyWanted && _notifyConnected && _notifyChannel != null) return;
    _notifyWanted = true;
    _notifyAuthFailed = false;
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) {
      _notifyWanted = false;
      return;
    }
    _notifyToken = token;
    _notifyAttempts = 0;
    _notifySlowMode = false;
    await _connectNotifySocket();
  }

  /// Reconnect the notify socket now, resetting the retry budget and
  /// clearing any auth-failure flag. Safe to call any time after
  /// login; a no-op when already connected or when not wanted.
  Future<void> reconnectNotify() async {
    if (!_notifyWanted || _notifyConnected) return;
    _notifyAuthFailed = false;
    _notifyAttempts = 0;
    _notifySlowMode = false;
    _notifyReconnectTimer?.cancel();
    _notifyReconnectTimer = null;
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    try {
      await _notifyChannel?.sink.close();
    } catch (_) {
      // Already closed.
    }
    _notifyChannel = null;
    final token = await TokenStorage.instance.accessToken;
    if (token != null && token.isNotEmpty) _notifyToken = token;
    await _connectNotifySocket();
  }

  /// Close the notify socket. Called on logout.
  Future<void> disconnectNotify() async {
    _notifyWanted = false;
    _notifyReconnectTimer?.cancel();
    _notifyReconnectTimer = null;
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    try {
      await _notifyChannel?.sink.close();
    } catch (_) {
      // Already closed.
    }
    _notifyChannel = null;
    _notifyConnected = false;
  }

  Uri get _notifyUri => Uri.parse(ChatService.wsBase).replace(
    path: '/ws/notify/',
    queryParameters: {'token': _notifyToken ?? ''},
  );

  Future<void> _connectNotifySocket() async {
    if (!_notifyWanted) return;
    WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(_notifyUri);
    } catch (_) {
      _scheduleNotifyReconnect();
      return;
    }
    _notifyChannel = channel;
    _notifySubscription = channel.stream.listen(
      _onNotifyData,
      onError: (_) => _onNotifyClosed(),
      onDone: _onNotifyClosed,
      cancelOnError: false,
    );
    // Confirm the handshake before reporting connected: the backend
    // rejects bad tokens at HTTP level (403), so a failed handshake
    // surfaces here, not as a close code.
    unawaited(
      channel.ready
          .then((_) {
            if (!_notifyWanted || !identical(_notifyChannel, channel)) return;
            _notifyConnected = true;
            _notifyAttempts = 0;
            _notifySlowMode = false;
            _notifyAuthFailed = false;
          })
          .catchError((Object e) {
            if (!_notifyWanted || !identical(_notifyChannel, channel)) return;
            if ('$e'.contains('403')) {
              // Auth error, not a network blip: stop retrying with a
              // dead token and say so distinctly.
              _notifyAuthFailed = true;
              _emitNotifyError(
                'Your session expired. Log in again to receive calls.',
              );
            }
            // Other handshake failures fall through to the socket
            // close path, which retries on its own.
          }),
    );
  }

  void _emitNotifyError(String message) {
    if (!_notifyErrorsController.isClosed) {
      _notifyErrorsController.add(message);
    }
  }

  void _onNotifyData(dynamic data) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (frame['type']) {
      case 'call.incoming':
        try {
          final incoming = IncomingCall.fromFrame(frame);
          if (!_incomingController.isClosed) {
            _incomingController.add(incoming);
          }
        } catch (_) {
          // Malformed frame — ignore.
        }
      case 'call.cancelled':
        // The caller hung up before the callee answered: dismiss
        // the incoming-call UI for this call right away.
        final callId = frame['call_id'] as String?;
        if (callId != null && !_callCancelledController.isClosed) {
          _callCancelledController.add(callId);
        }
      // The notify endpoint is read-only; anything else is ignored.
    }
  }

  void _onNotifyClosed() {
    final code = _notifyCloseCode;
    _notifyConnected = false;
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _notifyChannel = null;
    if (!_notifyWanted) return;
    _scheduleNotifyReconnect(refreshTokenFirst: code == 4001);
  }

  int? get _notifyCloseCode {
    try {
      return _notifyChannel?.closeCode;
    } catch (_) {
      return null;
    }
  }

  void _scheduleNotifyReconnect({bool refreshTokenFirst = false}) {
    if (!_notifyWanted || _notifyAuthFailed) return;
    if (_notifyAttempts >= _notifyRetryDelays.length) {
      // Escalating budget spent: keep a slow 60s retry so incoming
      // calls never silently die until logout. Say so once.
      if (!_notifySlowMode) {
        _notifySlowMode = true;
        _emitNotifyError(
          'Call notifications unavailable. Retrying in the background.',
        );
      }
      _notifyReconnectTimer?.cancel();
      _notifyReconnectTimer = Timer(_notifySlowRetry, () async {
        if (_notifyWanted) await _connectNotifySocket();
      });
      return;
    }
    final delay = _notifyRetryDelays[_notifyAttempts];
    _notifyAttempts++;
    _notifyReconnectTimer?.cancel();
    _notifyReconnectTimer = Timer(delay, () async {
      if (!_notifyWanted) return;
      if (refreshTokenFirst) {
        // Force a token refresh through the REST client, which
        // refreshes on 401, then read the fresh token.
        try {
          await ApiClient.instance.get('/api/v1/auth/me/');
          final fresh = await TokenStorage.instance.accessToken;
          if (fresh != null && fresh.isNotEmpty) _notifyToken = fresh;
        } catch (_) {
          // Refresh failed — reconnect with the old token; the
          // server will reject it again and the slow retry keeps
          // trying until logout.
        }
      }
      if (_notifyWanted) await _connectNotifySocket();
    });
  }

  /// Route an incoming call that arrived on an open call socket
  /// (the server also delivers `call.incoming` there when the user
  /// is already in a call) to the same stream as the notify socket.
  void _routeIncoming(IncomingCall incoming) {
    if (!_incomingController.isClosed) _incomingController.add(incoming);
  }

  // ------------------------------------------------------------------
  // Starting / answering / declining calls
  // ------------------------------------------------------------------

  /// Start an outgoing call. Connects the call socket, acquires the
  /// camera/mic, and sends `call.initiate`. Returns once the server
  /// confirms with `call.initiated` (state: ringing) — the caller
  /// then waits for the callee to accept (or the ring timeout).
  ///
  /// Throws [ApiException] when the callee does not exist, when the
  /// user tries to call themselves, or when media access fails.
  Future<CallConnection> startCall({
    required String calleeId,
    String callType = 'video',
    String calleeName = '',
  }) async {
    final peerId = calleeId.trim();
    if (peerId.isEmpty) {
      throw const ApiException('Choose a person to call.');
    }
    if (peerId == _myId) {
      throw const ApiException('You cannot call yourself.');
    }
    if (hasActiveCall) {
      throw const ApiException('You are already in a call.');
    }
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('You are not logged in.');
    }
    final connection = CallConnection._outgoing(
      callId: newCallId(),
      peerId: peerId,
      peerName: calleeName,
      callType: callType == 'audio' ? 'audio' : 'video',
      token: token,
      service: this,
    );
    activeCall = connection;
    try {
      await connection._startOutgoing();
    } catch (_) {
      if (activeCall == connection) activeCall = null;
      await connection.dispose();
      rethrow;
    }
    return connection;
  }

  /// Answer an incoming call. Acquires the camera/mic, connects to
  /// the call socket, and sends `call.accept`. Returns once the
  /// server confirms with `call.accepted` (state: connecting) — the
  /// caller then sends the SDP offer.
  Future<CallConnection> answerCall(IncomingCall incoming) async {
    if (hasActiveCall) {
      throw const ApiException('You are already in a call.');
    }
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('You are not logged in.');
    }
    final connection = CallConnection._incoming(
      incoming: incoming,
      token: token,
      service: this,
    );
    activeCall = connection;
    try {
      await connection._startIncoming();
    } catch (_) {
      if (activeCall == connection) activeCall = null;
      await connection.dispose();
      rethrow;
    }
    return connection;
  }

  /// Decline an incoming call. Connects to the call socket, sends
  /// `call.reject`, and closes again. Best-effort: failures are
  /// swallowed — the caller's ring timeout ends the session anyway.
  Future<void> declineCall(IncomingCall incoming) async {
    final token = await TokenStorage.instance.accessToken;
    if (token == null || token.isEmpty) return;
    WebSocketChannel? channel;
    try {
      final uri = Uri.parse(ChatService.wsBase).replace(
        path: '/ws/call/${incoming.callId}/',
        queryParameters: {'token': token},
      );
      channel = WebSocketChannel.connect(uri);
      // Wait for the handshake to complete before rejecting: on a
      // slow network a fixed delay can fire before the socket is
      // open, and the reject is then lost (the caller times out and
      // the call shows as missed instead of rejected).
      await channel.ready.timeout(const Duration(seconds: 10));
      channel.sink.add(jsonEncode({'type': 'call.reject'}));
      // Closing the sink flushes the queued frame before the close
      // handshake, so the reject reaches the server (see finally).
    } catch (_) {
      // Best-effort — the caller's timeout handles the rest.
    } finally {
      try {
        await channel?.sink.close();
      } catch (_) {
        // Already closed.
      }
    }
  }

  // ------------------------------------------------------------------
  // Call history (REST)
  // ------------------------------------------------------------------

  /// GET /api/call/history/ — my 30 most recent calls, newest first.
  Future<List<CallSessionInfo>> fetchHistory() async {
    final res = await ApiClient.instance.get('$_callRest/history/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load call history.'),
        statusCode: res.statusCode,
      );
    }
    final decoded = jsonDecode(res.body);
    final List items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      items = decoded['results'] as List;
    } else {
      return const [];
    }
    return items
        .map((e) => CallSessionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/call/<call_id>/ — details of one call (participants only).
  Future<CallSessionInfo> fetchCall(String callId) async {
    final res = await ApiClient.instance.get('$_callRest/$callId/');
    if (res.statusCode != 200) {
      throw ApiException(
        ApiClient.errorMessage(res, 'Could not load the call.'),
        statusCode: res.statusCode,
      );
    }
    return CallSessionInfo.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }
}

/// One live call: its signalling socket plus the WebRTC peer
/// connection. Created by [CallService.startCall] / [answerCall];
/// the call screen drives it and listens to [states], [errors],
/// [localStream] and [remoteStream].
class CallConnection {
  CallConnection._outgoing({
    required this.callId,
    required this.peerId,
    this.peerName = '',
    required this.callType,
    required String token,
    required CallService service,
  }) : _token = token,
       _service = service,
       isOutgoing = true;

  CallConnection._incoming({
    required IncomingCall incoming,
    required String token,
    required CallService service,
  }) : callId = incoming.callId,
       peerId = incoming.callerId,
       peerName = incoming.callerUsername,
       callType = incoming.callType,
       _token = token,
       _service = service,
       isOutgoing = false;

  final String callId;

  /// The other party's numeric user ID.
  final String peerId;

  /// The other party's username when known (incoming calls: the
  /// email from the `call.incoming` frame; outgoing calls: the name
  /// of the person picked in the user picker, or '' when unknown).
  final String peerName;

  /// 'video' or 'audio'.
  final String callType;

  /// True when I placed the call.
  final bool isOutgoing;

  final String _token;
  final CallService _service;

  /// ICE servers for the peer connection: Google's free public STUN
  /// servers plus Metered Open Relay TURN servers with time-limited
  /// static-auth credentials (see [meteredTurnCredentials]), so
  /// calls can connect across symmetric NATs and mobile data (STUN
  /// alone cannot relay media).
  ///
  /// The old `turn:openrelay.metered.ca` host with the
  /// `openrelayproject` / `openrelayproject` credentials is dead
  /// (the hostname resolves to the 192.0.2.1 TEST-NET sinkhole and
  /// the no-signup credentials are stale) — with TURN dead, phones
  /// behind carrier NATs never established a media path (ICE stuck
  /// in "checking", 0 RTP frames). The static-auth host
  /// `staticauth.openrelay.metered.ca` replaces it; the `?transport=
  /// tcp` variants are the most firewall-proof (443 TCP looks like
  /// ordinary HTTPS traffic). Credentials expire an hour after the
  /// call starts, which is far longer than any call setup takes.
  /// [expiryUnix] is injectable for tests; pass null for "now + 1h".
  static List<Map<String, dynamic>> iceServers({int? expiryUnix}) {
    final expiry =
        expiryUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final creds = meteredTurnCredentials(expiryUnix: expiry);
    Map<String, dynamic> turn(String url) => <String, dynamic>{
      'urls': url,
      'username': creds['username'],
      'credential': creds['credential'],
    };
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      turn('turn:staticauth.openrelay.metered.ca:80'),
      turn('turn:staticauth.openrelay.metered.ca:443'),
      turn('turn:staticauth.openrelay.metered.ca:80?transport=tcp'),
      turn('turn:staticauth.openrelay.metered.ca:443?transport=tcp'),
    ];
  }

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallState _state = CallState.idle;
  CallState get state => _state;

  /// Why the call ended — set before [CallState.ended] is emitted.
  /// One of [CallEndReason].
  String endReason = CallEndReason.ended;

  /// Human-readable message for a [CallState.failed] ending, set by
  /// [_fail] (e.g. the ICE watchdog's "Couldn't establish a media
  /// connection"). The call screen shows this instead of a generic
  /// "Call failed" so the user learns what actually went wrong.
  String? failureMessage;

  /// True once the server confirmed a session exists (initiated /
  /// accepted), i.e. `call.end` is meaningful.
  bool _sessionStarted = false;

  /// True once setRemoteDescription succeeded; ICE candidates that
  /// arrive earlier are queued in [_pendingCandidates].
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Timer? _ringTimer;

  /// ICE watchdog: started when the remote description is set; if
  /// ICE is still not connected after [_iceWatchdogTimeout] the call
  /// fails honestly instead of showing "Connected" forever.
  Timer? _iceWatchdog;
  static const _iceWatchdogTimeout = Duration(seconds: 15);

  /// Grace timer for a transient ICE "disconnected": the connection
  /// may recover on its own, so the call only ends if it is still
  /// down after [_disconnectGrace].
  Timer? _disconnectGraceTimer;
  static const _disconnectGrace = Duration(seconds: 5);

  /// The outgoing ringback tone, played only once the callee's
  /// client is actually ringing (`call.ringing`) — never before,
  /// since the callee may be offline. Stopped on accept, end,
  /// failure and every cleanup path.
  AudioPlayer? _ringbackPlayer;

  bool _disposed = false;

  Completer<void>? _initiateCompleter;
  Completer<void>? _acceptCompleter;

  final _statesController = StreamController<CallState>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _localStreamController = StreamController<MediaStream>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _peerRingingController = StreamController<bool>.broadcast();

  Stream<CallState> get states => _statesController.stream;
  Stream<String> get errors => _errorsController.stream;

  /// True once the server sent `call.ringing` for this call — the
  /// callee's client was notified and is ringing. The call screen
  /// switches its status text from "Calling…" to "Ringing…" on this.
  /// Fires on [peerRingingChanges]; only meaningful for outgoing calls.
  bool peerRinging = false;
  Stream<bool> get peerRingingChanges => _peerRingingController.stream;

  /// Fires once with my camera/mic stream (for the local preview).
  Stream<MediaStream> get localStream => _localStreamController.stream;

  /// Fires once with the peer's stream (for the remote video).
  Stream<MediaStream> get remoteStream => _remoteStreamController.stream;

  MediaStream? get currentLocalStream => _localStream;
  MediaStream? get currentRemoteStream => _remoteStream;

  bool get isVideoCall => callType == 'video';

  /// Display name for the peer.
  String get peerDisplayName =>
      peerName.isNotEmpty ? peerName : 'User #$peerId';

  bool _muted = false;
  bool get isMuted => _muted;

  bool _speakerOn = false;
  bool get isSpeakerOn => _speakerOn;

  bool _videoEnabled = true;
  bool get isVideoEnabled => _videoEnabled;

  Uri get _wsUri => Uri.parse(ChatService.wsBase)
      .replace(path: '/ws/call/$callId/', queryParameters: {'token': _token});

  // ------------------------------------------------------------------
  // Setup: outgoing / incoming
  // ------------------------------------------------------------------

  Future<void> _startOutgoing() async {
    await _connectSocket();
    await _acquireMedia();
    _send({
      'type': 'call.initiate',
      'callee_id': peerId,
      'call_type': callType,
    });
    final completer = Completer<void>();
    _initiateCompleter = completer;
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw const ApiException(
          'The server did not answer. Please try again.',
        );
      },
    );
    _setState(CallState.ringing);
    _startRingTimer();
  }

  Future<void> _startIncoming() async {
    // Get media first: if the camera/mic is unavailable there is no
    // point accepting the call.
    await _acquireMedia();
    await _connectSocket();
    _send({'type': 'call.accept'});
    final completer = Completer<void>();
    _acceptCompleter = completer;
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw const ApiException(
          'The server did not answer. Please try again.',
        );
      },
    );
    // call.accepted was received; the caller now sends the SDP offer.
    _setState(CallState.connecting);
    await _createPeerConnection();
  }

  /// Connects the call socket and waits for the handshake to
  /// complete, so the first frame (`call.initiate` / `call.accept`)
  /// is never sent on a socket that is still connecting. Throws
  /// [ApiException] when the handshake does not complete in time.
  Future<void> _connectSocket() async {
    final channel = WebSocketChannel.connect(_wsUri);
    _channel = channel;
    _subscription = channel.stream.listen(
      _onData,
      onError: (_) => _onSocketClosed(),
      onDone: _onSocketClosed,
      cancelOnError: false,
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException(
        'Could not connect to the call server. Please try again.',
      );
    }
  }

  Future<void> _acquireMedia() async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideoCall
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      _localStream = stream;
      if (!_localStreamController.isClosed) {
        _localStreamController.add(stream);
      }
      // Video calls default to the loudspeaker (standard pattern —
      // the phone is held away from the ear); voice calls stay on
      // the earpiece. The manual speaker toggle still works.
      if (isVideoCall) await setSpeakerOn(true);
    } catch (e) {
      throw ApiException(
        'Could not access the camera/microphone. '
        'Please allow the permission and try again.',
      );
    }
  }

  // ------------------------------------------------------------------
  // Signalling frames
  // ------------------------------------------------------------------

  void _onData(dynamic data) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (frame['type'] as String?) {
      case 'call.initiated':
        _sessionStarted = true;
        _complete(_initiateCompleter);
      case 'call.accepted':
        _sessionStarted = true;
        _complete(_acceptCompleter);
        _onAccepted();
      case 'call.ringing':
        // The callee's client was notified and is ringing: show
        // "Ringing…" (not "Calling…") and start the ringback tone —
        // only now, since before this the callee may be offline.
        if (!peerRinging) {
          peerRinging = true;
          if (!_peerRingingController.isClosed) {
            _peerRingingController.add(true);
          }
          if (isOutgoing) _startRingback();
        }
      case 'call.rejected':
        _finishWithReason(
          frame['reason'] == 'busy'
              ? CallEndReason.busy
              : CallEndReason.declined,
        );
      case 'call.ended':
        _finishWithReason(CallEndReason.ended);
      case 'peer_disconnected':
        // The peer's app died mid-call: end the survivor's screen
        // instead of leaving it open with the timer running forever.
        _finishWithReason(CallEndReason.connectionLost);
      case 'call.peer_connected':
        // The peer joined the call group (they are about to accept
        // or reject). No state change needed.
        break;
      case 'call.sdp_offer':
        _onSdpOffer(frame);
      case 'call.sdp_answer':
        _onSdpAnswer(frame);
      case 'call.ice_candidate':
        _onIceCandidate(frame);
      case 'call.incoming':
        // A second call arrived while in this call — route it to the
        // app-level incoming stream.
        try {
          _service._routeIncoming(IncomingCall.fromFrame(frame));
        } catch (_) {
          // Malformed frame — ignore.
        }
      case 'error':
        _onErrorFrame(frame);
    }
  }

  void _onErrorFrame(Map<String, dynamic> frame) {
    final detail = frame['detail'] as String? ?? 'Something went wrong.';
    final code = frame['code'] as String?;
    // Fail the pending setup step, if any, so startCall/answerCall
    // throw with the server's message.
    if (_initiateCompleter != null && !_initiateCompleter!.isCompleted) {
      _initiateCompleter!.completeError(ApiException(detail));
      _initiateCompleter = null;
      return;
    }
    if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
      _acceptCompleter!.completeError(ApiException(detail));
      _acceptCompleter = null;
      return;
    }
    // Mid-call errors (e.g. a signal sent in the wrong state).
    if (code == 'not_connected') return; // Stale signal — ignore.
    if (!_errorsController.isClosed) _errorsController.add(detail);
  }

  void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
    if (identical(completer, _initiateCompleter)) _initiateCompleter = null;
    if (identical(completer, _acceptCompleter)) _acceptCompleter = null;
  }

  /// The call was accepted (both sides receive this broadcast).
  /// The caller creates the peer connection and sends the SDP offer;
  /// the callee already created theirs in [_startIncoming].
  void _onAccepted() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _stopRingback();
    if (_state == CallState.ended || _state == CallState.failed) return;
    _setState(CallState.connecting);
    if (isOutgoing) {
      _createPeerConnection().then((_) => _sendOffer()).catchError((_) {
        _fail('Could not start the call. Please try again.');
      });
    }
  }

  /// Start the outgoing ringback tone (looping), owned by this
  /// connection: it plays only while the peer is ringing and stops
  /// on accept, end, failure and every cleanup path.
  Future<void> _startRingback() async {
    if (_ringbackPlayer != null || _disposed) return;
    try {
      final player = AudioPlayer();
      _ringbackPlayer = player;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('ringback.mp3'));
    } catch (_) {
      // No audio on this device — the call still works.
      _ringbackPlayer = null;
    }
  }

  Future<void> _stopRingback() async {
    final player = _ringbackPlayer;
    _ringbackPlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // Already stopped.
    }
    try {
      await player.dispose();
    } catch (_) {
      // Already disposed.
    }
  }

  // ------------------------------------------------------------------
  // WebRTC
  // ------------------------------------------------------------------

  Future<void> _createPeerConnection() async {
    if (_pc != null) return;
    final pc = await createPeerConnection({'iceServers': iceServers()});
    _pc = pc;

    pc.onIceCandidate = (candidate) {
      // Null candidate = end of gathering.
      if (candidate.candidate == null) return;
      _send({'type': 'call.ice_candidate', 'candidate': candidate.toMap()});
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) _setRemoteStream(event.streams.first);
    };
    pc.onAddStream = (stream) => _setRemoteStream(stream);
    pc.onIceConnectionState = (state) {
      // Log every ICE transition: with no WebRTC in the dev VM these
      // logs are the only diagnosis for "no voice" reports.
      debugPrint('[Call $callId] ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // `connected` comes ONLY from here: onTrack fires on SDP
        // exchange with zero media, so it must never set it.
        _iceWatchdog?.cancel();
        _iceWatchdog = null;
        _disconnectGraceTimer?.cancel();
        _disconnectGraceTimer = null;
        _setState(CallState.connected);
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // Transient drops recover on their own (network switch, ...),
        // so give it a few seconds before ending the call.
        _disconnectGraceTimer?.cancel();
        _disconnectGraceTimer = Timer(_disconnectGrace, () {
          if (_disposed) return;
          if (_state == CallState.ended || _state == CallState.failed) return;
          _finishWithReason(CallEndReason.connectionLost);
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (_state == CallState.connected) {
          // Mid-call ICE failure is terminal — end honestly instead
          // of leaving a dead call screen up.
          _finishWithReason(CallEndReason.connectionLost);
        } else if (!_errorsController.isClosed) {
          _errorsController.add(
            'Connection failed. The call may not work across some '
            'networks without a TURN server.',
          );
        }
        // Before `connected`, the ICE watchdog ends the call with
        // its honest message if media never arrives.
      }
    };

    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    }
  }

  Future<void> _sendOffer() async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({'type': 'call.sdp_offer', 'sdp': offer.toMap()});
  }

  /// Start the ICE watchdog: if ICE is still not connected
  /// [_iceWatchdogTimeout] after the remote description was set, the
  /// media path never came up (typically a NAT/TURN problem) — fail
  /// the call with an honest message instead of showing "Connected"
  /// (or "Connecting…") forever.
  void _startIceWatchdog() {
    _iceWatchdog?.cancel();
    _iceWatchdog = Timer(_iceWatchdogTimeout, () {
      if (_disposed) return;
      if (_state == CallState.ended || _state == CallState.failed) return;
      if (_state == CallState.connected) return;
      _fail("Couldn't establish a media connection — check your network");
    });
  }

  Future<void> _onSdpOffer(Map<String, dynamic> frame) async {
    if (_disposed) return;
    final raw = frame['sdp'];
    if (raw is! Map<String, dynamic>) return;
    try {
      await _createPeerConnection();
      final pc = _pc!;
      await pc.setRemoteDescription(
        RTCSessionDescription(raw['sdp'] as String?, raw['type'] as String?),
      );
      _remoteDescriptionSet = true;
      _startIceWatchdog();
      await _flushPendingCandidates();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _send({'type': 'call.sdp_answer', 'sdp': answer.toMap()});
    } catch (_) {
      _fail('Could not set up the call. Please try again.');
    }
  }

  Future<void> _onSdpAnswer(Map<String, dynamic> frame) async {
    if (_disposed) return;
    final raw = frame['sdp'];
    if (raw is! Map<String, dynamic>) return;
    final pc = _pc;
    if (pc == null) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(raw['sdp'] as String?, raw['type'] as String?),
      );
      _remoteDescriptionSet = true;
      _startIceWatchdog();
      await _flushPendingCandidates();
    } catch (_) {
      _fail('Could not set up the call. Please try again.');
    }
  }

  Future<void> _onIceCandidate(Map<String, dynamic> frame) async {
    final raw = frame['candidate'];
    if (raw is! Map<String, dynamic>) return;
    final candidate = RTCIceCandidate(
      raw['candidate'] as String?,
      raw['sdpMid'] as String?,
      raw['sdpMLineIndex'] as int?,
    );
    if (candidate.candidate == null) return;
    if (!_remoteDescriptionSet) {
      // Candidates that arrive before the remote description must
      // wait — adding them now throws.
      _pendingCandidates.add(candidate);
      return;
    }
    try {
      await _pc?.addCandidate(candidate);
    } catch (_) {
      // A stale candidate — safe to ignore.
    }
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _pc;
    if (pc == null || _pendingCandidates.isEmpty) return;
    final queued = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in queued) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {
        // Stale candidate — safe to ignore.
      }
    }
  }

  void _setRemoteStream(MediaStream stream) {
    if (_remoteStream != null) return; // Already have one — dedupe.
    _remoteStream = stream;
    if (!_remoteStreamController.isClosed) {
      _remoteStreamController.add(stream);
    }
    // Deliberately no state transition here: onTrack fires on SDP
    // exchange with ZERO media (observed live: onTrack with ICE
    // state "new"), so `connected` must come only from the ICE
    // connected/completed callback — otherwise the screen shows
    // "Connected" while no voice flows.
  }

  // ------------------------------------------------------------------
  // In-call controls
  // ------------------------------------------------------------------

  /// Mute/unmute my microphone.
  void setMuted(bool muted) {
    _muted = muted;
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  /// Turn my camera on/off (video calls). The peer sees a frozen or
  /// black frame while off.
  void setVideoEnabled(bool enabled) {
    _videoEnabled = enabled;
    for (final track in _localStream?.getVideoTracks() ?? const []) {
      track.enabled = enabled;
    }
  }

  /// Route audio to the loudspeaker (or back to the earpiece).
  Future<void> setSpeakerOn(bool on) async {
    _speakerOn = on;
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {
      // Not supported on this device — ignore.
    }
  }

  /// Switch between front and back camera (video calls).
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? const [];
    if (videoTracks.isEmpty) return;
    try {
      await Helper.switchCamera(videoTracks.first);
    } catch (_) {
      if (!_errorsController.isClosed) {
        _errorsController.add('Could not switch the camera.');
      }
    }
  }

  // ------------------------------------------------------------------
  // Ring timeout, ending, teardown
  // ------------------------------------------------------------------

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(CallService.ringTimeout, () {
      // Nobody answered. End the session server-side so it does not
      // stay RINGING forever (the backend has no timeout of its own).
      unawaited(endCall(reason: CallEndReason.noAnswer));
    });
  }

  void _onSocketClosed() {
    if (_disposed) return;
    final code = _closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_state == CallState.ended || _state == CallState.failed) return;
    if (code == 4001) {
      _fail('Session expired. Please log in again and retry the call.');
      return;
    }
    if (code == 4003) {
      _fail('You are not a participant of this call.');
      return;
    }
    if (code == 4008) {
      // The call is already over server-side. If accept/initiate is
      // still pending, fail it now with the honest reason — otherwise
      // the caller/callee waits the full 15s timeout and gets the
      // misleading "The server did not answer."
      _failPendingSetup(
        _acceptCompleter != null
            ? 'The caller hung up.'
            : 'The call ended.',
      );
      _finishWithReason(CallEndReason.ended);
      return;
    }
    // Unexpected drop mid-call: the peer connection cannot be
    // resumed without renegotiation, so end the call. Tell the
    // server first (best-effort) so the session does not stay live
    // and the peer is not left hanging, then clean up locally.
    unawaited(_endOnServerThenFinish());
  }

  Future<void> _endOnServerThenFinish() async {
    await _endSessionOnServer();
    _finishWithReason(CallEndReason.connectionLost);
  }

  /// End the session server-side via REST, for when the signalling
  /// socket is already gone. Best-effort and capped at 10s so a slow
  /// backend never strands the local UI; any failure (offline,
  /// already ended) is swallowed and local cleanup still proceeds.
  Future<void> _endSessionOnServer() async {
    if (!_sessionStarted) return;
    try {
      await ApiClient.instance
          .post('${CallService._callRest}/$callId/end/')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or already ended — local cleanup still proceeds.
    }
  }

  int? get _closeCode {
    try {
      return _channel?.closeCode;
    } catch (_) {
      return null;
    }
  }

  /// End the call (or cancel the outgoing ring). Sends `call.end`
  /// to the server so the peer is notified, then releases everything.
  Future<void> endCall({String reason = CallEndReason.ended}) async {
    if (_disposed) return;
    endReason = reason;
    if (_sessionStarted) {
      try {
        _send({'type': 'call.end'});
      } catch (_) {
        // Socket already gone — nothing to tell.
      }
      // Give the frame a moment to flush before closing the socket.
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _cleanup();
    _setState(CallState.ended);
  }

  /// Fail any still-pending setup step (`call.initiate` /
  /// `call.accept`) so `startCall`/`answerCall` throw now instead of
  /// hanging until the 15s timeout. Called with the specific reason
  /// by [_onSocketClosed] (4008) and [_fail], and with a generic
  /// message by [_cleanup] as a backstop — a completer must never be
  /// dropped uncompleted.
  void _failPendingSetup([String message = 'The call ended.']) {
    if (_initiateCompleter != null && !_initiateCompleter!.isCompleted) {
      _initiateCompleter!.completeError(ApiException(message));
    }
    if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
      _acceptCompleter!.completeError(ApiException(message));
    }
    _initiateCompleter = null;
    _acceptCompleter = null;
  }

  void _finishWithReason(String reason) {
    if (_state == CallState.ended || _state == CallState.failed) return;
    endReason = reason;
    unawaited(_cleanup());
    _setState(CallState.ended);
  }

  void _fail(String message) {
    if (_state == CallState.ended || _state == CallState.failed) return;
    endReason = CallEndReason.failed;
    failureMessage = message;
    if (!_errorsController.isClosed) _errorsController.add(message);
    _failPendingSetup(message);
    unawaited(_cleanup());
    _setState(CallState.failed);
  }

  void _send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (_disposed || channel == null) {
      throw const ApiException('Not connected.');
    }
    channel.sink.add(jsonEncode(frame));
  }

  void _setState(CallState next) {
    if (_disposed || _state == next) return;
    // Terminal states are final.
    if (_state == CallState.ended || _state == CallState.failed) return;
    _state = next;
    if (!_statesController.isClosed) _statesController.add(next);
  }

  Future<void> _cleanup() async {
    _ringTimer?.cancel();
    _ringTimer = null;
    _iceWatchdog?.cancel();
    _iceWatchdog = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    await _stopRingback();
    _failPendingSetup();
    _pendingCandidates.clear();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Already closed.
    }
    _channel = null;
    try {
      await _pc?.close();
    } catch (_) {
      // Already closed.
    }
    _pc = null;
    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        try {
          track.stop();
        } catch (_) {
          // Already stopped.
        }
      }
      try {
        await local.dispose();
      } catch (_) {
        // Already disposed.
      }
      _localStream = null;
    }
    _remoteStream = null;
    if (_service.activeCall == this) _service.activeCall = null;
  }

  /// Release everything. If the call is still active, the server is
  /// told (best-effort, no flush delay) before the socket closes.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_sessionStarted &&
        _state != CallState.ended &&
        _state != CallState.failed) {
      try {
        _send({'type': 'call.end'});
      } catch (_) {
        // Socket already gone.
      }
    }
    await _cleanup();
    await _statesController.close();
    await _errorsController.close();
    await _localStreamController.close();
    await _remoteStreamController.close();
    await _peerRingingController.close();
  }
}
