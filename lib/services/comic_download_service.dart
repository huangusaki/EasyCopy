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
import 'package:reader/services/comic_download_service/image_integrity.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
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
    final DownloadStorageState sourceState = await resolveStorageState(
      preferences: from,
      verifyWritable: false,
    );
    final DownloadStorageState targetState = await resolveStorageState(
      preferences: to,
      verifyWritable: false,
    );
    final String fromStorageKey = _storageService.storageKeyForState(
      sourceState,
    );
    final String toStorageKey = _storageService.storageKeyForState(targetState);
    if (fromStorageKey == toStorageKey) {
      return;
    }
    final _ResolvedStorageRoot targetRoot = await _resolveStorageRootFromState(
      targetState,
    );
    final List<Map<String, Object?>> manifests = await _loadLibraryManifests(
      targetRoot,
      stats: _LibraryScanStats(),
    );
    final List<CachedComicLibraryEntry> comics = _buildLibraryFromManifests(
      manifests,
      previousEntries: <CachedComicLibraryEntry>[
        ...await _readCachedLibraryMetadata(sourceState),
        ...await _readCachedLibraryMetadata(targetState),
      ],
    );
    await _writeCachedLibraryIndex(toStorageKey, comics);
    await _replaceCachedChapterLocators(
      storageKey: toStorageKey,
      comics: comics,
    );
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

  Future<void> downloadChapter(
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
    await _checkChapterDirectoryIdentity(
      root,
      chapterDirectoryPath,
      chapterHref: resolvedChapterHref,
      sourceUri: page.uri,
    );

    final bool isCompleted = await _isChapterCompleted(
      root: root,
      manifestRelativePath: manifestRelativePath,
      chapterDirectoryPath: chapterDirectoryPath,
      expectedImageCount: page.imageUrls.length,
    );
    if (isCompleted) {
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
      return;
    }

    if (page.imageUrls.any((String url) {
      final Uri? uri = Uri.tryParse(url);
      return uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty;
    })) {
      throw const FileSystemException('本地章节缓存已变化，请重试下载。');
    }

    final Map<int, String> existingFiles = await _loadExistingImageFiles(
      root,
      chapterDirectoryPath,
    );
    final String downloadIdentityPath = _joinRelativePath(<String>[
      chapterDirectoryPath,
      _downloadIdentityFileName,
    ]);
    await root.writeString(
      downloadIdentityPath,
      jsonEncode(<String, Object?>{
        'chapterHref': resolvedChapterHref,
        'sourceUri': page.uri,
        'imageCount': page.imageUrls.length,
      }),
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
        'sourceImageUrls': page.imageUrls,
      }),
    );
    await root.deletePath(downloadIdentityPath);
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
  }

  Future<void> _checkChapterDirectoryIdentity(
    _ResolvedStorageRoot root,
    String directoryPath, {
    required String chapterHref,
    required String sourceUri,
  }) async {
    if (!await root.exists(directoryPath)) return;
    for (final String name in <String>[
      'manifest.json',
      _downloadIdentityFileName,
    ]) {
      final String path = _joinRelativePath(<String>[directoryPath, name]);
      if (!await root.exists(path)) continue;
      Object? metadata;
      try {
        metadata = jsonDecode(await root.readString(path));
      } on FormatException {
        throw FileSystemException('同名目录中的章节记录无法识别，已停止下载。', directoryPath);
      }
      final Set<String> expectedKeys = <String>{
        _pathKeyForUri(chapterHref),
        _pathKeyForUri(sourceUri),
      }..remove('');
      final Set<String> storedKeys = metadata is Map
          ? <String>{
              _pathKeyForUri(_stringValue(metadata['chapterHref'])),
              _pathKeyForUri(_stringValue(metadata['sourceUri'])),
            }
          : <String>{};
      storedKeys.remove('');
      if (storedKeys.isEmpty || !storedKeys.every(expectedKeys.contains)) {
        throw FileSystemException('同名目录已有其他章节或无法识别的文件，已停止下载。', directoryPath);
      }
      return;
    }
    if ((await root.listEntries(directoryPath, recursive: false)).isNotEmpty) {
      throw FileSystemException('同名目录已有无法识别的文件，已停止下载。', directoryPath);
    }
  }
}
