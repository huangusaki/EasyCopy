import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';
import 'package:reader/services/storage_migration_store.dart';
import 'package:reader/services/uri_keys.dart';

import 'download_queue_manager/cleanup_guard.dart';
import 'download_queue_manager/migration_coordinator.dart';
import 'download_queue_manager/migration_storage.dart';
import 'download_queue_manager/retry_policy.dart';
import 'download_queue_manager/storage_write_barrier.dart';
import 'download_queue_manager/task_executor.dart';

typedef LibraryChangedCallback =
    Future<void> Function(CacheLibraryRefreshReason reason);
typedef DownloadQueueNoticeCallback = void Function(String message);

class DownloadQueueManager implements DownloadMigrationQueue {
  DownloadQueueManager({
    required AppPreferencesController preferencesController,
    required ComicDownloadService downloadService,
    required DownloadQueueStore queueStore,
    required DownloadTaskRunner taskRunner,
    DownloadTaskExecutor? taskExecutor,
    DownloadRetryPolicy retryPolicy = const DownloadRetryPolicy(),
    DownloadStorageWriteBarrier? storageWrites,
    DownloadStorageMigrationStore? migrationStore,
    MigrationDeltaJournalStore? deltaJournalStore,
    LibraryChangedCallback? onLibraryChanged,
    DownloadQueueNoticeCallback? onNotice,
  }) : _downloadService = downloadService,
       _queueStore = queueStore,
       _taskExecutor = taskExecutor ?? DownloadTaskExecutor(runner: taskRunner),
       _retryPolicy = retryPolicy,
       _writes = storageWrites ?? DownloadStorageWriteBarrier(),
       _onLibraryChanged = onLibraryChanged,
       _onNotice = onNotice {
    _retryScheduler = DownloadRetryScheduler(onReady: _resumeFailedTaskIfReady);
    _migration = DownloadMigrationCoordinator(
      preferencesController: preferencesController,
      storage: ComicDownloadMigrationStorage(downloadService),
      queue: this,
      writes: _writes,
      migrationStore: migrationStore,
      deltaJournalStore: deltaJournalStore,
      onLibraryChanged: _notifyLibraryChanged,
      onNotice: _notify,
    );
  }

  final ComicDownloadService _downloadService;
  final DownloadQueueStore _queueStore;
  final DownloadTaskExecutor _taskExecutor;
  final DownloadRetryPolicy _retryPolicy;
  final DownloadStorageWriteBarrier _writes;
  late final DownloadRetryScheduler _retryScheduler;
  late final DownloadMigrationCoordinator _migration;
  final LibraryChangedCallback? _onLibraryChanged;
  final DownloadQueueNoticeCallback? _onNotice;

  final ValueNotifier<DownloadQueueSnapshot> snapshotNotifier =
      ValueNotifier<DownloadQueueSnapshot>(const DownloadQueueSnapshot());
  ValueNotifier<DownloadStorageState> get storageStateNotifier =>
      _migration.storageStateNotifier;
  ValueNotifier<bool> get storageBusyNotifier => _migration.storageBusyNotifier;
  ValueNotifier<StorageMigrationProgress?> get migrationProgressNotifier =>
      _migration.migrationProgressNotifier;

  final DownloadCleanupGuard _cleanupGuard = DownloadCleanupGuard();
  final List<_PendingQueueCleanup> _deferredCleanups = <_PendingQueueCleanup>[];
  final Map<String, int> _taskGenerations = <String, int>{};
  int _nextGeneration = 0;
  bool _isProcessingQueue = false;
  bool _disposed = false;
  DownloadQueueTask? _runningTask;
  bool _storageSwitchPending = false;
  Completer<void>? _queueIdle;

  DownloadQueueSnapshot get snapshot => snapshotNotifier.value;

  DownloadStorageState get storageState => storageStateNotifier.value;

  bool get supportsCustomStorageSelection =>
      _downloadService.supportsCustomStorageSelection;

  bool get shouldBypassCachedReaderLookup => _migration.isActive;

  Future<void> restoreState() async {
    await refreshStorageState();
    await restoreQueue();
  }

  Future<void> restoreQueue() async {
    final DownloadQueueSnapshot restored = await _queueStore.read();
    if (_disposed) return;
    for (final DownloadQueueTask task in restored.tasks) {
      _taskGenerations[task.id] = ++_nextGeneration;
    }
    snapshotNotifier.value = restored;
    _retryScheduler.sync(restored);
  }

