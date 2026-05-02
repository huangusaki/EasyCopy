part of '../easy_copy_screen.dart';

extension _EasyCopyScreenStandardMode on _EasyCopyScreenState {
  Widget _buildStandardMode(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('standard-scaffold'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: appDestinations
            .map(
              (AppDestination destination) => NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
      body: SafeArea(child: _buildStandardBody(context)),
    );
  }

  Widget _buildStandardBody(BuildContext context) {
    final List<Widget> children = _buildStandardBodyChildren(context);
    final String contentKey = _standardContentTransitionKey;

    return RefreshIndicator(
      onRefresh: _retryCurrentPage,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleStandardScrollNotification,
        child: ListView.builder(
          controller: _standardScrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: children.length,
          itemBuilder: (BuildContext context, int index) {
            return KeyedSubtree(
              key: ValueKey<String>('$contentKey::$index'),
              child: children[index],
            );
          },
        ),
      ),
    );
  }

  String get _standardContentTransitionKey {
    final String prefix = _errorMessage != null && _page == null
        ? 'error'
        : 'page';
    return '$prefix::$_standardBodyTransitionScope';
  }

  List<Widget> _buildStandardBodyChildren(BuildContext context) {
    if (_errorMessage != null && _page == null) {
      return _buildErrorSections(context);
    }
    return _buildStandardChildren(context);
  }

  List<Widget> _buildStandardChildren(BuildContext context) {
    final List<Widget> children = <Widget>[
      ..._buildStandardTopContent(context),
    ];

    if (_page == null) {
      children.addAll(_buildLoadingSections(context));
      return children;
    }

    final EasyCopyPage page = _page!;
    if (page is HomePageData) {
      children.addAll(_buildHomeSections(page));
    } else if (page is DiscoverPageData) {
      children.addAll(_buildDiscoverSections(page));
    } else if (page is RankPageData) {
      children.addAll(_buildRankSections(page));
    } else if (page is DetailPageData) {
      children.addAll(_buildDetailSections(page));
    } else if (page is ProfilePageData) {
      children.addAll(_buildProfileSections(page));
    } else if (page is UnknownPageData) {
      children.addAll(_buildMessageSections(page.message));
    }

    return children;
  }

  List<Widget> _buildStandardTopContent(BuildContext context) {
    if (_shouldShowDiscoverSearchChrome) {
      return <Widget>[
        _buildDiscoverSearchChrome(context),
        const SizedBox(height: 18),
      ];
    }

    if (_shouldShowHeaderCard) {
      return <Widget>[
        _buildHeaderCard(
          context,
          title: _pageTitle,
          showBackButton: _shouldShowBackButton,
          showSearchBar: _shouldShowSearchBar,
        ),
        const SizedBox(height: 18),
      ];
    }

    return const <Widget>[];
  }

  bool get _shouldShowDiscoverSearchChrome {
    if (_isDetailRoute || _isSecondaryDiscoverRoute) {
      return false;
    }
    if (_selectedIndex != 1 && !_isPrimaryDiscoverUri(_currentUri)) {
      return false;
    }
    final EasyCopyPage? page = _page;
    if (page == null || page is DiscoverPageData) {
      return true;
    }
    return _isPrimaryDiscoverUri(_currentUri);
  }

