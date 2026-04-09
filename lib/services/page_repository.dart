import 'dart:collection';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/debug_trace.dart';
import 'package:easy_copy/services/network_diagnostics.dart';
import 'package:easy_copy/services/navigation_request_guard.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_probe_service.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:flutter/foundation.dart';

typedef StandardPageFreshLoader =
    Future<EasyCopyPage> Function(
      Uri uri, {
      required String authScope,
      NavigationRequestContext? requestContext,
    });

typedef HtmlPageFreshLoader =
    Future<EasyCopyPage> Function(Uri uri, {required String authScope});

@immutable
class PageQueryKey {
  const PageQueryKey({required this.routeKey, required this.authScope});

  factory PageQueryKey.forUri(Uri uri, {required String authScope}) {
    final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
    return PageQueryKey(
      routeKey: AppConfig.routeKeyForUri(normalizedUri),
      authScope: authScope,
    );
  }

  final String routeKey;
  final String authScope;

  @override
  bool operator ==(Object other) {
    return other is PageQueryKey &&
        other.routeKey == routeKey &&
        other.authScope == authScope;
  }

  @override
  int get hashCode => Object.hash(routeKey, authScope);
}

@immutable
class CachedPageHit {
  const CachedPageHit({
    required this.key,
    required this.page,
    required this.envelope,
    this.fromMemory = false,
  });

  final PageQueryKey key;
  final EasyCopyPage page;
  final CachedPageEnvelope envelope;
  final bool fromMemory;

  CachedPageHit copyWith({
    PageQueryKey? key,
    EasyCopyPage? page,
    CachedPageEnvelope? envelope,
    bool? fromMemory,
  }) {
    return CachedPageHit(
      key: key ?? this.key,
      page: page ?? this.page,
      envelope: envelope ?? this.envelope,
      fromMemory: fromMemory ?? this.fromMemory,
    );
  }
}

class PageRepository {
  PageRepository({
    PageCacheStore? cacheStore,
    PageProbeService? probeService,
    SiteApiClient? apiClient,
    required StandardPageFreshLoader standardPageLoader,
    HtmlPageFreshLoader? htmlPageLoader,
    this.memoryCapacity = 48,
  }) : _cacheStore = cacheStore ?? PageCacheStore.instance,
       _probeService = probeService ?? PageProbeService.instance,
       _apiClient = apiClient ?? SiteApiClient.instance,
       _standardPageLoader = standardPageLoader,
       _htmlPageLoader =
           htmlPageLoader ??
           ((Uri uri, {required String authScope}) {
             return standardPageLoader(uri, authScope: authScope);
           });

  final PageCacheStore _cacheStore;
  final PageProbeService _probeService;
  final SiteApiClient _apiClient;
  final StandardPageFreshLoader _standardPageLoader;
  final HtmlPageFreshLoader _htmlPageLoader;
  final int memoryCapacity;

  final LinkedHashMap<PageQueryKey, CachedPageHit> _memoryCache =
      LinkedHashMap<PageQueryKey, CachedPageHit>();
  final Map<PageQueryKey, Future<EasyCopyPage>> _inFlightLoads =
      <PageQueryKey, Future<EasyCopyPage>>{};
  final Map<PageQueryKey, Future<void>> _inFlightRevalidations =
      <PageQueryKey, Future<void>>{};

  Future<CachedPageHit?> readCached(PageQueryKey key) async {
    final CachedPageHit? inMemory = _memoryCache.remove(key);
    if (inMemory != null) {
      _memoryCache[key] = inMemory.copyWith(fromMemory: true);
      return _memoryCache[key];
    }

    final CachedPageEnvelope? envelope = await _cacheStore.read(
      key.routeKey,
      authScope: key.authScope,
    );
    if (envelope == null) {
      return null;
    }

    final CachedPageHit hit = CachedPageHit(
      key: key,
      page: PageCacheStore.restorePage(envelope),
      envelope: envelope,
    );
    _putMemory(hit);
    return hit;
  }

  Future<EasyCopyPage> loadFresh(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final PageQueryKey requestedKey = PageQueryKey.forUri(
      targetUri,
      authScope: authScope,
    );
    final Future<EasyCopyPage>? existing = _inFlightLoads[requestedKey];
    if (existing != null) {
      return existing;
    }

    final Future<EasyCopyPage> future = _loadFreshInternal(
      targetUri,
      requestedKey: requestedKey,
      requestContext: requestContext,
    );
    _inFlightLoads[requestedKey] = future;

    try {
      return await future;
    } finally {
      _inFlightLoads.remove(requestedKey);
    }
  }

