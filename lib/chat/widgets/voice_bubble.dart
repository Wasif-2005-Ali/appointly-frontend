import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VOICE MESSAGE BUBBLE — Professional waveform with simulated playback
// ─────────────────────────────────────────────────────────────────────────────
class VoiceBubble extends StatefulWidget {
  final String duration;
  final bool isMe;
  final Color accent;
  final List<Color> btnGrad;

  const VoiceBubble({
    super.key,
    required this.duration,
    required this.isMe,
    required this.accent,
    required this.btnGrad,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble>
    with SingleTickerProviderStateMixin {
  bool _playing  = false;
  double _progress = 0.0;
  Timer? _timer;
  late AnimationController _waveCtrl;
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    final rng = math.Random(42);
    _bars = List.generate(28, (i) => 0.15 + rng.nextDouble() * 0.85);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveCtrl.dispose();
    super.dispose();
  }

  int _parseSecs(String dur) {
    final parts = dur.split(':');
    return parts.length == 2
        ? (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0)
        : 30;
  }

  void _toggle() {
    if (_playing) {
      _timer?.cancel();
      _waveCtrl.stop();
      setState(() => _playing = false);
    } else {
      setState(() {
        _playing = true;
        if (_progress >= 1.0) _progress = 0.0;
      });
      _waveCtrl.repeat(reverse: true);
      final totalSecs = _parseSecs(widget.duration);
      const tickMs  = 80;
      final totalTicks =
          (totalSecs * 1000 / tickMs).ceil().clamp(1, 99999);
      int tick = 0;
      _timer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
        tick++;
        if (!mounted) { t.cancel(); return; }
        setState(() => _progress = tick / totalTicks);
        if (tick >= totalTicks) {
          t.cancel();
          _waveCtrl.stop();
          setState(() { _playing = false; _progress = 0.0; });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fgColor  = widget.isMe ? Colors.white : widget.accent;
    final dimColor = fgColor.withOpacity(0.28);

    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: _toggle,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: widget.isMe
                ? Colors.white.withOpacity(0.22)
                : widget.accent.withOpacity(0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: fgColor, size: 24,
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated waveform
            AnimatedBuilder(
              animation: _waveCtrl,
              builder: (_, __) => SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_bars.length, (i) {
                    final pct      = i / _bars.length;
                    final played   = pct < _progress;
                    final isActive = _playing && (pct - _progress).abs() < 0.06;
                    final h        = (_bars[i] * 28).clamp(4.0, 28.0);
                    final animH    = isActive
                        ? h * (0.65 + _waveCtrl.value * 0.35)
                        : h;
                    return Container(
                      width: 3,
                      height: animH.clamp(3.0, 28.0),
                      decoration: BoxDecoration(
                        color: (played || isActive) ? fgColor : dimColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2.5,
                    backgroundColor: dimColor,
                    valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.duration,
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: fgColor.withOpacity(0.85),
                ),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }
}
