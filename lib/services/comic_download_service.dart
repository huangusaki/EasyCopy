import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/android_document_tree_bridge.dart';
import 'package:easy_copy/services/cached_chapter_locator_store.dart';
import 'package:easy_copy/services/cached_library_index_store.dart';
import 'package:easy_copy/services/debug_trace.dart';
import 'package:easy_copy/services/migration_delta_journal_store.dart';
import 'package:easy_copy/services/document_tree_relative_image_provider.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:http/http.dart' as http;

typedef ChapterDownloadProgressCallback =
    Future<void> Function(ChapterDownloadProgress progress);
typedef ChapterDownloadPauseChecker = bool Function();
typedef ChapterDownloadCancelChecker = bool Function();
typedef DownloadStorageMigrationProgressCallback =
    FutureOr<void> Function(DownloadStorageMigrationProgress progress);

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

class ComicDownloadService {
  ComicDownloadService({
    http.Client? client,
    Future<Directory> Function()? baseDirectoryProvider,
    DownloadStorageService? storageService,
    AndroidDocumentTreeBridge? documentTreeBridge,
    CachedLibraryIndexStore? cachedLibraryIndexStore,
    CachedChapterLocatorStore? cachedChapterLocatorStore,
  }) : _client = client ?? http.Client(),
       _documentTreeBridge =
           documentTreeBridge ?? AndroidDocumentTreeBridge.instance,
       _cachedLibraryIndexStore =
           cachedLibraryIndexStore ?? CachedLibraryIndexStore.instance,
       _cachedChapterLocatorStore =
           cachedChapterLocatorStore ?? CachedChapterLocatorStore.instance,
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
  final CachedLibraryIndexStore _cachedLibraryIndexStore;
  final CachedChapterLocatorStore _cachedChapterLocatorStore;
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

  Future<String> storageKeyForPreferences(
    DownloadPreferences preferences, {
    bool verifyWritable = false,
  }) async {
    final DownloadStorageState state = await resolveStorageState(
      preferences: preferences,
      verifyWritable: verifyWritable,
    );
    return _storageService.storageKeyForState(state);
  }

  Future<void> copyCachedLibraryIndex({
    required DownloadPreferences from,
    required DownloadPreferences to,
  }) async {
    final String fromStorageKey = await storageKeyForPreferences(from);
    final String toStorageKey = await storageKeyForPreferences(to);
    if (fromStorageKey == toStorageKey) {
      return;
    }
    await _cachedLibraryIndexStore.copy(fromStorageKey, toStorageKey);
    await _cachedChapterLocatorStore.copy(fromStorageKey, toStorageKey);
  }

  String comicDirectoryPath(String comicTitle) {
    return _sanitizePathSegment(comicTitle);
  }

  String chapterDirectoryPath(String comicTitle, String chapterLabel) {
    return _joinRelativePath(<String>[
      _sanitizePathSegment(comicTitle),
      _sanitizePathSegment(chapterLabel),
    ]);
  }

  Future<ChapterDownloadResult> downloadChapter(
    ReaderPageData page, {
    String cookieHeader = '',
    String? comicUri,
    String? chapterHref,
    String? chapterLabel,
    String? coverUrl,
    CachedComicDetailSnapshot? detailSnapshot,
    ChapterDownloadProgressCallback? onProgress,
    ChapterDownloadPauseChecker? shouldPause,
    ChapterDownloadCancelChecker? shouldCancel,
  }) async {
    if (page.imageUrls.isEmpty) {
      throw FileSystemException('当前章节没有可下载图片。');
    }

    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: true,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
      storageState,
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
      await _upsertCachedChapterIndex(
        storageKey: storageKey,
        comicTitle: page.comicTitle,
        comicHref: resolvedComicUri,
        coverUrl: coverUrl ?? '',
        detailSnapshot: detailSnapshot,
        chapter: CachedChapterEntry(
          chapterTitle: resolvedChapterLabel,
          chapterHref: resolvedChapterHref,
          sourceUri: page.uri,
          directoryPath: chapterDirectoryPath,
          downloadedAt: DateTime.now(),
        ),
      );
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
    await _upsertCachedChapterIndex(
      storageKey: storageKey,
      comicTitle: page.comicTitle,
      comicHref: resolvedComicUri,
      coverUrl: coverUrl ?? '',
      detailSnapshot: detailSnapshot,
      chapter: CachedChapterEntry(
        chapterTitle: resolvedChapterLabel,
        chapterHref: resolvedChapterHref,
        sourceUri: page.uri,
        directoryPath: chapterDirectoryPath,
        downloadedAt: DateTime.now(),
      ),
    );

    return ChapterDownloadResult(
      directory: Directory(chapterDirectoryPath),
      fileCount: orderedSavedFiles.length,
      manifestFile: File(manifestRelativePath),
    );
  }

