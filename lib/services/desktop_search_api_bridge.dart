import 'dart:async';
import 'dart:convert';

import 'package:reader/config/app_config.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/desktop_webview_environment.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:webview_windows/webview_windows.dart';

typedef DesktopSearchResponse = ({String body, int statusCode});

class DesktopSearchApiBridge {
  DesktopSearchApiBridge._();

  static final DesktopSearchApiBridge instance = DesktopSearchApiBridge._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String _messageKind = 'easy-copy-search-response';

  Future<DesktopSearchResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (!PlatformCapabilities.supportsDesktopWebView) {
      throw UnsupportedError('当前平台不支持 WebView2 搜索请求');
    }
    if (uri.scheme != 'https' || uri.port != 443) {
      throw ArgumentError.value(uri, 'uri', '搜索接口仅允许 HTTPS 443');
    }

    await AppConfig.hostManager.ensureInitialized();
    if (!AppConfig.hostManager.allowedHosts.contains(uri.host.toLowerCase())) {
      throw ArgumentError.value(uri, 'uri', '搜索接口域名不在允许列表中');
    }
    await DesktopWebViewEnvironment.instance.ensureReady();

    final WebviewController controller = WebviewController();
    final Completer<DesktopSearchResponse> completer =
        Completer<DesktopSearchResponse>();
    final List<StreamSubscription<Object?>> subscriptions =
        <StreamSubscription<Object?>>[];
    final String requestId = DateTime.now().microsecondsSinceEpoch.toString();
    bool initialized = false;
    bool requestStarted = false;

    try {
      await controller.initialize();
      initialized = true;
      await controller.setUserAgent(AppConfig.desktopUserAgent);
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );

      subscriptions.add(
        controller.webMessage.listen(
          (Object? message) {
            _handleMessage(message, requestId: requestId, completer: completer);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        ),
      );
      subscriptions.add(
        controller.onLoadError.listen((WebErrorStatus error) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('搜索页面加载失败：${error.name}'));
          }
        }),
      );
      subscriptions.add(
        controller.loadingState.listen((LoadingState state) {
          if (state != LoadingState.navigationCompleted ||
              requestStarted ||
              completer.isCompleted) {
            return;
          }
          requestStarted = true;
          unawaited(
            _executeRequest(
              controller,
              uri: uri,
              headers: headers,
              requestId: requestId,
              completer: completer,
            ),
          );
        }),
      );

      final Uri originUri = uri.replace(path: '/', query: null, fragment: null);
      await controller.loadUrl(originUri.toString());
      return await completer.future.timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('搜索请求超时'),
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

  Future<void> _executeRequest(
    WebviewController controller, {
    required Uri uri,
    required Map<String, String> headers,
    required String requestId,
    required Completer<DesktopSearchResponse> completer,
  }) async {
    try {
      final String cookieScript = _buildCookieScript(
        SiteSession.parseCookieHeader(headers['Cookie'] ?? ''),
      );
      if (cookieScript.isNotEmpty) {
        await controller.executeScript(cookieScript);
      }
      await controller.executeScript(
        _buildFetchScript(uri, headers: headers, requestId: requestId),
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  String _buildCookieScript(Map<String, String> cookies) {
    final String statements = cookies.entries
        .where(
          (MapEntry<String, String> cookie) =>
              cookie.key.trim().isNotEmpty && cookie.value.trim().isNotEmpty,
        )
        .map((MapEntry<String, String> cookie) {
          final String value =
              '${cookie.key}=${cookie.value}; path=/; max-age=2592000';
          return 'document.cookie = ${jsonEncode(value)};';
        })
        .join('\n');
    if (statements.isEmpty) {
      return '';
    }
    return '(() => {$statements})();';
  }

  String _buildFetchScript(
    Uri uri, {
    required Map<String, String> headers,
    required String requestId,
  }) {
    final Map<String, String> browserHeaders = <String, String>{
      for (final MapEntry<String, String> header in headers.entries)
        if (!_isForbiddenBrowserHeader(header.key)) header.key: header.value,
    };
    return '''
(() => {
  const requestId = ${jsonEncode(requestId)};
  const requestUrl = ${jsonEncode(uri.toString())};
  fetch(requestUrl, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store',
    headers: ${jsonEncode(browserHeaders)},
  })
    .then(async (response) => {
      const entries = performance.getEntriesByName(requestUrl);
      const protocol = entries.length === 0
        ? ''
        : String(entries[entries.length - 1].nextHopProtocol || '');
      chrome.webview.postMessage({
        kind: ${jsonEncode(_messageKind)},
        requestId,
        statusCode: response.status,
        body: await response.text(),
        protocol,
      });
    })
    .catch((error) => {
      chrome.webview.postMessage({
        kind: ${jsonEncode(_messageKind)},
        requestId,
        statusCode: 0,
        body: '',
        error: String(error?.message || error || 'unknown error'),
      });
    });
})();
''';
  }

  bool _isForbiddenBrowserHeader(String name) {
    return switch (name.trim().toLowerCase()) {
      'cookie' || 'host' || 'user-agent' => true,
      _ => false,
    };
  }

  void _handleMessage(
    Object? message, {
    required String requestId,
    required Completer<DesktopSearchResponse> completer,
  }) {
    if (completer.isCompleted || message is! Map) {
      return;
    }
    final Map<String, Object?> payload = message.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    if (payload['kind'] != _messageKind || payload['requestId'] != requestId) {
      return;
    }
    final String error = (payload['error'] as String? ?? '').trim();
    if (error.isNotEmpty) {
      completer.completeError(StateError('搜索请求失败：$error'));
      return;
    }
    final String protocol = (payload['protocol'] as String? ?? '').trim();
    DebugTrace.log('net.webview_search_response', <String, Object?>{
      'protocol': protocol,
      'statusCode': (payload['statusCode'] as num?)?.toInt() ?? 0,
    });
    completer.complete((
      body: payload['body'] as String? ?? '',
      statusCode: (payload['statusCode'] as num?)?.toInt() ?? 0,
    ));
  }
}
