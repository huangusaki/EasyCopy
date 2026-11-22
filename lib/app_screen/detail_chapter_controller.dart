import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:reader/app_screen/models.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/deferred_viewport_coordinator.dart';
import 'package:reader/services/local_comic.dart';

const String detailAllChapterTabKey = '__detail_all__';

class DetailChapterController {
  DetailChapterController({
    required this.isActiveRoute,
    required this.chapterPathKey,
    required this.lastReadChapterKey,
    required this.onViewportInteraction,
    required this.onChanged,
  });

  final bool Function(String routeKey) isActiveRoute;
  final String Function(String href) chapterPathKey;
  final String Function(DetailPageData page) lastReadChapterKey;
  final VoidCallback onViewportInteraction;
  final void Function(VoidCallback mutation) onChanged;

  final DeferredViewportCoordinator _autoScroll = DeferredViewportCoordinator();

  String _selectedTabKey = detailAllChapterTabKey;
  bool _sortAscending = false;
  String _routeKey = '';
  String _handledAutoScrollKey = '';
  ({List<ChapterData> chapters, String lastRead})? _missingPosition;

  bool get sortAscending => _sortAscending;

  void noteViewportInteraction() {
    _autoScroll.noteUserInteraction();
  }

  void sync(DetailPageData page, {bool forceReset = false}) {
    final String routeKey = AppConfig.routeKeyForUri(Uri.parse(page.uri));
    final List<DetailChapterTabData> tabs = this.tabs(page);
    DetailChapterTabData? fallbackTab;
    for (final DetailChapterTabData tab in tabs) {
      if (tab.enabled) {
        fallbackTab = tab;
        break;
      }
    }
    fallbackTab ??= tabs.isEmpty ? null : tabs.first;
    if (forceReset || _routeKey != routeKey) {
      _routeKey = routeKey;
      final preferredTabKey = _preferredTabKey(page, tabs);
      _handledAutoScrollKey = '';
      _missingPosition = null;
      _selectedTabKey =
          preferredTabKey ?? fallbackTab?.key ?? detailAllChapterTabKey;
      _sortAscending = isLocalComic(page.uri);
      return;
    }
    if (!tabs.any(
      (DetailChapterTabData tab) => tab.key == _selectedTabKey && tab.enabled,
    )) {
      _selectedTabKey = fallbackTab?.key ?? detailAllChapterTabKey;
    }
  }

  List<DetailChapterTabData> tabs(DetailPageData page) {
    final List<ChapterData> allChapters = page.allChapters;
    if (page.chapterGroups.isNotEmpty) {
      final bool hasAllGroup = page.chapterGroups.any(
        (ChapterGroupData group) => _isAllGroupLabel(group.label),
      );
      final List<DetailChapterTabData> tabs = <DetailChapterTabData>[
        if (!hasAllGroup && allChapters.isNotEmpty)
          DetailChapterTabData(
            key: detailAllChapterTabKey,
            label: '全部',
            chapters: allChapters,
          ),
        for (int index = 0; index < page.chapterGroups.length; index += 1)
          DetailChapterTabData(
            key: 'group:$index',
            label: _tabLabel(page.chapterGroups[index].label),
            chapters:
                _isAllGroupLabel(page.chapterGroups[index].label) &&
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
        key: detailAllChapterTabKey,
        label: '全部',
        chapters: allChapters,
      ),
    ];
  }

  DetailChapterTabData? activeTab(List<DetailChapterTabData> tabs) {
    if (tabs.isEmpty) {
      return null;
    }
    for (final DetailChapterTabData tab in tabs) {
      if (tab.key == _selectedTabKey && tab.enabled) {
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

  List<ChapterData> visibleChapters(
    DetailPageData page,
    DetailChapterTabData? active,
  ) {
    if (active == null || active.chapters.isEmpty) {
      return const <ChapterData>[];
    }
    if (_sortAscending == isLocalComic(page.uri)) {
      return active.chapters;
    }
    return active.chapters.reversed.toList(growable: false);
  }

  String contentKey(
    DetailPageData page,
    DetailChapterTabData? activeTab,
    List<ChapterData> chapters,
  ) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      activeTab?.key ?? 'empty',
      _sortAscending ? 'asc' : 'desc',
      '${chapters.length}',
      chapters.isEmpty ? '' : chapters.first.href,
      chapters.isEmpty ? '' : chapters.last.href,
    ].join('::');
  }

  void selectTab(String key) {
    if (_selectedTabKey == key) {
      return;
    }
    onViewportInteraction();
    onChanged(() {
      _selectedTabKey = key;
    });
  }

  void toggleSortOrder() {
    onViewportInteraction();
    onChanged(() {
      _sortAscending = !_sortAscending;
    });
  }

  void scheduleAutoPosition(
    DetailPageData page,
    List<ChapterData> chapters,
    String lastRead,
    SliverConstraints constraints,
    SliverGridDelegateWithFixedCrossAxisCount delegate,
    ScrollController scroll,
  ) {
    if (lastRead.isEmpty) return;
    final signature = '${page.uri}::$lastRead';
    final attempt = (chapters: chapters, lastRead: lastRead);
    if (_handledAutoScrollKey == signature || _missingPosition == attempt) {
      return;
    }
    final index = chapters.indexWhere(
      (chapter) => chapterPathKey(chapter.href) == lastRead,
    );
    if (index < 0) {
      _missingPosition = attempt;
      return;
    }
    _missingPosition = null;
    _handledAutoScrollKey = signature;
    final geometry = delegate
        .getLayout(constraints)
        .getGeometryForChildIndex(index);
    final target =
        constraints.precedingScrollExtent +
        geometry.scrollOffset -
        (constraints.viewportMainAxisExtent - geometry.mainAxisExtent) * 0.12;
    final routeKey = AppConfig.routeKeyForUri(Uri.parse(page.uri));
    final ticket = _autoScroll.beginRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients ||
          !_autoScroll.isActive(ticket) ||
          !isActiveRoute(routeKey)) {
        return;
      }
      final pos = scroll.position;
      unawaited(
        scroll.animateTo(
          target.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble(),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  bool _isAllGroupLabel(String label) {
    final String normalized = label.replaceAll(RegExp(r'\s+'), '');
    return normalized.contains('全部');
  }

  String _tabLabel(String label) {
    final String normalized = label.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return '列表';
    }
    if (_isAllGroupLabel(normalized)) {
      return '全部';
    }
    if (normalized.contains('番外')) {
      return '番外';
    }
    if (normalized.contains('單話') ||
        normalized.contains('单话') ||
        normalized == '話' ||
        normalized.endsWith('話')) {
      return '话';
    }
    if (normalized.contains('卷')) {
      return '卷';
    }
    return label.trim();
  }

  String? _preferredTabKey(
    DetailPageData page,
    List<DetailChapterTabData> tabs,
  ) {
    final String lastReadChapterPathKey = lastReadChapterKey(page);
    if (lastReadChapterPathKey.isEmpty) {
      return null;
    }
    for (final DetailChapterTabData tab in tabs) {
      if (!tab.enabled) {
        continue;
      }
      if (tab.chapters.any(
        (ChapterData chapter) =>
            chapterPathKey(chapter.href) == lastReadChapterPathKey,
      )) {
        return tab.key;
      }
    }
    return null;
  }
}
