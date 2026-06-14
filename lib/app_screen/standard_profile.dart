part of '../app_screen.dart';

extension _AppScreenProfileSections on _AppScreenState {
  List<Widget> _buildProfileSections(ProfilePageData page) {
    return <Widget>[
      _hPaddedBox(
        ProfilePageView(
          page: page,
          onAuthenticate: _openAuthFlow,
          onLogout: _logout,
          onOpenComic: _navigateToHref,
          onOpenHistory: (ProfileHistoryItem item) {
            final String targetHref = item.chapterHref.isNotEmpty
                ? item.chapterHref
                : item.comicHref;
            _navigateToHref(targetHref);
          },
          onOpenCollections: () =>
              _openProfileSubview(ProfileSubview.collections),
          onOpenHistoryPage: () => _openProfileSubview(ProfileSubview.history),
          onOpenCachedComicPage: () =>
              _openProfileSubview(ProfileSubview.cached),
          onOpenCollectionsPage: (int page) =>
              _openProfileSubview(ProfileSubview.collections, page: page),
          onOpenHistoryPageNumber: (int page) =>
              _openProfileSubview(ProfileSubview.history, page: page),
          isCollectionLoading:
              _isLoading &&
              AppConfig.profileSubviewForUri(_currentUri) ==
                  ProfileSubview.collections,
          currentHost: _services.hostManager.currentHost,
          knownHosts: _services.hostManager.knownHosts,
          candidateHosts: _services.hostManager.candidateHosts,
          candidateHostAliases: _services.hostManager.candidateHostAliases,
          hostSnapshot: _services.hostManager.probeSnapshot,
          isRefreshingHosts: _shell.isUpdatingHostSettings,
          onRefreshHosts: _refreshHostSettings,
          onUseAutomaticHostSelection: _useAutomaticHostSelection,
          onSelectHost: _selectHost,
          themePreference: _preferencesController.themePreference,
          onThemePreferenceChanged: (AppThemePreference preference) {
            unawaited(_preferencesController.setThemePreference(preference));
          },
          wallpaperPreferences: _preferencesController.wallpaperPreferences,
          wallpaperActions: buildWallpaperActions(
            preferencesController: _preferencesController,
            showError: (String message) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
            },
          ),
          versionLabel: _appVersionLabel,
          isCheckingForUpdates: _shell.isCheckingForUpdates,
          onCheckForUpdates: () {
            unawaited(_checkForUpdates());
          },
          onOpenProjectRepository: () {
            unawaited(_openProjectRepository());
          },
          afterContinueReading: _buildDownloadManagementEntry(),
          cachedComicCards: _cachedComicCardsForProfile(),
          activeSubview: AppConfig.profileSubviewForUri(_currentUri),
          onOpenCachedComic: _openCachedComicFromProfile,
          onDeleteCachedComic: _deleteCachedComicFromProfile,
          onDeleteHistory: _deleteLocalHistoryFromProfile,
        ),
      ),
    ];
  }

  Widget _buildDownloadManagementEntry() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder:
          (
            BuildContext context,
            DownloadQueueSnapshot queueSnapshot,
            Widget? _,
          ) {
            return ValueListenableBuilder<DownloadStorageState>(
              valueListenable: _downloadStorageStateNotifier,
              builder:
                  (
                    BuildContext context,
                    DownloadStorageState storageStateValue,
                    Widget? _,
                  ) {
                    final String statusLabel = queueSnapshot.isEmpty
                        ? '空闲'
                        : queueSnapshot.isPaused
                        ? '已暂停'
                        : '缓存中';
                    final String queueLabel = queueSnapshot.isEmpty
                        ? '0 话'
                        : '${queueSnapshot.remainingCount} 话';
                    return ValueListenableBuilder<StorageMigrationProgress?>(
                      valueListenable: _storageMigrationProgress,
                      builder:
                          (
                            BuildContext context,
                            StorageMigrationProgress? migrationProgress,
                            Widget? _,
                          ) {
                            return DownloadManagementEntryCard(
                              statusLabel: migrationProgress != null
                                  ? '迁移中'
                                  : statusLabel,
                              queueLabel: queueLabel,
                              noteLabel:
                                  migrationProgress?.message ??
                                  (storageStateValue.errorMessage.isNotEmpty
                                      ? '目录异常：${storageStateValue.errorMessage}'
                                      : storageStateValue.isLoading
                                      ? '正在读取缓存目录…'
                                      : null),
                              onTap: _openDownloadManagementPage,
                            );
                          },
                    );
                  },
            );
          },
    );
  }

  void _openDownloadManagementPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return DownloadManagementPage(
            queueListenable: _downloadQueueSnapshotNotifier,
            storageStateListenable: _downloadStorageStateNotifier,
            storageBusyListenable: _downloadStorageBusyNotifier,
            migrationProgressListenable: _storageMigrationProgress,
            cachedComics: _library.cachedComics,
            onOpenCachedComic: (CachedComicLibraryEntry item) {
              _openCachedComicFromProfile(_cachedComicCardKey(item));
            },
            onDeleteCachedComic: (CachedComicLibraryEntry item) {
              unawaited(_confirmDeleteCachedComic(item));
            },
            supportsCustomDirs:
                _services.downloadService.supportsCustomStorageSelection,
            onPauseQueue: () {
              unawaited(_pauseDownloadQueue());
            },
            onResumeQueue: () {
              unawaited(_resumeDownloadQueue());
            },
            onClearQueue: () {
              unawaited(_confirmClearDownloadQueue());
            },
            onStopComicTasks: (DownloadQueueTask task) {
              unawaited(_confirmRemoveQueuedComic(task));
            },
            onRemoveComic: (DownloadQueueTask task) {
              unawaited(_confirmRemoveComicCache(task));
            },
            onRemoveTask: (DownloadQueueTask task) {
              unawaited(_confirmRemoveQueuedTask(task));
            },
            onRetryTask: (DownloadQueueTask task) {
              unawaited(_retryDownloadQueueTask(task));
            },
            onPickStorageDirectory: () {
              unawaited(_pickDownloadStorageDirectory());
            },
            onResetStorageDirectory: () {
              unawaited(_resetDownloadStorageDirectory());
            },
            onRescanStorageDirectory: _rescanCurrentDownloadStorage,
          );
        },
      ),
    );
  }

  List<ComicCardData> _cachedComicCardsForProfile() {
    return _library.cachedComics
        .map((CachedComicLibraryEntry item) {
          final String latestChapterTitle = item.chapters.isEmpty
              ? ''
              : item.chapters.first.chapterTitle;
          return ComicCardData(
            title: item.comicTitle,
            subtitle: '${item.cachedChapterCount}话',
            secondaryText: latestChapterTitle.isEmpty
                ? ''
                : '最近缓存：$latestChapterTitle',
            coverUrl: item.coverUrl,
            href: _cachedComicCardKey(item),
          );
        })
        .toList(growable: false);
  }

  String _cachedComicCardKey(CachedComicLibraryEntry item) {
    if (item.comicHref.isNotEmpty) {
      return item.comicHref;
    }
    return 'cache-title:${item.comicTitle}';
  }

  CachedComicLibraryEntry? _cachedComicByCardKey(String key) {
    return _library.cachedComics.cast<CachedComicLibraryEntry?>().firstWhere(
      (CachedComicLibraryEntry? item) =>
          item != null && _cachedComicCardKey(item) == key,
      orElse: () => null,
    );
  }

  void _openCachedComicFromProfile(String key) {
    final CachedComicLibraryEntry? item = _cachedComicByCardKey(key);
    if (item == null) {
      return;
    }
    final DetailPageData localPage = _services.downloadService
        .buildCachedDetailPage(item);
    final Uri targetUri = Uri.parse(localPage.uri);
    final int targetTabIndex = resolveNavigationTabIndex(
      targetUri,
      sourceTabIndex: _nav.selectedIndex,
    );
    final NavigationRequestContext requestContext = _prepareRouteEntry(
      targetUri,
      targetTabIndex: targetTabIndex,
      intent: NavigationIntent.push,
      preserveVisiblePage: false,
      sourceKind: NavigationRequestSourceKind.navigation,
    );
    _applyLoadedPage(
      localPage,
      requestContext: requestContext,
      switchToTab: _shouldActivateAsyncResultTab(requestContext.targetTabIndex),
    );
    if (item.comicHref.trim().isNotEmpty) {
      unawaited(
        _refreshCachedComicDetail(
          item,
          targetTabIndex: targetTabIndex,
          routeKey: AppConfig.routeKeyForUri(targetUri),
        ),
      );
    }
  }

  void _deleteCachedComicFromProfile(String key) {
    final CachedComicLibraryEntry? item = _cachedComicByCardKey(key);
    if (item == null) {
      return;
    }
    unawaited(_confirmDeleteCachedComic(item));
  }

  void _deleteLocalHistoryFromProfile(String comicHref) {
    unawaited(_confirmDeleteLocalHistory(comicHref));
  }

  Future<void> _confirmDeleteLocalHistory(String comicHref) async {
    final String normalizedHref = comicHref.trim();
    if (normalizedHref.isEmpty) {
      return;
    }
    final SitePage? currentPageData = _page;
    final ProfilePageData? profilePage = currentPageData is ProfilePageData
        ? currentPageData
        : null;
    if (profilePage == null ||
        profilePage.isLoggedIn ||
        _services.session.isAuthenticated) {
      _showNotice('登录账号的浏览历史暂不支持删除');
      return;
    }
    ProfileHistoryItem? targetItem;
    for (final ProfileHistoryItem item in profilePage.history) {
      if (item.comicHref.trim() == normalizedHref) {
        targetItem = item;
        break;
      }
    }
    final String title = targetItem?.title.trim() ?? '';
    if (!await _confirmDialog(
      title: '删除浏览记录',
      content: title.isEmpty ? '确认删除这条浏览记录吗？' : '确认删除《$title》的浏览记录吗？',
      confirmLabel: '删除',
    )) {
      return;
    }

    try {
      await _services.localLibraryStore.removeHistory(
        LocalLibraryStore.guestScope,
        normalizedHref,
      );
      if (!mounted) {
        return;
      }
      _showNotice('已删除浏览记录');
      final ProfileSubview activeSubview = AppConfig.profileSubviewForUri(
        _currentUri,
      );
      final int activePage = AppConfig.profilePageForUri(_currentUri);
      final bool shouldStepBack =
          activeSubview == ProfileSubview.history &&
          activePage > 1 &&
          profilePage.history.length <= 1;
      final Uri targetUri = shouldStepBack
          ? AppConfig.buildProfileUri(
              view: ProfileSubview.history,
              page: activePage - 1,
            )
          : _currentUri;
      await _loadProfilePage(
        targetUri: targetUri,
        forceRefresh: true,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      );
    } catch (_) {
      if (mounted) {
        _showNotice('删除失败，请稍后重试');
      }
    }
  }

  Future<void> _refreshCachedComicDetail(
    CachedComicLibraryEntry item, {
    required int targetTabIndex,
    required String routeKey,
  }) async {
    final String href = item.comicHref.trim();
    if (href.isEmpty) {
      return;
    }
    try {
      final Uri targetUri = AppConfig.rewriteToCurrentHost(Uri.parse(href));
      final SitePage freshPage = await _pageRepository.loadFresh(
        targetUri,
        authScope: _pageQueryKeyForUri(targetUri).authScope,
      );
      if (!mounted || freshPage is! DetailPageData) {
        return;
      }
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        targetTabIndex,
      );
      if (entry.routeKey != routeKey) {
        return;
      }
      _applyLoadedPage(
        freshPage,
        targetTabIndex: targetTabIndex,
        switchToTab: false,
      );
    } catch (_) {
      return;
    }
  }
}
