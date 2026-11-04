import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Hell- und Dunkel-Theme aus der Markenpalette. Rollen werden explizit gesetzt, statt sie aus einer
/// Seed-Farbe generieren zu lassen, damit die Töne genau der Palette entsprechen.
abstract final class AppTheme {
  static ThemeData light() => _build(const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.espresso,
        onPrimary: Colors.white,
        primaryContainer: AppColors.sky,
        onPrimaryContainer: AppColors.espresso,
        secondary: AppColors.blueDeep,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFD9E7F4),
        onSecondaryContainer: AppColors.espresso,
        tertiary: AppColors.dusk,
        onTertiary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        surface: AppColors.linen,
        onSurface: AppColors.espresso,
        onSurfaceVariant: AppColors.taupe,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFFBF8F5),
        surfaceContainer: Color(0xFFF2EDE8),
        surfaceContainerHigh: Color(0xFFEFE9E3),
        surfaceContainerHighest: AppColors.sand,
        outline: AppColors.taupe,
        outlineVariant: Color(0xFFDCD3CB),
      ));

  static ThemeData dark() => _build(const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.sky,
        onPrimary: AppColors.roast,
        primaryContainer: Color(0xFF34495F),
        onPrimaryContainer: AppColors.sky,
        secondary: AppColors.dusk,
        onSecondary: AppColors.roast,
        secondaryContainer: Color(0xFF3A4757),
        onSecondaryContainer: AppColors.sky,
        tertiary: AppColors.greige,
        onTertiary: AppColors.roast,
        error: Color(0xFFE08A78),
        onError: AppColors.roast,
        surface: AppColors.roast,
        onSurface: Color(0xFFF1EBE6),
        onSurfaceVariant: AppColors.greige,
        surfaceContainerLowest: Color(0xFF17110F),
        surfaceContainerLow: Color(0xFF241B19),
        surfaceContainer: AppColors.cocoa,
        surfaceContainerHigh: Color(0xFF382B27),
        surfaceContainerHighest: AppColors.mocha,
        outline: Color(0xFFA0958C),
        outlineVariant: Color(0xFF4E3E38),
      ));

  static ThemeData _build(ColorScheme scheme) {
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: rounded, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: rounded, side: BorderSide(color: scheme.outline)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(activeTrackColor: scheme.secondary, thumbColor: scheme.secondary),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
