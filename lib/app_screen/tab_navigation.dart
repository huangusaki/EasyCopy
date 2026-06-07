part of '../app_screen.dart';

extension _AppScreenTabNavigation on _AppScreenState {
  void _setSelectedPrimaryTabIndex(int index, {bool persist = true}) {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (_nav.selectedIndex == index) {
      return;
    }
    _nav.selectedIndex = index;
    if (persist) {
      unawaited(_preferencesController.setLastPrimaryTabIndex(index));
    }
  }

  Future<void> _retryCurrentPage() async {
    final SitePage? page = _page;
    if (page is ProfilePageData ||
        (page == null && isProfileUri(_currentUri))) {
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
      sourceTabIndex: _nav.selectedIndex,
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
    final SitePage? page = _page;
    final bool isLoggedIn = page is ProfilePageData
        ? page.isLoggedIn
        : _services.session.isAuthenticated;
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

  Uri _profileUriWithSort(Uri uri) {
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
    _applyDiscoverFilter(targetUri);
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
    _applyRankFilter(targetUri);
    unawaited(
      _loadUri(
        targetUri,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _applyDiscoverFilter(Uri targetUri) {
    final SitePage? page = _page;
    if (page is! DiscoverPageData) {
      return;
    }
    final DiscoverPageData nextPage = applyDiscoverFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _nav.selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _applyRankFilter(Uri targetUri) {
    final SitePage? page = _page;
    if (page is! RankPageData) {
      return;
    }
    final RankPageData nextPage = applyRankFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _nav.selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _navigateToHref(String href, {int? sourceTabIndex}) {
    unawaited(
      _openHref(href, sourceTabIndex: sourceTabIndex ?? _nav.selectedIndex),
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
    if (isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    await _loadUri(
      targetUri,
      sourceTabIndex: sourceTabIndex ?? _nav.selectedIndex,
      historyMode: historyMode,
      cachedChapterContext: CachedChapterNavigationContext(
        prevHref: prevHref,
        nextHref: nextHref,
        catalogHref: catalogHref,
      ),
    );
  }

  Future<void> _toggleDetailCollection(DetailPageData page) async {
    if (_shell.isUpdatingCollection) {
      return;
    }

    final int sourceTabIndex = _nav.selectedIndex;
    final bool nextCollected = !page.isCollected;
    _mutateSessionState(() {
      _shell.isUpdatingCollection = true;
    }, syncSearch: false);
    try {
      if (_services.session.isAuthenticated &&
          (_services.session.token ?? '').isNotEmpty) {
        await _services.siteApiClient.setComicCollection(
          comicId: page.comicId,
          isCollected: nextCollected,
        );
      } else {
        if (nextCollected) {
          final String secondaryText = page.updatedAt.trim().isNotEmpty
              ? page.updatedAt.trim()
              : page.status.trim();
          await _services.localLibraryStore.upsertCollection(
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
          await _services.localLibraryStore.removeCollection(
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
      }, syncSearch: sourceTabIndex == _nav.selectedIndex);
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
          _shell.isUpdatingCollection = false;
        }, syncSearch: false);
      } else {
        _shell.isUpdatingCollection = false;
      }
    }
  }

  Future<void> _openAuthFlow() async {
    await _services.hostManager.ensureInitialized();
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
    await _services.session.updateFromCookieHeader(result.cookieHeader);
    await _services.session.saveToken(token!, cookies: result.cookies);
    try {
      await _services.siteApiClient.loadUserInfo();
    } catch (_) {
      // Best-effort user binding only.
    }
    await _syncHostCookies();
    await _loadProfilePage(
      forceRefresh: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  Future<void> _logout({bool showFeedback = true}) async {
    _scrollState.persistVisiblePageState();
    _scrollState.resetStandardScrollPosition();
    await _pageRepository.removeAuthenticatedEntries();
    await _services.session.clear();
    await _ui.cookieManager.clearCookies();
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
    if (_shell.appVersion.isEmpty) {
      return '--';
    }
    if (_shell.appBuildNumber.isEmpty) {
      return _shell.appVersion;
    }
    return '${_shell.appVersion}+${_shell.appBuildNumber}';
  }

  Uri _targetUriForPrimaryTab(int index, {bool resetToRoot = false}) {
    if (resetToRoot) {
      return appDestinations[index].uri;
    }
    return _tabSessionStore.currentEntry(index).uri;
  }

  bool _activateRestoredPrimaryTab(int index) {
    if (index == _nav.selectedIndex) {
      return false;
    }
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(index);
    final SitePage? page = entry.page;
    if (page == null) {
      return false;
    }
    final int previousSelectedIndex = _nav.selectedIndex;
    _mutateSessionState(() {
      _abandonCurrentRequest(
        previousSelectedIndex,
        phase: 'restore-tab-$index',
      );
      _abandonCurrentRequest(index, phase: 'restore-tab-$index');
      _setSelectedPrimaryTabIndex(index);
    });
    if (page is! ReaderPageData) {
      _scrollState.restoreStandardScrollPosition(
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
    if (index == _nav.selectedIndex &&
        _routes.isPrimaryTabContent &&
        !_isLoading) {
      await _scrollState.scrollCurrentStandardPageToTop(
        onUserInteraction: _noteViewportInteraction,
      );
      return;
    }
    if (index == 3) {
      await _loadProfilePage(
        preserveVisiblePage: true,
        historyMode: index == _nav.selectedIndex
            ? NavigationIntent.resetToRoot
            : NavigationIntent.preserve,
      );
      return;
    }
    final bool shouldResetToRoot = index == _nav.selectedIndex;
    final Uri targetUri = _targetUriForPrimaryTab(
      index,
      resetToRoot: shouldResetToRoot,
    );
    if (!shouldResetToRoot &&
        _tabSessionStore.currentEntry(index).page != null) {
      _scrollState.persistVisiblePageState();
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
