import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:easy_copy/widgets/top_notice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DownloadManagementEntryCard extends StatelessWidget {
  const DownloadManagementEntryCard({
    required this.statusLabel,
    required this.queueLabel,
    required this.onTap,
    this.noteLabel,
    super.key,
  });

  final String statusLabel;
  final String queueLabel;
  final String? noteLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '下载管理',
      action: Text(
        '状态 $statusLabel · 队列 $queueLabel',
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.58),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (noteLabel != null && noteLabel!.trim().isNotEmpty) ...<Widget>[
            _InfoRow(
              icon: Icons.sync_rounded,
              text: noteLabel!,
              color: colorScheme.secondary,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onTap,
              icon: const Icon(Icons.download_rounded),
              label: const Text('打开下载管理'),
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadManagementPage extends StatefulWidget {
  const DownloadManagementPage({
    required this.queueListenable,
    required this.storageStateListenable,
    required this.storageBusyListenable,
    required this.migrationProgressListenable,
    required this.cachedComics,
    required this.onOpenCachedComic,
    required this.onDeleteCachedComic,
    required this.supportsCustomDirectorySelection,
    required this.onPauseQueue,
    required this.onResumeQueue,
    required this.onClearQueue,
    required this.onStopComicTasks,
    required this.onRemoveComic,
    required this.onRemoveTask,
    required this.onRetryTask,
    this.onPickStorageDirectory,
    this.onResetStorageDirectory,
    this.onRescanStorageDirectory,
    super.key,
  });

  final ValueListenable<DownloadQueueSnapshot> queueListenable;
  final ValueListenable<DownloadStorageState> storageStateListenable;
  final ValueListenable<bool> storageBusyListenable;
  final ValueListenable<DownloadStorageMigrationProgress?>
  migrationProgressListenable;
  final List<CachedComicLibraryEntry> cachedComics;
  final ValueChanged<CachedComicLibraryEntry> onOpenCachedComic;
  final ValueChanged<CachedComicLibraryEntry> onDeleteCachedComic;
  final bool supportsCustomDirectorySelection;
  final VoidCallback onPauseQueue;
  final VoidCallback onResumeQueue;
  final VoidCallback onClearQueue;
  final ValueChanged<DownloadQueueTask> onStopComicTasks;
  final ValueChanged<DownloadQueueTask> onRemoveComic;
  final ValueChanged<DownloadQueueTask> onRemoveTask;
  final ValueChanged<DownloadQueueTask> onRetryTask;
  final VoidCallback? onPickStorageDirectory;
  final VoidCallback? onResetStorageDirectory;
  final AsyncValueGetter<String>? onRescanStorageDirectory;

  @override
  State<DownloadManagementPage> createState() => _DownloadManagementPageState();
}

class _DownloadManagementPageState extends State<DownloadManagementPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: SafeArea(
        child: ValueListenableBuilder<DownloadQueueSnapshot>(
          valueListenable: widget.queueListenable,
          builder: (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
            return ValueListenableBuilder<DownloadStorageState>(
              valueListenable: widget.storageStateListenable,
              builder:
                  (
                    BuildContext context,
                    DownloadStorageState storageState,
                    Widget? _,
                  ) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.storageBusyListenable,
                      builder:
                          (BuildContext context, bool storageBusy, Widget? _) {
                            return ValueListenableBuilder<
                              DownloadStorageMigrationProgress?
                            >(
                              valueListenable:
                                  widget.migrationProgressListenable,
                              builder:
                                  (
                                    BuildContext context,
                                    DownloadStorageMigrationProgress?
                                    migrationProgress,
                                    Widget? _,
                                  ) {
                                    final Map<String, CachedComicLibraryEntry>
                                    cachedComicMap = _cachedComicMap(
                                      widget.cachedComics,
                                    );
                                    return ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        28,
                                      ),
                                      children: <Widget>[
                                        _CurrentTaskSection(
                                          snapshot: snapshot,
                                          onPauseQueue: widget.onPauseQueue,
                                          onResumeQueue: widget.onResumeQueue,
                                        ),
                                        const SizedBox(height: 16),
                                        _QueueSection(
                                          snapshot: snapshot,
                                          cachedComicMap: cachedComicMap,
                                          onClearQueue: widget.onClearQueue,
                                          onStopComicTasks:
                                              widget.onStopComicTasks,
                                          onRemoveComic: widget.onRemoveComic,
                                          onRemoveTask: widget.onRemoveTask,
                                          onRetryTask: widget.onRetryTask,
                                        ),
                                        const SizedBox(height: 16),
                                        _CachedLibrarySection(
                                          comics: widget.cachedComics,
                                          onOpenCachedComic:
                                              widget.onOpenCachedComic,
                                          onDeleteCachedComic:
                                              widget.onDeleteCachedComic,
                                        ),
                                        const SizedBox(height: 16),
                                        _StorageSection(
                                          state: storageState,
                                          busy: storageBusy,
                                          migrationProgress: migrationProgress,
                                          supportsCustomDirectorySelection: widget
                                              .supportsCustomDirectorySelection,
                                          onPickStorageDirectory:
                                              widget.onPickStorageDirectory,
                                          onResetStorageDirectory:
                                              widget.onResetStorageDirectory,
                                          onRescanStorageDirectory:
                                              widget.onRescanStorageDirectory,
                                        ),
                                      ],
                                    );
                                  },
                            );
                          },
                    );
                  },
            );
          },
        ),
      ),
    );
  }
}

