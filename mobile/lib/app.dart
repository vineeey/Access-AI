import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'screens/nav_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/providers.dart';

/// Root of the app. Wires the theme choice (light / dark / follow-system /
/// high-contrast) to MaterialApp and gates the first run: until the user has
/// confirmed a server URL once, they see [OnboardingScreen]; afterwards the
/// full [NavShell]. High-contrast is a standalone dark-based scheme, so it's
/// applied to both [theme] and [darkTheme] with the mode forced to dark.
class AccessAIApp extends ConsumerWidget {
  const AccessAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeProvider);
    final configured = ref.watch(isConfiguredProvider);
    final (light, dark, mode) = _themes(choice);

    return MaterialApp(
      title: 'AccessAI',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      home: configured ? const NavShell() : const OnboardingScreen(),
    );
  }

  /// Resolve (light theme, dark theme, mode) for a theme choice. High-contrast
  /// is a distinct scheme rather than a variant, so both slots get it and the
  /// mode is pinned to dark to guarantee it's the one shown.
  (ThemeData, ThemeData, ThemeMode) _themes(AppThemeChoice c) {
    switch (c) {
      case AppThemeChoice.system:
        return (AppTheme.light(), AppTheme.dark(), ThemeMode.system);
      case AppThemeChoice.light:
        return (AppTheme.light(), AppTheme.dark(), ThemeMode.light);
      case AppThemeChoice.dark:
        return (AppTheme.light(), AppTheme.dark(), ThemeMode.dark);
      case AppThemeChoice.highContrast:
        final hc = AppTheme.highContrast();
        return (hc, hc, ThemeMode.dark);
    }
  }
}
