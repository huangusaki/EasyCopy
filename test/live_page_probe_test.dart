import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/key_value_store.dart';
import 'package:easy_copy/services/navigation_request_guard.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_html_page_loader.dart';
import 'package:easy_copy/services/site_html_page_parser.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const bool _runLiveTests = bool.fromEnvironment('EASY_COPY_RUN_LIVE_TESTS');
const String _probeHost = 'www.2026copy.com';

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpOverrides? previous = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      return HttpClient(context: context);
    } finally {
      HttpOverrides.global = previous;
    }
  }
}

class _ProbeSnapshot {
  const _ProbeSnapshot({
    required this.uri,
    required this.page,
    required this.rawHtmlBytes,
    required this.pageJsonBytes,
    required this.cachePayloadBytes,
    required this.cacheEnvelopeBytes,
    required this.parseMs,
    this.detailApiBytes = 0,
  });

  final Uri uri;
  final EasyCopyPage page;
  final int rawHtmlBytes;
  final int pageJsonBytes;
  final int cachePayloadBytes;
  final int cacheEnvelopeBytes;
  final int parseMs;
  final int detailApiBytes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': uri.path,
      'type': page.type.name,
      'rawHtmlBytes': rawHtmlBytes,
      'pageJsonBytes': pageJsonBytes,
      'cachePayloadBytes': cachePayloadBytes,
      'cacheEnvelopeBytes': cacheEnvelopeBytes,
      'detailApiBytes': detailApiBytes,
      'parseMs': parseMs,
      'summary': _pageSummary(page),
    };
  }
}

class _LoadedTextResponse {
  const _LoadedTextResponse({required this.uri, required this.body});

  final Uri uri;
  final String body;
}

void main() {
  test(
    'live HTML loader gets compact page payloads without hitting standard loader',
    () async {
      final HttpOverrides? previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
      try {
        final Uri baseUri = Uri.parse('https://$_probeHost/');
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'copyfullter_live_probe_',
        );
        final http.Client client = http.Client();
        try {
          final SiteSession session = SiteSession(store: _MemoryKeyValueStore());
          final SiteHtmlPageLoader loader = SiteHtmlPageLoader(
            client: client,
            session: session,
            hostManager: HostManager(
              client: client,
              candidateHosts: <String>[_probeHost],
              directoryProvider: () async => tempDir,
            ),
          );
          final SiteHtmlPageParser parser = SiteHtmlPageParser.instance;
          final PageCacheStore cacheStore = PageCacheStore(
            directoryProvider: () async => tempDir,
          );
          final SiteApiClient apiClient = SiteApiClient(
            client: client,
            session: session,
          );

          int standardLoaderCalls = 0;
          final PageRepository repository = PageRepository(
            cacheStore: cacheStore,
            apiClient: apiClient,
            standardPageLoader:
                (
                  Uri uri, {
                  required String authScope,
                  NavigationRequestContext? requestContext,
                }) async {
                  standardLoaderCalls += 1;
                  throw StateError('standard loader should not be used: $uri');
                },
            htmlPageLoader: (Uri uri, {required String authScope}) {
              return loader.loadPage(uri, authScope: authScope);
            },
          );

          final HomePageData homePage =
              await repository.loadFresh(baseUri, authScope: 'guest')
                  as HomePageData;
          final DiscoverPageData discoverPage =
              await repository.loadFresh(
                    baseUri.resolve('/comics'),
                    authScope: 'guest',
                  )
                  as DiscoverPageData;
          final RankPageData rankPage =
              await repository.loadFresh(
                    baseUri.resolve('/rank'),
                    authScope: 'guest',
                  )
                  as RankPageData;

          final Uri detailUri = _firstDetailUri(homePage, discoverPage);
          final DetailPageData detailPage =
              await repository.loadFresh(detailUri, authScope: 'guest')
                  as DetailPageData;

          final Uri readerUri = Uri.parse(
            detailPage.startReadingHref.isNotEmpty
                ? detailPage.startReadingHref
                : detailPage.chapters.first.href,
          );
          final ReaderPageData readerPage =
              await repository.loadFresh(readerUri, authScope: 'guest')
                  as ReaderPageData;

          expect(standardLoaderCalls, 0);
          expect(homePage.sections, isNotEmpty);
          expect(discoverPage.items, isNotEmpty);
          expect(rankPage.items, isNotEmpty);
          expect(detailPage.chapterGroups, isNotEmpty);
          expect(readerPage.imageUrls, isNotEmpty);
          expect(readerPage.contentKey, isNotEmpty);

          final List<_ProbeSnapshot> probes = <_ProbeSnapshot>[
            await _probePage(client, parser, baseUri),
            await _probePage(client, parser, baseUri.resolve('/comics')),
            await _probePage(client, parser, baseUri.resolve('/rank')),
            await _probePage(client, parser, detailUri),
            await _probePage(client, parser, readerUri),
          ];

          for (final _ProbeSnapshot probe in probes) {
            expect(
              probe.cachePayloadBytes,
              lessThan(probe.rawHtmlBytes),
              reason:
                  'cache payload should be smaller than raw HTML: ${probe.uri}',
            );
          }

          final _ProbeSnapshot detailProbe = probes.firstWhere(
            (_ProbeSnapshot probe) => probe.page is DetailPageData,
          );
          final _ProbeSnapshot readerProbe = probes.firstWhere(
            (_ProbeSnapshot probe) => probe.page is ReaderPageData,
          );

          expect(detailProbe.detailApiBytes, greaterThan(0));
          expect(
            detailProbe.cachePayloadBytes,
            lessThan(detailProbe.pageJsonBytes),
          );
          expect(
            readerProbe.cachePayloadBytes,
            lessThan(readerProbe.rawHtmlBytes),
          );

          for (final _ProbeSnapshot probe in probes) {
            stdout.writeln('LIVE_PROBE ${jsonEncode(probe.toJson())}');
          }
        } finally {
          client.close();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      } finally {
        HttpOverrides.global = previousOverrides;
      }
    },
    skip: !_runLiveTests,
  );
}

