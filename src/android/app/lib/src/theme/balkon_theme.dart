// Balkon-Borg theme, adapted from `design/flutter_theme.dart` (design export).
// Material 3 Expressive, dark-native + light variant.
//
// Migration note: the design export uses `ColorScheme.background`/
// `onBackground`, deprecated in current Flutter in favor of `surface`/
// `onSurface`. Both tokens already shared the same color value as their
// `surface`/`onSurface` counterparts in the export, so folding them in loses
// nothing; the design's separate "surface" token (one step above the screen
// background) moves to `BalkonExtras.surface` so all four background levels
// (bg/surface/surface2/surface3) stay addressable.

import 'package:flutter/material.dart';

/// Raw brand colors, independent of theme brightness.
class BalkonColors {
  BalkonColors._();

  // Dark theme
  static const darkBg = Color(0xFF0D0A17);
  static const darkSurface = Color(0xFF17111F);
  static const darkSurface2 = Color(0xFF1F1830);
  static const darkSurface3 = Color(0xFF291F3D);
  static const darkPrimary = Color(0xFFB57BFF);
  static const darkPrimaryStrong = Color(0xFF8B2FFF);
  static const darkAccent = Color(0xFFFF4FD8);
  static const darkCyan = Color(0xFF35E6FF);
  static const darkText = Color(0xFFF2ECFF);
  static const darkTextDim = Color(0xFFA99BC9);
  static const darkBorder = Color(0xFF332A49);

  // Light theme
  static const lightBg = Color(0xFFFAF8FD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF3EEFB);
  static const lightSurface3 = Color(0xFFECE4FA);
  static const lightPrimary = Color(0xFF7C3AED);
  static const lightPrimaryStrong = Color(0xFF6D28D9);
  static const lightAccent = Color(0xFFD6409F);
  static const lightCyan = Color(0xFF0891B2);
  static const lightText = Color(0xFF1C1530);
  static const lightTextDim = Color(0xFF6B6280);
  static const lightBorder = Color(0xFFE4DEF2);

  // Shared
  static const danger = Color(0xFFFF5470); // SENTRY armed / alarm state
}

/// Extra tokens Material's ColorScheme has no slot for (surface/surface2/3,
/// textDim, per-mode accents). Access via
/// `Theme.of(context).extension<BalkonExtras>()!`.
class BalkonExtras extends ThemeExtension<BalkonExtras> {
  final Color surface; // design token "surface" (one step above screen bg)
  final Color surface2;
  final Color surface3;
  final Color textDim;
  final Color cyan; // COMMS
  final Color accent; // LUMEN
  final Color danger; // SENTRY

  const BalkonExtras({
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.textDim,
    required this.cyan,
    required this.accent,
    required this.danger,
  });

  static const dark = BalkonExtras(
    surface: BalkonColors.darkSurface,
    surface2: BalkonColors.darkSurface2,
    surface3: BalkonColors.darkSurface3,
    textDim: BalkonColors.darkTextDim,
    cyan: BalkonColors.darkCyan,
    accent: BalkonColors.darkAccent,
    danger: BalkonColors.danger,
  );

  static const light = BalkonExtras(
    surface: BalkonColors.lightSurface,
    surface2: BalkonColors.lightSurface2,
    surface3: BalkonColors.lightSurface3,
    textDim: BalkonColors.lightTextDim,
    cyan: BalkonColors.lightCyan,
    accent: BalkonColors.lightAccent,
    danger: BalkonColors.danger,
  );

  @override
  BalkonExtras copyWith({
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? textDim,
    Color? cyan,
    Color? accent,
    Color? danger,
  }) =>
      BalkonExtras(
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        textDim: textDim ?? this.textDim,
        cyan: cyan ?? this.cyan,
        accent: accent ?? this.accent,
        danger: danger ?? this.danger,
      );

