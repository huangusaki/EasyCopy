part of '../download_queue_manager.dart';

extension _DownloadMigrationCoordinator on DownloadQueueManager {
  void _startMigrationTask(
    PendingDownloadStorageMigration pendingMigration, {
    required bool isRecovery,
  }) {
    if (_disposed || _activeMigrationTask != null) {
      return;
    }
    _pendingMigration = pendingMigration;
    late final Future<void> task;
    task = _runMigrationFlow(pendingMigration, isRecovery: isRecovery)
        .whenComplete(() {
          if (identical(_activeMigrationTask, task)) {
            _activeMigrationTask = null;
          }
          if (!_disposed) {
            unawaited(ensureRunning());
          }
        });
    _activeMigrationTask = task;
  }

  Future<void> _runMigrationFlow(
    PendingDownloadStorageMigration pendingMigration, {
    required bool isRecovery,
  }) async {
    PendingDownloadStorageMigration currentMigration = pendingMigration;
    final Stopwatch stopwatch = Stopwatch()..start();
    DebugTrace.log('storage_migration.flow_start', <String, Object?>{
      'migrationId': currentMigration.storageKey,
      'phase': currentMigration.phase.name,
      'trigger': isRecovery ? 'recovery' : 'manual',
      'pendingAgeMs': DateTime.now()
          .difference(currentMigration.createdAt)
          .inMilliseconds,
    });
    try {
      if (currentMigration.phase == DownloadStorageMigrationStep.copying) {
        currentMigration = await _runMigrationCopyPhase(currentMigration);
      }
      if (currentMigration.phase == DownloadStorageMigrationStep.switching) {
        currentMigration = await _runMigrationSwitchPhase(currentMigration);
      }
      if (currentMigration.phase == DownloadStorageMigrationStep.cleaning ||
          currentMigration.cleanupPending) {
        if (!_disposed) {
          storageBusyNotifier.value = false;
          _storageSwitchPending = false;
        }
        unawaited(ensureRunning());
        await _runMigrationCleanupPhase(currentMigration);
      }
      DebugTrace.log('storage_migration.flow_complete', <String, Object?>{
        'migrationId': pendingMigration.storageKey,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
    } catch (error) {
      DebugTrace.log('storage_migration.flow_failed', <String, Object?>{
        'migrationId': pendingMigration.storageKey,
        'phase': _pendingMigration?.phase.name ?? pendingMigration.phase.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': error.toString(),
      });
      if (!_disposed) {
        storageBusyNotifier.value = false;
        _storageSwitchPending = false;
        _clearMigrationProgress();
      }
      _notify('缓存目录迁移失败：${_formatDownloadError(error)}');
    }
  }

  Future<PendingDownloadStorageMigration> _runMigrationCopyPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    DebugTrace.log('storage_migration.copy_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'phase': pendingMigration.phase.name,
    });
    await _downloadService.migrateCacheRoot(
      from: pendingMigration.from,
      to: pendingMigration.to,
      onProgress: _setMigrationProgress,
    );
    final String fromStorageKey = await _downloadService
        .storageKeyForPreferences(pendingMigration.from);
    final PendingDownloadStorageMigration nextMigration = pendingMigration
        .copyWith(
          phase: DownloadStorageMigrationStep.switching,
          activeStorageKey: fromStorageKey,
          cleanupPending: true,
        );
    await _persistMigration(nextMigration);
    DebugTrace.log('storage_migration.copy_phase_complete', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'nextPhase': nextMigration.phase.name,
    });
    return nextMigration;
  }

  Future<PendingDownloadStorageMigration> _runMigrationSwitchPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    final bool resumeQueueAfterSwitch =
        snapshot.isNotEmpty && !snapshot.isPaused;
    if (resumeQueueAfterSwitch) {
      await _persistSnapshot(snapshot.copyWith(isPaused: true));
    }
    if (!_disposed) {
      _storageSwitchPending = true;
      storageBusyNotifier.value = true;
    }
    await _waitForQueueIdle();

    final DownloadStorageState fromState = await _downloadService
        .resolveStorageState(
          preferences: pendingMigration.from,
          verifyWritable: false,
        );
    final DownloadStorageState toState = await _downloadService
        .resolveStorageState(
          preferences: pendingMigration.to,
          verifyWritable: true,
        );
    final List<MigrationDeltaEntry> deltas = await _deltaJournalStore.read(
      pendingMigration.storageKey,
    );
    DebugTrace.log('storage_migration.switch_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'deltaReplayCount': deltas.length,
      'fromPath': fromState.displayPath,
      'toPath': toState.displayPath,
    });
    _setMigrationProgressVisible(
      StorageMigrationProgress(
        phase: DownloadStorageMigrationPhase.preparing,
        fromPath: fromState.displayPath,
        toPath: toState.displayPath,
        message: '正在切换缓存目录…',
      ),
      immediate: true,
    );
    if (deltas.isNotEmpty) {
      await _downloadService.applyMigrationDeltas(
        from: pendingMigration.from,
        to: pendingMigration.to,
        entries: deltas,
        onProgress: _setMigrationProgress,
      );
    }
    await _downloadService.copyCachedLibraryIndex(
      from: pendingMigration.from,
      to: pendingMigration.to,
    );
    await _preferencesController.updateDownloadPreferences(
      (_) => pendingMigration.to,
    );
    await _deltaJournalStore.clear(pendingMigration.storageKey);
    final String targetStorageKey = await _downloadService
        .storageKeyForPreferences(pendingMigration.to);
    final PendingDownloadStorageMigration nextMigration = pendingMigration
        .copyWith(
          phase: DownloadStorageMigrationStep.cleaning,
          activeStorageKey: targetStorageKey,
          cleanupPending: true,
        );
    await _persistMigration(nextMigration);
    if (!_disposed) {
      storageStateNotifier.value = toState;
      storageBusyNotifier.value = false;
      _storageSwitchPending = false;
    }
    await _notifyLibraryChanged(CacheLibraryRefreshReason.migrationSwitched);
    if (resumeQueueAfterSwitch &&
        !_disposed &&
        snapshot.isNotEmpty &&
        snapshot.isPaused) {
      await _persistSnapshot(snapshot.copyWith(isPaused: false));
    }
    DebugTrace.log('storage_migration.switch_phase_complete', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'deltaReplayCount': deltas.length,
    });
    return nextMigration;
  }

  Future<void> _runMigrationCleanupPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    DebugTrace.log('storage_migration.cleanup_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'fromPath': pendingMigration.from.displayPath,
    });
    final String cleanupWarning = await _downloadService
        .cleanupStorageDirectory(
          preferences: pendingMigration.from,
          onProgress: _setMigrationProgress,
        );
    await _deltaJournalStore.clear(pendingMigration.storageKey);
    await _migrationStore.clear();
    _pendingMigration = null;
    if (!_disposed) {
      _clearMigrationProgress();
      storageBusyNotifier.value = false;
      _storageSwitchPending = false;
    }
    if (cleanupWarning.isNotEmpty) {
      _notify(cleanupWarning);
    }
    DebugTrace.log(
      'storage_migration.cleanup_phase_complete',
      <String, Object?>{
        'migrationId': pendingMigration.storageKey,
        'warning': cleanupWarning,
      },
    );
  }

  Future<void> _waitForQueueIdle() async {
    while (!_disposed && (_runningTaskId != null || _isProcessingQueue)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _persistMigration(
    PendingDownloadStorageMigration migration,
  ) async {
    _pendingMigration = migration;
    await _migrationStore.write(migration);
  }

  Future<void> _setMigrationProgress(StorageMigrationProgress progress) async {
    if (_disposed) {
      return;
    }
    _setMigrationProgressVisible(progress);
  }

  void _setMigrationProgressVisible(
    StorageMigrationProgress progress, {
    bool immediate = false,
  }) {
    if (_disposed) {
      return;
    }
    if (immediate || _shouldShowMigrationNow(progress)) {
      _publishMigrationProgress(progress);
      return;
    }
    _pendingMigrationProgress = progress;
    _scheduleMigrationProgressFlush();
  }

  bool _shouldShowMigrationNow(StorageMigrationProgress progress) {
    final StorageMigrationProgress? lastProgress = _lastMigrationProgress;
    if (lastProgress == null) {
      return true;
    }
    if (lastProgress.phase != progress.phase ||
        lastProgress.totalItems != progress.totalItems ||
        progress.completedItems <= 3 ||
        (progress.totalItems > 0 &&
            progress.completedItems >= progress.totalItems)) {
      return true;
    }
    final DateTime? lastUpdatedAt = _lastMigrationAt;
    if (lastUpdatedAt == null) {
      return true;
    }
    return DateTime.now().difference(lastUpdatedAt) >=
        DownloadQueueManager._migrationProgressUiInterval;
  }

  void _scheduleMigrationProgressFlush() {
    if (_disposed || _migrationFlushTimer != null) {
      return;
    }
    final DateTime? lastUpdatedAt = _lastMigrationAt;
    final Duration delay = lastUpdatedAt == null
        ? Duration.zero
        : DownloadQueueManager._migrationProgressUiInterval -
              DateTime.now().difference(lastUpdatedAt);
    _migrationFlushTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _flushMigrationProgress,
    );
  }

  void _flushMigrationProgress() {
    _migrationFlushTimer?.cancel();
    _migrationFlushTimer = null;
    if (_disposed) {
      _pendingMigrationProgress = null;
      return;
    }
    final StorageMigrationProgress? queuedProgress = _pendingMigrationProgress;
    if (queuedProgress == null) {
      return;
    }
    _pendingMigrationProgress = null;
    _publishMigrationProgress(queuedProgress);
  }

  void _publishMigrationProgress(StorageMigrationProgress progress) {
    _migrationFlushTimer?.cancel();
    _migrationFlushTimer = null;
    _pendingMigrationProgress = null;
    _lastMigrationProgress = progress;
    _lastMigrationAt = DateTime.now();
    migrationProgressNotifier.value = progress;
  }

  void _clearMigrationProgress() {
    _migrationFlushTimer?.cancel();
    _migrationFlushTimer = null;
    _pendingMigrationProgress = null;
    _lastMigrationProgress = null;
    _lastMigrationAt = null;
    migrationProgressNotifier.value = null;
  }

  Future<void> _recordMigrationDelta(MigrationDeltaEntry entry) async {
    final PendingDownloadStorageMigration? pendingMigration = _pendingMigration;
    if (_disposed ||
        pendingMigration == null ||
        pendingMigration.phase != DownloadStorageMigrationStep.copying ||
        entry.relativePath.trim().isEmpty) {
      return;
    }
    await _deltaJournalStore.append(pendingMigration.storageKey, entry);
    DebugTrace.log('storage_migration.delta_recorded', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'phase': pendingMigration.phase.name,
      'kind': entry.kind.name,
      'relativePath': entry.relativePath,
    });
  }

  Future<void> _recordTaskUpsertForMigration(DownloadQueueTask task) {
    return _recordMigrationDelta(
      MigrationDeltaEntry(
        kind: MigrationDeltaKind.upsertChapter,
        relativePath: _downloadService.chapterDirectoryPath(
          task.comicTitle,
          task.chapterLabel,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _recordTaskCleanupForMigration(
    Iterable<DownloadQueueTask> tasks,
  ) async {
    final Set<String> seenPaths = <String>{};
    for (final DownloadQueueTask task in tasks) {
      final String relativePath = _downloadService.chapterDirectoryPath(
        task.comicTitle,
        task.chapterLabel,
      );
      if (relativePath.isEmpty || !seenPaths.add(relativePath)) {
        continue;
      }
      await _recordMigrationDelta(
        MigrationDeltaEntry(
          kind: MigrationDeltaKind.deleteChapter,
          relativePath: relativePath,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _recordComicDeletion(String comicTitle) {
    return _recordMigrationDelta(
      MigrationDeltaEntry(
        kind: MigrationDeltaKind.deleteComic,
        relativePath: _downloadService.comicDirectoryPath(comicTitle),
        updatedAt: DateTime.now(),
      ),
    );
  }
}
