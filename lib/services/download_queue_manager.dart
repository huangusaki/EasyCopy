import 'dart:async';
import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_storage_migration_store.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:flutter/foundation.dart';

typedef DownloadQueueLibraryChangedCallback = Future<void> Function();
typedef DownloadQueueNoticeCallback = void Function(String message);

abstract class DownloadTaskRunner {
  Future<ReaderPageData> prepare(DownloadQueueTask task);

  Future<void> download(
    DownloadQueueTask task,
    ReaderPageData page, {
    required ChapterDownloadPauseChecker shouldPause,
    required ChapterDownloadCancelChecker shouldCancel,
    ChapterDownloadProgressCallback? onProgress,
  });
}

class DownloadQueueManager {
  DownloadQueueManager({
    required AppPreferencesController preferencesController,
    required ComicDownloadService downloadService,
    required DownloadQueueStore queueStore,
    required DownloadTaskRunner taskRunner,
    DownloadStorageMigrationStore? migrationStore,
    DownloadQueueLibraryChangedCallback? onLibraryChanged,
    DownloadQueueNoticeCallback? onNotice,
  }) : _preferencesController = preferencesController,
       _downloadService = downloadService,
       _queueStore = queueStore,
       _taskRunner = taskRunner,
       _migrationStore =
           migrationStore ?? DownloadStorageMigrationStore.instance,
       _onLibraryChanged = onLibraryChanged,
       _onNotice = onNotice;

  final AppPreferencesController _preferencesController;
  final ComicDownloadService _downloadService;
  final DownloadQueueStore _queueStore;
  final DownloadTaskRunner _taskRunner;
  final DownloadStorageMigrationStore _migrationStore;
  final DownloadQueueLibraryChangedCallback? _onLibraryChanged;
  final DownloadQueueNoticeCallback? _onNotice;

  final ValueNotifier<DownloadQueueSnapshot> snapshotNotifier =
      ValueNotifier<DownloadQueueSnapshot>(const DownloadQueueSnapshot());
  final ValueNotifier<DownloadStorageState> storageStateNotifier =
      ValueNotifier<DownloadStorageState>(const DownloadStorageState.loading());
  final ValueNotifier<bool> storageBusyNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<DownloadStorageMigrationProgress?>
  storageMigrationProgressNotifier =
      ValueNotifier<DownloadStorageMigrationProgress?>(null);

  final Map<String, List<DownloadQueueTask>> _pendingCancelledTaskCleanups =
      <String, List<DownloadQueueTask>>{};
  final Map<String, String> _pendingCancelledComicDeletions =
      <String, String>{};

  bool _isProcessingQueue = false;
  bool _disposed = false;
  String? _runningTaskId;
  String? _runningComicKey;
  Object? _activeStorageCleanupToken;

  DownloadQueueSnapshot get snapshot => snapshotNotifier.value;

  DownloadStorageState get storageState => storageStateNotifier.value;

  bool get supportsCustomStorageSelection =>
      _downloadService.supportsCustomStorageSelection;

  Future<void> restoreState() async {
    await _queueStore.ensureInitialized();
    await refreshStorageState();
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = await _queueStore.read();
  }

  Future<void> restoreQueue() async {
    await _queueStore.ensureInitialized();
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = await _queueStore.read();
  }