  @override
  BalkonExtras lerp(ThemeExtension<BalkonExtras>? other, double t) {
    if (other is! BalkonExtras) return this;
    return BalkonExtras(
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Radii — reuse across every card/sheet/control so the "no hard edges" rule holds.
class BalkonRadii {
  BalkonRadii._();
  static const screen = 42.0;
  static const sheet = 32.0;
  static const card = 28.0;
  static const sentryCard = 24.0;
  static const statTile = 20.0;
  static const chipWide = 16.0;
  static const chip = 14.0;
  static const badge = 13.0;
  static const bottomNav = 28.0;
  static const navItem = 20.0;
  static const pill = 999.0;
}

/// Spring-like overshoot curve used for nearly all direct-manipulation
/// feedback (card tap-scale, switch thumb, chip select, nav active state,
/// theme-toggle thumb slide).
/// Equivalent to CSS cubic-bezier(.34,1.56,.64,1).
const Curve balkonSpring = Cubic(0.34, 1.56, 0.64, 1.0);
const Duration balkonSpringDuration = Duration(milliseconds: 300);

/// Screen/tab-content enter transition (fade + rise + scale), motion.md §3.
const Curve balkonScreenEnterCurve = Cubic(0.22, 1.0, 0.36, 1.0);
const Duration balkonScreenEnterDuration = Duration(milliseconds: 450);

/// Bottom-sheet slide-up, motion.md §2.
const Curve balkonSheetCurve = Cubic(0.22, 1.1, 0.36, 1.0);
const Duration balkonSheetDuration = Duration(milliseconds: 380);

/// Sheet-backdrop fade, motion.md §4.
const Curve balkonBackdropCurve = Curves.ease;
const Duration balkonBackdropDuration = Duration(milliseconds: 250);

/// Light/dark crossfade, motion.md §5. Fed to `MaterialApp.themeAnimation*`,
/// which already wraps its child in an `AnimatedTheme`.
const Curve balkonThemeCrossfadeCurve = Curves.ease;
const Duration balkonThemeCrossfadeDuration = Duration(milliseconds: 400);

ThemeData buildBalkonTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;

  final colorScheme = isDark
      ? const ColorScheme.dark(
          surface: BalkonColors.darkBg,
          primary: BalkonColors.darkPrimary,
          secondary: BalkonColors.darkCyan,
          tertiary: BalkonColors.darkAccent,
          error: BalkonColors.danger,
          onSurface: BalkonColors.darkText,
          onPrimary: Colors.white,
          outline: BalkonColors.darkBorder,
        )
      : const ColorScheme.light(
          surface: BalkonColors.lightBg,
          primary: BalkonColors.lightPrimary,
          secondary: BalkonColors.lightCyan,
          tertiary: BalkonColors.lightAccent,
          error: BalkonColors.danger,
          onSurface: BalkonColors.lightText,
          onPrimary: Colors.white,
          outline: BalkonColors.lightBorder,
        );

  const bodyFont = 'Manrope';

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    fontFamily: bodyFont,
    extensions: [isDark ? BalkonExtras.dark : BalkonExtras.light],
    textTheme: TextTheme(
      // "screenTitle" — Guten Abend. / Vogel-Log title
      headlineMedium: TextStyle(fontFamily: bodyFont, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.26, color: colorScheme.onSurface),
      headlineLarge: TextStyle(fontFamily: bodyFont, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: colorScheme.onSurface),
      titleLarge: TextStyle(fontFamily: bodyFont, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.22, color: colorScheme.onSurface), // active card value / wordmark
      titleMedium: TextStyle(fontFamily: bodyFont, fontSize: 18, fontWeight: FontWeight.w800, color: colorScheme.onSurface), // sheet title
      titleSmall: TextStyle(fontFamily: bodyFont, fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant), // off-state card value
      bodyLarge: TextStyle(fontFamily: bodyFont, fontSize: 15, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
      bodyMedium: TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
      bodySmall: TextStyle(fontFamily: bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
      labelLarge: TextStyle(fontFamily: bodyFont, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: colorScheme.onSurfaceVariant), // eyebrow/section label, UPPERCASE in UI
      labelSmall: TextStyle(fontFamily: bodyFont, fontSize: 10, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
    ),
    // Mono numerals (Space Grotesk) are applied ad-hoc via a helper TextStyle
    // (see balkonMonoStyle below) rather than a TextTheme slot, since Flutter
    // has no built-in "monospace variant" concept per style.
  );
}

/// Helper for Space Grotesk numeric/mono text (clock, stat values, frequencies,
/// chart readouts). Use directly: Text('93.3 MHz', style: balkonMonoStyle(context, 19, FontWeight.w700))
TextStyle balkonMonoStyle(BuildContext context, double size, FontWeight weight) {
  final color = Theme.of(context).colorScheme.onSurface;
  return TextStyle(fontFamily: 'SpaceGrotesk', fontSize: size, fontWeight: weight, color: color);
}
