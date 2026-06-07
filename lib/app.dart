import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/app_screen.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/wallpaper_storage.dart';
import 'package:reader/theme/app_theme.dart';

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
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: controller.preferences.buildLightTheme().applyWallpaperOverlay(
            active: wallpaperActive,
          ),
          darkTheme: controller.preferences
              .buildDarkTheme()
              .applyWallpaperOverlay(active: wallpaperActive),
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
    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) =>
              const SizedBox.shrink(),
    );
    if (blur > 0.01) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: image,
      );
    }
    return ColoredBox(
      color: colorScheme.surface.withValues(alpha: 1.0),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(child: image),
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
