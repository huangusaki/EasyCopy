import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/image_cache.dart';
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
    this.onOpenCachedComic,
    this.onDeleteCachedComic,
    this.currentHost = '',
    this.candidateHosts = const <String>[],
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
  final ValueChanged<String>? onOpenCachedComic;
  final ValueChanged<String>? onDeleteCachedComic;
  final String currentHost;
  final List<String> candidateHosts;
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

  @override
  Widget build(BuildContext context) {
    final bool showsHostSettings =
        currentHost.trim().isNotEmpty ||
        candidateHosts.isNotEmpty ||
        hostSnapshot != null;
    final List<ComicCardData> collectionCards = page.collections
        .map(_collectionCardData)
        .toList(growable: false);
    final List<ComicCardData> historyCards = page.history
        .map(_historyCardData)
        .toList(growable: false);

    if (activeSubview == ProfileSubview.cached) {
      return _buildComicCollectionSection(
        context,
        title: '已缓存漫画',
        summary: '共 ${cachedComicCards.length} 部漫画',
        items: cachedComicCards,
        emptyMessage: '还没有缓存的漫画。',
        onTap: onOpenCachedComic ?? onOpenComic,
        onLongPress: onDeleteCachedComic,
      );
    }

    if (page.isLoggedIn && page.user != null) {
      switch (activeSubview) {
        case ProfileSubview.collections:
          return _buildComicCollectionSection(
            context,
            title: '我的收藏',
            summary: '共 ${collectionCards.length} 部漫画',
            items: collectionCards,
            emptyMessage: '还没有收藏的漫画。',
            onTap: onOpenComic,
          );
        case ProfileSubview.history:
          return _buildComicCollectionSection(
            context,
            title: '浏览历史',
            summary: '共 ${historyCards.length} 条记录',
            items: historyCards,
            emptyMessage: '还没有浏览历史。',
            onTap: onOpenComic,
          );
        case ProfileSubview.root:
        case ProfileSubview.cached:
          break;
      }
    }

    final List<Widget> sections = <Widget>[
      page.isLoggedIn && page.user != null
          ? _buildUserCard(context, page.user!)
          : _buildLoggedOutCard(),
    ];

    if (showsHostSettings) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        _HostSettingsEntryCard(
          currentHost: currentHost,
          candidateHosts: candidateHosts,
          snapshot: hostSnapshot,
          isRefreshing: isRefreshingHosts,
          onRefresh: onRefreshHosts,
          onUseAutomaticSelection: onUseAutomaticHostSelection,
          onSelectHost: onSelectHost,
        ),
      );
    }

    sections.add(const SizedBox(height: 18));
    sections.add(
      _AppearanceSettingsCard(
        themePreference: themePreference,
        onChanged: onThemePreferenceChanged,
      ),
    );

    if (afterContinueReading != null) {
      sections.add(const SizedBox(height: 18));
      sections.add(afterContinueReading!);
    }

    if (cachedComicCards.isNotEmpty) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        _SectionCard(
          title: '已缓存漫画',
          action: _SectionActionButton(
            semanticLabel: '查看全部缓存',
            onTap: onOpenCachedComicPage,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionCaption('共 ${cachedComicCards.length} 部漫画'),
              const SizedBox(height: 14),
              SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cachedComicCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = cachedComicCards[index];
                    return SizedBox(
                      width: 136,
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

    if (!page.isLoggedIn || page.user == null) {
      return Column(children: sections);
    }

    if (page.continueReading != null) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        _SectionCard(
          title: '继续阅读',
          child: _HistoryTile(
            item: page.continueReading!,
            onTap: () => onOpenHistory(page.continueReading!),
          ),
        ),
      );
    }
    if (page.collections.isNotEmpty) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        _SectionCard(
          title: '我的收藏',
          action: _SectionActionButton(
            semanticLabel: '查看全部收藏',
            onTap: onOpenCollections,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionCaption('共 ${collectionCards.length} 部漫画'),
              const SizedBox(height: 14),
              SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: collectionCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = collectionCards[index];
                    return SizedBox(
                      width: 136,
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
    if (page.history.isNotEmpty) {
      sections.add(const SizedBox(height: 18));
      sections.add(
        _SectionCard(
          title: '浏览历史',
          action: _SectionActionButton(
            semanticLabel: '查看全部历史',
            onTap: onOpenHistoryPage,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionCaption('最近浏览 ${historyCards.length} 条记录'),
              const SizedBox(height: 14),
              SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: historyCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final ComicCardData item = historyCards[index];
                    return SizedBox(
                      width: 136,
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
    return Column(children: sections);
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

  Widget _buildComicCollectionSection(
    BuildContext context, {
    required String title,
    required String summary,
    required List<ComicCardData> items,
    required String emptyMessage,
    required ValueChanged<String> onTap,
    ValueChanged<String>? onLongPress,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ComicGrid(
            items: items,
            onTap: onTap,
            onLongPress: onLongPress,
            emptyMessage: emptyMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedOutCard() {
    return _SectionCard(
      child: Column(
        children: <Widget>[
          const Icon(Icons.person_outline_rounded, size: 48),
          const SizedBox(height: 14),
          Text(
            page.message.isEmpty ? '登录后可查看收藏与历史。' : page.message,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.6),
          ),
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

  Widget _buildUserCard(BuildContext context, ProfileUserData user) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _AvatarImage(imageUrl: user.avatarUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.username,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (user.createdAt.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '注册于 ${user.createdAt}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.62),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          if (user.membershipLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                user.membershipLabel,
                style: TextStyle(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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
    required this.candidateHosts,
    required this.snapshot,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
  });

  final String currentHost;
  final List<String> candidateHosts;
  final HostProbeSnapshot? snapshot;
  final bool isRefreshing;
  final FutureOr<void> Function()? onRefresh;
  final FutureOr<void> Function()? onUseAutomaticSelection;
  final FutureOr<void> Function(String value)? onSelectHost;

  @override
  Widget build(BuildContext context) {
    final String? pinnedHost = snapshot?.sessionPinnedHost
        ?.trim()
        .toLowerCase();

    return AppSurfaceCard(
      title: '节点设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            pinnedHost == null
                ? '管理备用网址测速、自动选择和手动切换。'
                : '当前已手动锁定节点，可进入二级页面恢复自动选择或切换其他节点。',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) {
                      return _HostSettingsPage(
                        currentHost: currentHost,
                        candidateHosts: candidateHosts,
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
              label: const Text('管理节点'),
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
    required this.candidateHosts,
    required this.snapshot,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
  });

  final String currentHost;
  final List<String> candidateHosts;
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
    final String recommendedHost =
        _snapshot?.selectedHost.trim().toLowerCase() ?? '';
    final Map<String, HostProbeRecord> probes = <String, HostProbeRecord>{
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        probe.host.trim().toLowerCase(): probe,
    };
    final Set<String> seenHosts = <String>{};
    final List<String> hosts = <String>[
      for (final String rawHost in widget.candidateHosts)
        if (rawHost.trim().isNotEmpty &&
            seenHosts.add(rawHost.trim().toLowerCase()))
          rawHost.trim().toLowerCase(),
      if (normalizedCurrentHost.isNotEmpty &&
          seenHosts.add(normalizedCurrentHost))
        normalizedCurrentHost,
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        if (probe.host.trim().isNotEmpty &&
            seenHosts.add(probe.host.trim().toLowerCase()))
          probe.host.trim().toLowerCase(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('节点设置')),
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
                              label: '当前节点',
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
                  const SizedBox(height: 14),
                  Text(
                    pinnedHost == null
                        ? '当前使用自动选择。点击下方节点可手动锁定。'
                        : '当前已手动锁定到 $pinnedHost。点击其他节点可立即切换。',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.72),
                      height: 1.5,
                    ),
                  ),
                  if (pinnedHost != null &&
                      widget.onUseAutomaticSelection != null) ...<Widget>[
                    const SizedBox(height: 12),
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
                  '还没有可用的节点信息。',
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
                            isCurrent: host == normalizedCurrentHost,
                            isPinned: host == pinnedHost,
                            isRecommended:
                                recommendedHost.isNotEmpty &&
                                host == recommendedHost &&
                                host != normalizedCurrentHost,
                            enabled: !_isBusy && widget.onSelectHost != null,
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
      if (_currentHost.isNotEmpty) _currentHost,
      for (final String host in widget.candidateHosts)
        if (_normalizeHostValue(host).isNotEmpty) _normalizeHostValue(host),
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        if (_normalizeHostValue(probe.host).isNotEmpty)
          _normalizeHostValue(probe.host),
    };
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
    required this.isCurrent,
    required this.isPinned,
    required this.isRecommended,
    required this.enabled,
    this.probe,
    this.onTap,
  });

  final String host;
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
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isCurrent
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
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
    return '测速失败';
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

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
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

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const CircleAvatar(radius: 28, child: Icon(Icons.person_rounded));
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        cacheManager: EasyCopyImageCaches.coverCache,
        errorWidget: (_, __, ___) {
          return const CircleAvatar(
            radius: 28,
            child: Icon(Icons.person_rounded),
          );
        },
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
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: item.coverUrl.isEmpty
                  ? const _PlaceholderBox()
                  : CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheManager: EasyCopyImageCaches.coverCache,
                      errorWidget: (_, __, ___) => const _PlaceholderBox(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: item.coverUrl.isEmpty
                    ? const _PlaceholderBox()
                    : CachedNetworkImage(
                        imageUrl: item.coverUrl,
                        fit: BoxFit.cover,
                        cacheManager: EasyCopyImageCaches.coverCache,
                        errorWidget: (_, __, ___) => const _PlaceholderBox(),
                      ),
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

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: colorScheme.onSurface.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}
