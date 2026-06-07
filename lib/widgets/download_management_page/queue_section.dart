part of '../download_management_page.dart';

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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<_QueuedComicGroup> groups = _groupQueue(snapshot.tasks);
    return AppSurfaceCard(
      title: '缓存队列',
      action: OutlinedButton.icon(
        onPressed: onClearQueue,
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text('清空队列'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
      ),
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
