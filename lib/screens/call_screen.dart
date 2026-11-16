import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/api_client.dart';
import '../services/call_service.dart';
import '../services/user_service.dart';
import 'user_picker_screen.dart';

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
  Timer? _durationTimer;
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
        _durationTimer?.cancel();
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
      if (state == CallState.ended || state == CallState.failed) {
        _popWithResult();
        return;
      }
      setState(() {});
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
      message = 'Call failed. Please try again.';
    } else {
      switch (connection?.endReason) {
        case CallEndReason.declined:
          message = 'Call declined.';
        case CallEndReason.noAnswer:
          message = 'No answer.';
        case CallEndReason.connectionLost:
          message = 'Connection lost.';
        default:
          message = null; // Clean end — nothing to say.
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
        return connection.isOutgoing ? 'Calling…' : 'Connecting…';
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
    _durationTimer?.cancel();
    // Ends the call server-side if it is still active.
    unawaited(_connection?.dispose());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isVideo ? _buildVideoLayout() : _buildAudioLayout(),
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
        // Peer name + status.
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
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
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
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  String get _initials {
    final name = _peerName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

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
        Text(
          _statusText,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
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
    return Scaffold(
      appBar: AppBar(title: const Text('New Call')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Call another Appointly user. '
              'They need to be online in the app to receive the call.',
            ),
            const SizedBox(height: 20),
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
    );
  }
}

/// Incoming-call dialog, shown by the app root when a `call.incoming`
/// frame arrives (see `main.dart`).
///
/// Returns `true` when the user accepts, `false` when they decline,
/// and null when the dialog is dismissed or times out after 30
/// seconds (matching the caller's ring timeout — the server keeps
/// the call RINGING until the caller ends it, so the dialog must go
/// away on its own).
class IncomingCallDialog extends StatefulWidget {
  final IncomingCall incoming;

  const IncomingCallDialog({super.key, required this.incoming});

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(CallService.ringTimeout, () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = widget.incoming;
    final isVideo = incoming.callType == 'video';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              child: Icon(isVideo ? Icons.videocam : Icons.call, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              incoming.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isVideo ? 'Incoming video call' : 'Incoming voice call',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _answerButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  backgroundColor: Colors.red,
                  onPressed: () => Navigator.pop(context, false),
                ),
                _answerButton(
                  icon: Icons.call,
                  label: 'Accept',
                  backgroundColor: Colors.green,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
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
          radius: 28,
          backgroundColor: backgroundColor,
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 6),
        Text(label),
      ],
    );
  }
}
