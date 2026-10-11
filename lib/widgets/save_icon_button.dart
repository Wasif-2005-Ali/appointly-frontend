import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SaveIconButton
//
//  IDLE    → Logo body (3 triangles) + 4 arcs shown statically. NO tick.
//            Soft border glow pulses gently.
//  SAVING  → Body (triangles) stays perfectly still in centre.
//            Only the outer arcs rotate — real-time loading indicator.
//  SUCCESS → Arcs ease to a stop. Tick strokes in over the logo, then fills.
//
//  Colors: navy #132E4D, silver #B0B3AB, alice blue #DAE8F5
// ─────────────────────────────────────────────────────────────────────────────

enum _SS { idle, saving, success }

class SaveIconButton extends StatefulWidget {
  final Future<void> Function() onSave;
  final double size;
  /// Fire this listenable whenever a field changes — resets the button
  /// from success back to idle so the user can save again.
  final Listenable? changeSignal;
  /// Primary logo colour. Pass Colors.white when rendered on dark backgrounds
  /// so the logo is always visible. Defaults to navy.
  final Color foregroundColor;
  const SaveIconButton({
    super.key,
    required this.onSave,
    this.size = 42,
    this.changeSignal,
    this.foregroundColor = const Color(0xFF132E4D),
  });

  @override
  State<SaveIconButton> createState() => _SaveIconButtonState();
}

