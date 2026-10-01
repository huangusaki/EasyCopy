part of '../comic_download_service.dart';

extension DownloadMigrationOps on ComicDownloadService {
  Future<void> verifyMigrationSource(DownloadPreferences preferences) async {
    try {
      final DownloadStorageState state = await resolveStorageState(
        preferences: preferences,
        verifyWritable: false,
      );
      if (state.errorMessage.isNotEmpty) {
        throw const DownloadSourceUnavailableException();
      }
      final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
        state,
      );
      await root.listEntries('', recursive: false);
    } catch (_) {
      throw const DownloadSourceUnavailableException();
    }
  }

  Future<List<String>> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  }) => _transferCache(from: from, to: to, onProgress: onProgress);

  Future<void> verifyMigratedCache({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
  }) async {
    await _transferCache(
      from: from,
      to: to,
      relativePaths: relativePaths,
      verifyOnly: true,
    );
  }

  Future<List<String>> _transferCache({
    required DownloadPreferences from,
    required DownloadPreferences to,
    List<String>? relativePaths,
    bool verifyOnly = false,
    MigrationProgressCallback? onProgress,
  }) async {
    final DownloadStorageState fromState = await resolveStorageState(
      preferences: from,
      verifyWritable: false,
    );
    final DownloadStorageState toState = await resolveStorageState(
      preferences: to,
      verifyWritable: true,
    );
    _checkMigrationTarget(toState);
    if (_sameStorageLocation(fromState, toState)) return const <String>[];
    _checkMigrationOverlap(fromState, toState);
    await verifyMigrationSource(from);
    final _ResolvedStorageRoot sourceRoot = await _resolveStorageRootFromState(
      fromState,
    );
    final _ResolvedStorageRoot targetRoot = await _resolveStorageRootFromState(
      toState,
    );
    final List<String> paths =
        relativePaths ?? await _cacheFilePaths(sourceRoot);
    final _MigrationProgressController progress = _MigrationProgressController(
      fromPath: fromState.displayPath,
      toPath: toState.displayPath,
      onProgress: onProgress,
    );
    await progress.emitPreparing();
    await _migrateStorageContents(
      sourceRoot,
      targetRoot,
      relativePaths: paths,
      verifyOnly: verifyOnly,
      progressController: progress,
    );
    return paths;
  }

  Future<String> cleanupStorageDirectory({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
    MigrationProgressCallback? onProgress,
  }) async {
    try {
      final DownloadStorageState fromState = await resolveStorageState(
        preferences: from,
        verifyWritable: false,
      );
      final DownloadStorageState toState = await resolveStorageState(
        preferences: to,
        verifyWritable: true,
      );
      _checkMigrationTarget(toState);
      if (_sameStorageLocation(fromState, toState)) return '';
      _checkMigrationOverlap(fromState, toState);
      await verifyMigrationSource(from);
      final _ResolvedStorageRoot sourceRoot =
          await _resolveStorageRootFromState(fromState);
      final _ResolvedStorageRoot targetRoot =
          await _resolveStorageRootFromState(toState);
      // Recovery may follow a partially completed cleanup. Never broaden the
      // saved selection to files created after the original copy.
      final List<String> remaining = <String>[];
      for (final String path in relativePaths) {
        if (await sourceRoot.exists(path)) remaining.add(path);
      }
      final _MigrationProgressController progress =
          _MigrationProgressController(
            fromPath: fromState.displayPath,
            toPath: toState.displayPath,
            onProgress: onProgress,
          );
      await _migrateStorageContents(
        sourceRoot,
        targetRoot,
        relativePaths: remaining,
        verifyOnly: true,
        progressController: progress,
      );
      await progress.emitCleaning();
      for (final String path in remaining) {
        if (!await sourceRoot.deletePath(path)) {
          return '部分旧缓存未能清理，原目录中的其他文件已保留。';
        }
      }
      return '';
    } catch (_) {
      return '未清理原缓存目录，请确认新目录可用后再手动处理。';
    }
  }

  void _checkMigrationTarget(DownloadStorageState state) {
    if (!state.isReady) {
      throw FileSystemException(
        state.errorMessage.isEmpty ? '目标缓存目录不可用。' : state.errorMessage,
      );
    }
  }

  void _checkMigrationOverlap(
    DownloadStorageState from,
    DownloadStorageState to,
  ) {
    if (_storageRootsOverlap(from, to)) {
      throw const FileSystemException('目标缓存目录不能位于当前缓存目录内部，也不能包含当前缓存目录。');
    }
  }
}
