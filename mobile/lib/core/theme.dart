import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Which theme the user has chosen. High-contrast is a distinct, WCAG-AAA-leaning
/// scheme rather than a tweak on dark, so it can be validated independently.
enum AppThemeChoice { system, light, dark, highContrast }

extension AppThemeChoiceLabel on AppThemeChoice {
  String get label => switch (this) {
        AppThemeChoice.system => 'Follow system',
        AppThemeChoice.light => 'Light',
        AppThemeChoice.dark => 'Dark',
        AppThemeChoice.highContrast => 'High contrast',
      };

  String get id => name;

  static AppThemeChoice fromId(String? id) =>
      AppThemeChoice.values.firstWhere((e) => e.name == id,
          orElse: () => AppThemeChoice.system);
}

/// "Cinema Mobile" theming. Dark is the hero: deep navy canvas, explicit navy
/// surface ramp (fromSeed alone would tint surfaces green), green primary,
/// Jarvis cyan/violet as secondary/tertiary, Plus Jakarta Sans throughout.
/// Light stays a clean functional variant; high-contrast stays WCAG-AAA.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(_lightScheme(), Brightness.light);

  static ThemeData dark() => _base(_darkScheme(), Brightness.dark);

  static ColorScheme _darkScheme() =>
      ColorScheme.fromSeed(seedColor: T.seed, brightness: Brightness.dark)
          .copyWith(
        primary: T.seed,
        onPrimary: const Color(0xFF03130A),
        primaryContainer: const Color(0xFF14532D),
        onPrimaryContainer: const Color(0xFFBBF7D0),
        secondary: T.jarvis1,
        onSecondary: const Color(0xFF04121A),
        secondaryContainer: const Color(0xFF0B2E42),
        onSecondaryContainer: const Color(0xFFBAE6FD),
        tertiary: T.jarvis3,
        onTertiary: const Color(0xFF1B0B2E),
        tertiaryContainer: const Color(0xFF3B1E5A),
        onTertiaryContainer: const Color(0xFFE9D5FF),
        error: T.danger,
        onError: const Color(0xFF2A0606),
        errorContainer: const Color(0xFF4C1414),
        onErrorContainer: const Color(0xFFFECACA),
        surface: T.bg2,
        onSurface: T.fg,
        onSurfaceVariant: T.muted,
        surfaceContainerLowest: T.bg,
        surfaceContainerLow: const Color(0xFF131C2E),
        surfaceContainer: T.surface,
        surfaceContainerHigh: T.surfaceHi,
        surfaceContainerHighest: const Color(0xFF2E3D54),
        surfaceTint: Colors.transparent,
        outline: T.hairline,
        outlineVariant: const Color(0xFF22304A),
        inverseSurface: T.fg,
        onInverseSurface: T.bg,
      );

  static ColorScheme _lightScheme() =>
      ColorScheme.fromSeed(seedColor: T.seed, brightness: Brightness.light)
          .copyWith(
        primary: const Color(0xFF15803D),
        secondary: const Color(0xFF0369A1),
        tertiary: const Color(0xFF7C3AED),
        error: T.danger,
      );

  /// Maximised contrast: near-black surfaces, pure-white text, a bright accent.
  static ThemeData highContrast() {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFE600),
      onPrimary: Color(0xFF000000),
      secondary: Color(0xFF00E5FF),
      onSecondary: Color(0xFF000000),
      error: Color(0xFFFF5252),
      onError: Color(0xFF000000),
      surface: Color(0xFF000000),
      onSurface: Color(0xFFFFFFFF),
      surfaceContainerHighest: Color(0xFF1A1A1A),
      outline: Color(0xFFFFFFFF),
    );
    return _base(cs, Brightness.dark, highContrast: true);
  }

  static ThemeData _base(ColorScheme cs, Brightness brightness,
      {bool highContrast = false}) {
    final baseText = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    // Plus Jakarta Sans everywhere — heavy tight display, calm readable body.
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseText).copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
          textStyle: baseText.displayLarge,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2),
      displayMedium: GoogleFonts.plusJakartaSans(
          textStyle: baseText.displayMedium,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8),
      displaySmall: GoogleFonts.plusJakartaSans(
          textStyle: baseText.displaySmall,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5),
      headlineLarge: GoogleFonts.plusJakartaSans(
          textStyle: baseText.headlineLarge,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5),
      headlineMedium: GoogleFonts.plusJakartaSans(
          textStyle: baseText.headlineMedium,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3),
      headlineSmall: GoogleFonts.plusJakartaSans(
          textStyle: baseText.headlineSmall, fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.plusJakartaSans(
          textStyle: baseText.titleLarge,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2),
      titleMedium: GoogleFonts.plusJakartaSans(
          textStyle: baseText.titleMedium, fontWeight: FontWeight.w600),
      labelLarge: GoogleFonts.plusJakartaSans(
          textStyle: baseText.labelLarge, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor:
          highContrast ? cs.surface : cs.surfaceContainerLowest,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.comfortable,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: cs.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: cs.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: highContrast ? 0 : 2,
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rMd),
          side: highContrast
              ? BorderSide(color: cs.outline, width: 2)
              : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: highContrast ? cs.outline : cs.outlineVariant,
        thickness: 1,
        space: T.s24,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(T.minTouch, T.minTouch),
          padding:
              const EdgeInsets.symmetric(horizontal: T.s24, vertical: T.s16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rMd)),
          textStyle: textTheme.titleMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(T.minTouch, T.minTouch),
          side: BorderSide(
              color: highContrast ? cs.outline : cs.outlineVariant,
              width: highContrast ? 2 : 1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(T.minTouch, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rSm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(T.minTouch, T.minTouch),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rPill),
          side: BorderSide(
              color: highContrast ? cs.outline : cs.outlineVariant, width: 1),
        ),
        backgroundColor: highContrast
            ? cs.surface
            : cs.surfaceContainer.withValues(alpha: 0.6),
        labelStyle: textTheme.labelLarge?.copyWith(color: cs.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: T.s12, vertical: T.s10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: highContrast
            ? cs.surfaceContainerHighest
            : cs.surfaceContainer.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rSm),
          borderSide: BorderSide(
              color: highContrast ? cs.outline : cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rSm),
          borderSide: BorderSide(
              color: highContrast ? cs.outline : cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rSm),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: highContrast ? cs.surfaceContainerHighest : null,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rSm)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: Colors.transparent,
        indicatorColor: cs.primary.withValues(alpha: highContrast ? 1 : 0.20),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? cs.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? cs.primary : null),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
