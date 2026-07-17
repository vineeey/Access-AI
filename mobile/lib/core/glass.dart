import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'motion.dart';
import 'tokens.dart';

/// Liquid-glass surface: a real BackdropFilter blur under a translucent
/// gradient fill, wrapped in a 1px *specular* gradient border (bright at the
/// top-left where the "light" hits, fading away) and a soft depth shadow.
///
/// Tappable cards press down (scale 0.97 on the expo curve) with a selection
/// haptic — the signature tactile feel of the app. Pass [semanticLabel] to
/// expose a tappable card as a button to screen readers.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(T.s16),
    this.radius = T.rMd,
    this.blur = 20,
    this.onTap,
    this.onLongPress,
    this.tint,
    this.borderTint,
    this.glow = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Glass body tint. Defaults to the theme's surfaceContainer (deep navy).
  final Color? tint;

  /// Specular edge + glow colour. Defaults to white light.
  final Color? borderTint;

  /// When true the card emits a soft coloured glow (borderTint / primary)
  /// instead of a plain depth shadow — used for "live" or highlighted cards.
  final bool glow;

  final String? semanticLabel;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final highContrast = cs.outline == Colors.white ||
        cs.outline.toARGB32() == 0xFFFFFFFF;
    final base = widget.tint ?? cs.surfaceContainer;
    final edge = widget.borderTint ?? Colors.white;
    final r = BorderRadius.circular(widget.radius);

    // Inner glass: blur + translucent top-lit gradient fill.
    final Widget glass = ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withValues(alpha: highContrast ? 1.0 : 0.62),
                base.withValues(alpha: highContrast ? 1.0 : 0.38),
              ],
            ),
          ),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    // Specular 1px gradient border + depth shadow / glow.
    final Widget bordered = Container(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highContrast
              ? [cs.outline, cs.outline]
              : [
                  edge.withValues(alpha: 0.28),
                  edge.withValues(alpha: 0.06),
                  edge.withValues(alpha: 0.0),
                ],
          stops: highContrast ? const [0, 1] : const [0.0, 0.45, 1.0],
        ),
        boxShadow: highContrast
            ? null
            : [
                if (widget.glow)
                  BoxShadow(
                    color: (widget.borderTint ?? cs.primary)
                        .withValues(alpha: 0.30),
                    blurRadius: 32,
                    spreadRadius: -4,
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                    spreadRadius: -8,
                  ),
              ],
      ),
      padding: EdgeInsets.all(highContrast ? 2 : 1),
      child: glass,
    );

    if (widget.onTap == null && widget.onLongPress == null) return bordered;

    Widget pressable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _set(true);
        HapticFeedback.selectionClick();
      },
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: Motion.duration(context, T.fast),
        curve: Motion.curve(context),
        child: bordered,
      ),
    );
    if (widget.semanticLabel != null) {
      pressable = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: pressable,
      );
    }
    return pressable;
  }
}

/// The ambient "cinema" backdrop behind every screen: three soft aurora light
/// blobs (green / cyan / indigo) drifting slowly across a deep navy canvas.
/// When motion is reduced (or [animate] is false) the blobs hold still —
/// identical look, zero movement. Cheap: three radial gradients, no blur.
class GradientMesh extends StatefulWidget {
  const GradientMesh({super.key, this.animate = true});

  final bool animate;

  @override
  State<GradientMesh> createState() => _GradientMeshState();
}

