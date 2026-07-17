import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';

/// A small glass status pill with a glowing dot (or icon) + label. Used for
/// connection state, module health, and mode. Colour is conveyed by BOTH the
/// dot and the text (never colour alone — WCAG 1.4.1), and the whole pill is
/// one semantics node so a screen reader reads "Connected" not "green dot,
/// Connected". The dot breathes gently; it holds still under reduce-motion.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? label,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s12, vertical: T.s8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(T.rPill),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 14,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 16, color: color)
            else
              _BreathingDot(color: color),
            const SizedBox(width: T.s8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pill's glowing dot: a slow opacity breath. Still under reduce-motion.
class _BreathingDot extends StatefulWidget {
  const _BreathingDot({required this.color});

  final Color color;

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  void _sync(bool still) {
    if (still) {
      _c?.stop();
      return;
    }
    _c ??= AnimationController(vsync: this, duration: T.xslow * 2);
    if (!_c!.isAnimating) _c!.repeat(reverse: true);
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
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.7),
            blurRadius: 8,
          ),
        ],
      ),
    );
    final c = _c;
    if (still || c == null) return dot;
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: dot,
    );
  }
}

/// Maps a module `state` string to a semantic colour.
Color stateColor(String state) => switch (state) {
      'ok' => T.success,
      'placeholder' => T.accent,
      'unavailable' => T.danger,
      _ => const Color(0xFF8A8F98), // off / unknown — neutral grey
    };