  Future<void> recoverInterruptedStorageMigration() async {
    await _migrationStore.ensureInitialized();
    final PendingDownloadStorageMigration? pendingMigration =
        await _migrationStore.read();
    if (pendingMigration == null || _disposed) {
      return;
    }

    final DownloadPreferences currentPreferences =
        _preferencesController.downloadPreferences;
    if (currentPreferences.hasSameStorageLocation(pendingMigration.to)) {
      await _migrationStore.clear();
      return;
    }
    if (!currentPreferences.hasSameStorageLocation(pendingMigration.from)) {
      await _migrationStore.clear();
      return;
    }

    final DownloadStorageState currentState = await _downloadService
        .resolveStorageState(
          preferences: currentPreferences,
          verifyWritable: false,
        );
    if (!_disposed) {
      storageStateNotifier.value = currentState;
    }
    if (!_disposed) {
      storageBusyNotifier.value = true;
    }
    Future<String>? cleanupFuture;
    try {
      final DownloadStorageMigrationResult result = await _downloadService
          .migrateCacheRoot(
            from: pendingMigration.from,
            to: pendingMigration.to,
            onProgress: (DownloadStorageMigrationProgress progress) {
              if (_disposed) {
                return;
              }
              storageMigrationProgressNotifier.value = progress;
            },
          );
      await _preferencesController.updateDownloadPreferences(
        (_) => pendingMigration.to,
      );
      await _migrationStore.clear();
      if (!_disposed) {
        storageStateNotifier.value = result.storageState;
      }
      await _notifyLibraryChanged();
      cleanupFuture = result.cleanupFuture;
      final String message = result.cleanupWarning.isEmpty
          ? '已恢复上次未完成的缓存目录迁移'
          : '已恢复上次未完成的缓存目录迁移，${result.cleanupWarning}';
      _notify(message);
      if (cleanupFuture != null) {
        unawaited(_watchStorageCleanup(cleanupFuture));
      }
    } catch (_) {
      await _migrationStore.clear();
      await refreshStorageState(preferences: currentPreferences);
      _notify('检测到上次缓存目录迁移未完成，请重新选择缓存目录。');
    } finally {
      if (!_disposed) {
        storageBusyNotifier.value = false;
        if (cleanupFuture == null) {
          storageMigrationProgressNotifier.value = null;
        }
      }
    }
  }

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

