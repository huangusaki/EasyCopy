import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/wallpaper_storage.dart';
import 'package:reader/widgets/comic_grid.dart';
import 'package:reader/widgets/cover_image.dart';
import 'package:reader/widgets/settings_ui.dart';

part 'profile_page_view/appearance_wallpaper.dart';
part 'profile_page_view/host_settings_page.dart';
part 'profile_page_view/profile_sections.dart';

/// 壁纸设置回调：滑动时仅预览，结束后再保存。
@immutable
class WallpaperEditingActions {
  const WallpaperEditingActions({
    required this.pickImage,
    required this.clearImage,
    required this.previewPreferences,
    required this.commitPreferences,
  });

  final Future<void> Function() pickImage;
  final VoidCallback clearImage;
  final ValueChanged<WallpaperPreferences> previewPreferences;
  final ValueChanged<WallpaperPreferences> commitPreferences;
}

class ProfilePageView extends StatelessWidget {
  const ProfilePageView({
    required this.page,
    required this.onAuthenticate,
    required this.onLogout,
    required this.onOpenComic,
    required this.onOpenHistory,
    required this.onOpenCollections,
    required this.onOpenHistoryPage,
    required this.onOpenCachedComicPage,
    this.onOpenCollectionsPage,
    this.onOpenHistoryPageNumber,
    this.onOpenCachedComic,
    this.onDeleteCachedComic,
    this.onDeleteHistory,
    this.isCollectionLoading = false,
    this.versionLabel = '--',
    this.isCheckingForUpdates = false,
    this.onCheckForUpdates,
    this.onOpenProjectRepository,
    this.currentHost = '',
    this.knownHosts = const <String>[],
    this.candidateHosts = const <String>[],
    this.candidateHostAliases = const <String, List<String>>{},
    this.hostSnapshot,
    this.isRefreshingHosts = false,
    this.onRefreshHosts,
    this.onUseAutomaticHostSelection,
    this.onSelectHost,
    this.themePreference = AppThemePreference.system,
    this.onThemePreferenceChanged,
    this.wallpaperPreferences = const WallpaperPreferences(),
    this.wallpaperActions,
    this.afterContinueReading,
    this.cachedComicCards = const <ComicCardData>[],
    this.activeSubview = ProfileSubview.root,
    super.key,
  });

  final ProfilePageData page;
  final VoidCallback onAuthenticate;
  final VoidCallback onLogout;
  final ValueChanged<String> onOpenComic;
  final ValueChanged<ProfileHistoryItem> onOpenHistory;
  final VoidCallback onOpenCollections;
  final VoidCallback onOpenHistoryPage;
  final VoidCallback onOpenCachedComicPage;
  final ValueChanged<int>? onOpenCollectionsPage;
  final ValueChanged<int>? onOpenHistoryPageNumber;
  final ValueChanged<String>? onOpenCachedComic;
  final ValueChanged<String>? onDeleteCachedComic;
  final ValueChanged<String>? onDeleteHistory;
  final bool isCollectionLoading;
  final String versionLabel;
  final bool isCheckingForUpdates;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenProjectRepository;
  final String currentHost;
  final List<String> knownHosts;
  final List<String> candidateHosts;
  final Map<String, List<String>> candidateHostAliases;
  final HostProbeSnapshot? hostSnapshot;
  final bool isRefreshingHosts;
  final FutureOr<void> Function()? onRefreshHosts;
  final FutureOr<void> Function()? onUseAutomaticHostSelection;
  final FutureOr<void> Function(String value)? onSelectHost;
  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference>? onThemePreferenceChanged;
  final WallpaperPreferences wallpaperPreferences;
  final WallpaperEditingActions? wallpaperActions;
  final Widget? afterContinueReading;
  final List<ComicCardData> cachedComicCards;
  final ProfileSubview activeSubview;
  static const double _libraryPreviewHeight = 204;
  static const double _libraryPreviewWidth = 100;

