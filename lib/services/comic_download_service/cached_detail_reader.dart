part of '../comic_download_service.dart';

extension ComicCacheDetailsOps on ComicDownloadService {
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
    final String fallbackStartReadingHref = _preferredStartHref(
      chapters,
      preferredHref: snapshot?.startReadingHref ?? '',
    );
    return DetailPageData(
      title: entry.comicTitle,
      uri: detailUri,
      coverUrl: entry.coverUrl,
      aliases: snapshot?.aliases ?? '',
      authors: snapshot?.authors ?? '',
      authorLinks: snapshot?.authorLinks ?? const <LinkAction>[],
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
      await _removeComicFromIndex(
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
      await _removeComicFromIndex(
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
      await _removeChapterFromIndex(
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
}
