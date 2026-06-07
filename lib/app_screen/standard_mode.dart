part of '../app_screen.dart';

extension _AppScreenStandardMode on _AppScreenState {
  Widget _buildStandardMode(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('standard-scaffold'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      floatingActionButton: _buildSortFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: NavigationBar(
              selectedIndex: _nav.selectedIndex,
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
          ),
        ),
      ),
      body: SafeArea(bottom: false, child: _buildStandardBody(context)),
    );
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

    return _TabContentFadeIn(
      contentKey: '${_nav.selectedIndex}::${_currentEntry.routeKey}',
      child: RefreshIndicator(
        onRefresh: _retryCurrentPage,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
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
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(child: child),
    );
  }

  Widget _hPaddedSliver(Widget sliver) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: sliver,
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
        builder: (BuildContext context) =>
            SizedBox(height: MediaQuery.of(context).padding.bottom + 28),
      ),
    );
  }

  List<Widget> _buildStandardTopContent(BuildContext context) {
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
