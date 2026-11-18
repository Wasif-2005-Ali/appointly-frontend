import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../app_state.dart';
import '../services/api_client.dart';
import '../services/call_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import 'call_history_screen.dart';
import 'user_picker_screen.dart';

/// Initials for an avatar from a display name ("Test B" → "TB",
/// single word → first letter). Shared by the call screen and the
/// incoming-call screen.
String initialsFor(String name) {
  final parts = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Full-screen voice/video call.
///
/// Two ways in:
/// - [CallScreen.outgoing] — I am calling [calleeId] (their numeric
///   user ID). The screen connects the call socket, rings the peer,
///   and runs the WebRTC offer/answer exchange once they accept.
/// - [CallScreen.incoming] — I accepted an [IncomingCall]. The screen
///   connects the call socket, accepts, and answers the SDP offer.
///
/// Pops with a `String?` result: a message to show on the previous
/// screen (`'Call declined.'`, `'No answer.'`, …), or null when the
/// call ended cleanly.
class CallScreen extends StatefulWidget {
  final String? calleeId;
  final String calleeName;
  final IncomingCall? incoming;
  final String callType;

  const CallScreen.outgoing({
    super.key,
    required this.calleeId,
    this.calleeName = '',
    this.callType = 'video',
  }) : incoming = null;

  const CallScreen.incoming({super.key, required this.incoming})
    : calleeId = null,
      calleeName = '',
      callType = 'video';

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  CallConnection? _connection;
  StreamSubscription<CallState>? _statesSub;
  StreamSubscription<String>? _errorsSub;
  StreamSubscription<MediaStream>? _localSub;
  StreamSubscription<MediaStream>? _remoteSub;
  StreamSubscription<bool>? _peerRingingSub;
  DateTime? _connectedAt;

  bool _popped = false;
  bool _startingFailed = false;

  bool get _isVideo {
    final incoming = widget.incoming;
    if (incoming != null) return incoming.callType == 'video';
    return widget.callType == 'video';
  }

  String get _peerName {
    final connection = _connection;
    if (connection != null) return connection.peerDisplayName;
    final incoming = widget.incoming;
    if (incoming != null) return incoming.displayName;
    return 'User #${widget.calleeId ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    _beginCall();
  }

  Future<void> _beginCall() async {
    try {
      final connection = widget.incoming != null
          ? await CallService.instance.answerCall(widget.incoming!)
          : await CallService.instance.startCall(
              calleeId: widget.calleeId!,
              calleeName: widget.calleeName,
              callType: widget.callType,
            );
      if (!mounted) {
        await connection.dispose();
        return;
      }
      _connection = connection;
      _listen(connection);
      // The local stream may already be available (acquired during setup).
      final local = connection.currentLocalStream;
      if (local != null) _localRenderer.srcObject = local;
      setState(() {});
    } on ApiException catch (e) {
      if (!mounted) return;
      _startingFailed = true;
      Navigator.pop(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _startingFailed = true;
      Navigator.pop(context, 'Could not start the call. Please try again.');
    }
  }

  void _listen(CallConnection connection) {
    _statesSub = connection.states.listen((state) {
      if (!mounted) return;
      if (state == CallState.connected && _connectedAt == null) {
        _connectedAt = DateTime.now();
      }
      if (state == CallState.ended || state == CallState.failed) {
        _popWithResult();
        return;
      }
      setState(() {});
    });
    // The peer started ringing: "Calling…" becomes "Ringing…".
    _peerRingingSub = connection.peerRingingChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _errorsSub = connection.errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
    _localSub = connection.localStream.listen((stream) {
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    });
    _remoteSub = connection.remoteStream.listen((stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() {});
    });
  }

  void _popWithResult() {
    if (_popped) return;
    _popped = true;
    final connection = _connection;
    String? message;
    if (connection?.state == CallState.failed) {
      // The honest reason (e.g. the ICE watchdog's media-connection
      // message) beats a generic "Call failed".
      message = connection?.failureMessage ?? 'Call failed. Please try again.';
    } else {
      switch (connection?.endReason) {
        case CallEndReason.declined:
          message = 'Call declined.';
        case CallEndReason.busy:
          message = 'User is busy.';
        case CallEndReason.noAnswer:
          message = 'No answer.';
        case CallEndReason.connectionLost:
          message = 'Connection lost.';
        default:
          // Clean end — confirm it with the duration, so the call
          // does not just vanish without feedback.
          message = _connectedAt == null
              ? null
              : 'Call ended • $_elapsedText';
      }
    }
    if (mounted) Navigator.pop(context, message);
  }

  String get _statusText {
    final connection = _connection;
    if (connection == null) {
      return _startingFailed ? 'Could not start the call' : 'Starting call…';
    }
    switch (connection.state) {
      case CallState.ringing:
        if (!connection.isOutgoing) return 'Connecting…';
        return connection.peerRinging ? 'Ringing…' : 'Calling…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.connected:
        return _elapsedText;
      case CallState.ended:
      case CallState.failed:
        return 'Call ended';
      case CallState.idle:
        return 'Starting call…';
    }
  }

  /// Status line for the current state. While connected this is the
  /// live duration rendered by [_CallDurationText], which ticks
  /// itself every second — so the 1s timer rebuilds only that tiny
  /// text widget, not the whole call screen (incl. the RTCVideoViews).
  Widget _buildStatusText(TextStyle style) {
    final connection = _connection;
    if (connection?.state == CallState.connected && _connectedAt != null) {
      return _CallDurationText(connectedAt: _connectedAt!, style: style);
    }
    return Text(_statusText, style: style);
  }

  String get _elapsedText {
    final start = _connectedAt;
    if (start == null) return 'Connected';
    final elapsed = DateTime.now().difference(start);
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall() async {
    final connection = _connection;
    if (connection == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await connection.endCall();
    // The states listener pops the screen once `ended` is emitted.
  }

  @override
  void dispose() {
    _statesSub?.cancel();
    _errorsSub?.cancel();
    _localSub?.cancel();
    _remoteSub?.cancel();
    _peerRingingSub?.cancel();
    // Ends the call server-side if it is still active.
    unawaited(_connection?.dispose());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // System back must end the call explicitly (same as pressing
    // End), not pop the screen and hang up silently: the vetoed pop
    // runs [_endCall], and the states listener pops the screen once
    // the call actually ends. (Programmatic Navigator.pop is not
    // vetoed by PopScope — only the system back gesture is.)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _isVideo ? _buildVideoLayout() : _buildAudioLayout(),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Video layout
  // ------------------------------------------------------------------

  Widget _buildVideoLayout() {
    final remoteReady = _remoteRenderer.srcObject != null;
    return Stack(
      children: [
        // Remote video, full screen (placeholder until media arrives).
        Positioned.fill(
          child: remoteReady
              ? RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : _buildWaitingPlaceholder(),
        ),
        // Peer name + status. Only shown once remote video arrives —
        // until then the waiting placeholder below already shows the
        // name (showing both would render it twice while ringing).
        if (remoteReady)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // Live status under the peer name — the call duration
                // once connected (it was a static "Video call" here,
                // so the timer was invisible on video calls).
                _buildStatusText(
                  const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        // Local preview, top-right corner.
        Positioned(
          top: 76,
          right: 16,
          child: Container(
            width: 110,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _localRenderer.srcObject != null
                  ? RTCVideoView(_localRenderer, mirror: true)
                  : const Center(
                      child: Icon(Icons.videocam_off, color: Colors.white54),
                    ),
            ),
          ),
        ),
        // Controls.
        Positioned(bottom: 32, left: 0, right: 0, child: _buildControls()),
      ],
    );
  }

  Widget _buildWaitingPlaceholder() {
    return Container(
      color: const Color(0xFF101828),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.white12,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _peerName,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 6),
            _buildStatusText(
              const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  String get _initials => initialsFor(_peerName);

  // ------------------------------------------------------------------
  // Audio-only layout
  // ------------------------------------------------------------------

  Widget _buildAudioLayout() {
    return Column(
      children: [
        const Spacer(),
        CircleAvatar(
          radius: 64,
          backgroundColor: Colors.white12,
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _peerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildStatusText(
          const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        const SizedBox(height: 8),
        const Text(
          'Voice call',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
        const Spacer(),
        _buildControls(),
        const SizedBox(height: 32),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Controls
  // ------------------------------------------------------------------

  Widget _buildControls() {
    final connection = _connection;
    final muted = connection?.isMuted ?? false;
    final speakerOn = connection?.isSpeakerOn ?? false;
    final videoEnabled = connection?.isVideoEnabled ?? true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _controlButton(
          icon: muted ? Icons.mic_off : Icons.mic,
          label: muted ? 'Unmute' : 'Mute',
          active: muted,
          onPressed: connection == null
              ? null
              : () {
                  connection.setMuted(!muted);
                  setState(() {});
                },
        ),
        if (_isVideo)
          _controlButton(
            icon: videoEnabled ? Icons.videocam : Icons.videocam_off,
            label: videoEnabled ? 'Camera off' : 'Camera on',
            active: !videoEnabled,
            onPressed: connection == null
                ? null
                : () {
                    connection.setVideoEnabled(!videoEnabled);
                    setState(() {});
                  },
          ),
        _controlButton(
          icon: speakerOn ? Icons.volume_up : Icons.hearing,
          label: 'Speaker',
          active: speakerOn,
          onPressed: connection == null
              ? null
              : () async {
                  await connection.setSpeakerOn(!speakerOn);
                  if (mounted) setState(() {});
                },
        ),
        if (_isVideo)
          _controlButton(
            icon: Icons.switch_camera,
            label: 'Switch',
            onPressed: connection == null
                ? null
                : () => connection.switchCamera(),
          ),
        _controlButton(
          icon: Icons.call_end,
          label: 'End',
          backgroundColor: Colors.red,
          onPressed: _endCall,
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    bool active = false,
    Color? backgroundColor,
    required VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor:
              backgroundColor ?? (active ? Colors.white : Colors.white24),
          child: IconButton(
            icon: Icon(
              icon,
              color: backgroundColor != null
                  ? Colors.white
                  : (active ? Colors.black : Colors.white),
            ),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

/// Live call duration ("04:32") that ticks itself every second, so
/// the 1s timer rebuilds only this text — not the whole call screen
/// (and its RTCVideoViews).
class _CallDurationText extends StatefulWidget {
  final DateTime connectedAt;
  final TextStyle style;

  const _CallDurationText({required this.connectedAt, required this.style});

  @override
  State<_CallDurationText> createState() => _CallDurationTextState();
}

class _CallDurationTextState extends State<_CallDurationText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.connectedAt);
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Text('$m:$s', style: widget.style);
  }
}

/// Start a call: pick the other person from the user directory and
/// choose video or voice, then open [CallScreen].
class StartCallScreen extends StatefulWidget {
  const StartCallScreen({super.key});

  @override
  State<StartCallScreen> createState() => _StartCallScreenState();
}

class _StartCallScreenState extends State<StartCallScreen> {
  AppUser? _selectedUser;
  String _callType = 'video';

  Future<void> _pickUser() async {
    final user = await Navigator.push<AppUser?>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const UserPickerScreen(title: 'Choose a person to call'),
      ),
    );
    if (user != null && mounted) setState(() => _selectedUser = user);
  }

  Future<void> _startCall() async {
    final user = _selectedUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a person to call.')));
      return;
    }
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen.outgoing(
          calleeId: user.id.toString(),
          calleeName: user.fullName,
          callType: _callType,
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedUser;
    final heroColors = AppStateProvider.of(context).heroGradient;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient hero, matching the dashboard's header.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: heroColors,
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.history_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Call history',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CallHistoryScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'New Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Call another Appointly user. They need to be '
                        'online in the app to receive the call.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
            // Person picker (replaces the old numeric user-ID field).
            GestureDetector(
              onTap: _pickUser,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline
                        .withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      child: selected == null
                          ? const Icon(Icons.person_add_alt_rounded, size: 20)
                          : Text(selected.initials),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: selected == null
                          ? const Text('Choose a person…')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (selected.email.isNotEmpty)
                                  Text(
                                    selected.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                              ],
                            ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'video',
                  label: Text('Video'),
                  icon: Icon(Icons.videocam),
                ),
                ButtonSegment(
                  value: 'audio',
                  label: Text('Voice'),
                  icon: Icon(Icons.call),
                ),
              ],
              selected: {_callType},
              onSelectionChanged: (selection) {
                setState(() => _callType = selection.first);
              },
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _startCall,
              icon: const Icon(Icons.call),
              label: const Text('Call'),
            ),
                ],
              ),
            ),
          ),
          ],
        ),
      );
  }
}

/// Full-screen incoming-call screen (WhatsApp-style), shown by the
/// app root when a `call.incoming` frame arrives (see `main.dart`).
///
/// Returns `true` when the user accepts, `false` when they decline,
/// and null when the screen times out after 30 seconds (matching the
/// caller's ring timeout — the server keeps the call RINGING until
/// the caller ends it, so the screen must go away on its own) or the
/// caller cancels (`call.cancelled`, dismissed from `main.dart`).
///
/// While shown, the ringtone loops and the phone vibrates every ~2s.
/// Both stop on EVERY exit path: accept, decline, timeout, cancel,
/// and the app backgrounding (see [didChangeAppLifecycleState]).
/// The back button cannot dismiss the screen (PopScope).
class IncomingCallScreen extends StatefulWidget {
  final IncomingCall incoming;

  const IncomingCallScreen({super.key, required this.incoming});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _timeout;
  Timer? _vibrationTimer;
  AudioPlayer? _ringtonePlayer;
  late final AnimationController _pulseController;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2000),
        )..repeat();
    _timeout = Timer(CallService.ringTimeout, () => _pop(null));
    _startAlerting();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding stops the ringtone + vibration (the screen is
    // hidden); coming back resumes them while the call still rings.
    if (!mounted || _popped) return;
    if (state == AppLifecycleState.resumed) {
      _startAlerting();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopAlerting();
    }
  }

  /// Start the looping ringtone + periodic vibration. Idempotent —
  /// safe to call again on resume.
  Future<void> _startAlerting() async {
    if (_popped || !mounted) return;
    if (_ringtonePlayer == null) {
      try {
        final player = AudioPlayer();
        _ringtonePlayer = player;
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(AssetSource('ringtone.mp3'));
      } catch (_) {
        // No audio on this device — vibration still alerts.
        _ringtonePlayer = null;
      }
    }
    _vibrationTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.vibrate();
    });
    HapticFeedback.vibrate();
  }

  Future<void> _stopAlerting() async {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    final player = _ringtonePlayer;
    _ringtonePlayer = null;
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

  void _pop(bool? accepted) {
    if (_popped) return;
    _popped = true;
    unawaited(_stopAlerting());
    if (mounted) Navigator.pop(context, accepted);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    _pulseController.dispose();
    unawaited(_stopAlerting());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = widget.incoming;
    final isVideo = incoming.callType == 'video';
    final heroColors = AppStateProvider.of(context).heroGradient;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: heroColors,
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  color: Colors.white70,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  isVideo ? 'Incoming video call' : 'Incoming voice call',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const Spacer(),
                // Pulsing rings around the caller's avatar.
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _pulseRing((_pulseController.value + 0.0) % 1.0),
                          _pulseRing((_pulseController.value + 0.5) % 1.0),
                          child!,
                        ],
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    child: Text(
                      initialsFor(incoming.displayName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    incoming.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'wants to talk to you',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _answerButton(
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        backgroundColor: AppColors.danger,
                        onPressed: () => _pop(false),
                      ),
                      _answerButton(
                        icon: Icons.call_rounded,
                        label: 'Accept',
                        backgroundColor: AppColors.green,
                        onPressed: () => _pop(true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One expanding, fading ring of the pulsing avatar animation.
  Widget _pulseRing(double progress) {
    return Container(
      width: 112 + 72 * progress,
      height: 112 + 72 * progress,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45 * (1 - progress)),
          width: 2,
        ),
      ),
    );
  }

  Widget _answerButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: backgroundColor,
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}
