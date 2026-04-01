import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/android_document_tree_bridge.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:http/http.dart' as http;

typedef ChapterDownloadProgressCallback =
    Future<void> Function(ChapterDownloadProgress progress);
typedef ChapterDownloadPauseChecker = bool Function();
typedef ChapterDownloadCancelChecker = bool Function();
typedef DownloadStorageMigrationProgressCallback =
    FutureOr<void> Function(DownloadStorageMigrationProgress progress);

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

class DownloadStorageMigrationProgress {
  const DownloadStorageMigrationProgress({
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
}

class CachedComicLibraryEntry {
  const CachedComicLibraryEntry({
    required this.comicTitle,
    required this.comicHref,
    required this.coverUrl,
    required this.chapters,
  });

  final String comicTitle;
  final String comicHref;
  final String coverUrl;
  final List<CachedChapterEntry> chapters;

  int get cachedChapterCount => chapters.length;

  DateTime? get lastDownloadedAt =>
      chapters.isEmpty ? null : chapters.first.downloadedAt;
}

class ComicDownloadService {
  ComicDownloadService({
    http.Client? client,
    Future<Directory> Function()? baseDirectoryProvider,
    DownloadStorageService? storageService,
    AndroidDocumentTreeBridge? documentTreeBridge,
  }) : _client = client ?? http.Client(),
       _documentTreeBridge =
           documentTreeBridge ?? AndroidDocumentTreeBridge.instance,
       _storageService =
           storageService ??
           DownloadStorageService(
             preferencesProvider: baseDirectoryProvider == null
                 ? null
                 : () async => const DownloadPreferences(),
             defaultBaseDirectoryProvider: baseDirectoryProvider,
           );

  static final ComicDownloadService instance = ComicDownloadService();

  final http.Client _client;
  final AndroidDocumentTreeBridge _documentTreeBridge;
  final DownloadStorageService _storageService;

  bool get supportsCustomStorageSelection =>
      _storageService.supportsCustomDirectorySelection;

  Future<DownloadStorageState> resolveStorageState({
    DownloadPreferences? preferences,
    bool verifyWritable = true,
  }) {
    return _storageService.resolveState(
      preferences: preferences,
      verifyWritable: verifyWritable,
    );
  }

  Future<List<DownloadStorageState>> loadCustomDirectoryCandidates() {
    return _storageService.loadCustomDirectoryCandidates();
  }

  Future<ChapterDownloadResult> downloadChapter(
    ReaderPageData page, {
    String cookieHeader = '',
    String? comicUri,
    String? chapterHref,
    String? chapterLabel,
    String? coverUrl,
    ChapterDownloadProgressCallback? onProgress,
    ChapterDownloadPauseChecker? shouldPause,
    ChapterDownloadCancelChecker? shouldCancel,
  }) async {
    if (page.imageUrls.isEmpty) {
      throw FileSystemException('当前章节没有可下载图片。');
    }

    final _ResolvedStorageRoot root = await _resolveStorageRoot(
      verifyWritable: true,
    );
    final String resolvedComicUri =
        (comicUri ?? page.catalogHref).trim().isNotEmpty
        ? (comicUri ?? page.catalogHref).trim()
        : _deriveComicUri(page.uri);
    final String chapterHrefCandidate = (chapterHref ?? '').trim();
    final String resolvedChapterHref = chapterHrefCandidate.isEmpty
        ? page.uri
        : chapterHrefCandidate;
    final String resolvedChapterLabel = (chapterLabel ?? '').trim().isEmpty
        ? _chapterFolderName(page)
        : chapterLabel!.trim();
    final String chapterDirectoryPath = _joinRelativePath(<String>[
      _sanitizePathSegment(page.comicTitle),
      _sanitizePathSegment(resolvedChapterLabel),
    ]);
    final String manifestRelativePath = _joinRelativePath(<String>[
      chapterDirectoryPath,
      'manifest.json',
    ]);

    final ChapterDownloadResult? completedResult =
        await _loadCompletedChapterFromManifest(
          root: root,
          manifestRelativePath: manifestRelativePath,
          chapterDirectoryPath: chapterDirectoryPath,
          expectedImageCount: page.imageUrls.length,
        );
    if (completedResult != null) {
      if (onProgress != null) {
        await onProgress(
          ChapterDownloadProgress(
            completedCount: page.imageUrls.length,
            totalCount: page.imageUrls.length,
            currentLabel: '已恢复本地缓存',
          ),
        );
      }
      return completedResult;
    }

    final Map<int, String> existingFiles = await _loadExistingImageFiles(
      root,
      chapterDirectoryPath,
    );
    final List<String> savedFiles = List<String>.filled(
      page.imageUrls.length,
      '',
      growable: false,
    );
    existingFiles.forEach((int index, String fileName) {
      if (index >= 0 && index < savedFiles.length) {
        savedFiles[index] = fileName;
      }
    });
    final Map<String, String> headers = <String, String>{
      'User-Agent': AppConfig.desktopUserAgent,
      'Referer': page.uri,
      if (cookieHeader.trim().isNotEmpty) 'Cookie': cookieHeader.trim(),
    };

    for (int index = 0; index < page.imageUrls.length; index += 1) {
      _throwIfCancelled(shouldCancel);
      _throwIfPaused(shouldPause);

      final String existingFileName = savedFiles[index];
      if (existingFileName.isNotEmpty) {
        if (onProgress != null) {
          await onProgress(
            ChapterDownloadProgress(
              completedCount: index + 1,
              totalCount: page.imageUrls.length,
              currentLabel: '已恢复 ${index + 1}/${page.imageUrls.length}',
            ),
          );
        }
        continue;
      }

      final Uri imageUri = Uri.parse(page.imageUrls[index]);
      final http.Response response = await _client.get(
        imageUri,
        headers: headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载图片失败（${response.statusCode}）', uri: imageUri);
      }

      final String extension = _detectExtension(
        imageUri,
        response.headers['content-type'],
      );
      final String fileName =
          '${(index + 1).toString().padLeft(3, '0')}.$extension';
      await root.writeBytes(
        _joinRelativePath(<String>[chapterDirectoryPath, fileName]),
        response.bodyBytes,
      );
      savedFiles[index] = fileName;

      if (onProgress != null) {
        await onProgress(
          ChapterDownloadProgress(
            completedCount: index + 1,
            totalCount: page.imageUrls.length,
            currentLabel: '正在下载 ${index + 1}/${page.imageUrls.length}',
          ),
        );
      }
    }

    final List<String> orderedSavedFiles = savedFiles
        .where((String fileName) => fileName.isNotEmpty)
        .toList(growable: false);
    await root.writeString(
      manifestRelativePath,
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'comicTitle': page.comicTitle,
        'comicUri': resolvedComicUri,
        'coverUrl': coverUrl ?? '',
        'chapterTitle': page.chapterTitle,
        'chapterLabel': resolvedChapterLabel,
        'chapterHref': resolvedChapterHref,
        'prevHref': page.prevHref,
        'nextHref': page.nextHref,
        'catalogHref': page.catalogHref,
        'progressLabel': page.progressLabel,
        'sourceUri': page.uri,
        'downloadedAt': DateTime.now().toIso8601String(),
        'imageCount': orderedSavedFiles.length,
        'files': orderedSavedFiles,
      }),
    );

    return ChapterDownloadResult(
      directory: Directory(chapterDirectoryPath),
      fileCount: orderedSavedFiles.length,
      manifestFile: File(manifestRelativePath),
    );
  }

