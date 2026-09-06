import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/download_queue_manager/migration_storage.dart';
import 'package:reader/services/download_queue_manager/retry_policy.dart';
import 'package:reader/services/download_queue_manager/storage_write_barrier.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';
import 'package:reader/services/storage_migration_store.dart';

abstract interface class DownloadMigrationQueue {
  Future<bool> suspendForStorageSwitch();
  Future<void> resumeAfterStorageSwitch(bool wasRunning);
  void continueDownloads();
}

/// Owns migration persistence, delta replay and progress independently of UI and
/// task execution. The queue and external cache edits share one write barrier.
class DownloadMigrationCoordinator {
  DownloadMigrationCoordinator({
    required AppPreferencesController preferencesController,
    required DownloadMigrationStorage storage,
    required DownloadMigrationQueue queue,
    required DownloadStorageWriteBarrier writes,
    DownloadStorageMigrationStore? migrationStore,
    MigrationDeltaJournalStore? deltaJournalStore,
    required Future<void> Function(CacheLibraryRefreshReason) onLibraryChanged,
    required void Function(String) onNotice,
  }) : _preferencesController = preferencesController,
       _storage = storage,
       _queue = queue,
       _writes = writes,
       _migrationStore =
           migrationStore ?? DownloadStorageMigrationStore.instance,
       _deltaJournalStore =
           deltaJournalStore ?? MigrationDeltaJournalStore.instance,
       _notifyLibraryChanged = onLibraryChanged,
       _onNotice = onNotice;

  final AppPreferencesController _preferencesController;
  final DownloadMigrationStorage _storage;
  final DownloadMigrationQueue _queue;
  final DownloadStorageWriteBarrier _writes;
  final DownloadStorageMigrationStore _migrationStore;
  final MigrationDeltaJournalStore _deltaJournalStore;
  final Future<void> Function(CacheLibraryRefreshReason) _notifyLibraryChanged;
  final void Function(String) _onNotice;
  final ValueNotifier<DownloadStorageState> storageStateNotifier =
      ValueNotifier<DownloadStorageState>(const DownloadStorageState.loading());
  final ValueNotifier<bool> storageBusyNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<StorageMigrationProgress?> migrationProgressNotifier =
      ValueNotifier<StorageMigrationProgress?>(null);
  static const Duration _migrationProgressUiInterval = Duration(
    milliseconds: 220,
  );
  bool _disposed = false;
  bool _starting = false;
  Future<void>? _activeMigrationTask;
  PendingDownloadStorageMigration? _pendingMigration;
  Timer? _migrationFlushTimer;
  StorageMigrationProgress? _pendingMigrationProgress;
  StorageMigrationProgress? _lastMigrationProgress;
  DateTime? _lastMigrationAt;

  bool get isActive =>
      _starting ||
      _activeMigrationTask != null ||
      _pendingMigration != null ||
      migrationProgressNotifier.value != null;
  Future<void> get settled => _activeMigrationTask ?? Future<void>.value();

  void _checkActive() {
    if (_disposed) throw const _MigrationStoppedException();
  }

  void _notify(String message) {
    if (!_disposed) _onNotice(message);
  }

  void dispose() {
    _disposed = true;
    _migrationFlushTimer?.cancel();
    storageStateNotifier.dispose();
    storageBusyNotifier.dispose();
    migrationProgressNotifier.dispose();
  }

