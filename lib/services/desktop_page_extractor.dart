import 'dart:async';
import 'dart:convert';

import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/desktop_webview_environment.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/services/webview_page_payload_decoder.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:reader/webview/page_extractor_script.dart';
import 'package:webview_windows/webview_windows.dart';

class DesktopPageExtractor {
  DesktopPageExtractor._();

  static final DesktopPageExtractor instance = DesktopPageExtractor._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String _bridgeBootstrap = '''
(() => {
  window.easyCopyBridge = {
    postMessage: (message) => {
      try {
        chrome.webview.postMessage(JSON.parse(message));
      } catch (_) {
        chrome.webview.postMessage(message);
      }
    },
  };
})();
''';

  Future<SitePage> loadPage(Uri uri, {int? loadId}) async {
    if (!PlatformCapabilities.supportsDesktopWebView) {
      throw UnsupportedError('当前平台不支持桌面页面抽取');
    }

    await DesktopWebViewEnvironment.instance.ensureReady();
    final WebviewController controller = WebviewController();
    bool initialized = false;
    final List<StreamSubscription<Object?>> subscriptions =
        <StreamSubscription<Object?>>[];
    final Completer<SitePage> completer = Completer<SitePage>();
    final int effectiveLoadId = loadId ?? DateTime.now().microsecondsSinceEpoch;

    try {
      await controller.initialize();
      initialized = true;
      await controller.setUserAgent(AppConfig.desktopUserAgent);
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      await controller.addScriptToExecuteOnDocumentCreated(_bridgeBootstrap);
      await _primeCookies(controller);

      subscriptions.add(
        controller.webMessage.listen((Object? message) {
          _handleMessage(
            message,
            loadId: effectiveLoadId,
            completer: completer,
          );
        }),
      );
      subscriptions.add(
        controller.onLoadError.listen((WebErrorStatus error) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('页面加载失败：${error.name}'));
          }
        }),
      );
      subscriptions.add(
        controller.loadingState.listen((LoadingState state) {
          if (state != LoadingState.navigationCompleted ||
              completer.isCompleted) {
            return;
          }
          unawaited(
            controller.executeScript(
              buildPageExtractionScript(effectiveLoadId),
            ),
          );
        }),
      );

      await controller.loadUrl(AppConfig.rewriteToCurrentHost(uri).toString());
      return await completer.future.timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('页面解析超时'),
      );
    } finally {
      for (final StreamSubscription<Object?> subscription in subscriptions) {
        await subscription.cancel();
      }
      if (initialized) {
        await controller.dispose();
      }
    }
  }

  /// WebView2 共享 profile 的会话 Cookie 指纹。
  String? _lastPrimedCookieFingerprint;

  void invalidateCookiePriming() {
    _lastPrimedCookieFingerprint = null;
  }

  Future<void> _primeCookies(WebviewController controller) async {
    await SiteSession.instance.ensureInitialized();
    final Map<String, String> cookies = SiteSession.instance.cookies;
    if (cookies.isEmpty) {
      return;
    }
    final String fingerprint = _cookieFingerprint(cookies);
    if (fingerprint == _lastPrimedCookieFingerprint) {
      return;
    }
    try {
      final Future<LoadingState> loaded = controller.loadingState
          .firstWhere(
            (LoadingState state) => state == LoadingState.navigationCompleted,
          )
          .timeout(const Duration(seconds: 8));
      await controller.loadUrl(AppConfig.baseUri.toString());
      await loaded;
      await controller.executeScript(_buildCookieScript(cookies));
      _lastPrimedCookieFingerprint = fingerprint;
    } catch (_) {
      return;
    }
  }

  String _cookieFingerprint(Map<String, String> cookies) {
    final List<String> entries =
        cookies.entries
            .map(
              (MapEntry<String, String> cookie) =>
                  '${cookie.key}=${cookie.value}',
            )
            .toList()
          ..sort();
    return entries.join(';');
  }

  String _buildCookieScript(Map<String, String> cookies) {
    final String statements = cookies.entries
        .where(
          (MapEntry<String, String> cookie) =>
              cookie.key.trim().isNotEmpty && cookie.value.trim().isNotEmpty,
        )
        .map((MapEntry<String, String> cookie) {
          // WebView2 进程重启会丢会话 Cookie。
          final String value =
              '${cookie.key}=${cookie.value}; path=/; max-age=2592000';
          return 'document.cookie = ${jsonEncode(value)};';
        })
        .join('\n');
    return '(() => {$statements})();';
  }

  void _handleMessage(
    Object? message, {
    required int loadId,
    required Completer<SitePage> completer,
  }) {
    if (completer.isCompleted) {
      return;
    }
    try {
      Object? decoded = message;
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final int payloadLoadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (payloadLoadId != loadId) {
        return;
      }
      payload.remove('loadId');
      completer.complete(WebViewPagePayloadDecoder.restore(payload));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}
