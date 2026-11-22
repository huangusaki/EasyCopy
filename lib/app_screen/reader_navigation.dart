part of '../app_screen.dart';

extension _AppScreenReaderNavigation on _AppScreenState {
  void _handleReaderChaptersChanged() {
    if (_page is DetailPageData) _setStateIfMounted();
  }

  bool _shouldBypassUnknownCache(Uri uri, SitePage page) {
    if (page is! UnknownPageData) {
      return false;
    }
    return SitePageRoute.forUri(uri) != SitePageRoute.standard ||
        uri.path.startsWith('/person') ||
        isLoginUri(uri);
  }

  CachedChapterNavigationContext _resolvedCachedChapterContext(
    Uri targetUri, {
    required CachedChapterNavigationContext context,
  }) {
    final SitePage? currentPage = _page;
    CachedChapterNavigationContext resolvedContext = context;
    if (currentPage is ReaderPageData && !context.hasAnyValue) {
      final String targetKey = _chapterKeys.pathKey(targetUri.toString());
      final String currentKey = _chapterKeys.pathKey(currentPage.uri);
      final String prevKey = _chapterKeys.pathKey(currentPage.prevHref);
      final String nextKey = _chapterKeys.pathKey(currentPage.nextHref);

      if (targetKey == currentKey) {
        resolvedContext = CachedChapterNavigationContext(
          prevHref: currentPage.prevHref,
          nextHref: currentPage.nextHref,
          catalogHref: currentPage.catalogHref,
        );
      } else if (targetKey == prevKey) {
        resolvedContext = CachedChapterNavigationContext(
          nextHref: currentPage.uri,
          catalogHref: currentPage.catalogHref,
        );
      } else if (targetKey == nextKey) {
        resolvedContext = CachedChapterNavigationContext(
          prevHref: currentPage.uri,
          catalogHref: currentPage.catalogHref,
        );
      } else {
        resolvedContext = CachedChapterNavigationContext(
          catalogHref: currentPage.catalogHref,
        );
      }
    }

    final CachedChapterNavigationContext detailContext = _cachedChapterContext(
      targetUri,
      preferredCatalogHref: resolvedContext.catalogHref,
    );
    return resolvedContext.mergeMissing(detailContext);
  }

  CachedChapterNavigationContext _cachedChapterContext(
    Uri targetUri, {
    String preferredCatalogHref = '',
  }) {
    if (targetUri.path.isEmpty) {
      return const CachedChapterNavigationContext();
    }
    final preferredRoute = preferredCatalogHref.trim().isEmpty
        ? ''
        : AppConfig.routeKeyForUri(Uri.parse(preferredCatalogHref));
    CachedChapterNavigationContext? fallback;
    for (final entry
        in _tabSessionStore.stackForTab(_nav.selectedIndex).reversed) {
      final page = entry.page;
      if (page is! DetailPageData) continue;
      final preferred =
          preferredRoute.isEmpty || entry.routeKey == preferredRoute;
      if (fallback != null && !preferred) continue;
      final links = page.adjacentTo(targetUri.toString());
      if (links == null) continue;
      final context = CachedChapterNavigationContext(
        prevHref: links.prevHref,
        nextHref: links.nextHref,
        catalogHref: page.uri,
      );
      if (preferred) return context;
      fallback = context;
    }
    return fallback ?? const CachedChapterNavigationContext();
  }

  ReaderPageData _mergeReaderPageNavigation(
    ReaderPageData page,
    CachedChapterNavigationContext context,
  ) {
    return page.mergeMissingNavigation(
      prevHref: context.prevHref,
      nextHref: context.nextHref,
      catalogHref: context.catalogHref,
    );
  }

  bool _didReaderNavigationChange(ReaderPageData before, ReaderPageData after) {
    return before.prevHref != after.prevHref ||
        before.nextHref != after.nextHref ||
        before.catalogHref != after.catalogHref;
  }

  Future<void> _persistReaderPageCache(ReaderPageData page) async {
    try {
      final String authScope = _pageQueryKeyForUri(
        Uri.parse(page.uri),
      ).authScope;
      await _pageRepository.writeCachedPage(page, authScope: authScope);
    } catch (_) {
      // 缓存修复失败不影响当前页面。
    }
  }

