import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/easy_copy_screen.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/theme/app_theme.dart';
import 'package:flutter/material.dart';

class EasyCopyApp extends StatelessWidget {
  const EasyCopyApp({
    super.key,
    this.home,
    this.preferencesController,
  });

  final Widget? home;
  final AppPreferencesController? preferencesController;

  @override
  Widget build(BuildContext context) {
    final AppPreferencesController controller =
        preferencesController ?? AppPreferencesController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildLightTheme(),
          darkTheme: AppTheme.buildDarkTheme(),
          themeMode: controller.preferences.materialThemeMode,
          home: home ?? EasyCopyScreen(preferencesController: controller),
        );
      },
    );
  }
}
