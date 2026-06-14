import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/frame_jank_logger.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/network_client.dart';
import 'package:reader/services/site_html_page_parser.dart';
import 'package:reader/services/site_session.dart';

class SiteHtmlPageLoadException implements Exception {
  SiteHtmlPageLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SiteHtmlPageLoader {
  SiteHtmlPageLoader({
    http.Client? client,
    SiteSession? session,
    HostManager? hostManager,
    SiteHtmlPageParser? parser,
    String? userAgent,
  }) : _client = client ?? http.Client(),
       _session = session ?? SiteSession.instance,
       _hostManager = hostManager ?? HostManager.instance,
       _parser = parser ?? SiteHtmlPageParser.instance,
       _userAgent = userAgent ?? AppConfig.desktopUserAgent;

  static final SiteHtmlPageLoader instance = SiteHtmlPageLoader();

  static const int _maxRedirects = 6;
  static const Duration _requestTimeout = Duration(seconds: 12);

  final http.Client _client;
  final SiteSession _session;
  final HostManager _hostManager;
  final SiteHtmlPageParser _parser;
  final String _userAgent;

  Future<SitePage> loadPage(Uri uri, {required String authScope}) async {
    await _hostManager.ensureInitialized();
    await _session.ensureInitialized();

    final _LoadedTextResponse response = await _getTextResponse(
      AppConfig.rewriteToCurrentHost(uri),
      headers: _defaultHeaders(
        accept:
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      ),
    );
    if (_isDetailPageUri(response.uri)) {
      return _parser.parsePage(
        response.uri,
        response.body,
        loadDetailChapterResults: _loadDetailChapterResults,
      );
    }
    // 详情页外的 HTML 解析移到后台 isolate。
    final Uri responseUri = response.uri;
    final String responseBody = response.body;
    final Stopwatch parseStopwatch = Stopwatch()..start();
    final SitePage page = await Isolate.run(() {
      return const SiteHtmlPageParser().parsePage(responseUri, responseBody);
    });
    perfLog(
      '[parse] off-main ${parseStopwatch.elapsedMilliseconds}ms '
      'type=${page.type.name} path=${responseUri.path}',
    );
    return page;
  }

  bool _isDetailPageUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.contains('/chapter/');
  }

  Future<String> _loadDetailChapterResults(DetailChapterRequest request) async {
    final _LoadedTextResponse response = await _getTextResponse(
      AppConfig.resolvePath('/comicdetail/${request.slug}/chapters'),
      headers: _defaultHeaders(
        accept: 'application/json, text/plain, */*',
        extra: <String, String>{
          'Referer': request.pageUri.toString(),
          'dnts': request.dnt,
        },
      ),
    );
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw SiteHtmlPageLoadException('详情页章节接口返回格式异常：${request.pageUri.path}');
    }

    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final int code = (payload['code'] as num?)?.toInt() ?? 0;
    final String results = (payload['results'] as String?)?.trim() ?? '';
    if (code != 200 || results.isEmpty) {
      throw SiteHtmlPageLoadException(
        (payload['message'] as String?) ?? '详情页章节接口请求失败：$code',
      );
    }
    return results;
  }

  Future<_LoadedTextResponse> _getTextResponse(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    Uri currentUri = AppConfig.rewriteToCurrentHost(uri);
    for (
      int redirectCount = 0;
      redirectCount <= _maxRedirects;
      redirectCount += 1
    ) {
      final Stopwatch stopwatch = Stopwatch()..start();
      final NetworkResponseBytes response = await NetworkClient.sendForBytes(
        _client,
        () => http.Request('GET', currentUri)
          ..followRedirects = false
          ..maxRedirects = 1
          ..headers.addAll(headers),
        uri: currentUri,
        timeout: _requestTimeout,
        maxRetries: 1,
        label: 'html.get',
      );
      if (currentUri.path.toLowerCase().contains('/chapter/')) {
        DebugTrace.log('reader.html_request_complete', <String, Object?>{
          'uri': currentUri.toString(),
          'statusCode': response.statusCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'byteCount': response.bytes.length,
        });
      }

      if (_isRedirectStatus(response.statusCode)) {
        final String location = (response.headers['location'] ?? '').trim();
        if (location.isEmpty) {
          throw SiteHtmlPageLoadException('页面重定向缺少跳转地址：${currentUri.path}');
        }
        currentUri = AppConfig.rewriteToCurrentHost(
          currentUri.resolve(location),
        );
        continue;
      }

      if (response.statusCode >= 400) {
        throw SiteHtmlPageLoadException(
          '页面请求失败：${response.statusCode} ${currentUri.path}',
        );
      }

      return _LoadedTextResponse(
        uri: currentUri,
        body: utf8.decode(response.bytes, allowMalformed: true),
      );
    }

    throw SiteHtmlPageLoadException('页面重定向次数过多：${uri.path}');
  }

  Map<String, String> _defaultHeaders({
    required String accept,
    Map<String, String> extra = const <String, String>{},
  }) {
    return <String, String>{
      'User-Agent': _userAgent,
      'Accept': accept,
      if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
      ...extra,
    };
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }
}

class _LoadedTextResponse {
  const _LoadedTextResponse({required this.uri, required this.body});

  final Uri uri;
  final String body;
}
