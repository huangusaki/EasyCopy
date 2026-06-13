import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

class AppRuntime {
  AppRuntime._();

  static const Size _defaultWindowSize = Size(1320, 860);

  static const Size _minimumWindowSize = Size(960, 640);

  static const int _desktopImageCacheBytes = 512 << 20;
  static const int _desktopImageCacheEntries = 4000;

  static const int _mobileImageCacheBytes = 200 << 20;
  static const int _mobileImageCacheEntries = 1500;

  static Future<void>? _initialization;

  static bool get _isRunningInTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    if (!PlatformCapabilities.isDesktop) {
      _tuneImageCache(
        maxEntries: _mobileImageCacheEntries,
        maxBytes: _mobileImageCacheBytes,
      );
      return;
    }
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    _tuneImageCache(
      maxEntries: _desktopImageCacheEntries,
      maxBytes: _desktopImageCacheBytes,
    );
    if (!_isRunningInTest) {
      await _bootstrapWindow();
    }
  }

  static void _tuneImageCache({
    required int maxEntries,
    required int maxBytes,
  }) {
    final ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = maxEntries;
    imageCache.maximumSizeBytes = maxBytes;
  }

  static Future<void> _bootstrapWindow() async {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      title: 'EasyCopy',
      size: _defaultWindowSize,
      minimumSize: _minimumWindowSize,
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
