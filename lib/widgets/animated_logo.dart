import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppointlyLogo
//  Wraps the calendar SVG in a frosted glass circle with a glowing ring.
//  Works on both dark gradient headers and light backgrounds.
// ─────────────────────────────────────────────────────────────────────────────
class AppointlyLogo extends StatelessWidget {
  final double size;
  final Color? glowColor;
  final double glowRadius;
  final bool showGlow;

  const AppointlyLogo({
    super.key,
    this.size = 56,
    this.glowColor,
    this.glowRadius = 18,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showGlow || size < 24) {
      return SvgPicture.asset(
        'assets/logo.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    final glow = glowColor ?? const Color(0xFF3D8EE8);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Layered shadows for the glow ring effect
        boxShadow: [
          BoxShadow(
            color: glow.withOpacity(0.38),
            blurRadius: size * 0.50,
            spreadRadius: size * 0.02,
            offset: Offset(0, size * 0.06),
          ),
          BoxShadow(
            color: glow.withOpacity(0.18),
            blurRadius: size * 0.20,
            spreadRadius: 0,
            offset: Offset(0, size * 0.02),
          ),
        ],
        // Gradient ring border
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D8EE8), Color(0xFF0B2447)],
        ),
      ),
      child: Padding(
        // Thin ring border gap
        padding: EdgeInsets.all(size * 0.038),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.10),
              child: SvgPicture.asset(
                'assets/logo.svg',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AnimatedLogo — softly pulsing version of AppointlyLogo
// ─────────────────────────────────────────────────────────────────────────────
class AnimatedLogo extends StatefulWidget {
  final double size;
  final Color? glowColor;
  final bool pulse;

  const AnimatedLogo({
    super.key,
    this.size = 56,
    this.glowColor,
    this.pulse = true,
  });

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
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
      builder: (_, __) => Transform.scale(
        scale: widget.pulse ? _pulse.value : 1.0,
        child: AppointlyLogo(size: widget.size, glowColor: widget.glowColor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LogoBadge — compact rounded-rect app icon style badge
//  Used in the drawer and other compact spots.
// ─────────────────────────────────────────────────────────────────────────────
class LogoBadge extends StatelessWidget {
  final double size;
  final List<Color>? gradient;

  const LogoBadge({super.key, this.size = 52, this.gradient});

  @override
  Widget build(BuildContext context) {
    final grad = gradient ?? const [Color(0xFF3D8EE8), Color(0xFF0B2447)];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: grad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: grad.first.withOpacity(0.40),
            blurRadius: size * 0.45,
            offset: Offset(0, size * 0.10),
          ),
          BoxShadow(
            color: grad.last.withOpacity(0.25),
            blurRadius: size * 0.20,
            offset: Offset(0, size * 0.04),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(size * 0.14),
          // On a dark background, render SVG in white
          child: SvgPicture.asset(
            'assets/logo.svg',
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SpinningLogo — rotation loading indicator
// ─────────────────────────────────────────────────────────────────────────────
class SpinningLogo extends StatefulWidget {
  final double size;
  const SpinningLogo({super.key, this.size = 48});

  @override
  State<SpinningLogo> createState() => _SpinningLogoState();
}

class _SpinningLogoState extends State<SpinningLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: SvgPicture.asset(
        'assets/logo.svg',
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StaticLogo — bare SVG, no decoration
// ─────────────────────────────────────────────────────────────────────────────
class StaticLogo extends StatelessWidget {
  final double size;
  const StaticLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo.svg',
      width: size,
      height: size,
    );
  }
}