class _GradientMeshState extends State<GradientMesh>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  void _sync(bool still) {
    if (still) {
      _c?.stop();
      return;
    }
    _c ??= AnimationController(
        vsync: this, duration: const Duration(seconds: 26));
    if (!_c!.isAnimating) _c!.repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = !widget.animate || context.reduceMotion;
    _sync(still);
    final c = _c;
    if (still || c == null) return _paint(0, dark);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => _paint(c.value, dark),
    );
  }

  Widget _paint(double t, bool dark) {
    final a = t * 2 * math.pi;
    Alignment orbit(double phase, double rx, double ry) =>
        Alignment(rx * math.cos(a + phase), ry * math.sin(a + phase));

    final strength = dark ? 1.0 : 0.55;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [T.bg2, T.bg]
              : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Blob(
            color: T.mesh2,
            alignment: orbit(0.4, 0.9, 0.7) + const Alignment(-0.4, -0.5),
            size: 1.3,
            opacity: 0.16 * strength,
          ),
          _Blob(
            color: T.mesh3,
            alignment: orbit(2.5, 0.7, 0.9) + const Alignment(0.6, 0.2),
            size: 1.1,
            opacity: 0.14 * strength,
          ),
          _Blob(
            color: T.mesh1,
            alignment: orbit(4.6, 0.8, 0.6) + const Alignment(-0.2, 0.8),
            size: 1.0,
            opacity: 0.10 * strength,
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.alignment,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final Alignment alignment;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: size,
        heightFactor: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gyroscope parallax — the "liquid" in liquid glass. Wrap a *small* hero
/// element (not a whole screen) and it drifts a few pixels against device
/// tilt. Uses a ValueNotifier so the child is never rebuilt, only translated.
/// Off entirely under reduce-motion or when the device has no accelerometer.
class ParallaxTilt extends StatefulWidget {
  const ParallaxTilt({super.key, required this.child, this.strength = 10});

  final Widget child;

  /// Max translation in logical pixels.
  final double strength;

  @override
  State<ParallaxTilt> createState() => _ParallaxTiltState();
}

class _ParallaxTiltState extends State<ParallaxTilt> {
  StreamSubscription<AccelerometerEvent>? _sub;
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);
  double _x = 0, _y = 0;

  @override
  void initState() {
    super.initState();
    try {
      _sub = accelerometerEventStream(
              samplingPeriod: SensorInterval.uiInterval)
          .listen((e) {
        // Low-pass filter so the drift is silky, not jittery.
        _x = _x * 0.88 + (-e.x / 9.81) * 0.12;
        _y = _y * 0.88 + (e.y / 9.81 - 1.0) * 0.12;
        final s = widget.strength;
        _offset.value = Offset(
          (_x * s * 2).clamp(-s, s),
          (_y * s * 2).clamp(-s, s),
        );
      }, onError: (_) {}, cancelOnError: true);
    } catch (_) {
      // No sensor (desktop / emulator) — hold still.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return ValueListenableBuilder<Offset>(
      valueListenable: _offset,
      child: widget.child,
      builder: (context, o, child) =>
          Transform.translate(offset: o, child: child),
    );
  }
}

/// A breathing aurora ring — the Jarvis identity mark. Used behind the mic
/// button and in the wake-word UI: a conic cyan→indigo→violet sweep that
/// slowly rotates and gently scales ("breathes"). [active] speeds it up and
/// brightens it (listening); reduce-motion renders it as a still ring.
class AuroraRing extends StatefulWidget {
  const AuroraRing({
    super.key,
    this.size = 180,
    this.thickness = 5,
    this.active = false,
    this.child,
  });

  final double size;
  final double thickness;
  final bool active;
  final Widget? child;

  @override
  State<AuroraRing> createState() => _AuroraRingState();
}

class _AuroraRingState extends State<AuroraRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  void _sync(bool still) {
    if (still) {
      _c?.stop();
      return;
    }
    _c ??= AnimationController(vsync: this, duration: T.xslow * 4);
    final target = widget.active ? T.xslow * 1.5 : T.xslow * 4;
    if (_c!.duration != target) _c!.duration = target;
    if (!_c!.isAnimating) _c!.repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = context.reduceMotion;
    _sync(still);
    final c = _c;
    final Widget core = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: widget.child),
    );
    if (still || c == null) {
      return CustomPaint(
        painter: _AuroraRingPainter(
          turn: 0,
          breathe: 1,
          thickness: widget.thickness,
          opacity: widget.active ? 1.0 : 0.7,
        ),
        child: core,
      );
    }
    return AnimatedBuilder(
      animation: c,
      child: core,
      builder: (context, child) {
        final t = c.value;
        final breathe = 1 + 0.03 * math.sin(t * 2 * math.pi * 2);
        return CustomPaint(
          painter: _AuroraRingPainter(
            turn: t,
            breathe: breathe,
            thickness: widget.thickness,
            opacity: widget.active ? 1.0 : 0.7,
          ),
          child: child,
        );
      },
    );
  }
}

class _AuroraRingPainter extends CustomPainter {
  _AuroraRingPainter({
    required this.turn,
    required this.breathe,
    required this.thickness,
    required this.opacity,
  });

  final double turn;
  final double breathe;
  final double thickness;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius =
        (math.min(size.width, size.height) / 2 - thickness) * breathe;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = SweepGradient(
      transform: GradientRotation(turn * 2 * math.pi),
      colors: [
        T.jarvis1.withValues(alpha: opacity),
        T.jarvis2.withValues(alpha: opacity),
        T.jarvis3.withValues(alpha: opacity),
        T.jarvis1.withValues(alpha: opacity),
      ],
    );
    // Soft outer glow.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = sweep.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Crisp ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = sweep.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness,
    );
  }

  @override
  bool shouldRepaint(_AuroraRingPainter old) =>
      old.turn != turn ||
      old.breathe != breathe ||
      old.opacity != opacity ||
      old.thickness != thickness;
}