class _SaveIconButtonState extends State<SaveIconButton>
    with TickerProviderStateMixin {

  // ── Arc rotation (Ticker for smooth speed control) ────────────────────────
  late final Ticker _ticker;
  double _angleDeg  = 0.0;
  double _curSpeed  = 0.0;
  double _tgtSpeed  = 0.0;
  DateTime? _lastAt;
  bool _waitForStop = false;
  bool _workDone    = false;
  static const double _spinSpeed = 280.0;  // °/second — clear, obvious rotation

  // ── Tick draw-in (success only) ───────────────────────────────────────────
  late final AnimationController _tickCtrl;

  // ── Press scale feedback ──────────────────────────────────────────────────
  late final AnimationController _pressCtrl;
  late final Animation<double>   _pressAnim;

  // ── Idle border glow pulse ────────────────────────────────────────────────
  late final AnimationController _glowCtrl;

  _SS _state = _SS.idle;

  @override
  void initState() {
    super.initState();

    _ticker = createTicker(_onTick)..start();

    // Tick stays at 0 on idle — only plays on success
    _tickCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() { if (mounted) setState(() {}); });

    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 110));
    _pressAnim = Tween<double>(begin: 1.0, end: 0.84)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);

    widget.changeSignal?.addListener(_onChangeSignal);
  }

  @override
  void didUpdateWidget(SaveIconButton old) {
    super.didUpdateWidget(old);
    if (old.changeSignal != widget.changeSignal) {
      old.changeSignal?.removeListener(_onChangeSignal);
      widget.changeSignal?.addListener(_onChangeSignal);
    }
  }

  void _onChangeSignal() {
    if (_state == _SS.success && mounted) {
      _tickCtrl.reset();
      setState(() { _state = _SS.idle; _angleDeg = 0; });
      _glowCtrl.repeat(reverse: true);
    }
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    final dt  = _lastAt == null ? 0.016
        : now.difference(_lastAt!).inMicroseconds / 1e6;
    _lastAt = now;

    _curSpeed += (_tgtSpeed - _curSpeed) * 0.12;  // ramps to full speed quickly
    _angleDeg  = (_angleDeg + _curSpeed * dt) % 360.0;

    if (_waitForStop && _workDone && _curSpeed < 1.0) {
      _waitForStop = false;
      _workDone    = false;
      _curSpeed    = 0;
      _tgtSpeed    = 0;
      if (mounted) _triggerSuccess();
      return;
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleTap() async {
    if (_state == _SS.saving) return;
    HapticFeedback.lightImpact();
    await _pressCtrl.forward();
    _pressCtrl.reverse();

    if (_state == _SS.success) {
      // Back to idle — logo no tick
      _tickCtrl.reset();
      setState(() { _state = _SS.idle; _angleDeg = 0; });
      _glowCtrl.repeat(reverse: true);
      return;
    }

    // Idle → Saving: arcs spin during the entire onSave() call.
    // A guaranteed minimum of 800 ms ensures the rotation is always
    // clearly visible, even when the save completes instantly.
    _glowCtrl.stop();
    setState(() => _state = _SS.saving);
    _tgtSpeed    = _spinSpeed;
    _waitForStop = true;
    _workDone    = false;

    final started = DateTime.now();
    await widget.onSave();
    if (!mounted) return;

    final elapsed = DateTime.now().difference(started);
    const minSpin = Duration(milliseconds: 800);
    if (elapsed < minSpin) {
      await Future.delayed(minSpin - elapsed);
    }
    if (!mounted) return;

    _workDone = true;
    _tgtSpeed = 0; // speed ramps down → tick fires when < 1 °/s
  }

  void _triggerSuccess() {
    if (!mounted) return;
    setState(() => _state = _SS.success);
    HapticFeedback.mediumImpact();
    _tickCtrl.forward();
  }

  @override
  void dispose() {
    widget.changeSignal?.removeListener(_onChangeSignal);
    _ticker.dispose();
    _tickCtrl.dispose();
    _pressCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pressAnim,
        builder: (_, child) =>
            Transform.scale(scale: _pressAnim.value, child: child),
        child: CustomPaint(
          size: Size(s, s),
          painter: _SaveBtnPainter(
            state:          _state,
            angleDeg:       _angleDeg,
            tickT:          _tickCtrl.value,
            btnSize:        s,
            foregroundColor: widget.foregroundColor,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Painter
//  SVG window: origin (285, 195), size 625×625
//  Logo centre: svg cx=597.5 cy=507.5  →  btn centre
// ─────────────────────────────────────────────────────────────────────────────
class _SaveBtnPainter extends CustomPainter {
  final _SS    state;
  final double angleDeg;
  final double tickT;
  final double btnSize;
  /// FIX: Dynamic colour — white on dark headers, navy on light backgrounds
  final Color  foregroundColor;

  const _SaveBtnPainter({
    required this.state,
    required this.angleDeg,
    required this.tickT,
    required this.btnSize,
    this.foregroundColor = const Color(0xFF132E4D),
  });

  static const double _ox = 285.0, _oy = 195.0, _vw = 625.0, _vh = 625.0;
  static const double _cx = 597.5, _cy = 507.5;

  // Derive secondary (silver-like) from foreground: if white→white70, else silver
  Color get _secondary => foregroundColor == Colors.white || foregroundColor.computeLuminance() > 0.7
      ? Colors.white.withOpacity(0.65)
      : const Color(0xFFB0B3AB);
  Color get _silvL => foregroundColor.computeLuminance() > 0.7
      ? Colors.white.withOpacity(0.85)
      : const Color(0xFFDAE8F5);

  // Outer arc paths — rotate during saving
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

  // Inner body triangles — always static
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

  // Tick — only shown on success
  static final _pCheck = parseSvgPathData(
    'M804.7,314.6c-2.2,8.1-5,16.4-8.2,24.8'
    'c-24.7,64.8-73.8,133.1-73.8,133.1L675,539.3l-76.9,100.1'
    'L459.9,504.9l29.6-65.7l99.8,100.4l1.6-1.6'
    'c73.2-81.7,162-171.6,197.8-207.4'
    'C798.9,320.4,804.7,314.6,804.7,314.6z');

  Offset _svgToBtn(double x, double y) {
    return Offset((x - _ox) * (btnSize / _vw), (y - _oy) * (btnSize / _vh));
  }

  Path _scalePath(Path raw) {
    final sx = btnSize / _vw, sy = btnSize / _vh;
    final m = Matrix4.identity()
      ..translate(-_ox * sx, -_oy * sy)
      ..scale(sx, sy);
    return raw.transform(m.storage);
  }

  Path _trim(Path p, double t) {
    if (t <= 0) return Path();
    if (t >= 1) return p;
    final out = Path();
    for (final m in p.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * t), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (state) {
      case _SS.idle:
        _paintBody(canvas, opacity: 0.85);
        _paintArcs(canvas, spin: false, opacity: 0.85);

      case _SS.saving:
        _paintBody(canvas, opacity: 0.90);
        _paintArcs(canvas, spin: true,  opacity: 0.95);

      case _SS.success:
        _paintBody(canvas, opacity: 0.85);
        _paintArcs(canvas, spin: false, opacity: 0.85);
        _paintTick(canvas,
            drawT: tickT,
            fillT: (tickT - 0.5).clamp(0.0, 1.0));
    }
  }



  void _paintBody(Canvas canvas, {double opacity = 1.0}) {
    final p = Paint()..color = foregroundColor.withOpacity(opacity)..style = PaintingStyle.fill;
    for (final tri in [_pTri1, _pTri2, _pTri3]) {
      canvas.drawPath(_scalePath(tri), p);
    }
  }

  void _paintArcs(Canvas canvas, {required bool spin, double opacity = 1.0}) {
    if (spin) {
      final pivot = _svgToBtn(_cx, _cy);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(angleDeg * math.pi / 180.0);
      canvas.translate(-pivot.dx, -pivot.dy);
    }
    final colors = [foregroundColor, foregroundColor, foregroundColor, _secondary];
    final paths  = [_pArc1, _pArc2, _pArc3, _pArc4];
    for (var i = 0; i < 4; i++) {
      canvas.drawPath(_scalePath(paths[i]),
          Paint()..color = colors[i].withOpacity(opacity)..style = PaintingStyle.fill);
    }
    if (spin) canvas.restore();
  }

  void _paintTick(Canvas canvas, {required double drawT, required double fillT}) {
    final scaled = _scalePath(_pCheck);
    if (fillT > 0) {
      canvas.drawPath(scaled,
          Paint()..color = _silvL.withOpacity(fillT.clamp(0.0, 1.0))..style = PaintingStyle.fill);
    }
    if (drawT > 0) {
      final a = (1.0 - fillT).clamp(0.0, 1.0);
      if (a > 0.01) {
        canvas.drawPath(_trim(scaled, drawT),
            Paint()
              ..color = _secondary.withOpacity(a)
              ..style = PaintingStyle.stroke
              ..strokeWidth = btnSize * 0.038
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round);
      }
    }
  }

  @override
  bool shouldRepaint(_SaveBtnPainter o) =>
      o.state != state || o.angleDeg != angleDeg ||
      o.tickT  != tickT || o.btnSize  != btnSize ||
      o.foregroundColor != foregroundColor;
}
