import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/wallpaper_storage.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:flutter/material.dart';

import 'package:easy_copy/widgets/settings_ui.dart';

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
                const _ComicCollectionLoadingIndicator()
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

class _ComicCollectionLoadingIndicator extends StatelessWidget {
  const _ComicCollectionLoadingIndicator();

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

class _AppearanceSettingsCard extends StatelessWidget {
  const _AppearanceSettingsCard({
    required this.themePreference,
    this.onChanged,
    this.wallpaper = const WallpaperPreferences(),
    this.wallpaperActions,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference>? onChanged;
  final WallpaperPreferences wallpaper;
  final WallpaperEditingActions? wallpaperActions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '外观',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '主题配色',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppThemePreference.values
                .map(
                  (AppThemePreference option) => _ThemeSwatch(
                    option: option,
                    selected: option == themePreference,
                    onTap: onChanged == null ? null : () => onChanged!(option),
                  ),
                )
                .toList(growable: false),
          ),
          if (wallpaperActions != null) ...<Widget>[
            const SizedBox(height: 20),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            _WallpaperSettingsSection(
              wallpaper: wallpaper,
              actions: wallpaperActions!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 92,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildPreview(option),
                  if (selected)
                    Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appThemePreferenceLabel(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPreview(AppThemePreference option) {
    switch (option) {
      case AppThemePreference.system:
        return Row(
          children: const <Widget>[
            Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
            Expanded(child: ColoredBox(color: Color(0xFF000000))),
          ],
        );
      case AppThemePreference.pureWhite:
        return const ColoredBox(color: Color(0xFFFFFFFF));
      case AppThemePreference.pureBlack:
        return const ColoredBox(color: Color(0xFF000000));
      case AppThemePreference.warmLight:
        return const ColoredBox(color: Color(0xFFFAF6EE));
      case AppThemePreference.warmDark:
        return const ColoredBox(color: Color(0xFF18130E));
      case AppThemePreference.lightOrange:
        return const ColoredBox(color: Color(0xFFFFF3E6));
      case AppThemePreference.softGreen:
        return const ColoredBox(color: Color(0xFFC7EDCC));
      case AppThemePreference.bluePink:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFC9D5FF),
                Color(0xFFEEDBF1),
                Color(0xFFFFCEDF),
              ],
            ),
          ),
        );
      case AppThemePreference.lightBlueGreen:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFC4E0FF),
                Color(0xFFD2E9DD),
                Color(0xFFC0E8CB),
              ],
            ),
          ),
        );
    }
  }
}

class _WallpaperSettingsSection extends StatefulWidget {
  const _WallpaperSettingsSection({
    required this.wallpaper,
    required this.actions,
  });

  final WallpaperPreferences wallpaper;
  final WallpaperEditingActions actions;

  @override
  State<_WallpaperSettingsSection> createState() =>
      _WallpaperSettingsSectionState();
}

