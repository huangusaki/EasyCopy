import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:reader/config/app_config.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/desktop_webview_environment.dart';
import 'package:reader/services/site_session.dart';
import 'package:webview_windows/webview_windows.dart';

typedef DesktopSearchResponse = ({String body, int statusCode});

typedef SearchResponseLoader =
    Future<DesktopSearchResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
    });

class DesktopSearchApiBridge {
  DesktopSearchApiBridge._();

  static final DesktopSearchApiBridge instance = DesktopSearchApiBridge._();

  static const Duration _timeout = Duration(seconds: 30);
  static const String _messageKind = 'easy-copy-search-response';

  Future<T> withOrigin<T>(
    Uri origin,
    Future<T> Function(SearchResponseLoader) search,
  ) async {
    await AppConfig.hostManager.ensureInitialized();
    if (origin.scheme != 'https' ||
        origin.port != 443 ||
        !AppConfig.hostManager.allowedHosts.contains(
          origin.host.toLowerCase(),
        )) {
      throw ArgumentError.value(origin, 'origin', '搜索接口域名不在允许列表中');
    }
    await DesktopWebViewEnvironment.instance.ensureReady();
    final controller = WebviewController();
    await controller.initialize();
    final subscriptions = <StreamSubscription<Object?>>[];
    try {
      await controller.setUserAgent(AppConfig.desktopUserAgent);
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      final ready = Completer<void>();
      Completer<DesktopSearchResponse>? pending;
      int sequence = 0;
      subscriptions.add(
        controller.loadingState.listen((state) {
          if (state == LoadingState.navigationCompleted && !ready.isCompleted) {
            ready.complete();
          }
        }),
      );
      subscriptions.add(
        controller.onLoadError.listen((error) {
          final failure = StateError('搜索页面加载失败：${error.name}');
          if (!ready.isCompleted) {
            ready.completeError(failure);
          } else if (pending != null && !pending!.isCompleted) {
            pending!.completeError(failure);
          }
        }),
      );
      subscriptions.add(
        controller.webMessage.listen((message) {
          final result = pending;
          if (result != null) {
            _handleMessage(message, requestId: '$sequence', completer: result);
          }
        }),
      );
      await Future.wait<void>([
        controller.loadUrl(origin.resolve('/').toString()),
        ready.future,
      ], eagerError: true).timeout(_timeout);
      return await search((uri, {required headers}) async {
        if (uri.origin != origin.origin) throw StateError('搜索接口域名已变化');
        sequence++;
        final result = pending = Completer<DesktopSearchResponse>();
        final reply = result.future;
        final script = _buildFetchScript(
          uri,
          headers: headers,
          requestId: '$sequence',
        );
        final values = await Future.wait<Object?>([
          controller.executeScript(script),
          reply,
        ], eagerError: true).timeout(_timeout);
        return values.last! as DesktopSearchResponse;
      });
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await controller.dispose();
    }
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
  if (location.origin !== new URL(requestUrl).origin) {
    chrome.webview.postMessage({kind: ${jsonEncode(_messageKind)}, requestId, error: '搜索来源域名发生变化'});
    return;
  }
  ${SiteSession.cookieScript(SiteSession.parseCookieHeader(headers['Cookie'] ?? ''))}
  fetch(requestUrl, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store',
    headers: ${jsonEncode(browserHeaders)},
  })
    .then(async (response) => {
      chrome.webview.postMessage({
        kind: ${jsonEncode(_messageKind)},
        requestId,
        statusCode: response.status,
        body: await response.text(),
        ${kDebugMode ? "protocol: performance.getEntriesByName(requestUrl).slice(-1)[0]?.nextHopProtocol || ''," : ''}
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