Uri _firstDetailUri(HomePageData homePage, DiscoverPageData discoverPage) {
  for (final ComicSectionData section in homePage.sections) {
    for (final ComicCardData card in section.items) {
      if (card.href.isNotEmpty) {
        return Uri.parse(card.href);
      }
    }
  }
  for (final ComicCardData card in discoverPage.items) {
    if (card.href.isNotEmpty) {
      return Uri.parse(card.href);
    }
  }
  throw StateError('no detail URI found');
}

Future<_ProbeSnapshot> _probePage(
  http.Client client,
  SiteHtmlPageParser parser,
  Uri uri,
) async {
  final _LoadedTextResponse response = await _getTextResponse(
    client,
    uri,
    headers: <String, String>{
      'User-Agent': AppConfig.desktopUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  );

  int detailApiBytes = 0;
  final Stopwatch stopwatch = Stopwatch()..start();
  final EasyCopyPage page = await parser.parsePage(
    response.uri,
    response.body,
    loadDetailChapterResults: (DetailChapterRequest request) async {
      final _LoadedTextResponse apiResponse = await _getTextResponse(
        client,
        response.uri.resolve('/comicdetail/${request.slug}/chapters'),
        headers: <String, String>{
          'User-Agent': AppConfig.desktopUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Referer': request.pageUri.toString(),
          'dnts': request.dnt,
        },
      );
      detailApiBytes = utf8.encode(apiResponse.body).length;
      final Object? decoded = jsonDecode(apiResponse.body);
      if (decoded is! Map) {
        throw StateError('detail chapter response is not a map');
      }
      return (decoded['results'] as String?)?.trim() ?? '';
    },
  );
  stopwatch.stop();

  final CachedPageEnvelope envelope = PageCacheStore.buildEnvelope(
    routeKey: AppConfig.routeKeyForUri(Uri.parse(page.uri)),
    page: page,
    fingerprint: 'live-probe',
    authScope: 'guest',
  );
  return _ProbeSnapshot(
    uri: response.uri,
    page: page,
    rawHtmlBytes: utf8.encode(response.body).length,
    pageJsonBytes: utf8.encode(jsonEncode(page.toJson())).length,
    cachePayloadBytes: utf8.encode(jsonEncode(envelope.payload)).length,
    cacheEnvelopeBytes: utf8.encode(jsonEncode(envelope.toJson())).length,
    detailApiBytes: detailApiBytes,
    parseMs: stopwatch.elapsedMilliseconds,
  );
}

Future<_LoadedTextResponse> _getTextResponse(
  http.Client client,
  Uri uri, {
  required Map<String, String> headers,
}) async {
  Uri currentUri = uri;
  for (int redirectCount = 0; redirectCount <= 6; redirectCount += 1) {
    final http.Request request = http.Request('GET', currentUri)
      ..followRedirects = false
      ..maxRedirects = 1
      ..headers.addAll(headers);
    final http.StreamedResponse response = await client.send(request).timeout(
      const Duration(seconds: 12),
    );
    final List<int> bytes = await response.stream.toBytes().timeout(
      const Duration(seconds: 12),
    );

    if (response.statusCode == 301 ||
        response.statusCode == 302 ||
        response.statusCode == 303 ||
        response.statusCode == 307 ||
        response.statusCode == 308) {
      final String location = (response.headers['location'] ?? '').trim();
      if (location.isEmpty) {
        throw StateError('redirect without location: $currentUri');
      }
      currentUri = currentUri.resolve(location);
      continue;
    }

    if (response.statusCode >= 400) {
      throw StateError('request failed: ${response.statusCode} $currentUri');
    }

    return _LoadedTextResponse(
      uri: currentUri,
      body: utf8.decode(bytes, allowMalformed: true),
    );
  }

  throw StateError('too many redirects: $uri');
}

Map<String, Object?> _pageSummary(EasyCopyPage page) {
  switch (page) {
    case HomePageData home:
      return <String, Object?>{
        'heroCount': home.heroBanners.length,
        'sectionCount': home.sections.length,
        'cardCount': home.sections.fold<int>(
          0,
          (int sum, ComicSectionData section) => sum + section.items.length,
        ),
      };
    case DiscoverPageData discover:
      return <String, Object?>{
        'filterGroupCount': discover.filters.length,
        'itemCount': discover.items.length,
        'spotlightCount': discover.spotlight.length,
      };
    case RankPageData rank:
      return <String, Object?>{
        'categoryCount': rank.categories.length,
        'periodCount': rank.periods.length,
        'itemCount': rank.items.length,
      };
    case DetailPageData detail:
      return <String, Object?>{
        'groupCount': detail.chapterGroups.length,
        'chapterCount': detail.chapters.length,
        'tagCount': detail.tags.length,
      };
    case ReaderPageData reader:
      return <String, Object?>{
        'imageCount': reader.imageUrls.length,
        'hasContentKey': reader.contentKey.isNotEmpty,
      };
    case ProfilePageData profile:
      return <String, Object?>{
        'isLoggedIn': profile.isLoggedIn,
        'collectionCount': profile.collections.length,
        'historyCount': profile.history.length,
      };
    case UnknownPageData unknown:
      return <String, Object?>{'message': unknown.message};
  }
}