  Future<void> recoverStorageMigration() => _migration.recover();

  Future<void> refreshStorageState({DownloadPreferences? preferences}) async {
    final DownloadStorageState nextState = await _downloadService
        .resolveStorageState(preferences: preferences);
    if (_disposed) {
      return;
    }
    storageStateNotifier.value = nextState;
  }

  Future<bool> addTasks(Iterable<DownloadQueueTask> newTasks) async {
    final List<DownloadQueueTask> additions = newTasks.toList(growable: false);
    if (additions.isEmpty) {
      return snapshot.isPaused && snapshot.isNotEmpty;
    }

    for (final DownloadQueueTask task in additions) {
      _taskGenerations[task.id] = ++_nextGeneration;
    }
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    final bool keepPaused =
        currentSnapshot.isPaused && currentSnapshot.isNotEmpty;
    await _persistSnapshot(
      currentSnapshot.copyWith(
        isPaused: keepPaused,
        tasks: <DownloadQueueTask>[
          ...currentSnapshot.tasks.where(
            (task) => !additions.any((next) => next.id == task.id),
          ),
          ...{for (final task in additions) task.id: task}.values,
        ].toList(growable: false),
      ),
    );
    if (!keepPaused) {
      unawaited(ensureRunning());
    }
    return keepPaused;
  }