  Future<ReaderPageData?> _loadRepairReaderPage(
    Uri uri, {
    required String authScope,
  }) async {
    final SitePage page = await _pageRepository.loadFresh(
      uri,
      authScope: authScope,
    );
    if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
      return page;
    }
    return null;
  }

  Future<RepairCatalog?> _loadRepairDetailPage(
    Uri uri, {
    required String authScope,
    required String chapterHref,
  }) async {
    final CachedPageHit? cached = await _pageRepository.readCached(
      PageQueryKey.forUri(uri, authScope: authScope),
    );
    final SitePage? cachedPage = cached?.page;
    if (cachedPage is DetailPageData &&
        !cached!.envelope.isSoftExpired(DateTime.now()) &&
        cachedPage.adjacentTo(chapterHref) != null) {
      return (page: cachedPage, validatedAt: cached.envelope.validatedAt);
    }
    final SitePage page = await _pageRepository.loadFresh(
      uri,
      authScope: authScope,
    );
    return page is DetailPageData
        ? (page: page, validatedAt: DateTime.now())
        : null;
  }

  Future<void> _repairCachedReaderNavigation(
    ReaderPageData page, {
    required Uri targetUri,
    required CachedChapterNavigationContext context,
    required NavigationRequestContext requestContext,
    required bool persistToPageCache,
  }) async {
    if (!page.hasMissingChapterNavigation) {
      return;
    }
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (_navigationRepairer.hasConfirmedNavigation(page, key.authScope) ||
        !_nav.repairRouteKeys.add(key.routeKey)) {
      return;
    }
    final sessionGeneration = _sessionController.generation;
    try {
      DebugTrace.log('reader.navigation_repair_start', <String, Object?>{
        'bootId': _shell.bootId,
        'uri': targetUri.toString(),
        'persistToPageCache': persistToPageCache,
      });
      final ReaderPageData repairedPage = await _navigationRepairer.repair(
        page,
        authScope: key.authScope,
        preferredCatalogHref: context.catalogHref,
        loadReaderPage: _loadRepairReaderPage,
        loadDetailPage: (uri, {required authScope}) => _loadRepairDetailPage(
          uri,
          authScope: authScope,
          chapterHref: page.uri,
        ),
      );
      if (!_sessionController.accepts(sessionGeneration)) return;
      if (!_didReaderNavigationChange(page, repairedPage)) {
        DebugTrace.log('reader.navigation_repair_noop', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': targetUri.toString(),
        });
        return;
      }
      if (persistToPageCache) {
        await _persistReaderPageCache(repairedPage);
      }
      DebugTrace.log('reader.navigation_repair_complete', <String, Object?>{
        'bootId': _shell.bootId,
        'uri': targetUri.toString(),
        'prevHref': repairedPage.prevHref,
        'nextHref': repairedPage.nextHref,
        'catalogHref': repairedPage.catalogHref,
      });
      if (!_canCommitRequest(requestContext)) {
        return;
      }
      _applyLoadedPage(
        repairedPage,
        requestContext: requestContext,
        switchToTab: false,
      );
    } catch (error) {
      DebugTrace.log('reader.navigation_repair_failed', <String, Object?>{
        'bootId': _shell.bootId,
        'uri': targetUri.toString(),
        'error': error.toString(),
      });
    } finally {
      _nav.repairRouteKeys.remove(key.routeKey);
    }
  }

  Future<bool> _tryOpenCachedChapterReader(
    Uri targetUri, {
    required NavigationRequestContext requestContext,
    CachedChapterNavigationContext context =
        const CachedChapterNavigationContext(),
  }) async {
    final CachedChapterNavigationContext resolvedContext =
        _resolvedCachedChapterContext(targetUri, context: context);
    final ReaderPageData? cachedPage = await _services.downloadService
        .loadCachedReaderPage(
          targetUri.toString(),
          prevHref: resolvedContext.prevHref,
          nextHref: resolvedContext.nextHref,
          catalogHref: resolvedContext.catalogHref,
        );
    if (cachedPage == null) {
      return false;
    }
    final bool applied = _applyLoadedPage(
      cachedPage,
      requestContext: requestContext,
      switchToTab: true,
    );
    if (applied && cachedPage.hasMissingChapterNavigation) {
      unawaited(
        _repairCachedReaderNavigation(
          cachedPage,
          targetUri: targetUri,
          context: resolvedContext,
          requestContext: requestContext,
          persistToPageCache: false,
        ),
      );
    }
    return applied;
  }

  void _openDetailChapter(DetailPageData page, String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final links = page.adjacentTo(href);
    unawaited(
      _openHref(
        href,
        prevHref: links?.prevHref ?? '',
        nextHref: links?.nextHref ?? '',
        catalogHref: page.uri,
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    if (_ui.mobileSearchFocusNode.hasFocus) {
      _ui.mobileSearchFocusNode.unfocus();
      return;
    }
    if (_isReaderMode) {
      await _runReaderExitTransition(() async {
        await _handleReaderBack();
      });
      return;
    }
    await _handleReaderBack();
  }

  Future<void> _handleReaderBack() async {
    final SitePage? page = _page;
    if (page is ReaderPageData) {
      await _ui.readerScreenKey.currentState?.controller
          .flushProgressPersistence();
    } else {
      _scrollState.persistVisiblePageState();
    }
    if (page is ReaderPageData && await _handleReaderBackNavigation(page)) {
      return;
    }
    _scrollState.pauseTrackingForRoute();
    final PrimaryTabRouteEntry? previousEntry = _tabSessionStore.pop(
      _nav.selectedIndex,
    );
    if (previousEntry != null) {
      await _loadUri(
        previousEntry.uri,
        preserveVisiblePage: _page != null,
        skipPersistVisiblePageState: true,
        sourceTabIndex: _nav.selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    if (_nav.selectedIndex != 0) {
      await _loadHome();
      return;
    }
    if (_shouldConfirmBackToExit()) {
      return;
    }
    await SystemNavigator.pop();
  }

  /// 移动端根路由需二次返回退出，避免误触。
  bool _shouldConfirmBackToExit() {
    if (PlatformCapabilities.isDesktop) {
      return false;
    }
    final DateTime now = DateTime.now();
    final DateTime? lastPrompt = _shell.backToExitPromptedAt;
    if (lastPrompt != null &&
        now.difference(lastPrompt) <= _backToExitConfirmWindow) {
      return false;
    }
    _shell.backToExitPromptedAt = now;
    _showNotice('再按一次返回退出应用');
    return true;
  }

  Future<void> _runReaderExitTransition(Future<void> Function() action) async {
    if (!_isReaderMode || _shell.isReaderExitTransitionActive || !mounted) {
      await action();
      return;
    }

    _setStateIfMounted(() {
      _shell.isReaderExitTransitionActive = true;
    });

    final Future<void> fadeFuture = Future<void>.delayed(
      _readerExitFadeDuration,
    );
    try {
      await action();
      await fadeFuture;
    } finally {
      if (!mounted) {
        _shell.isReaderExitTransitionActive = false;
      } else if (_page is ReaderPageData) {
        _setStateIfMounted(() {
          _shell.isReaderExitTransitionActive = false;
        });
      } else {
        _shell.isReaderExitTransitionActive = false;
      }
    }
  }

  Future<bool> _handleReaderBackNavigation(ReaderPageData page) async {
    final String catalogHref = page.catalogHref.trim();
    if (catalogHref.isEmpty) {
      return false;
    }
    final Uri catalogUri = AppConfig.resolveNavigationUri(
      catalogHref,
      currentUri: Uri.parse(page.uri),
    );
    final PrimaryTabRouteEntry? existingCatalogEntry = _tabSessionStore
        .popToRoute(_nav.selectedIndex, catalogUri);
    if (existingCatalogEntry != null) {
      await _loadUri(
        existingCatalogEntry.uri,
        preserveVisiblePage: existingCatalogEntry.page != null,
        skipPersistVisiblePageState: true,
        sourceTabIndex: _nav.selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return true;
    }
    // 直接进入阅读时，用目录替换阅读页，保留下面的来源页。
    _scrollState.pauseTrackingForRoute();
    await _loadUri(
      catalogUri,
      skipPersistVisiblePageState: true,
      sourceTabIndex: _nav.selectedIndex,
      historyMode: NavigationIntent.preserve,
    );
    return true;
  }

  String _resolveHistoryCoverForCatalog(String catalogHref) {
    final String catalogPath = Uri.tryParse(catalogHref)?.path ?? '';
    if (catalogPath.isEmpty) {
      return '';
    }
    for (final PrimaryTabRouteEntry entry in _tabSessionStore.stackForTab(
      _nav.selectedIndex,
    )) {
      final SitePage? entryPage = entry.page;
      if (entryPage is DetailPageData &&
          Uri.parse(entryPage.uri).path == catalogPath) {
        return entryPage.coverUrl;
      }
    }
    final CachedComicLibraryEntry? cachedEntry = _library.cachedComics
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? item) =>
              item != null && Uri.tryParse(item.comicHref)?.path == catalogPath,
          orElse: () => null,
        );
    return cachedEntry?.coverUrl ?? '';
  }

  bool get _isReaderMode => _page is ReaderPageData;

  Widget _buildReaderLoadingScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
