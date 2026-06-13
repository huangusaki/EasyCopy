part of '../app_screen.dart';

extension _AppScreenStandardMode on _AppScreenState {
  Widget _buildStandardMode(BuildContext context) {
    if (usesDesktopLayout(context)) {
      return _buildDesktopStandardMode(context);
    }

    return Scaffold(
      key: const ValueKey<String>('standard-scaffold'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      floatingActionButton: _buildSortFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: MobileFloatingNavBar(
        selectedIndex: _nav.selectedIndex,
        destinations: appDestinations,
        onDestinationSelected: (int index) => unawaited(_onItemTapped(index)),
        visibleListenable: _ui.bottomBarVisibleNotifier,
      ),
      body: SafeArea(bottom: false, child: _buildStandardBody(context)),
    );
  }

  Widget _buildDesktopStandardMode(BuildContext context) {
    final bool wallpaperActive =
        _preferencesController.preferences.wallpaperPreferences.isActive;
    return AmbientBackdrop(
      enabled: !wallpaperActive,
      child: DesktopShortcuts(
        shortcuts: _preferencesController.shortcutPreferences,
        onSelectTab: (int index) => unawaited(_onItemTapped(index)),
        onRefresh: () {
          if (!_isLoading) {
            unawaited(_retryCurrentPage());
          }
        },
        onBack: () => unawaited(_handleBackNavigation()),
        onFocusSearch: _ui.desktopSearchFocusNode.requestFocus,
        child: Scaffold(
          key: const ValueKey<String>('standard-scaffold'),
          backgroundColor: Colors.transparent,
          floatingActionButton: _buildSortFab(context),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          body: Column(
            children: <Widget>[
              DesktopTitleBar(
                title: _routes.pageTitle,
                showBackButton: _routes.shouldShowBackButton,
                onBack: () => unawaited(_handleBackNavigation()),
                isLoading: _isLoading,
                onRefresh: () => unawaited(_retryCurrentPage()),
                onOpenShortcuts: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const KeyboardShortcutsPage(),
                  ),
                ),
                searchField: DesktopSearchField(
                  controller: _searchActions.textController,
                  focusNode: _ui.desktopSearchFocusNode,
                  history: _searchActions.entries,
                  onSubmit: _searchActions.submitVisible,
                  onRemoveHistoryEntry: (String term) =>
                      unawaited(_searchActions.removeHistoryEntry(term)),
                  onClearHistory: () =>
                      unawaited(_searchActions.confirmClearHistory(context)),
                ),
              ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _buildStandardBody(context)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Center(
                        child: DesktopDock(
                          selectedIndex: _nav.selectedIndex,
                          destinations: appDestinations,
                          onDestinationSelected: (int index) =>
                              unawaited(_onItemTapped(index)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 只响应真实拖动，忽略程序式滚动恢复。
  void _updateBottomBarVisibility(ScrollNotification notification) {
    if (PlatformCapabilities.isDesktop || notification.depth != 0) {
      return;
    }
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels <= 48) {
        _ui.bottomBarScrollAccumulator = 0;
        _ui.bottomBarVisibleNotifier.value = true;
        return;
      }
      final double? delta = notification.scrollDelta;
      if (notification.dragDetails == null || delta == null || delta == 0) {
        return;
      }
      if (delta.sign != _ui.bottomBarScrollAccumulator.sign) {
        _ui.bottomBarScrollAccumulator = 0;
      }
      _ui.bottomBarScrollAccumulator += delta;
      if (_ui.bottomBarScrollAccumulator > 24) {
        _ui.bottomBarScrollAccumulator = 0;
        _ui.bottomBarVisibleNotifier.value = false;
      } else if (_ui.bottomBarScrollAccumulator < -24) {
        _ui.bottomBarScrollAccumulator = 0;
        _ui.bottomBarVisibleNotifier.value = true;
      }
      return;
    }
    if (notification is ScrollEndNotification) {
      _ui.bottomBarScrollAccumulator = 0;
    }
  }

  Widget? _buildSortFab(BuildContext context) {
    if (AppConfig.profileSubviewForUri(_currentUri) !=
        ProfileSubview.collections) {
      return null;
    }
    final SitePage? page = _page;
    if (page is! ProfilePageData && !_isLoading) {
      return null;
    }

    final ProfileCollectionSort sort =
        _currentUri.queryParameters.containsKey('sort')
        ? AppConfig.profileCollectionSortForUri(_currentUri)
        : _preferencesController.profileCollectionSort;
    final bool isLoggedIn = page is ProfilePageData
        ? page.isLoggedIn
        : _services.session.isAuthenticated;
    final bool supportsAlphabetical = !isLoggedIn;
    final ProfileCollectionSort effectiveSort = _effectiveProfileCollectionSort(
      sort,
    );
    final ProfileCollectionSort nextSort = _nextProfileCollectionSort(
      effectiveSort,
      supportsAlphabetical: supportsAlphabetical,
    );

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return FloatingActionButton.small(
      heroTag: 'profile-collection-sort',
      tooltip: _profileCollectionSortLabel(effectiveSort),
      elevation: 2,
      hoverElevation: 4,
      focusElevation: 2,
      highlightElevation: 6,
      backgroundColor: colorScheme.surfaceContainerHigh,
      foregroundColor: colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      onPressed: _isLoading
          ? null
          : () {
              unawaited(
                _preferencesController.setProfileCollectionSort(nextSort),
              );
              _showNotice('已切换为${_profileCollectionSortLabel(nextSort)}排序');
              _openProfileSubview(
                ProfileSubview.collections,
                collectionSort: nextSort,
                historyMode: NavigationIntent.preserve,
              );
            },
      child: _isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _buildSortIconWidget(context, effectiveSort),
            ),
    );
  }

  ProfileCollectionSort _nextProfileCollectionSort(
    ProfileCollectionSort sort, {
    required bool supportsAlphabetical,
  }) {
    return switch (sort) {
      ProfileCollectionSort.latestUpdate => ProfileCollectionSort.readingTime,
      ProfileCollectionSort.readingTime =>
        supportsAlphabetical
            ? ProfileCollectionSort.alphabetical
            : ProfileCollectionSort.latestUpdate,
      ProfileCollectionSort.alphabetical => ProfileCollectionSort.latestUpdate,
    };
  }

  Widget _buildSortIconWidget(
    BuildContext context,
    ProfileCollectionSort sort,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    switch (sort) {
      case ProfileCollectionSort.latestUpdate:
        return Icon(
          Icons.auto_awesome_rounded,
          key: const ValueKey<ProfileCollectionSort>(
            ProfileCollectionSort.latestUpdate,
          ),
          size: 20,
          color: colorScheme.primary,
        );
      case ProfileCollectionSort.readingTime:
        return Icon(
          Icons.history_rounded,
          key: const ValueKey<ProfileCollectionSort>(
            ProfileCollectionSort.readingTime,
          ),
          size: 20,
          color: colorScheme.primary,
        );
      case ProfileCollectionSort.alphabetical:
        return Icon(
          Icons.sort_by_alpha_rounded,
          key: const ValueKey<ProfileCollectionSort>(
            ProfileCollectionSort.alphabetical,
          ),
          size: 20,
          color: colorScheme.primary,
        );
    }
  }

  String _profileCollectionSortLabel(ProfileCollectionSort sort) {
    return switch (sort) {
      ProfileCollectionSort.latestUpdate => '最近更新',
      ProfileCollectionSort.readingTime => '阅读时间',
      ProfileCollectionSort.alphabetical => 'A-Z',
    };
  }

  Widget _buildStandardBody(BuildContext context) {
    final List<Widget> slivers = _buildStandardBodySlivers(context);

    return ContentSwitchTransition(
      contentKey: '${_nav.selectedIndex}::${_currentEntry.routeKey}',
      tabIndex: _nav.selectedIndex,
      routeDepth: _tabSessionStore.depth(_nav.selectedIndex),
      reducedMotion: !usesDesktopLayout(context),
      child: RefreshIndicator(
        onRefresh: () {
          if (!PlatformCapabilities.isDesktop) {
            unawaited(HapticFeedback.mediumImpact());
          }
          return _retryCurrentPage();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            _updateBottomBarVisibility(notification);
            return _scrollState.handleScrollNotification(
              notification,
              onUserInteraction: _noteViewportInteraction,
            );
          },
          child: CustomScrollView(
            controller: _ui.standardScrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: slivers,
          ),
        ),
      ),
    );
  }

  Widget _hPaddedBox(Widget child) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, constraints) {
        return SliverPadding(
          padding: standardContentPadding(context),
          sliver: SliverToBoxAdapter(child: child),
        );
      },
    );
  }

  Widget _hPaddedSliver(Widget sliver) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, constraints) {
        return SliverPadding(
          padding: standardContentPadding(context),
          sliver: sliver,
        );
      },
    );
  }

  List<Widget> _buildStandardBodySlivers(BuildContext context) {
    final List<Widget> slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];

    if (_errorMessage != null && _page == null) {
      slivers.addAll(_buildErrorSections(context));
      slivers.add(_buildBottomInsetSliver());
      return slivers;
    }

    slivers.addAll(_buildStandardTopContent(context));

    if (_page == null) {
      slivers.addAll(_buildLoadingSections(context));
    } else {
      final SitePage page = _page!;
      if (page is HomePageData) {
        slivers.addAll(_buildHomeSections(page));
      } else if (page is DiscoverPageData) {
        slivers.addAll(_buildDiscoverSections(page));
      } else if (page is RankPageData) {
        slivers.addAll(_buildRankSections(page));
      } else if (page is DetailPageData) {
        slivers.addAll(_buildDetailSections(page));
      } else if (page is ProfilePageData) {
        slivers.addAll(_buildProfileSections(page));
      } else if (page is UnknownPageData) {
        slivers.addAll(_buildMessageSections(page.message));
      }
    }

    slivers.add(_buildBottomInsetSliver());
    return slivers;
  }

  Widget _buildBottomInsetSliver() {
    return SliverToBoxAdapter(
      child: Builder(
        builder: (BuildContext context) {
          final double dockInset = usesDesktopLayout(context)
              ? DesktopDock.bottomOverlayExtent + 12
              : 0;
          return SizedBox(
            height: MediaQuery.of(context).padding.bottom + 28 + dockInset,
          );
        },
      ),
    );
  }

  List<Widget> _buildStandardTopContent(BuildContext context) {
    if (usesDesktopLayout(context)) {
      return const <Widget>[];
    }

    if (_shouldShowDiscoverSearchChrome) {
      return <Widget>[
        _hPaddedBox(_buildDiscoverSearchChrome(context)),
        _hPaddedBox(const SizedBox(height: 18)),
      ];
    }

    if (_routes.shouldShowHeaderCard) {
      return <Widget>[
        _hPaddedBox(
          _buildHeaderCard(
            context,
            title: _routes.pageTitle,
            showBackButton: _routes.shouldShowBackButton,
            showSearchBar: _routes.shouldShowSearchBar,
          ),
        ),
        _hPaddedBox(const SizedBox(height: 18)),
      ];
    }

    return const <Widget>[];
  }
}
