import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/cached_chapter_locator_store.dart';
import 'package:reader/services/cached_library_index_store.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';
import 'package:reader/services/network_client.dart';
import 'package:reader/services/tree_image_provider.dart';
import 'package:reader/services/uri_keys.dart';

part 'comic_download_service/cached_detail_reader.dart';
part 'comic_download_service/cached_library_index.dart';
part 'comic_download_service/download_models.dart';
part 'comic_download_service/download_path_utils.dart';
part 'comic_download_service/migration_flow.dart';
part 'comic_download_service/storage_roots.dart';

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

  static const int _imageDownloadConcurrency = 3;

  final http.Client _client;
  final AndroidDocumentTreeBridge _documentTreeBridge;
  final CachedLibraryIndexStore _cachedLibraryIndexStore;
  final CachedChapterLocatorStore _cachedChapterLocatorStore;
  final DownloadStorageService _storageService;

  bool get supportsCustomStorageSelection => _storageService.supportsCustomDirs;

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
      throw const FileSystemException('当前章节没有可下载图片。');
    }

    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: true,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
      storageState,
    );
    final String comicDirectoryPath = _sanitizePathSegment(page.comicTitle);
    final bool comicDirectoryExisted = await root.exists(comicDirectoryPath);
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
      comicDirectoryPath,
      _sanitizePathSegment(resolvedChapterLabel),
    ]);
    final String manifestRelativePath = _joinRelativePath(<String>[
      chapterDirectoryPath,
      'manifest.json',
    ]);

    final ChapterDownloadResult? completedResult = await _loadCompletedChapter(
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

    int completedCount = savedFiles
        .where((String fileName) => fileName.isNotEmpty)
        .length;

    Future<void> emitProgress(String label) async {
      if (onProgress == null) {
        return;
      }
      await onProgress(
        ChapterDownloadProgress(
          completedCount: completedCount,
          totalCount: page.imageUrls.length,
          currentLabel: label,
        ),
      );
    }

    Future<void> downloadImageAt(int index) async {
      _throwIfCancelled(shouldCancel);
      _throwIfPaused(shouldPause);

      final String existingFileName = savedFiles[index];
      if (existingFileName.isNotEmpty) {
        await emitProgress('Restored $completedCount/${page.imageUrls.length}');
        return;
      }

      final Uri imageUri = Uri.parse(page.imageUrls[index]);
      final http.Response response = await NetworkClient.get(
        _client,
        imageUri,
        headers: headers,
        timeout: NetworkClient.imageTimeout,
        maxRetries: 2,
        label: 'download.image',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Image download failed: ${response.statusCode}',
          uri: imageUri,
        );
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
      completedCount += 1;

      await emitProgress(
        'Downloading $completedCount/${page.imageUrls.length}',
      );
    }

    int nextImageIndex = 0;

    Future<void> runDownloadWorker() async {
      while (true) {
        _throwIfCancelled(shouldCancel);
        _throwIfPaused(shouldPause);
        final int index = nextImageIndex;
        nextImageIndex += 1;
        if (index >= page.imageUrls.length) {
          return;
        }
        await downloadImageAt(index);
      }
    }

    final int workerCount = page.imageUrls.length < _imageDownloadConcurrency
        ? page.imageUrls.length
        : _imageDownloadConcurrency;
    if (workerCount > 0) {
      await Future.wait(<Future<void>>[
        for (int worker = 0; worker < workerCount; worker += 1)
          runDownloadWorker(),
      ]);
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
    await _markOwnedComicDirectory(
      root,
      comicDirectoryPath,
      existedBefore: comicDirectoryExisted,
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
}