  Future<void> revalidate(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope envelope,
    NavigationRequestContext? requestContext,
  }) async {
    final Future<void>? existing = _inFlightRevalidations[key];
    if (existing != null) {
      return existing;
    }

    final Future<void> future = _revalidateInternal(
      AppConfig.rewriteToCurrentHost(uri),
      key: key,
      envelope: envelope,
      requestContext: requestContext,
    );
    _inFlightRevalidations[key] = future;

    try {
      await future;
    } finally {
      _inFlightRevalidations.remove(key);
    }
  }

  Future<void> removeAuthenticatedEntries() async {
    _memoryCache.removeWhere(
      (PageQueryKey key, CachedPageHit _) => key.authScope != 'guest',
    );
    await _cacheStore.removeAuthenticatedEntries();
  }

  Future<void> removeAuthScope(String authScope) async {
    _memoryCache.removeWhere(
      (PageQueryKey key, CachedPageHit _) => key.authScope == authScope,
    );
    await _cacheStore.removeAuthScope(authScope);
  }

  void clearMemory() {
    _memoryCache.clear();
  }

  Future<EasyCopyPage> _loadFreshInternal(
    Uri uri, {
    required PageQueryKey requestedKey,
    NavigationRequestContext? requestContext,
  }) async {
    final EasyCopyPage page = _isProfileUri(uri)
        ? await _apiClient.loadProfile(uri: uri)
        : _isSearchUri(uri)
        ? await _apiClient.loadSearchResults(
            query: uri.queryParameters['q'] ?? '',
            page: int.tryParse(uri.queryParameters['page'] ?? '') ?? 1,
            qType: uri.queryParameters['q_type'] ?? '',
          )
        : _isReaderChapterUri(uri)
        ? await _loadReaderPageWithFallback(
            uri,
            requestedKey: requestedKey,
            requestContext: requestContext,
          )
        : _isHtmlStandardUri(uri)
        ? await _htmlPageLoader(uri, authScope: requestedKey.authScope)
        : await _standardPageLoader(
            uri,
            authScope: requestedKey.authScope,
            requestContext: requestContext,
          );

    final PageQueryKey finalKey = PageQueryKey.forUri(
      Uri.parse(page.uri),
      authScope: _authScopeForPage(page, requestedKey.authScope),
    );
    final CachedPageEnvelope envelope = PageCacheStore.buildEnvelope(
      routeKey: finalKey.routeKey,
      page: page,
      fingerprint: _fingerprintForPage(page),
      authScope: finalKey.authScope,
    );
    await _cacheStore.writeEnvelope(envelope);

    final CachedPageHit hit = CachedPageHit(
      key: finalKey,
      page: page,
      envelope: envelope,
    );
    _putMemory(hit);
    if (finalKey != requestedKey) {
      _memoryCache.remove(requestedKey);
    }
    return page;
  }

  Future<EasyCopyPage> _loadReaderPageWithFallback(
    Uri uri, {
    required PageQueryKey requestedKey,
    NavigationRequestContext? requestContext,
  }) async {
    try {
      DebugTrace.log('reader.html_loader_start', <String, Object?>{
        'uri': uri.toString(),
      });
      final EasyCopyPage page = await _htmlPageLoader(
        uri,
        authScope: requestedKey.authScope,
      );
      if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
        NetworkDiagnostics.probeImageVariants(
          page.imageUrls.first,
          referer: page.uri,
          label: 'reader.first_image',
        );
      }
      return page;
    } catch (error) {
      DebugTrace.log('reader.html_loader_fallback', <String, Object?>{
        'uri': uri.toString(),
        'error': error.toString(),
      });
      debugPrint(
        'Reader HTML loader failed for ${uri.path}; '
        'falling back to standard loader. $error',
      );
      final EasyCopyPage page = await _standardPageLoader(
        uri,
        authScope: requestedKey.authScope,
        requestContext: requestContext,
      );
      if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
        NetworkDiagnostics.probeImageVariants(
          page.imageUrls.first,
          referer: page.uri,
          label: 'reader.first_image_fallback',
        );
      }
      return page;
    }
  }

  Future<void> _revalidateInternal(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope envelope,
    NavigationRequestContext? requestContext,
  }) async {
    if (_isProfileUri(uri) ||
        _isSearchUri(uri) ||
        _shouldForceFreshRevalidate(uri, key)) {
      final EasyCopyPage page = await loadFresh(
        uri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      final PageQueryKey finalKey = PageQueryKey.forUri(
        Uri.parse(page.uri),
        authScope: _authScopeForPage(page, key.authScope),
      );
      if (finalKey != key) {
        _memoryCache.remove(key);
      }
      return;
    }

    final PageProbeResult probe = await _probeService.probe(uri);
    if (probe.fingerprint == envelope.fingerprint) {
      await _cacheStore.refreshValidation(
        key.routeKey,
        authScope: key.authScope,
      );
      final CachedPageHit? currentHit = _memoryCache[key];
      if (currentHit != null) {
        final DateTime now = DateTime.now();
        _putMemory(
          currentHit.copyWith(
            envelope: currentHit.envelope.copyWith(
              fetchedAt: now,
              validatedAt: now,
              lastAccessedAt: now,
            ),
          ),
        );
      }
      return;
    }

    final EasyCopyPage page = await loadFresh(
      uri,
      authScope: key.authScope,
      requestContext: requestContext,
    );
    final PageQueryKey finalKey = PageQueryKey.forUri(
      Uri.parse(page.uri),
      authScope: _authScopeForPage(page, key.authScope),
    );
    if (finalKey != key) {
      _memoryCache.remove(key);
    }
  }

  void _putMemory(CachedPageHit hit) {
    _memoryCache.remove(hit.key);
    _memoryCache[hit.key] = hit;
    while (_memoryCache.length > memoryCapacity) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  bool _isProfileUri(Uri uri) {
    return uri.path.startsWith(AppConfig.profilePath);
  }

  bool _isSearchUri(Uri uri) {
    return uri.path.startsWith('/search');
  }

  bool _isDetailUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.contains('/chapter/');
  }

  bool _isReaderChapterUri(Uri uri) {
    return uri.path.toLowerCase().contains('/chapter/');
  }

  bool _isHtmlStandardUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path == '/' ||
        path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/topic') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest') ||
        path.startsWith('/rank') ||
        _isDetailUri(uri);
  }

  bool _shouldForceFreshRevalidate(Uri uri, PageQueryKey key) {
    return key.authScope != 'guest' && _isDetailUri(uri);
  }

  String _authScopeForPage(EasyCopyPage page, String requestedAuthScope) {
    if (page is ProfilePageData && !page.isLoggedIn) {
      return 'guest';
    }
    return requestedAuthScope;
  }

  String _fingerprintForPage(EasyCopyPage page) {
    switch (page) {
      case HomePageData homePage:
        final List<ComicCardData> cards = homePage.sections
            .expand((ComicSectionData section) => section.items)
            .toList(growable: false);
        return <String>[
          Uri.parse(homePage.uri).path,
          Uri.parse(homePage.uri).query,
          '',
          cards.isEmpty ? '' : '${cards.first.title}::${cards.first.href}',
          cards.isEmpty ? '' : '${cards.last.title}::${cards.last.href}',
          '${cards.length}',
        ].join('::');
      case DiscoverPageData discoverPage:
        final List<String> activeFilters = discoverPage.filters
            .expand((FilterGroupData group) => group.options)
            .where((LinkAction option) => option.active)
            .map((LinkAction option) => option.label)
            .followedBy(
              discoverPage.pager.currentLabel.isEmpty
                  ? const Iterable<String>.empty()
                  : <String>[discoverPage.pager.currentLabel],
            )
            .toList(growable: false);
        return <String>[
          Uri.parse(discoverPage.uri).path,
          Uri.parse(discoverPage.uri).query,
          activeFilters.join('|'),
          discoverPage.items.isEmpty
              ? ''
              : '${discoverPage.items.first.title}::${discoverPage.items.first.href}',
          discoverPage.items.isEmpty
              ? ''
              : '${discoverPage.items.last.title}::${discoverPage.items.last.href}',
          '${discoverPage.items.length}',
        ].join('::');
      case RankPageData rankPage:
        final List<LinkAction> activeTabs = <LinkAction>[
          ...rankPage.categories.where((LinkAction item) => item.active),
          ...rankPage.periods.where((LinkAction item) => item.active),
        ];
        return <String>[
          Uri.parse(rankPage.uri).path,
          activeTabs.map((LinkAction item) => item.label).join('|'),
          rankPage.items.isEmpty
              ? ''
              : '${rankPage.items.first.title}::${rankPage.items.first.href}',
          rankPage.items.isEmpty
              ? ''
              : '${rankPage.items.last.title}::${rankPage.items.last.href}',
          '${rankPage.items.length}',
        ].join('::');
      case DetailPageData detailPage:
        final List<ChapterData> chapters = detailPage.chapterGroups.isNotEmpty
            ? detailPage.chapterGroups
                  .expand((ChapterGroupData group) => group.chapters)
                  .toList(growable: false)
            : detailPage.chapters;
        return <String>[
          Uri.parse(detailPage.uri).path,
          detailPage.updatedAt,
          detailPage.status,
          '${chapters.length}',
          chapters.isEmpty ? '' : chapters.first.href,
          chapters.isEmpty ? '' : chapters.last.href,
        ].join('::');
      case ReaderPageData readerPage:
        return <String>[
          Uri.parse(readerPage.uri).path,
          readerPage.title,
          readerPage.progressLabel,
          readerPage.contentKey,
        ].join('::');
      case ProfilePageData profilePage:
        return <String>[
          profilePage.user?.userId ?? '',
          '${profilePage.collections.length}',
          '${profilePage.history.length}',
          profilePage.continueReading?.chapterHref ?? '',
        ].join('::');
      case UnknownPageData unknownPage:
        return <String>[unknownPage.uri, unknownPage.message].join('::');
    }
  }
}
