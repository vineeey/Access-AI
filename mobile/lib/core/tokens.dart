import 'package:flutter/material.dart';

/// Design tokens for AccessAI — the "Cinema Mobile" dark system.
///
/// One source of truth for spacing, radii, motion and the signature palette.
/// An 8pt spacing scale keeps rhythm consistent. The canvas is a deep navy
/// (never pure black — pure black kills the frosted-glass depth), lifted by an
/// aurora of green (primary / calls-to-action), amber (the doorbell) and a
/// cyan→indigo→violet "Jarvis" gradient that is the voice assistant's identity.
///
/// The token *names* are the app's public contract — screens reference `T.s16`,
/// `T.rMd`, `T.seed`, `T.accent`, `T.danger`, `T.minTouch`, `T.mesh1..3`,
/// `T.fast/med/slow`. Values evolve; names stay stable.
class T {
  T._();

  // ---- 8pt spacing scale ----
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;

  // ---- Corner radii (generous, liquid-glass leaning) ----
  static const double rSm = 14;
  static const double rMd = 22;
  static const double rLg = 30;
  static const double rXl = 40;
  static const double rPill = 999;

  // ---- Touch target — accessibility hard floor (comfortably above 48dp) ----
  static const double minTouch = 64;

  // ---- Cinema Mobile palette ----
  static const Color bg = Color(0xFF0B1120); // app canvas base (deepest)
  static const Color bg2 = Color(0xFF0F172A); // raised canvas / scaffold
  static const Color surface = Color(0xFF1E293B); // card / elevated glass tint
  static const Color surfaceHi = Color(0xFF273449); // pressed / hover
  static const Color fg = Color(0xFFF8FAFC); // primary text
  static const Color muted = Color(0xFF94A3B8); // secondary text
  static const Color faint = Color(0xFF64748B); // tertiary / hints
  static const Color hairline = Color(0xFF334155); // borders / dividers

  // Signature accents.
  static const Color seed = Color(0xFF22C55E); // primary / CTA green
  static const Color accent = Color(0xFFF59E0B); // doorbell amber
  static const Color danger = Color(0xFFEF4444); // spoof / errors
  static const Color success = Color(0xFF22C55E); // healthy status
  static const Color deafFlash = Color(0xFFF59E0B); // full-screen deaf alert

  // "Jarvis" aurora — the voice assistant's identity (cyan → indigo → violet).
  static const Color jarvis1 = Color(0xFF38BDF8); // sky cyan
  static const Color jarvis2 = Color(0xFF818CF8); // indigo
  static const Color jarvis3 = Color(0xFFC084FC); // violet

  // Gradient-mesh anchors (the ambient light blobs behind every screen).
  static const Color mesh1 = Color(0xFF22C55E);
  static const Color mesh2 = Color(0xFF38BDF8);
  static const Color mesh3 = Color(0xFF818CF8);

  // Convenience gradients.
  static const LinearGradient aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [jarvis1, jarvis2, jarvis3],
  );
  static const LinearGradient greenGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), seed],
  );

  // ---- Motion ----
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration med = Duration(milliseconds: 340);
  static const Duration slow = Duration(milliseconds: 620);
  static const Duration xslow = Duration(milliseconds: 1100);

  // Signature curves.
  // Expo-out — the glassy "settle": quick to leave, long soft landing.
  static const Cubic easeExpo = Cubic(0.16, 1.0, 0.3, 1.0);
  // Emphasized — Material 3 hero transitions.
  static const Cubic easeEmphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  // Springy — a touch of overshoot for playful, tactile presses.
  static const Cubic springy = Cubic(0.34, 1.56, 0.64, 1.0);
}
