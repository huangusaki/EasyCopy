part of '../comic_download_service.dart';

const String _comicOwnershipMarkerName = '.easycopy_comic';

typedef ChapterDownloadProgressCallback =
    Future<void> Function(ChapterDownloadProgress progress);
typedef ChapterDownloadPauseChecker = bool Function();
typedef ChapterDownloadCancelChecker = bool Function();
typedef MigrationProgressCallback =
    FutureOr<void> Function(StorageMigrationProgress progress);

enum CacheLibraryRefreshReason {
  bootstrap,
  preferencesChanged,
  queueChanged,
  migrationSwitched,
  storageRescan,
  manual,
}

class ChapterDownloadProgress {
  const ChapterDownloadProgress({
    required this.completedCount,
    required this.totalCount,
    required this.currentLabel,
  });

  final int completedCount;
  final int totalCount;
  final String currentLabel;

  double get fraction {
    if (totalCount <= 0) {
      return 0;
    }
    return completedCount / totalCount;
  }
}

class ChapterDownloadResult {
  const ChapterDownloadResult({
    required this.directory,
    required this.fileCount,
    required this.manifestFile,
  });

  final Directory directory;
  final int fileCount;
  final File manifestFile;
}

class DownloadStorageMigrationResult {
  const DownloadStorageMigrationResult({
    required this.storageState,
    this.cleanupWarning = '',
    this.cleanupFuture,
  });

  final DownloadStorageState storageState;
  final String cleanupWarning;
  final Future<String>? cleanupFuture;
}

enum DownloadStorageMigrationPhase { preparing, migrating, cleaning }

class StorageMigrationProgress {
  const StorageMigrationProgress({
    required this.phase,
    required this.fromPath,
    required this.toPath,
    required this.message,
    this.currentItemPath = '',
    this.completedItems = 0,
    this.totalItems = 0,
  });

  final DownloadStorageMigrationPhase phase;
  final String fromPath;
  final String toPath;
  final String message;
  final String currentItemPath;
  final int completedItems;
  final int totalItems;

  bool get hasDeterminateProgress => totalItems > 0;

  double? get fraction {
    if (!hasDeterminateProgress) {
      return null;
    }
    if (completedItems <= 0) {
      return 0;
    }
    if (completedItems >= totalItems) {
      return 1;
    }
    return completedItems / totalItems;
  }
}

class DownloadPausedException implements Exception {
  const DownloadPausedException([this.message = '缓存已暂停。']);

  final String message;

  @override
  String toString() => message;
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException([this.message = '缓存任务已取消。']);

  final String message;

  @override
  String toString() => message;
}

class CachedChapterEntry {
  const CachedChapterEntry({
    required this.chapterTitle,
    required this.chapterHref,
    required this.sourceUri,
    required this.directoryPath,
    required this.downloadedAt,
  });

  final String chapterTitle;
  final String chapterHref;
  final String sourceUri;
  final String directoryPath;
  final DateTime downloadedAt;

  factory CachedChapterEntry.fromJson(Map<String, Object?> json) {
    return CachedChapterEntry(
      chapterTitle: (json['chapterTitle'] as String?)?.trim() ?? '',
      chapterHref: (json['chapterHref'] as String?)?.trim() ?? '',
      sourceUri: (json['sourceUri'] as String?)?.trim() ?? '',
      directoryPath: (json['directoryPath'] as String?)?.trim() ?? '',
      downloadedAt:
          DateTime.tryParse((json['downloadedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'chapterTitle': chapterTitle,
      'chapterHref': chapterHref,
      'sourceUri': sourceUri,
      'directoryPath': directoryPath,
      'downloadedAt': downloadedAt.toIso8601String(),
    };
  }
}

class CachedComicLibraryEntry {
  const CachedComicLibraryEntry({
    required this.comicTitle,
    required this.comicHref,
    required this.coverUrl,
    required this.chapters,
    this.detailSnapshot,
  });

  final String comicTitle;
  final String comicHref;
  final String coverUrl;
  final List<CachedChapterEntry> chapters;
  final CachedComicDetailSnapshot? detailSnapshot;

  int get cachedChapterCount => chapters.length;

  DateTime? get lastDownloadedAt =>
      chapters.isEmpty ? null : chapters.first.downloadedAt;

  factory CachedComicLibraryEntry.fromJson(Map<String, Object?> json) {
    final List<Object?> rawChapters =
        (json['chapters'] as List<Object?>?) ?? const <Object?>[];
    return CachedComicLibraryEntry(
      comicTitle: (json['comicTitle'] as String?)?.trim() ?? '',
      comicHref: (json['comicHref'] as String?)?.trim() ?? '',
      coverUrl: (json['coverUrl'] as String?)?.trim() ?? '',
      detailSnapshot: json['detailSnapshot'] is Map<Object?, Object?>
          ? CachedComicDetailSnapshot.fromJson(
              (json['detailSnapshot'] as Map<Object?, Object?>).map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      chapters: rawChapters
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> entry) => CachedChapterEntry.fromJson(
              entry.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  CachedComicLibraryEntry copyWith({
    String? comicTitle,
    String? comicHref,
    String? coverUrl,
    List<CachedChapterEntry>? chapters,
    CachedComicDetailSnapshot? detailSnapshot,
  }) {
    return CachedComicLibraryEntry(
      comicTitle: comicTitle ?? this.comicTitle,
      comicHref: comicHref ?? this.comicHref,
      coverUrl: coverUrl ?? this.coverUrl,
      chapters: chapters ?? this.chapters,
      detailSnapshot: detailSnapshot ?? this.detailSnapshot,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'comicTitle': comicTitle,
      'comicHref': comicHref,
      'coverUrl': coverUrl,
      'detailSnapshot': detailSnapshot?.toJson(),
      'chapters': chapters
          .map((CachedChapterEntry chapter) => chapter.toJson())
          .toList(growable: false),
    };
  }
}
