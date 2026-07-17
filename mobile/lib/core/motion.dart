import 'package:flutter/material.dart';

import 'tokens.dart';

/// Motion-safety gate. Honours the OS "reduce motion" / "remove animations"
/// setting (MediaQuery.disableAnimations) and the "prefer legible / accessible
/// navigation" setting. When either is on we drop parallax, tilt, looping hero
/// motion and long transitions — but NEVER gate functionality. Everything
/// still works; it just holds still.
class Motion {
  Motion._();

  static bool reduced(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return false;
    return mq.disableAnimations || mq.accessibleNavigation;
  }

  /// A duration that collapses to (near) zero when motion is reduced, so
  /// implicit-animation widgets settle instantly instead of sliding.
  static Duration duration(BuildContext context, Duration full) =>
      reduced(context) ? Duration.zero : full;

  /// A curve that collapses to linear when motion is reduced (overshoot curves
  /// can look glitchy at near-zero durations).
  static Curve curve(BuildContext context, [Curve full = T.easeExpo]) =>
      reduced(context) ? Curves.linear : full;
}

/// Convenience: read the reduce-motion flag anywhere with `context.reduceMotion`.
extension MotionContext on BuildContext {
  bool get reduceMotion => Motion.reduced(this);
}

/// Staggered entrance helper — screens use `Entrance(index: i, child: ...)`
/// around list items / cards for the signature "cascade in" (fade + 24px rise
/// on the expo curve, 60ms apart). Renders instantly when motion is reduced.
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = T.med,
    this.offset = 24,
  });

  final Widget child;
  final int index;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + Duration(milliseconds: 60 * index),
      curve: T.easeExpo,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
