part of '../easy_copy_screen.dart';

extension _EasyCopyScreenDetailChapterState on _EasyCopyScreenState {
  void _syncDetailChapterState(DetailPageData page, {bool forceReset = false}) {
    final String routeKey = AppConfig.routeKeyForUri(Uri.parse(page.uri));
    final List<DetailChapterTabData> tabs = _detailChapterTabs(page);
    DetailChapterTabData? fallbackTab;
    for (final DetailChapterTabData tab in tabs) {
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
      (DetailChapterTabData tab) =>
          tab.key == _selectedDetailChapterTabKey && tab.enabled,
    )) {
      _selectedDetailChapterTabKey =
          fallbackTab?.key ?? _detailAllChapterTabKey;
    }
  }

  List<DetailChapterTabData> _detailChapterTabs(DetailPageData page) {
    final List<ChapterData> allChapters = _detailChapterList(page);
    if (page.chapterGroups.isNotEmpty) {
      final bool hasAllGroup = page.chapterGroups.any(
        (ChapterGroupData group) => _isAllDetailChapterGroupLabel(group.label),
      );
      final List<DetailChapterTabData> tabs = <DetailChapterTabData>[
        if (!hasAllGroup && allChapters.isNotEmpty)
          DetailChapterTabData(
            key: _detailAllChapterTabKey,
            label: '全部',
            chapters: allChapters,
          ),
        for (int index = 0; index < page.chapterGroups.length; index += 1)
          DetailChapterTabData(
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
      return const <DetailChapterTabData>[];
    }
    return <DetailChapterTabData>[
      DetailChapterTabData(
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

  DetailChapterTabData? _activeDetailChapterTab(DetailPageData page) {
    final List<DetailChapterTabData> tabs = _detailChapterTabs(page);
    if (tabs.isEmpty) {
      return null;
    }
    for (final DetailChapterTabData tab in tabs) {
      if (tab.key == _selectedDetailChapterTabKey && tab.enabled) {
        return tab;
      }
    }
    for (final DetailChapterTabData tab in tabs) {
      if (tab.enabled) {
        return tab;
      }
    }
    return tabs.first;
  }

  List<ChapterData> _visibleDetailChapters(DetailPageData page) {
    final DetailChapterTabData? activeTab = _activeDetailChapterTab(page);
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
    for (final DetailChapterTabData tab in _detailChapterTabs(page)) {
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
    DetailChapterTabData? activeTab,
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
    _noteStandardViewportUserInteraction();
    _setStateIfMounted(() {
      _selectedDetailChapterTabKey = key;
    });
  }

  void _toggleDetailChapterSortOrder() {
    if (!mounted) {
      return;
    }
    _noteStandardViewportUserInteraction();
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
    final DeferredViewportTicket ticket = _detailChapterAutoScrollCoordinator
        .beginRequest();
    _handledDetailAutoScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDetailChapterVisible(
        lastReadChapterPathKey,
        routeKey: AppConfig.routeKeyForUri(Uri.parse(page.uri)),
        attempts: 12,
        ticket: ticket,
      );
    });
  }

  void _ensureDetailChapterVisible(
    String chapterPathKey, {
    required String routeKey,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveDetailChapterAutoScroll(ticket, routeKey: routeKey)) {
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
            routeKey: routeKey,
            attempts: attempts - 1,
            ticket: ticket,
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
}
