part of '../profile_page_view.dart';

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
    this.onAddHost,
    this.onDeleteHost,
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
  final FutureOr<String> Function(String value)? onAddHost;
  final FutureOr<void> Function(String value)? onDeleteHost;

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
                        onAddHost: onAddHost,
                        onDeleteHost: onDeleteHost,
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
    this.onAddHost,
    this.onDeleteHost,
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
  final FutureOr<String> Function(String value)? onAddHost;
  final FutureOr<void> Function(String value)? onDeleteHost;

  @override
  State<_HostSettingsPage> createState() => _HostSettingsPageState();
}

class _HostSettingsPageState extends State<_HostSettingsPage> {
  static const Object _snapshotSentinel = Object();

  late String _currentHost;
  late HostProbeSnapshot? _snapshot;
  late bool _isRefreshing;
  final TextEditingController _customHostController = TextEditingController();
  final Set<String> _localHosts = <String>{};
  final Set<String> _deletedHosts = <String>{};
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _currentHost = _normalizeHostValue(widget.currentHost);
    _snapshot = _normalizeSnapshot(widget.snapshot);
    _isRefreshing = widget.isRefreshing;
    _syncLocalHostsFromWidget();
  }

  @override
  void dispose() {
    _customHostController.dispose();
    super.dispose();
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
      _syncLocalHostsFromWidget();
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
    final Map<String, List<HostProbeRecord>> probesByCanonicalHost =
        <String, List<HostProbeRecord>>{};
    for (final HostProbeRecord probe
        in _snapshot?.probes ?? const <HostProbeRecord>[]) {
      final String normalizedProbeHost = _normalizeHostValue(probe.host);
      if (normalizedProbeHost.isEmpty || _isDeletedHost(normalizedProbeHost)) {
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
    final String normalizedCurrentKey = _canonicalActiveHost(
      normalizedCurrentHost,
      canonicalHostByAlias,
    );
    final String normalizedPinnedKey = _canonicalActiveHost(
      normalizedPinnedHost,
      canonicalHostByAlias,
    );
    final String recommendedKey = _canonicalActiveHost(
      recommendedHost,
      canonicalHostByAlias,
    );
    final Set<String> seenHosts = <String>{};
    final List<String> rawHosts = <String>[
      ...aliasGroups.keys,
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
      backgroundColor: opaquePageBackground(context),
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
            AppSurfaceCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _customHostController,
                      enabled: !_isBusy && widget.onAddHost != null,
                      decoration: const InputDecoration(
                        labelText: '新增域名',
                        hintText: 'example.com',
                        prefixIcon: Icon(Icons.add_link_rounded),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleAddHost(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _isBusy || widget.onAddHost == null
                        ? null
                        : _handleAddHost,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加'),
                  ),
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
                            enabled: !_isBusy && widget.onSelectHost != null,
                            canDelete:
                                !_isBusy &&
                                widget.onDeleteHost != null &&
                                hosts.length > 1,
                            onTap: widget.onSelectHost == null
                                ? null
                                : () => _handleSelectHost(host),
                            onDelete: widget.onDeleteHost == null
                                ? null
                                : () => _confirmDeleteHost(host),
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

  String _activeHostValue(String value) {
    final String normalizedHost = _normalizeHostValue(value);
    if (normalizedHost.isEmpty || _isDeletedHost(normalizedHost)) {
      return '';
    }
    return normalizedHost;
  }

  bool _isDeletedHost(String host) {
    return _deletedHosts.contains(_normalizeHostValue(host));
  }

  String _canonicalActiveHost(
    String host,
    Map<String, String> canonicalHostByAlias,
  ) {
    final String activeHost = _activeHostValue(host);
    if (activeHost.isEmpty) {
      return '';
    }
    return _activeHostValue(canonicalHostByAlias[activeHost] ?? activeHost);
  }

  void _syncLocalHostsFromWidget() {
    _localHosts.addAll(_widgetHosts());
    _localHosts.removeWhere(_isDeletedHost);
  }

  Set<String> _widgetHosts() {
    final Set<String> hosts = <String>{};
    void addHost(String value) {
      final String activeHost = _activeHostValue(value);
      if (activeHost.isNotEmpty) {
        hosts.add(activeHost);
      }
    }

    for (final String host in widget.knownHosts) {
      addHost(host);
    }
    for (final String host in widget.candidateHosts) {
      addHost(host);
    }
    for (final MapEntry<String, List<String>> entry
        in widget.candidateHostAliases.entries) {
      addHost(entry.key);
      for (final String alias in entry.value) {
        addHost(alias);
      }
    }
    for (final HostProbeRecord probe
        in _snapshot?.probes ?? const <HostProbeRecord>[]) {
      addHost(probe.host);
    }
    addHost(_currentHost);
    return hosts;
  }

  Map<String, List<String>> _normalizedAliasGroups(
    List<String> candidateHosts,
    Map<String, List<String>> candidateHostAliases,
  ) {
    final Map<String, List<String>> normalizedGroups = <String, List<String>>{};
    for (final MapEntry<String, List<String>> entry
        in candidateHostAliases.entries) {
      final String normalizedPrimary = _activeHostValue(entry.key);
      if (normalizedPrimary.isEmpty) {
        continue;
      }
      final List<String> aliases = <String>[];
      final Set<String> seenAliases = <String>{normalizedPrimary};
      for (final String alias in entry.value) {
        final String normalizedAlias = _activeHostValue(alias);
        if (normalizedAlias.isEmpty || !seenAliases.add(normalizedAlias)) {
          continue;
        }
        aliases.add(normalizedAlias);
      }
      normalizedGroups[normalizedPrimary] = aliases;
    }
    for (final String host in candidateHosts) {
      final String normalizedHost = _activeHostValue(host);
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
    final Set<String> hosts = _widgetHosts();
    for (final String host in _localHosts) {
      final String activeHost = _activeHostValue(host);
      if (activeHost.isNotEmpty) {
        hosts.add(activeHost);
      }
    }
    return hosts;
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

  Future<void> _handleAddHost() async {
    final FutureOr<String> Function(String value)? onAddHost =
        widget.onAddHost;
    if (onAddHost == null) {
      return;
    }
    final String input = _customHostController.text.trim();
    if (input.isEmpty) {
      return;
    }
    await _runBusyAction(() async {
      final String normalizedHost = _normalizeHostValue(await onAddHost(input));
      if (normalizedHost.isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _deletedHosts.remove(normalizedHost);
        _localHosts.add(normalizedHost);
        _customHostController.clear();
      });
      _syncFromHostManager();
    });
  }

  Future<void> _confirmDeleteHost(String host) async {
    final String normalizedHost = _normalizeHostValue(host);
    if (normalizedHost.isEmpty || widget.onDeleteHost == null) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('删除域名'),
              content: const Text('操作不可逆，确定删除？'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _handleDeleteHost(normalizedHost);
  }

  Future<void> _handleDeleteHost(String host) async {
    final FutureOr<void> Function(String value)? onDeleteHost =
        widget.onDeleteHost;
    if (onDeleteHost == null) {
      return;
    }
    final String normalizedHost = _normalizeHostValue(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    final String previousCurrentHost = _currentHost;
    final HostProbeSnapshot? previousSnapshot = _snapshot;
    final Set<String> previousLocalHosts = Set<String>.from(_localHosts);
    await _runBusyAction(() async {
      try {
        await onDeleteHost(normalizedHost);
        if (!mounted) {
          return;
        }
        setState(() {
          _deletedHosts.add(normalizedHost);
          _localHosts.remove(normalizedHost);
          if (_currentHost == normalizedHost) {
            _currentHost = _localHosts.isEmpty ? '' : _localHosts.first;
          }
          _snapshot = _copySnapshot(
            selectedHost: _currentHost,
            pinnedHost: _snapshot?.sessionPinnedHost == normalizedHost
                ? null
                : _snapshotSentinel,
          );
        });
        _syncFromHostManager();
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentHost = previousCurrentHost;
          _snapshot = previousSnapshot;
          _localHosts
            ..clear()
            ..addAll(previousLocalHosts);
        });
      }
    });
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
    required this.canDelete,
    this.probe,
    this.onTap,
    this.onDelete,
  });

  final String host;
  final List<String> aliases;
  final HostProbeRecord? probe;
  final bool isCurrent;
  final bool isPinned;
  final bool isRecommended;
  final bool enabled;
  final bool canDelete;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '删除',
                  onPressed: canDelete ? onDelete : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
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
