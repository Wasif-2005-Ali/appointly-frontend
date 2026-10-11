import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppointlyHandIcon  — static version (used everywhere except the banner)
//
//  AnimatedAppointlyHandIcon — outer arcs rotate continuously; body is still
//    (used on the Incoming Requests banner)
//
//  isClose = true  → clean × for closing panels
// ─────────────────────────────────────────────────────────────────────────────

class AppointlyHandIcon extends StatelessWidget {
  final bool   isClose;
  final double size;
  final Color  color;

  const AppointlyHandIcon({
    super.key,
    this.isClose = false,
    this.size    = 26,
    this.color   = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(
          angleDeg: 0.0,
          isClose:  isClose,
          color:    color,
          size:     size,
        ),
      ),
    );
  }
}

// ── Animated variant: arcs spin, body triangles stay still ───────────────────
class AnimatedAppointlyHandIcon extends StatefulWidget {
  final double size;
  final Color  color;

  const AnimatedAppointlyHandIcon({
    super.key,
    this.size  = 26,
    this.color = Colors.white,
  });

  @override
  State<AnimatedAppointlyHandIcon> createState() =>
      _AnimatedAppointlyHandIconState();
}

class _AnimatedAppointlyHandIconState extends State<AnimatedAppointlyHandIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();                          // loops forever
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width:  widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _LogoPainter(
            angleDeg: _ctrl.value * 360.0,   // 0° → 360° over 7 s
            isClose:  false,
            color:    widget.color,
            size:     widget.size,
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double angleDeg;
  final bool   isClose;
  final Color  color;
  final double size;

  const _LogoPainter({
    required this.angleDeg,
    required this.isClose,
    required this.color,
    required this.size,
  });

  static const double _ox = 285.0, _oy = 195.0, _vw = 625.0;
  static const double _cx = 597.5, _cy = 507.5;  // logo centre in SVG space

  static final _pArc1 = parseSvgPathData(
      'M586.9,210.6l-0.6,1.7L572,248.1h0l-13.1,32.9l-27.8-0.9l12-26.3l0.9-1.5'
          'c-97.2,20.1-174.4,94.4-198.4,189.6c0,0,0,0,0,0.1'
          'c-10.1,57-1.4,94.7-1.4,94.7l-4.7-3.1l-37-25.8'
          'c0-1,0-2,0-3C302.6,345.8,428.9,216.4,586.9,210.6z');
  static final _pArc2 = parseSvgPathData(
      'M781,322.6c-35.1-35-80.3-60-130.9-70.4l0.7,1.3l12.4,27.4h-29.1'
          'l-14.5-33.1l-15.8-36l0-0.1l-0.6-1.3'
          'c80.3,1.4,152.8,34.7,205.2,87.7L781,322.6z');
  static final _pArc3 = parseSvgPathData(
      'M893.2,504.7c0,10.8-0.6,21.4-1.7,31.9v0l-34.9-22.8'
          'c0.1-3,0.2-6.1,0.2-9.1c0-53.2-16.2-102.6-43.9-143.6l13.1-43.4'
          'C868,368.5,893.2,433.7,893.2,504.7z');
  static final _pArc4 = parseSvgPathData(
      'M891.5,536.6c-16,147.6-141.3,262.5-293.6,262.5'
          'c-121.9,0-226.6-73.7-271.7-178.8l-30.1,16.5l14-65.6v0'
          'l5.7-26.6l28.6,17.4v0l49.2,30l-35.4,12.8'
          'c39.3,92.7,131.6,157.7,239.1,157.7'
          'c140.2,0,254.4-110.5,259.2-248.7L891.5,536.6z');

  static final _pTri1 = Path()..addPolygon([
    const Offset(561.3,487.1), const Offset(596.5,412.3),
    const Offset(627.4,471.2), const Offset(684.5,408.8),
    const Offset(640.3,324.0), const Offset(548.2,324.0),
    const Offset(498.9,423.9)], true);
  static final _pTri2 = Path()..addPolygon([
    const Offset(450.2,522.3), const Offset(512.8,580.5),
    const Offset(479.1,645.7), const Offset(389.4,645.7)], true);
  static final _pTri3 = Path()..addPolygon([
    const Offset(731.7,494.0), const Offset(674.0,566.2),
    const Offset(715.0,645.2), const Offset(806.9,645.2)], true);

  Path _scale(Path raw) {
    final s  = size / _vw;
    final dx = -_ox * s + size * 0.5 - (_cx - _ox) * s;
    final dy = -_oy * s + size * 0.5 - (_cy - _oy) * s;
    final m  = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(s, s);
    return raw.transform(m.storage);
  }

  Offset _pivot() {
    final s = size / _vw;
    final dx = -_ox * s + size * 0.5 - (_cx - _ox) * s;
    final dy = -_oy * s + size * 0.5 - (_cy - _oy) * s;
    return Offset(_cx * s + dx, _cy * s + dy);
  }

  @override
  void paint(Canvas canvas, Size sz) {
    if (isClose) { _drawClose(canvas); return; }

    final pivot   = _pivot();
    final radians = angleDeg * math.pi / 180.0;

    // ── Rotating arcs — canvas transform spins them around logo centre ────
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(radians);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawPath(_scale(_pArc1),
        Paint()..color = color.withOpacity(0.92)..style = PaintingStyle.fill);
    canvas.drawPath(_scale(_pArc2),
        Paint()..color = color.withOpacity(0.92)..style = PaintingStyle.fill);
    canvas.drawPath(_scale(_pArc3),
        Paint()..color = color.withOpacity(0.70)..style = PaintingStyle.fill);
    canvas.drawPath(_scale(_pArc4),
        Paint()..color = color.withOpacity(0.50)..style = PaintingStyle.fill);
    canvas.restore();

    // ── Static body triangles — drawn without any transform ───────────────
    for (final tri in [_pTri1, _pTri2, _pTri3]) {
      canvas.drawPath(_scale(tri),
          Paint()..color = color..style = PaintingStyle.fill);
    }
  }

  void _drawClose(Canvas canvas) {
    final cx = size / 2, cy = size / 2;
    final d  = size * 0.28;
    final p  = Paint()
      ..color      = color
      ..strokeWidth = size * 0.11
      ..strokeCap  = StrokeCap.round
      ..style      = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), p);
    canvas.drawLine(Offset(cx + d, cy - d), Offset(cx - d, cy + d), p);
  }

  @override
  bool shouldRepaint(_LogoPainter o) =>
      o.angleDeg != angleDeg || o.isClose != isClose ||
          o.color != color || o.size != size;
}