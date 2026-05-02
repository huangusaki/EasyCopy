part of '../easy_copy_screen.dart';

extension _EasyCopyScreenSearchActions on _EasyCopyScreenState {
  void _handleSearchTextChanged() {
    if (!mounted) {
      return;
    }
    _setStateIfMounted(() {});
  }

  void _syncSearchController() {
    final String query = _currentUri.queryParameters['q'] ?? '';
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _primeSearchController(String query) {
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _submitSearch(
    String value, {
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    NavigationIntent historyMode = NavigationIntent.push,
  }) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    _primeSearchController(query);
    _recordSearchHistory(query);
    unawaited(
      _loadUri(
        AppConfig.buildSearchUri(query),
        sourceTabIndex: sourceTabIndex,
        targetTabIndexOverride: targetTabIndexOverride,
        historyMode: historyMode,
      ),
    );
  }

  void _recordSearchHistory(String query) {
    final String normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }
    final List<String> next = <String>[
      normalized,
      ..._searchHistoryEntries.where((String item) => item != normalized),
    ];
    final List<String> limited = next.length <= 10
        ? next
        : next.take(10).toList(growable: false);
    if (mounted) {
      _setStateIfMounted(() {
        _searchHistoryEntries = limited;
      });
    } else {
      _searchHistoryEntries = limited;
    }
    unawaited(_searchHistoryStore.record(normalized));
  }

  Future<void> _removeSearchHistoryEntry(String query) async {
    final String normalized = query.trim();
    if (normalized.isEmpty || !_searchHistoryEntries.contains(normalized)) {
      return;
    }
    final List<String> next = _searchHistoryEntries
        .where((String item) => item != normalized)
        .toList(growable: false);
    if (mounted) {
      _setStateIfMounted(() {
        _searchHistoryEntries = next;
      });
    } else {
      _searchHistoryEntries = next;
    }
    await _searchHistoryStore.remove(normalized);
    _showSnackBar('已删除搜索历史：$normalized');
  }

  Future<void> _confirmClearSearchHistory() async {
    if (_searchHistoryEntries.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清空搜索历史'),
          content: const Text('确认清空发现页的全部搜索历史吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (mounted) {
      _setStateIfMounted(() {
        _searchHistoryEntries = const <String>[];
      });
    } else {
      _searchHistoryEntries = const <String>[];
    }
    await _searchHistoryStore.clear();
    _showSnackBar('已清空搜索历史');
  }

  void _submitSearchFromCurrentStack(String value) {
    _submitSearch(
      value,
      sourceTabIndex: _selectedIndex,
      targetTabIndexOverride: _selectedIndex,
    );
  }

  bool get _shouldKeepDiscoverSearchInCurrentStack =>
      _selectedIndex != 1 && _isPrimaryDiscoverUri(_currentUri);

  void _submitSearchFromVisibleDiscoverContext(String value) {
    if (_shouldKeepDiscoverSearchInCurrentStack) {
      _submitSearchFromCurrentStack(value);
      return;
    }
    _submitSearch(value);
  }

  void _clearVisibleDiscoverSearch() {
    if (_currentUri.path == '/search') {
      _searchController.clear();
      unawaited(
        _loadUri(
          AppConfig.resolvePath('/comics'),
          sourceTabIndex: _shouldKeepDiscoverSearchInCurrentStack
              ? _selectedIndex
              : null,
          targetTabIndexOverride: _shouldKeepDiscoverSearchInCurrentStack
              ? _selectedIndex
              : null,
          historyMode: NavigationIntent.preserve,
        ),
      );
      return;
    }
    _setStateIfMounted(_searchController.clear);
  }
}