class _WallpaperSettingsSectionState extends State<_WallpaperSettingsSection> {
  double? _draftBrightness;
  double? _draftBlur;
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final WallpaperPreferences w = widget.wallpaper;
    final WallpaperEditingActions actions = widget.actions;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double brightness = _draftBrightness ?? w.brightness;
    final double blur = _draftBlur ?? w.blurSigma;
    final bool hasImage = w.hasImage;
    final bool isEnabled = w.enabled;
    final bool controlsEnabled = hasImage && isEnabled && !_isPicking;
    final String statusLine = !hasImage
        ? '选择一张图片作为应用背景'
        : !isEnabled
        ? '已隐藏 · 打开开关即可启用'
        : '已启用 · 拖动滑块实时调节';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '自定义壁纸',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLine,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: isEnabled,
              onChanged: !hasImage || _isPicking
                  ? null
                  : (bool value) {
                      actions.commitPreferences(w.copyWith(enabled: value));
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WallpaperPreviewTile(
          wallpaper: w,
          previewBrightness: brightness,
          previewBlur: blur,
          isLoading: _isPicking,
          onTap: _isPicking ? null : _handlePick,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _isPicking ? null : _handlePick,
                icon: const Icon(Icons.image_outlined),
                label: Text(hasImage ? '更换图片' : '选择图片'),
              ),
            ),
            if (hasImage) ...<Widget>[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _isPicking
                    ? null
                    : () {
                        actions.clearImage();
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('移除'),
              ),
            ],
          ],
        ),
        if (hasImage) ...<Widget>[
          const SizedBox(height: 14),
          _WallpaperSliderRow(
            icon: Icons.brightness_6_outlined,
            label: '背景亮度',
            valueLabel: '${(brightness * 100).round()}%',
            value: brightness,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            enabled: controlsEnabled,
            onChanged: (double value) {
              setState(() => _draftBrightness = value);
              actions.previewPreferences(w.copyWith(brightness: value));
            },
            onChangeEnd: (double value) {
              actions.commitPreferences(w.copyWith(brightness: value));
              setState(() => _draftBrightness = null);
            },
          ),
          const SizedBox(height: 4),
          _WallpaperSliderRow(
            icon: Icons.blur_on_outlined,
            label: '模糊度',
            valueLabel: blur < 0.5 ? '关闭' : '${blur.round()}',
            value: blur,
            min: 0.0,
            max: WallpaperPreferences.maxBlurSigma,
            divisions: WallpaperPreferences.maxBlurSigma.round(),
            enabled: controlsEnabled,
            onChanged: (double value) {
              setState(() => _draftBlur = value);
              actions.previewPreferences(w.copyWith(blurSigma: value));
            },
            onChangeEnd: (double value) {
              actions.commitPreferences(w.copyWith(blurSigma: value));
              setState(() => _draftBlur = null);
            },
          ),
        ],
      ],
    );
  }

  Future<void> _handlePick() async {
    if (_isPicking) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      await widget.actions.pickImage();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      } else {
        _isPicking = false;
      }
    }
  }
}

class _WallpaperPreviewTile extends StatelessWidget {
  const _WallpaperPreviewTile({
    required this.wallpaper,
    required this.previewBrightness,
    required this.previewBlur,
    required this.isLoading,
    required this.onTap,
  });

  final WallpaperPreferences wallpaper;
  final double previewBrightness;
  final double previewBlur;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String? path = WallpaperStorage.instance.resolvePathSync(
      wallpaper.imageFileName,
    );
    final double scrimAlpha = (1.0 - previewBrightness).clamp(0.0, 1.0);

