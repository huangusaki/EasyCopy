import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:webview_windows/webview_windows.dart';

class DesktopWebViewUnavailableException implements Exception {
  const DesktopWebViewUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DesktopWebViewEnvironment {
  DesktopWebViewEnvironment._();

  static final DesktopWebViewEnvironment instance =
      DesktopWebViewEnvironment._();

  Future<void>? _initialization;

  Future<void> ensureReady() {
    return _initialization ??= _initialize();
  }

  Future<void> clearCookies() async {
    if (!PlatformCapabilities.supportsDesktopWebView) {
      return;
    }
    try {
      await ensureReady();
      final WebviewController controller = WebviewController();
      bool initialized = false;
      try {
        await controller.initialize();
        initialized = true;
        await controller.clearCookies();
        await controller.clearCache();
      } finally {
        if (initialized) {
          await controller.dispose();
        }
      }
    } on DesktopWebViewUnavailableException {
      return;
    }
  }

  Future<void> _initialize() async {
    if (!PlatformCapabilities.supportsDesktopWebView) {
      throw const DesktopWebViewUnavailableException('当前系统不支持网页登录');
    }

    final String? version = await WebviewController.getWebViewVersion();
    if ((version ?? '').trim().isEmpty) {
      throw const DesktopWebViewUnavailableException(
        '缺少 WebView2 Runtime，无法打开网页登录。',
      );
    }

    final Directory supportDirectory = await getApplicationSupportDirectory();
    final Directory userDataDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}webview2',
    );
    await userDataDirectory.create(recursive: true);

    try {
      await WebviewController.initializeEnvironment(
        userDataPath: userDataDirectory.path,
      );
    } on PlatformException catch (error) {
      final String message = (error.message ?? error.code).toLowerCase();
      if (message.contains('initialized') || message.contains('initialize')) {
        return;
      }
      throw DesktopWebViewUnavailableException(
        error.message ?? 'WebView2 初始化失败。',
      );
    }
  }
}
