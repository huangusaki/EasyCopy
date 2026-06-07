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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<String> history = _searchActions.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (_routes.shouldShowBackButton) ...<Widget>[
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
                        controller: _searchActions.textController,
                        onSubmitted: _searchActions.submitVisible,
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
                    if (_searchActions.textController.text.trim().isNotEmpty)
                      IconButton(
                        onPressed: _searchActions.clearVisibleDiscoverSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      onPressed: () => _searchActions.submitVisible(
                        _searchActions.textController.text,
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
                onPressed: () {
                  unawaited(_searchActions.confirmClearHistory(context));
                },
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
                      unawaited(_searchActions.removeHistoryEntry(term));
                    },
                    child: ActionChip(
                      label: Text(term),
                      onPressed: () {
                        _searchActions.prime(term);
                        _searchActions.submitVisible(term);
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
              controller: _searchActions.textController,
              onSubmitted: _searchActions.submitVisible,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '搜索漫画、作者或题材',
              ),
            ),
          ),
          IconButton(
            onPressed: () => _searchActions.submitVisible(
              _searchActions.textController.text,
            ),
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
    if (_currentEntry.routeKey == AppConfig.routeKeyForUri(targetUri)) {
      return;
    }
    await _loadUri(
      targetUri,
      preserveVisiblePage: true,
      historyMode: NavigationIntent.preserve,
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
    );
    _movePagerToDiscoverList(targetUri);
  }

  void _movePagerToDiscoverList(Uri targetUri) {
    final String routeKey = AppConfig.routeKeyForUri(targetUri);
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
