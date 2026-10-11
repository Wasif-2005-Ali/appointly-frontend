import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppointlyLogo — static final-state logo
//  FIX: primaryColor + secondaryColor params so logo is visible on ANY bg
//  • Dark backgrounds  → pass Colors.white / Colors.white70
//  • Light backgrounds → leave defaults (navy / silver)
// ─────────────────────────────────────────────────────────────────────────────
class AppointlyLogo extends StatelessWidget {
  final double size;
  /// Main fill colour (arcs + triangles). Defaults to navy.
  /// Pass Colors.white on dark backgrounds so the logo is visible.
  final Color primaryColor;
  /// Secondary fill colour (check + arc4). Defaults to silver.
  final Color secondaryColor;
  /// Glow colour behind the logo. Defaults to white.
  final Color glowColor;

  const AppointlyLogo({
    super.key,
    this.size = 110,
    this.primaryColor  = const Color(0xFF132E4D),
    this.secondaryColor = const Color(0xFFB0B3AB),
    this.glowColor     = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        // Outer glow halo
        Container(
          width: size * 1.4,
          height: size * 1.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.25),
                blurRadius: size * 0.6,
                spreadRadius: size * 0.05,
              ),
            ],
          ),
        ),
        // Inner glow
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.12),
                blurRadius: size * 0.3,
                spreadRadius: size * 0.02,
              ),
            ],
          ),
        ),
        // Logo
        CustomPaint(
          size: Size(size, size),
          painter: _FinalLogoPainter(
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Painter — accepts dynamic colours so logo is always visible
// ─────────────────────────────────────────────────────────────────────────────
class _FinalLogoPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;

  const _FinalLogoPainter({
    required this.primaryColor,
    required this.secondaryColor,
  });

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

  static const double _svgLeft   = 285.0;
  static const double _svgTop    = 195.0;
  static const double _svgWidth  = 625.0;
  static const double _svgHeight = 625.0;

  Path _scale(Path raw, Size size) {
    final sx = size.width  / _svgWidth;
    final sy = size.height / _svgHeight;
    final m  = Matrix4.identity()
      ..translate(-_svgLeft * sx, -_svgTop * sy)
      ..scale(sx, sy);
    return raw.transform(m.storage);
  }

  void _fill(Canvas canvas, Size size, Path svgPath, Color color) {
    canvas.drawPath(
      _scale(svgPath, size),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _fill(canvas, size, _pArc1,  primaryColor);
    _fill(canvas, size, _pArc2,  primaryColor);
    _fill(canvas, size, _pArc3,  primaryColor);
    _fill(canvas, size, _pArc4,  secondaryColor);
    _fill(canvas, size, _pTri1,  primaryColor);
    _fill(canvas, size, _pTri2,  primaryColor);
    _fill(canvas, size, _pTri3,  primaryColor);
    _fill(canvas, size, _pCheck, secondaryColor);
  }

  @override
  bool shouldRepaint(_FinalLogoPainter old) =>
      old.primaryColor != primaryColor || old.secondaryColor != secondaryColor;
}
