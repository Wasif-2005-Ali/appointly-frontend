// ═══════════════════════════════════════════════════════════════════
//  splash_screen.dart
//
//  Animated splash that draws the Appointly logo path-by-path,
//  then fades in the wordmark before navigating to WelcomeScreen.
//
//  Requires pubspec.yaml dependency:
//    path_drawing: ^1.0.1
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import '../database/bd_helper.dart';
import '../app_state.dart';
import '../user_session.dart';
import 'login_signup_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _ctrl;

  late final Animation<double> _arc1Draw;
  late final Animation<double> _arc2Draw;
  late final Animation<double> _arc3Draw;
  late final Animation<double> _arc4Draw;

  late final Animation<double> _arc1Fill;
  late final Animation<double> _arc2Fill;
  late final Animation<double> _arc3Fill;
  late final Animation<double> _arc4Fill;

  late final Animation<double> _tri1Draw;
  late final Animation<double> _tri2Draw;
  late final Animation<double> _tri3Draw;

  late final Animation<double> _tri1Fill;
  late final Animation<double> _tri2Fill;
  late final Animation<double> _tri3Fill;

  late final Animation<double> _checkDraw;
  late final Animation<double> _checkFill;

  late final Animation<double> _glow;

  final List<Animation<double>> _letterFade = [];


  Animation<double> _interval(double start, double end,
      [Curve curve = Curves.easeInOut]) {
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _glow = _interval(0.00, 0.06, Curves.easeIn);

    _arc1Draw = _interval(0.000, 0.175, Curves.easeInOut);
    _arc2Draw = _interval(0.175, 0.269, Curves.easeInOut);
    _arc3Draw = _interval(0.269, 0.338, Curves.easeInOut);
    _arc4Draw = _interval(0.338, 0.513, Curves.easeInOut);

    _arc1Fill = _interval(0.100, 0.220);
    _arc2Fill = _interval(0.210, 0.300);
    _arc3Fill = _interval(0.285, 0.375);
    _arc4Fill = _interval(0.430, 0.560);

    _tri1Draw = _interval(0.183, 0.320, Curves.easeInOut);
    _tri2Draw = _interval(0.280, 0.410, Curves.easeInOut);
    _tri3Draw = _interval(0.355, 0.475, Curves.easeInOut);

    _tri1Fill = _interval(0.265, 0.360);
    _tri2Fill = _interval(0.355, 0.455);
    _tri3Fill = _interval(0.415, 0.510);

    _checkDraw = _interval(0.540, 0.750, Curves.easeInOut);
    _checkFill = _interval(0.640, 0.800);

    const double ls = 0.790;
    const double le = 0.990;
    const double span = (le - ls) / 9.0;
    for (int i = 0; i < 9; i++) {
      _letterFade.add(
        _interval(ls + i * span, (ls + i * span + span + 0.015).clamp(0, 1),
            Curves.easeOut),
      );
    }

    _ctrl.forward().then((_) async {
      if (!mounted) return;
      // Ensure DB is ready (runs in background during the 4 s animation — fast)
      await DBHelper.instance.database;
      // Restore saved session for data pre-loading only — login is always required
      final savedUser = await DBHelper.instance.restoreSession();
      if (savedUser != null && mounted) {
        UserSession.instance.setFromMap(savedUser);
      }
      if (!mounted) return;
      // Crossfade directly — no pre-fade so no black flash
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WelcomeScreen(),
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
            child: child,
          );
        },
      ));
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF0B1E3D), // matches login hero gradient start
        body: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: _glow.value,
                        child: Container(
                          width: 320,
                          height: 320,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2D4C70).withOpacity(0.85),
                                blurRadius: 100,
                                spreadRadius: 30,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: _glow.value * 0.7,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3D6FA8).withOpacity(0.6),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(290, 290),
                        painter: _LogoPainter(
                          arc1Draw: _arc1Draw.value, arc1Fill: _arc1Fill.value,
                          arc2Draw: _arc2Draw.value, arc2Fill: _arc2Fill.value,
                          arc3Draw: _arc3Draw.value, arc3Fill: _arc3Fill.value,
                          arc4Draw: _arc4Draw.value, arc4Fill: _arc4Fill.value,
                          tri1Draw: _tri1Draw.value, tri1Fill: _tri1Fill.value,
                          tri2Draw: _tri2Draw.value, tri2Fill: _tri2Fill.value,
                          tri3Draw: _tri3Draw.value, tri3Fill: _tri3Fill.value,
                          checkDraw: _checkDraw.value, checkFill: _checkFill.value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: 'APPOINTLY'.split('').asMap().entries.map((e) {
                      final t = _letterFade[e.key].value;
                      final lerp = e.key / 8.0;
                      final color = Color.lerp(
                        const Color(0xFF1C3F6A),
                        const Color(0xFF2D6FAA),
                        lerp,
                      )!;
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, 14.0 * (1.0 - t)),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: color,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              fontFamily: 'sans-serif',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      );
  }
}

