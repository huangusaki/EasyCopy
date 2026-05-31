part of '../easy_copy_screen.dart';

extension _EasyCopyScreenTabNavigation on _EasyCopyScreenState {
  void _setSelectedPrimaryTabIndex(int index, {bool persist = true}) {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (_selectedIndex == index) {
      return;
    }
    _selectedIndex = index;
    if (persist) {
      unawaited(_preferencesController.setLastPrimaryTabIndex(index));
    }
  }

  Future<void> _retryCurrentPage() async {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData ||
        (page == null && _isProfileUri(_currentUri))) {
      await _loadProfilePage(
        targetUri: _currentUri,
        forceRefresh: true,
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    await _loadUri(
      _currentUri,
      bypassCache: true,
      preserveVisiblePage: _page != null,
      sourceTabIndex: _selectedIndex,
      historyMode: NavigationIntent.preserve,
    );
  }

  Future<void> _loadHome() async {
    await _loadUri(
      _targetUriForPrimaryTab(0, resetToRoot: true),
      preserveVisiblePage: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  ProfileCollectionSort _effectiveProfileCollectionSort(
    ProfileCollectionSort sort,
  ) {
    final EasyCopyPage? page = _page;
    final bool isLoggedIn = page is ProfilePageData
        ? page.isLoggedIn
        : _session.isAuthenticated;
    if (isLoggedIn && sort == ProfileCollectionSort.alphabetical) {
      return AppConfig.defaultProfileCollectionSort;
    }
    return sort;
  }

  ProfileCollectionSort _preferredProfileCollectionSort() {
    return _effectiveProfileCollectionSort(
      _preferencesController.profileCollectionSort,
    );
  }

  Uri _profileUriWithPreferredCollectionSort(Uri uri) {
    final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
    final ProfileSubview view = AppConfig.profileSubviewForUri(normalizedUri);
    if (view != ProfileSubview.root && view != ProfileSubview.collections) {
      return normalizedUri;
    }
    final Map<String, String> queryParameters = Map<String, String>.from(
      normalizedUri.queryParameters,
    );
    final ProfileCollectionSort sort = queryParameters.containsKey('sort')
        ? _effectiveProfileCollectionSort(
            AppConfig.profileCollectionSortForUri(normalizedUri),
          )
        : _preferredProfileCollectionSort();
    queryParameters['sort'] = AppConfig.profileCollectionSortQueryValue(sort);
    if (view == ProfileSubview.root) {
      queryParameters.remove('view');
      queryParameters.remove('page');
    }
    return normalizedUri.replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  void _openProfileSubview(
    ProfileSubview view, {
    int page = 1,
    ProfileCollectionSort? collectionSort,
    NavigationIntent historyMode = NavigationIntent.push,
  }) {
    final ProfileCollectionSort? effectiveCollectionSort =
        view == ProfileSubview.collections
        ? _effectiveProfileCollectionSort(
            collectionSort ?? _preferencesController.profileCollectionSort,
          )
        : null;
    unawaited(
      _loadProfilePage(
        targetUri: AppConfig.buildProfileUri(
          view: view,
          page: page,
          collectionSort: effectiveCollectionSort,
        ),
        preserveVisiblePage: _page is ProfilePageData,
        historyMode: historyMode,
      ),
    );
  }

  void _navigateDiscoverFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    _applyOptimisticDiscoverFilterSelectionToCurrentPage(targetUri);
    unawaited(
      _loadUri(
        targetUri,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _navigateRankFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    _applyOptimisticRankFilterSelectionToCurrentPage(targetUri);
    unawaited(
      _loadUri(
        targetUri,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _applyOptimisticDiscoverFilterSelectionToCurrentPage(Uri targetUri) {
    final EasyCopyPage? page = _page;
    if (page is! DiscoverPageData) {
      return;
    }
    final DiscoverPageData nextPage = applyOptimisticDiscoverFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _applyOptimisticRankFilterSelectionToCurrentPage(Uri targetUri) {
    final EasyCopyPage? page = _page;
    if (page is! RankPageData) {
      return;
    }
    final RankPageData nextPage = applyOptimisticRankFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _navigateToHref(String href, {int? sourceTabIndex}) {
    unawaited(
      _openHref(href, sourceTabIndex: sourceTabIndex ?? _selectedIndex),
    );
  }

  Future<void> _openHref(
    String href, {
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
    int? sourceTabIndex,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    await _loadUri(
      targetUri,
      sourceTabIndex: sourceTabIndex ?? _selectedIndex,
      historyMode: historyMode,
      cachedChapterContext: CachedChapterNavigationContext(
        prevHref: prevHref,
        nextHref: nextHref,
        catalogHref: catalogHref,
      ),
    );
  }

  Future<void> _toggleDetailCollection(DetailPageData page) async {
    if (_isUpdatingCollection) {
      return;
    }

    final int sourceTabIndex = _selectedIndex;
    final bool nextCollected = !page.isCollected;
    _mutateSessionState(() {
      _isUpdatingCollection = true;
    }, syncSearch: false);
    try {
      if (_session.isAuthenticated && (_session.token ?? '').isNotEmpty) {
        await _siteApiClient.setComicCollection(
          comicId: page.comicId,
          isCollected: nextCollected,
        );
      } else {
        if (nextCollected) {
          final String secondaryText = page.updatedAt.trim().isNotEmpty
              ? page.updatedAt.trim()
              : page.status.trim();
          await _localLibraryStore.upsertCollection(
            LocalLibraryStore.guestScope,
            ProfileLibraryItem(
              title: page.title.trim(),
              coverUrl: page.coverUrl.trim(),
              href: page.uri.trim(),
              subtitle: page.authors.trim(),
              secondaryText: secondaryText,
              updatedAt: page.updatedAt.trim(),
            ),
          );
        } else {
          await _localLibraryStore.removeCollection(
            LocalLibraryStore.guestScope,
            page.uri,
          );
        }
      }
      final DetailPageData updatedPage = page.copyWith(
        isCollected: nextCollected,
      );
      _mutateSessionState(() {
        _tabSessionStore.updatePage(sourceTabIndex, updatedPage);
      }, syncSearch: sourceTabIndex == _selectedIndex);
      unawaited(_persistDetailPageCache(updatedPage));
      if (mounted) {
        _showNotice(nextCollected ? '已加入书架' : '已取消收藏');
      }
    } catch (error) {
      final String message = error is SiteApiException
          ? error.message
          : error.toString();
      if (message.contains('登录已失效')) {
        await _logout(showFeedback: false);
      }
      if (mounted) {
        _showNotice(message.isEmpty ? '收藏操作失败，请稍后重试。' : message);
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingCollection = false;
        }, syncSearch: false);
      } else {
        _isUpdatingCollection = false;
      }
    }
  }

  Future<void> _openAuthFlow() async {
    await _hostManager.ensureInitialized();
    if (!mounted) {
      return;
    }
    final AuthSessionResult? result = await Navigator.of(context).push(
      MaterialPageRoute<AuthSessionResult>(
        builder: (BuildContext context) {
          return NativeLoginScreen(
            loginUri: AppConfig.resolvePath('/web/login/?url=person/home'),
            userAgent: AppConfig.desktopUserAgent,
          );
        },
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final String? token = result.cookies['token'];
    if ((token ?? '').isEmpty) {
      return;
    }
    await _session.updateFromCookieHeader(result.cookieHeader);
    await _session.saveToken(token!, cookies: result.cookies);
    try {
      await _siteApiClient.loadUserInfo();
    } catch (_) {
      // Best-effort user binding only.
    }
    await _syncSessionCookiesToCurrentHost();
    await _loadProfilePage(
      forceRefresh: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  Future<void> _logout({bool showFeedback = true}) async {
    _persistVisiblePageState();
    _resetStandardScrollPosition();
    await _pageRepository.removeAuthenticatedEntries();
    await _session.clear();
    await _cookieManager.clearCookies();
    _mutateSessionState(() {
      for (int index = 0; index < appDestinations.length; index += 1) {
        _abandonCurrentRequest(index, phase: 'logout');
      }
      _setSelectedPrimaryTabIndex(3);
      _tabSessionStore.resetToRoot(3);
      _tabSessionStore.updateCurrent(
        3,
        (PrimaryTabRouteEntry entry) => entry.copyWith(clearPage: true),
      );
    });
    await _loadProfilePage(
      forceRefresh: true,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.resetToRoot,
    );
    if (showFeedback) {
      _showNotice('已退出登录');
    }
  }

  String get _appVersionLabel {
    if (_appVersion.isEmpty) {
      return '--';
    }
    if (_appBuildNumber.isEmpty) {
      return _appVersion;
    }
    return '$_appVersion+$_appBuildNumber';
  }

  Uri _targetUriForPrimaryTab(int index, {bool resetToRoot = false}) {
    if (resetToRoot) {
      return appDestinations[index].uri;
    }
    return _tabSessionStore.currentEntry(index).uri;
  }

  bool _activateRestoredPrimaryTab(int index) {
    if (index == _selectedIndex) {
      return false;
    }
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(index);
    final EasyCopyPage? page = entry.page;
    if (page == null) {
      return false;
    }
    final int previousSelectedIndex = _selectedIndex;
    _mutateSessionState(() {
      _abandonCurrentRequest(
        previousSelectedIndex,
        phase: 'restore-tab-$index',
      );
      _abandonCurrentRequest(index, phase: 'restore-tab-$index');
      _setSelectedPrimaryTabIndex(index);
    });
    if (page is! ReaderPageData) {
      _restoreStandardScrollPosition(
        entry.standardScrollOffset,
        tabIndex: index,
        routeKey: entry.routeKey,
      );
    }
    return true;
  }

  Future<void> _onItemTapped(int index) async {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (index == _selectedIndex && _isPrimaryTabContent && !_isLoading) {
      await _scrollCurrentStandardPageToTop();
      return;
    }
    if (index == 3) {
      await _loadProfilePage(
        preserveVisiblePage: true,
        historyMode: index == _selectedIndex
            ? NavigationIntent.resetToRoot
            : NavigationIntent.preserve,
      );
      return;
    }
    final bool shouldResetToRoot = index == _selectedIndex;
    final Uri targetUri = _targetUriForPrimaryTab(
      index,
      resetToRoot: shouldResetToRoot,
    );
    if (!shouldResetToRoot &&
        _tabSessionStore.currentEntry(index).page != null) {
      _persistVisiblePageState();
      if (_activateRestoredPrimaryTab(index)) {
        unawaited(
          _loadUri(
            targetUri,
            preserveVisiblePage: true,
            skipPersistVisiblePageState: true,
            skipIfTargetTabInactive: true,
            // Restoring a tab should keep the tab's own stack ownership even when
            // the visible route is a shared detail or reader URI like `/comic/...`.
            targetTabIndexOverride: index,
            historyMode: NavigationIntent.preserve,
          ),
        );
        return;
      }
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: !shouldResetToRoot,
      targetTabIndexOverride: index,
      historyMode: shouldResetToRoot
          ? NavigationIntent.resetToRoot
          : NavigationIntent.preserve,
    );
  }
}
