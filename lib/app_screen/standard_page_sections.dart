part of '../app_screen.dart';

extension _AppScreenPageSections on _AppScreenState {
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
    return <Widget>[
      SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingIndicator(context),
      ),
    ];
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
      _hPaddedBox(
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
                      child: const Text('回到首页'),
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
      ),
    ];
  }

  Widget _buildInlineLoader() {
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

    for (final ComicSectionData section in page.sections) {
      sections.add(
        _hPaddedBox(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: section.title,
                actionLabel: section.href.isNotEmpty ? '更多' : null,
                onActionTap: section.href.isNotEmpty
                    ? () {
                        unawaited(_openHomeSectionHref(section.href));
                      }
                    : null,
              ),
              ComicGrid(items: section.items, onTap: _navigateToHref),
            ],
          ),
        ),
      );
      sections.add(_hPaddedBox(const SizedBox(height: 22)));
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
      sourceTabIndex: _nav.selectedIndex,
      targetTabIndexOverride: _nav.selectedIndex,
      historyMode: NavigationIntent.push,
    );
  }

  List<Widget> _buildDiscoverSections(DiscoverPageData page) {
    final List<Widget> sections = <Widget>[];
    final bool hasPager =
        page.pager.hasPrev ||
        page.pager.hasNext ||
        page.pager.currentLabel.isNotEmpty ||
        page.pager.totalLabel.isNotEmpty;

    if (page.filters.isNotEmpty) {
      final FilterGroupData primaryGroup = page.filters.first;
      final List<LinkAction> themeOptions = primaryGroup.options
          .where((LinkAction option) => !isDiscoverMoreCategoryOption(option))
          .toList(growable: false);
      final List<FilterGroupData> secondaryGroups = page.filters
          .skip(1)
          .toList(growable: false);

      sections.add(
        _hPaddedBox(
          ValueListenableBuilder<bool>(
            valueListenable: _ui.discoverFilterExpandedNotifier,
            builder: (BuildContext context, bool expanded, Widget? _) {
              final List<LinkAction> visibleThemeOptions = _routes
                  .visibleDiscoverThemeOptions(themeOptions);
              return SurfaceBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FilterGroup(
                      group: FilterGroupData(
                        label: primaryGroup.label,
                        options: visibleThemeOptions,
                      ),
                      onTap: _navigateDiscoverFilter,
                      actionLabel: themeOptions.length > 16
                          ? (expanded ? '收起' : '全部')
                          : null,
                      actionExpanded: expanded,
                      onActionTap: themeOptions.length > 16
                          ? () {
                              _ui.discoverFilterExpandedNotifier.value =
                                  !expanded;
                            }
                          : null,
                    ),
                    if (secondaryGroups.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      Container(
                        height: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                      const SizedBox(height: 18),
                      for (final FilterGroupData group in secondaryGroups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FilterGroup(
                            group: group,
                            onTap: _navigateDiscoverFilter,
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      );
      sections.add(_hPaddedBox(const SizedBox(height: 18)));
    }

    if (_isLoading) {
      sections.add(_hPaddedBox(_buildInlineLoader()));
    }

    sections.add(
      SliverToBoxAdapter(
        child: SizedBox(key: _discoverListAnchorKey(page), height: 1),
      ),
    );

    if (page.items.isEmpty) {
      sections.add(
        _hPaddedBox(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('暂时没有可展示的内容。')),
          ),
        ),
      );
    } else {
      final ({bool hasSubtitle, bool hasSecondary}) meta = comicMetaCoverage(
        page.items,
      );
      final double availableWidth = MediaQuery.sizeOf(context).width - 32;
      final double itemWidth = (availableWidth - 24) / 3;
      final double itemHeight = comicCardHeightFor(
        itemWidth: itemWidth,
        hasSubtitle: meta.hasSubtitle,
        hasSecondary: meta.hasSecondary,
      );
      final double aspectRatio = itemHeight <= 0
          ? 0.50
          : (itemWidth / itemHeight);
      sections.add(
        _hPaddedSliver(
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 10,
              childAspectRatio: aspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final ComicCardData item = page.items[index];
                return RepaintBoundary(
                  child: ComicCardTile(
                    key: ValueKey<String>(item.href),
                    item: item,
                    onTap: _navigateToHref,
                  ),
                );
              },
              childCount: page.items.length,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
      );
    }

    if (hasPager) {
      sections.add(_hPaddedBox(const SizedBox(height: 18)));
      sections.add(
        _hPaddedBox(
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
        ),
      );
    }

    return sections;
  }

  List<Widget> _buildRankSections(RankPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.categories.isNotEmpty || page.periods.isNotEmpty) {
      sections.add(
        _hPaddedBox(
          SurfaceBlock(
            title: '榜单切换',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (page.categories.isNotEmpty)
                  RankFilterGroup(
                    label: '榜单类型',
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
                    label: '统计周期',
                    items: page.periods,
                    onTap: _navigateRankFilter,
                  ),
              ],
            ),
          ),
        ),
      );
      sections.add(_hPaddedBox(const SizedBox(height: 18)));
    }

    sections.add(
      _hPaddedBox(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: '榜单列表'),
            if (_isLoading) _buildInlineLoader(),
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
    final Set<String> downloadedChapterKeys = _downloadedChapterKeys(page);
    final String lastReadChapterPathKey = _chapterKeys.lastReadKey(page);
    final List<DetailChapterTabData> chapterTabs = _detailChapters.tabs(page);
    final DetailChapterTabData? activeChapterTab = _detailChapters.activeTab(
      page,
    );
    final List<ChapterData> visibleChapters = _detailChapters.visibleChapters(
      page,
    );
    _detailChapters.scheduleAutoPosition(
      page,
      visibleChapters,
      lastReadChapterPathKey,
    );
    final List<Widget> sections = <Widget>[
      _hPaddedBox(
        DetailHeroCard(
          page: page,
          onReadNow: page.startReadingHref.isNotEmpty
              ? () => _openDetailChapter(page, page.startReadingHref)
              : null,
          onDownload: () => _showDetailDownloadPicker(page),
          onToggleCollection: page.comicId.trim().isEmpty
              ? null
              : () => unawaited(_toggleDetailCollection(page)),
          isCollectionBusy: _shell.isUpdatingCollection,
          onTagTap: _searchActions.submitFromCurrentStack,
          onAuthorTap: _navigateToHref,
        ),
      ),
      _hPaddedBox(const SizedBox(height: 18)),
    ];

    if (page.summary.isNotEmpty) {
      sections.add(
        _hPaddedBox(
          SurfaceBlock(
            title: '内容简介',
            child: Text(page.summary, style: const TextStyle(height: 1.7)),
          ),
        ),
      );
      sections.add(_hPaddedBox(const SizedBox(height: 18)));
    }

    final List<Widget> infoChips = <Widget>[
      if (page.authors.isNotEmpty) InfoChip(label: '作者', value: page.authors),
      if (page.status.isNotEmpty) InfoChip(label: '状态', value: page.status),
      if (page.updatedAt.isNotEmpty)
        InfoChip(label: '更新', value: page.updatedAt),
      if (page.heat.isNotEmpty) InfoChip(label: '热度', value: page.heat),
      if (page.aliases.isNotEmpty) InfoChip(label: '别名', value: page.aliases),
    ];
    if (infoChips.isNotEmpty) {
      sections.add(
        _hPaddedBox(
          SurfaceBlock(
            title: '作品信息',
            child: Wrap(spacing: 10, runSpacing: 10, children: infoChips),
          ),
        ),
      );
      sections.add(_hPaddedBox(const SizedBox(height: 18)));
    }

    sections.add(
      _hPaddedBox(
        SurfaceBlock(
          title: '章节目录',
          actionLabel: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
              ? '选择下载'
              : null,
          onActionTap: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
              ? () => _showDetailDownloadPicker(page)
              : null,
          child: chapterTabs.isEmpty
              ? const Text('章节还在整理中，向下刷新可重试。')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DetailChapterToolbar(
                      tabs: chapterTabs,
                      selectedKey: activeChapterTab?.key,
                      isAscending: _detailChapters.sortAscending,
                      onSelectTab: _detailChapters.selectTab,
                      onToggleSort: visibleChapters.length > 1
                          ? _detailChapters.toggleSortOrder
                          : null,
                    ),
                    const SizedBox(height: 14),
                    if (visibleChapters.isEmpty)
                      const Text('这个分组暂时没有章节。')
                    else
                      _buildAnimatedSectionContent(
                        contentKey: _detailChapters.contentKey(
                          page,
                          activeChapterTab,
                          visibleChapters,
                        ),
                        child: ChapterGrid(
                          chapters: visibleChapters,
                          onTap: (String href) =>
                              _openDetailChapter(page, href),
                          downloadedChapterPathKeys: downloadedChapterKeys,
                          lastReadChapterPathKey: lastReadChapterPathKey,
                          itemKeyBuilder: _detailChapters.itemKeyFor,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildMessageSections(String message) {
    return <Widget>[
      _hPaddedBox(
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
              FilledButton(onPressed: _loadHome, child: const Text('回到首页')),
            ],
          ),
        ),
      ),
    ];
  }
}
