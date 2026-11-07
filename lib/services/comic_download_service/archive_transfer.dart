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
        (await _findCachedChapter(chapterUri))?.directoryPath;
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
    final Directory temporary = await Directory.systemTemp.createTemp(
      'easycopy-import-',
    );
    final String id =
        'imported-${DateTime.now().microsecondsSinceEpoch}-${temporary.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    final String comicUri = localComicUri(id);
    final String coverUri = localChapterUri(id, 1);
    _ResolvedStorageRoot? root;
    String? storageKey;
    final List<CachedChapterEntry> chapters = <CachedChapterEntry>[];
    try {
      final List<ComicArchiveChapterFiles> extracted =
          await ComicArchive.extract(
            archivePath,
            preview,
            temporary.path,
            onProgress: (done, total) => onProgress?.call(done, total * 2),
            isCancelled: isCancelled,
          );
      final DownloadStorageState state = await resolveStorageState();
      root = await _resolveStorageRootFromState(state);
      storageKey = _storageService.storageKeyForState(state);
      final List<CachedComicLibraryEntry> library = await loadCachedLibrary();
      final DateTime importedAt = DateTime.now();
      final Map<String, String> manifests = <String, String>{};
      int completed = preview.imageCount;
      for (int index = 0; index < extracted.length; index++) {
        final ComicArchiveChapterFiles chapter = extracted[index];
        final String directory =
            '$id/${(index + 1).toString().padLeft(3, '0')}';
        final String chapterUri = localChapterUri(id, index + 1);
        final List<String> files = <String>[];
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
          await root.writeBytes('$directory/$name', bytes);
          files.add(name);
          onProgress?.call(++completed, preview.imageCount * 2);
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
      for (final MapEntry<String, String> manifest in manifests.entries) {
        await root.writeString(manifest.key, manifest.value);
      }
      final CachedComicLibraryEntry comic = CachedComicLibraryEntry(
        comicTitle: preview.title,
        comicHref: comicUri,
        coverUrl: coverUri,
        chapters: chapters,
      );
      await _replaceCachedChapterLocators(
        storageKey: storageKey,
        comics: <CachedComicLibraryEntry>[comic, ...library],
      );
      await _writeCachedLibraryIndex(storageKey, <CachedComicLibraryEntry>[
        comic,
        ...library,
      ]);
      return comic;
    } catch (_) {
      if (root != null) await root.deletePath(id);
      if (storageKey != null) {
        await _cachedChapterLocatorStore.removeDirectoryPaths(
          storageKey: storageKey,
          directoryPaths: chapters.map((chapter) => chapter.directoryPath),
        );
      }
      rethrow;
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
    for (final CachedChapterEntry chapter in comic.chapters) {
      _checkArchiveCancelled(isCancelled);
      final Map<String, Object?>? manifest = await _readCachedChapterManifest(
        root,
        chapter.directoryPath,
      );
      _archiveManifestFiles(manifest);
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
    final Directory temporary = await Directory.systemTemp.createTemp(
      'easycopy-export-',
    );
    try {
      final int imageCount = manifests.values.fold(
        0,
        (count, manifest) => count + (manifest['files'] as List).length,
      );
      final bool needsCopy = root is! _FileStorageRoot;
      int copied = 0;
      final List<ComicArchiveChapterFiles> chapters =
          <ComicArchiveChapterFiles>[];
      for (int index = 0; index < ordered.length; index++) {
        final CachedChapterEntry chapter = ordered[index];
        final List<String> files = <String>[];
        for (final String name in _archiveManifestFiles(manifests[chapter])) {
          _checkArchiveCancelled(isCancelled);
          final String relative = '${chapter.directoryPath}/$name';
          if (root is _FileStorageRoot) {
            files.add(root._absolutePath(relative));
          } else {
            final File target = File('${temporary.path}/$index/$name');
            await target.parent.create(recursive: true);
            await target.writeAsBytes(await root.readBytes(relative));
            files.add(target.path);
            onProgress?.call(++copied, imageCount * 2);
          }
        }
        chapters.add(ComicArchiveChapterFiles(chapter.chapterTitle, files));
      }
      await ComicArchive.encode(
        chapters,
        outputPath,
        onProgress: (done, total) =>
            onProgress?.call(done + copied, needsCopy ? total * 2 : total),
        isCancelled: isCancelled,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}

void _checkArchiveCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const ComicArchiveCancelled();
}

List<String> _archiveManifestFiles(Map<String, Object?>? manifest) {
  final Object? raw = manifest?['files'];
  if (raw is! List ||
      raw.isEmpty ||
      manifest?['imageCount'] != raw.length ||
      raw.any((file) => file is! String || !_isCacheFileName(file))) {
    throw const FormatException('章节缓存不完整');
  }
  return raw.cast<String>();
}

List<CachedChapterEntry> _archiveChapterOrder(
  Map<CachedChapterEntry, Map<String, Object?>> manifests,
) {
  final List<CachedChapterEntry> remaining = manifests.keys.toList()
    ..sort(
      (a, b) => comicArchiveNaturalCompare(a.chapterTitle, b.chapterTitle),
    );
  final Map<String, CachedChapterEntry> byPath = <String, CachedChapterEntry>{
    for (final CachedChapterEntry chapter in remaining)
      UriKeys.pathKey(chapter.chapterHref): chapter,
  };
  final Map<CachedChapterEntry, Set<CachedChapterEntry>> predecessors =
      <CachedChapterEntry, Set<CachedChapterEntry>>{
        for (final CachedChapterEntry chapter in remaining)
          chapter: <CachedChapterEntry>{},
      };
  for (final CachedChapterEntry chapter in remaining) {
    final Map<String, Object?> manifest = manifests[chapter]!;
    final CachedChapterEntry? prev =
        byPath[UriKeys.pathKey(manifest['prevHref']?.toString() ?? '')];
    final CachedChapterEntry? next =
        byPath[UriKeys.pathKey(manifest['nextHref']?.toString() ?? '')];
    if (prev != null && prev != chapter) predecessors[chapter]!.add(prev);
    if (next != null && next != chapter) predecessors[next]!.add(chapter);
  }
  final List<CachedChapterEntry> ordered = <CachedChapterEntry>[];
  while (remaining.isNotEmpty) {
    final CachedChapterEntry chapter = remaining.firstWhere(
      (chapter) => predecessors[chapter]!.isEmpty,
      orElse: () => remaining.first,
    );
    remaining.remove(chapter);
    ordered.add(chapter);
    for (final Set<CachedChapterEntry> parents in predecessors.values) {
      parents.remove(chapter);
    }
  }
  return ordered;
}
