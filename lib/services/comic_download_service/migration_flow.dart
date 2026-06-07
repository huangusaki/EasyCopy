part of '../comic_download_service.dart';

extension DownloadMigrationOps on ComicDownloadService {
  Future<DownloadStorageMigrationResult> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final DownloadStorageState fromState = await resolveStorageState(
      preferences: from,
      verifyWritable: false,
    );
    final DownloadStorageState toState = await resolveStorageState(
      preferences: to,
      verifyWritable: true,
    );
    if (!toState.isReady) {
      throw FileSystemException(
        toState.errorMessage.isEmpty ? '目标缓存目录不可用。' : toState.errorMessage,
      );
    }
    DebugTrace.log('storage_migration.copy_start', <String, Object?>{
      'fromPath': fromState.displayPath,
      'toPath': toState.displayPath,
      'fromStorageKind': fromState.isDocumentTree ? 'tree' : 'file',
      'toStorageKind': toState.isDocumentTree ? 'tree' : 'file',
    });
    if (_sameStorageLocation(fromState, toState)) {
      return DownloadStorageMigrationResult(storageState: toState);
    }
    if (_storageRootsOverlap(fromState, toState)) {
      throw const FileSystemException('目标缓存目录不能位于当前缓存目录内部，也不能包含当前缓存目录。');
    }
    final _ResolvedStorageRoot sourceRoot = await _resolveStorageRoot(
      preferences: from,
      verifyWritable: false,
    );
    final _ResolvedStorageRoot targetRoot = await _resolveStorageRoot(
      preferences: to,
      verifyWritable: true,
    );
    final _MigrationProgressController progressController =
        _MigrationProgressController(
          fromPath: fromState.displayPath,
          toPath: toState.displayPath,
          onProgress: onProgress,
        );
    await progressController.emitPreparing();
    final List<_StorageEntry> sourceEntries = await sourceRoot.listEntries(
      '',
      recursive: false,
    );
    final bool hasMigratableEntries = sourceEntries.any(
      (_StorageEntry entry) =>
          entry.isDirectory || !_shouldSkipMigrationFile(entry.name),
    );
    if (!hasMigratableEntries) {
      return DownloadStorageMigrationResult(storageState: toState);
    }

    await _migrateStorageContents(
      sourceRoot,
      targetRoot,
      progressController: progressController,
    );
    DebugTrace.log('storage_migration.copy_complete', <String, Object?>{
      'fromPath': fromState.displayPath,
      'toPath': toState.displayPath,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    return DownloadStorageMigrationResult(storageState: toState);
  }

  Future<void> applyMigrationDeltas({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required Iterable<MigrationDeltaEntry> entries,
    MigrationProgressCallback? onProgress,
  }) async {
    final List<MigrationDeltaEntry> operations = entries
        .where((MigrationDeltaEntry entry) => entry.relativePath.isNotEmpty)
        .toList(growable: false);
    if (operations.isEmpty) {
      return;
    }
    final DownloadStorageState fromState = await resolveStorageState(
      preferences: from,
      verifyWritable: false,
    );
    final DownloadStorageState toState = await resolveStorageState(
      preferences: to,
      verifyWritable: true,
    );
    final _ResolvedStorageRoot sourceRoot = await _resolveStorageRootFromState(
      fromState,
    );
    final _ResolvedStorageRoot targetRoot = await _resolveStorageRootFromState(
      toState,
    );
    final _MigrationProgressController progressController =
        _MigrationProgressController(
          fromPath: fromState.displayPath,
          toPath: toState.displayPath,
          onProgress: onProgress,
        );
    await progressController.startMigrating(totalItems: operations.length);
    for (final MigrationDeltaEntry entry in operations) {
      switch (entry.kind) {
        case MigrationDeltaKind.upsertChapter:
          await targetRoot.deletePath(entry.relativePath);
          await _copyRelativePath(sourceRoot, targetRoot, entry.relativePath);
          break;
        case MigrationDeltaKind.deleteChapter:
        case MigrationDeltaKind.deleteComic:
          await targetRoot.deletePath(entry.relativePath);
          break;
      }
      await progressController.advance(currentItemPath: entry.relativePath);
    }
  }

  Future<String> cleanupStorageDirectory({
    required DownloadPreferences preferences,
    MigrationProgressCallback? onProgress,
  }) async {
    final DownloadStorageState state = await resolveStorageState(
      preferences: preferences,
      verifyWritable: false,
    );
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(state);
    final bool allowFullClean = !state.preferences.usePickedDirectoryAsRoot;
    final _MigrationProgressController progressController =
        _MigrationProgressController(
          fromPath: state.displayPath,
          toPath: state.displayPath,
          onProgress: onProgress,
        );
    return _cleanupStorageRootSafely(
      root,
      progressController: progressController,
      allowFullClean: allowFullClean,
    );
  }
}
