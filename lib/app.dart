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

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, this.home, this.preferencesController});

  final Widget? home;
  final AppPreferencesController? preferencesController;

  @override
  Widget build(BuildContext context) {
    final AppPreferencesController controller =
        preferencesController ?? AppPreferencesController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final WallpaperPreferences wallpaper =
            controller.preferences.wallpaperPreferences;
        final bool wallpaperActive = wallpaper.isActive;
        final ThemeData lightTheme = controller.preferences.buildLightTheme();
        final ThemeData darkTheme = controller.preferences.buildDarkTheme();
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: lightTheme.applyWallpaperOverlay(active: wallpaperActive),
          darkTheme: darkTheme.applyWallpaperOverlay(active: wallpaperActive),
          themeMode: controller.preferences.materialThemeMode,
          builder: (BuildContext context, Widget? child) {
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
              // 桌面辅助功能语义树会持续报错并拖慢帧，先屏蔽。
              body = ExcludeSemantics(child: body);
            }
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
          home: home ?? AppScreen(preferencesController: controller),
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
            child: CroppedWallpaperImage(
              path: path,
              cropLeft: wallpaper.cropLeft,
              cropTop: wallpaper.cropTop,
              cropWidth: wallpaper.cropWidth,
              cropHeight: wallpaper.cropHeight,
              blurSigma: blur,
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
