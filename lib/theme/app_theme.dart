import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF1D63F2);
  static const Color _accentColor = Color(0xFF5A91FF);
  static const Color _lightBackground = Color(0xFFFFFFFF);
  static const Color _darkBackground = Color(0xFF151A1F);

  static ThemeData buildLightTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedColor,
      primary: _seedColor,
      secondary: _accentColor,
      surface: Colors.white,
      surfaceTint: Colors.white,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: _seedColor,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE3E8F3),
      onPrimaryContainer: const Color(0xFF163266),
      secondary: const Color(0xFF4F89FF),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE7EBF3),
      onSecondaryContainer: const Color(0xFF173666),
      tertiary: const Color(0xFF6D86B8),
      tertiaryContainer: const Color(0xFFE6E9F0),
      onTertiaryContainer: const Color(0xFF263C69),
      surface: const Color(0xFFF3F4F6),
      surfaceTint: const Color(0xFFF3F4F6),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFEFEFF2),
      surfaceContainer: const Color(0xFFE8E9ED),
      surfaceContainerHigh: const Color(0xFFE1E3E8),
      surfaceContainerHighest: const Color(0xFFD9DCE2),
      outline: const Color(0xFFB2B8C2),
      outlineVariant: const Color(0xFFD2D6DE),
      onSurface: const Color(0xFF10213F),
      onSurfaceVariant: const Color(0xFF4F6287),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightBackground,
    );
  }

  static ThemeData buildDarkTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedColor,
      primary: const Color(0xFF4FC8C1),
      secondary: const Color(0xFFFFAF8E),
      brightness: Brightness.dark,
    );
    final ColorScheme colorScheme = base.copyWith(
      surface: const Color(0xFF1C232B),
      surfaceTint: const Color(0xFF1C232B),
      surfaceContainerLowest: const Color(0xFF11161B),
      surfaceContainerLow: const Color(0xFF171D24),
      surfaceContainer: const Color(0xFF1C232B),
      surfaceContainerHigh: const Color(0xFF252D36),
      surfaceContainerHighest: const Color(0xFF2E3741),
      outline: const Color(0xFF4A5561),
      outlineVariant: const Color(0xFF313A44),
      onSurface: const Color(0xFFE5EBF2),
      onSecondaryContainer: const Color(0xFFFFE4D7),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkBackground,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
  }) {
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerColor: colorScheme.outlineVariant,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            color: colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.4);
          }
          return colorScheme.surfaceContainerHigh;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(18),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(18),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
