part of '../comic_download_service.dart';

extension ComicCacheDetailsOps on ComicDownloadService {
  Future<bool> upsertCachedComicDetailSnapshot(
    DetailPageData page,
  ) => _indexOperations.run(() async {
    final CachedComicDetailSnapshot snapshot = page.toCachedDetailSnapshot();
    if (snapshot.isEmpty) {
      return false;
    }
    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: false,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final List<CachedComicLibraryEntry> library =
        await _loadCachedLibraryForState(storageState);
    if (library.isEmpty) {
      return false;
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
      return false;
    }

    final CachedComicLibraryEntry current = library[comicIndex];
    if (current.detailSnapshot != null &&
        jsonEncode(current.detailSnapshot!.toJson()) ==
            jsonEncode(snapshot.toJson()) &&
        (page.title.isEmpty || current.comicTitle == page.title) &&
        (page.uri.isEmpty || current.comicHref == page.uri) &&
        (page.coverUrl.isEmpty || current.coverUrl == page.coverUrl)) {
      return false;
    }
    final next = library.toList();
    next[comicIndex] = current.copyWith(
      comicTitle: page.title.isEmpty ? current.comicTitle : page.title,
      comicHref: page.uri.isEmpty ? current.comicHref : page.uri,
      coverUrl: page.coverUrl.isEmpty ? current.coverUrl : page.coverUrl,
      detailSnapshot: snapshot,
    );
    await _writeCachedLibraryIndex(storageKey, next);
    return true;
  });

