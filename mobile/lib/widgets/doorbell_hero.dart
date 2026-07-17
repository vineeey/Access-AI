import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';

/// The signature animated smart-doorbell hero. Concentric "sound" rings pulse
/// outward from a glowing bell disc lit by the aurora gradient, evoking a ring
/// in progress. Fully self-contained (custom-painted, no external asset).
/// Motion-safe: when reduce-motion is on it renders a single static ring +
/// bell with no animation.
class DoorbellHero extends StatefulWidget {
  const DoorbellHero({
    super.key,
    this.size = 220,
    this.active = false,
    this.semanticLabel = 'AccessAI doorbell',
  });

  /// [active] pulses faster/brighter (e.g. while an event is fresh).
  final double size;
  final bool active;
  final String semanticLabel;

  @override
  State<DoorbellHero> createState() => _DoorbellHeroState();
}

class _DoorbellHeroState extends State<DoorbellHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = context.reduceMotion;

    // Drive/stop the loop based on motion preference.
    if (reduce) {
      if (_c.isAnimating) _c.stop();
    } else {
      if (!_c.isAnimating) _c.repeat();
    }

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return CustomPaint(
              painter: _DoorbellPainter(
                t: reduce ? 0.0 : _c.value,
                active: widget.active,
                ringColor: cs.primary,
                accent: T.accent,
                glow: cs.primary,
                animate: !reduce,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DoorbellPainter extends CustomPainter {
  _DoorbellPainter({
    required this.t,
    required this.active,
    required this.ringColor,
    required this.accent,
    required this.glow,
    required this.animate,
  });

  final double t; // 0..1 loop phase
  final bool active;
  final Color ringColor;
  final Color accent;
  final Color glow;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Pulsing rings — 3 staggered waves swept with the aurora gradient. With
    // animate off, draw one calm ring.
    final waves = animate ? 3 : 1;
    for (var i = 0; i < waves; i++) {
      final phase = animate ? (t + i / waves) % 1.0 : 0.55;
      final r = maxR * (0.28 + phase * 0.72);
      final fade = animate ? (1.0 - phase) : 0.5;
      final rect = Rect.fromCircle(center: center, radius: r);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (active ? 3.0 : 2.0)
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: [
            T.jarvis1.withValues(alpha: 0.45 * fade),
            ringColor.withValues(alpha: 0.40 * fade),
            T.jarvis2.withValues(alpha: 0.45 * fade),
            T.jarvis1.withValues(alpha: 0.45 * fade),
          ],
        ).createShader(rect);
      canvas.drawCircle(center, r, paint);
    }

    // Central glowing disc: a wide soft halo, then a glass-like gradient body
    // with a specular top-light.
    final discR = maxR * 0.30;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: active ? 0.85 : 0.55),
          glow.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: discR * 2.4));
    canvas.drawCircle(center, discR * 2.4, glowPaint);

    final disc = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ringColor, accent],
      ).createShader(Rect.fromCircle(center: center, radius: discR));
    canvas.drawCircle(center, discR, disc);

    // Specular highlight — the "liquid glass" light hit on the disc's top.
    final sheen = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 0.9,
        colors: [
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: discR));
    canvas.drawCircle(center, discR, sheen);

    // Thin bright rim.
    canvas.drawCircle(
      center,
      discR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Bell glyph.
    _drawBell(canvas, center, discR * 1.15, Colors.white);
  }

  void _drawBell(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    final w = s * 0.9;
    final h = s * 0.9;
    final top = c.dy - h * 0.55;
    // Bell body: a rounded dome flaring to a wide mouth.
    path.moveTo(c.dx - w * 0.5, c.dy + h * 0.30);
    path.quadraticBezierTo(
        c.dx - w * 0.5, top, c.dx, top - h * 0.10);
    path.quadraticBezierTo(
        c.dx + w * 0.5, top, c.dx + w * 0.5, c.dy + h * 0.30);
    path.lineTo(c.dx - w * 0.5, c.dy + h * 0.30);
    path.close();
    canvas.drawPath(path, p);
    // Clapper.
    canvas.drawCircle(Offset(c.dx, c.dy + h * 0.42), s * 0.14, p);
    // Top knob.
    canvas.drawCircle(Offset(c.dx, top - h * 0.16), s * 0.10, p);
  }

  @override
  bool shouldRepaint(_DoorbellPainter old) =>
      old.t != t || old.active != active || old.animate != animate;
}
