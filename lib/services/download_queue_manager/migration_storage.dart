import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';

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
  Future<DownloadStorageMigrationResult> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  });
  Future<void> applyMigrationDeltas({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required Iterable<MigrationDeltaEntry> entries,
    MigrationProgressCallback? onProgress,
  });
  Future<void> copyCachedLibraryIndex({
    required DownloadPreferences from,
    required DownloadPreferences to,
  });
  Future<String> cleanupStorageDirectory({
    required DownloadPreferences preferences,
    MigrationProgressCallback? onProgress,
  });
  String chapterDirectoryPath(String comicTitle, String chapterLabel);
  String comicDirectoryPath(String comicTitle);
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
  Future<DownloadStorageMigrationResult> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    MigrationProgressCallback? onProgress,
  }) => service.migrateCacheRoot(from: from, to: to, onProgress: onProgress);
  @override
  Future<void> applyMigrationDeltas({
    required DownloadPreferences from,
    required DownloadPreferences to,
    required Iterable<MigrationDeltaEntry> entries,
    MigrationProgressCallback? onProgress,
  }) => service.applyMigrationDeltas(
    from: from,
    to: to,
    entries: entries,
    onProgress: onProgress,
  );
  @override
  Future<void> copyCachedLibraryIndex({
    required DownloadPreferences from,
    required DownloadPreferences to,
  }) => service.copyCachedLibraryIndex(from: from, to: to);
  @override
  Future<String> cleanupStorageDirectory({
    required DownloadPreferences preferences,
    MigrationProgressCallback? onProgress,
  }) => service.cleanupStorageDirectory(
    preferences: preferences,
    onProgress: onProgress,
  );
  @override
  String chapterDirectoryPath(String comicTitle, String chapterLabel) =>
      service.chapterDirectoryPath(comicTitle, chapterLabel);
  @override
  String comicDirectoryPath(String comicTitle) =>
      service.comicDirectoryPath(comicTitle);
}