  Future<List<CachedComicLibraryEntry>> loadCachedLibrary() async {
    try {
      final _ResolvedStorageRoot root = await _resolveStorageRoot(
        verifyWritable: false,
      );
      final List<Map<String, Object?>> manifests = await _loadLibraryManifests(
        root,
      );

      final Map<String, List<CachedChapterEntry>> grouped =
          <String, List<CachedChapterEntry>>{};
      final Map<String, String> comicTitles = <String, String>{};
      final Map<String, String> comicHrefs = <String, String>{};
      final Map<String, String> comicCovers = <String, String>{};

      for (final Map<String, Object?> manifest in manifests) {
        final String sourceUri = _stringValue(manifest['sourceUri']);
        final String comicHref = _stringValue(manifest['comicUri']).isNotEmpty
            ? _rewriteAllowedUri(_stringValue(manifest['comicUri']))
            : _deriveComicUri(sourceUri);
        final String comicTitle = _stringValue(manifest['comicTitle']);
        final String coverUrl = _rewriteAllowedUri(
          _stringValue(manifest['coverUrl']),
        );
        final String chapterHref =
            _stringValue(manifest['chapterHref']).isNotEmpty
            ? _rewriteAllowedUri(_stringValue(manifest['chapterHref']))
            : _rewriteAllowedUri(sourceUri);
        final String chapterTitle =
            _stringValue(manifest['chapterLabel']).isNotEmpty
            ? _stringValue(manifest['chapterLabel'])
            : _stringValue(manifest['chapterTitle']);
        final DateTime downloadedAt =
            DateTime.tryParse(_stringValue(manifest['downloadedAt'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final String key = _comicKeyForUri(
          comicHref.isEmpty ? sourceUri : comicHref,
        );

        if (key.isEmpty) {
          continue;
        }

        comicTitles[key] = comicTitle.isEmpty ? '未命名漫画' : comicTitle;
        comicHrefs[key] = comicHref;
        if (coverUrl.isNotEmpty) {
          comicCovers[key] = coverUrl;
        }
        grouped
            .putIfAbsent(key, () => <CachedChapterEntry>[])
            .add(
              CachedChapterEntry(
                chapterTitle: chapterTitle.isEmpty ? '未命名章节' : chapterTitle,
                chapterHref: chapterHref,
                sourceUri: _rewriteAllowedUri(sourceUri),
                directoryPath: _stringValue(manifest['__directoryPath']),
                downloadedAt: downloadedAt,
              ),
            );
      }

      final List<CachedComicLibraryEntry> comics =
          grouped.entries
              .map((MapEntry<String, List<CachedChapterEntry>> entry) {
                final List<CachedChapterEntry> chapters =
                    entry.value.toList(growable: false)..sort(
                      (CachedChapterEntry left, CachedChapterEntry right) =>
                          right.downloadedAt.compareTo(left.downloadedAt),
                    );
                return CachedComicLibraryEntry(
                  comicTitle: comicTitles[entry.key] ?? '未命名漫画',
                  comicHref: comicHrefs[entry.key] ?? '',
                  coverUrl: comicCovers[entry.key] ?? '',
                  chapters: chapters,
                );
              })
              .toList(growable: false)
            ..sort((
              CachedComicLibraryEntry left,
              CachedComicLibraryEntry right,
            ) {
              final DateTime leftTime =
                  left.lastDownloadedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final DateTime rightTime =
                  right.lastDownloadedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return rightTime.compareTo(leftTime);
            });

      return comics;
    } catch (_) {
      return const <CachedComicLibraryEntry>[];
    }
  }

  Future<List<Map<String, Object?>>> _loadLibraryManifests(
    _ResolvedStorageRoot root,
  ) async {
    final List<Map<String, Object?>> manifests = <Map<String, Object?>>[];
    final List<_StorageEntry> comicEntries = await root.listEntries(
      '',
      recursive: false,
    );
    for (final _StorageEntry comicEntry in comicEntries) {
      if (!comicEntry.isDirectory || comicEntry.relativePath.trim().isEmpty) {
        continue;
      }
      final List<_StorageEntry> chapterEntries = await root.listEntries(
        comicEntry.relativePath,
        recursive: false,
      );
      for (final _StorageEntry chapterEntry in chapterEntries) {
        if (!chapterEntry.isDirectory ||
            chapterEntry.relativePath.trim().isEmpty) {
          continue;
        }
        final String manifestRelativePath = _joinRelativePath(<String>[
          chapterEntry.relativePath,
          'manifest.json',
        ]);
        if (!await root.exists(manifestRelativePath)) {
          continue;
        }
        try {
          final Object? decoded = jsonDecode(
            await root.readString(manifestRelativePath),
          );
          if (decoded is! Map) {
            continue;
          }
          manifests.add(<String, Object?>{
            ...decoded.map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
            '__directoryPath': chapterEntry.relativePath,
          });
        } catch (_) {
          continue;
        }
      }
    }
    return manifests;
  }

  Future<Set<String>> loadDownloadedChapterPathKeysForComic(
    String comicUri,
  ) async {
    final String targetKey = _comicKeyForUri(comicUri);
    if (targetKey.isEmpty) {
      return const <String>{};
    }
    final List<CachedComicLibraryEntry> library = await loadCachedLibrary();
    final CachedComicLibraryEntry? match = library
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? item) =>
              item != null && _comicKeyForUri(item.comicHref) == targetKey,
          orElse: () => null,
        );
    if (match == null) {
      return const <String>{};
    }
    return match.chapters
        .map(
          (CachedChapterEntry chapter) => _pathKeyForUri(chapter.chapterHref),
        )
        .where((String key) => key.isNotEmpty)
        .toSet();
  }

  Future<ReaderPageData?> loadCachedReaderPage(
    String chapterHref, {
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
  }) async {
    final CachedChapterEntry? entry = await _findCachedChapter(chapterHref);
    if (entry == null || entry.directoryPath.isEmpty) {
      return null;
    }

    final _ResolvedStorageRoot root = await _resolveStorageRoot(
      verifyWritable: false,
    );
    final String manifestRelativePath = _joinRelativePath(<String>[
      entry.directoryPath,
      'manifest.json',
    ]);
    if (!await root.exists(manifestRelativePath)) {
      return null;
    }

    try {
      final Object? decoded = jsonDecode(
        await root.readString(manifestRelativePath),
      );
      if (decoded is! Map) {
        return null;
      }
      final Map<String, Object?> manifest = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final Map<String, _StorageEntry> chapterFiles = <String, _StorageEntry>{
        for (final _StorageEntry file in await root.listEntries(
          entry.directoryPath,
          recursive: false,
        ))
          if (!file.isDirectory) file.name: file,
      };
      final List<String> imageUrls =
          ((manifest['files'] as List<Object?>?) ?? const <Object?>[])
              .whereType<String>()
              .map((String fileName) => chapterFiles[fileName]?.uri ?? '')
              .where((String uri) => uri.isNotEmpty)
              .toList(growable: false);
      if (imageUrls.isEmpty) {
        return null;
      }

      final String sourceUri = _stringValue(manifest['sourceUri']);
      final String manifestChapterHref = _stringValue(manifest['chapterHref']);
      final String resolvedUri = sourceUri.isNotEmpty
          ? _rewriteAllowedUri(sourceUri)
          : (manifestChapterHref.isNotEmpty
                ? _rewriteAllowedUri(manifestChapterHref)
                : _rewriteAllowedUri(chapterHref));
      final String resolvedPrevHref = prevHref.trim().isNotEmpty
          ? _rewriteAllowedUri(prevHref)
          : _rewriteAllowedUri(_stringValue(manifest['prevHref']));
      final String resolvedNextHref = nextHref.trim().isNotEmpty
          ? _rewriteAllowedUri(nextHref)
          : _rewriteAllowedUri(_stringValue(manifest['nextHref']));
      final String resolvedCatalogHref = catalogHref.trim().isNotEmpty
          ? catalogHref.trim()
          : _rewriteAllowedUri(
              _stringValue(manifest['catalogHref']).isNotEmpty
                  ? _stringValue(manifest['catalogHref'])
                  : _stringValue(manifest['comicUri']),
            );
      final String chapterTitle = _stringValue(manifest['chapterTitle']);
      final String chapterLabel = _stringValue(manifest['chapterLabel']);
      final String progressLabel = _stringValue(manifest['progressLabel']);

      return ReaderPageData(
        title: chapterTitle.isNotEmpty
            ? chapterTitle
            : (chapterLabel.isNotEmpty ? chapterLabel : '已缓存章节'),
        uri: resolvedUri,
        comicTitle: _stringValue(manifest['comicTitle']),
        chapterTitle: chapterTitle.isNotEmpty ? chapterTitle : chapterLabel,
        progressLabel: progressLabel,
        imageUrls: imageUrls,
        prevHref: resolvedPrevHref,
        nextHref: resolvedNextHref,
        catalogHref: resolvedCatalogHref,
        contentKey: _pathKeyForUri(resolvedUri),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteCachedComic(CachedComicLibraryEntry entry) async {
    if (entry.chapters.isEmpty) {
      await deleteComicCacheByTitle(entry.comicTitle);
      return;
    }

    final String chapterDirectoryPath = entry.chapters.first.directoryPath;
    if (chapterDirectoryPath.isEmpty) {
      await deleteComicCacheByTitle(entry.comicTitle);
      return;
    }

    final String comicRelativePath = _parentRelativePath(chapterDirectoryPath);
    if (comicRelativePath.isEmpty) {
      await deleteComicCacheByTitle(entry.comicTitle);
      return;
    }
    try {
      final _ResolvedStorageRoot root = await _resolveStorageRoot(
        verifyWritable: false,
      );
      if (!await root.deletePath(comicRelativePath)) {
        await deleteComicCacheByTitle(entry.comicTitle);
      }
    } catch (_) {
      await deleteComicCacheByTitle(entry.comicTitle);
    }
  }

  Future<CachedChapterEntry?> _findCachedChapter(String chapterHref) async {
    final String targetPathKey = _pathKeyForUri(chapterHref);
    if (targetPathKey.isEmpty) {
      return null;
    }
    final List<CachedComicLibraryEntry> library = await loadCachedLibrary();
    for (final CachedComicLibraryEntry comic in library) {
      for (final CachedChapterEntry chapter in comic.chapters) {
        final String chapterPathKey = _pathKeyForUri(chapter.chapterHref);
        final String sourcePathKey = _pathKeyForUri(chapter.sourceUri);
        if (chapterPathKey == targetPathKey || sourcePathKey == targetPathKey) {
          return chapter;
        }
      }
    }
    return null;
  }

  Future<void> deleteComicCacheByTitle(String comicTitle) async {
    try {
      final _ResolvedStorageRoot root = await _resolveStorageRoot(
        verifyWritable: false,
      );
      await root.deletePath(_sanitizePathSegment(comicTitle));
    } catch (_) {
      return;
    }
  }

  Future<void> cleanupIncompleteChapter({
    required String comicTitle,
    required String chapterLabel,
  }) async {
    final _ResolvedStorageRoot root = await _resolveStorageRoot(
      verifyWritable: false,
    );
    final String chapterDirectoryPath = _joinRelativePath(<String>[
      _sanitizePathSegment(comicTitle),
      _sanitizePathSegment(chapterLabel),
    ]);
    if (!await root.exists(chapterDirectoryPath)) {
      return;
    }
    final String manifestRelativePath = _joinRelativePath(<String>[
      chapterDirectoryPath,
      'manifest.json',
    ]);
    if (!await root.exists(manifestRelativePath)) {
      await root.deletePath(chapterDirectoryPath);
      return;
    }
    final List<_StorageEntry> entries = await root.listEntries(
      chapterDirectoryPath,
      recursive: false,
    );
    for (final _StorageEntry entry in entries) {
      if (entry.isDirectory || !entry.name.endsWith('.part')) {
        continue;
      }
      await root.deletePath(entry.relativePath);
    }
  }

  Future<void> cleanupIncompleteTasks(Iterable<DownloadQueueTask> tasks) async {
    final Set<String> cleanedKeys = <String>{};
    for (final DownloadQueueTask task in tasks) {
      final String key = '${task.comicTitle}::${task.chapterLabel}';
      if (!cleanedKeys.add(key)) {
        continue;
      }
      await cleanupIncompleteChapter(
        comicTitle: task.comicTitle,
        chapterLabel: task.chapterLabel,
      );
    }
  }

  Future<DownloadStorageMigrationResult> migrateCacheRoot({
    required DownloadPreferences from,
    required DownloadPreferences to,
    DownloadStorageMigrationProgressCallback? onProgress,
  }) async {
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

    return DownloadStorageMigrationResult(
      storageState: toState,
      cleanupFuture: _cleanupStorageRootSafely(
        sourceRoot,
        progressController: progressController,
      ),
    );
  }

  String _chapterFolderName(ReaderPageData page) {
    final String label = page.chapterTitle.trim().isNotEmpty
        ? page.chapterTitle.trim()
        : page.progressLabel.trim();
    if (label.isNotEmpty) {
      return label;
    }

    final Uri uri = Uri.parse(page.uri);
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return page.contentKey.trim().isNotEmpty
        ? page.contentKey.trim()
        : 'chapter';
  }

  String _detectExtension(Uri imageUri, String? contentType) {
    final RegExpMatch? pathMatch = RegExp(
      r'\.(avif|bmp|gif|jpeg|jpg|png|webp)$',
      caseSensitive: false,
    ).firstMatch(imageUri.path);
    if (pathMatch != null) {
      return pathMatch.group(1)!.toLowerCase();
    }

    final String normalizedType = (contentType ?? '').toLowerCase();
    if (normalizedType.contains('png')) {
      return 'png';
    }
    if (normalizedType.contains('webp')) {
      return 'webp';
    }
    if (normalizedType.contains('gif')) {
      return 'gif';
    }
    if (normalizedType.contains('bmp')) {
      return 'bmp';
    }
    if (normalizedType.contains('avif')) {
      return 'avif';
    }
    return 'jpg';
  }

  String _sanitizePathSegment(String rawValue) {
    final String normalized = rawValue
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (normalized.isEmpty) {
      return 'untitled';
    }
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }

  String _joinRelativePath(List<String> segments) {
    return segments
        .map((String segment) => segment.trim())
        .where((String segment) => segment.isNotEmpty)
        .join('/');
  }

  String _parentRelativePath(String value) {
    final String normalized = value.trim().replaceAll('\\', '/');
    final int separatorIndex = normalized.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return '';
    }
    return normalized.substring(0, separatorIndex);
  }

  String _stringValue(Object? value) {
    return value is String ? value.trim() : '';
  }

  String _deriveComicUri(String sourceUri) {
    final Uri? parsed = Uri.tryParse(sourceUri);
    if (parsed == null) {
      return '';
    }
    final List<String> segments = parsed.pathSegments;
    final int chapterIndex = segments.indexOf('chapter');
    if (chapterIndex <= 0) {
      return _rewriteAllowedUri(sourceUri);
    }
    final Uri detailUri = parsed.replace(
      pathSegments: segments.take(chapterIndex).toList(growable: false),
      query: null,
    );
    return _rewriteAllowedUri(detailUri.toString());
  }

  String _rewriteAllowedUri(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !AppConfig.isAllowedNavigationUri(uri)) {
      return value;
    }
    return AppConfig.rewriteToCurrentHost(uri).toString();
  }

  String _comicKeyForUri(String value) {
    final Uri? uri = Uri.tryParse(_rewriteAllowedUri(value));
    if (uri == null) {
      return '';
    }
    final List<String> segments = uri.pathSegments;
    final int chapterIndex = segments.indexOf('chapter');
    final List<String> targetSegments = chapterIndex > 0
        ? segments.take(chapterIndex).toList(growable: false)
        : segments;
    return Uri(pathSegments: targetSegments).path;
  }

  String _pathKeyForUri(String value) {
    final Uri? uri = Uri.tryParse(_rewriteAllowedUri(value));
    if (uri == null) {
      return '';
    }
    return Uri(path: uri.path).toString();
  }

  Future<_ResolvedStorageRoot> _resolveStorageRoot({
    DownloadPreferences? preferences,
    required bool verifyWritable,
  }) async {
    final DownloadStorageState storageState = await resolveStorageState(
      preferences: preferences,
      verifyWritable: verifyWritable,
    );
    if (!storageState.isReady && verifyWritable) {
      throw FileSystemException(
        storageState.errorMessage.isEmpty
            ? '缓存目录不可用。'
            : storageState.errorMessage,
      );
    }
    if (storageState.preferences.usesDocumentTree) {
      final String treeUri = storageState.preferences.customTreeUri.trim();
      if (treeUri.isEmpty) {
        throw const FileSystemException('缓存目录不可用。');
      }
      return _DocumentTreeStorageRoot(
        bridge: _documentTreeBridge,
        treeUri: treeUri,
        rootRelativePath: storageState.preferences.usePickedDirectoryAsRoot
            ? ''
            : DownloadStorageService.downloadsDirectoryName,
      );
    }
    final String rootPath = storageState.rootPath.trim();
    if (rootPath.isEmpty) {
      throw const FileSystemException('缓存目录不可用。');
    }
    return _FileStorageRoot(Directory(rootPath));
  }

  bool _sameStorageLocation(
    DownloadStorageState left,
    DownloadStorageState right,
  ) {
    if (left.preferences.usesDocumentTree ||
        right.preferences.usesDocumentTree) {
      return left.preferences.usesDocumentTree &&
          right.preferences.usesDocumentTree &&
          left.documentTreeUri.trim() == right.documentTreeUri.trim();
    }
    return _normalizedPath(left.rootPath) == _normalizedPath(right.rootPath);
  }

  bool _storageRootsOverlap(
    DownloadStorageState left,
    DownloadStorageState right,
  ) {
    final String leftRoot = _normalizedComparableRoot(left.rootPath);
    final String rightRoot = _normalizedComparableRoot(right.rootPath);
    if (leftRoot.isEmpty || rightRoot.isEmpty) {
      return false;
    }
    return _isNestedStoragePath(leftRoot, rightRoot) ||
        _isNestedStoragePath(rightRoot, leftRoot);
  }

  String _normalizedComparableRoot(String value) {
    String normalized = _normalizedPath(value);
    while (normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isNestedStoragePath(String candidate, String parent) {
    return candidate == parent ||
        candidate.startsWith('$parent${Platform.pathSeparator}');
  }

  Future<ChapterDownloadResult?> _loadCompletedChapterFromManifest({
    required _ResolvedStorageRoot root,
    required String manifestRelativePath,
    required String chapterDirectoryPath,
    required int expectedImageCount,
  }) async {
    if (!await root.exists(manifestRelativePath)) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(
        await root.readString(manifestRelativePath),
      );
      if (decoded is! Map) {
        return null;
      }
      final int imageCount = (decoded['imageCount'] as num?)?.toInt() ?? 0;
      if (imageCount < expectedImageCount) {
        return null;
      }
      return ChapterDownloadResult(
        directory: Directory(chapterDirectoryPath),
        fileCount: imageCount,
        manifestFile: File(manifestRelativePath),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, String>> _loadExistingImageFiles(
    _ResolvedStorageRoot root,
    String chapterDirectoryPath,
  ) async {
    if (!await root.exists(chapterDirectoryPath)) {
      return const <int, String>{};
    }

    final Map<int, String> existingFiles = <int, String>{};
    final RegExp pattern = RegExp(r'^(\d{3})\.[^.]+$');
    for (final _StorageEntry entry in await root.listEntries(
      chapterDirectoryPath,
      recursive: false,
    )) {
      if (entry.isDirectory) {
        continue;
      }
      final String fileName = entry.name;
      final RegExpMatch? match = pattern.firstMatch(fileName);
      if (match == null) {
        continue;
      }
      if (entry.size <= 0) {
        continue;
      }
      final int index = int.parse(match.group(1)!) - 1;
      existingFiles[index] = fileName;
    }
    return existingFiles;
  }

  void _throwIfPaused(ChapterDownloadPauseChecker? shouldPause) {
    if (shouldPause?.call() ?? false) {
      throw const DownloadPausedException();
    }
  }

  void _throwIfCancelled(ChapterDownloadCancelChecker? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const DownloadCancelledException();
    }
  }

  Future<void> _clearStorageRoot(_ResolvedStorageRoot root) async {
    final List<_StorageEntry> topLevelEntries = await root.listEntries(
      '',
      recursive: false,
    );
    for (final _StorageEntry entry in topLevelEntries) {
      await root.deletePath(entry.relativePath);
    }
  }

  Future<String> _cleanupStorageRootSafely(
    _ResolvedStorageRoot root, {
    required _MigrationProgressController progressController,
  }) async {
    try {
      await progressController.emitCleaning();
      await _clearStorageRoot(root);
      return '';
    } catch (_) {
      return '旧缓存目录未能自动清理，可稍后手动删除。';
    }
  }

  Future<void> _migrateStorageContents(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot, {
    required _MigrationProgressController progressController,
  }) async {
    if (sourceRoot is _FileStorageRoot && targetRoot is _FileStorageRoot) {
      await progressController.startMigrating(
        totalItems: await _countMigratableFilesInDirectory(
          sourceRoot.rootDirectory,
        ),
      );
      await _moveFileSystemDirectoryContents(
        sourceRoot.rootDirectory,
        targetRoot.rootDirectory,
        progressController: progressController,
      );
      return;
    }
    if (sourceRoot is _FileStorageRoot &&
        targetRoot is _DocumentTreeStorageRoot) {
      await progressController.startMigrating();
      await targetRoot.importFromDirectory(
        sourceRoot.rootDirectory,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
    if (sourceRoot is _DocumentTreeStorageRoot &&
        targetRoot is _FileStorageRoot) {
      await progressController.startMigrating();
      await sourceRoot.exportToDirectory(
        targetRoot.rootDirectory,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
    if (sourceRoot is _DocumentTreeStorageRoot &&
        targetRoot is _DocumentTreeStorageRoot) {
      await progressController.startMigrating();
      await sourceRoot.copyToDocumentTree(
        targetRoot,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
    await _copyStorageEntryByEntry(
      sourceRoot,
      targetRoot,
      progressController: progressController,
    );
  }

  Future<void> _copyStorageEntryByEntry(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot, {
    required _MigrationProgressController progressController,
  }) async {
    final List<_StorageEntry> sourceEntries = await sourceRoot.listEntries(
      '',
      recursive: true,
    );
    final List<_StorageEntry> fileEntries = sourceEntries
        .where(
          (_StorageEntry entry) =>
              !entry.isDirectory && !_shouldSkipMigrationFile(entry.name),
        )
        .toList(growable: false);
    await progressController.startMigrating(totalItems: fileEntries.length);
    for (final _StorageEntry entry in fileEntries) {
      await targetRoot.writeBytes(
        entry.relativePath,
        await sourceRoot.readBytes(entry.relativePath),
      );
      await progressController.advance(currentItemPath: entry.relativePath);
    }
  }

  Future<void> _moveFileSystemDirectoryContents(
    Directory source,
    Directory target, {
    required _MigrationProgressController progressController,
  }) async {
    await target.create(recursive: true);
    final List<FileSystemEntity> children = await source
        .list(recursive: false, followLinks: false)
        .toList();
    for (final FileSystemEntity child in children) {
      final String name = _fileSystemEntityName(child);
      if (name.isEmpty || _shouldSkipMigrationFile(name)) {
        continue;
      }
      if (child is Directory) {
        await _moveDirectoryEntity(
          child,
          Directory(_joinFileSystemPath(target.path, name)),
          progressController: progressController,
        );
        continue;
      }
      if (child is File) {
        await _moveFileEntity(
          child,
          File(_joinFileSystemPath(target.path, name)),
          progressController: progressController,
        );
      }
    }
  }

  Future<void> _moveDirectoryEntity(
    Directory source,
    Directory target, {
    required _MigrationProgressController progressController,
  }) async {
    if (!await target.exists()) {
      final int subtreeFileCount = await _countMigratableFilesInDirectory(
        source,
      );
      try {
        await source.rename(target.path);
        await progressController.advance(
          count: subtreeFileCount,
          currentItemPath: target.path,
        );
        return;
      } on FileSystemException {
        // Fall back to streamed copy when the directory cannot be moved directly.
      }
    }
    await target.create(recursive: true);
    final List<FileSystemEntity> children = await source
        .list(recursive: false, followLinks: false)
        .toList();
    for (final FileSystemEntity child in children) {
      final String name = _fileSystemEntityName(child);
      if (name.isEmpty || _shouldSkipMigrationFile(name)) {
        continue;
      }
      if (child is Directory) {
        await _moveDirectoryEntity(
          child,
          Directory(_joinFileSystemPath(target.path, name)),
          progressController: progressController,
        );
        continue;
      }
      if (child is File) {
        await _moveFileEntity(
          child,
          File(_joinFileSystemPath(target.path, name)),
          progressController: progressController,
        );
      }
    }
    if (await source.exists()) {
      await source.delete(recursive: true);
    }
  }

  Future<void> _moveFileEntity(
    File source,
    File target, {
    required _MigrationProgressController progressController,
  }) async {
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      try {
        await source.rename(target.path);
        await progressController.advance(currentItemPath: target.path);
        return;
      } on FileSystemException {
        // Fall back to streamed copy when the file cannot be moved directly.
      }
    }
    await _copyFile(source, target);
    if (await source.exists()) {
      await source.delete();
    }
    await progressController.advance(currentItemPath: target.path);
  }

  Future<void> _copyFile(File source, File target) async {
    await target.parent.create(recursive: true);
    final IOSink sink = target.openWrite();
    try {
      await sink.addStream(source.openRead());
    } finally {
      await sink.close();
    }
  }

  String _fileSystemEntityName(FileSystemEntity entity) {
    final String path = entity.path.replaceAll('\\', '/');
    final int separatorIndex = path.lastIndexOf('/');
    return separatorIndex >= 0 ? path.substring(separatorIndex + 1) : path;
  }

  String _joinFileSystemPath(String basePath, String name) {
    return '$basePath${Platform.pathSeparator}$name';
  }

  Future<int> _countMigratableFilesInDirectory(Directory directory) async {
    int count = 0;
    await for (final FileSystemEntity entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      if (_shouldSkipMigrationFile(_fileSystemEntityName(entity))) {
        continue;
      }
      count += 1;
    }
    return count;
  }

  bool _shouldSkipMigrationFile(String fileName) {
    final String normalized = fileName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.endsWith('.part') ||
        normalized.endsWith('.migrate_tmp') ||
        normalized.startsWith('.storage_probe_');
  }

  String _normalizedPath(String value) {
    final String normalized = value.trim().replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class _StorageEntry {
  const _StorageEntry({
    required this.relativePath,
    required this.name,
    required this.uri,
    required this.isDirectory,
    required this.size,
  });

  final String relativePath;
  final String name;
  final String uri;
  final bool isDirectory;
  final int size;
}

class _MigrationProgressController {
  _MigrationProgressController({
    required this.fromPath,
    required this.toPath,
    this.onProgress,
  });

  final String fromPath;
  final String toPath;
  final DownloadStorageMigrationProgressCallback? onProgress;

  int _completedItems = 0;
  int _totalItems = 0;

  Future<void> emitPreparing() {
    return _emit(DownloadStorageMigrationPhase.preparing, message: '正在准备迁移缓存…');
  }

  Future<void> startMigrating({int totalItems = 0}) {
    _completedItems = 0;
    _totalItems = totalItems;
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
    );
  }

  Future<void> advance({int count = 1, String currentItemPath = ''}) {
    if (count > 0) {
      _completedItems += count;
      if (_totalItems > 0 && _completedItems > _totalItems) {
        _completedItems = _totalItems;
      }
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      currentItemPath: currentItemPath,
      message: _migratingMessage(),
    );
  }

  Future<void> markMigratingComplete() {
    if (_totalItems > 0) {
      _completedItems = _totalItems;
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
    );
  }

  Future<void> syncMigrating({
    required int completedItems,
    required int totalItems,
    String currentItemPath = '',
  }) {
    _completedItems = completedItems < 0 ? 0 : completedItems;
    if (totalItems > 0) {
      _totalItems = totalItems;
      if (_completedItems > _totalItems) {
        _completedItems = _totalItems;
      }
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      currentItemPath: currentItemPath,
      message: _migratingMessage(),
    );
  }

  Future<void> emitCleaning() {
    return _emit(DownloadStorageMigrationPhase.cleaning, message: '正在清理旧缓存目录…');
  }

  String _migratingMessage() {
    if (_totalItems > 0) {
      return '正在迁移缓存 $_completedItems/$_totalItems…';
    }
    return '正在迁移缓存，请勿退出应用…';
  }

  Future<void> _emit(
    DownloadStorageMigrationPhase phase, {
    required String message,
    String currentItemPath = '',
  }) async {
    if (onProgress == null) {
      return;
    }
    await onProgress!(
      DownloadStorageMigrationProgress(
        phase: phase,
        fromPath: fromPath,
        toPath: toPath,
        message: message,
        currentItemPath: currentItemPath,
        completedItems: _completedItems,
        totalItems: _totalItems,
      ),
    );
  }
}

abstract class _ResolvedStorageRoot {
  Future<void> writeBytes(String relativePath, Uint8List bytes);

  Future<void> writeString(String relativePath, String text);

  Future<String> readString(String relativePath);

  Future<Uint8List> readBytes(String relativePath);

  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  });

  Future<bool> exists(String relativePath);

  Future<bool> deletePath(String relativePath);
}

class _FileStorageRoot implements _ResolvedStorageRoot {
  const _FileStorageRoot(this.rootDirectory);

  final Directory rootDirectory;

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) async {
    final File file = File(_absolutePath(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeString(String relativePath, String text) async {
    final File file = File(_absolutePath(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
  }

  @override
  Future<String> readString(String relativePath) {
    return File(_absolutePath(relativePath)).readAsString();
  }

  @override
  Future<Uint8List> readBytes(String relativePath) {
    return File(_absolutePath(relativePath)).readAsBytes();
  }

  @override
  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  }) async {
    final String normalizedRelativePath = _normalizeRelativePath(relativePath);
    final String absolutePath = normalizedRelativePath.isEmpty
        ? rootDirectory.path
        : _absolutePath(normalizedRelativePath);
    final FileSystemEntityType type = await FileSystemEntity.type(absolutePath);
    if (type == FileSystemEntityType.notFound) {
      return const <_StorageEntry>[];
    }
    if (type == FileSystemEntityType.file) {
      final File file = File(absolutePath);
      return <_StorageEntry>[
        _StorageEntry(
          relativePath: normalizedRelativePath,
          name: file.uri.pathSegments.last,
          uri: file.uri.toString(),
          isDirectory: false,
          size: await file.length(),
        ),
      ];
    }

    final Directory directory = Directory(absolutePath);
    final List<_StorageEntry> entries = <_StorageEntry>[];
    await for (final FileSystemEntity entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final String relative = entity.path
          .substring(rootDirectory.path.length)
          .replaceFirst(RegExp(r'^[\\/]+'), '')
          .replaceAll('\\', '/');
      if (relative.isEmpty) {
        continue;
      }
      final FileSystemEntityType entityType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      final bool isDirectory = entityType == FileSystemEntityType.directory;
      final int size = entity is File ? await entity.length() : 0;
      entries.add(
        _StorageEntry(
          relativePath: relative,
          name: entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last,
          uri: entity.uri.toString(),
          isDirectory: isDirectory,
          size: size,
        ),
      );
    }
    return entries;
  }

  @override
  Future<bool> exists(String relativePath) async {
    return await FileSystemEntity.type(
          _absolutePath(relativePath),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;
  }

  @override
  Future<bool> deletePath(String relativePath) async {
    final String absolutePath = _absolutePath(relativePath);
    final FileSystemEntityType type = await FileSystemEntity.type(
      absolutePath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return false;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(absolutePath).delete(recursive: true);
      return true;
    }
    await File(absolutePath).delete();
    return true;
  }

  String _absolutePath(String relativePath) {
    final String normalized = _normalizeRelativePath(
      relativePath,
    ).replaceAll('/', Platform.pathSeparator);
    return normalized.isEmpty
        ? rootDirectory.path
        : '${rootDirectory.path}${Platform.pathSeparator}$normalized';
  }

  String _normalizeRelativePath(String relativePath) {
    return relativePath.trim().replaceAll('\\', '/');
  }
}

class _DocumentTreeStorageRoot implements _ResolvedStorageRoot {
  const _DocumentTreeStorageRoot({
    required this.bridge,
    required this.treeUri,
    this.rootRelativePath = '',
  });

  final AndroidDocumentTreeBridge bridge;
  final String treeUri;
  final String rootRelativePath;

  Future<void> importFromDirectory(
    Directory source, {
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.importDirectoryFromPath(
      treeUri: treeUri,
      sourcePath: source.path,
      relativePath: rootRelativePath,
      onProgress: onProgress,
    );
  }

  Future<void> exportToDirectory(
    Directory destination, {
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.exportDirectoryToPath(
      treeUri: treeUri,
      destinationPath: destination.path,
      relativePath: rootRelativePath,
      onProgress: onProgress,
    );
  }

  Future<void> copyToDocumentTree(
    _DocumentTreeStorageRoot target, {
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.copyDirectoryToTree(
      sourceTreeUri: treeUri,
      targetTreeUri: target.treeUri,
      sourceRelativePath: rootRelativePath,
      targetRelativePath: target.rootRelativePath,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) {
    return bridge.writeBytes(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
      bytes: bytes,
    );
  }

  @override
  Future<void> writeString(String relativePath, String text) {
    return bridge.writeText(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
      text: text,
    );
  }

  @override
  Future<String> readString(String relativePath) {
    return bridge.readText(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<Uint8List> readBytes(String relativePath) {
    return bridge.readBytes(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  }) async {
    final String requestedPath = _resolveRelativePath(relativePath);
    final String prefix = _normalizeRelativePath(rootRelativePath);
    final List<DocumentTreeEntry> entries = await bridge.listEntries(
      treeUri: treeUri,
      relativePath: requestedPath,
      recursive: recursive,
    );
    return entries
        .map((DocumentTreeEntry entry) => _toStorageEntry(entry, prefix))
        .where((_StorageEntry entry) => entry.relativePath.isNotEmpty)
        .toList(growable: false);
  }

  _StorageEntry _toStorageEntry(DocumentTreeEntry entry, String prefix) {
    String relative = _normalizeRelativePath(entry.relativePath);
    if (prefix.isNotEmpty) {
      if (relative == prefix) {
        relative = '';
      } else if (relative.startsWith('$prefix/')) {
        relative = relative.substring(prefix.length + 1);
      }
    }
    return _StorageEntry(
      relativePath: relative,
      name: entry.name,
      uri: entry.uri,
      isDirectory: entry.isDirectory,
      size: entry.size,
    );
  }

  @override
  Future<bool> exists(String relativePath) {
    return bridge.exists(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<bool> deletePath(String relativePath) {
    return bridge.deletePath(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  String _resolveRelativePath(String relativePath) {
    final String normalized = _normalizeRelativePath(relativePath);
    final String normalizedRoot = _normalizeRelativePath(rootRelativePath);
    if (normalizedRoot.isEmpty) {
      return normalized;
    }
    if (normalized.isEmpty) {
      return normalizedRoot;
    }
    return '$normalizedRoot/$normalized';
  }

  String _normalizeRelativePath(String relativePath) {
    return relativePath.trim().replaceAll('\\', '/');
  }
}