  Future<List<CachedComicLibraryEntry>> loadCachedLibrary({
    bool forceRescan = false,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final DownloadStorageState storageState = await resolveStorageState(
        verifyWritable: false,
      );
      final String storageKey = _storageService.storageKeyForState(
        storageState,
      );
      final List<Map<String, Object?>>? previousIndexedEntries =
          await _cachedLibraryIndexStore.read(storageKey);
      final List<Map<String, Object?>>? indexedEntries = forceRescan
          ? null
          : previousIndexedEntries;
      if (indexedEntries != null) {
        final List<CachedComicLibraryEntry> indexedLibrary = indexedEntries
            .map(CachedComicLibraryEntry.fromJson)
            .toList(growable: false);
        if (indexedLibrary.isNotEmpty) {
          final List<CachedChapterLocator> existingLocators =
              await _cachedChapterLocatorStore.entriesForStorage(storageKey);
          if (existingLocators.isEmpty) {
            await _replaceCachedChapterLocators(
              storageKey: storageKey,
              comics: indexedLibrary,
            );
          }
        }
        DebugTrace.log('cached_library.index_hit', <String, Object?>{
          'storageKey': storageKey,
          'comicCount': indexedLibrary.length,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        });
        return indexedLibrary;
      }
      final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
        storageState,
      );
      final _LibraryScanStats stats = _LibraryScanStats();
      final List<Map<String, Object?>> manifests = await _loadLibraryManifests(
        root,
        stats: stats,
      );
      final List<CachedComicLibraryEntry> comics =
          _buildCachedLibraryFromManifests(
            manifests,
            previousEntries:
                previousIndexedEntries
                    ?.map(CachedComicLibraryEntry.fromJson)
                    .toList(growable: false) ??
                const <CachedComicLibraryEntry>[],
          );
      await _cachedLibraryIndexStore.write(
        storageKey,
        comics
            .map((CachedComicLibraryEntry entry) => entry.toJson())
            .toList(growable: false),
      );
      await _replaceCachedChapterLocators(
        storageKey: storageKey,
        comics: comics,
      );
      DebugTrace.log('cached_library.rebuilt', <String, Object?>{
        'storageKey': storageKey,
        'forceRescan': forceRescan,
        'comicCount': comics.length,
        'comicDirCount': stats.comicDirectoryCount,
        'chapterDirCount': stats.chapterDirectoryCount,
        'manifestCount': stats.manifestCount,
        'listCalls': stats.listCalls,
        'existsCalls': stats.existsCalls,
        'readCalls': stats.readCalls,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      return comics;
    } catch (error) {
      DebugTrace.log('cached_library.failed', <String, Object?>{
        'error': error.toString(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      return const <CachedComicLibraryEntry>[];
    }
  }

  Future<List<Map<String, Object?>>> _loadLibraryManifests(
    _ResolvedStorageRoot root, {
    required _LibraryScanStats stats,
  }) async {
    final List<Map<String, Object?>> manifests = <Map<String, Object?>>[];
    stats.listCalls += 1;
    final List<_StorageEntry> comicEntries = await root.listEntries(
      '',
      recursive: false,
    );
    stats.comicDirectoryCount = comicEntries
        .where((_StorageEntry entry) => entry.isDirectory)
        .length;

    for (final _StorageEntry comicEntry in comicEntries) {
      if (!comicEntry.isDirectory || comicEntry.relativePath.trim().isEmpty) {
        continue;
      }
      stats.listCalls += 1;
      final List<_StorageEntry> chapterEntries = await root.listEntries(
        comicEntry.relativePath,
        recursive: false,
      );
      stats.chapterDirectoryCount += chapterEntries
          .where((_StorageEntry entry) => entry.isDirectory)
          .length;

      for (final _StorageEntry chapterEntry in chapterEntries) {
        if (!chapterEntry.isDirectory ||
            chapterEntry.relativePath.trim().isEmpty) {
          continue;
        }
        final String manifestRelativePath = _joinRelativePath(<String>[
          chapterEntry.relativePath,
          'manifest.json',
        ]);
        stats.existsCalls += 1;
        if (!await root.exists(manifestRelativePath)) {
          continue;
        }
        try {
          stats.readCalls += 1;
          final Object? decoded = jsonDecode(
            await root.readString(manifestRelativePath),
          );
          if (decoded is! Map<Object?, Object?>) {
            continue;
          }
          manifests.add(<String, Object?>{
            ...decoded.map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
            '__directoryPath': chapterEntry.relativePath,
          });
          stats.manifestCount += 1;
        } catch (_) {
          continue;
        }
      }
    }

    return manifests;
  }

  List<CachedComicLibraryEntry> _buildCachedLibraryFromManifests(
    List<Map<String, Object?>> manifests, {
    List<CachedComicLibraryEntry> previousEntries =
        const <CachedComicLibraryEntry>[],
  }) {
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

    final Map<String, CachedComicLibraryEntry> previousEntriesByKey =
        <String, CachedComicLibraryEntry>{
          for (final CachedComicLibraryEntry entry in previousEntries)
            if (_comicKeyForUri(entry.comicHref).isNotEmpty)
              _comicKeyForUri(entry.comicHref): entry,
        };
    final Map<String, CachedComicLibraryEntry> previousEntriesByTitle =
        <String, CachedComicLibraryEntry>{
          for (final CachedComicLibraryEntry entry in previousEntries)
            if (entry.comicTitle.isNotEmpty) entry.comicTitle: entry,
        };

    return grouped.entries
        .map((MapEntry<String, List<CachedChapterEntry>> entry) {
          final List<CachedChapterEntry> chapters =
              entry.value.toList(growable: false)..sort(
                (CachedChapterEntry left, CachedChapterEntry right) =>
                    right.downloadedAt.compareTo(left.downloadedAt),
              );
          final CachedComicLibraryEntry? previousEntry =
              previousEntriesByKey[entry.key] ??
              previousEntriesByTitle[comicTitles[entry.key] ?? ''];
          return CachedComicLibraryEntry(
            comicTitle: comicTitles[entry.key] ?? '未命名漫画',
            comicHref: comicHrefs[entry.key] ?? '',
            coverUrl: comicCovers[entry.key] ?? '',
            chapters: chapters,
            detailSnapshot: previousEntry?.detailSnapshot,
          );
        })
        .toList(growable: false)
      ..sort((CachedComicLibraryEntry left, CachedComicLibraryEntry right) {
        final DateTime leftTime =
            left.lastDownloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime rightTime =
            right.lastDownloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      });
  }

  Iterable<CachedChapterLocator> _locatorsFromLibrary(
    String storageKey,
    Iterable<CachedComicLibraryEntry> comics,
  ) sync* {
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      return;
    }
    for (final CachedComicLibraryEntry comic in comics) {
      for (final CachedChapterEntry chapter in comic.chapters) {
        final CachedChapterLocator locator = _locatorForChapter(
          storageKey: normalizedStorageKey,
          comicTitle: comic.comicTitle,
          chapter: chapter,
        );
        if (locator.directoryPath.isEmpty) {
          continue;
        }
        yield locator;
      }
    }
  }

  CachedChapterLocator _locatorForChapter({
    required String storageKey,
    required String comicTitle,
    required CachedChapterEntry chapter,
  }) {
    return CachedChapterLocator(
      storageKey: storageKey,
      chapterPathKey: _pathKeyForUri(chapter.chapterHref),
      sourcePathKey: _pathKeyForUri(chapter.sourceUri),
      directoryPath: chapter.directoryPath,
      comicTitle: comicTitle,
      chapterTitle: chapter.chapterTitle,
      downloadedAt: chapter.downloadedAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _replaceCachedChapterLocators({
    required String storageKey,
    required List<CachedComicLibraryEntry> comics,
  }) {
    return _cachedChapterLocatorStore.replaceStorage(
      storageKey,
      _locatorsFromLibrary(storageKey, comics),
    );
  }

  Future<void> _upsertCachedChapterLocator({
    required String storageKey,
    required String comicTitle,
    required CachedChapterEntry chapter,
  }) {
    return _cachedChapterLocatorStore.upsert(
      _locatorForChapter(
        storageKey: storageKey,
        comicTitle: comicTitle,
        chapter: chapter,
      ),
    );
  }

  Future<void> _upsertCachedChapterIndex({
    required String storageKey,
    required String comicTitle,
    required String comicHref,
    required String coverUrl,
    CachedComicDetailSnapshot? detailSnapshot,
    required CachedChapterEntry chapter,
  }) async {
    final List<CachedComicLibraryEntry> comics = await _readCachedLibraryIndex(
      storageKey,
    );
    final int comicIndex = comics.indexWhere(
      (CachedComicLibraryEntry entry) =>
          _comicKeyForUri(entry.comicHref) == _comicKeyForUri(comicHref) &&
          _comicKeyForUri(comicHref).isNotEmpty,
    );
    CachedComicLibraryEntry? comic = comicIndex >= 0
        ? comics[comicIndex]
        : null;
    comic ??= comics.cast<CachedComicLibraryEntry?>().firstWhere(
      (CachedComicLibraryEntry? entry) =>
          entry != null && entry.comicTitle == comicTitle,
      orElse: () => null,
    );
    final List<CachedChapterEntry> chapters =
        (comic?.chapters ?? const <CachedChapterEntry>[]).toList(
          growable: true,
        );
    final int chapterIndex = chapters.indexWhere(
      (CachedChapterEntry entry) =>
          entry.directoryPath == chapter.directoryPath,
    );
    if (chapterIndex >= 0) {
      chapters[chapterIndex] = chapter;
    } else {
      chapters.add(chapter);
    }
    chapters.sort(
      (CachedChapterEntry left, CachedChapterEntry right) =>
          right.downloadedAt.compareTo(left.downloadedAt),
    );
    final CachedComicLibraryEntry nextComic = CachedComicLibraryEntry(
      comicTitle: comicTitle,
      comicHref: comicHref,
      coverUrl: coverUrl,
      chapters: chapters.toList(growable: false),
      detailSnapshot: detailSnapshot ?? comic?.detailSnapshot,
    );
    if (comicIndex >= 0) {
      comics[comicIndex] = nextComic;
    } else if (comic != null) {
      final int fallbackIndex = comics.indexOf(comic);
      if (fallbackIndex >= 0) {
        comics[fallbackIndex] = nextComic;
      } else {
        comics.add(nextComic);
      }
    } else {
      comics.add(nextComic);
    }
    comics.sort(
      (CachedComicLibraryEntry left, CachedComicLibraryEntry right) =>
          (right.lastDownloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                left.lastDownloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
    );
    await _writeCachedLibraryIndex(storageKey, comics);
    await _upsertCachedChapterLocator(
      storageKey: storageKey,
      comicTitle: comicTitle,
      chapter: chapter,
    );
  }

  Future<void> _removeChapterFromCachedLibraryIndex({
    required String storageKey,
    required String chapterDirectoryPath,
  }) async {
    final List<CachedComicLibraryEntry> comics = await _readCachedLibraryIndex(
      storageKey,
    );
    if (comics.isEmpty) {
      return;
    }
    final List<CachedComicLibraryEntry> nextComics =
        <CachedComicLibraryEntry>[];
    for (final CachedComicLibraryEntry comic in comics) {
      final List<CachedChapterEntry> chapters = comic.chapters
          .where(
            (CachedChapterEntry chapter) =>
                chapter.directoryPath != chapterDirectoryPath,
          )
          .toList(growable: false);
      if (chapters.isEmpty) {
        continue;
      }
      nextComics.add(
        CachedComicLibraryEntry(
          comicTitle: comic.comicTitle,
          comicHref: comic.comicHref,
          coverUrl: comic.coverUrl,
          chapters: chapters,
          detailSnapshot: comic.detailSnapshot,
        ),
      );
    }
    await _writeCachedLibraryIndex(storageKey, nextComics);
    await _cachedChapterLocatorStore.removeDirectoryPath(
      storageKey: storageKey,
      directoryPath: chapterDirectoryPath,
    );
  }

  Future<void> _removeComicFromCachedLibraryIndex({
    required String storageKey,
    required String comicTitle,
    String comicHref = '',
    String comicRelativePath = '',
  }) async {
    final String targetComicKey = _comicKeyForUri(comicHref);
    final List<CachedComicLibraryEntry> comics = await _readCachedLibraryIndex(
      storageKey,
    );
    if (comics.isEmpty) {
      return;
    }
    final List<CachedComicLibraryEntry> nextComics = comics
        .where((CachedComicLibraryEntry comic) {
          if (targetComicKey.isNotEmpty &&
              _comicKeyForUri(comic.comicHref) == targetComicKey) {
            return false;
          }
          if (comic.comicTitle == comicTitle) {
            return false;
          }
          if (comicRelativePath.isNotEmpty &&
              comic.chapters.any(
                (CachedChapterEntry chapter) =>
                    chapter.directoryPath == comicRelativePath ||
                    chapter.directoryPath.startsWith('$comicRelativePath/'),
              )) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    await _writeCachedLibraryIndex(storageKey, nextComics);
    if (comicRelativePath.isNotEmpty) {
      await _cachedChapterLocatorStore.removeComicDirectory(
        storageKey: storageKey,
        comicRelativePath: comicRelativePath,
      );
    }
  }

  Future<List<CachedComicLibraryEntry>> _readCachedLibraryIndex(
    String storageKey,
  ) async {
    final List<Map<String, Object?>>? rawEntries =
        await _cachedLibraryIndexStore.read(storageKey);
    if (rawEntries == null) {
      return <CachedComicLibraryEntry>[];
    }
    return rawEntries
        .map(CachedComicLibraryEntry.fromJson)
        .toList(growable: true);
  }

  Future<void> _writeCachedLibraryIndex(
    String storageKey,
    List<CachedComicLibraryEntry> comics,
  ) {
    return _cachedLibraryIndexStore.write(
      storageKey,
      comics
          .map((CachedComicLibraryEntry entry) => entry.toJson())
          .toList(growable: false),
    );
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

  Future<void> upsertCachedComicDetailSnapshot(DetailPageData page) async {
    final CachedComicDetailSnapshot snapshot = page.toCachedDetailSnapshot();
    if (snapshot.isEmpty) {
      return;
    }
    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: false,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final List<CachedComicLibraryEntry> library = await _readCachedLibraryIndex(
      storageKey,
    );
    if (library.isEmpty) {
      return;
    }

    final String targetComicKey = _comicKeyForUri(page.uri);
    final int comicIndex = library.indexWhere((CachedComicLibraryEntry entry) {
      if (targetComicKey.isNotEmpty &&
          _comicKeyForUri(entry.comicHref) == targetComicKey) {
        return true;
      }
      return entry.comicTitle == page.title;
    });
    if (comicIndex == -1) {
      return;
    }

    final CachedComicLibraryEntry current = library[comicIndex];
    library[comicIndex] = current.copyWith(
      comicTitle: page.title.isEmpty ? current.comicTitle : page.title,
      comicHref: page.uri.isEmpty ? current.comicHref : page.uri,
      coverUrl: page.coverUrl.isEmpty ? current.coverUrl : page.coverUrl,
      detailSnapshot: snapshot,
    );
    await _writeCachedLibraryIndex(storageKey, library);
  }

  DetailPageData buildCachedDetailPage(CachedComicLibraryEntry entry) {
    final List<ChapterData> chapters = entry.chapters
        .map((CachedChapterEntry chapter) {
          final String chapterHref = chapter.chapterHref.isNotEmpty
              ? chapter.chapterHref
              : chapter.sourceUri;
          return ChapterData(
            label: chapter.chapterTitle,
            href: chapterHref,
            subtitle: _formatCachedChapterSubtitle(chapter),
          );
        })
        .toList(growable: false);
    final CachedComicDetailSnapshot? snapshot = entry.detailSnapshot;
    final String detailUri = _cachedComicDetailUri(entry);
    final String fallbackStartReadingHref = _preferredCachedStartReadingHref(
      chapters,
      preferredHref: snapshot?.startReadingHref ?? '',
    );
    return DetailPageData(
      title: entry.comicTitle,
      uri: detailUri,
      coverUrl: entry.coverUrl,
      aliases: snapshot?.aliases ?? '',
      authors: snapshot?.authors ?? '',
      heat: snapshot?.heat ?? '',
      updatedAt: snapshot?.updatedAt ?? '',
      status: snapshot?.status ?? '已缓存',
      summary: snapshot?.summary ?? '',
      tags: snapshot?.tags ?? const <LinkAction>[],
      startReadingHref: fallbackStartReadingHref,
      chapterGroups: const <ChapterGroupData>[],
      chapters: chapters,
    );
  }

  Future<ReaderPageData?> loadCachedReaderPage(
    String chapterHref, {
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: false,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final String targetPathKey = _pathKeyForUri(chapterHref);
    if (targetPathKey.isEmpty) {
      return null;
    }
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
      storageState,
    );
    final Stopwatch locatorStopwatch = Stopwatch()..start();
    CachedChapterLocator? locator = await _cachedChapterLocatorStore
        .findByPathKey(storageKey: storageKey, targetPathKey: targetPathKey);
    DebugTrace.log('cached_reader.locator_lookup', <String, Object?>{
      'storageKey': storageKey,
      'targetPathKey': targetPathKey,
      'hit': locator != null,
      'elapsedMs': locatorStopwatch.elapsedMilliseconds,
    });

    CachedChapterEntry? entry;
    if (locator != null) {
      entry = CachedChapterEntry(
        chapterTitle: locator.chapterTitle,
        chapterHref: locator.chapterPathKey,
        sourceUri: locator.sourcePathKey,
        directoryPath: locator.directoryPath,
        downloadedAt: locator.downloadedAt,
      );
    } else {
      entry = await _findCachedChapter(chapterHref);
      if (entry != null) {
        await _upsertCachedChapterLocator(
          storageKey: storageKey,
          comicTitle: '',
          chapter: entry,
        );
      }
    }
    if (entry == null || entry.directoryPath.isEmpty) {
      return null;
    }

    try {
      final Stopwatch manifestStopwatch = Stopwatch()..start();
      Map<String, Object?>? manifest = await _readCachedChapterManifest(
        root,
        entry.directoryPath,
      );
      if (manifest == null) {
        if (locator != null) {
          await _cachedChapterLocatorStore.removeDirectoryPath(
            storageKey: storageKey,
            directoryPath: entry.directoryPath,
          );
        }
        entry = await _findCachedChapter(chapterHref, forceRescan: true);
        if (entry == null || entry.directoryPath.isEmpty) {
          return null;
        }
        manifest = await _readCachedChapterManifest(root, entry.directoryPath);
        if (manifest == null) {
          return null;
        }
        await _upsertCachedChapterLocator(
          storageKey: storageKey,
          comicTitle: '',
          chapter: entry,
        );
      }
      final List<String> fileNames =
          ((manifest['files'] as List<Object?>?) ?? const <Object?>[])
              .whereType<String>()
              .map((String fileName) => fileName.trim())
              .where((String fileName) => fileName.isNotEmpty)
              .toList(growable: false);
      final Stopwatch imageRefStopwatch = Stopwatch()..start();
      final List<String> imageUrls = root.buildReaderImageUrls(
        entry.directoryPath,
        fileNames,
      );
      DebugTrace.log('cached_reader.manifest_loaded', <String, Object?>{
        'storageKey': storageKey,
        'directoryPath': entry.directoryPath,
        'imageCount': imageUrls.length,
        'locatorHit': locator != null,
        'manifestReadMs': manifestStopwatch.elapsedMilliseconds,
        'imageRefBuildMs': imageRefStopwatch.elapsedMilliseconds,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      if (imageUrls.isEmpty) {
        return null;
      }

      final Map<String, Object?> normalizedManifest = manifest;
      final String sourceUri = _stringValue(normalizedManifest['sourceUri']);
      final String manifestChapterHref = _stringValue(
        normalizedManifest['chapterHref'],
      );
      final DateTime downloadedAt =
          DateTime.tryParse(_stringValue(normalizedManifest['downloadedAt'])) ??
          entry.downloadedAt;
      final String resolvedUri = sourceUri.isNotEmpty
          ? _rewriteAllowedUri(sourceUri)
          : (manifestChapterHref.isNotEmpty
                ? _rewriteAllowedUri(manifestChapterHref)
                : _rewriteAllowedUri(chapterHref));
      final String resolvedPrevHref = prevHref.trim().isNotEmpty
          ? _rewriteAllowedUri(prevHref)
          : _rewriteAllowedUri(_stringValue(normalizedManifest['prevHref']));
      final String resolvedNextHref = nextHref.trim().isNotEmpty
          ? _rewriteAllowedUri(nextHref)
          : _rewriteAllowedUri(_stringValue(normalizedManifest['nextHref']));
      final String resolvedCatalogHref = catalogHref.trim().isNotEmpty
          ? catalogHref.trim()
          : _rewriteAllowedUri(
              _stringValue(normalizedManifest['catalogHref']).isNotEmpty
                  ? _stringValue(normalizedManifest['catalogHref'])
                  : _stringValue(normalizedManifest['comicUri']),
            );
      final String chapterTitle = _stringValue(
        normalizedManifest['chapterTitle'],
      );
      final String chapterLabel = _stringValue(
        normalizedManifest['chapterLabel'],
      );
      final String progressLabel = _stringValue(
        normalizedManifest['progressLabel'],
      );
      await _upsertCachedChapterLocator(
        storageKey: storageKey,
        comicTitle: _stringValue(normalizedManifest['comicTitle']),
        chapter: CachedChapterEntry(
          chapterTitle: chapterTitle.isNotEmpty ? chapterTitle : chapterLabel,
          chapterHref: manifestChapterHref,
          sourceUri: sourceUri,
          directoryPath: entry.directoryPath,
          downloadedAt: downloadedAt,
        ),
      );

      return ReaderPageData(
        title: chapterTitle.isNotEmpty
            ? chapterTitle
            : (chapterLabel.isNotEmpty ? chapterLabel : '已缓存章节'),
        uri: resolvedUri,
        comicTitle: _stringValue(normalizedManifest['comicTitle']),
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
      final DownloadStorageState storageState = await resolveStorageState(
        verifyWritable: false,
      );
      final String storageKey = _storageService.storageKeyForState(
        storageState,
      );
      final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
        storageState,
      );
      if (!await root.deletePath(comicRelativePath)) {
        await deleteComicCacheByTitle(entry.comicTitle);
        return;
      }
      await _removeComicFromCachedLibraryIndex(
        storageKey: storageKey,
        comicTitle: entry.comicTitle,
        comicHref: entry.comicHref,
        comicRelativePath: comicRelativePath,
      );
    } catch (_) {
      await deleteComicCacheByTitle(entry.comicTitle);
    }
  }

  Future<Map<String, Object?>?> _readCachedChapterManifest(
    _ResolvedStorageRoot root,
    String directoryPath,
  ) async {
    final String manifestRelativePath = _joinRelativePath(<String>[
      directoryPath,
      'manifest.json',
    ]);
    if (!await root.exists(manifestRelativePath)) {
      return null;
    }
    final Object? decoded = jsonDecode(
      await root.readString(manifestRelativePath),
    );
    if (decoded is! Map) {
      return null;
    }
    return decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }

  CachedChapterEntry? _findCachedChapterInLibrary(
    Iterable<CachedComicLibraryEntry> library,
    String targetPathKey,
  ) {
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

  Future<CachedChapterEntry?> _findCachedChapter(
    String chapterHref, {
    bool forceRescan = false,
  }) async {
    final String targetPathKey = _pathKeyForUri(chapterHref);
    if (targetPathKey.isEmpty) {
      return null;
    }
    final List<CachedComicLibraryEntry> library = await loadCachedLibrary(
      forceRescan: forceRescan,
    );
    return _findCachedChapterInLibrary(library, targetPathKey);
  }

  Future<void> deleteComicCacheByTitle(String comicTitle) async {
    try {
      final DownloadStorageState storageState = await resolveStorageState(
        verifyWritable: false,
      );
      final String storageKey = _storageService.storageKeyForState(
        storageState,
      );
      final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
        storageState,
      );
      final String comicRelativePath = _sanitizePathSegment(comicTitle);
      await root.deletePath(comicRelativePath);
      await _removeComicFromCachedLibraryIndex(
        storageKey: storageKey,
        comicTitle: comicTitle,
        comicRelativePath: comicRelativePath,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> cleanupIncompleteChapter({
    required String comicTitle,
    required String chapterLabel,
  }) async {
    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: false,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
      storageState,
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
      await _removeChapterFromCachedLibraryIndex(
        storageKey: storageKey,
        chapterDirectoryPath: chapterDirectoryPath,
      );
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
    DownloadStorageMigrationProgressCallback? onProgress,
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
    DownloadStorageMigrationProgressCallback? onProgress,
  }) async {
    final DownloadStorageState state = await resolveStorageState(
      preferences: preferences,
      verifyWritable: false,
    );
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(state);
    final _MigrationProgressController progressController =
        _MigrationProgressController(
          fromPath: state.displayPath,
          toPath: state.displayPath,
          onProgress: onProgress,
        );
    return _cleanupStorageRootSafely(
      root,
      progressController: progressController,
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

  String _formatCachedChapterSubtitle(CachedChapterEntry chapter) {
    final String timestamp = _formatDownloadedAt(chapter.downloadedAt);
    if (timestamp.isEmpty) {
      return '';
    }
    return '已缓存 $timestamp';
  }

  String _formatDownloadedAt(DateTime value) {
    if (value == DateTime.fromMillisecondsSinceEpoch(0)) {
      return '';
    }
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  String _cachedComicDetailUri(CachedComicLibraryEntry entry) {
    if (entry.comicHref.trim().isNotEmpty) {
      return _rewriteAllowedUri(entry.comicHref);
    }
    for (final CachedChapterEntry chapter in entry.chapters) {
      final String derived = _deriveComicUri(
        chapter.chapterHref.isNotEmpty
            ? chapter.chapterHref
            : chapter.sourceUri,
      );
      if (derived.isNotEmpty) {
        return derived;
      }
    }
    final String slug = Uri.encodeComponent(
      entry.comicTitle.isEmpty ? 'offline' : entry.comicTitle,
    );
    return AppConfig.resolvePath('/comic/offline/$slug').toString();
  }

  String _preferredCachedStartReadingHref(
    List<ChapterData> chapters, {
    String preferredHref = '',
  }) {
    final String preferredPathKey = _pathKeyForUri(preferredHref);
    if (preferredPathKey.isNotEmpty) {
      for (final ChapterData chapter in chapters) {
        if (_pathKeyForUri(chapter.href) == preferredPathKey) {
          return chapter.href;
        }
      }
    }
    return chapters.isEmpty ? '' : chapters.first.href;
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
    return _resolveStorageRootFromState(storageState);
  }

  Future<_ResolvedStorageRoot> _resolveStorageRootFromState(
    DownloadStorageState storageState,
  ) async {
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

  Future<void> _copyRelativePath(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot,
    String relativePath,
  ) async {
    final List<_StorageEntry> entries = await sourceRoot.listEntries(
      relativePath,
      recursive: true,
    );
    if (entries.isEmpty) {
      return;
    }
    for (final _StorageEntry entry in entries) {
      if (entry.isDirectory || _shouldSkipMigrationFile(entry.name)) {
        continue;
      }
      await targetRoot.writeBytes(
        entry.relativePath,
        await sourceRoot.readBytes(entry.relativePath),
      );
    }
  }

  Future<int> _copyFileSystemDirectoryContentsInIsolate(
    Directory source,
    Directory target,
  ) {
    return Isolate.run<int>(
      () => _copyFileSystemTreeSync(
        _FileSystemCopyRequest(
          sourcePath: source.path,
          targetPath: target.path,
        ),
      ),
    );
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
      await progressController.startMigrating();
      final int copiedFiles = await _copyFileSystemDirectoryContentsInIsolate(
        sourceRoot.rootDirectory,
        targetRoot.rootDirectory,
      );
      await progressController.syncMigrating(
        completedItems: copiedFiles,
        totalItems: copiedFiles,
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

  bool _shouldSkipMigrationFile(String fileName) {
    return _shouldSkipMigrationFileName(fileName);
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

  static const Duration _minimumEmitInterval = Duration(milliseconds: 800);
  static const int _largeProgressStep = 160;
  static const int _smallProgressStep = 12;

  final String fromPath;
  final String toPath;
  final DownloadStorageMigrationProgressCallback? onProgress;

  int _completedItems = 0;
  int _totalItems = 0;
  int _lastEmittedCompletedItems = -1;
  int _lastEmittedTotalItems = -1;
  DateTime? _lastEmittedAt;
  DownloadStorageMigrationPhase? _lastEmittedPhase;

  Future<void> emitPreparing() {
    return _emit(
      DownloadStorageMigrationPhase.preparing,
      message: '正在准备迁移缓存…',
      force: true,
    );
  }

  Future<void> startMigrating({int totalItems = 0}) {
    _completedItems = 0;
    _totalItems = totalItems;
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
      force: true,
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
      force: true,
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
    return _emit(
      DownloadStorageMigrationPhase.cleaning,
      message: '正在清理旧缓存目录…',
      force: true,
    );
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
    bool force = false,
  }) async {
    if (onProgress == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (!force && !_shouldEmit(phase, now)) {
      return;
    }
    _lastEmittedAt = now;
    _lastEmittedCompletedItems = _completedItems;
    _lastEmittedTotalItems = _totalItems;
    _lastEmittedPhase = phase;
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

  bool _shouldEmit(DownloadStorageMigrationPhase phase, DateTime now) {
    if (_lastEmittedPhase != phase) {
      return true;
    }
    if (_completedItems <= 1 ||
        (_totalItems > 0 && _completedItems >= _totalItems)) {
      return true;
    }
    if (_totalItems != _lastEmittedTotalItems) {
      return true;
    }
    final int progressStep = _totalItems > 0 && _totalItems <= 64
        ? _smallProgressStep
        : _largeProgressStep;
    if (_completedItems - _lastEmittedCompletedItems >= progressStep) {
      return true;
    }
    final DateTime? lastEmittedAt = _lastEmittedAt;
    if (lastEmittedAt == null) {
      return true;
    }
    return now.difference(lastEmittedAt) >= _minimumEmitInterval;
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

  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  );
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

  @override
  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  ) {
    final String normalizedChapterDirectoryPath = _normalizeRelativePath(
      chapterDirectoryPath,
    );
    return fileNames
        .map((String fileName) => fileName.trim())
        .where((String fileName) => fileName.isNotEmpty)
        .map(
          (String fileName) => File(
            _absolutePath(
              normalizedChapterDirectoryPath.isEmpty
                  ? fileName
                  : '$normalizedChapterDirectoryPath/$fileName',
            ),
          ).uri.toString(),
        )
        .toList(growable: false);
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

  @override
  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  ) {
    final String normalizedChapterDirectoryPath = _normalizeRelativePath(
      chapterDirectoryPath,
    );
    return fileNames
        .map((String fileName) => fileName.trim())
        .where((String fileName) => fileName.isNotEmpty)
        .map((String fileName) {
          final String relativePath = normalizedChapterDirectoryPath.isEmpty
              ? fileName
              : '$normalizedChapterDirectoryPath/$fileName';
          return buildDocumentTreeRelativeImageUri(
            treeUri: treeUri,
            relativePath: _resolveRelativePath(relativePath),
          );
        })
        .toList(growable: false);
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

class _LibraryScanStats {
  int comicDirectoryCount = 0;
  int chapterDirectoryCount = 0;
  int manifestCount = 0;
  int listCalls = 0;
  int existsCalls = 0;
  int readCalls = 0;
}

class _FileSystemCopyRequest {
  const _FileSystemCopyRequest({
    required this.sourcePath,
    required this.targetPath,
  });

  final String sourcePath;
  final String targetPath;
}

int _copyFileSystemTreeSync(_FileSystemCopyRequest request) {
  final Directory source = Directory(request.sourcePath);
  final Directory target = Directory(request.targetPath);
  target.createSync(recursive: true);
  return _copyDirectoryRecursiveSync(source, target);
}

int _copyDirectoryRecursiveSync(Directory source, Directory target) {
  int copiedFiles = 0;
  final List<FileSystemEntity> children = source.listSync(followLinks: false);
  for (final FileSystemEntity child in children) {
    final String name = child.uri.pathSegments.isEmpty
        ? ''
        : child.uri.pathSegments.lastWhere(
            (String segment) => segment.isNotEmpty,
            orElse: () => '',
          );
    if (name.isEmpty || _shouldSkipMigrationFileName(name)) {
      continue;
    }
    if (child is Directory) {
      final Directory nextTarget = Directory(
        '${target.path}${Platform.pathSeparator}$name',
      );
      nextTarget.createSync(recursive: true);
      copiedFiles += _copyDirectoryRecursiveSync(child, nextTarget);
      continue;
    }
    if (child is File) {
      final File nextTarget = File(
        '${target.path}${Platform.pathSeparator}$name',
      );
      nextTarget.parent.createSync(recursive: true);
      child.copySync(nextTarget.path);
      copiedFiles += 1;
    }
  }
  return copiedFiles;
}

bool _shouldSkipMigrationFileName(String fileName) {
  final String normalized = fileName.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.endsWith('.part') ||
      normalized.endsWith('.migrate_tmp') ||
      normalized.startsWith('.storage_probe_');
}
