part of '../download_management_page.dart';

class _StorageSection extends StatefulWidget {
  const _StorageSection({
    required this.state,
    required this.busy,
    required this.migrationProgress,
    required this.supportsCustomDirs,
    this.onPickStorageDirectory,
    this.onResetStorageDirectory,
    this.onRescanStorageDirectory,
  });

  final DownloadStorageState state;
  final bool busy;
  final StorageMigrationProgress? migrationProgress;
  final bool supportsCustomDirs;
  final VoidCallback? onPickStorageDirectory;
  final VoidCallback? onResetStorageDirectory;
  final AsyncValueGetter<String>? onRescanStorageDirectory;

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  bool _isRescanning = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool canEdit =
        !widget.busy && widget.migrationProgress == null && !_isRescanning;
    final bool canRescan =
        canEdit &&
        widget.state.isReady &&
        widget.onRescanStorageDirectory != null;
    final String pathLabel =
        widget.migrationProgress?.toPath.trim().isNotEmpty == true
        ? widget.migrationProgress!.toPath
        : widget.state.displayPath;

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '缓存目录',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    pathLabel.isEmpty ? '当前目录不可用' : pathLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.state.isLoading && widget.migrationProgress == null)
            const Text('正在读取缓存目录…')
          else if (widget.state.errorMessage.isNotEmpty)
            Text(
              widget.state.errorMessage,
              style: TextStyle(color: colorScheme.error, height: 1.4),
            ),
          if (widget.supportsCustomDirs) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: canEdit ? widget.onPickStorageDirectory : null,
                    icon: widget.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.drive_folder_upload_rounded),
                    label: Text(widget.state.isCustom ? '更换位置' : '选择目录'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canRescan
                        ? () => _handleRescanStorageDirectory(context)
                        : null,
                    icon: _isRescanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.manage_search_rounded),
                    label: Text(_isRescanning ? '扫描中…' : '扫描当前目录'),
                  ),
                ),
              ],
            ),
            if (widget.state.isCustom && widget.onResetStorageDirectory != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: canEdit ? widget.onResetStorageDirectory : null,
                  child: const Text('恢复默认'),
                ),
              ),
          ],
          if (widget.migrationProgress != null) ...<Widget>[
            const SizedBox(height: 14),
            _MigrationProgressPanel(progress: widget.migrationProgress!),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRescanStorageDirectory(BuildContext context) async {
    final AsyncValueGetter<String>? callback = widget.onRescanStorageDirectory;
    if (callback == null || _isRescanning) {
      return;
    }
    setState(() {
      _isRescanning = true;
    });
    try {
      final String message = await callback();
      if (!context.mounted || message.trim().isEmpty) {
        return;
      }
      TopNotice.show(context, message, tone: _toneForMessage(message));
    } catch (error) {
      if (context.mounted) {
        TopNotice.show(context, error.toString(), tone: TopNoticeTone.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRescanning = false;
        });
      }
    }
  }

  TopNoticeTone _toneForMessage(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.contains('未发现')) {
      return TopNoticeTone.warning;
    }
    if (normalized.contains('恢复') || normalized.contains('已')) {
      return TopNoticeTone.success;
    }
    return TopNoticeTone.info;
  }
}

class _MigrationProgressPanel extends StatelessWidget {
  const _MigrationProgressPanel({required this.progress});

  final StorageMigrationProgress progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String title = switch (progress.phase) {
      DownloadStorageMigrationPhase.preparing => '准备迁移',
      DownloadStorageMigrationPhase.migrating => '迁移缓存中',
      DownloadStorageMigrationPhase.cleaning => '清理旧目录',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.sync_rounded, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(progress.message, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.folder_open_rounded,
            text: '来源：${progress.fromPath}',
            color: colorScheme.secondary,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.drive_folder_upload_rounded,
            text: '目标：${progress.toPath}',
            color: colorScheme.secondary,
          ),
          if (progress.currentItemPath.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.description_outlined,
              text: progress.currentItemPath,
              color: colorScheme.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DownloadQueueTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ({Color background, Color foreground, String label}) config =
        switch (status) {
          DownloadQueueTaskStatus.queued => (
            background: colorScheme.surfaceContainerHighest,
            foreground: colorScheme.onSurface,
            label: '等待中',
          ),
          DownloadQueueTaskStatus.parsing => (
            background: colorScheme.secondaryContainer,
            foreground: colorScheme.onSecondaryContainer,
            label: '解析中',
          ),
          DownloadQueueTaskStatus.downloading => (
            background: colorScheme.primaryContainer,
            foreground: colorScheme.onPrimaryContainer,
            label: '下载中',
          ),
          DownloadQueueTaskStatus.paused => (
            background: colorScheme.tertiaryContainer,
            foreground: colorScheme.onTertiaryContainer,
            label: '已暂停',
          ),
          DownloadQueueTaskStatus.failed => (
            background: colorScheme.errorContainer,
            foreground: colorScheme.onErrorContainer,
            label: '失败',
          ),
        };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          config.label,
          style: TextStyle(
            color: config.foreground,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.76),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

enum _QueueMenuAction { retry, removeCurrent, removeQueue, removeQueueAndCache }

enum _CachedMenuAction { export, delete }

class _QueuedComicGroup {
  _QueuedComicGroup(this.task);

  final DownloadQueueTask task;
  DownloadQueueTask? activeTask;
  DownloadQueueTask? failedTask;
  int taskCount = 0;
  int queuedCount = 0;
  int failedCount = 0;

  void add(DownloadQueueTask value) {
    taskCount++;
    switch (value.status) {
      case DownloadQueueTaskStatus.queued:
        queuedCount++;
      case DownloadQueueTaskStatus.parsing:
      case DownloadQueueTaskStatus.downloading:
        activeTask ??= value;
      case DownloadQueueTaskStatus.failed:
        failedTask ??= value;
        failedCount++;
      case DownloadQueueTaskStatus.paused:
        break;
    }
  }

  DownloadQueueTask? get singleTask => taskCount == 1 ? task : null;
  DownloadQueueTask get primaryTask => activeTask ?? failedTask ?? task;
  DownloadQueueTaskStatus get status => primaryTask.status;
  String get primaryChapterLabel => primaryTask.chapterLabel;

  String get summary {
    final List<String> fragments = <String>[];
    if (queuedCount > 0) {
      fragments.add('$queuedCount 话等待中');
    }
    if (failedCount > 0) {
      fragments.add('$failedCount 话失败');
    }
    final DownloadQueueTask? runningTask = activeTask;
    if (runningTask != null && runningTask.progressLabel.trim().isNotEmpty) {
      fragments.insert(0, runningTask.progressLabel);
    }
    if (fragments.isEmpty) {
      return '$taskCount 话待处理';
    }
    return fragments.join(' · ');
  }
}

List<_QueuedComicGroup> _groupQueue(List<DownloadQueueTask> tasks) {
  final grouped = <String, _QueuedComicGroup>{};
  for (final task in tasks) {
    grouped.putIfAbsent(task.comicKey, () => _QueuedComicGroup(task)).add(task);
  }
  return grouped.values.toList(growable: false);
}

Set<String> _cachedComicKeys(List<CachedComicLibraryEntry> comics) {
  final result = <String>{};
  for (final CachedComicLibraryEntry entry in comics) {
    final Uri? uri = Uri.tryParse(entry.comicHref);
    if (uri == null) {
      continue;
    }
    result.add(Uri(path: uri.path).toString());
  }
  return result;
}
