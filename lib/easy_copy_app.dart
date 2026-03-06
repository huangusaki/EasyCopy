import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/easy_copy_screen.dart';
import 'package:flutter/material.dart';

class EasyCopyApp extends StatelessWidget {
  const EasyCopyApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E8B84),
      primary: const Color(0xFF0E8B84),
      secondary: const Color(0xFFFF7B54),
      surface: Colors.white,
      surfaceTint: Colors.white,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F1E8),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFF0E8B84).withValues(alpha: 0.14),
          labelTextStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              color: colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      home: home ?? const EasyCopyScreen(),
    );
  }
}
