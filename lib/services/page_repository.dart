import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/site_page_source.dart';

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
  final SitePage page;
  final CachedPageEnvelope envelope;
  final bool fromMemory;

  CachedPageHit copyWith({
    PageQueryKey? key,
    SitePage? page,
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
    required SitePageSource source,
    this.memoryCapacity = 48,
  }) : _cacheStore = cacheStore ?? PageCacheStore.instance,
       _source = source,
       assert(memoryCapacity >= 0);

  final PageCacheStore _cacheStore;
  final SitePageSource _source;
  final int memoryCapacity;

  final LinkedHashMap<PageQueryKey, CachedPageHit> _memoryCache =
      LinkedHashMap<PageQueryKey, CachedPageHit>();
  final Map<PageQueryKey, Future<SitePage>> _inFlightLoads =
      <PageQueryKey, Future<SitePage>>{};
  final Map<PageQueryKey, Future<void>> _inFlightRevalidations =
      <PageQueryKey, Future<void>>{};
  int _authenticatedGeneration = 0;
  final Map<String, int> _scopeGenerations = <String, int>{};

  static const String _readerCacheFingerprintVersion = 'reader-v2';

  Future<CachedPageHit?> readCached(PageQueryKey key) async {
    final (int, int) generation = _generationFor(key.authScope);
    final CachedPageHit? inMemory = _memoryCache.remove(key);
    if (inMemory != null &&
        _isSupportedCache(inMemory.envelope) &&
        !inMemory.envelope.isHardExpired(DateTime.now())) {
      _memoryCache[key] = inMemory.copyWith(fromMemory: true);
      return _memoryCache[key];
    }

    final CachedPageEnvelope? envelope = await _cacheStore.read(
      key.routeKey,
      authScope: key.authScope,
    );
    if (envelope == null || generation != _generationFor(key.authScope)) {
      return null;
    }
    if (!_isSupportedCache(envelope)) {
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

  Future<SitePage> loadFresh(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final PageQueryKey requestedKey = PageQueryKey.forUri(
      targetUri,
      authScope: authScope,
    );
    final Future<SitePage>? existing = _inFlightLoads[requestedKey];
    if (existing != null) {
      return existing;
    }

    final Future<SitePage> future = _loadFreshInternal(
      targetUri,
      requestedKey: requestedKey,
      generation: _generationFor(authScope),
      requestContext: requestContext,
    );
    _inFlightLoads[requestedKey] = future;

    try {
      return await future;
    } finally {
      _inFlightLoads.removeWhere(
        (key, pending) => key == requestedKey && identical(pending, future),
      );
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
      generation: _generationFor(key.authScope),
      requestContext: requestContext,
    );
    _inFlightRevalidations[key] = future;

    try {
      await future;
    } finally {
      _inFlightRevalidations.removeWhere(
        (pendingKey, pending) =>
            pendingKey == key && identical(pending, future),
      );
    }
  }

  Future<void> removeAuthenticatedEntries() async {
    _authenticatedGeneration += 1;
    _invalidateWhere((PageQueryKey key) => key.authScope != 'guest');
    await _cacheStore.removeAuthenticatedEntries();
  }

  Future<void> removeAuthScope(String authScope) async {
    _scopeGenerations[authScope] = (_scopeGenerations[authScope] ?? 0) + 1;
    _invalidateWhere((PageQueryKey key) => key.authScope == authScope);
    await _cacheStore.removeAuthScope(authScope);
  }

  Future<void> writeCachedPage(
    SitePage page, {
    required String authScope,
  }) async {
    final (int, int) generation = _generationFor(authScope);
    final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
    final PageQueryKey key = PageQueryKey.forUri(pageUri, authScope: authScope);
    final CachedPageEnvelope envelope = PageCacheStore.buildEnvelope(
      routeKey: key.routeKey,
      page: page,
      fingerprint: _fingerprintForPage(page),
      authScope: authScope,
    );
    await _cacheStore.writeEnvelope(envelope);
    if (generation == _generationFor(authScope)) {
      _putMemory(CachedPageHit(key: key, page: page, envelope: envelope));
    }
  }

  void clearMemory() {
    _memoryCache.clear();
  }

  (int, int) _generationFor(String authScope) => (
    authScope == 'guest' ? 0 : _authenticatedGeneration,
    _scopeGenerations[authScope] ?? 0,
  );

  void _invalidateWhere(bool Function(PageQueryKey key) matches) {
    _memoryCache.removeWhere((key, _) => matches(key));
    _inFlightLoads.removeWhere((key, _) => matches(key));
    _inFlightRevalidations.removeWhere((key, _) => matches(key));
  }

  Future<SitePage> _loadFreshInternal(
    Uri uri, {
    required PageQueryKey requestedKey,
    required (int, int) generation,
    NavigationRequestContext? requestContext,
  }) async {
    final SitePage page = await _source.load(
      uri,
      authScope: requestedKey.authScope,
      requestContext: requestContext,
    );
    if (generation != _generationFor(requestedKey.authScope)) {
      return page;
    }

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
    if (generation != _generationFor(requestedKey.authScope)) {
      return page;
    }

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

  Future<void> _revalidateInternal(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope envelope,
    required (int, int) generation,
    NavigationRequestContext? requestContext,
  }) async {
    if (_canSkipNetworkRevalidate(uri, envelope: envelope)) {
      await _cacheStore.refreshValidation(
        key.routeKey,
        authScope: key.authScope,
      );
      if (generation == _generationFor(key.authScope)) {
        _refreshMemoryValidation(key);
      }
      return;
    }

    // Use a single fresh request instead of probe + follow-up fetch.
    final SitePage page = await loadFresh(
      uri,
      authScope: key.authScope,
      requestContext: requestContext,
    );
    if (generation != _generationFor(key.authScope)) {
      return;
    }
    final PageQueryKey finalKey = PageQueryKey.forUri(
      Uri.parse(page.uri),
      authScope: _authScopeForPage(page, key.authScope),
    );
    if (finalKey != key) {
      _memoryCache.remove(key);
    }
  }

  bool _canSkipNetworkRevalidate(
    Uri uri, {
    required CachedPageEnvelope envelope,
  }) {
    // Reader content is effectively immutable after publish; avoid reloading
    // large chapter payloads on soft-expiry and just refresh local validation.
    return envelope.pageType == SitePageType.reader &&
        SitePageRoute.forUri(uri) == SitePageRoute.reader;
  }

  void _refreshMemoryValidation(PageQueryKey key) {
    final CachedPageHit? currentHit = _memoryCache[key];
    if (currentHit == null) {
      return;
    }
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

  void _putMemory(CachedPageHit hit) {
    _memoryCache.remove(hit.key);
    _memoryCache[hit.key] = hit;
    while (_memoryCache.length > memoryCapacity) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  String _authScopeForPage(SitePage page, String requestedAuthScope) {
    if (page is ProfilePageData && !page.isLoggedIn) {
      return 'guest';
    }
    return requestedAuthScope;
  }

  String _fingerprintForPage(SitePage page) {
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
          _readerCacheFingerprintVersion,
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

  bool _isSupportedCache(CachedPageEnvelope envelope) {
    return envelope.pageType != SitePageType.reader ||
        envelope.fingerprint.startsWith('$_readerCacheFingerprintVersion::');
  }
}
