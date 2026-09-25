part of '../app_screen.dart';

extension _AppScreenDiscoverChrome on _AppScreenState {
  bool get _shouldShowDiscoverSearchChrome {
    if (_routes.isDetailRoute || _routes.isSecondaryDiscoverRoute) {
      return false;
    }
    if (_nav.selectedIndex != 1 && !isPrimaryDiscoverUri(_currentUri)) {
      return false;
    }
    final SitePage? page = _page;
    if (page == null || page is DiscoverPageData) {
      return true;
    }
    return isPrimaryDiscoverUri(_currentUri);
  }

  Widget _buildDiscoverSearchChrome(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        if (_routes.shouldShowBackButton) ...<Widget>[
          IconButton.filledTonal(
            onPressed: _handleBackNavigation,
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.onSurface,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: _buildSearchField(context)),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return MobileSearchField(
      controller: _searchActions.textController,
      focusNode: _ui.mobileSearchFocusNode,
      navigationKey: '${_nav.selectedIndex}::${_currentEntry.routeKey}',
      history: _searchActions.entries,
      onSubmit: _searchActions.submitVisible,
      onClearQuery: _searchActions.clearVisibleDiscoverSearch,
      onRemoveHistoryEntry: (String term) =>
          unawaited(_searchActions.removeHistoryEntry(term)),
      onClearHistory: () =>
          unawaited(_searchActions.confirmClearHistory(context)),
    );
  }

  Future<void> _openDiscoverPagerHref(String href) async {
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    if (_currentEntry.routeKey == AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
      targetTabIndexOverride: _nav.selectedIndex,
    );
    _movePagerToDiscoverList(targetUri);
  }

  Future<void> _jumpDiscoverToPage(
    DiscoverPageData page,
    int targetPage,
  ) async {
    if (targetPage < 1) {
      _showNotice('请输入有效页码');
      return;
    }
    final int? totalPageCount = page.pager.totalPageCount;
    if (totalPageCount != null && targetPage > totalPageCount) {
      _showNotice('页码超出范围，最多 $totalPageCount 页');
      return;
    }
    final Uri targetUri = AppConfig.buildDiscoverPagerJumpUri(
      Uri.parse(page.uri),
      pager: page.pager,
      page: targetPage,
    );
    if (_currentEntry.routeKey == AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
      targetTabIndexOverride: _nav.selectedIndex,
    );
    _movePagerToDiscoverList(targetUri);
  }

  void _movePagerToDiscoverList(Uri targetUri) {
    final String routeKey = AppConfig.routeKeyForUri(targetUri);
    if (_currentEntry.routeKey != routeKey ||
        _isLoading ||
        _errorMessage != null) {
      return;
    }
    _scrollState.moveToAnchor(
      routeKey: routeKey,
      anchorContext: () {
        final SitePage? page = _page;
        return page is DiscoverPageData
            ? _discoverListAnchorKey(page).currentContext
            : null;
      },
    );
  }

  GlobalKey<State<StatefulWidget>> _discoverListAnchorKey(
    DiscoverPageData page,
  ) {
    final String routeKey = AppConfig.routeKeyForUri(Uri.parse(page.uri));
    return _ui.discoverListAnchorKeys.putIfAbsent(
      routeKey,
      () => GlobalKey<State<StatefulWidget>>(
        debugLabel: 'discover-list:$routeKey',
      ),
    );
  }
}