  Future<void> recover() async {
    await _preferencesController.ensureInitialized();
    await _migrationStore.ensureInitialized();
    await _deltaJournalStore.ensureInitialized();
    if (_disposed || _activeMigrationTask != null) {
      return;
    }
    final PendingDownloadStorageMigration? pendingMigration =
        await _migrationStore.read();
    if (_disposed || pendingMigration == null) {
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
    final DownloadStorageState currentState = await _storage
        .resolveStorageState(
          preferences: currentPreferences,
          verifyWritable: false,
        );
    if (!_disposed) {
      storageStateNotifier.value = currentState;
    }
    _checkActive();
    _startMigrationTask(pendingMigration, isRecovery: true);
  }

  Future<DownloadStorageMigrationResult?> applyPreferences(
    DownloadPreferences nextPreferences,
  ) async {
    if (isActive) {
      throw const FileSystemException('已有缓存目录迁移正在进行中。');
    }
    _starting = true;
    try {
      await _preferencesController.ensureInitialized();
      _checkActive();
      final DownloadPreferences currentPreferences =
          _preferencesController.downloadPreferences;
      if (currentPreferences.hasSameStorageLocation(nextPreferences)) {
        return null;
      }
      final DownloadStorageState fromState = await _storage.resolveStorageState(
        preferences: currentPreferences,
        verifyWritable: false,
      );
      final DownloadStorageState toState = await _storage.resolveStorageState(
        preferences: nextPreferences,
        verifyWritable: true,
      );
      if (!toState.isReady) {
        throw FileSystemException(
          toState.errorMessage.isEmpty ? '目标缓存目录不可用。' : toState.errorMessage,
        );
      }
      final String fromStorageKey = await _storage.storageKeyForPreferences(
        currentPreferences,
      );
      final String toStorageKey = await _storage.storageKeyForPreferences(
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
      _checkActive();
      await _migrationStore.write(pendingMigration);
      await _deltaJournalStore.clear();
      _pendingMigration = pendingMigration;
      _checkActive();
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
    } finally {
      _starting = false;
    }
  }

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
            _queue.continueDownloads();
          }
        });
    _activeMigrationTask = task;
  }

  /// 丢弃 copying 阶段的失败状态；后续阶段仍需恢复。
  Future<void> _discardFailedMigration() async {
    _pendingMigration = null;
    try {
      await _migrationStore.clear();
      await _deltaJournalStore.clear();
    } catch (_) {
      // 清理失败不覆盖原始迁移异常。
    }
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
      _checkActive();
      if (currentMigration.phase == DownloadStorageMigrationStep.copying) {
        currentMigration = await _runMigrationCopyPhase(currentMigration);
      }
      _checkActive();
      if (currentMigration.phase == DownloadStorageMigrationStep.switching) {
        currentMigration = await _runMigrationSwitchPhase(currentMigration);
      }
      _checkActive();
      if (currentMigration.phase == DownloadStorageMigrationStep.cleaning ||
          currentMigration.cleanupPending) {
        if (!_disposed) {
          storageBusyNotifier.value = false;
        }
        _queue.continueDownloads();
        await _runMigrationCleanupPhase(currentMigration);
      }
      DebugTrace.log('storage_migration.flow_complete', <String, Object?>{
        'migrationId': pendingMigration.storageKey,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
    } on _MigrationStoppedException {
      // Keep the persisted phase so a new coordinator can recover it.
    } catch (error) {
      final DownloadStorageMigrationStep failedPhase =
          _pendingMigration?.phase ?? pendingMigration.phase;
      DebugTrace.log('storage_migration.flow_failed', <String, Object?>{
        'migrationId': pendingMigration.storageKey,
        'phase': failedPhase.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': error.toString(),
      });
      // 后续阶段保留记录，以便恢复切换并清理旧目录。
      if (failedPhase == DownloadStorageMigrationStep.copying) {
        await _discardFailedMigration();
      }
      if (!_disposed) {
        storageBusyNotifier.value = false;
        _clearMigrationProgress();
      }
      _notify('缓存目录迁移失败：${formatDownloadError(error)}');
    }
  }

  Future<PendingDownloadStorageMigration> _runMigrationCopyPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    DebugTrace.log('storage_migration.copy_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'phase': pendingMigration.phase.name,
    });
    await _storage.migrateCacheRoot(
      from: pendingMigration.from,
      to: pendingMigration.to,
      onProgress: _setMigrationProgress,
    );
    final String fromStorageKey = await _storage.storageKeyForPreferences(
      pendingMigration.from,
    );
    final PendingDownloadStorageMigration nextMigration = pendingMigration
        .copyWith(
          phase: DownloadStorageMigrationStep.switching,
          activeStorageKey: fromStorageKey,
          cleanupPending: true,
        );
    _checkActive();
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
    _checkActive();
    storageBusyNotifier.value = true;
    final bool resumeQueueAfterSwitch = await _queue.suspendForStorageSwitch();
    try {
      final PendingDownloadStorageMigration switched = await _writes
          .switchStorage(() async {
            _checkActive();
            final DownloadStorageState fromState = await _storage
                .resolveStorageState(
                  preferences: pendingMigration.from,
                  verifyWritable: false,
                );
            final DownloadStorageState toState = await _storage
                .resolveStorageState(
                  preferences: pendingMigration.to,
                  verifyWritable: true,
                );
            final List<MigrationDeltaEntry> deltas = await _deltaJournalStore
                .read(pendingMigration.storageKey);
            DebugTrace.log(
              'storage_migration.switch_phase_start',
              <String, Object?>{
                'migrationId': pendingMigration.storageKey,
                'deltaReplayCount': deltas.length,
                'fromPath': fromState.displayPath,
                'toPath': toState.displayPath,
              },
            );
            _setMigrationProgressVisible(
              StorageMigrationProgress(
                phase: DownloadStorageMigrationPhase.preparing,
                fromPath: fromState.displayPath,
                toPath: toState.displayPath,
                message: '正在切换缓存目录…',
              ),
              immediate: true,
            );
            final bool alreadyCommitted = _preferencesController
                .downloadPreferences
                .hasSameStorageLocation(pendingMigration.to);
            _checkActive();
            if (!alreadyCommitted && deltas.isNotEmpty) {
              await _storage.applyMigrationDeltas(
                from: pendingMigration.from,
                to: pendingMigration.to,
                entries: deltas,
                onProgress: _setMigrationProgress,
              );
            }
            _checkActive();
            if (!alreadyCommitted) {
              await _storage.copyCachedLibraryIndex(
                from: pendingMigration.from,
                to: pendingMigration.to,
              );
            }
            _checkActive();
            await _preferencesController.updateDownloadPreferences(
              (_) => pendingMigration.to,
            );
            _checkActive();
            final String targetStorageKey = await _storage
                .storageKeyForPreferences(pendingMigration.to);
            final PendingDownloadStorageMigration nextMigration =
                pendingMigration.copyWith(
                  phase: DownloadStorageMigrationStep.cleaning,
                  activeStorageKey: targetStorageKey,
                  cleanupPending: true,
                );
            await _persistMigration(nextMigration);
            if (!_disposed) {
              storageStateNotifier.value = toState;
              storageBusyNotifier.value = false;
            }
            _checkActive();
            DebugTrace.log(
              'storage_migration.switch_phase_complete',
              <String, Object?>{
                'migrationId': pendingMigration.storageKey,
                'deltaReplayCount': deltas.length,
              },
            );
            return nextMigration;
          });
      _checkActive();
      await _notifyLibraryChanged(CacheLibraryRefreshReason.migrationSwitched);
      return switched;
    } finally {
      if (!_disposed) storageBusyNotifier.value = false;
      await _queue.resumeAfterStorageSwitch(resumeQueueAfterSwitch);
    }
  }

  Future<void> _runMigrationCleanupPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    DebugTrace.log('storage_migration.cleanup_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'fromPath': pendingMigration.from.displayPath,
    });
    _checkActive();
    final String cleanupWarning = await _storage.cleanupStorageDirectory(
      preferences: pendingMigration.from,
      onProgress: _setMigrationProgress,
    );
    _checkActive();
    await _deltaJournalStore.clear(pendingMigration.storageKey);
    await _migrationStore.clear();
    _pendingMigration = null;
    if (!_disposed) {
      _clearMigrationProgress();
      storageBusyNotifier.value = false;
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

  Future<void> _persistMigration(
    PendingDownloadStorageMigration migration,
  ) async {
    await _migrationStore.write(migration);
    _pendingMigration = migration;
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
        _migrationProgressUiInterval;
  }

  void _scheduleMigrationProgressFlush() {
    if (_disposed || _migrationFlushTimer != null) {
      return;
    }
    final DateTime? lastUpdatedAt = _lastMigrationAt;
    final Duration delay = lastUpdatedAt == null
        ? Duration.zero
        : _migrationProgressUiInterval -
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
        pendingMigration.phase == DownloadStorageMigrationStep.cleaning ||
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

  Future<void> recordTaskUpsert(DownloadQueueTask task) {
    return _recordMigrationDelta(
      MigrationDeltaEntry(
        kind: MigrationDeltaKind.upsertChapter,
        relativePath: _storage.chapterDirectoryPath(
          task.comicTitle,
          task.chapterLabel,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> recordTaskCleanup(Iterable<DownloadQueueTask> tasks) async {
    final Set<String> seenPaths = <String>{};
    for (final DownloadQueueTask task in tasks) {
      final String relativePath = _storage.chapterDirectoryPath(
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

  Future<void> recordComicDeletion(String comicTitle) {
    return _recordMigrationDelta(
      MigrationDeltaEntry(
        kind: MigrationDeltaKind.deleteComic,
        relativePath: _storage.comicDirectoryPath(comicTitle),
        updatedAt: DateTime.now(),
      ),
    );
  }
}

class _MigrationStoppedException implements Exception {
  const _MigrationStoppedException();
}
