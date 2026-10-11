import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SWIPE-TO-REPLY WRAPPER
// ─────────────────────────────────────────────────────────────────────────────
class SwipeableMessage extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const SwipeableMessage({
    super.key,
    required this.child,
    required this.onReply,
  });

  @override
  State<SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<SwipeableMessage>
    with SingleTickerProviderStateMixin {
  double _off      = 0;
  bool   _triggered = false;
  late   AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    setState(() => _off = (_off + d.delta.dx).clamp(-70.0, 70.0));
    if (_off.abs() > 50 && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
      widget.onReply();
    }
  }

  void _onEnd(DragEndDetails _) {
    _triggered = false;
    final start = _off;
    _ctrl.reset();
    final anim = Tween<double>(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    anim.addListener(() {
      if (mounted) setState(() => _off = anim.value);
    });
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        child: Transform.translate(
          offset: Offset(_off, 0),
          child: widget.child,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DOT BACKGROUND PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class DotBackgroundPainter extends CustomPainter {
  final Color color;
  DotBackgroundPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    const s = 30.0;
    for (double y = 0; y < size.height; y += s) {
      final off = (y ~/ s % 2 == 0) ? 0.0 : s / 2;
      for (double x = off; x < size.width; x += s) {
        canvas.drawCircle(Offset(x, y), 1.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotBackgroundPainter old) => old.color != color;
}
