import 'dart:async';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:flutter/material.dart';

import 'package:easy_copy/widgets/settings_ui.dart';

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
          pager: page.collectionsPager,
          onOpenPage: onOpenCollectionsPage,
        );
      case ProfileSubview.history:
        return _buildComicCollectionSection(
          items: historyCards,
          emptyMessage: '还没有浏览历史。',
          onTap: onOpenComic,
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
    PagerData pager = const PagerData(),
    ValueChanged<int>? onOpenPage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSurfaceCard(
          child: ComicGrid(
            items: items,
            onTap: onTap,
            onLongPress: onLongPress,
            emptyMessage: emptyMessage,
          ),
        ),
        if (_shouldShowPager(pager)) ...<Widget>[
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
        message != '登录后可发表评论并查看账号信息。' &&
        message != '個人中心還在重構中，這個版本先把首頁、發現、排行和閱讀體驗做好。';

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
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      title: '外观',
      child: SettingsSection(
        children: <Widget>[
          SettingsSelectRow<AppThemePreference>(
            label: '主题模式',
            value: themePreference,
            items: const <DropdownMenuItem<AppThemePreference>>[
              DropdownMenuItem<AppThemePreference>(
                value: AppThemePreference.system,
                child: Text('跟随系统'),
              ),
              DropdownMenuItem<AppThemePreference>(
                value: AppThemePreference.light,
                child: Text('浅色'),
              ),
              DropdownMenuItem<AppThemePreference>(
                value: AppThemePreference.dark,
                child: Text('深色'),
              ),
            ],
            onChanged: (AppThemePreference? nextValue) {
              if (nextValue == null || onChanged == null) {
                return;
              }
              onChanged!(nextValue);
            },
          ),
        ],
      ),
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