  Future<void> pauseQueue() async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    if (currentSnapshot.isEmpty || currentSnapshot.isPaused) {
      return;
    }
    await _persistSnapshot(currentSnapshot.copyWith(isPaused: true));
  }

  Future<void> resumeQueue() async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    if (currentSnapshot.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<DownloadQueueTask> tasks = currentSnapshot.tasks
        .map((DownloadQueueTask task) {
          if (task.status == DownloadQueueTaskStatus.failed ||
              task.status == DownloadQueueTaskStatus.paused ||
              task.status == DownloadQueueTaskStatus.parsing ||
              task.status == DownloadQueueTaskStatus.downloading) {
            return _retryPolicy.queuedTask(task, now, resetAttempts: true);
          }
          return task;
        })
        .toList(growable: false);

    await _persistSnapshot(
      currentSnapshot.copyWith(isPaused: false, tasks: tasks),
    );
    unawaited(ensureRunning());
  }

  Future<void> retryTask(DownloadQueueTask task) async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    final int index = currentSnapshot.tasks.indexWhere(
      (DownloadQueueTask item) => item.id == task.id,
    );
    if (index == -1) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<DownloadQueueTask> tasks = currentSnapshot.tasks.toList(
      growable: true,
    );
    tasks[index] = _retryPolicy.queuedTask(
      tasks[index],
      now,
      resetAttempts: true,
    );

    final bool shouldResume =
        currentSnapshot.isPaused &&
        currentSnapshot.activeTask?.id == task.id &&
        task.status == DownloadQueueTaskStatus.failed;
    await _persistSnapshot(
      currentSnapshot.copyWith(
        isPaused: shouldResume ? false : currentSnapshot.isPaused,
        tasks: tasks.toList(growable: false),
      ),
    );
    if (shouldResume || !currentSnapshot.isPaused) {
      unawaited(ensureRunning());
    }
  }

  Future<void> removeQueuedComic(DownloadQueueTask task) {
    final List<DownloadQueueTask> removed = _tasksForComic(task.comicKey);
    return _removeWithCleanup(
      removed,
      scope: _comicCleanupScope(task.comicKey, task.comicTitle, removed),
      cleanup: () => _cleanupIncompleteTasks(removed),
    );
  }

  Future<void> removeQueuedTask(DownloadQueueTask task) {
    final List<DownloadQueueTask> removed = snapshot.tasks
        .where((DownloadQueueTask current) => current.id == task.id)
        .toList(growable: false);
    final List<DownloadQueueTask> cleanupTasks = removed.isEmpty
        ? <DownloadQueueTask>[task]
        : removed;
    return _removeWithCleanup(
      removed,
      scope: _chapterCleanupScope(cleanupTasks),
      cleanup: () => _cleanupIncompleteTasks(cleanupTasks),
    );
  }

  Future<void> removeComicAndDeleteCache(DownloadQueueTask task) {
    final List<DownloadQueueTask> removed = _tasksForComic(task.comicKey);
    return _removeWithCleanup(
      removed,
      scope: _comicCleanupScope(task.comicKey, task.comicTitle, removed),
      cleanup: () async {
        await _downloadService.cleanupIncompleteTasks(removed);
        await _deleteCachedComicByKeyOrTitle(
          comicKey: task.comicKey,
          fallbackTitle: task.comicTitle,
        );
        await _migration.recordComicDeletion(task.comicTitle);
      },
    );
  }

  Future<void> clearQueue() {
    final List<DownloadQueueTask> removed = snapshot.tasks;
    if (removed.isEmpty) return Future<void>.value();
    return _removeWithCleanup(
      removed,
      scope: _chapterCleanupScope(removed),
      cleanup: () => _cleanupIncompleteTasks(removed),
    );
  }

  Future<void> deleteCachedComic(
    CachedComicLibraryEntry entry, {
    required String comicKey,
  }) {
    final List<DownloadQueueTask> removed = _tasksForComic(comicKey);
    return _removeWithCleanup(
      removed,
      scope: _comicCleanupScope(
        comicKey,
        entry.comicTitle,
        removed,
        extraComicPaths: entry.chapters.map((CachedChapterEntry chapter) {
          final String path = chapter.directoryPath.replaceAll('\\', '/');
          final int slash = path.lastIndexOf('/');
          return slash < 0 ? path : path.substring(0, slash);
        }),
      ),
      cleanup: () async {
        await _downloadService.cleanupIncompleteTasks(removed);
        await _downloadService.deleteCachedComic(entry);
        await _migration.recordComicDeletion(entry.comicTitle);
      },
    );
  }

  List<DownloadQueueTask> _tasksForComic(String comicKey) => snapshot.tasks
      .where((DownloadQueueTask task) => task.comicKey == comicKey)
      .toList(growable: false);

  DownloadCleanupScope _chapterCleanupScope(
    Iterable<DownloadQueueTask> tasks,
  ) => DownloadCleanupScope(
    chapterPaths: tasks.map(
      (DownloadQueueTask task) => _downloadService.chapterDirectoryPath(
        task.comicTitle,
        task.chapterLabel,
      ),
    ),
  );

  DownloadCleanupScope _comicCleanupScope(
    String comicKey,
    String comicTitle,
    Iterable<DownloadQueueTask> tasks, {
    Iterable<String> extraComicPaths = const <String>[],
  }) => DownloadCleanupScope(
    comicKeys: <String>[comicKey],
    comicPaths: <String>[
      _downloadService.comicDirectoryPath(comicTitle),
      ...tasks.map(
        (DownloadQueueTask task) =>
            _downloadService.comicDirectoryPath(task.comicTitle),
      ),
      ...extraComicPaths.where((String path) => path.isNotEmpty),
    ],
  );

  bool _scopeContainsTask(DownloadCleanupScope scope, DownloadQueueTask task) =>
      scope.contains(
        comicKey: task.comicKey,
        comicPath: _downloadService.comicDirectoryPath(task.comicTitle),
        chapterPath: _downloadService.chapterDirectoryPath(
          task.comicTitle,
          task.chapterLabel,
        ),
      );

  bool _isCleanupBlocked(DownloadQueueTask task) => _cleanupGuard.blocks(
    comicKey: task.comicKey,
    comicPath: _downloadService.comicDirectoryPath(task.comicTitle),
    chapterPath: _downloadService.chapterDirectoryPath(
      task.comicTitle,
      task.chapterLabel,
    ),
  );

  Future<void> _removeWithCleanup(
    List<DownloadQueueTask> removed, {
    required DownloadCleanupScope scope,
    required Future<void> Function() cleanup,
  }) async {
    if (_disposed) return;
    // Reserve before listeners can observe removal and enqueue a replacement.
    _cleanupGuard.reserve(scope);
    final _PendingQueueCleanup pending = _PendingQueueCleanup(scope, cleanup);
    final DownloadQueueTask? running = _runningTask;
    final bool deferred = running != null && _scopeContainsTask(scope, running);
    if (deferred) _deferredCleanups.add(pending);
    try {
      final Set<String> removedIds = removed.map((task) => task.id).toSet();
      final DownloadQueueSnapshot current = snapshot;
      final List<DownloadQueueTask> remaining = current.tasks
          .where((DownloadQueueTask task) => !removedIds.contains(task.id))
          .toList(growable: false);
      await _persistSnapshot(
        current.copyWith(
          isPaused: remaining.isNotEmpty && current.isPaused,
          tasks: remaining,
        ),
      );
    } catch (_) {
      if (!deferred) {
        try {
          await _runCleanup(pending);
        } catch (_) {
          // Preserve the queue persistence failure; the reservation is released.
        }
      }
      rethrow;
    }
    if (!deferred) await _runCleanup(pending);
  }

  Future<void> _runCleanup(_PendingQueueCleanup pending) async {
    try {
      await _writes.write(() async {
        if (!_disposed) await pending.action();
      });
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
    } finally {
      _cleanupGuard.release(pending.scope);
      continueDownloads();
    }
  }

  String? storageEditBlockReason() =>
      _migration.isActive ? '正在切换缓存目录，请稍后再试' : null;

  Future<List<DownloadStorageState>> loadStorageCandidates() =>
      _downloadService.loadCustomDirectoryCandidates();

  Future<DownloadStorageMigrationResult?> applyStoragePreferences(
    DownloadPreferences preferences,
  ) => _migration.applyPreferences(preferences);

  @override
  Future<bool> suspendForStorageSwitch() async {
    final bool wasRunning = snapshot.isNotEmpty && !snapshot.isPaused;
    _storageSwitchPending = true;
    try {
      if (wasRunning) await _persistSnapshot(snapshot.copyWith(isPaused: true));
      await _queueIdle?.future;
      return wasRunning;
    } catch (_) {
      _storageSwitchPending = false;
      if (!_disposed &&
          wasRunning &&
          snapshot.isNotEmpty &&
          snapshot.isPaused) {
        try {
          // Restore memory even if the same store also rejects this write.
          await _persistSnapshot(snapshot.copyWith(isPaused: false));
        } catch (_) {
          // The original suspend failure remains the caller's error.
        }
      }
      continueDownloads();
      rethrow;
    }
  }

  @override
  Future<void> resumeAfterStorageSwitch(bool wasRunning) async {
    _storageSwitchPending = false;
    if (_disposed) return;
    if (wasRunning && snapshot.isNotEmpty && snapshot.isPaused) {
      await _persistSnapshot(snapshot.copyWith(isPaused: false));
    }
    continueDownloads();
  }

  @override
  void continueDownloads() {
    if (!_disposed) unawaited(ensureRunning());
  }

  Future<void> ensureRunning() async {
    if (_disposed ||
        _isProcessingQueue ||
        storageBusyNotifier.value ||
        _storageSwitchPending ||
        snapshot.isPaused ||
        snapshot.isEmpty) {
      return;
    }

    // 磁盘检查前锁定队列，防止并发启动同一任务。
    _isProcessingQueue = true;
    final Completer<void> idle = Completer<void>();
    _queueIdle = idle;
    try {
      final DownloadStorageState nextStorageState = await _downloadService
          .resolveStorageState();
      if (_disposed) {
        return;
      }
      storageStateNotifier.value = nextStorageState;
      if (!nextStorageState.isReady) {
        await _persistSnapshot(snapshot.copyWith(isPaused: true));
        _notify(
          nextStorageState.errorMessage.isEmpty
              ? '缓存目录不可用，请检查下载管理页中的目录设置。'
              : '缓存目录不可用：${nextStorageState.errorMessage}',
        );
        return;
      }

      while (!_disposed) {
        if (_storageSwitchPending) {
          break;
        }
        final DownloadQueueSnapshot currentSnapshot = snapshot;
        if (currentSnapshot.isPaused || currentSnapshot.isEmpty) {
          break;
        }
        final DownloadQueueTask? activeTask = currentSnapshot.tasks
            .where((DownloadQueueTask task) => !_isCleanupBlocked(task))
            .firstOrNull;
        if (activeTask == null) break;
        if (activeTask.status == DownloadQueueTaskStatus.failed) {
          if (activeTask.nextRetryAt == null) {
            break;
          }
          if (activeTask.nextRetryAt!.isAfter(DateTime.now())) {
            _retryScheduler.sync(snapshot);
            break;
          }
          await _resumeFailedTaskIfReady(activeTask.id);
          continue;
        }
        await _runTask(activeTask);
      }
    } finally {
      _isProcessingQueue = false;
      _queueIdle = null;
      idle.complete();
    }
  }

  Future<void> _resumeFailedTaskIfReady(String taskId) async {
    if (_disposed || snapshot.isPaused) {
      _retryScheduler.cancel(taskId);
      return;
    }

    final DownloadQueueTask? latestTask = _taskById(taskId);
    if (latestTask == null ||
        latestTask.status != DownloadQueueTaskStatus.failed ||
        latestTask.nextRetryAt == null) {
      _retryScheduler.cancel(taskId);
      return;
    }

    if (latestTask.nextRetryAt!.isAfter(DateTime.now())) {
      _retryScheduler.sync(snapshot);
      return;
    }

    _retryScheduler.cancel(taskId);
    await _updateTask(_retryPolicy.queuedTask(latestTask, DateTime.now()));
    if (!_isProcessingQueue) {
      unawaited(ensureRunning());
    }
  }

  void dispose() {
    _disposed = true;
    _retryScheduler.dispose();
    _migration.dispose();
    snapshotNotifier.dispose();
  }

  Future<void> _persistSnapshot(DownloadQueueSnapshot nextSnapshot) async {
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = nextSnapshot;
    _retryScheduler.sync(nextSnapshot);
    if (nextSnapshot.isEmpty) {
      await _queueStore.clear();
      return;
    }
    await _queueStore.write(nextSnapshot);
  }

  Future<void> _removeTaskFromQueue(DownloadQueueTask task) async {
    final DownloadQueueSnapshot current = snapshot;
    final List<DownloadQueueTask> remaining = current.tasks
        .where((DownloadQueueTask item) => item.id != task.id)
        .toList(growable: false);
    await _persistSnapshot(
      current.copyWith(
        isPaused: remaining.isNotEmpty && current.isPaused,
        tasks: remaining,
      ),
    );
  }

  DownloadQueueTask? _taskById(String taskId) {
    for (final DownloadQueueTask task in snapshot.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  Future<void> _updateTask(
    DownloadQueueTask updatedTask, {
    bool persist = true,
  }) async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    final int index = currentSnapshot.tasks.indexWhere(
      (DownloadQueueTask task) => task.id == updatedTask.id,
    );
    if (index == -1 || _disposed) {
      return;
    }

    final List<DownloadQueueTask> tasks = currentSnapshot.tasks.toList(
      growable: true,
    );
    tasks[index] = updatedTask;
    final DownloadQueueSnapshot nextSnapshot = currentSnapshot.copyWith(
      tasks: tasks.toList(growable: false),
    );
    if (persist) {
      await _persistSnapshot(nextSnapshot);
      return;
    }
    snapshotNotifier.value = nextSnapshot;
  }

  Future<void> _runTask(DownloadQueueTask task) async {
    _runningTask = task;
    final int generation = _taskGenerations.putIfAbsent(
      task.id,
      () => ++_nextGeneration,
    );
    final _QueueTaskExecutionHost host = _QueueTaskExecutionHost(
      this,
      task.id,
      generation,
    );
    try {
      final DownloadTaskExecutionResult result = await _writes.write(
        () => _taskExecutor.execute(task, host),
      );
      if (_disposed) return;
      switch (result.outcome) {
        case DownloadTaskOutcome.completed:
          if (host.currentTask == null) {
            await _cleanupCancelledTask(task);
            break;
          }
          await _removeTaskFromQueue(task);
          await _writes.write(() => _migration.recordTaskUpsert(task));
          await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
          if (snapshot.isEmpty) _notify('后台缓存已完成');
        case DownloadTaskOutcome.paused:
          final DownloadQueueTask? latest = host.currentTask;
          if (latest != null) {
            await host.update(
              latest.copyWith(
                status: DownloadQueueTaskStatus.paused,
                progressLabel:
                    latest.totalImages > 0 && latest.completedImages > 0
                    ? '已暂停 ${latest.completedImages}/${latest.totalImages}'
                    : '已暂停',
                updatedAt: DateTime.now(),
              ),
            );
          }
          // Removal can arrive while a pause is being persisted.
          if (host.currentTask == null) {
            await _cleanupCancelledTask(task);
          }
        case DownloadTaskOutcome.cancelled:
          await _cleanupCancelledTask(task);
        case DownloadTaskOutcome.failed:
          await _failTask(host, result.error!);
      }
    } catch (error) {
      if (!_disposed && host.currentTask != null) await _failTask(host, error);
    } finally {
      try {
        await _finishDeferredCleanups(task);
      } finally {
        _runningTask = null;
      }
    }
  }

  Future<void> _failTask(_QueueTaskExecutionHost host, Object error) async {
    final DownloadQueueTask? current = host.currentTask;
    if (current == null) return;
    final DownloadQueueTask failed = _retryPolicy.failedTask(
      current,
      error,
      DateTime.now(),
    );
    await host.update(failed);
    if (_disposed || host.currentTask == null) return;
    if (failed.nextRetryAt == null) {
      await _persistSnapshot(snapshot.copyWith(isPaused: true));
    }
    _notify(
      failed.nextRetryAt == null
          ? '缓存失败：${failed.errorMessage}'
          : '缓存失败：${failed.errorMessage}，${_retryPolicy.delay.inSeconds}秒后自动重试',
    );
  }

  Future<void> _cleanupCancelledTask(DownloadQueueTask task) async {
    if (_deferredCleanups.any(
      (pending) => _scopeContainsTask(pending.scope, task),
    )) {
      return;
    }
    final DownloadCleanupScope scope = _chapterCleanupScope(<DownloadQueueTask>[
      task,
    ]);
    _cleanupGuard.reserve(scope);
    await _runCleanup(
      _PendingQueueCleanup(
        scope,
        () => _cleanupIncompleteTasks(<DownloadQueueTask>[task]),
      ),
    );
  }

  Future<void> _finishDeferredCleanups(DownloadQueueTask task) async {
    Object? failure;
    while (true) {
      final int index = _deferredCleanups.indexWhere(
        (pending) => _scopeContainsTask(pending.scope, task),
      );
      if (index < 0) break;
      final _PendingQueueCleanup pending = _deferredCleanups.removeAt(index);
      try {
        await _runCleanup(pending);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) {
      _notify('缓存清理失败：${formatDownloadError(failure)}');
    }
  }

  Future<void> _cleanupIncompleteTasks(
    Iterable<DownloadQueueTask> tasks,
  ) async {
    if (_disposed) return;
    await _downloadService.cleanupIncompleteTasks(tasks);
    await _migration.recordTaskCleanup(tasks);
  }

  Future<void> _deleteCachedComicByKeyOrTitle({
    required String comicKey,
    required String fallbackTitle,
  }) async {
    final List<CachedComicLibraryEntry> library = await _downloadService
        .loadCachedLibrary();
    final CachedComicLibraryEntry? match = library
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? entry) =>
              entry != null &&
              entry.comicHref.isNotEmpty &&
              Uri.tryParse(entry.comicHref) != null &&
              _comicKey(entry.comicHref) == comicKey,
          orElse: () => null,
        );
    if (match != null) {
      await _downloadService.deleteCachedComic(match);
      return;
    }
    await _downloadService.deleteComicCacheByTitle(fallbackTitle);
  }

  String _comicKey(String value) => UriKeys.pathKey(value);

  Future<void> _notifyLibraryChanged(CacheLibraryRefreshReason reason) async {
    if (_disposed || _onLibraryChanged == null) {
      return;
    }
    await _onLibraryChanged(reason);
  }

  void _notify(String message) {
    if (_disposed || message.trim().isEmpty) {
      return;
    }
    _onNotice?.call(message);
  }
}

class _QueueTaskExecutionHost implements DownloadTaskExecutionHost {
  const _QueueTaskExecutionHost(this.manager, this.taskId, this.generation);

  final DownloadQueueManager manager;
  final String taskId;
  final int generation;

  @override
  DownloadQueueTask? get currentTask =>
      manager._disposed || manager._taskGenerations[taskId] != generation
      ? null
      : manager._taskById(taskId);

  @override
  bool get shouldCancel => currentTask == null;

  @override
  bool get shouldPause => !shouldCancel && manager.snapshot.isPaused;

  @override
  Future<void> update(DownloadQueueTask task, {bool persist = true}) async {
    if (currentTask == null) return;
    await manager._updateTask(task, persist: persist);
  }
}

class _PendingQueueCleanup {
  const _PendingQueueCleanup(this.scope, this.action);
  final DownloadCleanupScope scope;
  final Future<void> Function() action;
}
