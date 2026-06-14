import 'package:flutter/material.dart';
import 'package:reader/utils/platform_capabilities.dart';

class _SoftFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SoftFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: child,
      ),
    );
  }
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    this.backgroundGradient,
  });

  final Color success;

  final Color onSuccess;

  final Color successContainer;

  final Gradient? backgroundGradient;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Gradient? backgroundGradient,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
    );
  }

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      backgroundGradient: t < 0.5
          ? backgroundGradient
          : other.backgroundGradient,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const Color _seedBrown = Color(0xFF7A4A2F);
  static const Color _accentOrange = Color(0xFFFF7A3D);
  static const Color _accentOrangeDeep = Color(0xFFE85F1F);

  static const Color _warmLightBackground = Color(0xFFFAF6EE);
  static const Color _warmDarkBackground = Color(0xFF1B130D);

  static const AppSemanticColors _warmLightSemanticColors = AppSemanticColors(
    success: Color(0xFF18A558),
    onSuccess: Colors.white,
    successContainer: Color(0xFFCFEBD9),
  );

  static const AppSemanticColors _warmDarkSemanticColors = AppSemanticColors(
    success: Color(0xFF4CC58A),
    onSuccess: Color(0xFF053018),
    successContainer: Color(0xFF124C2C),
  );

  static ThemeData buildWarmLightTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedBrown,
      primary: _seedBrown,
      secondary: _accentOrange,
      surface: _warmLightBackground,
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
      surface: _warmLightBackground,
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
      scaffoldBackgroundColor: _warmLightBackground,
      semanticColors: _warmLightSemanticColors,
    );
  }

  static ThemeData buildWarmDarkTheme() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _seedBrown,
      primary: const Color(0xFFE3B695),
      secondary: _accentOrange,
      brightness: Brightness.dark,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: const Color(0xFFEFC09A),
      onPrimary: const Color(0xFF44260D),
      primaryContainer: const Color(0xFF6A4426),
      onPrimaryContainer: const Color(0xFFFBDFC5),
      secondary: _accentOrange,
      onSecondary: const Color(0xFF401600),
      secondaryContainer: const Color(0xFF7A3411),
      onSecondaryContainer: const Color(0xFFFFE0CC),
      tertiary: const Color(0xFFDCB98B),
      surface: _warmDarkBackground,
      surfaceTint: _accentOrangeDeep,
      surfaceContainerLowest: const Color(0xFF140D08),
      surfaceContainerLow: const Color(0xFF20160F),
      surfaceContainer: const Color(0xFF281C14),
      surfaceContainerHigh: const Color(0xFF33251B),
      surfaceContainerHighest: const Color(0xFF3F2F23),
      outline: const Color(0xFF6E5C4B),
      outlineVariant: const Color(0xFF463A2D),
      onSurface: const Color(0xFFF3E9DD),
      onSurfaceVariant: const Color(0xFFC5B4A1),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _warmDarkBackground,
      semanticColors: _warmDarkSemanticColors,
    );
  }

  static ThemeData buildBluePinkTheme() {
    const Color blueSeed = Color(0xFF6B7FE8);
    const Color pinkSeed = Color(0xFFE85F95);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: blueSeed,
      primary: blueSeed,
      secondary: pinkSeed,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: blueSeed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDDE2FF),
      onPrimaryContainer: const Color(0xFF1F2D7A),
      secondary: pinkSeed,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFD9E8),
      onSecondaryContainer: const Color(0xFF7A1F47),
      tertiary: const Color(0xFFA875D6),
      tertiaryContainer: const Color(0xFFEFDDFE),
      onTertiaryContainer: const Color(0xFF42196E),
      surface: const Color(0xFFFAF0F6),
      surfaceTint: blueSeed,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8EDF4),
      surfaceContainer: const Color(0xFFF1E4ED),
      surfaceContainerHigh: const Color(0xFFEAD9E5),
      surfaceContainerHighest: const Color(0xFFE2CDDD),
      outline: const Color(0xFFB69EAD),
      outlineVariant: const Color(0xFFE5D2DC),
      onSurface: const Color(0xFF2D1F2A),
      onSurfaceVariant: const Color(0xFF6E5566),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      semanticColors: const AppSemanticColors(
        success: Color(0xFF2E9E62),
        onSuccess: Colors.white,
        successContainer: Color(0xFFCFE9DA),
        backgroundGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFC9D5FF),
            Color(0xFFEEDBF1),
            Color(0xFFFFCEDF),
          ],
          stops: <double>[0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  static ThemeData buildPureWhiteTheme() {
    const Color inkSeed = Color(0xFF1A1A1A);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: inkSeed,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: inkSeed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8E8E8),
      onPrimaryContainer: inkSeed,
      secondary: const Color(0xFF404040),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEEEEEE),
      onSecondaryContainer: inkSeed,
      tertiary: const Color(0xFF555555),
      tertiaryContainer: const Color(0xFFE0E0E0),
      onTertiaryContainer: inkSeed,
      surface: const Color(0xFFFFFFFF),
      surfaceTint: inkSeed,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFAFAFA),
      surfaceContainer: const Color(0xFFF4F4F4),
      surfaceContainerHigh: const Color(0xFFEDEDED),
      surfaceContainerHighest: const Color(0xFFE5E5E5),
      outline: const Color(0xFFBDBDBD),
      outlineVariant: const Color(0xFFE0E0E0),
      onSurface: inkSeed,
      onSurfaceVariant: const Color(0xFF666666),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      semanticColors: const AppSemanticColors(
        success: Color(0xFF16A34A),
        onSuccess: Colors.white,
        successContainer: Color(0xFFDCFCE7),
      ),
    );
  }

  static ThemeData buildPureBlackTheme() {
    const Color paperSeed = Color(0xFFFFFFFF);
    // 浅灰强调色避免选中态过亮。
    const Color accentGray = Color(0xFFD6D6D6);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: paperSeed,
      brightness: Brightness.dark,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: accentGray,
      onPrimary: const Color(0xFF141414),
      primaryContainer: const Color(0xFF2E2E2E),
      onPrimaryContainer: const Color(0xFFECECEC),
      secondary: const Color(0xFFADADAD),
      onSecondary: const Color(0xFF141414),
      secondaryContainer: const Color(0xFF333333),
      onSecondaryContainer: const Color(0xFFECECEC),
      tertiary: const Color(0xFF8C8C8C),
      tertiaryContainer: const Color(0xFF292929),
      onTertiaryContainer: const Color(0xFFECECEC),
      surface: const Color(0xFF000000),
      surfaceTint: accentGray,
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF080808),
      surfaceContainer: const Color(0xFF101010),
      surfaceContainerHigh: const Color(0xFF181818),
      surfaceContainerHighest: const Color(0xFF242424),
      outline: const Color(0xFF5A5A5A),
      outlineVariant: const Color(0xFF363636),
      onSurface: paperSeed,
      onSurfaceVariant: const Color(0xFFB8B8B8),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      semanticColors: const AppSemanticColors(
        success: Color(0xFF22C55E),
        onSuccess: Color(0xFF052E14),
        successContainer: Color(0xFF14532D),
      ),
    );
  }

  static ThemeData buildLightBlueGreenTheme() {
    const Color blueSeed = Color(0xFF5B9CC4);
    const Color greenSeed = Color(0xFF5FB48A);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: blueSeed,
      primary: blueSeed,
      secondary: greenSeed,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: blueSeed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD3EAFB),
      onPrimaryContainer: const Color(0xFF103E5E),
      secondary: greenSeed,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFD2EFDF),
      onSecondaryContainer: const Color(0xFF124430),
      tertiary: const Color(0xFF6EB4B0),
      tertiaryContainer: const Color(0xFFD8EEEC),
      onTertiaryContainer: const Color(0xFF143C3A),
      surface: const Color(0xFFF1F8F5),
      surfaceTint: blueSeed,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFEAF4F1),
      surfaceContainer: const Color(0xFFE0EEEB),
      surfaceContainerHigh: const Color(0xFFD2E6E2),
      surfaceContainerHighest: const Color(0xFFC1DBD7),
      outline: const Color(0xFF94B5AD),
      outlineVariant: const Color(0xFFCFE0DA),
      onSurface: const Color(0xFF1B2C28),
      onSurfaceVariant: const Color(0xFF53685F),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      semanticColors: const AppSemanticColors(
        success: Color(0xFF2D8E4F),
        onSuccess: Colors.white,
        successContainer: Color(0xFFC9E7D4),
        backgroundGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFC4E0FF),
            Color(0xFFD2E9DD),
            Color(0xFFC0E8CB),
          ],
          stops: <double>[0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  static ThemeData buildLightOrangeTheme() {
    const Color orangeSeed = Color(0xFFE07B3F);
    const Color softPeachBackground = Color(0xFFFFF3E6);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: orangeSeed,
      primary: orangeSeed,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: orangeSeed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE0C4),
      onPrimaryContainer: const Color(0xFF5C2A0C),
      secondary: const Color(0xFFD96A38),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFD7BC),
      onSecondaryContainer: const Color(0xFF5C2A0C),
      tertiary: const Color(0xFFB07852),
      tertiaryContainer: const Color(0xFFF6DCC4),
      onTertiaryContainer: const Color(0xFF44230B),
      surface: softPeachBackground,
      surfaceTint: orangeSeed,
      surfaceContainerLowest: const Color(0xFFFFFAF3),
      surfaceContainerLow: const Color(0xFFFCEEDD),
      surfaceContainer: softPeachBackground,
      surfaceContainerHigh: const Color(0xFFF6DEC4),
      surfaceContainerHighest: const Color(0xFFEFCFAB),
      outline: const Color(0xFFC19E83),
      outlineVariant: const Color(0xFFE8D2BD),
      onSurface: const Color(0xFF2C1A0E),
      onSurfaceVariant: const Color(0xFF6E5340),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: softPeachBackground,
      semanticColors: const AppSemanticColors(
        success: Color(0xFF18A558),
        onSuccess: Colors.white,
        successContainer: Color(0xFFCFEBD9),
      ),
    );
  }

  static ThemeData buildSoftGreenTheme() {
    const Color greenSeed = Color(0xFF4A7B5A);
    const Color softGreenBackground = Color(0xFFC7EDCC);

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: greenSeed,
      primary: greenSeed,
      brightness: Brightness.light,
    );
    final ColorScheme colorScheme = base.copyWith(
      primary: greenSeed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD4EDD9),
      onPrimaryContainer: const Color(0xFF1F4530),
      secondary: const Color(0xFF7DB48A),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDDF0E2),
      onSecondaryContainer: const Color(0xFF234735),
      tertiary: const Color(0xFF9F8B5C),
      tertiaryContainer: const Color(0xFFEEE3C9),
      onTertiaryContainer: const Color(0xFF3F3215),
      surface: softGreenBackground,
      surfaceTint: greenSeed,
      surfaceContainerLowest: const Color(0xFFE8F5EB),
      surfaceContainerLow: const Color(0xFFD6EFDA),
      surfaceContainer: softGreenBackground,
      surfaceContainerHigh: const Color(0xFFB9DEBE),
      surfaceContainerHighest: const Color(0xFFA8CFAD),
      outline: const Color(0xFF87A88E),
      outlineVariant: const Color(0xFFB0CCB5),
      onSurface: const Color(0xFF1F2D24),
      onSurfaceVariant: const Color(0xFF4A6552),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: softGreenBackground,
      semanticColors: const AppSemanticColors(
        success: Color(0xFF2D8E4F),
        onSuccess: Colors.white,
        successContainer: Color(0xFFB9DEBE),
      ),
    );
  }

  static ThemeData buildDynamicTheme(ColorScheme dynamicScheme) {
    final bool isDark = dynamicScheme.brightness == Brightness.dark;
    final Color accent = dynamicScheme.primary;

    // 系统取色生成的表面色偏中性，叠少量强调色增强取色感。
    Color tinted(Color base, double amount) =>
        Color.alphaBlend(accent.withValues(alpha: amount), base);

    final Color surfaceBase = isDark
        ? const Color(0xFF12100F)
        : const Color(0xFFFBFAF9);

    final ColorScheme scheme = dynamicScheme.copyWith(
      surface: tinted(surfaceBase, isDark ? 0.08 : 0.05),
      surfaceContainerLowest: tinted(
        isDark ? const Color(0xFF0A0908) : const Color(0xFFFFFFFF),
        isDark ? 0.04 : 0.02,
      ),
      surfaceContainerLow: tinted(surfaceBase, isDark ? 0.10 : 0.06),
      surfaceContainer: tinted(surfaceBase, isDark ? 0.13 : 0.08),
      surfaceContainerHigh: tinted(surfaceBase, isDark ? 0.16 : 0.11),
      surfaceContainerHighest: tinted(surfaceBase, isDark ? 0.20 : 0.14),
      surfaceTint: accent,
    );

    return _buildTheme(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      semanticColors: isDark
          ? _warmDarkSemanticColors
          : _warmLightSemanticColors,
    );
  }

  /// 桌面中文回退字体栈。
  static const String _windowsLatinFont = 'Segoe UI';
  static const List<String> _simplifiedHanFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans SC',
  ];

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required AppSemanticColors semanticColors,
  }) {
    final bool useWindowsFontStack = PlatformCapabilities.isWindows;
    final ThemeData theme = ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: _SoftFadePageTransitionsBuilder(),
          TargetPlatform.linux: _SoftFadePageTransitionsBuilder(),
          TargetPlatform.macOS: _SoftFadePageTransitionsBuilder(),
        },
      ),
      fontFamily: useWindowsFontStack ? _windowsLatinFont : null,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerColor: colorScheme.outlineVariant,
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(999),
        crossAxisMargin: 3,
        mainAxisMargin: 6,
        interactive: true,
        thickness: WidgetStateProperty.resolveWith<double>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.hovered) ? 8 : 5,
        ),
        thumbColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.dragged)) {
            return colorScheme.primary.withValues(alpha: 0.75);
          }
          if (states.contains(WidgetState.hovered)) {
            return colorScheme.onSurface.withValues(alpha: 0.4);
          }
          return colorScheme.onSurface.withValues(alpha: 0.22);
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.62),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: colorScheme.secondaryContainer.withValues(alpha: 0.78),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            color: colorScheme.onSurface,
            fontSize: 11,
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
    if (!useWindowsFontStack) {
      return theme;
    }
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: _windowsLatinFont,
        fontFamilyFallback: _simplifiedHanFallback,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: _windowsLatinFont,
        fontFamilyFallback: _simplifiedHanFallback,
      ),
    );
  }
}

