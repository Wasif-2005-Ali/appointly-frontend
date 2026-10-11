import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_state.dart';

Future<void> showSaveAnimation(
  BuildContext context, {
  String label = 'Saving…',
  Duration processingDuration = const Duration(milliseconds: 1100),
}) {
  final appState = AppStateProvider.of(context);
  final cardBg  = appState.cardBg;
  final border  = appState.border;
  final accent  = appState.accent;
  final txtSub  = appState.txtSub;
  final isDark  = appState.isDarkMode;

  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.55),
    barrierLabel: 'save',
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, a1, a2, child) => ScaleTransition(
      scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: a1, child: child),
    ),
    pageBuilder: (ctx, a1, a2) => _SaveDialog(
      label: label,
      processingDuration: processingDuration,
      cardBg: cardBg, border: border,
      accent: accent, txtSub: txtSub, isDark: isDark,
    ),
  );
}

class _SaveDialog extends StatefulWidget {
  final String label;
  final Duration processingDuration;
  final Color cardBg, border, accent, txtSub;
  final bool isDark;
  const _SaveDialog({
    required this.label, required this.processingDuration,
    required this.cardBg, required this.border,
    required this.accent, required this.txtSub, required this.isDark,
  });
  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> with TickerProviderStateMixin {
  late final AnimationController _spinCtrl, _ringCtrl, _checkCtrl, _exitCtrl;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _ringCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _exitCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(widget.processingDuration);
    if (!mounted) return;
    _spinCtrl.stop();
    setState(() => _success = true);
    await _ringCtrl.animateTo(1.0, curve: Curves.easeOutCubic);
    if (!mounted) return;
    await _checkCtrl.animateTo(1.0, curve: Curves.easeOutCubic);
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _exitCtrl.animateTo(1.0, curve: Curves.easeIn);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _spinCtrl.dispose(); _ringCtrl.dispose(); _checkCtrl.dispose(); _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg    = widget.isDark
        ? Color.alphaBlend(Colors.black.withOpacity(0.25), widget.cardBg)
        : Color.alphaBlend(Colors.black.withOpacity(0.04), widget.cardBg);
    final track = widget.isDark
        ? widget.border.withOpacity(0.5)
        : widget.border.withOpacity(0.8);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _exitCtrl,
          builder: (ctx, child) => Opacity(opacity: 1.0 - _exitCtrl.value, child: child),
          child: Container(
            width: 192, height: 192,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: widget.border, width: 1.5),
              boxShadow: [
                BoxShadow(color: widget.accent.withOpacity(0.22), blurRadius: 48, spreadRadius: 4),
                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 32, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                width: 88, height: 88,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_spinCtrl, _ringCtrl, _checkCtrl]),
                  builder: (_, __) => CustomPaint(
                    painter: _SaveRingPainter(
                      spinValue: _spinCtrl.value, ringValue: _ringCtrl.value,
                      checkValue: _checkCtrl.value, success: _success,
                      accentColor: widget.accent, trackColor: track, isDark: widget.isDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut, switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
                    child: child)),
                child: Text(
                  _success && _checkCtrl.value > 0.85 ? '✓  Saved!' : widget.label,
                  key: ValueKey(_success && _checkCtrl.value > 0.85),
                  style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2,
                    color: _success && _checkCtrl.value > 0.85
                        ? const Color(0xFF2ECC96)
                        : widget.txtSub,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SaveRingPainter extends CustomPainter {
  final double spinValue, ringValue, checkValue;
  final bool success, isDark;
  final Color accentColor, trackColor;
  const _SaveRingPainter({
    required this.spinValue, required this.ringValue, required this.checkValue,
    required this.success, required this.accentColor,
    required this.trackColor, required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(center, radius,
      Paint()..color = trackColor..strokeWidth = 7..style = PaintingStyle.stroke);

    if (!success) {
      final startAngle = spinValue * 2 * math.pi - math.pi / 2;
      const sweepAngle = 1.6 * math.pi;
      final dimAcc = HSLColor.fromColor(accentColor)
          .withLightness((HSLColor.fromColor(accentColor).lightness * 0.6).clamp(0.08, 0.35))
          .toColor();
      final leadX = center.dx + radius * math.cos(startAngle + sweepAngle);
      final leadY = center.dy + radius * math.sin(startAngle + sweepAngle);
      canvas.drawCircle(Offset(leadX, leadY), 4,
        Paint()..color = accentColor.withOpacity(0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false,
        Paint()
          ..shader = SweepGradient(
            startAngle: startAngle, endAngle: startAngle + sweepAngle,
            colors: [dimAcc.withOpacity(0.1), dimAcc, accentColor],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..strokeWidth = 7..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * ringValue, false,
        Paint()
          ..shader = const SweepGradient(
            startAngle: -math.pi / 2, endAngle: -math.pi / 2 + 2 * math.pi,
            colors: [Color(0xFF0D9E6A), Color(0xFF2ECC96)],
          ).createShader(Rect.fromCircle(center: center, radius: 40))
          ..strokeWidth = 7..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
      );
      if (checkValue > 0) _drawCheckmark(canvas, center, checkValue.clamp(0.0, 1.0));
    }
  }

  void _drawCheckmark(Canvas canvas, Offset center, double progress) {
    final p1 = center + const Offset(-16, 2);
    final p2 = center + const Offset(-4, 14);
    final p3 = center + const Offset(18, -12);
    final paint = Paint()
      ..color = isDark ? Colors.white : const Color(0xFF0D9E6A)
      ..strokeWidth = 4.5..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (progress < 0.45) {
      final t = (progress / 0.45).clamp(0.0, 1.0);
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      final t = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SaveRingPainter old) =>
      old.spinValue != spinValue || old.ringValue != ringValue ||
      old.checkValue != checkValue || old.success != success;
}
