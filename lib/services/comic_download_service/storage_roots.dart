part of '../comic_download_service.dart';

extension _DownloadStorageRoots on ComicDownloadService {
  Future<_ResolvedStorageRoot> _resolveStorageRoot({
    DownloadPreferences? preferences,
    required bool verifyWritable,
  }) async {
    final DownloadStorageState storageState = await resolveStorageState(
      preferences: preferences,
      verifyWritable: verifyWritable,
    );
    if (!storageState.isReady && verifyWritable) {
      throw FileSystemException(
        storageState.errorMessage.isEmpty
            ? '缓存目录不可用。'
            : storageState.errorMessage,
      );
    }
    return _resolveStorageRootFromState(storageState);
  }

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
    if (left.preferences.usesDocumentTree ||
        right.preferences.usesDocumentTree) {
      return left.preferences.usesDocumentTree &&
          right.preferences.usesDocumentTree &&
          left.documentTreeUri.trim() == right.documentTreeUri.trim();
    }
    return _normalizedPath(left.rootPath) == _normalizedPath(right.rootPath);
  }

  bool _storageRootsOverlap(
    DownloadStorageState left,
    DownloadStorageState right,
  ) {
    final String leftRoot = _normalizedComparableRoot(left.rootPath);
    final String rightRoot = _normalizedComparableRoot(right.rootPath);
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

  Future<ChapterDownloadResult?> _loadCompletedChapter({
    required _ResolvedStorageRoot root,
    required String manifestRelativePath,
    required String chapterDirectoryPath,
    required int expectedImageCount,
  }) async {
    if (!await root.exists(manifestRelativePath)) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(
        await root.readString(manifestRelativePath),
      );
      if (decoded is! Map) {
        return null;
      }
      final int imageCount = (decoded['imageCount'] as num?)?.toInt() ?? 0;
      if (imageCount < expectedImageCount) {
        return null;
      }
      return ChapterDownloadResult(
        directory: Directory(chapterDirectoryPath),
        fileCount: imageCount,
        manifestFile: File(manifestRelativePath),
      );
    } catch (_) {
      return null;
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
    final RegExp pattern = RegExp(r'^(\d{3})\.[^.]+$');
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

  Future<void> _copyRelativePath(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot,
    String relativePath,
  ) async {
    final List<_StorageEntry> entries = await sourceRoot.listEntries(
      relativePath,
      recursive: true,
    );
    if (entries.isEmpty) {
      return;
    }
    for (final _StorageEntry entry in entries) {
      if (entry.isDirectory || _shouldSkipMigrationFile(entry.name)) {
        continue;
      }
      await targetRoot.writeBytes(
        entry.relativePath,
        await sourceRoot.readBytes(entry.relativePath),
      );
    }
  }

  Future<int> _copyDirInIsolate(Directory source, Directory target) {
    return Isolate.run<int>(
      () => _copyFileSystemTreeSync(
        _FileSystemCopyRequest(
          sourcePath: source.path,
          targetPath: target.path,
        ),
      ),
    );
  }

  Future<bool> _clearStorageRoot(
    _ResolvedStorageRoot root, {
    required bool allowFullClean,
  }) async {
    final List<_StorageEntry> topLevelEntries = await root.listEntries(
      '',
      recursive: false,
    );
    bool didDelete = false;
    for (final _StorageEntry entry in topLevelEntries) {
      if (allowFullClean) {
        if (await root.deletePath(entry.relativePath)) {
          didDelete = true;
        }
        continue;
      }
      if (!entry.isDirectory) {
        continue;
      }
      final String markerPath = _joinRelativePath(<String>[
        entry.relativePath,
        _comicOwnershipMarkerName,
      ]);
      if (!await root.exists(markerPath)) {
        continue;
      }
      if (await root.deletePath(entry.relativePath)) {
        didDelete = true;
      }
    }
    return didDelete;
  }

  Future<String> _cleanupStorageRootSafely(
    _ResolvedStorageRoot root, {
    required _MigrationProgressController progressController,
    required bool allowFullClean,
  }) async {
    try {
      await progressController.emitCleaning();
      final bool didDelete = await _clearStorageRoot(
        root,
        allowFullClean: allowFullClean,
      );
      if (!allowFullClean) {
        return didDelete
            ? '出于安全考虑仅清理了应用创建的缓存目录，请检查自选目录内是否仍有旧缓存。'
            : '出于安全考虑未清空自选目录，请手动删除易拷贝创建的缓存目录。';
      }
      return '';
    } catch (_) {
      return '旧缓存目录未能自动清理，可稍后手动删除。';
    }
  }

  Future<void> _migrateStorageContents(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot, {
    required _MigrationProgressController progressController,
  }) async {
    if (sourceRoot is _FileStorageRoot && targetRoot is _FileStorageRoot) {
      await progressController.startMigrating();
      final int copiedFiles = await _copyDirInIsolate(
        sourceRoot.rootDirectory,
        targetRoot.rootDirectory,
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
    await _copyStorageEntryByEntry(
      sourceRoot,
      targetRoot,
      progressController: progressController,
    );
  }

  Future<void> _copyStorageEntryByEntry(
    _ResolvedStorageRoot sourceRoot,
    _ResolvedStorageRoot targetRoot, {
    required _MigrationProgressController progressController,
  }) async {
    final List<_StorageEntry> sourceEntries = await sourceRoot.listEntries(
      '',
      recursive: true,
    );
    final List<_StorageEntry> fileEntries = sourceEntries
        .where(
          (_StorageEntry entry) =>
              !entry.isDirectory && !_shouldSkipMigrationFile(entry.name),
        )
        .toList(growable: false);
    await progressController.startMigrating(totalItems: fileEntries.length);
    for (final _StorageEntry entry in fileEntries) {
      await targetRoot.writeBytes(
        entry.relativePath,
        await sourceRoot.readBytes(entry.relativePath),
      );
      await progressController.advance(currentItemPath: entry.relativePath);
    }
  }

  bool _shouldSkipMigrationFile(String fileName) {
    return _shouldSkipMigrationFileName(fileName);
  }

  String _normalizedPath(String value) {
    final String normalized = value.trim().replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class _StorageEntry {
  const _StorageEntry({
    required this.relativePath,
    required this.name,
    required this.uri,
    required this.isDirectory,
    required this.size,
  });

  final String relativePath;
  final String name;
  final String uri;
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

  Future<void> advance({int count = 1, String currentItemPath = ''}) {
    if (count > 0) {
      _completedItems += count;
      if (_totalItems > 0 && _completedItems > _totalItems) {
        _completedItems = _totalItems;
      }
    }
    return _emit(
      DownloadStorageMigrationPhase.migrating,
      currentItemPath: currentItemPath,
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
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeString(String relativePath, String text) async {
    final File file = File(_absolutePath(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
  }

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
          uri: file.uri.toString(),
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
          uri: entity.uri.toString(),
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
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.importDirectoryFromPath(
      treeUri: treeUri,
      sourcePath: source.path,
      relativePath: rootRelativePath,
      onProgress: onProgress,
    );
  }

  Future<void> exportToDirectory(
    Directory destination, {
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.exportDirectoryToPath(
      treeUri: treeUri,
      destinationPath: destination.path,
      relativePath: rootRelativePath,
      onProgress: onProgress,
    );
  }

  Future<void> copyToDocumentTree(
    _DocumentTreeStorageRoot target, {
    DocumentTreeProgressCallback? onProgress,
  }) {
    return bridge.copyDirectoryToTree(
      sourceTreeUri: treeUri,
      targetTreeUri: target.treeUri,
      sourceRelativePath: rootRelativePath,
      targetRelativePath: target.rootRelativePath,
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
      uri: entry.uri,
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
  });

  final String sourcePath;
  final String targetPath;
}

int _copyFileSystemTreeSync(_FileSystemCopyRequest request) {
  final Directory source = Directory(request.sourcePath);
  final Directory target = Directory(request.targetPath);
  target.createSync(recursive: true);
  return _copyDirectoryRecursiveSync(source, target);
}

int _copyDirectoryRecursiveSync(Directory source, Directory target) {
  int copiedFiles = 0;
  final List<FileSystemEntity> children = source.listSync(followLinks: false);
  for (final FileSystemEntity child in children) {
    final String name = child.uri.pathSegments.isEmpty
        ? ''
        : child.uri.pathSegments.lastWhere(
            (String segment) => segment.isNotEmpty,
            orElse: () => '',
          );
    if (name.isEmpty || _shouldSkipMigrationFileName(name)) {
      continue;
    }
    if (child is Directory) {
      final Directory nextTarget = Directory(
        '${target.path}${Platform.pathSeparator}$name',
      );
      nextTarget.createSync(recursive: true);
      copiedFiles += _copyDirectoryRecursiveSync(child, nextTarget);
      continue;
    }
    if (child is File) {
      final File nextTarget = File(
        '${target.path}${Platform.pathSeparator}$name',
      );
      nextTarget.parent.createSync(recursive: true);
      child.copySync(nextTarget.path);
      copiedFiles += 1;
    }
  }
  return copiedFiles;
}

bool _shouldSkipMigrationFileName(String fileName) {
  final String normalized = fileName.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.endsWith('.part') ||
      normalized.endsWith('.migrate_tmp') ||
      normalized.startsWith('.storage_probe_');
}
