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
    required Map<String, Object?>? manifest,
    required String chapterDirectoryPath,
    required int expectedImageCount,
    required Future<bool> Function(String relativePath) validateImage,
  }) async {
    if (manifest == null) return false;
    try {
      final files = _manifestImageFiles(manifest);
      if (files == null || files.length != expectedImageCount) return false;
      for (final value in files) {
        final String path = _joinRelativePath(<String>[
          chapterDirectoryPath,
          value,
        ]);
        if (!await validateImage(path)) return false;
      }
      return true;
    } on DownloadCancelledException {
      rethrow;
    } on DownloadPausedException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<Map<int, String>> _loadExistingImageFiles(
    _ResolvedStorageRoot root,
    String chapterDirectoryPath, {
    Future<bool> Function(String relativePath)? validateImage,
    required int imageCount,
  }) async {
    if (!await root.exists(chapterDirectoryPath)) {
      return const <int, String>{};
    }

    final Map<int, String> existingFiles = <int, String>{};
    final RegExp pattern = RegExp(r'^(\d+)\.[^.]+$');
    for (final DocumentTreeEntry entry in await root.listEntries(
      chapterDirectoryPath,
      recursive: false,
      includeSize: true,
    )) {
      if (entry.isDirectory) {
        continue;
      }
      final String fileName = entry.name;
      final RegExpMatch? match = pattern.firstMatch(fileName);
      if (match == null) {
        continue;
      }
      final index = int.tryParse(match.group(1)!) ?? 0;
      if (index < 1 || index > imageCount || entry.size <= 0) {
        continue;
      }
      try {
        final bool valid =
            await (validateImage?.call(entry.relativePath) ??
                isCompleteImage(await root.readBytes(entry.relativePath)));
        if (!valid) {
          continue;
        }
      } on DownloadCancelledException {
        rethrow;
      } on DownloadPausedException {
        rethrow;
      } catch (_) {
        continue;
      }
      existingFiles[index - 1] = fileName;
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
    List<DocumentTreeEntry>? listedEntries,
  }) async {
    final List<DocumentTreeEntry> entries =
        listedEntries ?? await root.listEntries(relativePath, recursive: true);
    final Set<String> paths = <String>{};
    for (final DocumentTreeEntry entry in entries) {
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
          imageCount: count,
        );
        paths.addAll(images.values.map((name) => '$directory/$name'));
        paths.add(entry.relativePath);
        continue;
      }
      final files = _manifestImageFiles(decoded);
      if ((decoded['comicTitle']?.toString().trim() ?? '').isEmpty ||
          files == null ||
          !files.every(_isNumberedCacheImage)) {
        continue;
      }
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
        onProgress: progressController.onProgress == null || verifyOnly
            ? null
            : progressController.syncTransfer,
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
        onProgress: progressController.onProgress == null || verifyOnly
            ? null
            : progressController.syncTransfer,
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
        onProgress: progressController.onProgress == null || verifyOnly
            ? null
            : progressController.syncTransfer,
      );
      await progressController.markMigratingComplete();
      return;
    }
  }

  String _normalizedPath(String value) => normalizeStoragePath(value);
}

class _MigrationProgressController {
  _MigrationProgressController({
    required this.fromPath,
    required this.toPath,
    this.onProgress,
  });

  final String fromPath;
  final String toPath;
  final MigrationProgressCallback? onProgress;

  int _completedItems = 0;
  int _totalItems = 0;
  Future<void> syncTransfer(DocumentTreeTransferProgress progress) =>
      syncMigrating(
        completedItems: progress.completedCount,
        totalItems: progress.totalCount,
        currentItemPath: progress.currentItemPath,
      );

  Future<void> emitPreparing() {
    return _emit(DownloadStorageMigrationPhase.preparing, message: '正在准备迁移缓存…');
  }

  Future<void> startMigrating({int totalItems = 0}) {
    _completedItems = 0;
    _totalItems = totalItems;
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
    );
  }

  Future<void> markMigratingComplete() {
    if (_totalItems > 0) {
      _completedItems = _totalItems;
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      message: _migratingMessage(),
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
    return _emit(DownloadStorageMigrationPhase.cleaning, message: '正在清理旧缓存目录…');
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
  }) async {
    if (onProgress == null) {
      return;
    }
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
}

abstract class _ResolvedStorageRoot {
  Future<void> writeBytes(String relativePath, Uint8List bytes);

  Future<void> writeString(String relativePath, String text);

  Future<String> readString(String relativePath);

  Future<Uint8List> readBytes(String relativePath);

  Future<List<DocumentTreeEntry>> listEntries(
    String relativePath, {
    required bool recursive,
    bool includeSize = false,
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
  Future<List<DocumentTreeEntry>> listEntries(
    String relativePath, {
    required bool recursive,
    bool includeSize = false,
  }) async {
    final String normalizedRelativePath = _normalizeRelativePath(relativePath);
    final String absolutePath = normalizedRelativePath.isEmpty
        ? rootDirectory.path
        : _absolutePath(normalizedRelativePath);
    final FileSystemEntityType type = await FileSystemEntity.type(absolutePath);
    if (type == FileSystemEntityType.notFound) {
      return const <DocumentTreeEntry>[];
    }
    if (type == FileSystemEntityType.file) {
      final File file = File(absolutePath);
      return <DocumentTreeEntry>[
        DocumentTreeEntry(
          relativePath: normalizedRelativePath,
          name: file.uri.pathSegments.last,
          isDirectory: false,
          size: includeSize ? await file.length() : 0,
        ),
      ];
    }

    final Directory directory = Directory(absolutePath);
    final List<DocumentTreeEntry> entries = <DocumentTreeEntry>[];
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
      final bool isDirectory = entity is Directory;
      final int size = includeSize && entity is File
          ? await entity.length()
          : 0;
      entries.add(
        DocumentTreeEntry(
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
  Future<List<DocumentTreeEntry>> listEntries(
    String relativePath, {
    required bool recursive,
    bool includeSize = false,
  }) async {
    final String requestedPath = _resolveRelativePath(relativePath);
    return bridge.listEntries(
      treeUri: treeUri,
      relativePath: requestedPath,
      recursive: recursive,
      rootPrefix: _normalizeRelativePath(rootRelativePath),
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
}

class _LibraryScanStats {
  int comicDirectoryCount = 0;
  int chapterDirectoryCount = 0;
  int manifestCount = 0;
  int listCalls = 0;
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
      if (source.lengthSync() != temporary.lengthSync()) {
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
    final leftBytes = Uint8List(64 * 1024);
    final rightBytes = Uint8List(leftBytes.length);
    while (true) {
      final count = leftReader.readIntoSync(leftBytes);
      if (rightReader.readIntoSync(rightBytes) != count) return false;
      if (count == 0) return true;
      for (int index = 0; index < count; index += 1) {
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

final _numberedCacheImagePattern = RegExp(r'^(\d+)\.([^.]+)$');

bool _isNumberedCacheImage(String name) {
  final match = _numberedCacheImagePattern.firstMatch(name);
  return match != null &&
      comicImageExtensions.contains(match[2]!.toLowerCase());
}

List<String>? _manifestImageFiles(Map? manifest) {
  final raw = manifest?['files'];
  if (raw is! List || raw.isEmpty || raw.length != manifest?['imageCount']) {
    return null;
  }
  final seen = <String>{};
  for (final name in raw) {
    if (name is! String || !_isCacheFileName(name) || !seen.add(name)) {
      return null;
    }
  }
  return raw.cast<String>();
}

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

String _normalizeRelativePath(String relativePath) {
  return relativePath.trim().replaceAll('\\', '/');
}
