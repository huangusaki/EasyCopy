part of '../comic_download_service.dart';

extension _DownloadPathUtils on ComicDownloadService {
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

  Future<void> _markOwnedComicDirectory(
    _ResolvedStorageRoot root,
    String comicDirectoryPath, {
    required bool existedBefore,
  }) async {
    if (comicDirectoryPath.trim().isEmpty || existedBefore) {
      return;
    }
    final String markerPath = _joinRelativePath(<String>[
      comicDirectoryPath,
      _comicOwnershipMarkerName,
    ]);
    try {
      if (await root.exists(markerPath)) {
        return;
      }
      await root.writeString(markerPath, 'easy_copy_owned');
    } catch (_) {
      return;
    }
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

  String _preferredStartHref(
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
}