    final DownloadQueueSnapshot currentSnapshot = snapshot;
    final bool keepPaused =
        currentSnapshot.isPaused && currentSnapshot.isNotEmpty;
    await _persistSnapshot(
      currentSnapshot.copyWith(
        isPaused: keepPaused,
        tasks: <DownloadQueueTask>[
          ...currentSnapshot.tasks,
          ...additions,
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
            return task.copyWith(
              status: DownloadQueueTaskStatus.queued,
              progressLabel: '等待缓存',
              errorMessage: '',
              updatedAt: now,
            );
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
    tasks[index] = task.copyWith(
      status: DownloadQueueTaskStatus.queued,
      progressLabel: '等待缓存',
      errorMessage: '',
      updatedAt: now,
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

  Future<void> removeQueuedComic(DownloadQueueTask task) async {
    final bool removesRunningComic = _isComicRunning(task.comicKey);
    final List<DownloadQueueTask> removedTasks = await _removeComicFromQueue(
      task.comicKey,
      deferCleanupToRunningTask: removesRunningComic,
    );
    if (!removesRunningComic) {
      await _downloadService.cleanupIncompleteTasks(removedTasks);
      await _notifyLibraryChanged();
    }
  }

  Future<void> removeQueuedTask(DownloadQueueTask task) async {
    final bool removesRunningTask = _isTaskRunning(task.id);
    await _removeTaskFromQueue(
      task,
      deferCleanupToRunningTask: removesRunningTask,
    );
    if (!removesRunningTask) {
      await _downloadService.cleanupIncompleteTasks(<DownloadQueueTask>[task]);
      await _notifyLibraryChanged();
    }
  }

  Future<void> removeComicAndDeleteCache(DownloadQueueTask task) async {
    final bool removesRunningComic = _isComicRunning(task.comicKey);
    final List<DownloadQueueTask> removedTasks = await _removeComicFromQueue(
      task.comicKey,
      deferCleanupToRunningTask: removesRunningComic,
    );

    if (removesRunningComic) {
      if (_runningTaskId != null) {
        _pendingCancelledComicDeletions[_runningTaskId!] = task.comicTitle;
      }
      return;
    }

    await _downloadService.cleanupIncompleteTasks(removedTasks);
    await _deleteCachedComicByKeyOrTitle(
      comicKey: task.comicKey,
      fallbackTitle: task.comicTitle,
    );
    await _notifyLibraryChanged();
  }

  Future<void> clearQueue() async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    if (currentSnapshot.isEmpty) {
      return;
    }

    final List<DownloadQueueTask> removedTasks = currentSnapshot.tasks;
    final String? runningTaskId = _runningTaskId;
    await _persistSnapshot(const DownloadQueueSnapshot());

    if (runningTaskId != null) {
      _pendingCancelledTaskCleanups[runningTaskId] = removedTasks;
      return;
    }

    await _downloadService.cleanupIncompleteTasks(removedTasks);
    await _notifyLibraryChanged();
  }

  Future<void> deleteCachedComic(
    CachedComicLibraryEntry entry, {
    required String comicKey,
  }) async {
    final bool removesRunningComic = _isComicRunning(comicKey);
    final List<DownloadQueueTask> removedTasks = await _removeComicFromQueue(
      comicKey,
      deferCleanupToRunningTask: removesRunningComic,
    );

    if (!removesRunningComic) {
      await _downloadService.cleanupIncompleteTasks(removedTasks);
      await _downloadService.deleteCachedComic(entry);
      await _notifyLibraryChanged();
      return;
    }

    if (_runningTaskId != null) {
      _pendingCancelledComicDeletions[_runningTaskId!] = entry.comicTitle;
    }
  }

  String? storageEditBlockReason() {
    if (storageBusyNotifier.value ||
        storageMigrationProgressNotifier.value != null) {
      return '正在切换缓存目录，请稍后再试';
    }
    if (snapshot.isNotEmpty && !snapshot.isPaused) {
      return '请先暂停缓存队列后再切换缓存目录';
    }
    return null;
  }

  Future<List<DownloadStorageState>> loadStorageCandidates() {
    return _downloadService.loadCustomDirectoryCandidates();
  }

  Future<DownloadStorageMigrationResult?> applyStoragePreferences(
    DownloadPreferences nextPreferences,
  ) async {
    final DownloadPreferences currentPreferences =
        _preferencesController.downloadPreferences;
    if (currentPreferences.hasSameStorageLocation(nextPreferences)) {
      return null;
    }

    if (!_disposed) {
      storageBusyNotifier.value = true;
    }
    Future<String>? cleanupFuture;
    try {
      await _migrationStore.write(
        PendingDownloadStorageMigration(
          from: currentPreferences,
          to: nextPreferences,
          createdAt: DateTime.now(),
        ),
      );
      final DownloadStorageMigrationResult result = await _downloadService
          .migrateCacheRoot(
            from: currentPreferences,
            to: nextPreferences,
            onProgress: (DownloadStorageMigrationProgress progress) {
              if (_disposed) {
                return;
              }
              storageMigrationProgressNotifier.value = progress;
            },
          );
      await _preferencesController.updateDownloadPreferences(
        (_) => nextPreferences,
      );
      await _migrationStore.clear();
      if (!_disposed) {
        storageStateNotifier.value = result.storageState;
      }
      await _notifyLibraryChanged();
      cleanupFuture = result.cleanupFuture;
      if (cleanupFuture != null) {
        unawaited(_watchStorageCleanup(cleanupFuture));
      }
      return result;
    } catch (_) {
      await _migrationStore.clear();
      await refreshStorageState();
      rethrow;
    } finally {
      if (!_disposed) {
        storageBusyNotifier.value = false;
        if (cleanupFuture == null) {
          storageMigrationProgressNotifier.value = null;
        }
      }
    }
  }

  Future<void> ensureRunning() async {
    if (_disposed ||
        _isProcessingQueue ||
        storageBusyNotifier.value ||
        snapshot.isPaused ||
        snapshot.isEmpty) {
      return;
    }

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

    _isProcessingQueue = true;
    try {
      while (!_disposed) {
        final DownloadQueueSnapshot currentSnapshot = snapshot;
        if (currentSnapshot.isPaused || currentSnapshot.isEmpty) {
          break;
        }
        await _runTask(currentSnapshot.activeTask!);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  void dispose() {
    _disposed = true;
    snapshotNotifier.dispose();
    storageStateNotifier.dispose();
    storageBusyNotifier.dispose();
    storageMigrationProgressNotifier.dispose();
  }

  Future<void> _persistSnapshot(DownloadQueueSnapshot nextSnapshot) async {
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = nextSnapshot;
    if (nextSnapshot.isEmpty) {
      await _queueStore.clear();
      return;
    }
    await _queueStore.write(nextSnapshot);
  }

  Future<List<DownloadQueueTask>> _removeComicFromQueue(
    String comicKey, {
    bool deferCleanupToRunningTask = false,
  }) async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    if (currentSnapshot.isEmpty) {
      return const <DownloadQueueTask>[];
    }

    final List<DownloadQueueTask> removedTasks = currentSnapshot.tasks
        .where((DownloadQueueTask task) => task.comicKey == comicKey)
        .toList(growable: false);
    if (removedTasks.isEmpty) {
      return const <DownloadQueueTask>[];
    }

    final List<DownloadQueueTask> remainingTasks = currentSnapshot.tasks
        .where((DownloadQueueTask task) => task.comicKey != comicKey)
        .toList(growable: false);

    if (deferCleanupToRunningTask && _runningTaskId != null) {
      _pendingCancelledTaskCleanups[_runningTaskId!] = removedTasks;
    }

    await _persistSnapshot(
      currentSnapshot.copyWith(
        isPaused: remainingTasks.isEmpty ? false : currentSnapshot.isPaused,
        tasks: remainingTasks,
      ),
    );
    return removedTasks;
  }

  Future<void> _removeTaskFromQueue(
    DownloadQueueTask task, {
    bool deferCleanupToRunningTask = false,
  }) async {
    final DownloadQueueSnapshot currentSnapshot = snapshot;
    if (currentSnapshot.isEmpty) {
      return;
    }

    final bool containsTask = currentSnapshot.tasks.any(
      (DownloadQueueTask item) => item.id == task.id,
    );
    if (!containsTask) {
      return;
    }

    final List<DownloadQueueTask> remainingTasks = currentSnapshot.tasks
        .where((DownloadQueueTask item) => item.id != task.id)
        .toList(growable: false);
    if (deferCleanupToRunningTask) {
      _pendingCancelledTaskCleanups[task.id] = <DownloadQueueTask>[task];
    }
    await _persistSnapshot(
      currentSnapshot.copyWith(
        isPaused: remainingTasks.isEmpty ? false : currentSnapshot.isPaused,
        tasks: remainingTasks,
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

  bool _shouldPauseActiveDownload(DownloadQueueTask task) {
    return !_disposed &&
        _isTaskRunning(task.id) &&
        snapshot.isPaused &&
        _taskById(task.id) != null;
  }

  bool _shouldCancelActiveDownload(DownloadQueueTask task) {
    return _disposed || (_isTaskRunning(task.id) && _taskById(task.id) == null);
  }

  Future<void> _runTask(DownloadQueueTask task) async {
    _runningTaskId = task.id;
    _runningComicKey = task.comicKey;
    try {
      await _updateTask(
        task.copyWith(
          status: DownloadQueueTaskStatus.parsing,
          progressLabel: '正在解析 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: 0,
          errorMessage: '',
          updatedAt: DateTime.now(),
        ),
      );

      final ReaderPageData readerPage = await _taskRunner.prepare(task);

      if (_shouldCancelActiveDownload(task)) {
        throw const DownloadCancelledException();
      }
      if (_shouldPauseActiveDownload(task)) {
        throw const DownloadPausedException();
      }

      await _updateTask(
        task.copyWith(
          status: DownloadQueueTaskStatus.downloading,
          progressLabel: '正在缓存 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: readerPage.imageUrls.length,
          errorMessage: '',
          updatedAt: DateTime.now(),
        ),
      );

      await _taskRunner.download(
        task,
        readerPage,
        shouldPause: () => _shouldPauseActiveDownload(task),
        shouldCancel: () => _shouldCancelActiveDownload(task),
        onProgress: (ChapterDownloadProgress progress) async {
          final DownloadQueueTask? latestTask = _taskById(task.id);
          if (latestTask == null || _disposed) {
            return;
          }
          await _updateTask(
            latestTask.copyWith(
              status: DownloadQueueTaskStatus.downloading,
              progressLabel: '${task.chapterLabel} · ${progress.currentLabel}',
              completedImages: progress.completedCount,
              totalImages: progress.totalCount,
              errorMessage: '',
              updatedAt: DateTime.now(),
            ),
            persist: false,
          );
        },
      );

      final DownloadQueueSnapshot currentSnapshot = snapshot;
      final List<DownloadQueueTask> remainingTasks = currentSnapshot.tasks
          .where((DownloadQueueTask item) => item.id != task.id)
          .toList(growable: false);
      await _persistSnapshot(
        currentSnapshot.copyWith(
          isPaused: remainingTasks.isEmpty ? false : currentSnapshot.isPaused,
          tasks: remainingTasks,
        ),
      );
      final List<DownloadQueueTask>? tasksToCleanup =
          _pendingCancelledTaskCleanups.remove(task.id);
      final String? comicDeletionTitle = _pendingCancelledComicDeletions.remove(
        task.id,
      );
      if (comicDeletionTitle != null) {
        await _downloadService.deleteComicCacheByTitle(comicDeletionTitle);
      } else if (tasksToCleanup != null) {
        await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
      }
      await _notifyLibraryChanged();

      if (remainingTasks.isEmpty) {
        _notify('后台缓存已完成');
      }
    } on DownloadPausedException {
      final DownloadQueueTask? latestTask = _taskById(task.id);
      if (latestTask != null) {
        final String pauseLabel =
            latestTask.totalImages > 0 && latestTask.completedImages > 0
            ? '已暂停 ${latestTask.completedImages}/${latestTask.totalImages}'
            : '已暂停';
        await _updateTask(
          latestTask.copyWith(
            status: DownloadQueueTaskStatus.paused,
            progressLabel: pauseLabel,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } on DownloadCancelledException {
      final List<DownloadQueueTask> tasksToCleanup =
          _pendingCancelledTaskCleanups.remove(task.id) ??
          <DownloadQueueTask>[task];
      final String? comicDeletionTitle = _pendingCancelledComicDeletions.remove(
        task.id,
      );
      if (comicDeletionTitle != null) {
        await _downloadService.deleteComicCacheByTitle(comicDeletionTitle);
      } else {
        await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
      }
      await _notifyLibraryChanged();
    } catch (error) {
      final DownloadQueueTask? latestTask = _taskById(task.id);
      final String message = _formatDownloadError(error);
      if (latestTask == null) {
        final List<DownloadQueueTask>? tasksToCleanup =
            _pendingCancelledTaskCleanups.remove(task.id);
        final String? comicDeletionTitle = _pendingCancelledComicDeletions
            .remove(task.id);
        if (comicDeletionTitle != null) {
          await _downloadService.deleteComicCacheByTitle(comicDeletionTitle);
          await _notifyLibraryChanged();
          return;
        }
        if (tasksToCleanup != null) {
          await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
          await _notifyLibraryChanged();
          return;
        }
      }
      if (latestTask != null) {
        final DownloadQueueSnapshot currentSnapshot = snapshot;
        final List<DownloadQueueTask> tasks = currentSnapshot.tasks
            .map((DownloadQueueTask item) {
              if (item.id != latestTask.id) {
                return item;
              }
              return latestTask.copyWith(
                status: DownloadQueueTaskStatus.failed,
                progressLabel: '失败：$message',
                errorMessage: message,
                updatedAt: DateTime.now(),
              );
            })
            .toList(growable: false);
        await _persistSnapshot(
          currentSnapshot.copyWith(isPaused: true, tasks: tasks),
        );
      }
      _notify('缓存失败：$message');
    } finally {
      if (_runningTaskId == task.id) {
        _runningTaskId = null;
        _runningComicKey = null;
      }
    }
  }

  bool _isTaskRunning(String taskId) => _runningTaskId == taskId;

  bool _isComicRunning(String comicKey) => _runningComicKey == comicKey;

  Future<void> _watchStorageCleanup(Future<String> cleanupFuture) async {
    final Object token = Object();
    _activeStorageCleanupToken = token;
    try {
      final String cleanupWarning = await cleanupFuture;
      if (_disposed || _activeStorageCleanupToken != token) {
        return;
      }
      if (cleanupWarning.isNotEmpty) {
        _notify(cleanupWarning);
      }
    } finally {
      if (!_disposed && _activeStorageCleanupToken == token) {
        _activeStorageCleanupToken = null;
        storageMigrationProgressNotifier.value = null;
      }
    }
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

  String _comicKey(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return value.trim();
    }
    return Uri(path: uri.path).toString();
  }

  Future<void> _notifyLibraryChanged() async {
    if (_disposed || _onLibraryChanged == null) {
      return;
    }
    await _onLibraryChanged();
  }

  void _notify(String message) {
    if (_disposed || message.trim().isEmpty) {
      return;
    }
    _onNotice?.call(message);
  }

  String _formatDownloadError(Object error) {
    return switch (error) {
      TimeoutException _ => '章节解析超时',
      HttpException httpError => httpError.message,
      FileSystemException fileError => fileError.message,
      DownloadPausedException paused => paused.message,
      DownloadCancelledException cancelled => cancelled.message,
      _ => error.toString(),
    };
  }
}
