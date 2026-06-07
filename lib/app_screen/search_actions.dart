import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/app_screen/route_utils.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/services/primary_tab_session_store.dart';
import 'package:reader/services/search_history_store.dart';

typedef SearchUriLoader =
    Future<void> Function(
      Uri uri, {
      int? sourceTabIndex,
      int? targetTabIndexOverride,
      required NavigationIntent historyMode,
    });

typedef SearchUiUpdater = void Function([VoidCallback? mutation]);

class AppSearchActions {
  AppSearchActions({
    required SearchHistoryStore historyStore,
    required Uri Function() currentUri,
    required int Function() selectedIndex,
    required bool Function() isMounted,
    required SearchUiUpdater updateUi,
    required void Function(String message) showNotice,
    required SearchUriLoader loadUri,
  }) : _historyStore = historyStore,
       _currentUri = currentUri,
       _selectedIndex = selectedIndex,
       _isMounted = isMounted,
       _updateUi = updateUi,
       _showNotice = showNotice,
       _loadUri = loadUri;

  final SearchHistoryStore _historyStore;
  final Uri Function() _currentUri;
  final int Function() _selectedIndex;
  final bool Function() _isMounted;
  final SearchUiUpdater _updateUi;
  final void Function(String message) _showNotice;
  final SearchUriLoader _loadUri;

  final TextEditingController textController = TextEditingController();
  List<String> entries = const <String>[];

  void attach() {
    textController.addListener(handleTextChanged);
  }

  void dispose() {
    textController.removeListener(handleTextChanged);
    textController.dispose();
  }

  void handleTextChanged() {
    if (!_isMounted()) {
      return;
    }
    _updateUi();
  }

  void replaceHistory(List<String> value) {
    entries = List<String>.unmodifiable(value);
  }

  void syncFromCurrentUri() {
    final String query = _currentUri().queryParameters['q'] ?? '';
    if (textController.text == query) {
      return;
    }
    textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void prime(String query) {
    if (textController.text == query) {
      return;
    }
    textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void submit(
    String value, {
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    NavigationIntent historyMode = NavigationIntent.push,
  }) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    prime(query);
    record(query);
    unawaited(
      _loadUri(
        AppConfig.buildSearchUri(query),
        sourceTabIndex: sourceTabIndex,
        targetTabIndexOverride: targetTabIndexOverride,
        historyMode: historyMode,
      ),
    );
  }

  void record(String query) {
    final String normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }
    final List<String> next = <String>[
      normalized,
      ...entries.where((String item) => item != normalized),
    ];
    final List<String> limited = next.length <= 10
        ? next
        : next.take(10).toList(growable: false);
    _replaceEntries(limited);
    unawaited(_historyStore.record(normalized));
  }

  Future<void> removeHistoryEntry(String query) async {
    final String normalized = query.trim();
    if (normalized.isEmpty || !entries.contains(normalized)) {
      return;
    }
    final List<String> next = entries
        .where((String item) => item != normalized)
        .toList(growable: false);
    _replaceEntries(next);
    await _historyStore.remove(normalized);
    _showNotice('已删除搜索历史：$normalized');
  }

  Future<void> confirmClearHistory(BuildContext context) async {
    if (entries.isEmpty) {
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
    _replaceEntries(const <String>[]);
    await _historyStore.clear();
    _showNotice('已清空搜索历史');
  }

  void submitFromCurrentStack(String value) {
    submit(
      value,
      sourceTabIndex: _selectedIndex(),
      targetTabIndexOverride: _selectedIndex(),
    );
  }

  bool get keepDiscoverSearchInStack {
    return _selectedIndex() != 1 && isPrimaryDiscoverUri(_currentUri());
  }

  void submitVisible(String value) {
    if (keepDiscoverSearchInStack) {
      submitFromCurrentStack(value);
      return;
    }
    submit(value);
  }

  void clearVisibleDiscoverSearch() {
    if (_currentUri().path == '/search') {
      textController.clear();
      final bool keepInStack = keepDiscoverSearchInStack;
      unawaited(
        _loadUri(
          AppConfig.resolvePath('/comics'),
          sourceTabIndex: keepInStack ? _selectedIndex() : null,
          targetTabIndexOverride: keepInStack ? _selectedIndex() : null,
          historyMode: NavigationIntent.preserve,
        ),
      );
      return;
    }
    _updateUi(textController.clear);
  }

  void _replaceEntries(List<String> next) {
    if (_isMounted()) {
      _updateUi(() {
        entries = next;
      });
      return;
    }
    entries = next;
  }
}
