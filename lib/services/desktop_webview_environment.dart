import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/host_manager.dart';
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

  static Future<void> disposeControllerSafely(
    WebviewController controller,
  ) async {
    try {
      await controller.dispose();
    } on PlatformException catch (error) {
      // webview_windows 0.4.0's C++ dispose handler uses std::get_if<int64_t>
      // on the textureId argument, which fails with `invalid_id` when Flutter's
      // StandardMessageCodec encodes small texture IDs as int32_t.
      if (error.code == 'invalid_id') {
        return;
      }
      rethrow;
    }
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
          await disposeControllerSafely(controller);
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

    await HostManager.instance.ensureInitialized();
    final List<String> quicOrigins =
        <String>{
              ...HostManager.instance.knownHosts,
              HostManager.instance.currentHost,
            }
            .where((String host) => host.trim().isNotEmpty)
            .map((String host) {
              return '${host.trim().toLowerCase()}:443';
            })
            .toList(growable: false)
          ..sort();
    final String additionalArguments = <String>[
      '--enable-quic',
      if (quicOrigins.isNotEmpty)
        '--origin-to-force-quic-on=${quicOrigins.join(',')}',
    ].join(' ');

    try {
      await WebviewController.initializeEnvironment(
        userDataPath: userDataDirectory.path,
        additionalArguments: additionalArguments,
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
