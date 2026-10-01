part of '../comic_download_service.dart';

extension _DownloadStorageRoots on ComicDownloadService {
  Future<_ResolvedStorageRoot> _resolveStorageRootFromState(
    DownloadStorageState storageState,
  ) async {
    if (storageState.preferences.usesDocumentTree) {
      final String treeUri = storageState.preferences.customTreeUri.trim();
      if (treeUri.isEmpty) {
        throw const FileSystemException('缓存目录不可用。');
      }
      return _DocumentTreeStorageRoot(
        bridge: _documentTreeBridge,
        treeUri: treeUri,
        rootRelativePath: storageState.preferences.usePickedDirectoryAsRoot
            ? ''
            : DownloadStorageService.downloadsDirectoryName,
      );
    }
    final String rootPath = storageState.rootPath.trim();
    if (rootPath.isEmpty) {
      throw const FileSystemException('缓存目录不可用。');
    }
    return _FileStorageRoot(Directory(rootPath));
  }

  bool _sameStorageLocation(
    DownloadStorageState left,
    DownloadStorageState right,
  ) {
    return left.storageIdentity.isNotEmpty &&
        left.storageIdentity == right.storageIdentity;
  }

  bool _storageRootsOverlap(
    DownloadStorageState left,
    DownloadStorageState right,
  ) {
    if (left.isDocumentTree &&
        right.isDocumentTree &&
        left.documentTreeUri.isNotEmpty &&
        left.documentTreeUri == right.documentTreeUri &&
        left.preferences.usePickedDirectoryAsRoot !=
            right.preferences.usePickedDirectoryAsRoot) {
      return true;
    }
    final String leftRoot = _normalizedComparableRoot(left.comparablePath);
    final String rightRoot = _normalizedComparableRoot(right.comparablePath);
    if (leftRoot.isEmpty || rightRoot.isEmpty) {
      return false;
    }
    return _isNestedStoragePath(leftRoot, rightRoot) ||
        _isNestedStoragePath(rightRoot, leftRoot);
  }

