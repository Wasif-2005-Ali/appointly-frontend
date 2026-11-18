import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VOICE MESSAGE TILE — real in-app playback
// ─────────────────────────────────────────────────────────────────────────────
// Voice notes are real .m4a files uploaded via the media endpoint and
// arrive as file messages whose name starts with `voice_note_` (see
// ChatMessage.fromApi). When [audioUrl] is given, this tile plays
// the recording in-app with a play/pause button, a progress bar, and
// position/duration. Voice notes recorded before real voice notes
// existed were stored on-device only (a duration string, no audio
// file), so there is nothing to play back — those render statically
// with [audioUrl] null and say so honestly.
class VoiceBubble extends StatefulWidget {
  final String duration;
  final bool isMe;
  final Color accent;
  final List<Color> btnGrad;

  /// URL of the recorded audio. Null for legacy on-device notes that
  /// have no audio file — those render statically.
  final String? audioUrl;

  const VoiceBubble({
    super.key,
    required this.duration,
    required this.isMe,
    required this.accent,
    required this.btnGrad,
    this.audioUrl,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  Duration? _total;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  bool _loadFailed = false;

  bool get _playing => _state == PlayerState.playing;
  bool get _hasAudio => widget.audioUrl != null && widget.audioUrl!.isNotEmpty;

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _durationSub = player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _positionSub = player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _stateSub = player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _completeSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _state = PlayerState.completed;
          _position = _total ?? Duration.zero;
        });
      }
    });
    _player = player;
    return player;
  }

  Future<void> _togglePlay() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    final player = _ensurePlayer();
    try {
      if (_playing) {
        await player.pause();
      } else {
        if (_state == PlayerState.completed) {
          await player.seek(Duration.zero);
        }
        await player.play(UrlSource(url));
      }
      if (mounted) setState(() => _loadFailed = false);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  static String _fmt(Duration d) {
    final mins = d.inMinutes;
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final fgColor = widget.isMe ? Colors.white : widget.accent;
    final total = _total;
    final progress = total != null && total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final timeLabel = _hasAudio
        ? (total != null
              ? '${_fmt(_position)} / ${_fmt(total)}'
              : widget.duration)
        : '${widget.duration} • recorded on this device';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _hasAudio ? _togglePlay : null,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: widget.isMe
                  ? Colors.white.withOpacity(0.22)
                  : widget.accent.withOpacity(0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _hasAudio
                  ? (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded)
                  : Icons.mic_rounded,
              color: fgColor,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Voice message',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fgColor,
              ),
            ),
            const SizedBox(height: 4),
            if (_hasAudio) ...[
              SizedBox(
                width: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: fgColor.withOpacity(0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              _loadFailed ? "Couldn't play this voice note" : timeLabel,
              style: GoogleFonts.dmSans(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: fgColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
