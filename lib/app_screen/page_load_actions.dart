part of '../app_screen.dart';

/// 缓存命中后延迟刷新，避开切页高峰。
const Duration _backgroundRevalidateDelay = Duration(milliseconds: 1200);

extension _AppScreenPageLoadActions on _AppScreenState {
  Future<void> _runDeferredBackgroundRefresh(
    NavigationRequestContext requestContext,
    Future<void> Function() refresh,
  ) async {
    await Future<void>.delayed(_backgroundRevalidateDelay);
    if (!mounted || !_canCommitRequest(requestContext)) {
      return;
    }
    perfLog(
      '[load] background refresh start '
      'route=${requestContext.routeKey}',
    );
    _markTabEntryLoading(requestContext, preservePage: true);
    await refresh();
    perfLog('[load] background refresh done route=${requestContext.routeKey}');
  }

  void _setPendingLocation(
    Uri uri, {
    required StandardPageLoadHandle<SitePage> pendingLoad,
  }) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    _mutateOwnedRequestEntry(
      pendingLoad.requestContext,
      (PrimaryTabRouteEntry entry) => entry.copyWith(uri: rewrittenUri),
      phase: 'set-pending-location',
    );
  }

  void _startLoading(
    Uri uri, {
    required StandardPageLoadHandle<SitePage> pendingLoad,
  }) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final bool preserveCurrentPage = pendingLoad.preserveCurrentPage;
    if (!preserveCurrentPage &&
        _canCommitRequest(pendingLoad.requestContext) &&
        pendingLoad.targetTabIndex == _nav.selectedIndex) {
      _scrollState.resetStandardScrollPosition();
    }
    final SitePage? visiblePage = preserveCurrentPage
        ? _tabSessionStore.currentEntry(pendingLoad.targetTabIndex).page
        : null;
    _mutateOwnedRequestEntry(
      pendingLoad.requestContext,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        uri: rewrittenUri,
        page: visiblePage,
        clearPage: !preserveCurrentPage,
        isLoading: true,
        clearError: true,
        standardScrollOffset: preserveCurrentPage
            ? entry.standardScrollOffset
            : 0,
      ),
      phase: 'start-loading',
    );
  }

  NavigationRequestContext _prepareRouteEntry(
    Uri uri, {
    required int targetTabIndex,
    required NavigationIntent intent,
    required bool preserveVisiblePage,
    required NavigationRequestSourceKind sourceKind,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex = targetTabIndex;
    final NavigationRequestContext requestContext =
        _createNavigationRequestContext(
          targetUri,
          targetTabIndex: tabIndex,
          intent: intent,
          preserveVisiblePage: preserveVisiblePage,
          sourceKind: sourceKind,
        );
    final bool shouldActivateTab = shouldActivateTargetTab(
      currentSelectedIndex: _nav.selectedIndex,
      targetTabIndex: tabIndex,
      phase: TabActivationPhase.navigationRequest,
    );
    final SitePage? preservedPage = preserveVisiblePage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    final int previousSelectedIndex = _nav.selectedIndex;
    _mutateSessionState(() {
      if (previousSelectedIndex != tabIndex) {
        _abandonCurrentRequest(
          previousSelectedIndex,
          phase: 'activate-tab-$tabIndex',
        );
      }
      if (intent == NavigationIntent.push) {
        _abandonCurrentRequest(tabIndex, phase: 'push-route');
      }
      switch (intent) {
        case NavigationIntent.push:
          _tabSessionStore.push(tabIndex, targetUri);
          break;
        case NavigationIntent.preserve:
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
        case NavigationIntent.resetToRoot:
          _tabSessionStore.resetToRoot(tabIndex);
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
      }
      if (shouldActivateTab) {
        _setSelectedPrimaryTabIndex(tabIndex);
      }
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          uri: targetUri,
          page: preservedPage,
          clearPage: !preserveVisiblePage,
          isLoading: true,
          clearError: true,
          standardScrollOffset: preserveVisiblePage
              ? entry.standardScrollOffset
              : 0,
          activeRequestId: requestContext.requestId,
        ),
      );
    });
    if (preserveVisiblePage &&
        preservedPage != null &&
        preservedPage is! ReaderPageData &&
        tabIndex == _nav.selectedIndex) {
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        tabIndex,
      );
      _scrollState.restoreStandardScrollPosition(
        entry.standardScrollOffset,
        tabIndex: tabIndex,
        routeKey: entry.routeKey,
      );
    }
    return requestContext;
  }

  void _markTabEntryLoading(
    NavigationRequestContext request, {
    required bool preservePage,
  }) {
    _mutateOwnedRequestEntry(
      request,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: true,
        clearError: true,
        clearPage: !preservePage,
      ),
      phase: 'mark-loading',
    );
  }

  void _finishTabEntryLoading(
    NavigationRequestContext request, {
    String? message,
  }) {
    _mutateOwnedRequestEntry(
      request,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: false,
        errorMessage: message,
        clearError: message == null,
      ),
      phase: 'finish-loading',
    );
  }

  Future<SitePage> _loadStandardPageFresh(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final NavigationRequestContext loadRequestContext =
        requestContext ??
        _createNavigationRequestContext(
          targetUri,
          targetTabIndex: resolveNavigationTabIndex(targetUri),
          intent: NavigationIntent.preserve,
          preserveVisiblePage: false,
          sourceKind: NavigationRequestSourceKind.navigation,
        );
    final int loadId = ++_nav.activeLoadId;
    final StandardPageLoadHandle<SitePage> pendingLoad =
        StandardPageLoadHandle<SitePage>(
          requestedUri: targetUri,
          queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
          loadId: loadId,
          requestContext: loadRequestContext,
          completer: Completer<SitePage>(),
        );
    _standardPageLoadController.begin(pendingLoad);
    await _syncHostCookies();
    if (!_standardPageLoadController.isCurrent(pendingLoad)) {
      _detachPrimaryWebViewIfIdle();
      throw const SupersededPageLoadException();
    }
    if (!PlatformCapabilities.usesMobileWebView) {
      unawaited(
        _loadStandardPageWithDesktopExtractor(
          pendingLoad: pendingLoad,
          targetUri: targetUri,
        ),
      );
      return pendingLoad.completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _standardPageLoadController.clear(pendingLoad);
          throw TimeoutException('页面解析超时');
        },
      );
    }
    await _ensurePrimaryWebViewAttached();
    try {
      await _primaryWebViewController.loadRequest(targetUri);
    } catch (_) {
      _failPendingPageLoad('页面加载失败，请稍后重试。');
      rethrow;
    }
    return pendingLoad.completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _standardPageLoadController.clear(pendingLoad);
        _detachPrimaryWebViewIfIdle();
        throw TimeoutException('页面解析超时');
      },
    );
  }

  Future<void> _loadStandardPageWithDesktopExtractor({
    required StandardPageLoadHandle<SitePage> pendingLoad,
    required Uri targetUri,
  }) async {
    try {
      final SitePage page = await DesktopPageExtractor.instance.loadPage(
        targetUri,
        loadId: pendingLoad.loadId,
      );
      if (!_standardPageLoadController.isCurrent(pendingLoad)) {
        if (!pendingLoad.completer.isCompleted) {
          pendingLoad.completer.completeError(
            const SupersededPageLoadException(),
          );
        }
        return;
      }
      if (!pendingLoad.completer.isCompleted) {
        pendingLoad.completer.complete(page);
      }
    } catch (error, stackTrace) {
      if (_standardPageLoadController.isCurrent(pendingLoad) &&
          !pendingLoad.completer.isCompleted) {
        pendingLoad.completer.completeError(error, stackTrace);
      }
    } finally {
      _standardPageLoadController.clear(pendingLoad);
    }
  }

  Future<SitePage> _preparePageForApply(SitePage page) async {
    if (page is! DetailPageData) {
      return page;
    }
    if (_services.session.isAuthenticated) {
      return page;
    }
    try {
      final bool isCollected = await _services.localLibraryStore.isCollected(
        LocalLibraryStore.guestScope,
        page.uri,
      );
      if (isCollected == page.isCollected) {
        return page;
      }
      final DetailPageData updated = page.copyWith(isCollected: isCollected);
      unawaited(_persistDetailPageCache(updated));
      return updated;
    } catch (_) {
      return page;
    }
  }

  Future<void> _persistDetailPageCache(DetailPageData page) async {
    try {
      final String authScope = _pageQueryKeyForUri(
        Uri.parse(page.uri),
      ).authScope;
      await _pageRepository.writeCachedPage(page, authScope: authScope);
    } catch (_) {
      // 缓存修复失败不影响当前页面。
    }
  }

  bool _applyLoadedPage(
    SitePage page, {
    NavigationRequestContext? requestContext,
    int? targetTabIndex,
    bool switchToTab = true,
    Uri? visibleUri,
  }) {
    final SitePage resolvedPage = _pageForVisibleUri(page, visibleUri);
    final Uri pageUri = AppConfig.rewriteToCurrentHost(
      Uri.parse(resolvedPage.uri),
    );
    final int tabIndex =
        requestContext?.targetTabIndex ??
        targetTabIndex ??
        tabIndexForUri(pageUri);
    if (requestContext != null && !_canCommitRequest(requestContext)) {
      _recordDiscardedMutation(requestContext, phase: 'apply-page');
      return false;
    }
    final SitePage? previousPage =
        (switchToTab || tabIndex == _nav.selectedIndex) ? _page : null;

    _mutateSessionState(() {
      if (switchToTab) {
        _setSelectedPrimaryTabIndex(tabIndex);
      }
      _tabSessionStore.updatePage(tabIndex, resolvedPage);
      if (resolvedPage is DetailPageData) {
        _detailChapters.sync(
          resolvedPage,
          forceReset:
              previousPage is! DetailPageData ||
              previousPage.uri != resolvedPage.uri,
        );
        unawaited(_persistCachedDetailSnapshot(resolvedPage));
      }
    }, syncSearch: switchToTab || tabIndex == _nav.selectedIndex);

    if (tabIndex != _nav.selectedIndex) {
      return true;
    }
    if (resolvedPage is DetailPageData && !_services.session.isAuthenticated) {
      unawaited(
        _services.localLibraryStore.recordHistoryFromDetail(
          LocalLibraryStore.guestScope,
          resolvedPage,
        ),
      );
    }
    if (resolvedPage is ReaderPageData) {
      return true;
    }
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(tabIndex);
    _scrollState.restoreStandardScrollPosition(
      entry.standardScrollOffset,
      tabIndex: tabIndex,
      routeKey: entry.routeKey,
    );
    return true;
  }

  SitePage _pageForVisibleUri(SitePage page, Uri? visibleUri) {
    if (visibleUri == null) {
      return page;
    }
    final Uri normalizedVisibleUri = AppConfig.rewriteToCurrentHost(visibleUri);
    if (page is ProfilePageData && isProfileUri(normalizedVisibleUri)) {
      return page.copyWith(uri: normalizedVisibleUri.toString());
    }
    return page;
  }

  void _failPendingPageLoad(String message) {
    final StandardPageLoadHandle<SitePage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null) {
      _detachPrimaryWebViewIfIdle();
      return;
    }
    if (!pendingLoad.completer.isCompleted) {
      pendingLoad.completer.completeError(message);
    }
    _standardPageLoadController.clear(pendingLoad);
    _detachPrimaryWebViewIfIdle();
  }

  Future<void> _loadUri(
    Uri uri, {
    bool bypassCache = false,
    bool preserveVisiblePage = false,
    bool skipPersistVisiblePageState = false,
    bool skipIfTargetTabInactive = false,
    NavigationIntent historyMode = NavigationIntent.push,
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    CachedChapterNavigationContext cachedChapterContext =
        const CachedChapterNavigationContext(),
  }) async {
    if (!skipPersistVisiblePageState) {
      _scrollState.persistVisiblePageState();
    }
    await _services.hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int resolvedTargetTabIndex =
        targetTabIndexOverride ??
        resolveNavigationTabIndex(targetUri, sourceTabIndex: sourceTabIndex);
    if (skipIfTargetTabInactive &&
        _nav.selectedIndex != resolvedTargetTabIndex) {
      return;
    }
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (!bypassCache &&
        !preserveVisiblePage &&
        !_isLoading &&
        _page != null &&
        _currentEntry.routeKey == key.routeKey &&
        _routes.isPrimaryTabContent) {
      _scrollState.restoreStandardScrollPosition(
        _currentEntry.standardScrollOffset,
        tabIndex: _nav.selectedIndex,
        routeKey: _currentEntry.routeKey,
      );
      return;
    }
    if (!preserveVisiblePage) {
      _scrollState.resetStandardScrollPosition();
    }
    if (isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    if (isProfileUri(targetUri)) {
      await _loadProfilePage(
        targetUri: targetUri,
        forceRefresh: bypassCache,
        historyMode: historyMode,
        preserveVisiblePage: preserveVisiblePage,
      );
      return;
    }
    if (!AppConfig.isAllowedNavigationUri(targetUri)) {
      _showNotice('已阻止跳转到站外页面');
      return;
    }
    _web.consecutiveFrameFailures = 0;
    final NavigationRequestContext requestContext = _prepareRouteEntry(
      targetUri,
      targetTabIndex: resolvedTargetTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: NavigationRequestSourceKind.navigation,
    );
    final bool isReaderChapterRoute = _isReaderChapterUri(targetUri);
    final bool shouldPreferFreshReaderLoad =
        isReaderChapterRoute &&
        _downloadQueueManager.shouldBypassCachedReaderLookup;
    final Stopwatch? readerLoadStopwatch = isReaderChapterRoute
        ? (Stopwatch()..start())
        : null;
    if (isReaderChapterRoute) {
      DebugTrace.log('reader.load_request', <String, Object?>{
        'bootId': _shell.bootId,
        'uri': targetUri.toString(),
        'bypassCache': bypassCache,
        'historyMode': historyMode.name,
      });
    }
    if (isReaderChapterRoute) {
      if (shouldPreferFreshReaderLoad) {
        DebugTrace.log('reader.cached_lookup_skipped', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': targetUri.toString(),
          'reason': 'storage_migration_active',
        });
      } else {
        final bool openedFromCache = await _tryOpenCachedChapterReader(
          targetUri,
          requestContext: requestContext.copyWith(
            sourceKind: NavigationRequestSourceKind.cachedReader,
          ),
          context: cachedChapterContext,
        );
        if (openedFromCache) {
          DebugTrace.log('reader.load_complete', <String, Object?>{
            'bootId': _shell.bootId,
            'uri': targetUri.toString(),
            'source': 'storage_cache',
            'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
          });
          return;
        }
      }
      if (!_canCommitRequest(requestContext)) {
        return;
      }
    }
    if (!bypassCache && !shouldPreferFreshReaderLoad) {
      final Stopwatch cacheStopwatch = Stopwatch()..start();
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      perfLog(
        '[load] readCached(${key.routeKey}) '
        '${cacheStopwatch.elapsedMilliseconds}ms '
        'hit=${cachedHit != null} memory=${cachedHit?.fromMemory ?? false}',
      );
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedMutation(requestContext, phase: 'cached-read');
        return;
      }
      if (cachedHit != null) {
        if (!_shouldBypassUnknownCache(targetUri, cachedHit.page)) {
          final SitePage cachedPage = cachedHit.page;
          final CachedChapterNavigationContext resolvedCachedContext =
              isReaderChapterRoute
              ? _resolvedCachedChapterContext(
                  targetUri,
                  context: cachedChapterContext,
                )
              : const CachedChapterNavigationContext();
          final SitePage displayPage =
              isReaderChapterRoute && cachedPage is ReaderPageData
              ? _mergeReaderPageNavigation(cachedPage, resolvedCachedContext)
              : cachedPage;
          final SitePage preparedPage = await _preparePageForApply(displayPage);
          _applyLoadedPage(
            preparedPage,
            requestContext: requestContext,
            switchToTab: _shouldActivateAsyncResultTab(
              requestContext.targetTabIndex,
            ),
          );
          if (isReaderChapterRoute) {
            DebugTrace.log('reader.load_complete', <String, Object?>{
              'bootId': _shell.bootId,
              'uri': targetUri.toString(),
              'source': 'page_cache',
              'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
            });
            if (preparedPage is ReaderPageData &&
                preparedPage.imageUrls.isNotEmpty) {
              unawaited(
                NetworkDiagnostics.probeImageVariants(
                  preparedPage.imageUrls.first,
                  referer: preparedPage.uri,
                  label: 'reader.first_image_page_cache',
                ),
              );
              if (cachedPage is ReaderPageData &&
                  _didReaderNavigationChange(cachedPage, preparedPage)) {
                unawaited(_persistReaderPageCache(preparedPage));
              }
              if (preparedPage.hasMissingChapterNavigation) {
                unawaited(
                  _repairCachedReaderNavigation(
                    preparedPage,
                    targetUri: targetUri,
                    context: resolvedCachedContext,
                    requestContext: requestContext,
                    persistToPageCache: true,
                  ),
                );
              }
            }
          }
          if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
            return;
          }
          final NavigationRequestContext revalidateContext = requestContext
              .copyWith(sourceKind: NavigationRequestSourceKind.revalidate);
          unawaited(
            _runDeferredBackgroundRefresh(revalidateContext, () {
              return _revalidateCachedPage(
                targetUri,
                key: key,
                cachedEntry: cachedHit.envelope,
                requestContext: revalidateContext,
              );
            }),
          );
          return;
        }
      }
    } else if (shouldPreferFreshReaderLoad) {
      DebugTrace.log('reader.page_cache_skipped', <String, Object?>{
        'bootId': _shell.bootId,
        'uri': targetUri.toString(),
        'reason': 'storage_migration_active',
      });
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedMutation(requestContext, phase: 'fresh-load');
      return;
    }
    try {
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.fresh_load_start', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': targetUri.toString(),
        });
      }
      final SitePage freshPage = await _pageRepository.loadFresh(
        targetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.load_complete', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': targetUri.toString(),
          'source': 'fresh',
          'pageType': freshPage.type.name,
          'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
        });
        if (freshPage is ReaderPageData && freshPage.imageUrls.isNotEmpty) {
          unawaited(
            NetworkDiagnostics.probeImageVariants(
              freshPage.imageUrls.first,
              referer: freshPage.uri,
              label: 'reader.first_image_fresh',
            ),
          );
        }
      }
      final SitePage preparedPage = await _preparePageForApply(freshPage);
      _applyLoadedPage(
        preparedPage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
      );
    } catch (error) {
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.load_failed', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': targetUri.toString(),
          'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
          'error': error.toString(),
        });
      }
      await _handlePageLoadFailure(error, requestContext: requestContext);
    }
  }

  Future<void> _revalidateCachedPage(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope cachedEntry,
    required NavigationRequestContext requestContext,
    Uri? visibleUri,
  }) async {
    try {
      await _pageRepository.revalidate(
        uri,
        key: key,
        envelope: cachedEntry,
        requestContext: requestContext,
      );
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedMutation(requestContext, phase: 'revalidate-complete');
        return;
      }
      final CachedPageHit? refreshedHit = await _pageRepository.readCached(key);
      if (refreshedHit != null) {
        final SitePage preparedPage = await _preparePageForApply(
          refreshedHit.page,
        );
        _applyLoadedPage(
          preparedPage,
          requestContext: requestContext,
          switchToTab: _shouldActivateAsyncResultTab(
            requestContext.targetTabIndex,
          ),
          visibleUri: visibleUri,
        );
        return;
      }
      _finishTabEntryLoading(requestContext);
    } on SupersededPageLoadException {
      _finishTabEntryLoading(requestContext);
    } catch (_) {
      _finishTabEntryLoading(requestContext);
    }
  }

  Future<void> _loadProfilePage({
    Uri? targetUri,
    bool forceRefresh = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _scrollState.persistVisiblePageState();
    if (!preserveVisiblePage) {
      _scrollState.resetStandardScrollPosition();
    }
    final Uri resolvedTargetUri = _profileUriWithSort(
      targetUri ?? AppConfig.profileUri,
    );
    const int profileTabIndex = 3;
    final NavigationRequestContext requestContext = _prepareRouteEntry(
      resolvedTargetUri,
      targetTabIndex: profileTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: NavigationRequestSourceKind.profile,
    );
    final PageQueryKey key = _pageQueryKeyForUri(resolvedTargetUri);
    final ProfileSubview activeSubview = AppConfig.profileSubviewForUri(
      resolvedTargetUri,
    );

    if (activeSubview == ProfileSubview.cached) {
      try {
        final ProfilePageData localProfilePage = await _services
            .localProfilePageLoader
            .loadLocalProfile(resolvedTargetUri, authScope: key.authScope);
        if (!_canCommitRequest(requestContext)) {
          _recordDiscardedMutation(
            requestContext,
            phase: 'profile-cached-local',
          );
          return;
        }
        _applyLoadedPage(
          localProfilePage,
          requestContext: requestContext,
          switchToTab: _shouldActivateAsyncResultTab(
            requestContext.targetTabIndex,
          ),
          visibleUri: resolvedTargetUri,
        );
      } catch (error) {
        await _handlePageLoadFailure(error, requestContext: requestContext);
      }
      return;
    }

    try {
      if (!forceRefresh) {
        final bool appliedCachedOrLocal = await _applyFastProfilePage(
          resolvedTargetUri,
          key: key,
          requestContext: requestContext,
        );
        if (appliedCachedOrLocal) {
          return;
        }
      }

      final SitePage profilePage = await _pageRepository.loadFresh(
        resolvedTargetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedMutation(requestContext, phase: 'profile-load');
        return;
      }
      if (profilePage is! ProfilePageData) {
        return;
      }
      _applyLoadedPage(
        profilePage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
        visibleUri: resolvedTargetUri,
      );
    } catch (error) {
      await _loadFallbackProfilePage(
        resolvedTargetUri,
        error,
        authScope: key.authScope,
        requestContext: requestContext,
        showFailureNotice: forceRefresh,
      );
    }
  }

  Future<bool> _applyFastProfilePage(
    Uri targetUri, {
    required PageQueryKey key,
    required NavigationRequestContext requestContext,
  }) async {
    final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedMutation(requestContext, phase: 'profile-cached-read');
      return true;
    }
    if (cachedHit != null && cachedHit.page is ProfilePageData) {
      _applyLoadedPage(
        cachedHit.page,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
        visibleUri: targetUri,
      );
      if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
        return true;
      }
      final NavigationRequestContext revalidateContext = requestContext
          .copyWith(sourceKind: NavigationRequestSourceKind.revalidate);
      unawaited(
        _runDeferredBackgroundRefresh(revalidateContext, () {
          return _revalidateCachedPage(
            targetUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            requestContext: revalidateContext,
            visibleUri: targetUri,
          );
        }),
      );
      return true;
    }

    final ProfilePageData localProfilePage = await _services
        .localProfilePageLoader
        .loadLocalProfile(targetUri, authScope: key.authScope);
    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedMutation(requestContext, phase: 'profile-local-read');
      return true;
    }
    _applyLoadedPage(
      localProfilePage,
      requestContext: requestContext,
      switchToTab: _shouldActivateAsyncResultTab(requestContext.targetTabIndex),
      visibleUri: targetUri,
    );
    if (!localProfilePage.isLoggedIn) {
      return true;
    }
    // 登录态但无服务端缓存：本地页仅为占位（user==null、仅本地收藏），
    // 账号信息与服务端书架只能靠服务端拉取。返回 false 让调用方立即前台拉取，
    // 不走 1200ms 延迟通道——后者会在用户快速切 Tab 时被 _canCommitRequest 静默丢弃，
    // 导致已登录却停留在本地占位页不再自动刷新。
    return false;
  }

  Future<void> _loadFallbackProfilePage(
    Uri targetUri,
    Object error, {
    required String authScope,
    required NavigationRequestContext requestContext,
    required bool showFailureNotice,
  }) async {
    if (error is SupersededPageLoadException ||
        error.toString().contains('登录已失效')) {
      await _handlePageLoadFailure(error, requestContext: requestContext);
      return;
    }

    try {
      final ProfilePageData localProfilePage = await _services
          .localProfilePageLoader
          .loadLocalProfile(targetUri, authScope: authScope);
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedMutation(
          requestContext,
          phase: 'profile-local-fallback',
        );
        return;
      }
      _applyLoadedPage(
        localProfilePage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
        visibleUri: targetUri,
      );
      if (showFailureNotice &&
          requestContext.targetTabIndex == _nav.selectedIndex) {
        _showNotice(error.toString());
      }
    } catch (_) {
      await _handlePageLoadFailure(error, requestContext: requestContext);
    }
  }

  Future<void> _handlePageLoadFailure(
    Object error, {
    required NavigationRequestContext requestContext,
  }) async {
    if (error is SupersededPageLoadException) {
      _finishTabEntryLoading(requestContext);
      return;
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedMutation(requestContext, phase: 'page-load-failure');
      return;
    }

    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (requestContext.targetTabIndex == _nav.selectedIndex) {
        _showNotice('登录已失效，请重新登录。');
      }
      return;
    }

    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
      requestContext.targetTabIndex,
    );
    if (entry.page != null) {
      _finishTabEntryLoading(requestContext);
      if (requestContext.targetTabIndex == _nav.selectedIndex) {
        _showNotice(message);
      }
      return;
    }

    _finishTabEntryLoading(requestContext, message: message);
  }
}
