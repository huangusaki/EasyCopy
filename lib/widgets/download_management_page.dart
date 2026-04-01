import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DownloadManagementEntryCard extends StatelessWidget {
  const DownloadManagementEntryCard({
    required this.statusLabel,
    required this.queueLabel,
    required this.pathLabel,
    required this.onTap,
    this.noteLabel,
    super.key,
  });

  final String statusLabel;
  final String queueLabel;
  final String pathLabel;
  final String? noteLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '下载管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _SummaryChip(label: '状态', value: statusLabel),
              _SummaryChip(label: '队列', value: queueLabel),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.folder_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pathLabel,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.76),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (noteLabel != null && noteLabel!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    noteLabel!,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.76),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
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

class DownloadManagementPage extends StatelessWidget {
  const DownloadManagementPage({
    required this.queueListenable,
    required this.storageStateListenable,
    required this.storageBusyListenable,
    required this.migrationProgressListenable,
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
    super.key,
  });

  final ValueListenable<DownloadQueueSnapshot> queueListenable;
  final ValueListenable<DownloadStorageState> storageStateListenable;
  final ValueListenable<bool> storageBusyListenable;
  final ValueListenable<DownloadStorageMigrationProgress?>
  migrationProgressListenable;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: SafeArea(
        child: ValueListenableBuilder<DownloadQueueSnapshot>(
          valueListenable: queueListenable,
          builder:
              (
                BuildContext context,
                DownloadQueueSnapshot snapshot,
                Widget? _,
              ) {
                return ValueListenableBuilder<DownloadStorageState>(
                  valueListenable: storageStateListenable,
                  builder:
                      (
                        BuildContext context,
                        DownloadStorageState storageState,
                        Widget? _,
                      ) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: storageBusyListenable,
                          builder:
                              (
                                BuildContext context,
                                bool storageBusy,
                                Widget? _,
                              ) {
                                return ValueListenableBuilder<
                                  DownloadStorageMigrationProgress?
                                >(
                                  valueListenable: migrationProgressListenable,
                                  builder:
                                      (
                                        BuildContext context,
                                        DownloadStorageMigrationProgress?
                                        migrationProgress,
                                        Widget? _,
                                      ) {
                                        final bool storageEditingAllowed =
                                            snapshot.isEmpty ||
                                            snapshot.isPaused;
                                        return ListView(
                                          padding: const EdgeInsets.all(16),
                                          children: <Widget>[
                                            _CurrentTaskSection(
                                              snapshot: snapshot,
                                              onPauseQueue: onPauseQueue,
                                              onResumeQueue: onResumeQueue,
                                            ),
                                            const SizedBox(height: 16),
                                            _QueueSection(
                                              snapshot: snapshot,
                                              onPauseQueue: onPauseQueue,
                                              onResumeQueue: onResumeQueue,
                                              onClearQueue: onClearQueue,
                                              onStopComicTasks:
                                                  onStopComicTasks,
                                              onRemoveComic: onRemoveComic,
                                              onRemoveTask: onRemoveTask,
                                              onRetryTask: onRetryTask,
                                            ),
                                            const SizedBox(height: 16),
                                            _StorageSection(
                                              state: storageState,
                                              busy: storageBusy,
                                              migrationProgress:
                                                  migrationProgress,
                                              editingAllowed:
                                                  storageEditingAllowed,
                                              supportsCustomDirectorySelection:
                                                  supportsCustomDirectorySelection,
                                              onPickStorageDirectory:
                                                  onPickStorageDirectory,
                                              onResetStorageDirectory:
                                                  onResetStorageDirectory,
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
    if (snapshot.isEmpty) {
      return const AppSurfaceCard(title: '当前任务', child: Text('暂无缓存任务。'));
    }

    final DownloadQueueTask activeTask = snapshot.activeTask!;
    final bool isPaused = snapshot.isPaused;
    return AppSurfaceCard(
      title: '当前任务',
      action: TextButton(
        onPressed: isPaused ? onResumeQueue : onPauseQueue,
        child: Text(isPaused ? '继续' : '暂停'),
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
              ).colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            activeTask.progressLabel.isEmpty
                ? (isPaused ? '队列已暂停' : '等待缓存')
                : activeTask.progressLabel,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: activeTask.fraction > 0 ? activeTask.fraction : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _SummaryChip(label: '队列', value: '${snapshot.remainingCount} 话'),
              _SummaryChip(
                label: '状态',
                value: _statusText(activeTask.status, snapshot),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({
    required this.snapshot,
    required this.onPauseQueue,
    required this.onResumeQueue,
    required this.onClearQueue,
    required this.onStopComicTasks,
    required this.onRemoveComic,
    required this.onRemoveTask,
    required this.onRetryTask,
  });

  final DownloadQueueSnapshot snapshot;
  final VoidCallback onPauseQueue;
  final VoidCallback onResumeQueue;
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

    final Map<String, List<DownloadQueueTask>> grouped =
        <String, List<DownloadQueueTask>>{};
    for (final DownloadQueueTask task in snapshot.tasks) {
      grouped.putIfAbsent(task.comicKey, () => <DownloadQueueTask>[]).add(task);
    }

    return AppSurfaceCard(
      title: '缓存队列',
      action: Wrap(
        spacing: 4,
        children: <Widget>[
          TextButton(
            onPressed: snapshot.isPaused ? onResumeQueue : onPauseQueue,
            child: Text(snapshot.isPaused ? '继续全部' : '停止全部'),
          ),
          TextButton(onPressed: onClearQueue, child: const Text('移除全部')),
        ],
      ),
      child: Column(
        children: grouped.entries
            .map((MapEntry<String, List<DownloadQueueTask>> entry) {
              final List<DownloadQueueTask> tasks = entry.value;
              final DownloadQueueTask displayTask = tasks.first;
              final bool isActiveComic =
                  snapshot.activeTask?.comicKey == displayTask.comicKey;
              final int failedCount = tasks
                  .where(
                    (DownloadQueueTask task) =>
                        task.status == DownloadQueueTaskStatus.failed,
                  )
                  .length;
              final int visibleTaskCount = tasks.length > 6 ? 6 : tasks.length;
              final List<DownloadQueueTask> visibleTasks = _visibleQueueTasks(
                tasks,
                maxCount: visibleTaskCount,
              );
              final int hiddenCount = tasks.length - visibleTasks.length;
              final String subtitle = isActiveComic
                  ? (snapshot.activeTask?.progressLabel.trim().isNotEmpty ??
                            false)
                        ? snapshot.activeTask!.progressLabel
                        : '当前正在处理'
                  : failedCount > 0
                  ? '${tasks.length} 话待处理，其中 $failedCount 话失败'
                  : '${tasks.length} 话待处理';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CircleAvatar(child: Text('${tasks.length}')),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  displayTask.comicTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    _SummaryChip(
                                      label: '等待',
                                      value:
                                          '${tasks.where((DownloadQueueTask task) => task.status == DownloadQueueTaskStatus.queued).length}',
                                    ),
                                    _SummaryChip(
                                      label: '失败',
                                      value: '$failedCount',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '停止',
                            onPressed: () => onStopComicTasks(displayTask),
                            icon: const Icon(Icons.stop_circle_outlined),
                          ),
                          IconButton(
                            tooltip: '移除',
                            onPressed: () => onRemoveComic(displayTask),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      if (visibleTasks.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        ...visibleTasks.map((DownloadQueueTask task) {
                          return _QueueTaskTile(
                            task: task,
                            onRemoveTask: () => onRemoveTask(task),
                            onRetryTask:
                                task.status == DownloadQueueTaskStatus.failed
                                ? () => onRetryTask(task)
                                : null,
                          );
                        }),
                      ],
                      if (hiddenCount > 0) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '另外 $hiddenCount 话已折叠，不再逐条展示。',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

List<DownloadQueueTask> _visibleQueueTasks(
  List<DownloadQueueTask> tasks, {
  int maxCount = 6,
}) {
  final List<DownloadQueueTask> prioritized = <DownloadQueueTask>[];

  void addTask(DownloadQueueTask task) {
    if (prioritized.any((DownloadQueueTask item) => item.id == task.id)) {
      return;
    }
    prioritized.add(task);
  }

  for (final DownloadQueueTask task in tasks) {
    if (task.status == DownloadQueueTaskStatus.downloading ||
        task.status == DownloadQueueTaskStatus.parsing ||
        task.status == DownloadQueueTaskStatus.failed) {
      addTask(task);
    }
    if (prioritized.length >= maxCount) {
      return prioritized.take(maxCount).toList(growable: false);
    }
  }

  for (final DownloadQueueTask task in tasks) {
    addTask(task);
    if (prioritized.length >= maxCount) {
      break;
    }
  }

  return prioritized.take(maxCount).toList(growable: false);
}

class _QueueTaskTile extends StatelessWidget {
  const _QueueTaskTile({
    required this.task,
    required this.onRemoveTask,
    this.onRetryTask,
  });

  final DownloadQueueTask task;
  final VoidCallback onRemoveTask;
  final VoidCallback? onRetryTask;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDownloading =
        task.status == DownloadQueueTaskStatus.downloading;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  task.chapterLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _StatusBadge(status: task.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            task.progressLabel.isEmpty ? '等待缓存' : task.progressLabel,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
          if (isDownloading || task.totalImages > 0) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: task.fraction > 0 ? task.fraction : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (onRetryTask != null)
                TextButton(onPressed: onRetryTask, child: const Text('重试')),
              TextButton(
                onPressed: onRemoveTask,
                child: Text(
                  task.status == DownloadQueueTaskStatus.downloading
                      ? '停止'
                      : '移除',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageSection extends StatelessWidget {
  const _StorageSection({
    required this.state,
    required this.busy,
    required this.migrationProgress,
    required this.editingAllowed,
    required this.supportsCustomDirectorySelection,
    this.onPickStorageDirectory,
    this.onResetStorageDirectory,
  });

  final DownloadStorageState state;
  final bool busy;
  final DownloadStorageMigrationProgress? migrationProgress;
  final bool editingAllowed;
  final bool supportsCustomDirectorySelection;
  final VoidCallback? onPickStorageDirectory;
  final VoidCallback? onResetStorageDirectory;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String retentionText = state.mayBeRemovedOnUninstall
        ? '卸载应用后，这个目录中的缓存通常会一起删除。'
        : '卸载应用后，这个目录中的缓存通常会保留。';
    final bool canEdit = editingAllowed && !busy && migrationProgress == null;
    final bool showLoadingState = state.isLoading && migrationProgress == null;
    return AppSurfaceCard(
      title: '缓存目录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showLoadingState)
            const Text('正在读取缓存目录…')
          else ...<Widget>[
            if (!state.isLoading) ...<Widget>[
              _InfoRow(
                icon: Icons.folder_rounded,
                text: state.displayPath.isEmpty ? '当前目录不可用' : state.displayPath,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: state.isCustom
                    ? Icons.sd_storage_rounded
                    : Icons.phone_android_rounded,
                text: state.isCustom ? '当前使用自定义目录' : '当前使用默认目录',
              ),
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.info_outline_rounded, text: retentionText),
              if (state.errorMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  state.errorMessage,
                  style: TextStyle(color: colorScheme.error, height: 1.4),
                ),
              ],
            ],
            if (!editingAllowed) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '请先暂停缓存队列后再切换目录。',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
            ],
            if (supportsCustomDirectorySelection) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: canEdit ? onPickStorageDirectory : null,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.drive_folder_upload_rounded),
                    label: Text(state.isCustom ? '更换位置' : '选择存储位置'),
                  ),
                  if (state.isCustom)
                    OutlinedButton.icon(
                      onPressed: canEdit ? onResetStorageDirectory : null,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('恢复默认'),
                    ),
                ],
              ),
            ],
            if (!state.isLoading) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '切换目录时会自动迁移已有缓存；迁移期间请勿退出应用。',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
            ],
            if (migrationProgress != null) ...<Widget>[
              const SizedBox(height: 14),
              _MigrationProgressPanel(progress: migrationProgress!),
            ],
          ],
        ],
      ),
    );
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
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.drive_folder_upload_rounded,
            text: '目标：${progress.toPath}',
          ),
          if (progress.currentItemPath.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.description_outlined,
              text: progress.currentItemPath,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '$label：$value',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
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
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.76),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

String _statusText(
  DownloadQueueTaskStatus status,
  DownloadQueueSnapshot snapshot,
) {
  if (snapshot.isPaused) {
    return '已暂停';
  }
  return switch (status) {
    DownloadQueueTaskStatus.queued => '等待中',
    DownloadQueueTaskStatus.parsing => '解析中',
    DownloadQueueTaskStatus.downloading => '下载中',
    DownloadQueueTaskStatus.paused => '已暂停',
    DownloadQueueTaskStatus.failed => '失败',
  };
}