  @override
  Widget build(BuildContext context) {
    final bool showsHostSettings =
        currentHost.trim().isNotEmpty ||
        knownHosts.isNotEmpty ||
        candidateHosts.isNotEmpty ||
        hostSnapshot != null;
    final List<ComicCardData> collectionCards = page.collections
        .map(_collectionCardData)
        .toList(growable: false);
    final List<ComicCardData> historyCards = page.history
        .map(_historyCardData)
        .toList(growable: false);
    final int collectionsTotal = page.collectionsTotal > 0
        ? page.collectionsTotal
        : collectionCards.length;
    final int historyTotal = page.historyTotal > 0
        ? page.historyTotal
        : historyCards.length;
    final ValueChanged<String>? localHistoryDelete = page.isLoggedIn
        ? null
        : onDeleteHistory;

    if (activeSubview == ProfileSubview.cached) {
      return _buildComicCollectionSection(
        items: cachedComicCards,
        emptyMessage: '还没有缓存的漫画。',
        onTap: onOpenCachedComic ?? onOpenComic,
        onLongPress: onDeleteCachedComic,
      );
    }

    switch (activeSubview) {
      case ProfileSubview.collections:
        return _buildComicCollectionSection(
          items: collectionCards,
          emptyMessage: '还没有收藏的漫画。',
          onTap: onOpenComic,
          isLoading: isCollectionLoading,
          pager: page.collectionsPager,
          onOpenPage: onOpenCollectionsPage,
        );
      case ProfileSubview.history:
        return _buildComicCollectionSection(
          items: historyCards,
          emptyMessage: '还没有浏览历史。',
          onTap: onOpenComic,
          onLongPress: localHistoryDelete,
          pager: page.historyPager,
          onOpenPage: onOpenHistoryPageNumber,
        );
      case ProfileSubview.root:
      case ProfileSubview.cached:
        break;
    }

    final List<Widget> sections = <Widget>[
      page.isLoggedIn
          ? _buildUserCard(context, page.user)
          : _buildLoggedOutCard(),
    ];
    void addSection(Widget widget) {
      sections.add(const SizedBox(height: 18));
      sections.add(widget);
    }

    if (page.collections.isNotEmpty) {
      addSection(
        _SectionCard(
          title: '我的收藏',
          action: _SectionHeaderAction(
            metaText: '$collectionsTotal 部漫画',
            semanticLabel: '查看全部收藏',
            onTap: onOpenCollections,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: _libraryPreviewHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: collectionCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = collectionCards[index];
                    return SizedBox(
                      width: _libraryPreviewWidth,
                      child: _LibraryCard(
                        item: item,
                        onTap: () => onOpenComic(item.href),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (cachedComicCards.isNotEmpty) {
      addSection(
        _SectionCard(
          title: '已缓存漫画',
          action: _SectionHeaderAction(
            metaText: '${cachedComicCards.length} 部漫画',
            semanticLabel: '查看全部缓存',
            onTap: onOpenCachedComicPage,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: _libraryPreviewHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cachedComicCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = cachedComicCards[index];
                    return SizedBox(
                      width: _libraryPreviewWidth,
                      child: _LibraryCard(
                        item: item,
                        onTap: () =>
                            (onOpenCachedComic ?? onOpenComic)(item.href),
                        onLongPress: onDeleteCachedComic == null
                            ? null
                            : () => onDeleteCachedComic!(item.href),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (page.continueReading != null) {
      addSection(
        _SectionCard(
          title: '继续阅读',
          child: _HistoryTile(
            item: page.continueReading!,
            onTap: () => onOpenHistory(page.continueReading!),
          ),
        ),
      );
    }
    if (page.history.isNotEmpty) {
      addSection(
        _SectionCard(
          title: '浏览历史',
          action: _SectionHeaderAction(
            metaText: '$historyTotal 条记录',
            semanticLabel: '查看全部历史',
            onTap: onOpenHistoryPage,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: _libraryPreviewHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: historyCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = historyCards[index];
                    return SizedBox(
                      width: _libraryPreviewWidth,
                      child: _LibraryCard(
                        item: item,
                        onTap: () => onOpenComic(item.href),
                        onLongPress: localHistoryDelete == null
                            ? null
                            : () => localHistoryDelete(item.href),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (afterContinueReading != null) {
      addSection(afterContinueReading!);
    }

    addSection(
      _AppearanceSettingsCard(
        themePreference: themePreference,
        onChanged: onThemePreferenceChanged,
        wallpaper: wallpaperPreferences,
        wallpaperActions: wallpaperActions,
      ),
    );

    if (showsHostSettings) {
      addSection(
        _HostSettingsEntryCard(
          currentHost: currentHost,
          knownHosts: knownHosts,
          candidateHosts: candidateHosts,
          candidateHostAliases: candidateHostAliases,
          snapshot: hostSnapshot,
          isRefreshing: isRefreshingHosts,
          onRefresh: onRefreshHosts,
          onUseAutomaticSelection: onUseAutomaticHostSelection,
          onSelectHost: onSelectHost,
        ),
      );
    }

    addSection(
      _VersionEntryCard(
        versionLabel: versionLabel,
        isCheckingForUpdates: isCheckingForUpdates,
        onCheckForUpdates: onCheckForUpdates,
        onOpenProjectRepository: onOpenProjectRepository,
      ),
    );

    final Widget content = Column(children: sections);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }

  ComicCardData _collectionCardData(ProfileLibraryItem item) {
    return ComicCardData(
      title: item.title,
      subtitle: item.subtitle,
      secondaryText: item.secondaryText,
      coverUrl: item.coverUrl,
      href: item.href,
    );
  }

  ComicCardData _historyCardData(ProfileHistoryItem item) {
    return ComicCardData(
      title: item.title,
      subtitle: item.chapterLabel,
      secondaryText: item.visitedAt,
      coverUrl: item.coverUrl,
      href: item.comicHref,
    );
  }

  Widget _buildComicCollectionSection({
    required List<ComicCardData> items,
    required String emptyMessage,
    required ValueChanged<String> onTap,
    ValueChanged<String>? onLongPress,
    bool isLoading = false,
    PagerData pager = const PagerData(),
    ValueChanged<int>? onOpenPage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (isLoading)
                const _CollectionLoader()
              else
                ComicGrid(
                  items: items,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  emptyMessage: emptyMessage,
                ),
            ],
          ),
        ),
        if (!isLoading && _shouldShowPager(pager)) ...<Widget>[
          const SizedBox(height: 16),
          _ProfilePagerBar(pager: pager, onOpenPage: onOpenPage),
        ],
      ],
    );
  }

  bool _shouldShowPager(PagerData pager) {
    final int? totalPages = pager.totalPageCount;
    return pager.hasPrev ||
        pager.hasNext ||
        (totalPages != null && totalPages > 1);
  }

  Widget _buildLoggedOutCard() {
    final String message = page.message.trim();
    final bool showMessage =
        message.isNotEmpty &&
        message != '登录后可查看收藏与历史。' &&
        message != '登录后可查看收藏、历史和继续阅读。' &&
        message != '登录后可发表评论并查看账号信息。';

    return _SectionCard(
      child: Column(
        children: <Widget>[
          const Icon(Icons.person_outline_rounded, size: 48),
          if (showMessage) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAuthenticate,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('登录 / 注册'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, ProfileUserData? user) {
    final String displayName = (user?.displayName ?? '').trim().isNotEmpty
        ? user!.displayName
        : '已登录';
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectionLoader extends StatelessWidget {
  const _CollectionLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProfilePagerBar extends StatelessWidget {
  const _ProfilePagerBar({required this.pager, this.onOpenPage});

  final PagerData pager;
  final ValueChanged<int>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final int currentPage = pager.currentPageNumber ?? 1;
    final int totalPages = pager.totalPageCount ?? 1;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: pager.hasPrev && onOpenPage != null
                  ? () => onOpenPage!(currentPage - 1)
                  : null,
              child: const Text('上一页'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$currentPage / $totalPages',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (pager.totalLabel.isNotEmpty)
                  Text(
                    pager.totalLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.68),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FilledButton(
              onPressed: pager.hasNext && onOpenPage != null
                  ? () => onOpenPage!(currentPage + 1)
                  : null,
              child: const Text('下一页'),
            ),
          ),
        ],
      ),
    );
  }
}
