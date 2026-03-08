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
    return RefreshIndicator(
      onRefresh: _retryCurrentPage,
      child: ListView(
        controller: _standardScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          KeyedSubtree(
            key: ValueKey<String>(_standardContentTransitionKey),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildStandardBodyChildren(context),
            ),
          ),
        ],
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
      _buildDownloadQueueBanner(),
    ];

    if (_page == null) {
      children.addAll(_buildLoadingSections(context));
      return children;
    }

    final EasyCopyPage page = _page!;
    switch (page) {
      case HomePageData homePage:
        children.addAll(_buildHomeSections(homePage));
      case DiscoverPageData discoverPage:
        children.addAll(_buildDiscoverSections(discoverPage));
      case RankPageData rankPage:
        children.addAll(_buildRankSections(rankPage));
      case DetailPageData detailPage:
        children.addAll(_buildDetailSections(detailPage));
      case ProfilePageData profilePage:
        children.addAll(_buildProfileSections(profilePage));
      case UnknownPageData unknownPage:
        children.addAll(_buildMessageSections(unknownPage.message));
      case ReaderPageData _:
        break;
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
    if (_selectedIndex != 1 || _isDetailRoute) {
      return false;
    }
    final EasyCopyPage? page = _page;
    if (page == null || page is DiscoverPageData) {
      return true;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/comics') || path.startsWith('/search');
  }

  Widget _buildDiscoverSearchChrome(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
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
                    onSubmitted: _submitSearch,
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
                    onPressed: () {
                      if (_currentUri.path == '/search') {
                        _searchController.clear();
                        unawaited(
                          _loadUri(
                            AppConfig.resolvePath('/comics'),
                            historyMode: NavigationIntent.preserve,
                          ),
                        );
                        return;
                      }
                      _setStateIfMounted(_searchController.clear);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton(
                  onPressed: () => _submitSearch(_searchController.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
        ),
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
              onSubmitted: _submitSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '搜尋漫畫、作者或題材',
              ),
            ),
          ),
          IconButton(
            onPressed: () => _submitSearch(_searchController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadQueueBanner() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder: (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
        if (snapshot.isEmpty || (_selectedIndex == 3 && _isPrimaryTabContent)) {
          return const SizedBox.shrink();
        }

        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final DownloadQueueTask activeTask = snapshot.activeTask!;
        final bool isPaused = snapshot.isPaused;
        final String statusLabel = isPaused
            ? (activeTask.progressLabel.isEmpty
                  ? '后台缓存已暂停'
                  : activeTask.progressLabel)
            : activeTask.progressLabel;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Material(
            color: isPaused
                ? colorScheme.secondaryContainer.withValues(alpha: 0.52)
                : colorScheme.primaryContainer.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        isPaused
                            ? Icons.pause_circle_rounded
                            : Icons.download_for_offline_rounded,
                        color: isPaused
                            ? colorScheme.secondary
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${activeTask.comicTitle} · 剩余 ${snapshot.remainingCount} 话',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: isPaused
                            ? _resumeDownloadQueue
                            : _pauseDownloadQueue,
                        child: Text(isPaused ? '继续' : '暂停'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: activeTask.fraction > 0 ? activeTask.fraction : null,
                    borderRadius: BorderRadius.circular(999),
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDiscoverPagerHref(String href) async {
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
    );
    if (!mounted ||
        _currentEntry.routeKey != AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _scrollCurrentStandardPageToTop();
  }

  Widget _buildDownloadQueueSection() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder:
          (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
            if (snapshot.isEmpty) {
              return const SizedBox.shrink();
            }

            final Map<String, List<DownloadQueueTask>> groupedTasks =
                <String, List<DownloadQueueTask>>{};
            for (final DownloadQueueTask task in snapshot.tasks) {
              groupedTasks
                  .putIfAbsent(task.comicKey, () => <DownloadQueueTask>[])
                  .add(task);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _SurfaceBlock(
                title: '缓存任务',
                actionLabel: snapshot.isPaused ? '继续' : '暂停',
                onActionTap: snapshot.isPaused
                    ? _resumeDownloadQueue
                    : _pauseDownloadQueue,
                child: Column(
                  children: groupedTasks.entries
                      .map((MapEntry<String, List<DownloadQueueTask>> entry) {
                        final List<DownloadQueueTask> tasks = entry.value;
                        final DownloadQueueTask displayTask = tasks.first;
                        final bool isActiveComic =
                            snapshot.activeTask?.comicKey ==
                            displayTask.comicKey;
                        final DownloadQueueTask taskForStatus = isActiveComic
                            ? snapshot.activeTask!
                            : displayTask;
                        final String subtitle = isActiveComic
                            ? taskForStatus.progressLabel
                            : '等待缓存 ${tasks.length} 话';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                8,
                                8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isActiveComic
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                foregroundColor: Colors.white,
                                child: Text('${tasks.length}'),
                              ),
                              title: Text(
                                displayTask.comicTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: IconButton(
                                onPressed: () =>
                                    _confirmRemoveQueuedComic(displayTask),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            );
          },
    );
  }

  List<Widget> _buildProfileSections(ProfilePageData page) {
    final List<Widget> sections = <Widget>[
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
        currentHost: _hostManager.currentHost,
        candidateHosts: _hostManager.candidateHosts,
        hostSnapshot: _hostManager.probeSnapshot,
        isRefreshingHosts: _isUpdatingHostSettings,
        onRefreshHosts: () {
          unawaited(_refreshHostSettings());
        },
        onUseAutomaticHostSelection: () {
          unawaited(_useAutomaticHostSelection());
        },
        onSelectHost: (String host) {
          unawaited(_selectHost(host));
        },
        themePreference: _preferencesController.themePreference,
        onThemePreferenceChanged: (AppThemePreference preference) {
          unawaited(_preferencesController.setThemePreference(preference));
        },
        afterContinueReading: _buildCachedComicsSection(),
      ),
    ];

    sections.add(const SizedBox(height: 18));
    sections.add(_buildDownloadQueueSection());
    return sections;
  }

  Widget _buildCachedComicsSection() {
    if (_isLoadingCachedComics) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: Row(
          children: const <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在读取本地缓存…'),
          ],
        ),
      );
    }

    if (_cachedComics.isEmpty) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: const Text('还没有缓存章节，去漫画详情页挑几话下载吧。'),
      );
    }

    return _SurfaceBlock(
      title: '已缓存漫画',
      child: SizedBox(
        height: 218,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _cachedComics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (BuildContext context, int index) {
            final CachedComicLibraryEntry item = _cachedComics[index];
            return SizedBox(
              width: 144,
              child: _CachedComicCard(
                item: item,
                onTap: item.comicHref.isEmpty
                    ? null
                    : () => _navigateToHref(item.comicHref),
                onDelete: () => _confirmDeleteCachedComic(item),
              ),
            );
          },
        ),
      ),
    );
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

  List<_ChapterPickerSection> _chapterPickerSections(DetailPageData page) {
    if (page.chapterGroups.isNotEmpty) {
      final List<_ChapterPickerSection> sections = page.chapterGroups
          .where((ChapterGroupData group) => group.chapters.isNotEmpty)
          .map(
            (ChapterGroupData group) => _ChapterPickerSection(
              label: group.label,
              chapters: group.chapters,
            ),
          )
          .toList(growable: false);
      if (sections.isNotEmpty) {
        return sections;
      }
    }
    return <_ChapterPickerSection>[
      _ChapterPickerSection(label: '全部章节', chapters: page.chapters),
    ];
  }

  Future<void> _showDetailDownloadPicker(DetailPageData page) async {
    final List<_ChapterPickerSection> sections = _chapterPickerSections(page);
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
              '正在整理可读内容',
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
      _buildDownloadQueueBanner(),
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

  void _syncDetailChapterState(DetailPageData page, {bool forceReset = false}) {
    final String routeKey = AppConfig.routeKeyForUri(Uri.parse(page.uri));
    final List<_DetailChapterTabData> tabs = _detailChapterTabs(page);
    _DetailChapterTabData? fallbackTab;
    for (final _DetailChapterTabData tab in tabs) {
      if (tab.enabled) {
        fallbackTab = tab;
        break;
      }
    }
    fallbackTab ??= tabs.isEmpty ? null : tabs.first;
    final String? preferredTabKey = _preferredDetailChapterTabKey(page);
    if (forceReset || _detailChapterStateRouteKey != routeKey) {
      _detailChapterStateRouteKey = routeKey;
      _detailChapterItemKeys.clear();
      _handledDetailAutoScrollSignature = '';
      _selectedDetailChapterTabKey =
          preferredTabKey ?? fallbackTab?.key ?? _detailAllChapterTabKey;
      _isDetailChapterSortAscending = false;
      return;
    }
    if (!tabs.any(
      (_DetailChapterTabData tab) =>
          tab.key == _selectedDetailChapterTabKey && tab.enabled,
    )) {
      _selectedDetailChapterTabKey =
          fallbackTab?.key ?? _detailAllChapterTabKey;
    }
  }

  List<_DetailChapterTabData> _detailChapterTabs(DetailPageData page) {
    final List<ChapterData> allChapters = _detailChapterList(page);
    if (page.chapterGroups.isNotEmpty) {
      final bool hasAllGroup = page.chapterGroups.any(
        (ChapterGroupData group) => _isAllDetailChapterGroupLabel(group.label),
      );
      final List<_DetailChapterTabData> tabs = <_DetailChapterTabData>[
        if (!hasAllGroup && allChapters.isNotEmpty)
          _DetailChapterTabData(
            key: _detailAllChapterTabKey,
            label: '全部',
            chapters: allChapters,
          ),
        for (int index = 0; index < page.chapterGroups.length; index += 1)
          _DetailChapterTabData(
            key: 'group:$index',
            label: _detailChapterTabLabel(page.chapterGroups[index].label),
            chapters:
                _isAllDetailChapterGroupLabel(
                      page.chapterGroups[index].label,
                    ) &&
                    page.chapterGroups[index].chapters.isEmpty &&
                    allChapters.isNotEmpty
                ? allChapters
                : page.chapterGroups[index].chapters,
          ),
      ];
      if (tabs.isNotEmpty) {
        return tabs;
      }
    }
    if (allChapters.isEmpty) {
      return const <_DetailChapterTabData>[];
    }
    return <_DetailChapterTabData>[
      _DetailChapterTabData(
        key: _detailAllChapterTabKey,
        label: '全部',
        chapters: allChapters,
      ),
    ];
  }

  bool _isAllDetailChapterGroupLabel(String label) {
    final String normalized = label.replaceAll(RegExp(r'\s+'), '');
    return normalized.isNotEmpty &&
        (normalized == '全部' || normalized.contains('全部'));
  }

  String _detailChapterTabLabel(String label) {
    final String normalized = label.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return '列表';
    }
    if (_isAllDetailChapterGroupLabel(normalized)) {
      return '全部';
    }
    if (normalized.contains('番外')) {
      return '番外';
    }
    if (normalized.contains('單話') ||
        normalized.contains('单话') ||
        normalized == '話' ||
        normalized.endsWith('話')) {
      return '話';
    }
    if (normalized.contains('卷')) {
      return '卷';
    }
    return label.trim();
  }

  _DetailChapterTabData? _activeDetailChapterTab(DetailPageData page) {
    final List<_DetailChapterTabData> tabs = _detailChapterTabs(page);
    if (tabs.isEmpty) {
      return null;
    }
    for (final _DetailChapterTabData tab in tabs) {
      if (tab.key == _selectedDetailChapterTabKey && tab.enabled) {
        return tab;
      }
    }
    for (final _DetailChapterTabData tab in tabs) {
      if (tab.enabled) {
        return tab;
      }
    }
    return tabs.first;
  }

  List<ChapterData> _visibleDetailChapters(DetailPageData page) {
    final _DetailChapterTabData? activeTab = _activeDetailChapterTab(page);
    if (activeTab == null || activeTab.chapters.isEmpty) {
      return const <ChapterData>[];
    }
    if (!_isDetailChapterSortAscending) {
      return activeTab.chapters;
    }
    return activeTab.chapters.reversed.toList(growable: false);
  }

  String? _preferredDetailChapterTabKey(DetailPageData page) {
    final String lastReadChapterPathKey = _lastReadChapterPathKeyForDetail(
      page,
    );
    if (lastReadChapterPathKey.isEmpty) {
      return null;
    }
    for (final _DetailChapterTabData tab in _detailChapterTabs(page)) {
      if (!tab.enabled) {
        continue;
      }
      if (tab.chapters.any(
        (ChapterData chapter) =>
            _chapterPathKey(chapter.href) == lastReadChapterPathKey,
      )) {
        return tab.key;
      }
    }
    return null;
  }

  String _detailChapterContentKey(
    DetailPageData page,
    _DetailChapterTabData? activeTab,
    List<ChapterData> chapters,
  ) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      activeTab?.key ?? 'empty',
      _isDetailChapterSortAscending ? 'asc' : 'desc',
      '${chapters.length}',
      chapters.isEmpty ? '' : chapters.first.href,
      chapters.isEmpty ? '' : chapters.last.href,
    ].join('::');
  }

  void _selectDetailChapterTab(String key) {
    if (!mounted || _selectedDetailChapterTabKey == key) {
      return;
    }
    _setStateIfMounted(() {
      _selectedDetailChapterTabKey = key;
    });
  }

  void _toggleDetailChapterSortOrder() {
    if (!mounted) {
      return;
    }
    _setStateIfMounted(() {
      _isDetailChapterSortAscending = !_isDetailChapterSortAscending;
    });
  }

  GlobalKey _detailChapterItemKeyFor(String chapterPathKey) {
    return _detailChapterItemKeys.putIfAbsent(chapterPathKey, GlobalKey.new);
  }

  void _scheduleDetailChapterAutoPosition(
    DetailPageData page,
    List<ChapterData> visibleChapters,
    String lastReadChapterPathKey,
  ) {
    if (lastReadChapterPathKey.isEmpty) {
      return;
    }
    final bool hasVisibleLastRead = visibleChapters.any(
      (ChapterData chapter) =>
          _chapterPathKey(chapter.href) == lastReadChapterPathKey,
    );
    if (!hasVisibleLastRead) {
      return;
    }
    final String signature =
        '${AppConfig.routeKeyForUri(Uri.parse(page.uri))}::$lastReadChapterPathKey';
    if (_handledDetailAutoScrollSignature == signature) {
      return;
    }
    _handledDetailAutoScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDetailChapterVisible(lastReadChapterPathKey, attempts: 12);
    });
  }

  void _ensureDetailChapterVisible(
    String chapterPathKey, {
    required int attempts,
  }) {
    if (!mounted) {
      return;
    }
    final BuildContext? targetContext =
        _detailChapterItemKeys[chapterPathKey]?.currentContext;
    if (targetContext == null) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 100),
          () => _ensureDetailChapterVisible(
            chapterPathKey,
            attempts: attempts - 1,
          ),
        );
      }
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.12,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  List<Widget> _buildHomeSections(HomePageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.heroBanners.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '推薦焦點',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: page.heroBanners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (BuildContext context, int index) {
                  final HeroBannerData banner = page.heroBanners[index];
                  return SizedBox(
                    width: 300,
                    child: _HeroBannerCard(
                      banner: banner,
                      onTap: () => _navigateToHref(banner.href),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    if (page.feature != null) {
      sections.add(
        _FeatureBannerCard(
          banner: page.feature!,
          onTap: () => _navigateToHref(page.feature!.href),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    for (final ComicSectionData section in page.sections) {
      sections.add(
        _SurfaceBlock(
          title: section.title,
          actionLabel: section.href.isNotEmpty ? '更多' : null,
          onActionTap: section.href.isNotEmpty
              ? () => _navigateToHref(section.href)
              : null,
          child: ComicGrid(items: section.items, onTap: _navigateToHref),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    return sections;
  }

  List<Widget> _buildDiscoverSections(DiscoverPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.filters.isNotEmpty) {
      final FilterGroupData primaryGroup = page.filters.first;
      final List<LinkAction> themeOptions = primaryGroup.options
          .where((LinkAction option) => !_isDiscoverMoreCategoryOption(option))
          .toList(growable: false);
      final List<FilterGroupData> secondaryGroups = page.filters
          .skip(1)
          .toList(growable: false);

      sections.add(
        _SurfaceBlock(
          title: '篩選器',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FilterGroup(
                group: FilterGroupData(
                  label: primaryGroup.label,
                  options: _visibleDiscoverThemeOptions(themeOptions),
                ),
                onTap: _navigateDiscoverFilter,
                actionLabel: _isDiscoverThemeExpanded ? '收起分類' : '查看全部分類',
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
                    child: _FilterGroup(
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
      _SurfaceBlock(
        title: '內容列表',
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
    sections.add(const SizedBox(height: 18));
    sections.add(
      IgnorePointer(
        ignoring: _isLoading,
        child: Opacity(
          opacity: _isLoading ? 0.72 : 1,
          child: _PagerCard(
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
          ),
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildRankSections(RankPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.categories.isNotEmpty || page.periods.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '榜單切換',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (page.categories.isNotEmpty)
                _RankFilterGroup(
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
                _RankFilterGroup(
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
      _SurfaceBlock(
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
                        child: _RankCard(
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
    final List<_DetailChapterTabData> chapterTabs = _detailChapterTabs(page);
    final _DetailChapterTabData? activeChapterTab = _activeDetailChapterTab(
      page,
    );
    final List<ChapterData> visibleChapters = _visibleDetailChapters(page);
    _scheduleDetailChapterAutoPosition(
      page,
      visibleChapters,
      lastReadChapterPathKey,
    );
    final List<Widget> sections = <Widget>[
      _DetailHeroCard(
        page: page,
        onReadNow: page.startReadingHref.isNotEmpty
            ? () => _openDetailChapter(page, page.startReadingHref)
            : null,
        onDownload: () => _showDetailDownloadPicker(page),
        onTagTap: _navigateToHref,
      ),
      const SizedBox(height: 18),
    ];

    if (page.summary.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '內容簡介',
          child: Text(page.summary, style: const TextStyle(height: 1.7)),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> infoChips = <Widget>[
      if (page.authors.isNotEmpty) _InfoChip(label: '作者', value: page.authors),
      if (page.status.isNotEmpty) _InfoChip(label: '狀態', value: page.status),
      if (page.updatedAt.isNotEmpty)
        _InfoChip(label: '更新', value: page.updatedAt),
      if (page.heat.isNotEmpty) _InfoChip(label: '熱度', value: page.heat),
      if (page.aliases.isNotEmpty) _InfoChip(label: '別名', value: page.aliases),
    ];
    if (infoChips.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '作品信息',
          child: Wrap(spacing: 10, runSpacing: 10, children: infoChips),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      _SurfaceBlock(
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
                  _DetailChapterToolbar(
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
                      child: _ChapterGrid(
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
