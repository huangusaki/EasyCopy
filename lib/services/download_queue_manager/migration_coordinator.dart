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
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/storage_migration_store.dart';

abstract interface class DownloadMigrationQueue {
  bool get hasActiveDownloads;
  Future<bool> suspendForStorageSwitch();
  Future<void> resumeAfterStorageSwitch(bool wasRunning);
  void continueDownloads();
}

/// Owns migration persistence and progress independently of UI and
/// task execution. The queue and external cache edits share one write barrier.
class DownloadMigrationCoordinator {
  DownloadMigrationCoordinator({
    required AppPreferencesController preferencesController,
    required DownloadMigrationStorage storage,
    required DownloadMigrationQueue queue,
    required DownloadStorageWriteBarrier writes,
    DownloadStorageMigrationStore? migrationStore,
    required Future<void> Function(CacheLibraryRefreshReason) onLibraryChanged,
    required void Function(String) onNotice,
  }) : _preferencesController = preferencesController,
       _storage = storage,
       _queue = queue,
       _writes = writes,
       _migrationStore =
           migrationStore ?? DownloadStorageMigrationStore.instance,
       _notifyLibraryChanged = onLibraryChanged,
       _onNotice = onNotice;

  final AppPreferencesController _preferencesController;
  final DownloadMigrationStorage _storage;
  final DownloadMigrationQueue _queue;
  final DownloadStorageWriteBarrier _writes;
  final DownloadStorageMigrationStore _migrationStore;
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
      _pendingMigration = null;
      return;
    }
    if (pendingMigration.phase != DownloadStorageMigrationStep.copying &&
        pendingMigration.copiedPaths == null) {
      await _migrationStore.clear();
      _notify('已保留上次迁移的两处文件，请重新选择缓存目录。');
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

  Future<bool> applyPreferences(
    DownloadPreferences nextPreferences, {
    bool migrateExisting = true,
  }) async {
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
        return false;
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
      if (fromState.storageIdentity.isNotEmpty &&
          fromState.storageIdentity == toState.storageIdentity) {
        return false;
      }
      if (!migrateExisting) {
        await _switchWithoutMigration(nextPreferences);
        return true;
      }
      await _storage.verifyMigrationSource(currentPreferences);
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
            phase: DownloadStorageMigrationStep.copying,
            resumeQueueAfterMigration: _queue.hasActiveDownloads,
          );
      _checkActive();
      await _migrationStore.write(pendingMigration);
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
      return true;
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

  /// 偏好尚未提交时丢弃失败状态，保留两处文件并允许重新选择目录。
  Future<void> _discardFailedMigration() async {
    _pendingMigration = null;
    try {
      await _migrationStore.clear();
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
    bool? wasRunning;
    bool completed = false;
    try {
      _checkActive();
      storageBusyNotifier.value = true;
      wasRunning = await _queue.suspendForStorageSwitch();
      await _writes.switchStorage(() async {
        _checkActive();
        if (currentMigration.phase == DownloadStorageMigrationStep.copying) {
          currentMigration = await _runMigrationCopyPhase(currentMigration);
        }
        _checkActive();
        if (currentMigration.phase == DownloadStorageMigrationStep.switching) {
          currentMigration = await _runMigrationSwitchPhase(currentMigration);
        }
        _checkActive();
        if (currentMigration.phase == DownloadStorageMigrationStep.cleaning) {
          await _runMigrationCleanupPhase(currentMigration);
        }
      });
      completed = true;
      await _notifyLibraryChanged(CacheLibraryRefreshReason.migrationSwitched);
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
      final bool committed = _preferencesController.downloadPreferences
          .hasSameStorageLocation(pendingMigration.to);
      if (!committed) {
        await _discardFailedMigration();
      } else {
        // Keep the journal for restart, but allow switching away from an
        // unavailable target without trapping the directory picker.
        _pendingMigration = null;
      }
      if (!_disposed) {
        storageBusyNotifier.value = false;
        _clearMigrationProgress();
      }
      _notify(
        committed
            ? '缓存目录已切换，原目录已保留；重启后会重试清理。'
            : '缓存目录迁移失败：${formatDownloadError(error)}',
      );
    } finally {
      if (!_disposed) storageBusyNotifier.value = false;
      if (wasRunning != null) {
        await _queue.resumeAfterStorageSwitch(
          wasRunning || pendingMigration.resumeQueueAfterMigration,
        );
      }
      if (completed) {
        await _migrationStore.clear();
        _pendingMigration = null;
      }
    }
  }

  Future<PendingDownloadStorageMigration> _runMigrationCopyPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    DebugTrace.log('storage_migration.copy_phase_start', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'phase': pendingMigration.phase.name,
    });
    final List<String> copiedPaths = await _storage.migrateCacheRoot(
      from: pendingMigration.from,
      to: pendingMigration.to,
      onProgress: _setMigrationProgress,
    );
    final PendingDownloadStorageMigration nextMigration = pendingMigration
        .copyWith(
          phase: DownloadStorageMigrationStep.switching,
          copiedPaths: copiedPaths,
        );
    _checkActive();
    await _persistMigration(nextMigration);
    DebugTrace.log('storage_migration.copy_phase_complete', <String, Object?>{
      'migrationId': pendingMigration.storageKey,
      'nextPhase': nextMigration.phase.name,
    });
    return nextMigration;
  }

  Future<void> _switchWithoutMigration(DownloadPreferences preferences) async {
    storageBusyNotifier.value = true;
    bool? wasRunning;
    try {
      wasRunning = await _queue.suspendForStorageSwitch();
      await _writes.switchStorage(() async {
        _checkActive();
        final DownloadStorageState target = await _storage.resolveStorageState(
          preferences: preferences,
          verifyWritable: true,
        );
        _requireReady(target);
        await _preferencesController.updateDownloadPreferences(
          (_) => preferences,
        );
        _checkActive();
        storageStateNotifier.value = target;
      });
      await _notifyLibraryChanged(CacheLibraryRefreshReason.migrationSwitched);
    } finally {
      if (!_disposed) storageBusyNotifier.value = false;
      if (wasRunning != null) await _queue.resumeAfterStorageSwitch(wasRunning);
    }
  }

  void _requireReady(DownloadStorageState state) {
    if (!state.isReady) {
      throw FileSystemException(
        state.errorMessage.isEmpty ? '目标缓存目录不可用。' : state.errorMessage,
      );
    }
  }

  Future<PendingDownloadStorageMigration> _runMigrationSwitchPhase(
    PendingDownloadStorageMigration pendingMigration,
  ) async {
    _checkActive();
    final DownloadStorageState toState = await _storage.resolveStorageState(
      preferences: pendingMigration.to,
      verifyWritable: true,
    );
    _requireReady(toState);
    await _storage.verifyMigratedCache(
      from: pendingMigration.from,
      to: pendingMigration.to,
      relativePaths: pendingMigration.copiedPaths!,
    );
    _checkActive();
    await _storage.copyCachedLibraryIndex(
      from: pendingMigration.from,
      to: pendingMigration.to,
    );
    _checkActive();
    await _preferencesController.updateDownloadPreferences(
      (_) => pendingMigration.to,
    );
    _checkActive();
    final PendingDownloadStorageMigration nextMigration = pendingMigration
        .copyWith(phase: DownloadStorageMigrationStep.cleaning);
    await _persistMigration(nextMigration);
    if (!_disposed) storageStateNotifier.value = toState;
    return nextMigration;
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
      from: pendingMigration.from,
      to: pendingMigration.to,
      relativePaths: pendingMigration.copiedPaths!,
      onProgress: _setMigrationProgress,
    );
    _checkActive();

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
}

class _MigrationStoppedException implements Exception {
  const _MigrationStoppedException();
}