  Widget _buildDiscoverSearchChrome(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<String> history = _searchHistoryEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (_shouldShowBackButton) ...<Widget>[
              IconButton.filledTonal(
                onPressed: _handleBackNavigation,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.search_rounded, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: _submitSearchFromVisibleDiscoverContext,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: '搜索漫画、作者或题材',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchController.text.trim().isNotEmpty)
                      IconButton(
                        onPressed: _clearVisibleDiscoverSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      onPressed: () => _submitSearchFromVisibleDiscoverContext(
                        _searchController.text,
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                '历史搜索',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.64),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _confirmClearSearchHistory,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: history
                .map(
                  (String term) => GestureDetector(
                    onLongPress: () {
                      unawaited(HapticFeedback.vibrate());
                      unawaited(_removeSearchHistoryEntry(term));
                    },
                    child: ActionChip(
                      label: Text(term),
                      onPressed: () {
                        _primeSearchController(term);
                        _submitSearchFromVisibleDiscoverContext(term);
                      },
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: _submitSearchFromVisibleDiscoverContext,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '搜尋漫畫、作者或題材',
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                _submitSearchFromVisibleDiscoverContext(_searchController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _openDiscoverPagerHref(String href) async {
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    _moveStandardPagerViewportToTop();
    if (_currentEntry.routeKey == AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
    );
  }

  Future<void> _jumpDiscoverToPage(
    DiscoverPageData page,
    int targetPage,
  ) async {
    if (targetPage < 1) {
      _showSnackBar('请输入有效页码');
      return;
    }
    final int? totalPageCount = page.pager.totalPageCount;
    if (totalPageCount != null && targetPage > totalPageCount) {
      _showSnackBar('页码超出范围，最多 $totalPageCount 页');
      return;
    }
    final Uri targetUri = AppConfig.buildDiscoverPagerJumpUri(
      Uri.parse(page.uri),
      pager: page.pager,
      page: targetPage,
    );
    _moveStandardPagerViewportToTop();
    if (_currentEntry.routeKey == AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
    );
  }

  void _moveStandardPagerViewportToTop() {
    _tabSessionStore.updateScroll(_selectedIndex, _currentEntry.routeKey, 0);
    if (_standardScrollController.hasClients) {
      _standardScrollController.jumpTo(0);
    }
  }

  List<Widget> _buildProfileSections(ProfilePageData page) {
    return <Widget>[
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
        onOpenCachedComicPage: () => _openProfileSubview(ProfileSubview.cached),
        onOpenCollectionsPage: (int page) =>
            _openProfileSubview(ProfileSubview.collections, page: page),
        onOpenHistoryPageNumber: (int page) =>
            _openProfileSubview(ProfileSubview.history, page: page),
        currentHost: _hostManager.currentHost,
        knownHosts: _hostManager.knownHosts,
        candidateHosts: _hostManager.candidateHosts,
        candidateHostAliases: _hostManager.candidateHostAliases,
        hostSnapshot: _hostManager.probeSnapshot,
        isRefreshingHosts: _isUpdatingHostSettings,
        onRefreshHosts: _refreshHostSettings,
        onUseAutomaticHostSelection: _useAutomaticHostSelection,
        onSelectHost: _selectHost,
        themePreference: _preferencesController.themePreference,
        onThemePreferenceChanged: (AppThemePreference preference) {
          unawaited(_preferencesController.setThemePreference(preference));
        },
        versionLabel: _appVersionLabel,
        isCheckingForUpdates: _isCheckingForUpdates,
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
                    return ValueListenableBuilder<
                      DownloadStorageMigrationProgress?
                    >(
                      valueListenable:
                          _downloadStorageMigrationProgressNotifier,
                      builder:
                          (
                            BuildContext context,
                            DownloadStorageMigrationProgress? migrationProgress,
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
            migrationProgressListenable:
                _downloadStorageMigrationProgressNotifier,
            cachedComics: _cachedComics,
            onOpenCachedComic: (CachedComicLibraryEntry item) {
              _openCachedComicFromProfile(_cachedComicCardKey(item));
            },
            onDeleteCachedComic: (CachedComicLibraryEntry item) {
              unawaited(_confirmDeleteCachedComic(item));
            },
            supportsCustomDirectorySelection:
                _downloadService.supportsCustomStorageSelection,
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
              unawaited(_confirmRemoveQueuedComicAndCache(task));
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
    return _cachedComics
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
    return _cachedComics.cast<CachedComicLibraryEntry?>().firstWhere(
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
    final DetailPageData localPage = _downloadService.buildCachedDetailPage(
      item,
    );
    final Uri targetUri = Uri.parse(localPage.uri);
    final int targetTabIndex = resolveNavigationTabIndex(
      targetUri,
      sourceTabIndex: _selectedIndex,
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
        _refreshCachedComicDetailInBackground(
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

  Future<void> _refreshCachedComicDetailInBackground(
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
      final EasyCopyPage freshPage = await _pageRepository.loadFresh(
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

  Set<String> _downloadedChapterPathKeysForDetail(DetailPageData page) {
    final Uri currentDetailUri = Uri.parse(page.uri);
    final String targetPath = currentDetailUri.path;
    final CachedComicLibraryEntry? match = _cachedComics
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? item) =>
              item != null && Uri.tryParse(item.comicHref)?.path == targetPath,
          orElse: () => null,
        );
    if (match == null) {
      return const <String>{};
    }
    return match.chapters
        .map(
          (CachedChapterEntry chapter) => _chapterPathKey(chapter.chapterHref),
        )
        .where((String key) => key.isNotEmpty)
        .toSet();
  }

  String _chapterPathKey(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return '';
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  String _lastReadChapterPathKeyForDetail(DetailPageData page) {
    return _readerProgressStore.latestChapterPathKeyForCatalog(page.uri) ?? '';
  }

  List<ChapterPickerSection> _chapterPickerSections(DetailPageData page) {
    final List<ChapterData> allChapters = page.chapters.isNotEmpty
        ? page.chapters
        : page.chapterGroups
              .expand((ChapterGroupData group) => group.chapters)
              .fold<Map<String, ChapterData>>(<String, ChapterData>{}, (
                Map<String, ChapterData> chaptersByKey,
                ChapterData chapter,
              ) {
                final String key = _chapterPathKey(chapter.href);
                if (key.isNotEmpty && !chaptersByKey.containsKey(key)) {
                  chaptersByKey[key] = chapter;
                }
                return chaptersByKey;
              })
              .values
              .toList(growable: false);
    if (allChapters.isEmpty) {
      return const <ChapterPickerSection>[];
    }
    return <ChapterPickerSection>[
      ChapterPickerSection(label: '全部章节', chapters: allChapters),
    ];
  }

  Future<void> _showDetailDownloadPicker(DetailPageData page) async {
    final List<ChapterPickerSection> sections = _chapterPickerSections(page);
    final Set<String> downloadedKeys = _downloadedChapterPathKeysForDetail(
      page,
    );
    final List<ChapterData>?
    selectedChapters = await showModalBottomSheet<List<ChapterData>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        final Set<String> selectedKeys = <String>{};
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            List<ChapterData> selectedChapterValues() {
              return sections
                  .expand((section) => section.chapters)
                  .where(
                    (ChapterData chapter) =>
                        selectedKeys.contains(_chapterPathKey(chapter.href)),
                  )
                  .toList(growable: false);
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '选择要缓存的章节',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedKeys
                                  ..clear()
                                  ..addAll(
                                    sections
                                        .expand((section) => section.chapters)
                                        .map(
                                          (ChapterData chapter) =>
                                              _chapterPathKey(chapter.href),
                                        ),
                                  );
                              });
                            },
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(selectedKeys.clear);
                            },
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          shrinkWrap: true,
                          children: sections
                              .expand((section) {
                                return <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      10,
                                      4,
                                      4,
                                    ),
                                    child: Text(
                                      section.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  ...section.chapters.map((
                                    ChapterData chapter,
                                  ) {
                                    final String key = _chapterPathKey(
                                      chapter.href,
                                    );
                                    final bool isDownloaded = downloadedKeys
                                        .contains(key);
                                    final bool selected = selectedKeys.contains(
                                      key,
                                    );
                                    return CheckboxListTile(
                                      value: selected,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged: (bool? nextValue) {
                                        setModalState(() {
                                          if (nextValue ?? false) {
                                            selectedKeys.add(key);
                                          } else {
                                            selectedKeys.remove(key);
                                          }
                                        });
                                      },
                                      secondary: isDownloaded
                                          ? const Icon(
                                              Icons.check_circle_rounded,
                                              color: Color(0xFF18A558),
                                            )
                                          : null,
                                      title: Text(chapter.label),
                                    );
                                  }),
                                ];
                              })
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedKeys.isEmpty
                              ? null
                              : () {
                                  Navigator.of(
                                    context,
                                  ).pop(selectedChapterValues());
                                },
                          child: Text(
                            selectedKeys.isEmpty
                                ? '请选择章节'
                                : '缓存 ${selectedKeys.length} 话',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedChapters == null || selectedChapters.isEmpty || !mounted) {
      return;
    }
    await _enqueueSelectedChapters(page, selectedChapters);
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String title,
    required bool showBackButton,
    required bool showSearchBar,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showBackButton)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: IconButton.filledTonal(
                    onPressed: _handleBackNavigation,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerLow,
                      foregroundColor: colorScheme.onSurface,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _retryCurrentPage,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerLow,
                  foregroundColor: colorScheme.primary,
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (showSearchBar) ...<Widget>[
            const SizedBox(height: 14),
            _buildSearchField(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildLoadingSections(BuildContext context) {
    return <Widget>[_buildLoadingIndicator(context)];
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double height = MediaQuery.sizeOf(context).height * 0.52;
    return SizedBox(
      height: height.clamp(260, 480),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '加载中……',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.88),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildErrorSections(BuildContext context) {
    return <Widget>[
      ..._buildStandardTopContent(context),
      AppSurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            const Text(
              '内容整理失败',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(_errorMessage ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              _currentUri.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _loadHome,
                    child: const Text('回到首頁'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _retryCurrentPage,
                    child: const Text('重新整理'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildInlineSectionLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: const LinearProgressIndicator(minHeight: 6),
      ),
    );
  }

  Widget _buildAnimatedSectionContent({
    required String contentKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: _pageFadeTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: _buildFadeSwitchTransition,
      child: KeyedSubtree(key: ValueKey<String>(contentKey), child: child),
    );
  }

  String _discoverListContentKey(DiscoverPageData page) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      page.pager.currentLabel,
      '${page.items.length}',
      page.items.isEmpty ? '' : page.items.first.href,
      page.items.isEmpty ? '' : page.items.last.href,
    ].join('::');
  }

  String _rankListContentKey(RankPageData page) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      '${page.items.length}',
      page.items.isEmpty ? '' : page.items.first.href,
      page.items.isEmpty ? '' : page.items.last.href,
    ].join('::');
  }

  List<Widget> _buildHomeSections(HomePageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.feature != null) {
      sections.add(
        FeatureBannerCard(
          banner: page.feature!,
          onTap: () =>
              _navigateToHref(AppConfig.resolvePath('/topic').toString()),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    for (final ComicSectionData section in page.sections) {
      sections.add(
        SurfaceBlock(
          title: section.title,
          actionLabel: section.href.isNotEmpty ? '更多' : null,
          onActionTap: section.href.isNotEmpty
              ? () {
                  unawaited(_openHomeSectionHref(section.href));
                }
              : null,
          child: ComicGrid(items: section.items, onTap: _navigateToHref),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    return sections;
  }

  Future<void> _openHomeSectionHref(String href) async {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    await _loadUri(
      targetUri,
      sourceTabIndex: _selectedIndex,
      targetTabIndexOverride: _selectedIndex,
      historyMode: NavigationIntent.push,
    );
  }

  List<Widget> _buildDiscoverSections(DiscoverPageData page) {
    if (_isTopicListUri(_currentUri)) {
      return _buildTopicListSections(page);
    }

    final List<Widget> sections = <Widget>[];
    final bool hasPager =
        page.pager.hasPrev ||
        page.pager.hasNext ||
        page.pager.currentLabel.isNotEmpty ||
        page.pager.totalLabel.isNotEmpty;

    if (page.filters.isNotEmpty) {
      final FilterGroupData primaryGroup = page.filters.first;
      final List<LinkAction> themeOptions = primaryGroup.options
          .where((LinkAction option) => !_isDiscoverMoreCategoryOption(option))
          .toList(growable: false);
      final List<FilterGroupData> secondaryGroups = page.filters
          .skip(1)
          .toList(growable: false);

      sections.add(
        SurfaceBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FilterGroup(
                group: FilterGroupData(
                  label: primaryGroup.label,
                  options: _visibleDiscoverThemeOptions(themeOptions),
                ),
                onTap: _navigateDiscoverFilter,
                actionLabel: _isDiscoverThemeExpanded ? '收起' : '全部',
                actionExpanded: _isDiscoverThemeExpanded,
                onActionTap: () {
                  _setStateIfMounted(() {
                    _isDiscoverThemeExpanded = !_isDiscoverThemeExpanded;
                  });
                },
              ),
              if (secondaryGroups.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Builder(
                  builder: (BuildContext context) {
                    return Container(
                      height: 1,
                      color: Theme.of(context).dividerColor,
                    );
                  },
                ),
                const SizedBox(height: 18),
                ...secondaryGroups.map(
                  (FilterGroupData group) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilterGroup(
                      group: group,
                      onTap: _navigateDiscoverFilter,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      SurfaceBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_isLoading) _buildInlineSectionLoadingIndicator(),
            _buildAnimatedSectionContent(
              contentKey: _discoverListContentKey(page),
              child: ComicGrid(items: page.items, onTap: _navigateToHref),
            ),
          ],
        ),
      ),
    );
    if (hasPager) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        IgnorePointer(
          ignoring: _isLoading,
          child: Opacity(
            opacity: _isLoading ? 0.72 : 1,
            child: PagerCard(
              pager: page.pager,
              onPrev: page.pager.hasPrev
                  ? () {
                      unawaited(_openDiscoverPagerHref(page.pager.prevHref));
                    }
                  : null,
              onNext: page.pager.hasNext
                  ? () {
                      unawaited(_openDiscoverPagerHref(page.pager.nextHref));
                    }
                  : null,
              onJumpToPage: (int targetPage) {
                unawaited(_jumpDiscoverToPage(page, targetPage));
              },
            ),
          ),
        ),
      );
    }

    return sections;
  }

  List<Widget> _buildTopicListSections(DiscoverPageData page) {
    final List<Widget> sections = <Widget>[];
    final bool hasPager =
        page.pager.hasPrev ||
        page.pager.hasNext ||
        page.pager.currentLabel.isNotEmpty ||
        page.pager.totalLabel.isNotEmpty;

    if (_isLoading) {
      sections.add(_buildInlineSectionLoadingIndicator());
      sections.add(const SizedBox(height: 14));
    }

    sections.add(
      _buildAnimatedSectionContent(
        contentKey: _discoverListContentKey(page),
        child: TopicIssueList(items: page.items, onTap: _navigateToHref),
      ),
    );

    if (hasPager) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        IgnorePointer(
          ignoring: _isLoading,
          child: Opacity(
            opacity: _isLoading ? 0.72 : 1,
            child: PagerCard(
              pager: page.pager,
              onPrev: page.pager.hasPrev
                  ? () => _navigateToHref(page.pager.prevHref)
                  : null,
              onNext: page.pager.hasNext
                  ? () => _navigateToHref(page.pager.nextHref)
                  : null,
              onJumpToPage: (int value) {
                unawaited(_jumpDiscoverToPage(page, value));
              },
            ),
          ),
        ),
      );
    }

    return sections;
  }

  List<Widget> _buildRankSections(RankPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.categories.isNotEmpty || page.periods.isNotEmpty) {
      sections.add(
        SurfaceBlock(
          title: '榜單切換',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (page.categories.isNotEmpty)
                RankFilterGroup(
                  label: '榜單類型',
                  items: page.categories,
                  onTap: _navigateRankFilter,
                ),
              if (page.categories.isNotEmpty && page.periods.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Builder(
                    builder: (BuildContext context) {
                      return Container(
                        height: 1,
                        color: Theme.of(context).dividerColor,
                      );
                    },
                  ),
                ),
              if (page.periods.isNotEmpty)
                RankFilterGroup(
                  label: '統計週期',
                  items: page.periods,
                  onTap: _navigateRankFilter,
                ),
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      SurfaceBlock(
        title: '榜单列表',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_isLoading) _buildInlineSectionLoadingIndicator(),
            _buildAnimatedSectionContent(
              contentKey: _rankListContentKey(page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: page.items
                    .map(
                      (RankEntryData item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RankCard(
                          item: item,
                          onTap: () => _navigateToHref(item.href),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildDetailSections(DetailPageData page) {
    final Set<String> downloadedChapterKeys =
        _downloadedChapterPathKeysForDetail(page);
    final String lastReadChapterPathKey = _lastReadChapterPathKeyForDetail(
      page,
    );
    final List<DetailChapterTabData> chapterTabs = _detailChapterTabs(page);
    final DetailChapterTabData? activeChapterTab = _activeDetailChapterTab(
      page,
    );
    final List<ChapterData> visibleChapters = _visibleDetailChapters(page);
    _scheduleDetailChapterAutoPosition(
      page,
      visibleChapters,
      lastReadChapterPathKey,
    );
    final List<Widget> sections = <Widget>[
      DetailHeroCard(
        page: page,
        onReadNow: page.startReadingHref.isNotEmpty
            ? () => _openDetailChapter(page, page.startReadingHref)
            : null,
        onDownload: () => _showDetailDownloadPicker(page),
        onToggleCollection: page.comicId.trim().isEmpty
            ? null
            : () => unawaited(_toggleDetailCollection(page)),
        isCollectionBusy: _isUpdatingCollection,
        onTagTap: _submitSearchFromCurrentStack,
        onAuthorTap: _navigateToHref,
      ),
      const SizedBox(height: 18),
    ];

    if (page.summary.isNotEmpty) {
      sections.add(
        SurfaceBlock(
          title: '內容簡介',
          child: Text(page.summary, style: const TextStyle(height: 1.7)),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> infoChips = <Widget>[
      if (page.authors.isNotEmpty) InfoChip(label: '作者', value: page.authors),
      if (page.status.isNotEmpty) InfoChip(label: '狀態', value: page.status),
      if (page.updatedAt.isNotEmpty)
        InfoChip(label: '更新', value: page.updatedAt),
      if (page.heat.isNotEmpty) InfoChip(label: '熱度', value: page.heat),
      if (page.aliases.isNotEmpty) InfoChip(label: '別名', value: page.aliases),
    ];
    if (infoChips.isNotEmpty) {
      sections.add(
        SurfaceBlock(
          title: '作品信息',
          child: Wrap(spacing: 10, runSpacing: 10, children: infoChips),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      SurfaceBlock(
        title: '章節目錄',
        actionLabel: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? '选择下载'
            : null,
        onActionTap: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? () => _showDetailDownloadPicker(page)
            : null,
        child: chapterTabs.isEmpty
            ? const Text('章節還在整理中，向下刷新可重試。')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DetailChapterToolbar(
                    tabs: chapterTabs,
                    selectedKey: activeChapterTab?.key,
                    isAscending: _isDetailChapterSortAscending,
                    onSelectTab: _selectDetailChapterTab,
                    onToggleSort: visibleChapters.length > 1
                        ? _toggleDetailChapterSortOrder
                        : null,
                  ),
                  const SizedBox(height: 14),
                  if (visibleChapters.isEmpty)
                    const Text('這個分組暫時沒有章節。')
                  else
                    _buildAnimatedSectionContent(
                      contentKey: _detailChapterContentKey(
                        page,
                        activeChapterTab,
                        visibleChapters,
                      ),
                      child: ChapterGrid(
                        chapters: visibleChapters,
                        onTap: (String href) => _openDetailChapter(page, href),
                        downloadedChapterPathKeys: downloadedChapterKeys,
                        lastReadChapterPathKey: lastReadChapterPathKey,
                        itemKeyBuilder: _detailChapterItemKeyFor,
                      ),
                    ),
                ],
              ),
      ),
    );

    return sections;
  }

  List<Widget> _buildMessageSections(String message) {
    return <Widget>[
      AppSurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            const Icon(Icons.layers_clear_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _loadHome, child: const Text('回到首頁')),
          ],
        ),
      ),
    ];
  }
}