// ─────────────────────────────────────────────────────────────────
//  LOGO PAINTER
// ─────────────────────────────────────────────────────────────────
class _LogoPainter extends CustomPainter {
  final double arc1Draw, arc1Fill;
  final double arc2Draw, arc2Fill;
  final double arc3Draw, arc3Fill;
  final double arc4Draw, arc4Fill;
  final double tri1Draw, tri1Fill;
  final double tri2Draw, tri2Fill;
  final double tri3Draw, tri3Fill;
  final double checkDraw, checkFill;

  const _LogoPainter({
    required this.arc1Draw, required this.arc1Fill,
    required this.arc2Draw, required this.arc2Fill,
    required this.arc3Draw, required this.arc3Fill,
    required this.arc4Draw, required this.arc4Fill,
    required this.tri1Draw, required this.tri1Fill,
    required this.tri2Draw, required this.tri2Fill,
    required this.tri3Draw, required this.tri3Fill,
    required this.checkDraw, required this.checkFill,
  });

  static const double _svgLeft   = 285.0;
  static const double _svgTop    = 195.0;
  static const double _svgWidth  = 625.0;
  static const double _svgHeight = 625.0;

  static final Path _pArc1 = parseSvgPathData(
    'M586.9,210.6l-0.6,1.7L572,248.1h0l-13.1,32.9l-27.8-0.9l12-26.3l0.9-1.5'
        'c-97.2,20.1-174.4,94.4-198.4,189.6c0,0,0,0,0,0.1'
        'c-10.1,57-1.4,94.7-1.4,94.7l-4.7-3.1l-37-25.8'
        'c0-1,0-2,0-3C302.6,345.8,428.9,216.4,586.9,210.6z',
  );
  static final Path _pArc2 = parseSvgPathData(
    'M781,322.6c-35.1-35-80.3-60-130.9-70.4l0.7,1.3l12.4,27.4h-29.1'
        'l-14.5-33.1l-15.8-36l0-0.1l-0.6-1.3'
        'c80.3,1.4,152.8,34.7,205.2,87.7L781,322.6z',
  );
  static final Path _pArc3 = parseSvgPathData(
    'M893.2,504.7c0,10.8-0.6,21.4-1.7,31.9v0l-34.9-22.8'
        'c0.1-3,0.2-6.1,0.2-9.1c0-53.2-16.2-102.6-43.9-143.6l13.1-43.4'
        'C868,368.5,893.2,433.7,893.2,504.7z',
  );
  static final Path _pArc4 = parseSvgPathData(
    'M891.5,536.6c-16,147.6-141.3,262.5-293.6,262.5'
        'c-121.9,0-226.6-73.7-271.7-178.8l-30.1,16.5l14-65.6v0'
        'l5.7-26.6l28.6,17.4v0l49.2,30l-35.4,12.8'
        'c39.3,92.7,131.6,157.7,239.1,157.7'
        'c140.2,0,254.4-110.5,259.2-248.7L891.5,536.6z',
  );
  static final Path _pCheck = parseSvgPathData(
    'M804.7,314.6c-2.2,8.1-5,16.4-8.2,24.8'
        'c-24.7,64.8-73.8,133.1-73.8,133.1L675,539.3l-76.9,100.1'
        'L459.9,504.9l29.6-65.7l99.8,100.4l1.6-1.6'
        'c73.2-81.7,162-171.6,197.8-207.4'
        'C798.9,320.4,804.7,314.6,804.7,314.6z',
  );

  static final Path _pTri1 = Path()
    ..addPolygon([
      const Offset(561.3, 487.1), const Offset(596.5, 412.3),
      const Offset(627.4, 471.2), const Offset(684.5, 408.8),
      const Offset(640.3, 324.0), const Offset(548.2, 324.0),
      const Offset(498.9, 423.9),
    ], true);

