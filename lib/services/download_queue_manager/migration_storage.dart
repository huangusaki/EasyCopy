import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/download_storage_service.dart';

/// Storage operations needed by migration, independent of queue execution.
abstract interface class DownloadMigrationStorage {
  Future<DownloadStorageState> resolveStorageState({
    DownloadPreferences? preferences,
    bool verifyWritable = true,
  });
  Future<String> storageKeyForPreferences(
    DownloadPreferences preferences, {
    bool verifyWritable = false,
  });
  Future<void> verifyMigrationSource(DownloadPreferences preferences);
  Future<List<String>> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  });
  Future<void> verifyMigratedCache({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
  });
  Future<void> copyCachedLibraryIndex({
    required DownloadPreferences from,
    required DownloadPreferences to,
  });
  Future<String> cleanupStorageDirectory({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
    MigrationProgressCallback? onProgress,
  });
}

class ComicDownloadMigrationStorage implements DownloadMigrationStorage {
  const ComicDownloadMigrationStorage(this.service);
  final ComicDownloadService service;

  @override
  Future<DownloadStorageState> resolveStorageState({
    DownloadPreferences? preferences,
    bool verifyWritable = true,
  }) => service.resolveStorageState(
    preferences: preferences,
    verifyWritable: verifyWritable,
  );
  @override
  Future<String> storageKeyForPreferences(
    DownloadPreferences preferences, {
    bool verifyWritable = false,
  }) => service.storageKeyForPreferences(
    preferences,
    verifyWritable: verifyWritable,
  );
  @override
  Future<void> verifyMigrationSource(DownloadPreferences preferences) =>
      service.verifyMigrationSource(preferences);
  @override
  Future<List<String>> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  }) => service.migrateCacheRoot(from: from, to: to, onProgress: onProgress);
  @override
  Future<void> verifyMigratedCache({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
  }) => service.verifyMigratedCache(
    from: from,
    to: to,
    relativePaths: relativePaths,
  );
  @override
  Future<void> copyCachedLibraryIndex({
    required DownloadPreferences from,
    required DownloadPreferences to,
  }) => service.copyCachedLibraryIndex(from: from, to: to);
  @override
  Future<String> cleanupStorageDirectory({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required List<String> relativePaths,
    MigrationProgressCallback? onProgress,
  }) => service.cleanupStorageDirectory(
    from: from,
    to: to,
    relativePaths: relativePaths,
    onProgress: onProgress,
  );
}
