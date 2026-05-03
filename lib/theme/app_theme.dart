import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _seedBrown = Color(0xFF7A4A2F);
  static const Color _accentOrange = Color(0xFFFF7A3D);
  static const Color _accentOrangeDeep = Color(0xFFE85F1F);

  static const Color _lightBackground = Color(0xFFFAF6EE);
  static const Color _darkBackground = Color(0xFF18130E);

  static ThemeData buildLightTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedBrown,
      primary: _seedBrown,
      secondary: _accentOrange,
      surface: _lightBackground,
      surfaceTint: _seedBrown,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: _seedBrown,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFF2DCC4),
      onPrimaryContainer: const Color(0xFF3F2412),
      secondary: _accentOrange,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFE2CB),
      onSecondaryContainer: const Color(0xFF6B2A05),
      tertiary: const Color(0xFF9A6F3F),
      tertiaryContainer: const Color(0xFFEFD9B7),
      onTertiaryContainer: const Color(0xFF3D2710),
      surface: _lightBackground,
      surfaceTint: _seedBrown,
      surfaceContainerLowest: const Color(0xFFFFFCF4),
      surfaceContainerLow: const Color(0xFFF4ECDB),
      surfaceContainer: const Color(0xFFEDE3CD),
      surfaceContainerHigh: const Color(0xFFE5D9BE),
      surfaceContainerHighest: const Color(0xFFDBCCAB),
      outline: const Color(0xFFB0A48E),
      outlineVariant: const Color(0xFFDFD4BB),
      onSurface: const Color(0xFF2A211A),
      onSurfaceVariant: const Color(0xFF6B5C4B),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightBackground,
    );
  }

  static ThemeData buildDarkTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedBrown,
      primary: const Color(0xFFE3B695),
      secondary: _accentOrange,
      brightness: Brightness.dark,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: const Color(0xFFE3B695),
      onPrimary: const Color(0xFF3A1F0E),
      primaryContainer: const Color(0xFF5C3A22),
      onPrimaryContainer: const Color(0xFFF4DAC2),
      secondary: _accentOrange,
      onSecondary: const Color(0xFF3A1500),
      secondaryContainer: const Color(0xFF6B2A05),
      onSecondaryContainer: const Color(0xFFFFE2CB),
      tertiary: const Color(0xFFD4B387),
      surface: _darkBackground,
      surfaceTint: _accentOrangeDeep,
      surfaceContainerLowest: const Color(0xFF120E08),
      surfaceContainerLow: const Color(0xFF1C170F),
      surfaceContainer: const Color(0xFF221C13),
      surfaceContainerHigh: const Color(0xFF2B231A),
      surfaceContainerHighest: const Color(0xFF342B22),
      outline: const Color(0xFF5C5044),
      outlineVariant: const Color(0xFF3D352A),
      onSurface: const Color(0xFFECE5D8),
      onSurfaceVariant: const Color(0xFFB7AC9B),
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
        indicatorColor: colorScheme.secondary.withValues(alpha: 0.22),
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
