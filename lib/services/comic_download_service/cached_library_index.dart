part of '../comic_download_service.dart';

extension ComicCacheLibraryOps on ComicDownloadService {
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
      final List<CachedComicLibraryEntry> comics = _buildLibraryFromManifests(
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

  List<CachedComicLibraryEntry> _buildLibraryFromManifests(
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

  Future<void> _removeChapterFromIndex({
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

  Future<void> _removeComicFromIndex({
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

  Future<Set<String>> loadChapterPathKeys(String comicUri) async {
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
}