    Widget content;
    if (path == null) {
      content = _buildPlaceholder(colorScheme);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: previewBlur < 0.5
                ? Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) => _buildPlaceholder(colorScheme),
                  )
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: previewBlur,
                      sigmaY: previewBlur,
                    ),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) => _buildPlaceholder(colorScheme),
                    ),
                  ),
          ),
          if (scrimAlpha > 0.001)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface.withValues(alpha: scrimAlpha),
              ),
            ),
          if (wallpaper.enabled)
            Positioned(
              right: 12,
              bottom: 12,
              child: _PreviewSampleCard(colorScheme: colorScheme),
            ),
          Positioned(
            left: 12,
            top: 12,
            child: _PreviewHintChip(
              colorScheme: colorScheme,
              label: wallpaper.enabled ? '当前壁纸' : '已隐藏',
            ),
          ),
        ],
      );
    }

    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              content,
              if (isLoading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.6),
            colorScheme.secondaryContainer.withValues(alpha: 0.55),
            colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '点击选择壁纸图片',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '支持 JPG / PNG / WEBP',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.52),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSampleCard extends StatelessWidget {
  const _PreviewSampleCard({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 60,
            height: 8,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 90,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 72,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHintChip extends StatelessWidget {
  const _PreviewHintChip({required this.colorScheme, required this.label});

  final ColorScheme colorScheme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _WallpaperSliderRow extends StatelessWidget {
  const _WallpaperSliderRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color disabledLabelColor = colorScheme.onSurface.withValues(
      alpha: 0.36,
    );
    final Color labelColor = enabled
        ? colorScheme.onSurface.withValues(alpha: 0.82)
        : disabledLabelColor;
    final Color iconColor = enabled ? colorScheme.primary : disabledLabelColor;
    final double clampedValue = value.clamp(min, max);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: clampedValue,
              min: min,
              max: max,
              divisions: divisions > 0 ? divisions : null,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 44,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _HostSettingsEntryCard extends StatelessWidget {
  const _HostSettingsEntryCard({
    required this.currentHost,
    required this.knownHosts,
    required this.candidateHosts,
    required this.candidateHostAliases,
    required this.snapshot,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
  });

  final String currentHost;
  final List<String> knownHosts;
  final List<String> candidateHosts;
  final Map<String, List<String>> candidateHostAliases;
  final HostProbeSnapshot? snapshot;
  final bool isRefreshing;
  final FutureOr<void> Function()? onRefresh;
  final FutureOr<void> Function()? onUseAutomaticSelection;
  final FutureOr<void> Function(String value)? onSelectHost;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      title: '访问域名',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) {
                      return _HostSettingsPage(
                        currentHost: currentHost,
                        knownHosts: knownHosts,
                        candidateHosts: candidateHosts,
                        candidateHostAliases: candidateHostAliases,
                        snapshot: snapshot,
                        isRefreshing: isRefreshing,
                        onRefresh: onRefresh,
                        onUseAutomaticSelection: onUseAutomaticSelection,
                        onSelectHost: onSelectHost,
                      );
                    },
                  ),
                );
              },
              icon: const Icon(Icons.tune_rounded),
              label: const Text('管理域名'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCheckedAt(DateTime checkedAt) {
  final String month = checkedAt.month.toString().padLeft(2, '0');
  final String day = checkedAt.day.toString().padLeft(2, '0');
  final String hour = checkedAt.hour.toString().padLeft(2, '0');
  final String minute = checkedAt.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

class _HostSettingsPage extends StatefulWidget {
  const _HostSettingsPage({
    required this.currentHost,
    required this.knownHosts,
    required this.candidateHosts,
    required this.candidateHostAliases,
    required this.snapshot,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
  });

  final String currentHost;
  final List<String> knownHosts;
  final List<String> candidateHosts;
  final Map<String, List<String>> candidateHostAliases;
  final HostProbeSnapshot? snapshot;
  final bool isRefreshing;
  final FutureOr<void> Function()? onRefresh;
  final FutureOr<void> Function()? onUseAutomaticSelection;
  final FutureOr<void> Function(String value)? onSelectHost;

  @override
  State<_HostSettingsPage> createState() => _HostSettingsPageState();
}

class _HostSettingsPageState extends State<_HostSettingsPage> {
  static const Object _snapshotSentinel = Object();

  late String _currentHost;
  late HostProbeSnapshot? _snapshot;
  late bool _isRefreshing;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _currentHost = _normalizeHostValue(widget.currentHost);
    _snapshot = _normalizeSnapshot(widget.snapshot);
    _isRefreshing = widget.isRefreshing;
  }

  @override
  void didUpdateWidget(covariant _HostSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isBusy) {
      return;
    }
    if (oldWidget.currentHost != widget.currentHost ||
        oldWidget.snapshot != widget.snapshot) {
      _currentHost = _normalizeHostValue(widget.currentHost);
      _snapshot = _normalizeSnapshot(widget.snapshot);
    }
    if (oldWidget.isRefreshing != widget.isRefreshing) {
      _isRefreshing = widget.isRefreshing;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String normalizedCurrentHost = _currentHost;
    final String? pinnedHost = _snapshot?.sessionPinnedHost
        ?.trim()
        .toLowerCase();
    final String normalizedPinnedHost = pinnedHost ?? '';
    final String recommendedHost =
        _snapshot?.selectedHost.trim().toLowerCase() ?? '';
    final Map<String, List<String>> aliasGroups = _normalizedAliasGroups(
      widget.candidateHosts,
      widget.candidateHostAliases,
    );
    final Map<String, String> canonicalHostByAlias = <String, String>{
      for (final MapEntry<String, List<String>> entry in aliasGroups.entries)
        entry.key: entry.key,
      for (final MapEntry<String, List<String>> entry in aliasGroups.entries)
        for (final String alias in entry.value) alias: entry.key,
    };
    final Set<String> selectableHosts = aliasGroups.keys.toSet();
    final Map<String, List<HostProbeRecord>> probesByCanonicalHost =
        <String, List<HostProbeRecord>>{};
    for (final HostProbeRecord probe
        in _snapshot?.probes ?? const <HostProbeRecord>[]) {
      final String normalizedProbeHost = _normalizeHostValue(probe.host);
      if (normalizedProbeHost.isEmpty) {
        continue;
      }
      final String canonicalHost =
          canonicalHostByAlias[normalizedProbeHost] ?? normalizedProbeHost;
      probesByCanonicalHost
          .putIfAbsent(canonicalHost, () => <HostProbeRecord>[])
          .add(probe);
    }
    final Map<String, HostProbeRecord> probes = <String, HostProbeRecord>{
      for (final MapEntry<String, List<HostProbeRecord>> entry
          in probesByCanonicalHost.entries)
        entry.key: _preferredProbeForHostGroup(entry.value),
    };
    final String normalizedCurrentKey =
        canonicalHostByAlias[normalizedCurrentHost] ?? normalizedCurrentHost;
    final String normalizedPinnedKey =
        canonicalHostByAlias[normalizedPinnedHost] ?? normalizedPinnedHost;
    final String recommendedKey =
        canonicalHostByAlias[recommendedHost] ?? recommendedHost;
    final Set<String> seenHosts = <String>{};
    final List<String> rawHosts = <String>[
      ...selectableHosts,
      ..._knownHosts(),
      if (normalizedCurrentKey.isNotEmpty) normalizedCurrentKey,
      if (normalizedPinnedKey.isNotEmpty) normalizedPinnedKey,
      if (recommendedKey.isNotEmpty) recommendedKey,
    ];
    final List<String> hosts =
        <String>[
          for (final String host in rawHosts)
            if (seenHosts.add(canonicalHostByAlias[host] ?? host))
              canonicalHostByAlias[host] ?? host,
        ]..sort((String left, String right) {
          final int leftRank = _hostDisplayRank(probes[left]);
          final int rightRank = _hostDisplayRank(probes[right]);
          if (leftRank != rightRank) {
            return leftRank.compareTo(rightRank);
          }
          return rawHosts.indexOf(left).compareTo(rawHosts.indexOf(right));
        });

    return Scaffold(
      appBar: AppBar(title: const Text('访问域名')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            _HostSummaryChip(
                              label: '当前域名',
                              value: normalizedCurrentHost.isEmpty
                                  ? '--'
                                  : normalizedCurrentHost,
                            ),
                            _HostSummaryChip(
                              label: '模式',
                              value: pinnedHost == null ? '自动选择' : '手动锁定',
                            ),
                            if (_snapshot != null)
                              _HostSummaryChip(
                                label: '最近测速',
                                value: _formatCheckedAt(_snapshot!.checkedAt),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _isBusy ? null : _handleRefresh,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.speed_rounded),
                        label: Text(_isRefreshing ? '测速中' : '重新测速'),
                      ),
                    ],
                  ),
                  if (pinnedHost != null &&
                      widget.onUseAutomaticSelection != null) ...<Widget>[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: _isBusy ? null : _handleUseAutomaticSelection,
                      icon: const Icon(Icons.auto_mode_rounded),
                      label: const Text('恢复自动选择'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hosts.isEmpty)
              AppSurfaceCard(
                child: Text(
                  '还没有可用的域名信息。',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              )
            else
              AppSurfaceCard(
                child: Column(
                  children: hosts
                      .map(
                        (String host) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HostOptionTile(
                            host: host,
                            probe: probes[host],
                            aliases: aliasGroups[host] ?? const <String>[],
                            isCurrent: host == normalizedCurrentKey,
                            isPinned: host == normalizedPinnedKey,
                            isRecommended:
                                recommendedKey.isNotEmpty &&
                                host == recommendedKey &&
                                host != normalizedCurrentKey,
                            enabled:
                                !_isBusy &&
                                widget.onSelectHost != null &&
                                selectableHosts.contains(host),
                            onTap: widget.onSelectHost == null
                                ? null
                                : () => _handleSelectHost(host),
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
  }

  String _normalizeHostValue(String value) {
    return value.trim().toLowerCase();
  }

  Map<String, List<String>> _normalizedAliasGroups(
    List<String> candidateHosts,
    Map<String, List<String>> candidateHostAliases,
  ) {
    final Map<String, List<String>> normalizedGroups = <String, List<String>>{};
    for (final MapEntry<String, List<String>> entry
        in candidateHostAliases.entries) {
      final String normalizedPrimary = _normalizeHostValue(entry.key);
      if (normalizedPrimary.isEmpty) {
        continue;
      }
      final List<String> aliases = <String>[];
      final Set<String> seenAliases = <String>{normalizedPrimary};
      for (final String alias in entry.value) {
        final String normalizedAlias = _normalizeHostValue(alias);
        if (normalizedAlias.isEmpty || !seenAliases.add(normalizedAlias)) {
          continue;
        }
        aliases.add(normalizedAlias);
      }
      normalizedGroups[normalizedPrimary] = aliases;
    }
    for (final String host in candidateHosts) {
      final String normalizedHost = _normalizeHostValue(host);
      if (normalizedHost.isEmpty ||
          normalizedGroups.containsKey(normalizedHost)) {
        continue;
      }
      normalizedGroups[normalizedHost] = const <String>[];
    }
    return normalizedGroups;
  }

  HostProbeRecord _preferredProbeForHostGroup(List<HostProbeRecord> probes) {
    final List<HostProbeRecord> ranked = probes.toList(growable: false)
      ..sort((HostProbeRecord left, HostProbeRecord right) {
        if (left.success != right.success) {
          return left.success ? -1 : 1;
        }
        return left.latencyMs.compareTo(right.latencyMs);
      });
    return ranked.first;
  }

  HostProbeSnapshot? _normalizeSnapshot(HostProbeSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    return HostProbeSnapshot(
      selectedHost: _normalizeHostValue(snapshot.selectedHost),
      checkedAt: snapshot.checkedAt,
      probes: snapshot.probes,
      sessionPinnedHost: snapshot.sessionPinnedHost == null
          ? null
          : _normalizeHostValue(snapshot.sessionPinnedHost!),
    );
  }

  Set<String> _knownHosts() {
    return <String>{
      for (final String host in widget.knownHosts)
        if (_normalizeHostValue(host).isNotEmpty) _normalizeHostValue(host),
      if (_currentHost.isNotEmpty) _currentHost,
      for (final String host in widget.candidateHosts)
        if (_normalizeHostValue(host).isNotEmpty) _normalizeHostValue(host),
      for (final MapEntry<String, List<String>> entry
          in widget.candidateHostAliases.entries)
        if (_normalizeHostValue(entry.key).isNotEmpty)
          _normalizeHostValue(entry.key),
      for (final MapEntry<String, List<String>> entry
          in widget.candidateHostAliases.entries)
        for (final String alias in entry.value)
          if (_normalizeHostValue(alias).isNotEmpty) _normalizeHostValue(alias),
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        if (_normalizeHostValue(probe.host).isNotEmpty)
          _normalizeHostValue(probe.host),
    };
  }

  int _hostDisplayRank(HostProbeRecord? probe) {
    if (probe == null) {
      return 2;
    }
    return probe.success ? 0 : 1;
  }

  HostProbeSnapshot? _copySnapshot({
    String? selectedHost,
    Object? pinnedHost = _snapshotSentinel,
    DateTime? checkedAt,
  }) {
    final HostProbeSnapshot? snapshot = _snapshot;
    final String resolvedSelectedHost = _normalizeHostValue(
      selectedHost ?? snapshot?.selectedHost ?? _currentHost,
    );
    final String? resolvedPinnedHost = switch (pinnedHost) {
      String value => _normalizeHostValue(value),
      null => null,
      _ =>
        snapshot?.sessionPinnedHost == null
            ? null
            : _normalizeHostValue(snapshot!.sessionPinnedHost!),
    };
    if (snapshot == null &&
        resolvedSelectedHost.isEmpty &&
        resolvedPinnedHost == null) {
      return null;
    }
    return HostProbeSnapshot(
      selectedHost: resolvedSelectedHost,
      checkedAt: checkedAt ?? snapshot?.checkedAt ?? DateTime.now(),
      probes: snapshot?.probes ?? const <HostProbeRecord>[],
      sessionPinnedHost: resolvedPinnedHost,
    );
  }

  void _syncFromHostManager() {
    final Set<String> knownHosts = _knownHosts();
    final String managerCurrent = _normalizeHostValue(
      HostManager.instance.currentHost,
    );
    final HostProbeSnapshot? managerSnapshot = _normalizeSnapshot(
      HostManager.instance.probeSnapshot,
    );
    final bool canUseManagerCurrent =
        managerCurrent.isNotEmpty && knownHosts.contains(managerCurrent);
    final bool canUseManagerSnapshot =
        managerSnapshot != null &&
        (knownHosts.contains(managerSnapshot.selectedHost) ||
            managerSnapshot.probes.any(
              (HostProbeRecord probe) =>
                  knownHosts.contains(_normalizeHostValue(probe.host)),
            ));
    if (!canUseManagerCurrent && !canUseManagerSnapshot) {
      return;
    }
    _currentHost = canUseManagerCurrent ? managerCurrent : _currentHost;
    _snapshot = canUseManagerSnapshot
        ? managerSnapshot
        : _copySnapshot(selectedHost: _currentHost);
  }

  Future<void> _runBusyAction(
    Future<void> Function() action, {
    bool refreshing = false,
  }) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _isRefreshing = refreshing || widget.isRefreshing;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isRefreshing = false;
        });
      } else {
        _isBusy = false;
        _isRefreshing = false;
      }
    }
  }

  Future<void> _handleRefresh() async {
    final FutureOr<void> Function()? onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return;
    }
    await _runBusyAction(() async {
      await onRefresh();
      _syncFromHostManager();
    }, refreshing: true);
  }

  Future<void> _handleUseAutomaticSelection() async {
    final FutureOr<void> Function()? onUseAutomaticSelection =
        widget.onUseAutomaticSelection;
    if (onUseAutomaticSelection == null) {
      return;
    }
    final String previousCurrentHost = _currentHost;
    final HostProbeSnapshot? previousSnapshot = _snapshot;
    final String automaticHost = _normalizeHostValue(
      _snapshot?.selectedHost ?? _currentHost,
    );
    setState(() {
      if (automaticHost.isNotEmpty) {
        _currentHost = automaticHost;
      }
      _snapshot = _copySnapshot(
        selectedHost: automaticHost.isEmpty ? _currentHost : automaticHost,
        pinnedHost: null,
      );
    });
    await _runBusyAction(() async {
      try {
        await onUseAutomaticSelection();
        _syncFromHostManager();
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentHost = previousCurrentHost;
          _snapshot = previousSnapshot;
        });
      }
    });
  }

  Future<void> _handleSelectHost(String host) async {
    final FutureOr<void> Function(String value)? onSelectHost =
        widget.onSelectHost;
    if (onSelectHost == null) {
      return;
    }
    final String normalizedHost = _normalizeHostValue(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    final String previousCurrentHost = _currentHost;
    final HostProbeSnapshot? previousSnapshot = _snapshot;
    setState(() {
      _currentHost = normalizedHost;
      _snapshot = _copySnapshot(
        selectedHost: normalizedHost,
        pinnedHost: normalizedHost,
      );
    });
    await _runBusyAction(() async {
      try {
        await onSelectHost(normalizedHost);
        _syncFromHostManager();
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentHost = previousCurrentHost;
          _snapshot = previousSnapshot;
        });
      }
    });
  }
}