class _CurrentTaskSection extends StatelessWidget {
  const _CurrentTaskSection({
    required this.snapshot,
    required this.onPauseQueue,
    required this.onResumeQueue,
  });

  final DownloadQueueSnapshot snapshot;
  final VoidCallback onPauseQueue;
  final VoidCallback onResumeQueue;

  @override
  Widget build(BuildContext context) {
    final DownloadQueueTask? activeTask = snapshot.activeTask;
    if (activeTask == null) {
      return const AppSurfaceCard(title: '当前任务', child: Text('队列空闲。'));
    }
    return AppSurfaceCard(
      title: '当前任务',
      action: FilledButton.tonal(
        onPressed: snapshot.isPaused ? onResumeQueue : onPauseQueue,
        child: Text(snapshot.isPaused ? '继续' : '暂停'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            activeTask.comicTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            activeTask.chapterLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.74),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            activeTask.progressLabel.isEmpty
                ? (snapshot.isPaused ? '队列已暂停' : '准备缓存')
                : activeTask.progressLabel,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: activeTask.fraction > 0 ? activeTask.fraction : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({
    required this.snapshot,
    required this.cachedComicMap,
    required this.onClearQueue,
    required this.onStopComicTasks,
    required this.onRemoveComic,
    required this.onRemoveTask,
    required this.onRetryTask,
  });

  final DownloadQueueSnapshot snapshot;
  final Map<String, CachedComicLibraryEntry> cachedComicMap;
  final VoidCallback onClearQueue;
  final ValueChanged<DownloadQueueTask> onStopComicTasks;
  final ValueChanged<DownloadQueueTask> onRemoveComic;
  final ValueChanged<DownloadQueueTask> onRemoveTask;
  final ValueChanged<DownloadQueueTask> onRetryTask;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isEmpty) {
      return const AppSurfaceCard(title: '缓存队列', child: Text('当前没有待处理章节。'));
    }
    final List<_QueuedComicGroup> groups = _groupQueue(snapshot.tasks);
    return AppSurfaceCard(
      title: '缓存队列',
      action: TextButton(onPressed: onClearQueue, child: const Text('清空')),
      child: Column(
        children: groups
            .map((_QueuedComicGroup group) {
              final CachedComicLibraryEntry? cachedComic =
                  cachedComicMap[group.task.comicKey];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: identical(group, groups.last) ? 0 : 12,
                ),
                child: _QueueGroupRow(
                  group: group,
                  hasCachedContent: cachedComic != null,
                  onStopComicTasks: () => onStopComicTasks(group.task),
                  onRemoveComic: () => onRemoveComic(group.task),
                  onRemoveTask: group.singleTask == null
                      ? null
                      : () => onRemoveTask(group.singleTask!),
                  onRetryTask: group.failedTask == null
                      ? null
                      : () => onRetryTask(group.failedTask!),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _QueueGroupRow extends StatelessWidget {
  const _QueueGroupRow({
    required this.group,
    required this.hasCachedContent,
    required this.onStopComicTasks,
    this.onRemoveComic,
    this.onRemoveTask,
    this.onRetryTask,
  });

  final _QueuedComicGroup group;
  final bool hasCachedContent;
  final VoidCallback onStopComicTasks;
  final VoidCallback? onRemoveComic;
  final VoidCallback? onRemoveTask;
  final VoidCallback? onRetryTask;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${group.taskCount}',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.task.comicTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  group.primaryChapterLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  group.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _StatusBadge(status: group.status),
              PopupMenuButton<_QueueMenuAction>(
                tooltip: '更多操作',
                onSelected: (_QueueMenuAction action) {
                  switch (action) {
                    case _QueueMenuAction.retry:
                      onRetryTask?.call();
                      break;
                    case _QueueMenuAction.removeCurrent:
                      onRemoveTask?.call();
                      break;
                    case _QueueMenuAction.removeQueue:
                      onStopComicTasks();
                      break;
                    case _QueueMenuAction.removeQueueAndCache:
                      onRemoveComic?.call();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) {
                  return <PopupMenuEntry<_QueueMenuAction>>[
                    if (onRetryTask != null)
                      const PopupMenuItem<_QueueMenuAction>(
                        value: _QueueMenuAction.retry,
                        child: Text('重试失败章节'),
                      ),
                    if (onRemoveTask != null)
                      const PopupMenuItem<_QueueMenuAction>(
                        value: _QueueMenuAction.removeCurrent,
                        child: Text('移除当前章节'),
                      ),
                    const PopupMenuItem<_QueueMenuAction>(
                      value: _QueueMenuAction.removeQueue,
                      child: Text('移出队列'),
                    ),
                    if (hasCachedContent && onRemoveComic != null)
                      const PopupMenuItem<_QueueMenuAction>(
                        value: _QueueMenuAction.removeQueueAndCache,
                        child: Text('删除缓存并移出队列'),
                      ),
                  ];
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CachedLibrarySection extends StatelessWidget {
  const _CachedLibrarySection({
    required this.comics,
    required this.onOpenCachedComic,
    required this.onDeleteCachedComic,
  });

  final List<CachedComicLibraryEntry> comics;
  final ValueChanged<CachedComicLibraryEntry> onOpenCachedComic;
  final ValueChanged<CachedComicLibraryEntry> onDeleteCachedComic;

  @override
  Widget build(BuildContext context) {
    if (comics.isEmpty) {
      return const AppSurfaceCard(title: '已缓存', child: Text('还没有已缓存漫画。'));
    }
    final List<CachedComicLibraryEntry> visibleComics = comics
        .take(8)
        .toList(growable: false);
    return AppSurfaceCard(
      title: '已缓存',
      child: Column(
        children: visibleComics
            .map((CachedComicLibraryEntry entry) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: identical(entry, visibleComics.last) ? 0 : 12,
                ),
                child: _CachedComicRow(
                  entry: entry,
                  onTap: () => onOpenCachedComic(entry),
                  onDelete: () => onDeleteCachedComic(entry),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _CachedComicRow extends StatelessWidget {
  const _CachedComicRow({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final CachedComicLibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String latestChapterTitle = entry.chapters.isEmpty
        ? '暂无章节'
        : entry.chapters.first.chapterTitle;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.comicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestChapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${entry.cachedChapterCount} 话已缓存',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CachedMenuAction>(
                tooltip: '更多操作',
                onSelected: (_CachedMenuAction action) {
                  if (action == _CachedMenuAction.delete) {
                    onDelete();
                  }
                },
                itemBuilder: (BuildContext context) {
                  return const <PopupMenuEntry<_CachedMenuAction>>[
                    PopupMenuItem<_CachedMenuAction>(
                      value: _CachedMenuAction.delete,
                      child: Text('删除本地缓存'),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageSection extends StatefulWidget {
  const _StorageSection({
    required this.state,
    required this.busy,
    required this.migrationProgress,
    required this.supportsCustomDirectorySelection,
    this.onPickStorageDirectory,
    this.onResetStorageDirectory,
    this.onRescanStorageDirectory,
  });

  final DownloadStorageState state;
  final bool busy;
  final DownloadStorageMigrationProgress? migrationProgress;
  final bool supportsCustomDirectorySelection;
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
          if (widget.supportsCustomDirectorySelection) ...<Widget>[
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

  final DownloadStorageMigrationProgress progress;

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

enum _CachedMenuAction { delete }

class _QueuedComicGroup {
  const _QueuedComicGroup({required this.task, required this.tasks});

  final DownloadQueueTask task;
  final List<DownloadQueueTask> tasks;

  int get taskCount => tasks.length;

  DownloadQueueTask? get activeTask {
    return tasks.cast<DownloadQueueTask?>().firstWhere(
      (DownloadQueueTask? task) =>
          task != null &&
          (task.status == DownloadQueueTaskStatus.downloading ||
              task.status == DownloadQueueTaskStatus.parsing),
      orElse: () => null,
    );
  }

  DownloadQueueTask? get failedTask {
    return tasks.cast<DownloadQueueTask?>().firstWhere(
      (DownloadQueueTask? task) =>
          task?.status == DownloadQueueTaskStatus.failed,
      orElse: () => null,
    );
  }

  DownloadQueueTask? get singleTask => tasks.length == 1 ? tasks.first : null;

  DownloadQueueTaskStatus get status {
    if (activeTask != null) {
      return activeTask!.status;
    }
    if (failedTask != null) {
      return DownloadQueueTaskStatus.failed;
    }
    return tasks.first.status;
  }

  String get primaryChapterLabel {
    final DownloadQueueTask referenceTask = activeTask ?? failedTask ?? task;
    return referenceTask.chapterLabel;
  }

  String get summary {
    final int queuedCount = tasks
        .where(
          (DownloadQueueTask item) =>
              item.status == DownloadQueueTaskStatus.queued,
        )
        .length;
    final int failedCount = tasks
        .where(
          (DownloadQueueTask item) =>
              item.status == DownloadQueueTaskStatus.failed,
        )
        .length;
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
      return '${tasks.length} 话待处理';
    }
    return fragments.join(' · ');
  }
}

List<_QueuedComicGroup> _groupQueue(List<DownloadQueueTask> tasks) {
  final Map<String, List<DownloadQueueTask>> grouped =
      <String, List<DownloadQueueTask>>{};
  for (final DownloadQueueTask task in tasks) {
    grouped.putIfAbsent(task.comicKey, () => <DownloadQueueTask>[]).add(task);
  }
  return grouped.entries
      .map(
        (MapEntry<String, List<DownloadQueueTask>> entry) =>
            _QueuedComicGroup(task: entry.value.first, tasks: entry.value),
      )
      .toList(growable: false);
}

Map<String, CachedComicLibraryEntry> _cachedComicMap(
  List<CachedComicLibraryEntry> comics,
) {
  final Map<String, CachedComicLibraryEntry> result =
      <String, CachedComicLibraryEntry>{};
  for (final CachedComicLibraryEntry entry in comics) {
    final Uri? uri = Uri.tryParse(entry.comicHref);
    if (uri == null) {
      continue;
    }
    result[Uri(path: uri.path).toString()] = entry;
  }
  return result;
}
