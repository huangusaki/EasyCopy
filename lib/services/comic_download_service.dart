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
import 'package:reader/services/comic_download_service/chapter_image_downloader.dart';
import 'package:reader/services/comic_download_service/download_contracts.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/migration_delta_journal_store.dart';
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
    ChapterImageDownloader? imageDownloader,
    Future<Directory> Function()? baseDirectoryProvider,
    DownloadStorageService? storageService,
    AndroidDocumentTreeBridge? documentTreeBridge,
    CachedLibraryIndexStore? cachedLibraryIndexStore,
    CachedChapterLocatorStore? cachedChapterLocatorStore,
  }) : _imageDownloader =
           imageDownloader ?? ChapterImageDownloader(client: client),
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

  final ChapterImageDownloader _imageDownloader;
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
    final List<String> orderedSavedFiles = await _imageDownloader.download(
      imageUrls: page.imageUrls,
      headers: <String, String>{
        'User-Agent': AppConfig.desktopUserAgent,
        'Referer': page.uri,
        if (cookieHeader.trim().isNotEmpty) 'Cookie': cookieHeader.trim(),
      },
      existingFiles: existingFiles,
      writeImage: (String fileName, Uint8List bytes) => root.writeBytes(
        _joinRelativePath(<String>[chapterDirectoryPath, fileName]),
        bytes,
      ),
      onProgress: onProgress,
      shouldPause: shouldPause,
      shouldCancel: shouldCancel,
    );
    _throwIfCancelled(shouldCancel);
    _throwIfPaused(shouldPause);
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