  static final Path _pTri2 = Path()
    ..addPolygon([
      const Offset(450.2, 522.3), const Offset(512.8, 580.5),
      const Offset(479.1, 645.7), const Offset(389.4, 645.7),
    ], true);

  static final Path _pTri3 = Path()
    ..addPolygon([
      const Offset(731.7, 494.0), const Offset(674.0, 566.2),
      const Offset(715.0, 645.2), const Offset(806.9, 645.2),
    ], true);

  static const Color _navyFill    = Color(0xFF132E4D);
  static const Color _navyLight   = Color(0xFF2D4C70);
  static const Color _silverFill  = Color(0xFFB0B3AB);
  static const Color _navyStroke  = Color(0xFF2D4C70);
  static const Color _silverStroke = Color(0xFF9FA39B);

  Path _scale(Path raw, Size size) {
    final sx = size.width  / _svgWidth;
    final sy = size.height / _svgHeight;
    final m = Matrix4.identity()
      ..translate(-_svgLeft * sx, -_svgTop * sy)
      ..scale(sx, sy);
    return raw.transform(m.storage);
  }

  Path _trim(Path p, double t) {
    if (t <= 0.0) return Path();
    if (t >= 1.0) return p;
    final out = Path();
    for (final metric in p.computeMetrics()) {
      out.addPath(metric.extractPath(0.0, metric.length * t), Offset.zero);
    }
    return out;
  }

  void _draw(Canvas canvas, Size size, {
    required Path svgPath,
    required double drawT,
    required double fillT,
    required Color strokeColor,
    required Color fillColor,
    double strokeWidth = 2.8,
  }) {
    final scaled = _scale(svgPath, size);
    if (fillT > 0) {
      canvas.drawPath(
        scaled,
        Paint()
          ..color = fillColor.withOpacity(fillT.clamp(0.0, 1.0))
          ..style = PaintingStyle.fill,
      );
    }
    if (drawT > 0) {
      final strokeAlpha = (1.0 - fillT).clamp(0.0, 1.0);
      if (strokeAlpha > 0.01) {
        canvas.drawPath(
          _trim(scaled, drawT),
          Paint()
            ..color = strokeColor.withOpacity(strokeAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, size, svgPath: _pArc1,
        drawT: arc1Draw, fillT: arc1Fill,
        strokeColor: _navyStroke, fillColor: _navyFill);
    _draw(canvas, size, svgPath: _pArc2,
        drawT: arc2Draw, fillT: arc2Fill,
        strokeColor: _navyStroke, fillColor: _navyFill);
    _draw(canvas, size, svgPath: _pArc3,
        drawT: arc3Draw, fillT: arc3Fill,
        strokeColor: _navyStroke, fillColor: _navyFill);
    _draw(canvas, size, svgPath: _pArc4,
        drawT: arc4Draw, fillT: arc4Fill,
        strokeColor: _silverStroke, fillColor: _silverFill);
    _draw(canvas, size, svgPath: _pTri1,
        drawT: tri1Draw, fillT: tri1Fill,
        strokeColor: _navyStroke, fillColor: _navyFill, strokeWidth: 2.2);
    _draw(canvas, size, svgPath: _pTri2,
        drawT: tri2Draw, fillT: tri2Fill,
        strokeColor: _navyStroke, fillColor: _navyFill, strokeWidth: 2.2);
    _draw(canvas, size, svgPath: _pTri3,
        drawT: tri3Draw, fillT: tri3Fill,
        strokeColor: _navyStroke, fillColor: _navyFill, strokeWidth: 2.2);
    _draw(canvas, size, svgPath: _pCheck,
        drawT: checkDraw, fillT: checkFill,
        strokeColor: _silverStroke, fillColor: _silverFill, strokeWidth: 3.2);
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.arc1Draw != arc1Draw || old.arc1Fill != arc1Fill ||
          old.arc2Draw != arc2Draw || old.arc2Fill != arc2Fill ||
          old.arc3Draw != arc3Draw || old.arc3Fill != arc3Fill ||
          old.arc4Draw != arc4Draw || old.arc4Fill != arc4Fill ||
          old.tri1Draw != tri1Draw || old.tri1Fill != tri1Fill ||
          old.tri2Draw != tri2Draw || old.tri2Fill != tri2Fill ||
          old.tri3Draw != tri3Draw || old.tri3Fill != tri3Fill ||
          old.checkDraw != checkDraw || old.checkFill != checkFill;
}