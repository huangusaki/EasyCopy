part of '../profile_page_view.dart';

class _HostSettingsEntryRow extends StatelessWidget {
  const _HostSettingsEntryRow({
    required this.manager,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
    this.onAddHost,
    this.onDeleteHost,
  });

  final HostManager manager;
  final bool isRefreshing;
  final FutureOr<void> Function()? onRefresh;
  final FutureOr<void> Function()? onUseAutomaticSelection;
  final FutureOr<void> Function(String value)? onSelectHost;
  final FutureOr<String> Function(String value)? onAddHost;
  final FutureOr<void> Function(String value)? onDeleteHost;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) => _SettingsEntryRow(
        label: '访问域名',
        valueLabel: manager.currentHost.isEmpty ? '自动选择' : manager.currentHost,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) {
                return _HostSettingsPage(
                  manager: manager,
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
    required this.manager,
    required this.isRefreshing,
    this.onRefresh,
    this.onUseAutomaticSelection,
    this.onSelectHost,
    this.onAddHost,
    this.onDeleteHost,
  });

  final HostManager manager;
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
  final TextEditingController _customHostController = TextEditingController();
  bool _isBusy = false;
  late bool _isRefreshing = widget.isRefreshing;
  String? _selectingHost;
  bool _selectingAutomatic = false;

  @override
  void dispose() {
    _customHostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.manager,
    builder: (context, _) => _buildSettings(context),
  );

  Widget _buildSettings(BuildContext context) {
    final HostManager manager = widget.manager;
    final HostProbeSnapshot? snapshot = manager.probeSnapshot;
    final String recommendedHost = snapshot?.selectedHost ?? '';
    final String normalizedCurrentHost =
        _selectingHost ??
        (_selectingAutomatic && recommendedHost.isNotEmpty
            ? recommendedHost
            : manager.currentHost);
    final String? pinnedHost = _selectingAutomatic
        ? null
        : _selectingHost ?? manager.sessionPinnedHost;
    final String normalizedPinnedHost = pinnedHost ?? '';
    final Map<String, List<String>> aliasGroups = manager.candidateHostAliases;
    final Map<String, String> canonicalHostByAlias = <String, String>{
      for (final MapEntry<String, List<String>> entry in aliasGroups.entries)
        entry.key: entry.key,
      for (final MapEntry<String, List<String>> entry in aliasGroups.entries)
        for (final String alias in entry.value) alias: entry.key,
    };
    String canonical(String host) => canonicalHostByAlias[host] ?? host;
    final Map<String, HostProbeRecord> probes = <String, HostProbeRecord>{};
    for (final probe in snapshot?.probes ?? const <HostProbeRecord>[]) {
      final key = canonical(probe.host);
      final current = probes[key];
      if (current == null ||
          (probe.success && !current.success) ||
          (probe.success == current.success &&
              probe.latencyMs < current.latencyMs)) {
        probes[key] = probe;
      }
    }
    final normalizedCurrentKey = canonical(normalizedCurrentHost);
    final normalizedPinnedKey = canonical(normalizedPinnedHost);
    final recommendedKey = canonical(recommendedHost);
    final hostOrder = <String, int>{};
    for (final host in [
      ...manager.candidateHosts,
      ...manager.knownHosts,
      ...probes.keys,
      normalizedCurrentKey,
      normalizedPinnedKey,
      recommendedKey,
    ]) {
      if (host.isNotEmpty) {
        hostOrder.putIfAbsent(canonical(host), () => hostOrder.length);
      }
    }
    final hosts = hostOrder.keys.toList()
      ..sort((left, right) {
        final rank = _hostDisplayRank(
          probes[left],
        ).compareTo(_hostDisplayRank(probes[right]));
        return rank != 0 ? rank : hostOrder[left]!.compareTo(hostOrder[right]!);
      });

    return SettingsPageScaffold(
      title: '访问域名',
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
                            if (snapshot != null)
                              _HostSummaryChip(
                                label: '最近测速',
                                value: _formatCheckedAt(snapshot.checkedAt),
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

  int _hostDisplayRank(HostProbeRecord? probe) {
    if (probe == null) {
      return 2;
    }
    return probe.success ? 0 : 1;
  }

  Future<void> _runBusyAction(
    FutureOr<void> Function() action, {
    bool refreshing = false,
    String? selectingHost,
    bool selectingAutomatic = false,
  }) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _isRefreshing = refreshing;
      _selectingHost = selectingHost;
      _selectingAutomatic = selectingAutomatic;
    });
    try {
      await action();
    } catch (_) {
      // 操作入口已经向用户展示错误，页面重新读取管理器中的实际状态。
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isRefreshing = false;
          _selectingHost = null;
          _selectingAutomatic = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() =>
      _runBusyAction(() => widget.onRefresh?.call(), refreshing: true);

  Future<void> _handleAddHost() async {
    final input = _customHostController.text.trim();
    if (input.isEmpty || widget.onAddHost == null) return;
    await _runBusyAction(() async {
      final result = await widget.onAddHost!(input);
      if (mounted && result.isNotEmpty) _customHostController.clear();
    });
  }

  Future<void> _confirmDeleteHost(String host) async {
    if (host.isEmpty || widget.onDeleteHost == null) {
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
    if (confirmed && mounted) {
      await _runBusyAction(() => widget.onDeleteHost!(host));
    }
  }

  Future<void> _handleUseAutomaticSelection() => _runBusyAction(
    () => widget.onUseAutomaticSelection?.call(),
    selectingAutomatic: true,
  );

  Future<void> _handleSelectHost(String host) => _runBusyAction(
    () => widget.onSelectHost?.call(host),
    selectingHost: host,
  );
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