  DetailPageData buildCachedDetailPage(CachedComicLibraryEntry entry) {
    final List<ChapterData> chapters = entry.chapters
        .map((CachedChapterEntry chapter) {
          final String chapterHref = chapter.chapterHref.isNotEmpty
              ? chapter.chapterHref
              : chapter.sourceUri;
          return ChapterData(label: chapter.chapterTitle, href: chapterHref);
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
      updatedAt: snapshot?.updatedAt ?? '',
      status: isLocalComic(entry.comicHref)
          ? '本地漫画'
          : snapshot?.status ?? '已缓存',
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
    bool forDownload = false,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final DownloadStorageState storageState = await resolveStorageState(
        verifyWritable: false,
      );
      final String storageKey = _storageService.storageKeyForState(
        storageState,
      );
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
        entry = await _findCachedChapter(chapterHref, storageState);
      }
      if (entry == null || entry.directoryPath.isEmpty) {
        return null;
      }

      final Stopwatch manifestStopwatch = Stopwatch()..start();
      Map<String, Object?>? manifest = await _readCachedChapterManifest(
        root,
        entry.directoryPath,
      );
      if (manifest == null) {
        if (locator != null) {
          await _cachedChapterLocatorStore.removeDirectoryPaths(
            storageKey: storageKey,
            directoryPaths: <String>[entry.directoryPath],
          );
          locator = null;
        }
        entry = await _findCachedChapter(
          chapterHref,
          storageState,
          forceRescan: true,
        );
        if (entry == null || entry.directoryPath.isEmpty) {
          return null;
        }
        manifest = await _readCachedChapterManifest(root, entry.directoryPath);
        if (manifest == null) {
          return null;
        }
      }
      if (_pathKeyForUri(_stringValue(manifest['chapterHref'])) !=
              targetPathKey &&
          _pathKeyForUri(_stringValue(manifest['sourceUri'])) !=
              targetPathKey) {
        return null;
      }
      final List<String>? fileNames = _manifestImageFiles(manifest);
      if (fileNames == null) return null;
      final List<String> sourceImageUrls = forDownload
          ? ((manifest['sourceImageUrls'] as List<Object?>?) ??
                    const <Object?>[])
                .whereType<String>()
                .toList(growable: false)
          : const <String>[];
      final bool hasDownloadSources =
          sourceImageUrls.isNotEmpty &&
          sourceImageUrls.length == fileNames.length &&
          sourceImageUrls.every((String url) {
            final Uri? uri = Uri.tryParse(url);
            return uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host.isNotEmpty;
          });
      if (!hasDownloadSources) {
        final Set<String> existingFiles =
            (await root.listEntries(
                  entry.directoryPath,
                  recursive: false,
                  includeSize: true,
                ))
                .where(
                  (DocumentTreeEntry file) =>
                      !file.isDirectory && file.size > 0,
                )
                .map((DocumentTreeEntry file) => file.name)
                .toSet();
        if (!fileNames.every(existingFiles.contains)) {
          return null;
        }
      }
      final Stopwatch imageRefStopwatch = Stopwatch()..start();
      final List<String> imageUrls = hasDownloadSources
          ? sourceImageUrls
          : root.buildReaderImageUrls(entry.directoryPath, fileNames);
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
      final CachedChapterLocator resolvedLocator = _locatorForChapter(
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
      // Library fallback may already have rebuilt the missing locator.
      locator ??= await _cachedChapterLocatorStore.findByPathKey(
        storageKey: storageKey,
        targetPathKey: targetPathKey,
      );
      if (locator == null ||
          locator.chapterPathKey != resolvedLocator.chapterPathKey ||
          locator.sourcePathKey != resolvedLocator.sourcePathKey ||
          locator.directoryPath != resolvedLocator.directoryPath ||
          locator.comicTitle != resolvedLocator.comicTitle ||
          locator.chapterTitle != resolvedLocator.chapterTitle ||
          locator.downloadedAt != resolvedLocator.downloadedAt) {
        await _cachedChapterLocatorStore.upsert(resolvedLocator);
      }

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

  Future<void> deleteCachedComic(CachedComicLibraryEntry entry) =>
      deleteComicCache(
        comicTitle: entry.comicTitle,
        comicHref: _cachedComicDetailUri(entry),
        chapterDirectoryPaths: entry.chapters.map(
          (CachedChapterEntry chapter) => chapter.directoryPath,
        ),
      );

  Future<Map<String, Object?>?> _readCachedChapterManifest(
    _ResolvedStorageRoot root,
    String directoryPath,
  ) async {
    final String manifestRelativePath = _joinRelativePath(<String>[
      directoryPath,
      'manifest.json',
    ]);
    try {
      final decoded = jsonDecode(await root.readString(manifestRelativePath));
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      if (!await root.exists(manifestRelativePath)) return null;
      rethrow;
    }
  }

  Future<CachedChapterEntry?> _findCachedChapter(
    String chapterHref,
    DownloadStorageState state, {
    bool forceRescan = false,
  }) async {
    final String targetPathKey = _pathKeyForUri(chapterHref);
    if (targetPathKey.isEmpty) {
      return null;
    }
    final library = await _indexOperations.run(
      () => _loadCachedLibraryForState(state, forceRescan: forceRescan),
    );
    final current = identical(library, _library);
    final lookup =
        (current ? _chaptersByPath : null) ??
        {
          for (final comic in library.reversed)
            for (final chapter in comic.chapters.reversed)
              for (final href in [chapter.chapterHref, chapter.sourceUri])
                if (href.isNotEmpty) _pathKeyForUri(href): chapter,
        };
    if (current) _chaptersByPath = lookup;
    return lookup[targetPathKey];
  }

  Future<void> deleteComicCache({
    required String comicTitle,
    required String comicHref,
    Iterable<String> chapterDirectoryPaths = const <String>[],
  }) async {
    final String comicKey = _comicKeyForUri(comicHref);
    if (comicKey.isEmpty) return;
    final DownloadStorageState storageState = await resolveStorageState(
      verifyWritable: false,
    );
    final String storageKey = _storageService.storageKeyForState(storageState);
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(
      storageState,
    );
    final Set<String> comicDirectories = <String>{
      _sanitizePathSegment(comicTitle),
      ...chapterDirectoryPaths.map(_parentRelativePath),
    }.where(_isCacheFileName).toSet();
    final Set<String> deletedChapterDirectories = <String>{};
    try {
      for (final String comicDirectory in comicDirectories) {
        final entries = await root.listEntries(
          comicDirectory,
          recursive: true,
          includeSize: false,
        );
        final paths = await _cacheFilePaths(
          root,
          relativePath: comicDirectory,
          comicKey: comicKey,
          listedEntries: entries,
        );
        if (paths.isEmpty) continue;
        final existingFiles = {
          for (final entry in entries)
            if (!entry.isDirectory) entry.relativePath,
        };
        final Set<String> chapterDirectories = <String>{};
        for (final String path in paths) {
          if (!existingFiles.contains(path)) continue;
          if (await root.deletePath(path)) {
            final String chapterDirectory = _parentRelativePath(path);
            chapterDirectories.add(chapterDirectory);
            deletedChapterDirectories.add(chapterDirectory);
          }
        }
        for (final String chapterDirectory in chapterDirectories) {
          if ((await root.listEntries(
            chapterDirectory,
            recursive: false,
          )).isEmpty) {
            await root.deletePath(chapterDirectory);
          }
        }
        if ((await root.listEntries(
          comicDirectory,
          recursive: false,
        )).isEmpty) {
          await root.deletePath(comicDirectory);
        }
      }
    } finally {
      if (deletedChapterDirectories.isNotEmpty) {
        await _removeChaptersFromIndex(
          storageKey: storageKey,
          chapterDirectoryPaths: deletedChapterDirectories,
        );
      }
    }
  }

  Future<void> cleanupIncompleteChapter({
    required String comicTitle,
    required String chapterLabel,
    required String chapterHref,
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
    final bool hasManifest = await root.exists(manifestRelativePath);
    final String identityPath = hasManifest
        ? manifestRelativePath
        : _joinRelativePath(<String>[
            chapterDirectoryPath,
            _downloadIdentityFileName,
          ]);
    if (!await root.exists(identityPath)) return;
    Object? identity;
    try {
      identity = jsonDecode(await root.readString(identityPath));
    } on FormatException {
      return;
    }
    final String targetKey = _pathKeyForUri(chapterHref);
    if (identity is! Map ||
        targetKey.isEmpty ||
        (_pathKeyForUri(_stringValue(identity['chapterHref'])) != targetKey &&
            _pathKeyForUri(_stringValue(identity['sourceUri'])) != targetKey)) {
      return;
    }
    final int imageCount = (identity['imageCount'] as num?)?.toInt() ?? 0;
    if (imageCount <= 0) return;
    final List<DocumentTreeEntry> entries = await root.listEntries(
      chapterDirectoryPath,
      recursive: false,
    );
    final partSuffix = RegExp(r'(?:\.\d+)?\.part$', caseSensitive: false);
    for (final DocumentTreeEntry entry in entries) {
      if (entry.isDirectory || (hasManifest && !entry.name.endsWith('.part'))) {
        continue;
      }
      final name = entry.name.replaceFirst(partSuffix, '');
      final match = _numberedCacheImagePattern.firstMatch(name);
      if (match == null ||
          !comicImageExtensions.contains(match[2]!.toLowerCase())) {
        continue;
      }
      final int index = int.tryParse(match.group(1)!) ?? 0;
      if (index <= 0 || index > imageCount) continue;
      await root.deletePath(entry.relativePath);
    }
    if (!hasManifest) {
      await root.deletePath(identityPath);
      if ((await root.listEntries(
        chapterDirectoryPath,
        recursive: false,
      )).isEmpty) {
        await root.deletePath(chapterDirectoryPath);
      }
      await _removeChaptersFromIndex(
        storageKey: storageKey,
        chapterDirectoryPaths: <String>{chapterDirectoryPath},
      );
    }
  }

  Future<void> cleanupIncompleteTasks(Iterable<DownloadQueueTask> tasks) async {
    final Set<String> cleanedKeys = <String>{};
    for (final DownloadQueueTask task in tasks) {
      final String key =
          '${task.comicTitle}::${task.chapterLabel}::${_pathKeyForUri(task.chapterHref)}';
      if (!cleanedKeys.add(key)) {
        continue;
      }
      await cleanupIncompleteChapter(
        comicTitle: task.comicTitle,
        chapterLabel: task.chapterLabel,
        chapterHref: task.chapterHref,
      );
    }
  }
}
