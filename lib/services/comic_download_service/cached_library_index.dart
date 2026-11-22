part of '../comic_download_service.dart';

extension ComicCacheLibraryOps on ComicDownloadService {
  Future<List<CachedComicLibraryEntry>> loadCachedLibrary({
    bool forceRescan = false,
  }) => _indexOperations.run(
    () async => _loadCachedLibraryForState(
      await resolveStorageState(verifyWritable: false),
      forceRescan: forceRescan,
    ),
  );

  Future<List<CachedComicLibraryEntry>> _loadCachedLibraryForState(
    DownloadStorageState storageState, {
    bool forceRescan = false,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final String storageKey = _storageService.storageKeyForState(
        storageState,
      );
      if (!forceRescan &&
          _libraryStorageKey == storageKey &&
          _library != null) {
        return _library!;
      }
      final (previousIndexedEntries, inDatabase) = await _readIndexRows(
        storageKey,
      );
      // The old SAF key omitted the selected relative root. Use it only for
      // metadata after scanning the actual root, never as an authoritative list.
      final String legacyKey = _storageService.legacyStorageKeyForState(
        storageState,
      );
      final List<Map<String, Object?>>? legacyEntries =
          previousIndexedEntries == null && legacyKey != storageKey
          ? (await _readIndexRows(legacyKey)).$1
          : null;
      final List<Map<String, Object?>>? indexedEntries = forceRescan
          ? null
          : previousIndexedEntries;
      if (indexedEntries != null) {
        final List<CachedComicLibraryEntry> indexedLibrary = indexedEntries
            .map(CachedComicLibraryEntry.fromJson)
            .toList(growable: false);
        if (!inDatabase && indexedLibrary.isNotEmpty) {
          if (!await _cachedChapterLocatorStore.hasEntriesForStorage(
            storageKey,
          )) {
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
        _rememberLibrary(storageKey, indexedLibrary, inDatabase: inDatabase);
        return _library!;
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
            (previousIndexedEntries ?? legacyEntries)
                ?.map(CachedComicLibraryEntry.fromJson)
                .toList(growable: false) ??
            const <CachedComicLibraryEntry>[],
      );
      await _writeCachedLibraryIndex(
        storageKey,
        comics,
        locators: _locatorsFromLibrary(storageKey, comics),
        replaceLocators: true,
      );
      DebugTrace.log('cached_library.rebuilt', <String, Object?>{
        'storageKey': storageKey,
        'forceRescan': forceRescan,
        'comicCount': comics.length,
        'comicDirCount': stats.comicDirectoryCount,
        'chapterDirCount': stats.chapterDirectoryCount,
        'manifestCount': stats.manifestCount,
        'listCalls': stats.listCalls,
        'readCalls': stats.readCalls,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      return _library!;
    } catch (error) {
      DebugTrace.log('cached_library.failed', <String, Object?>{
        'error': error.toString(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _loadLibraryManifests(
    _ResolvedStorageRoot root, {
    required _LibraryScanStats stats,
  }) async {
    final List<Map<String, Object?>> manifests = <Map<String, Object?>>[];
    stats.listCalls += 1;
    final List<DocumentTreeEntry> comicEntries = await root.listEntries(
      '',
      recursive: false,
      includeSize: false,
    );

    for (final DocumentTreeEntry comicEntry in comicEntries) {
      if (!comicEntry.isDirectory || comicEntry.relativePath.trim().isEmpty) {
        continue;
      }
      stats.comicDirectoryCount++;
      stats.listCalls += 1;
      final List<DocumentTreeEntry> chapterEntries = await root.listEntries(
        comicEntry.relativePath,
        recursive: false,
        includeSize: false,
      );
      for (final DocumentTreeEntry chapterEntry in chapterEntries) {
        if (!chapterEntry.isDirectory ||
            chapterEntry.relativePath.trim().isEmpty) {
          continue;
        }
        stats.chapterDirectoryCount++;
        final String manifestRelativePath = _joinRelativePath(<String>[
          chapterEntry.relativePath,
          'manifest.json',
        ]);
        try {
          stats.readCalls += 1;
          final Object? decoded = jsonDecode(
            await root.readString(manifestRelativePath),
          );
          if (decoded is! Map<String, dynamic>) continue;
          manifests.add({
            for (final key in const [
              'sourceUri',
              'comicUri',
              'comicTitle',
              'coverUrl',
              'chapterHref',
              'chapterLabel',
              'chapterTitle',
              'downloadedAt',
            ])
              key: decoded[key],
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
    final compare = comicArchiveNaturalComparator();
    return grouped.entries
        .map((MapEntry<String, List<CachedChapterEntry>> entry) {
          final List<CachedChapterEntry> chapters =
              entry.value.toList(growable: false)..sort(
                (CachedChapterEntry left, CachedChapterEntry right) =>
                    isLocalComic(comicHrefs[entry.key] ?? '')
                    ? compare(left.chapterHref, right.chapterHref)
                    : right.downloadedAt.compareTo(left.downloadedAt),
              );
          final CachedComicLibraryEntry? previousEntry =
              previousEntriesByKey[entry.key];
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
    return _cachedChapterLocatorStore.writeLocators(
      storageKey,
      _locatorsFromLibrary(storageKey, comics),
      replace: true,
    );
  }

  Future<void> _upsertCachedChapterIndex({
    required DownloadStorageState storageState,
    required String comicTitle,
    required String comicHref,
    required String coverUrl,
    CachedComicDetailSnapshot? detailSnapshot,
    required CachedChapterEntry chapter,
  }) => _indexOperations.run(() async {
    final storageKey = _storageService.storageKeyForState(storageState);
    final List<CachedComicLibraryEntry> comics =
        (await _loadCachedLibraryForState(storageState)).toList();
    final String targetComicKey = _comicKeyForUri(comicHref);
    final int comicIndex = comics.indexWhere(
      (CachedComicLibraryEntry entry) =>
          targetComicKey.isNotEmpty &&
          _comicKeyForUri(entry.comicHref) == targetComicKey,
    );
    final CachedComicLibraryEntry? comic = comicIndex >= 0
        ? comics[comicIndex]
        : null;
    final List<CachedChapterEntry> chapters =
        (comic?.chapters ?? const <CachedChapterEntry>[]).toList(
          growable: true,
        );
    final int chapterIndex = chapters.indexWhere(
      (CachedChapterEntry entry) =>
          entry.directoryPath == chapter.directoryPath,
    );
    if (chapterIndex >= 0) chapters.removeAt(chapterIndex);
    _insertNewestFirst(
      chapters,
      chapter,
      (entry) => entry.downloadedAt.microsecondsSinceEpoch,
    );
    final CachedComicLibraryEntry nextComic = CachedComicLibraryEntry(
      comicTitle: comicTitle,
      comicHref: comicHref,
      coverUrl: coverUrl,
      chapters: chapters,
      detailSnapshot: detailSnapshot ?? comic?.detailSnapshot,
    );
    if (comicIndex >= 0) comics.removeAt(comicIndex);
    _insertNewestFirst(
      comics,
      nextComic,
      (entry) => entry.lastDownloadedAt?.microsecondsSinceEpoch ?? 0,
    );
    await _writeCachedLibraryIndex(
      storageKey,
      comics,
      locators: [
        _locatorForChapter(
          storageKey: storageKey,
          comicTitle: comicTitle,
          chapter: chapter,
        ),
      ],
    );
  });

  Future<void> _removeChaptersFromIndex({
    required String storageKey,
    required Set<String> chapterDirectoryPaths,
  }) => _indexOperations.run(() async {
    final List<CachedComicLibraryEntry> comics = await _readCachedLibraryIndex(
      storageKey,
    );
    final List<CachedComicLibraryEntry> nextComics =
        <CachedComicLibraryEntry>[];
    for (final CachedComicLibraryEntry comic in comics) {
      final List<CachedChapterEntry> chapters = comic.chapters
          .where(
            (CachedChapterEntry chapter) =>
                !chapterDirectoryPaths.contains(chapter.directoryPath),
          )
          .toList(growable: false);
      if (chapters.length == comic.chapters.length) {
        nextComics.add(comic);
        continue;
      }
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
    if (comics.isNotEmpty) {
      await _writeCachedLibraryIndex(
        storageKey,
        nextComics,
        removedLocatorPaths: chapterDirectoryPaths,
      );
      return;
    }
    await _cachedChapterLocatorStore.removeDirectoryPaths(
      storageKey: storageKey,
      directoryPaths: chapterDirectoryPaths,
    );
  });

  Future<List<CachedComicLibraryEntry>> _readCachedLibraryIndex(
    String storageKey,
  ) async {
    if (_libraryStorageKey == storageKey && _library != null) return _library!;
    final (rawEntries, inDatabase) = await _readIndexRows(storageKey);
    if (rawEntries == null) {
      return <CachedComicLibraryEntry>[];
    }
    _rememberLibrary(
      storageKey,
      rawEntries.map(CachedComicLibraryEntry.fromJson).toList(),
      inDatabase: inDatabase,
    );
    return _library!;
  }

  Future<List<CachedComicLibraryEntry>> _readCachedLibraryMetadata(
    DownloadStorageState state,
  ) async {
    final String key = _storageService.storageKeyForState(state);
    final List<CachedComicLibraryEntry> entries = await _readCachedLibraryIndex(
      key,
    );
    if (entries.isNotEmpty) return entries;
    final String legacyKey = _storageService.legacyStorageKeyForState(state);
    return legacyKey == key ? entries : _readCachedLibraryIndex(legacyKey);
  }

  Future<(List<Map<String, Object?>>?, bool)> _readIndexRows(
    String storageKey,
  ) async {
    final rows = await _cachedChapterLocatorStore.readLibrary(storageKey);
    if (rows != null) return (rows, true);
    return (await _cachedLibraryIndexStore.read(storageKey), false);
  }

  void _rememberLibrary(
    String key,
    List<CachedComicLibraryEntry> entries, {
    required bool inDatabase,
  }) {
    _libraryInDatabase = inDatabase;
    _libraryStorageKey = key;
    _library = List.unmodifiable(entries);
    _chaptersByPath = null;
  }

  Future<void> _writeCachedLibraryIndex(
    String storageKey,
    List<CachedComicLibraryEntry> comics, {
    Iterable<CachedChapterLocator> locators = const [],
    bool replaceLocators = false,
    Iterable<String> removedLocatorPaths = const [],
  }) async {
    // Preserve ordering separately so moving a newly downloaded comic to the
    // front never serializes the other comics and their chapters.
    final previous = _libraryStorageKey == storageKey ? _library : null;
    // Legacy files can have an empty or repeated href. Occurrence-qualified keys
    // preserve all rows and their order during the first incremental write.
    Map<String, CachedComicLibraryEntry> keyed(
      Iterable<CachedComicLibraryEntry> entries,
    ) {
      final counts = <String, int>{};
      return {
        for (final comic in entries)
          jsonEncode([
            comic.comicHref,
            counts.update(comic.comicHref, (n) => n + 1, ifAbsent: () => 0),
          ]): comic,
      };
    }

    final oldByKey = keyed(previous ?? const []);
    final orderedKeys = <String>[];
    final changed = <String, Map<String, Object?>>{};
    final containsSnapshot = previous != null && _libraryInDatabase;
    for (final entry in keyed(comics).entries) {
      final key = entry.key;
      final comic = entry.value;
      orderedKeys.add(key);
      final old = oldByKey.remove(key);
      if (!containsSnapshot || !identical(old, comic)) {
        changed[key] = comic.toJson();
      }
    }
    await _cachedChapterLocatorStore.writeLibrary(
      storageKey,
      orderedKeys,
      changed,
      removedKeys: oldByKey.keys,
      replace: previous == null,
      locators: locators,
      replaceLocators: replaceLocators,
      removedLocatorPaths: removedLocatorPaths,
    );
    _rememberLibrary(storageKey, comics, inDatabase: true);
  }
}

void _insertNewestFirst<T>(List<T> entries, T item, int Function(T) timestamp) {
  // Existing JSON may have a custom order. Restore it once using the same
  // ordering as a download, then insert by date on subsequent updates.
  for (var i = 1; i < entries.length; i++) {
    if (timestamp(entries[i - 1]) < timestamp(entries[i])) {
      entries.sort((a, b) => timestamp(b).compareTo(timestamp(a)));
      break;
    }
  }
  final time = timestamp(item);
  final position = entries.indexWhere((entry) => timestamp(entry) <= time);
  entries.insert(position < 0 ? entries.length : position, item);
}
