import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/app_screen.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/wallpaper_storage.dart';
import 'package:reader/theme/app_theme.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:reader/widgets/cropped_wallpaper_image.dart';
import 'package:reader/widgets/responsive_layout.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, this.home, this.preferencesController});

  final Widget? home;
  final AppPreferencesController? preferencesController;

  /// 偏好任意一项变动（阅读设置、壁纸滑杆等）都会触发这里重建，
  /// 主题只随主题偏好与壁纸开关变化，缓存起来避免每次从头构建。
  static final Map<(AppThemePreference, bool, Brightness), ThemeData>
  _themeCache = <(AppThemePreference, bool, Brightness), ThemeData>{};

  static ThemeData _themeFor(
    AppPreferences preferences, {
    required bool wallpaperActive,
    required Brightness brightness,
  }) {
    return _themeCache.putIfAbsent(
      (preferences.themePreference, wallpaperActive, brightness),
      () =>
          (brightness == Brightness.dark
                  ? preferences.buildDarkTheme()
                  : preferences.buildLightTheme())
              .applyWallpaperOverlay(active: wallpaperActive),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPreferencesController controller =
        preferencesController ?? AppPreferencesController.instance;
    // 在 builder 外创建，保证实例不变，偏好变动时不连带重建整个 AppScreen。
    final Widget homeWidget =
        home ?? AppScreen(preferencesController: controller);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final WallpaperPreferences wallpaper =
            controller.preferences.wallpaperPreferences;
        final bool wallpaperActive = wallpaper.isActive;
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: _themeFor(
            controller.preferences,
            wallpaperActive: wallpaperActive,
            brightness: Brightness.light,
          ),
          darkTheme: _themeFor(
            controller.preferences,
            wallpaperActive: wallpaperActive,
            brightness: Brightness.dark,
          ),
          themeMode: controller.preferences.materialThemeMode,
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData mediaQuery = MediaQuery.of(context);
            final ThemeData theme = Theme.of(context);
            final Brightness brightness = theme.brightness;
            final Brightness iconBrightness = brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark;
            final Gradient? backgroundGradient = theme
                .extension<AppSemanticColors>()
                ?.backgroundGradient;
            Widget body = child ?? const SizedBox.shrink();
            if (wallpaperActive) {
              body = AppWallpaperBackground(wallpaper: wallpaper, child: body);
            } else if (backgroundGradient != null) {
              body = DecoratedBox(
                decoration: BoxDecoration(gradient: backgroundGradient),
                child: body,
              );
            }
            if (PlatformCapabilities.isDesktop) {
              body = ExcludeSemantics(child: body);
            }
            body = MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(
                  minScaleFactor: usesAndroidTabletLayout(context) ? 1.12 : 0,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: body,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness: brightness,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              child: body,
            );
          },
          home: homeWidget,
        );
      },
    );
  }
}

class AppWallpaperBackground extends StatelessWidget {
  const AppWallpaperBackground({
    required this.wallpaper,
    required this.child,
    super.key,
  });

  final WallpaperPreferences wallpaper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? path = WallpaperStorage.instance.resolvePathSync(
      wallpaper.imageFileName,
    );
    if (path == null) {
      return child;
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double scrimAlpha = (1.0 - wallpaper.brightness).clamp(0.0, 1.0);
    final double blur = wallpaper.blurSigma.clamp(
      0.0,
      WallpaperPreferences.maxBlurSigma,
    );
    return ColoredBox(
      color: colorScheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              child: CroppedWallpaperImage(
                path: path,
                cropLeft: wallpaper.cropLeft,
                cropTop: wallpaper.cropTop,
                cropWidth: wallpaper.cropWidth,
                cropHeight: wallpaper.cropHeight,
                blurSigma: blur,
              ),
            ),
          ),
          if (scrimAlpha > 0.001)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface.withValues(alpha: scrimAlpha),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
