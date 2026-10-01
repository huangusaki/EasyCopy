import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/blocked_content_filter.dart';
import 'package:reader/services/blocked_content_store.dart';
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
    BlockedContentStore? blockedContentStore,
    this.memoryCapacity = 48,
  }) : _cacheStore = cacheStore ?? PageCacheStore.instance,
       _source = source,
       _blockedFilter = BlockedContentFilter(
         blockedContentStore ?? BlockedContentStore.instance,
       ),
       assert(memoryCapacity >= 0);

  final PageCacheStore _cacheStore;
  final SitePageSource _source;
  final BlockedContentFilter _blockedFilter;
  final int memoryCapacity;

  final LinkedHashMap<PageQueryKey, CachedPageHit> _memoryCache =
      LinkedHashMap<PageQueryKey, CachedPageHit>();
  final Map<PageQueryKey, Future<SitePage>> _inFlightLoads =
      <PageQueryKey, Future<SitePage>>{};
  final Map<PageQueryKey, Future<void>> _inFlightRevalidations =
      <PageQueryKey, Future<void>>{};
  int _authenticatedGeneration = 0;

  Future<CachedPageHit?> readCached(PageQueryKey key) async {
    await _blockedFilter.store.ensureInitialized();
    final int generation = _generationFor(key.authScope);
    final CachedPageHit? inMemory = _memoryCache.remove(key);
    if (inMemory != null &&
        _isSupportedCache(inMemory.envelope) &&
        !inMemory.envelope.isHardExpired(DateTime.now())) {
      _memoryCache[key] = inMemory.copyWith(fromMemory: true);
      return _filteredHit(_memoryCache[key]!);
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
    return _filteredHit(hit);
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

  Future<void> writeCachedPage(
    SitePage page, {
    required String authScope,
  }) async {
    final int generation = _generationFor(authScope);
    final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
    final PageQueryKey key = PageQueryKey.forUri(pageUri, authScope: authScope);
    final CachedPageEnvelope envelope = PageCacheStore.buildEnvelope(
      routeKey: key.routeKey,
      page: page,
      authScope: authScope,
    );
    await _cacheStore.writeEnvelope(envelope);
    if (generation == _generationFor(authScope)) {
      _putMemory(CachedPageHit(key: key, page: page, envelope: envelope));
    }
  }

  int _generationFor(String authScope) =>
      authScope == 'guest' ? 0 : _authenticatedGeneration;

  void _invalidateWhere(bool Function(PageQueryKey key) matches) {
    _memoryCache.removeWhere((key, _) => matches(key));
    _inFlightLoads.removeWhere((key, _) => matches(key));
    _inFlightRevalidations.removeWhere((key, _) => matches(key));
  }

  Future<SitePage> _loadFreshInternal(
    Uri uri, {
    required PageQueryKey requestedKey,
    required int generation,
    NavigationRequestContext? requestContext,
  }) async {
    await _blockedFilter.store.ensureInitialized();
    final SitePage page = await _source.load(
      uri,
      authScope: requestedKey.authScope,
      requestContext: requestContext,
    );
    if (generation != _generationFor(requestedKey.authScope)) {
      return _blockedFilter.apply(page);
    }

    final PageQueryKey finalKey = PageQueryKey.forUri(
      Uri.parse(page.uri),
      authScope: _authScopeForPage(page, requestedKey.authScope),
    );
    final CachedPageEnvelope envelope = PageCacheStore.buildEnvelope(
      routeKey: finalKey.routeKey,
      page: page,
      authScope: finalKey.authScope,
    );
    await _cacheStore.writeEnvelope(envelope);
    if (generation != _generationFor(requestedKey.authScope)) {
      return _blockedFilter.apply(page);
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
    return _blockedFilter.apply(page);
  }

  CachedPageHit _filteredHit(CachedPageHit hit) {
    return hit.copyWith(page: _blockedFilter.apply(hit.page));
  }

  Future<void> _revalidateInternal(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope envelope,
    required int generation,
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

  bool _isSupportedCache(CachedPageEnvelope envelope) {
    return envelope.pageType != SitePageType.reader ||
        envelope.readerCacheVersion == PageCacheStore.readerCacheVersion;
  }
}