  String _normalizedComparableRoot(String value) {
    String normalized = _normalizedPath(value);
    while (normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isNestedStoragePath(String candidate, String parent) {
    return candidate == parent ||
        candidate.startsWith('$parent${Platform.pathSeparator}');
  }

  Future<bool> _isChapterCompleted({
    required _ResolvedStorageRoot root,
    required String manifestRelativePath,
    required String chapterDirectoryPath,
    required int expectedImageCount,
  }) async {
    if (!await root.exists(manifestRelativePath)) {
      return false;
    }
    try {
      final Object? decoded = jsonDecode(
        await root.readString(manifestRelativePath),
      );
      if (decoded is! Map) {
        return false;
      }
      final int imageCount = (decoded['imageCount'] as num?)?.toInt() ?? 0;
      final Object? rawFiles = decoded['files'];
      if (rawFiles is! List ||
          rawFiles.length != expectedImageCount ||
          imageCount != expectedImageCount ||
          expectedImageCount <= 0) {
        return false;
      }
      final Set<String> seen = <String>{};
      for (final Object? value in rawFiles) {
        if (value is! String || !_isCacheFileName(value) || !seen.add(value)) {
          return false;
        }
        final Uint8List bytes = await root.readBytes(
          _joinRelativePath(<String>[chapterDirectoryPath, value]),
        );
        if (!await isCompleteImage(bytes)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<int, String>> _loadExistingImageFiles(
    _ResolvedStorageRoot root,
    String chapterDirectoryPath,
  ) async {
    if (!await root.exists(chapterDirectoryPath)) {
      return const <int, String>{};
    }

    final Map<int, String> existingFiles = <int, String>{};
    final RegExp pattern = RegExp(r'^(\d+)\.[^.]+$');
    for (final _StorageEntry entry in await root.listEntries(
      chapterDirectoryPath,
      recursive: false,
    )) {
      if (entry.isDirectory) {
        continue;
      }
      final String fileName = entry.name;
      final RegExpMatch? match = pattern.firstMatch(fileName);
      if (match == null) {
        continue;
      }
      if (entry.size <= 0) {
        continue;
      }
      try {
        if (!await isCompleteImage(await root.readBytes(entry.relativePath))) {
          continue;
        }
      } catch (_) {
        continue;
      }
      final int index = int.parse(match.group(1)!) - 1;
      existingFiles[index] = fileName;
    }
    return existingFiles;
  }

  void _throwIfPaused(ChapterDownloadPauseChecker? shouldPause) {
    if (shouldPause?.call() ?? false) {
      throw const DownloadPausedException();
    }
  }

  void _throwIfCancelled(ChapterDownloadCancelChecker? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const DownloadCancelledException();
    }
  }

  Future<int> _copyDirInIsolate(
    Directory source,
    Directory target, {
    required List<String> relativePaths,
    required bool verifyOnly,
  }) {
    return Isolate.run<int>(
      () => _copyFileSystemTreeSync(
        _FileSystemCopyRequest(
          sourcePath: source.path,
          targetPath: target.path,
          relativePaths: relativePaths,
          verifyOnly: verifyOnly,
        ),
      ),
    );
  }

  Future<List<String>> _cacheFilePaths(
    _ResolvedStorageRoot root, {
    String relativePath = '',
    String comicKey = '',
  }) async {
    final List<_StorageEntry> entries = await root.listEntries(
      relativePath,
      recursive: true,
    );
    final Set<String> paths = <String>{};
    for (final _StorageEntry entry in entries) {
      if (entry.isDirectory ||
          (entry.name != 'manifest.json' &&
              entry.name != _downloadIdentityFileName)) {
        continue;
      }
      final List<String> segments = entry.relativePath.split('/');
      if (segments.length != 3 ||
          segments.any(
            (String part) => part.isEmpty || part == '..' || part == '.',
          )) {
        continue;
      }
      Object? decoded;
      try {
        decoded = jsonDecode(await root.readString(entry.relativePath));
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final Object? rawFiles = decoded['files'];
      final Uri? source = Uri.tryParse(decoded['sourceUri']?.toString() ?? '');
      if (source == null ||
          !source.path.startsWith('/comic/') ||
          !source.path.contains('/chapter/')) {
        continue;
      }
      if (comicKey.isNotEmpty &&
          _comicKeyForUri(source.toString()) != comicKey) {
        continue;
      }
      final String directory = segments.take(segments.length - 1).join('/');
      if (entry.name == _downloadIdentityFileName) {
        final Object? rawCount = decoded['imageCount'];
        final int count = rawCount is num ? rawCount.toInt() : 0;
        final Uri? chapter = Uri.tryParse(
          decoded['chapterHref']?.toString() ?? '',
        );
        if (count <= 0 ||
            chapter == null ||
            !chapter.path.startsWith('/comic/') ||
            !chapter.path.contains('/chapter/')) {
          continue;
        }
        final Map<int, String> images = await _loadExistingImageFiles(
          root,
          directory,
        );
        paths.addAll(
          images.entries
              .where(
                (MapEntry<int, String> image) =>
                    image.key >= 0 && image.key < count,
              )
              .map(
                (MapEntry<int, String> image) => '$directory/${image.value}',
              ),
        );
        paths.add(entry.relativePath);
        continue;
      }
      if ((decoded['comicTitle']?.toString().trim() ?? '').isEmpty ||
          rawFiles is! List ||
          rawFiles.isEmpty ||
          decoded['imageCount'] != rawFiles.length ||
          rawFiles.any(
            (Object? name) => name is! String || !_isNumberedCacheImage(name),
          )) {
        continue;
      }
      final List<String> files = rawFiles.cast<String>();
      if (files.toSet().length != files.length) continue;
      paths.addAll(files.map((String name) => '$directory/$name'));
      paths.add(entry.relativePath);
    }
    return paths.toList(growable: false);
  }

  Future<void> _migrateStorageContents(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot, {
    required List<String> relativePaths,
    bool verifyOnly = false,
    required _MigrationProgressController progressController,
  }) async {
    if (sourceRoot is _FileStorageRoot && targetRoot is _FileStorageRoot) {
      await progressController.startMigrating();
      final int copiedFiles = await _copyDirInIsolate(
        sourceRoot.rootDirectory,
        targetRoot.rootDirectory,
        relativePaths: relativePaths,
        verifyOnly: verifyOnly,
      );
      await progressController.syncMigrating(
        completedItems: copiedFiles,
        totalItems: copiedFiles,
      );
      return;
    }
    if (sourceRoot is _FileStorageRoot &&
        targetRoot is _DocumentTreeStorageRoot) {
      await progressController.startMigrating();
      await targetRoot.importFromDirectory(
        sourceRoot.rootDirectory,
        relativePaths: relativePaths,
        verifyOnly: verifyOnly,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
    if (sourceRoot is _DocumentTreeStorageRoot &&
        targetRoot is _FileStorageRoot) {
      await progressController.startMigrating();
      await sourceRoot.exportToDirectory(
        targetRoot.rootDirectory,
        relativePaths: relativePaths,
        verifyOnly: verifyOnly,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
    if (sourceRoot is _DocumentTreeStorageRoot &&
        targetRoot is _DocumentTreeStorageRoot) {
      await progressController.startMigrating();
      await sourceRoot.copyToDocumentTree(
        targetRoot,
        relativePaths: relativePaths,
        verifyOnly: verifyOnly,
        onProgress: (DocumentTreeTransferProgress progress) {
          return progressController.syncMigrating(
            completedItems: progress.completedCount,
            totalItems: progress.totalCount,
            currentItemPath: progress.currentItemPath,
          );
        },
      );
      await progressController.markMigratingComplete();
      return;
    }
  }

  String _normalizedPath(String value) => normalizeStoragePath(value);
}

class _StorageEntry {
  const _StorageEntry({
    required this.relativePath,
    required this.name,
    required this.isDirectory,
    required this.size,
  });

  final String relativePath;
  final String name;
  final bool isDirectory;
  final int size;
}

class _MigrationProgressController {
  _MigrationProgressController({
    required this.fromPath,
    required this.toPath,
    this.onProgress,
  });

  static const Duration _minimumEmitInterval = Duration(milliseconds: 800);
  static const int _largeProgressStep = 160;
  static const int _smallProgressStep = 12;

  final String fromPath;
  final String toPath;
  final MigrationProgressCallback? onProgress;

  int _completedItems = 0;
  int _totalItems = 0;
  int _lastEmittedCompletedItems = -1;
  int _lastEmittedTotalItems = -1;
  DateTime? _lastEmittedAt;
  DownloadStorageMigrationPhase? _lastEmittedPhase;

  Future<void> emitPreparing() {
    return _emit(
      DownloadStorageMigrationPhase.preparing,
      message: '正在准备迁移缓存…',
      force: true,
    );
  }

  Future<void> startMigrating({int totalItems = 0}) {
    _completedItems = 0;
    _totalItems = totalItems;
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
      force: true,
    );
  }

  Future<void> markMigratingComplete() {
    if (_totalItems > 0) {
      _completedItems = _totalItems;
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
      force: true,
    );
  }

  Future<void> syncMigrating({
    required int completedItems,
    required int totalItems,
    String currentItemPath = '',
  }) {
    _completedItems = completedItems < 0 ? 0 : completedItems;
    if (totalItems > 0) {
      _totalItems = totalItems;
      if (_completedItems > _totalItems) {
        _completedItems = _totalItems;
      }
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      currentItemPath: currentItemPath,
      message: _migratingMessage(),
    );
  }

  Future<void> emitCleaning() {
    return _emit(
      DownloadStorageMigrationPhase.cleaning,
      message: '正在清理旧缓存目录…',
      force: true,
    );
  }

  String _migratingMessage() {
    if (_totalItems > 0) {
      return '正在迁移缓存 $_completedItems/$_totalItems…';
    }
    return '正在迁移缓存，请勿退出应用…';
  }

  Future<void> _emit(
    DownloadStorageMigrationPhase phase, {
    required String message,
    String currentItemPath = '',
    bool force = false,
  }) async {
    if (onProgress == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (!force && !_shouldEmit(phase, now)) {
      return;
    }
    _lastEmittedAt = now;
    _lastEmittedCompletedItems = _completedItems;
    _lastEmittedTotalItems = _totalItems;
    _lastEmittedPhase = phase;
    await onProgress!(
      StorageMigrationProgress(
        phase: phase,
        fromPath: fromPath,
        toPath: toPath,
        message: message,
        currentItemPath: currentItemPath,
        completedItems: _completedItems,
        totalItems: _totalItems,
      ),
    );
  }

  bool _shouldEmit(DownloadStorageMigrationPhase phase, DateTime now) {
    if (_lastEmittedPhase != phase) {
      return true;
    }
    if (_completedItems <= 1 ||
        (_totalItems > 0 && _completedItems >= _totalItems)) {
      return true;
    }
    if (_totalItems != _lastEmittedTotalItems) {
      return true;
    }
    final int progressStep = _totalItems > 0 && _totalItems <= 64
        ? _smallProgressStep
        : _largeProgressStep;
    if (_completedItems - _lastEmittedCompletedItems >= progressStep) {
      return true;
    }
    final DateTime? lastEmittedAt = _lastEmittedAt;
    if (lastEmittedAt == null) {
      return true;
    }
    return now.difference(lastEmittedAt) >= _minimumEmitInterval;
  }
}

abstract class _ResolvedStorageRoot {
  Future<void> writeBytes(String relativePath, Uint8List bytes);

  Future<void> writeString(String relativePath, String text);

  Future<String> readString(String relativePath);

  Future<Uint8List> readBytes(String relativePath);

  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  });

  Future<bool> exists(String relativePath);

  Future<bool> deletePath(String relativePath);

  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  );
}

class _FileStorageRoot implements _ResolvedStorageRoot {
  const _FileStorageRoot(this.rootDirectory);

  final Directory rootDirectory;

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) async {
    final File file = File(_absolutePath(relativePath));
    await file.parent.create(recursive: true);
    final File temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> writeString(String relativePath, String text) =>
      writeBytes(relativePath, Uint8List.fromList(utf8.encode(text)));

  @override
  Future<String> readString(String relativePath) {
    return File(_absolutePath(relativePath)).readAsString();
  }

  @override
  Future<Uint8List> readBytes(String relativePath) {
    return File(_absolutePath(relativePath)).readAsBytes();
  }

  @override
  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  }) async {
    final String normalizedRelativePath = _normalizeRelativePath(relativePath);
    final String absolutePath = normalizedRelativePath.isEmpty
        ? rootDirectory.path
        : _absolutePath(normalizedRelativePath);
    final FileSystemEntityType type = await FileSystemEntity.type(absolutePath);
    if (type == FileSystemEntityType.notFound) {
      return const <_StorageEntry>[];
    }
    if (type == FileSystemEntityType.file) {
      final File file = File(absolutePath);
      return <_StorageEntry>[
        _StorageEntry(
          relativePath: normalizedRelativePath,
          name: file.uri.pathSegments.last,
          isDirectory: false,
          size: await file.length(),
        ),
      ];
    }

    final Directory directory = Directory(absolutePath);
    final List<_StorageEntry> entries = <_StorageEntry>[];
    await for (final FileSystemEntity entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final String relative = entity.path
          .substring(rootDirectory.path.length)
          .replaceFirst(RegExp(r'^[\\/]+'), '')
          .replaceAll('\\', '/');
      if (relative.isEmpty) {
        continue;
      }
      final FileSystemEntityType entityType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      final bool isDirectory = entityType == FileSystemEntityType.directory;
      final int size = entity is File ? await entity.length() : 0;
      entries.add(
        _StorageEntry(
          relativePath: relative,
          name: entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last,
          isDirectory: isDirectory,
          size: size,
        ),
      );
    }
    return entries;
  }

  @override
  Future<bool> exists(String relativePath) async {
    return await FileSystemEntity.type(
          _absolutePath(relativePath),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;
  }

  @override
  Future<bool> deletePath(String relativePath) async {
    final String absolutePath = _absolutePath(relativePath);
    final FileSystemEntityType type = await FileSystemEntity.type(
      absolutePath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return false;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(absolutePath).delete(recursive: true);
      return true;
    }
    await File(absolutePath).delete();
    return true;
  }

  @override
  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  ) {
    final String normalizedChapterDirectoryPath = _normalizeRelativePath(
      chapterDirectoryPath,
    );
    return fileNames
        .map((String fileName) => fileName.trim())
        .where((String fileName) => fileName.isNotEmpty)
        .map(
          (String fileName) => File(
            _absolutePath(
              normalizedChapterDirectoryPath.isEmpty
                  ? fileName
                  : '$normalizedChapterDirectoryPath/$fileName',
            ),
          ).uri.toString(),
        )
        .toList(growable: false);
  }

  String _absolutePath(String relativePath) {
    final String normalized = _normalizeRelativePath(
      relativePath,
    ).replaceAll('/', Platform.pathSeparator);
    return normalized.isEmpty
        ? rootDirectory.path
        : '${rootDirectory.path}${Platform.pathSeparator}$normalized';
  }

  String _normalizeRelativePath(String relativePath) {
    return relativePath.trim().replaceAll('\\', '/');
  }
}

class _DocumentTreeStorageRoot implements _ResolvedStorageRoot {
  const _DocumentTreeStorageRoot({
    required this.bridge,
    required this.treeUri,
    this.rootRelativePath = '',
  });

  final AndroidDocumentTreeBridge bridge;
  final String treeUri;
  final String rootRelativePath;

  Future<void> importFromDirectory(
    Directory source, {
    required List<String> relativePaths,
    bool verifyOnly = false,
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.importDirectoryFromPath(
      treeUri: treeUri,
      sourcePath: source.path,
      relativePath: rootRelativePath,
      relativePaths: relativePaths,
      verifyOnly: verifyOnly,
      onProgress: onProgress,
    );
  }

  Future<void> exportToDirectory(
    Directory destination, {
    required List<String> relativePaths,
    bool verifyOnly = false,
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.exportDirectoryToPath(
      treeUri: treeUri,
      destinationPath: destination.path,
      relativePath: rootRelativePath,
      relativePaths: relativePaths,
      verifyOnly: verifyOnly,
      onProgress: onProgress,
    );
  }

  Future<void> copyToDocumentTree(
    _DocumentTreeStorageRoot target, {
    required List<String> relativePaths,
    bool verifyOnly = false,
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.copyDirectoryToTree(
      sourceTreeUri: treeUri,
      targetTreeUri: target.treeUri,
      sourceRelativePath: rootRelativePath,
      targetRelativePath: target.rootRelativePath,
      relativePaths: relativePaths,
      verifyOnly: verifyOnly,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> writeBytes(String relativePath, Uint8List bytes) {
    return bridge.writeBytes(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
      bytes: bytes,
    );
  }

  @override
  Future<void> writeString(String relativePath, String text) {
    return bridge.writeText(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
      text: text,
    );
  }

  @override
  Future<String> readString(String relativePath) {
    return bridge.readText(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<Uint8List> readBytes(String relativePath) {
    return bridge.readBytes(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<List<_StorageEntry>> listEntries(
    String relativePath, {
    required bool recursive,
  }) async {
    final String requestedPath = _resolveRelativePath(relativePath);
    final String prefix = _normalizeRelativePath(rootRelativePath);
    final List<DocumentTreeEntry> entries = await bridge.listEntries(
      treeUri: treeUri,
      relativePath: requestedPath,
      recursive: recursive,
    );
    return entries
        .map((DocumentTreeEntry entry) => _toStorageEntry(entry, prefix))
        .where((_StorageEntry entry) => entry.relativePath.isNotEmpty)
        .toList(growable: false);
  }

  _StorageEntry _toStorageEntry(DocumentTreeEntry entry, String prefix) {
    String relative = _normalizeRelativePath(entry.relativePath);
    if (prefix.isNotEmpty) {
      if (relative == prefix) {
        relative = '';
      } else if (relative.startsWith('$prefix/')) {
        relative = relative.substring(prefix.length + 1);
      }
    }
    return _StorageEntry(
      relativePath: relative,
      name: entry.name,
      isDirectory: entry.isDirectory,
      size: entry.size,
    );
  }

  @override
  Future<bool> exists(String relativePath) {
    return bridge.exists(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  Future<bool> deletePath(String relativePath) {
    return bridge.deletePath(
      treeUri: treeUri,
      relativePath: _resolveRelativePath(relativePath),
    );
  }

  @override
  List<String> buildReaderImageUrls(
    String chapterDirectoryPath,
    List<String> fileNames,
  ) {
    final String normalizedChapterDirectoryPath = _normalizeRelativePath(
      chapterDirectoryPath,
    );
    return fileNames
        .map((String fileName) => fileName.trim())
        .where((String fileName) => fileName.isNotEmpty)
        .map((String fileName) {
          final String relativePath = normalizedChapterDirectoryPath.isEmpty
              ? fileName
              : '$normalizedChapterDirectoryPath/$fileName';
          return buildTreeImageUri(
            treeUri: treeUri,
            relativePath: _resolveRelativePath(relativePath),
          );
        })
        .toList(growable: false);
  }

  String _resolveRelativePath(String relativePath) {
    final String normalized = _normalizeRelativePath(relativePath);
    final String normalizedRoot = _normalizeRelativePath(rootRelativePath);
    if (normalizedRoot.isEmpty) {
      return normalized;
    }
    if (normalized.isEmpty) {
      return normalizedRoot;
    }
    return '$normalizedRoot/$normalized';
  }

  String _normalizeRelativePath(String relativePath) {
    return relativePath.trim().replaceAll('\\', '/');
  }
}

class _LibraryScanStats {
  int comicDirectoryCount = 0;
  int chapterDirectoryCount = 0;
  int manifestCount = 0;
  int listCalls = 0;
  int existsCalls = 0;
  int readCalls = 0;
}

class _FileSystemCopyRequest {
  const _FileSystemCopyRequest({
    required this.sourcePath,
    required this.targetPath,
    required this.relativePaths,
    required this.verifyOnly,
  });

  final String sourcePath;
  final String targetPath;
  final List<String> relativePaths;
  final bool verifyOnly;
}

int _copyFileSystemTreeSync(_FileSystemCopyRequest request) {
  final String sourceRoot = Directory(
    request.sourcePath,
  ).resolveSymbolicLinksSync();
  final String targetRoot = Directory(
    request.targetPath,
  ).resolveSymbolicLinksSync();
  final List<(String, File, File)> files = <(String, File, File)>[];
  for (final String relative in request.relativePaths) {
    final File source = _migrationFile(sourceRoot, relative);
    final File target = _migrationFile(targetRoot, relative);
    if (!source.existsSync()) {
      throw FileSystemException('原缓存文件无法读取。', source.path);
    }
    if (target.existsSync()) {
      if (!_filesMatchSync(source, target)) {
        throw FileSystemException('目标目录存在不同的同名文件，未覆盖。', target.path);
      }
    } else if (request.verifyOnly) {
      throw FileSystemException('目标缓存文件不完整，保留原目录。', target.path);
    } else {
      files.add((relative, source, target));
    }
  }
  for (final (String relative, File source, File target) in files) {
    target.parent.createSync(recursive: true);
    _migrationFile(sourceRoot, relative);
    _migrationFile(targetRoot, relative);
    final File temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.migrate_tmp',
    );
    try {
      source.copySync(temporary.path);
      if (!_filesMatchSync(source, temporary)) {
        throw FileSystemException('缓存复制校验失败，保留原目录。', source.path);
      }
      if (target.existsSync()) {
        if (!_filesMatchSync(source, target)) {
          throw FileSystemException('目标目录存在不同的同名文件，未覆盖。', target.path);
        }
      } else {
        temporary.renameSync(target.path);
      }
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
  return request.relativePaths.length;
}

bool _filesMatchSync(File left, File right) {
  if (left.lengthSync() != right.lengthSync()) return false;
  final RandomAccessFile leftReader = left.openSync();
  RandomAccessFile? rightReader;
  try {
    rightReader = right.openSync();
    while (true) {
      final Uint8List leftBytes = leftReader.readSync(64 * 1024);
      final Uint8List rightBytes = rightReader.readSync(64 * 1024);
      if (leftBytes.length != rightBytes.length) return false;
      if (leftBytes.isEmpty) return true;
      for (int index = 0; index < leftBytes.length; index += 1) {
        if (leftBytes[index] != rightBytes[index]) return false;
      }
    }
  } finally {
    leftReader.closeSync();
    rightReader?.closeSync();
  }
}

bool _isCacheFileName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains(r'\');

bool _isNumberedCacheImage(String name) => RegExp(
  r'^\d+\.(avif|bmp|gif|jpeg|jpg|png|webp)$',
  caseSensitive: false,
).hasMatch(name);

File _migrationFile(String canonicalRoot, String relativePath) {
  final List<String> parts = relativePath.split('/');
  if (parts.isEmpty ||
      parts.any(
        (String part) =>
            !_isCacheFileName(part) ||
            (Platform.isWindows && part.contains(':')),
      )) {
    throw FileSystemException('缓存文件路径无效。', relativePath);
  }
  final String root = normalizeStoragePath(canonicalRoot);
  final String rootPrefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  String path = canonicalRoot;
  for (final String part in parts) {
    path = path.endsWith(Platform.pathSeparator)
        ? '$path$part'
        : '$path${Platform.pathSeparator}$part';
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      continue;
    }
    final String resolved = normalizeStoragePath(
      File(path).resolveSymbolicLinksSync(),
    );
    if (resolved != root && !resolved.startsWith(rootPrefix)) {
      throw FileSystemException('缓存文件路径超出所选目录。', path);
    }
  }
  return File(path);
}
