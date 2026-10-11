import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

/// A full-screen dialog that lets the user pan and pinch-zoom an image
/// to frame exactly the portion they want shown in the profile circle.
///
/// Returns the cropped [Uint8List] (PNG) or null if cancelled.
Future<Uint8List?> showImageCropDialog({
  required BuildContext context,
  required Uint8List imageBytes,
}) {
  return Navigator.of(context).push<Uint8List>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _ImageCropPage(imageBytes: imageBytes),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 280),
    ),
  );
}

class _ImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;
  const _ImageCropPage({required this.imageBytes});

  @override
  State<_ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<_ImageCropPage>
    with SingleTickerProviderStateMixin {
  // Transform state
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;
  Offset _startOffset = Offset.zero;

  // Image natural size
  ui.Image? _image;
  Size _imageSize = Size.zero;

  // Crop circle key for repaint boundary
  final GlobalKey _cropKey = GlobalKey();

  // Animation for snapping/bouncing
  late AnimationController _snapCtrl;
  Animation<Offset>? _snapOffsetAnim;
  Animation<double>? _snapScaleAnim;

  bool _isCropping = false;

  static const double _circleSize = 280.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
      setState(() {
        if (_snapOffsetAnim != null) _offset = _snapOffsetAnim!.value;
        if (_snapScaleAnim != null) _scale = _snapScaleAnim!.value;
      });
    });
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    if (!mounted) return;
    setState(() {
      _image = img;
      _imageSize = Size(img.width.toDouble(), img.height.toDouble());
      // Fit image to fill the circle initially
      _fitToCircle();
    });
  }

  void _fitToCircle() {
    if (_imageSize == Size.zero) return;
    // Scale so the shorter side fills the circle diameter
    final scaleX = _circleSize / _imageSize.width;
    final scaleY = _circleSize / _imageSize.height;
    _scale = scaleX > scaleY ? scaleX : scaleY;
    _offset = Offset.zero;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _snapCtrl.stop();
    _lastFocalPoint = d.localFocalPoint;
    _lastScale = _scale;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      // Scale around focal point
      final newScale = (_lastScale * d.scale).clamp(_minScale, _maxScale);
      final focalDelta = d.localFocalPoint - _lastFocalPoint;
      // Adjust offset to keep focal point stable during zoom
      final scaleDiff = newScale / _scale;
      final center = Offset(_circleSize / 2, _circleSize / 2);
      _offset = (_offset - center) * scaleDiff + center + focalDelta;
      _scale = newScale;
      _lastFocalPoint = d.localFocalPoint;
      // ── Clamp DURING drag so image can never leave the circle ──
      _offset = _clampOffset(_offset, _scale);
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Clamp offset so image always covers the circle
    final clamped = _clampOffset(_offset, _scale);
    if (clamped != _offset) {
      _snapOffsetAnim = Tween<Offset>(begin: _offset, end: clamped)
          .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutBack));
      _snapScaleAnim = null;
      _snapCtrl.forward(from: 0);
    }
  }

  /// Returns the scale BoxFit.contain applies to render the image inside the circle box.
  double get _containScale {
    if (_imageSize == Size.zero) return 1.0;
    final sx = _circleSize / _imageSize.width;
    final sy = _circleSize / _imageSize.height;
    return sx < sy ? sx : sy;
  }

  /// Ensures the image always fully covers the crop circle
  Offset _clampOffset(Offset o, double s) {
    if (_imageSize == Size.zero) return o;
    // BoxFit.contain rendered dimensions, then our Transform.scale on top
    final fit = _containScale;
    final scaledW = _imageSize.width * fit * s;
    final scaledH = _imageSize.height * fit * s;
    final halfCircle = _circleSize / 2;
    // For the image rect to always cover the circle square:
    //   image left  <= 0            =>  offset.dx >= halfCircle - scaledW/2
    //   image right >= _circleSize  =>  offset.dx <= scaledW/2  - halfCircle
    //   same vertically
    final maxDx = (scaledW / 2 - halfCircle).abs();
    final maxDy = (scaledH / 2 - halfCircle).abs();
    final clampedX = o.dx.clamp(-maxDx, maxDx);
    final clampedY = o.dy.clamp(-maxDy, maxDy);
    return Offset(clampedX, clampedY);
  }

  Future<void> _confirmCrop() async {
    setState(() => _isCropping = true);
    try {
      // Render the RepaintBoundary to image
      final boundary = _cropKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      setState(() => _isCropping = false);
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text('Move & Zoom', style: GoogleFonts.dmSans(
                      fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _fitToCircle,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: const Icon(Icons.fit_screen_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // ── Hint ─────────────────────────────────────────────────────
            const SizedBox(height: 12),
            Text(
              'Drag to reposition · Pinch to zoom',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: Colors.white60, fontWeight: FontWeight.w500),
            ),

            const Spacer(),

            // ── Crop area ─────────────────────────────────────────────────
            Center(
              child: SizedBox(
                width: _circleSize,
                height: _circleSize,
                child: Stack(
                  children: [
                    // The repaint boundary captures only the circle content
                    RepaintBoundary(
                      key: _cropKey,
                      child: ClipOval(
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          child: SizedBox(
                            width: _circleSize,
                            height: _circleSize,
                            child: _image == null
                                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                : Transform.translate(
                              offset: _offset,
                              child: Transform.scale(
                                scale: _scale,
                                alignment: Alignment.center,
                                child: RawImage(image: _image, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Overlay: circular border + corner guides
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(_circleSize, _circleSize),
                        painter: _CropOverlayPainter(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ── Bottom actions ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(null),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Center(
                          child: Text('Cancel', style: GoogleFonts.dmSans(
                              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white70)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Use Photo
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isCropping ? null : _confirmCrop,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2ECC96), Color(0xFF1AAB7A)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(
                              color: const Color(0xFF2ECC96).withOpacity(0.4),
                              blurRadius: 14, offset: const Offset(0, 4))],
                        ),
                        child: Center(
                          child: _isCropping
                              ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text('Use Photo', style: GoogleFonts.dmSans(
                                  fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a glowing circular border with tick marks on the crop overlay
class _CropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Glow border
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius - 1, glowPaint);

    // Solid border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, borderPaint);

    // Corner arc indicators (at 4 cardinal corners)
    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const arcLen = 0.18; // radians
    for (final angle in [0.0, 1.5708, 3.1416, 4.7124]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1),
        angle - arcLen / 2,
        arcLen,
        false,
        arcPaint,
      );
    }

    // Center crosshair
    final crossPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0;
    canvas.drawLine(center - Offset(12, 0), center + Offset(12, 0), crossPaint);
    canvas.drawLine(center - Offset(0, 12), center + Offset(0, 12), crossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}