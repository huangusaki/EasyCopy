part of '../easy_copy_screen.dart';

extension _EasyCopyScreenPageLoadActions on _EasyCopyScreenState {
  void _setPendingLocation(
    Uri uri, {
    required StandardPageLoadHandle<EasyCopyPage> pendingLoad,
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
    required StandardPageLoadHandle<EasyCopyPage> pendingLoad,
  }) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final bool preserveCurrentPage = pendingLoad.preserveCurrentPage;
    if (!preserveCurrentPage &&
        _canCommitRequest(pendingLoad.requestContext) &&
        pendingLoad.targetTabIndex == _selectedIndex) {
      _resetStandardScrollPosition();
    }
    final EasyCopyPage? visiblePage = preserveCurrentPage
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
      currentSelectedIndex: _selectedIndex,
      targetTabIndex: tabIndex,
      phase: TabActivationPhase.navigationRequest,
    );
    final EasyCopyPage? preservedPage = preserveVisiblePage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    final int previousSelectedIndex = _selectedIndex;
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
        _selectedIndex = tabIndex;
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
        tabIndex == _selectedIndex) {
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        tabIndex,
      );
      _restoreStandardScrollPosition(
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

  void _finishMatchingRouteLoading(
    NavigationRequestContext request, {
    String? message,
  }) {
    _finishTabEntryLoading(request, message: message);
  }

  Future<EasyCopyPage> _loadStandardPageFresh(
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
    final int loadId = ++_activeLoadId;
    final StandardPageLoadHandle<EasyCopyPage> pendingLoad =
        StandardPageLoadHandle<EasyCopyPage>(
          requestedUri: targetUri,
          queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
          loadId: loadId,
          requestContext: loadRequestContext,
          completer: Completer<EasyCopyPage>(),
        );
    _standardPageLoadController.begin(pendingLoad);
    await _syncSessionCookiesToCurrentHost();
    if (!_standardPageLoadController.isCurrent(pendingLoad)) {
      _detachPrimaryWebViewIfIdle();
      throw const SupersededPageLoadException();
    }
    await _ensurePrimaryWebViewAttached();
    try {
      await _controller.loadRequest(targetUri);
    } catch (_) {
      _failPendingPageLoad('頁面加載失敗，請稍後重試。');
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

  Future<EasyCopyPage> _preparePageForApply(EasyCopyPage page) async {
    if (page is! DetailPageData) {
      return page;
    }
    if (_session.isAuthenticated) {
      return page;
    }
    try {
      final bool isCollected = await _localLibraryStore.isCollected(
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
      // Best-effort cache repair only.
    }
  }

  bool _applyLoadedPage(
    EasyCopyPage page, {
    NavigationRequestContext? requestContext,
    int? targetTabIndex,
    bool switchToTab = true,
    Uri? visibleUri,
  }) {
    final EasyCopyPage resolvedPage = _pageForVisibleUri(page, visibleUri);
    final Uri pageUri = AppConfig.rewriteToCurrentHost(
      Uri.parse(resolvedPage.uri),
    );
    final int tabIndex =
        requestContext?.targetTabIndex ??
        targetTabIndex ??
        tabIndexForUri(pageUri);
    if (requestContext != null && !_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(requestContext, phase: 'apply-page');
      return false;
    }
    final EasyCopyPage? previousPage =
        (switchToTab || tabIndex == _selectedIndex) ? _page : null;

    _mutateSessionState(() {
      if (switchToTab) {
        _selectedIndex = tabIndex;
      }
      _tabSessionStore.updatePage(tabIndex, resolvedPage);
      if (resolvedPage is DetailPageData) {
        _syncDetailChapterState(
          resolvedPage,
          forceReset:
              previousPage is! DetailPageData ||
              previousPage.uri != resolvedPage.uri,
        );
        unawaited(_persistCachedDetailSnapshot(resolvedPage));
      }
    }, syncSearch: switchToTab || tabIndex == _selectedIndex);

    if (tabIndex != _selectedIndex) {
      return true;
    }
    if (resolvedPage is DetailPageData && !_session.isAuthenticated) {
      unawaited(
        _localLibraryStore.recordHistoryFromDetail(
          LocalLibraryStore.guestScope,
          resolvedPage,
        ),
      );
    }
    if (resolvedPage is ReaderPageData) {
      return true;
    }
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(tabIndex);
    _restoreStandardScrollPosition(
      entry.standardScrollOffset,
      tabIndex: tabIndex,
      routeKey: entry.routeKey,
    );
    return true;
  }

  EasyCopyPage _pageForVisibleUri(EasyCopyPage page, Uri? visibleUri) {
    if (visibleUri == null) {
      return page;
    }
    final Uri normalizedVisibleUri = AppConfig.rewriteToCurrentHost(visibleUri);
    if (page is ProfilePageData && _isProfileUri(normalizedVisibleUri)) {
      return page.copyWith(uri: normalizedVisibleUri.toString());
    }
    return page;
  }

  void _failPendingPageLoad(String message) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
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
      _persistVisiblePageState();
    }
    await _hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int resolvedTargetTabIndex =
        targetTabIndexOverride ??
        resolveNavigationTabIndex(targetUri, sourceTabIndex: sourceTabIndex);
    if (skipIfTargetTabInactive && _selectedIndex != resolvedTargetTabIndex) {
      return;
    }
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (!bypassCache &&
        !preserveVisiblePage &&
        !_isLoading &&
        _page != null &&
        _currentEntry.routeKey == key.routeKey &&
        _isPrimaryTabContent) {
      _restoreStandardScrollPosition(
        _currentEntry.standardScrollOffset,
        tabIndex: _selectedIndex,
        routeKey: _currentEntry.routeKey,
      );
      return;
    }
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    if (_isProfileUri(targetUri)) {
      await _loadProfilePage(
        targetUri: targetUri,
        forceRefresh: bypassCache,
        historyMode: historyMode,
        preserveVisiblePage: preserveVisiblePage,
      );
      return;
    }
    if (!AppConfig.isAllowedNavigationUri(targetUri)) {
      _showSnackBar('已阻止跳转到站外页面');
      return;
    }
    _consecutiveFrameFailures = 0;
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
        'bootId': _bootId,
        'uri': targetUri.toString(),
        'bypassCache': bypassCache,
        'historyMode': historyMode.name,
      });
    }
    if (isReaderChapterRoute) {
      if (shouldPreferFreshReaderLoad) {
        DebugTrace.log('reader.cached_lookup_skipped', <String, Object?>{
          'bootId': _bootId,
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
            'bootId': _bootId,
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
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedNavigationMutation(
          requestContext,
          phase: 'cached-read',
        );
        return;
      }
      if (cachedHit != null) {
        if (!_shouldBypassUnknownCache(targetUri, cachedHit.page)) {
          final EasyCopyPage cachedPage = cachedHit.page;
          final CachedChapterNavigationContext resolvedCachedContext =
              isReaderChapterRoute
              ? _resolvedCachedChapterContext(
                  targetUri,
                  context: cachedChapterContext,
                )
              : const CachedChapterNavigationContext();
          final EasyCopyPage displayPage =
              isReaderChapterRoute && cachedPage is ReaderPageData
              ? _mergeReaderPageNavigation(cachedPage, resolvedCachedContext)
              : cachedPage;
          final EasyCopyPage preparedPage = await _preparePageForApply(
            displayPage,
          );
          _applyLoadedPage(
            preparedPage,
            requestContext: requestContext,
            switchToTab: _shouldActivateAsyncResultTab(
              requestContext.targetTabIndex,
            ),
          );
          if (isReaderChapterRoute) {
            DebugTrace.log('reader.load_complete', <String, Object?>{
              'bootId': _bootId,
              'uri': targetUri.toString(),
              'source': 'page_cache',
              'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
            });
            if (preparedPage is ReaderPageData &&
                preparedPage.imageUrls.isNotEmpty) {
              NetworkDiagnostics.probeImageVariants(
                preparedPage.imageUrls.first,
                referer: preparedPage.uri,
                label: 'reader.first_image_page_cache',
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
          _markTabEntryLoading(requestContext, preservePage: true);
          unawaited(
            _revalidateCachedPage(
              targetUri,
              key: key,
              cachedEntry: cachedHit.envelope,
              requestContext: requestContext.copyWith(
                sourceKind: NavigationRequestSourceKind.revalidate,
              ),
            ),
          );
          return;
        }
      }
    } else if (shouldPreferFreshReaderLoad) {
      DebugTrace.log('reader.page_cache_skipped', <String, Object?>{
        'bootId': _bootId,
        'uri': targetUri.toString(),
        'reason': 'storage_migration_active',
      });
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(requestContext, phase: 'fresh-load');
      return;
    }
    try {
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.fresh_load_start', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
        });
      }
      final EasyCopyPage freshPage = await _pageRepository.loadFresh(
        targetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.load_complete', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
          'source': 'fresh',
          'pageType': freshPage.type.name,
          'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
        });
        if (freshPage is ReaderPageData && freshPage.imageUrls.isNotEmpty) {
          NetworkDiagnostics.probeImageVariants(
            freshPage.imageUrls.first,
            referer: freshPage.uri,
            label: 'reader.first_image_fresh',
          );
        }
      }
      final EasyCopyPage preparedPage = await _preparePageForApply(freshPage);
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
          'bootId': _bootId,
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
        _recordDiscardedNavigationMutation(
          requestContext,
          phase: 'revalidate-complete',
        );
        return;
      }
      final CachedPageHit? refreshedHit = await _pageRepository.readCached(key);
      if (refreshedHit != null) {
        final EasyCopyPage preparedPage = await _preparePageForApply(
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
      _finishMatchingRouteLoading(requestContext);
    } on SupersededPageLoadException {
      _finishMatchingRouteLoading(requestContext);
    } catch (_) {
      _finishMatchingRouteLoading(requestContext);
    }
  }

  Future<void> _loadProfilePage({
    Uri? targetUri,
    bool forceRefresh = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _persistVisiblePageState();
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    final Uri resolvedTargetUri = AppConfig.rewriteToCurrentHost(
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
    // Local profile pages should always reflect the latest local library state,
    // so we bypass profile caching entirely.

    try {
      final EasyCopyPage profilePage = await _pageRepository.loadFresh(
        resolvedTargetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      _applyLoadedPage(
        profilePage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
        visibleUri: resolvedTargetUri,
      );
    } catch (error) {
      await _handlePageLoadFailure(error, requestContext: requestContext);
    }
  }

  Future<void> _handlePageLoadFailure(
    Object error, {
    required NavigationRequestContext requestContext,
  }) async {
    if (error is SupersededPageLoadException) {
      _finishMatchingRouteLoading(requestContext);
      return;
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(
        requestContext,
        phase: 'page-load-failure',
      );
      return;
    }

    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (requestContext.targetTabIndex == _selectedIndex) {
        _showSnackBar('登录已失效，请重新登录。');
      }
      return;
    }

    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
      requestContext.targetTabIndex,
    );
    if (entry.page != null) {
      _finishTabEntryLoading(requestContext);
      if (requestContext.targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }

    _finishTabEntryLoading(requestContext, message: message);
  }
}