class _HostSummaryChip extends StatelessWidget {
  const _HostSummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.66),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HostOptionTile extends StatelessWidget {
  const _HostOptionTile({
    required this.host,
    required this.aliases,
    required this.isCurrent,
    required this.isPinned,
    required this.isRecommended,
    required this.enabled,
    this.probe,
    this.onTap,
  });

  final String host;
  final List<String> aliases;
  final HostProbeRecord? probe;
  final bool isCurrent;
  final bool isPinned;
  final bool isRecommended;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color borderColor = isCurrent
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final Color backgroundColor = isCurrent
        ? colorScheme.primaryContainer.withValues(alpha: 0.42)
        : colorScheme.surfaceContainerLow;
    final Color probeColor = probe == null
        ? colorScheme.onSurface.withValues(alpha: 0.7)
        : probe!.success
        ? const Color(0xFF18794E)
        : colorScheme.error;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        host,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (isCurrent) const _HostStateBadge(label: '当前'),
                      if (isPinned) const _HostStateBadge(label: '手动'),
                      if (isRecommended)
                        const _HostStateBadge(
                          label: '推荐',
                          backgroundColor: Color(0xFFE8F7EE),
                          foregroundColor: Color(0xFF18794E),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _probeMessage(probe),
                    style: TextStyle(
                      color: probeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (aliases.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '同 IP：${aliases.join(' / ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isCurrent
                  ? Icons.check_circle_rounded
                  : enabled
                  ? Icons.chevron_right_rounded
                  : Icons.block_rounded,
              color: isCurrent
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  String _probeMessage(HostProbeRecord? probe) {
    if (probe == null) {
      return '未测速';
    }
    if (probe.success) {
      final String statusCode = probe.statusCode == null
          ? ''
          : ' · HTTP ${probe.statusCode}';
      return '${probe.latencyMs} ms$statusCode';
    }
    if (probe.statusCode != null) {
      return '测速失败 · HTTP ${probe.statusCode}';
    }
    return '连接失败';
  }
}

class _HostStateBadge extends StatelessWidget {
  const _HostStateBadge({
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor ?? colorScheme.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VersionEntryCard extends StatelessWidget {
  const _VersionEntryCard({
    required this.versionLabel,
    required this.isCheckingForUpdates,
    this.onCheckForUpdates,
    this.onOpenProjectRepository,
  });

  final String versionLabel;
  final bool isCheckingForUpdates;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenProjectRepository;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '版本',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: <Widget>[
            _VersionEntryRow(
              label: '当前版本',
              trailing: Text(
                versionLabel,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _VersionEntryDivider(color: colorScheme.outlineVariant),
            _VersionEntryRow(
              label: '检查更新',
              onTap: onCheckForUpdates,
              trailing: isCheckingForUpdates
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
            ),
            _VersionEntryDivider(color: colorScheme.outlineVariant),
            _VersionEntryRow(
              label: 'GitHub',
              onTap: onOpenProjectRepository,
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionEntryRow extends StatelessWidget {
  const _VersionEntryRow({
    required this.label,
    required this.trailing,
    this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconTheme(
              data: IconThemeData(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              child: trailing,
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionEntryDivider extends StatelessWidget {
  const _VersionEntryDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Divider(height: 1, color: color.withValues(alpha: 0.56)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title, this.action});

  final String? title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(title: title, action: action, child: child);
  }
}

class _SectionHeaderAction extends StatelessWidget {
  const _SectionHeaderAction({
    required this.metaText,
    required this.semanticLabel,
    required this.onTap,
  });

  final String metaText;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          metaText,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.58),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        _SectionActionButton(semanticLabel: semanticLabel, onTap: onTap),
      ],
    );
  }
}

class _SectionActionButton extends StatelessWidget {
  const _SectionActionButton({
    required this.semanticLabel,
    required this.onTap,
  });

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.72,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  static const double _titleHeight = 33.6;

  final ComicCardData item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: EasyCopyCoverImage(imageUrl: item.coverUrl)),
          const SizedBox(height: 8),
          SizedBox(
            height: _titleHeight,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (item.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.66),
                fontSize: 11,
              ),
            ),
          ],
          if (item.secondaryText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              item.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onTap});

  final ProfileHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 68,
              height: 92,
              child: EasyCopyCoverImage(
                imageUrl: item.coverUrl,
                borderRadius: 16,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.chapterLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (item.visitedAt.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      item.visitedAt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.56),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
