part of '../comic_download_service.dart';

extension ComicArchiveTransfer on ComicDownloadService {
  Future<Uint8List> loadLocalCoverBytes(String chapterUri) async {
    final DownloadStorageState state = await resolveStorageState(
      verifyWritable: false,
    );
    final CachedChapterLocator? locator = await _cachedChapterLocatorStore
        .findByPathKey(
          storageKey: _storageService.storageKeyForState(state),
          targetPathKey: _pathKeyForUri(chapterUri),
        );
    final String? directory =
        locator?.directoryPath ??
        (await _findCachedChapter(chapterUri, state))?.directoryPath;
    if (directory == null) throw const FileSystemException('本地封面不存在');
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(state);
    final Map<String, Object?>? manifest = await _readCachedChapterManifest(
      root,
      directory,
    );
    final List<String> files = _archiveManifestFiles(manifest);
    return root.readBytes('$directory/${files.first}');
  }

  Future<CachedComicLibraryEntry> importComicArchive(
    String archivePath,
    ComicArchivePreview preview, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final state = await resolveStorageState();
    final root = await _resolveStorageRootFromState(state);
    final storageKey = _storageService.storageKeyForState(state);
    await _indexOperations.run(() => _loadCachedLibraryForState(state));
    final stagingRoot = root is _FileStorageRoot
        ? root.rootDirectory
        : Directory.systemTemp;
    final temporary = await stagingRoot.createTemp('.easycopy-import-');
    final id =
        'imported-${DateTime.now().microsecondsSinceEpoch}-${temporary.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    final comicUri = localComicUri(id);
    final coverUri = localChapterUri(id, 1);
    final List<CachedChapterEntry> chapters = <CachedChapterEntry>[];
    final manifests = <String, String>{};
    try {
      try {
        final List<ComicArchiveChapterFiles> extracted =
            await ComicArchive.extract(
              archivePath,
              preview,
              temporary.path,
              onProgress: onProgress == null
                  ? null
                  : (done, total) => onProgress(done, total * 2),
              isCancelled: isCancelled,
            );
        final DateTime importedAt = DateTime.now();
        final imageCount = preview.imageCount;
        int completed = imageCount;
        for (int index = 0; index < extracted.length; index++) {
          final ComicArchiveChapterFiles chapter = extracted[index];
          final String directory =
              '$id/${(index + 1).toString().padLeft(3, '0')}';
          final String chapterUri = localChapterUri(id, index + 1);
          final List<String> files = <String>[];
          if (root is _FileStorageRoot) {
            await Directory(
              root._absolutePath(directory),
            ).create(recursive: true);
          }
          for (final String path in chapter.files) {
            _checkArchiveCancelled(isCancelled);
            final File source = File(path);
            final Uint8List bytes = await source.readAsBytes();
            if (!await isCompleteImage(bytes)) {
              throw FormatException(
                '图片无法读取：${chapter.title}/${source.uri.pathSegments.last}',
              );
            }
            _checkArchiveCancelled(isCancelled);
            final String name = source.uri.pathSegments.last;
            if (root is _FileStorageRoot) {
              final target = File(root._absolutePath('$directory/$name'));
              await source.rename(target.path);
            } else {
              await root.writeBytes('$directory/$name', bytes);
            }
            files.add(name);
            onProgress?.call(++completed, imageCount * 2);
          }
          chapters.add(
            CachedChapterEntry(
              chapterTitle: chapter.title,
              chapterHref: chapterUri,
              sourceUri: chapterUri,
              directoryPath: directory,
              downloadedAt: importedAt,
            ),
          );
          manifests['$directory/manifest.json'] = jsonEncode(<String, Object?>{
            'comicTitle': preview.title,
            'comicUri': comicUri,
            'coverUrl': coverUri,
            'chapterTitle': chapter.title,
            'chapterLabel': chapter.title,
            'chapterHref': chapterUri,
            'sourceUri': chapterUri,
            'catalogHref': comicUri,
            'prevHref': index == 0 ? '' : localChapterUri(id, index),
            'nextHref': index + 1 == extracted.length
                ? ''
                : localChapterUri(id, index + 2),
            'downloadedAt': importedAt.toIso8601String(),
            'imageCount': files.length,
            'files': files,
          });
        }
        _checkArchiveCancelled(isCancelled);
      } catch (_) {
        await root.deletePath(id);
        rethrow;
      }
      final CachedComicLibraryEntry comic = CachedComicLibraryEntry(
        comicTitle: preview.title,
        comicHref: comicUri,
        coverUrl: coverUri,
        chapters: chapters,
      );
      await _indexOperations.run(() async {
        try {
          for (final manifest in manifests.entries) {
            _checkArchiveCancelled(isCancelled);
            await root.writeString(manifest.key, manifest.value);
          }
          final library = await _readCachedLibraryIndex(storageKey);
          await _writeCachedLibraryIndex(storageKey, [
            comic,
            ...library.where((entry) => entry.comicHref != comicUri),
          ], locators: _locatorsFromLibrary(storageKey, [comic]));
        } catch (_) {
          // A queued rescan must never observe half-published manifests.
          await root.deletePath(id);
          rethrow;
        }
      });
      return comic;
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<void> exportComicArchive(
    CachedComicLibraryEntry comic,
    String outputPath, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final DownloadStorageState state = await resolveStorageState(
      verifyWritable: false,
    );
    final _ResolvedStorageRoot root = await _resolveStorageRootFromState(state);
    final Map<CachedChapterEntry, Map<String, Object?>> manifests =
        <CachedChapterEntry, Map<String, Object?>>{};
    final filesByChapter = <CachedChapterEntry, List<String>>{};
    for (final CachedChapterEntry chapter in comic.chapters) {
      _checkArchiveCancelled(isCancelled);
      final Map<String, Object?>? manifest = await _readCachedChapterManifest(
        root,
        chapter.directoryPath,
      );
      filesByChapter[chapter] = _archiveManifestFiles(manifest);
      final String chapterKey = _pathKeyForUri(
        chapter.chapterHref.isEmpty ? chapter.sourceUri : chapter.chapterHref,
      );
      if (_pathKeyForUri(_stringValue(manifest!['chapterHref'])) !=
              chapterKey &&
          _pathKeyForUri(_stringValue(manifest['sourceUri'])) != chapterKey) {
        throw const FormatException('章节缓存已变化，请刷新后重试');
      }
      manifests[chapter] = manifest;
    }
    final List<CachedChapterEntry> ordered = _archiveChapterOrder(manifests);
    final temporary = root is _DocumentTreeStorageRoot
        ? await Directory.systemTemp.createTemp('easycopy-export-')
        : null;
    try {
      final int imageCount = filesByChapter.values.fold(
        0,
        (count, files) => count + files.length,
      );
      final bool needsCopy = root is! _FileStorageRoot;
      int copied = 0;
      final List<ComicArchiveChapterFiles> chapters =
          <ComicArchiveChapterFiles>[];
      for (int index = 0; index < ordered.length; index++) {
        final CachedChapterEntry chapter = ordered[index];
        final List<String> files = <String>[];
        for (final String name in filesByChapter[chapter]!) {
          _checkArchiveCancelled(isCancelled);
          final String relative = '${chapter.directoryPath}/$name';
          if (root is _FileStorageRoot) {
            files.add(root._absolutePath(relative));
          } else if (root is _DocumentTreeStorageRoot) {
            final File target = File('${temporary!.path}/$index/$name');
            await root.bridge.stageFile(
              treeUri: root.treeUri,
              relativePath: root._resolveRelativePath(relative),
              destinationPath: target.path,
            );
            files.add(target.path);
            onProgress?.call(++copied, imageCount * 2);
          }
        }
        chapters.add(ComicArchiveChapterFiles(chapter.chapterTitle, files));
      }
      await ComicArchive.encode(
        chapters,
        outputPath,
        onProgress: onProgress == null
            ? null
            : (done, total) =>
                  onProgress(done + copied, needsCopy ? total * 2 : total),
        isCancelled: isCancelled,
      );
    } finally {
      await temporary?.delete(recursive: true);
    }
  }
}

void _checkArchiveCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const ComicArchiveCancelled();
}

List<String> _archiveManifestFiles(Map<String, Object?>? manifest) {
  return _manifestImageFiles(manifest) ??
      (throw const FormatException('章节缓存不完整'));
}

List<CachedChapterEntry> _archiveChapterOrder(
  Map<CachedChapterEntry, Map<String, Object?>> manifests,
) {
  final compare = comicArchiveNaturalComparator();
  final chapters = manifests.keys.toList()
    ..sort((a, b) => compare(a.chapterTitle, b.chapterTitle));
  final byPath = {
    for (var i = 0; i < chapters.length; i++)
      UriKeys.pathKey(chapters[i].chapterHref): i,
  };
  final outgoing = List.generate(chapters.length, (_) => <int>{});
  final indegree = List.filled(chapters.length, 0);
  void link(int? from, int? to) {
    if (from != null && to != null && from != to && outgoing[from].add(to)) {
      indegree[to]++;
    }
  }

  for (var i = 0; i < chapters.length; i++) {
    final manifest = manifests[chapters[i]]!;
    link(byPath[UriKeys.pathKey(manifest['prevHref']?.toString() ?? '')], i);
    link(i, byPath[UriKeys.pathKey(manifest['nextHref']?.toString() ?? '')]);
  }
  final remaining = SplayTreeSet<int>.from(Iterable.generate(chapters.length));
  final ready = SplayTreeSet<int>.from(
    remaining.where((i) => indegree[i] == 0),
  );
  final ordered = <CachedChapterEntry>[];
  while (remaining.isNotEmpty) {
    final i = ready.isEmpty ? remaining.first : ready.first;
    remaining.remove(i);
    ready.remove(i);
    ordered.add(chapters[i]);
    for (final next in outgoing[i]) {
      if (--indegree[next] == 0 && remaining.contains(next)) ready.add(next);
    }
  }
  return ordered;
}