extension WallpaperThemeOverlay on ThemeData {
  ThemeData applyWallpaperOverlay({required bool active}) {
    if (!active) {
      return this;
    }
    final ColorScheme baseScheme = colorScheme;
    final ColorScheme overlayScheme = baseScheme.copyWith(
      surface: baseScheme.surface.withValues(alpha: 0.78),
      surfaceContainerLowest: baseScheme.surfaceContainerLowest.withValues(
        alpha: 0.78,
      ),
      surfaceContainerLow: baseScheme.surfaceContainerLow.withValues(
        alpha: 0.82,
      ),
      surfaceContainer: baseScheme.surfaceContainer.withValues(alpha: 0.84),
      surfaceContainerHigh: baseScheme.surfaceContainerHigh.withValues(
        alpha: 0.86,
      ),
      surfaceContainerHighest: baseScheme.surfaceContainerHighest.withValues(
        alpha: 0.88,
      ),
    );
    final CardThemeData baseCardTheme = cardTheme;
    final BottomSheetThemeData baseBottomSheetTheme = bottomSheetTheme;
    final NavigationBarThemeData baseNavigationBarTheme = navigationBarTheme;
    final InputDecorationThemeData baseInputDecorationTheme =
        inputDecorationTheme;
    return copyWith(
      colorScheme: overlayScheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardTheme: baseCardTheme.copyWith(
        color: overlayScheme.surface.withValues(alpha: 0.8),
      ),
      bottomSheetTheme: baseBottomSheetTheme.copyWith(
        backgroundColor: overlayScheme.surface.withValues(alpha: 0.92),
      ),
      navigationBarTheme: baseNavigationBarTheme.copyWith(
        backgroundColor: overlayScheme.surface.withValues(alpha: 0.4),
      ),
      inputDecorationTheme: baseInputDecorationTheme.copyWith(
        fillColor: overlayScheme.surfaceContainerLow,
      ),
    );
  }
}
