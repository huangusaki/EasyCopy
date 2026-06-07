import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';
import 'package:reader/services/storage_migration_store.dart';

part 'download_queue_manager/migration_coordinator.dart';

typedef LibraryChangedCallback =
    Future<void> Function(CacheLibraryRefreshReason reason);
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
    MigrationDeltaJournalStore? deltaJournalStore,
    LibraryChangedCallback? onLibraryChanged,
    DownloadQueueNoticeCallback? onNotice,
  }) : _preferencesController = preferencesController,
       _downloadService = downloadService,
       _queueStore = queueStore,
       _taskRunner = taskRunner,
       _migrationStore =
           migrationStore ?? DownloadStorageMigrationStore.instance,
       _deltaJournalStore =
           deltaJournalStore ?? MigrationDeltaJournalStore.instance,
       _onLibraryChanged = onLibraryChanged,
       _onNotice = onNotice;

  final AppPreferencesController _preferencesController;
  final ComicDownloadService _downloadService;
  final DownloadQueueStore _queueStore;
  final DownloadTaskRunner _taskRunner;
  final DownloadStorageMigrationStore _migrationStore;
  final MigrationDeltaJournalStore _deltaJournalStore;
  final LibraryChangedCallback? _onLibraryChanged;
  final DownloadQueueNoticeCallback? _onNotice;

  final ValueNotifier<DownloadQueueSnapshot> snapshotNotifier =
      ValueNotifier<DownloadQueueSnapshot>(const DownloadQueueSnapshot());
  final ValueNotifier<DownloadStorageState> storageStateNotifier =
      ValueNotifier<DownloadStorageState>(const DownloadStorageState.loading());
  final ValueNotifier<bool> storageBusyNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<StorageMigrationProgress?> migrationProgressNotifier =
      ValueNotifier<StorageMigrationProgress?>(null);

  final Map<String, List<DownloadQueueTask>> _pendingCancelledTaskCleanups =
      <String, List<DownloadQueueTask>>{};
  final Map<String, String> _pendingCancelledComicDeletions =
      <String, String>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  static const Duration _migrationProgressUiInterval = Duration(
    milliseconds: 220,
  );
  static const Duration _failedRetryDelay = Duration(seconds: 5);
  static const int _maxAutoRetryCount = 3;

  bool _isProcessingQueue = false;
  bool _disposed = false;
  String? _runningTaskId;
  String? _runningComicKey;
  bool _storageSwitchPending = false;
  Future<void>? _activeMigrationTask;
  PendingDownloadStorageMigration? _pendingMigration;
  Timer? _migrationFlushTimer;
  StorageMigrationProgress? _pendingMigrationProgress;
  StorageMigrationProgress? _lastMigrationProgress;
  DateTime? _lastMigrationAt;

  DownloadQueueSnapshot get snapshot => snapshotNotifier.value;

  DownloadStorageState get storageState => storageStateNotifier.value;

  bool get supportsCustomStorageSelection =>
      _downloadService.supportsCustomStorageSelection;

  bool get shouldBypassCachedReaderLookup =>
      _activeMigrationTask != null ||
      storageBusyNotifier.value ||
      migrationProgressNotifier.value != null;

  Future<void> restoreState() async {
    await _queueStore.ensureInitialized();
    await refreshStorageState();
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = await _queueStore.read();
    _syncRetryTimers(snapshotNotifier.value);
  }

  Future<void> restoreQueue() async {
    await _queueStore.ensureInitialized();
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = await _queueStore.read();
    _syncRetryTimers(snapshotNotifier.value);
  }

  Future<void> recoverStorageMigration() async {
    await _migrationStore.ensureInitialized();
    await _deltaJournalStore.ensureInitialized();
    if (_disposed || _activeMigrationTask != null) {
      return;
    }
    final PendingDownloadStorageMigration? pendingMigration =
        await _migrationStore.read();
    if (pendingMigration == null) {
      return;
    }
    final DownloadPreferences currentPreferences =
        _preferencesController.downloadPreferences;
    if (!currentPreferences.hasSameStorageLocation(pendingMigration.from) &&
        !currentPreferences.hasSameStorageLocation(pendingMigration.to)) {
      await _migrationStore.clear();
      await _deltaJournalStore.clear();
      _pendingMigration = null;
      return;
    }
    _pendingMigration = pendingMigration;
    final DownloadStorageState currentState = await _downloadService
        .resolveStorageState(
          preferences: currentPreferences,
          verifyWritable: false,
        );
    if (!_disposed) {
      storageStateNotifier.value = currentState;
    }
    _startMigrationTask(pendingMigration, isRecovery: true);
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
              autoRetryCount: 0,
              clearNextRetryAt: true,
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
      autoRetryCount: 0,
      clearNextRetryAt: true,
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
      await _recordTaskCleanupForMigration(removedTasks);
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
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
      await _recordTaskCleanupForMigration(<DownloadQueueTask>[task]);
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
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
    await _recordComicDeletion(task.comicTitle);
    await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
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
    await _recordTaskCleanupForMigration(removedTasks);
    await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
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
      await _recordComicDeletion(entry.comicTitle);
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
      return;
    }

    if (_runningTaskId != null) {
      _pendingCancelledComicDeletions[_runningTaskId!] = entry.comicTitle;
    }
  }

  String? storageEditBlockReason() {
    if (_activeMigrationTask != null ||
        storageBusyNotifier.value ||
        migrationProgressNotifier.value != null) {
      return '正在切换缓存目录，请稍后再试';
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
    if (_activeMigrationTask != null ||
        migrationProgressNotifier.value != null) {
      throw const FileSystemException('已有缓存目录迁移正在进行中。');
    }
    final DownloadStorageState fromState = await _downloadService
        .resolveStorageState(
          preferences: currentPreferences,
          verifyWritable: false,
        );
    final DownloadStorageState toState = await _downloadService
        .resolveStorageState(
          preferences: nextPreferences,
          verifyWritable: true,
        );
    if (!toState.isReady) {
      throw FileSystemException(
        toState.errorMessage.isEmpty ? '目标缓存目录不可用。' : toState.errorMessage,
      );
    }
    final String fromStorageKey = await _downloadService
        .storageKeyForPreferences(currentPreferences);
    final String toStorageKey = await _downloadService.storageKeyForPreferences(
      nextPreferences,
      verifyWritable: true,
    );
    final PendingDownloadStorageMigration pendingMigration =
        PendingDownloadStorageMigration(
          from: currentPreferences,
          to: nextPreferences,
          createdAt: DateTime.now(),
          storageKey: '$fromStorageKey->$toStorageKey',
          activeStorageKey: fromStorageKey,
          phase: DownloadStorageMigrationStep.copying,
        );
    await _migrationStore.write(pendingMigration);
    await _deltaJournalStore.clear();
    _pendingMigration = pendingMigration;
    storageStateNotifier.value = fromState;
    _setMigrationProgressVisible(
      StorageMigrationProgress(
        phase: DownloadStorageMigrationPhase.preparing,
        fromPath: fromState.displayPath,
        toPath: toState.displayPath,
        message: '正在后台迁移缓存目录…',
      ),
      immediate: true,
    );
    _startMigrationTask(pendingMigration, isRecovery: false);
    return DownloadStorageMigrationResult(storageState: fromState);
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
        if (_storageSwitchPending) {
          break;
        }
        final DownloadQueueSnapshot currentSnapshot = snapshot;
        if (currentSnapshot.isPaused || currentSnapshot.isEmpty) {
          break;
        }
        final DownloadQueueTask activeTask = currentSnapshot.activeTask!;
        if (activeTask.status == DownloadQueueTaskStatus.failed) {
          if (activeTask.nextRetryAt == null) {
            break;
          }
          if (activeTask.nextRetryAt!.isAfter(DateTime.now())) {
            _scheduleRetryTimer(activeTask);
            break;
          }
          await _resumeFailedTaskIfReady(activeTask.id);
          continue;
        }
        await _runTask(activeTask);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  void _syncRetryTimers(DownloadQueueSnapshot nextSnapshot) {
    final Set<String> activeRetryTaskIds = <String>{};
    if (!nextSnapshot.isPaused) {
      for (final DownloadQueueTask task in nextSnapshot.tasks) {
        if (task.status != DownloadQueueTaskStatus.failed ||
            task.nextRetryAt == null) {
          continue;
        }
        activeRetryTaskIds.add(task.id);
        _scheduleRetryTimer(task);
      }
    }

    final List<String> staleTaskIds = _retryTimers.keys
        .where((String taskId) => !activeRetryTaskIds.contains(taskId))
        .toList(growable: false);
    for (final String taskId in staleTaskIds) {
      _cancelRetryTimer(taskId);
    }
  }

  void _scheduleRetryTimer(DownloadQueueTask task) {
    if (_disposed || task.nextRetryAt == null || snapshot.isPaused) {
      _cancelRetryTimer(task.id);
      return;
    }
    final Duration delay = task.nextRetryAt!.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _cancelRetryTimer(task.id);
      unawaited(_resumeFailedTaskIfReady(task.id));
      return;
    }

    _cancelRetryTimer(task.id);
    _retryTimers[task.id] = Timer(delay, () {
      _retryTimers.remove(task.id);
      unawaited(_resumeFailedTaskIfReady(task.id));
    });
  }

  void _cancelRetryTimer(String taskId) {
    final Timer? timer = _retryTimers.remove(taskId);
    timer?.cancel();
  }

  Future<void> _resumeFailedTaskIfReady(String taskId) async {
    if (_disposed || snapshot.isPaused) {
      _cancelRetryTimer(taskId);
      return;
    }

    final DownloadQueueTask? latestTask = _taskById(taskId);
    if (latestTask == null ||
        latestTask.status != DownloadQueueTaskStatus.failed ||
        latestTask.nextRetryAt == null) {
      _cancelRetryTimer(taskId);
      return;
    }

    if (latestTask.nextRetryAt!.isAfter(DateTime.now())) {
      _scheduleRetryTimer(latestTask);
      return;
    }

    _cancelRetryTimer(taskId);
    await _updateTask(
      latestTask.copyWith(
        status: DownloadQueueTaskStatus.queued,
        progressLabel: '等待缓存',
        errorMessage: '',
        completedImages: 0,
        totalImages: 0,
        clearNextRetryAt: true,
        updatedAt: DateTime.now(),
      ),
    );
    if (!_isProcessingQueue) {
      unawaited(ensureRunning());
    }
  }

  void dispose() {
    _disposed = true;
    _migrationFlushTimer?.cancel();
    for (final Timer timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    snapshotNotifier.dispose();
    storageStateNotifier.dispose();
    storageBusyNotifier.dispose();
    migrationProgressNotifier.dispose();
  }

  Future<void> _persistSnapshot(DownloadQueueSnapshot nextSnapshot) async {
    if (_disposed) {
      return;
    }
    snapshotNotifier.value = nextSnapshot;
    _syncRetryTimers(nextSnapshot);
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
      await _recordTaskUpsertForMigration(task);
      final List<DownloadQueueTask>? tasksToCleanup =
          _pendingCancelledTaskCleanups.remove(task.id);
      final String? comicDeletionTitle = _pendingCancelledComicDeletions.remove(
        task.id,
      );
      if (comicDeletionTitle != null) {
        await _downloadService.deleteComicCacheByTitle(comicDeletionTitle);
        await _recordComicDeletion(comicDeletionTitle);
      } else if (tasksToCleanup != null) {
        await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
        await _recordTaskCleanupForMigration(tasksToCleanup);
      }
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);

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
        await _recordComicDeletion(comicDeletionTitle);
      } else {
        await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
        await _recordTaskCleanupForMigration(tasksToCleanup);
      }
      await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
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
          await _recordComicDeletion(comicDeletionTitle);
          await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
          return;
        }
        if (tasksToCleanup != null) {
          await _downloadService.cleanupIncompleteTasks(tasksToCleanup);
          await _recordTaskCleanupForMigration(tasksToCleanup);
          await _notifyLibraryChanged(CacheLibraryRefreshReason.queueChanged);
          return;
        }
      }
      if (latestTask != null) {
        final DateTime now = DateTime.now();
        if (latestTask.autoRetryCount < _maxAutoRetryCount) {
          final int nextRetryCount = latestTask.autoRetryCount + 1;
          final DownloadQueueTask retryTask = latestTask.copyWith(
            status: DownloadQueueTaskStatus.failed,
            progressLabel:
                '失败，${_failedRetryDelay.inSeconds}秒后重试（$nextRetryCount/$_maxAutoRetryCount）',
            errorMessage: message,
            autoRetryCount: nextRetryCount,
            nextRetryAt: now.add(_failedRetryDelay),
            updatedAt: now,
          );
          await _updateTask(retryTask);
          _scheduleRetryTimer(retryTask);
          _notify('缓存失败：$message，${_failedRetryDelay.inSeconds}秒后自动重试');
        } else {
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
                  clearNextRetryAt: true,
                  updatedAt: now,
                );
              })
              .toList(growable: false);
          await _persistSnapshot(
            currentSnapshot.copyWith(isPaused: true, tasks: tasks),
          );
          _notify('缓存失败：$message');
        }
        return;
      }
    } finally {
      if (_runningTaskId == task.id) {
        _runningTaskId = null;
        _runningComicKey = null;
      }
    }
  }

  bool _isTaskRunning(String taskId) => _runningTaskId == taskId;

  bool _isComicRunning(String comicKey) => _runningComicKey == comicKey;

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

  String _formatDownloadError(Object error) {
    return switch (error) {
      TimeoutException _ => '章节解析超时',
      HttpException httpError => httpError.message,
      FileSystemException fileError => fileError.message,
      PlatformException platformError =>
        platformError.message?.trim().isNotEmpty == true
            ? platformError.message!.trim()
            : platformError.code,
      DownloadPausedException paused => paused.message,
      DownloadCancelledException cancelled => cancelled.message,
      _ => error.toString(),
    };
  }
}
