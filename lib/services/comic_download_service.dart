import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

typedef ChapterDownloadProgressCallback =
    Future<void> Function(ChapterDownloadProgress progress);

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
  }) : _client = client ?? http.Client(),
       _baseDirectoryProvider =
           baseDirectoryProvider ?? _defaultBaseDirectoryProvider;

  static final ComicDownloadService instance = ComicDownloadService();

  final http.Client _client;
  final Future<Directory> Function() _baseDirectoryProvider;

  Future<ChapterDownloadResult> downloadChapter(
    ReaderPageData page, {
    String cookieHeader = '',
    String? comicUri,
    String? chapterHref,
    String? chapterLabel,
    String? coverUrl,
    ChapterDownloadProgressCallback? onProgress,
  }) async {
    if (page.imageUrls.isEmpty) {
      throw FileSystemException('当前章节没有可下载图片。');
    }

    final Directory rootDirectory = await _downloadsRootDirectory();
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
    final Directory chapterDirectory = Directory(
      _joinPath(<String>[
        rootDirectory.path,
        _sanitizePathSegment(page.comicTitle),
        _sanitizePathSegment(resolvedChapterLabel),
      ]),
    );
    await chapterDirectory.create(recursive: true);

    final List<String> savedFiles = <String>[];
    final Map<String, String> headers = <String, String>{
      'User-Agent': AppConfig.desktopUserAgent,
      'Referer': page.uri,
      if (cookieHeader.trim().isNotEmpty) 'Cookie': cookieHeader.trim(),
    };

    for (int index = 0; index < page.imageUrls.length; index += 1) {
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
      final File imageFile = File(
        _joinPath(<String>[chapterDirectory.path, fileName]),
      );
      await imageFile.writeAsBytes(response.bodyBytes, flush: true);
      savedFiles.add(fileName);

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

    final File manifestFile = File(
      _joinPath(<String>[chapterDirectory.path, 'manifest.json']),
    );
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'comicTitle': page.comicTitle,
        'comicUri': resolvedComicUri,
        'coverUrl': coverUrl ?? '',
        'chapterTitle': page.chapterTitle,
        'chapterLabel': resolvedChapterLabel,
        'chapterHref': resolvedChapterHref,
        'progressLabel': page.progressLabel,
        'sourceUri': page.uri,
        'downloadedAt': DateTime.now().toIso8601String(),
        'imageCount': savedFiles.length,
        'files': savedFiles,
      }),
      flush: true,
    );

    return ChapterDownloadResult(
      directory: chapterDirectory,
      fileCount: savedFiles.length,
      manifestFile: manifestFile,
    );
  }

  Future<List<CachedComicLibraryEntry>> loadCachedLibrary() async {
    final Directory rootDirectory = await _downloadsRootDirectory();
    if (!await rootDirectory.exists()) {
      return const <CachedComicLibraryEntry>[];
    }

    final List<Map<String, Object?>> manifests = <Map<String, Object?>>[];
    await for (final FileSystemEntity entity in rootDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          !entity.path.endsWith('${Platform.pathSeparator}manifest.json')) {
        continue;
      }
      try {
        final Object? decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) {
          continue;
        }
        manifests.add(<String, Object?>{
          ...decoded.map(
            (Object? key, Object? value) => MapEntry(key.toString(), value),
          ),
          '__directoryPath': entity.parent.path,
        });
      } catch (_) {
        continue;
      }
    }

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
          ..sort((CachedComicLibraryEntry left, CachedComicLibraryEntry right) {
            final DateTime leftTime =
                left.lastDownloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime rightTime =
                right.lastDownloadedAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return rightTime.compareTo(leftTime);
          });

    return comics;
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

  Future<Directory> _downloadsRootDirectory() async {
    final Directory baseDirectory = await _baseDirectoryProvider();
    final Directory root = Directory(
      _joinPath(<String>[baseDirectory.path, 'EasyCopyDownloads']),
    );
    await root.create(recursive: true);
    return root;
  }

  static Future<Directory> _defaultBaseDirectoryProvider() async {
    if (Platform.isAndroid) {
      return (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    return await getApplicationDocumentsDirectory();
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

  String _joinPath(List<String> segments) {
    return segments.join(Platform.pathSeparator);
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
}
