import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/app_preferences_controller.dart';

typedef DownloadPreferencesProvider = Future<DownloadPreferences> Function();
typedef DownloadBaseDirectoryProvider = Future<Directory> Function();
typedef DownloadBaseDirectoriesProvider = Future<List<Directory>?> Function();
typedef StorageDirsProvider =
    Future<List<Directory>?> Function(StorageDirectory? type);

@immutable
class DownloadStorageState {
  const DownloadStorageState({
    required this.preferences,
    required this.basePath,
    required this.rootPath,
    required this.isCustom,
    required this.isDocumentTree,
    required this.isWritable,
    required this.mayBeRemovedOnUninstall,
    this.documentTreeUri = '',
    this.errorMessage = '',
    this.isLoading = false,
  });

  const DownloadStorageState.loading()
    : preferences = const DownloadPreferences(),
      basePath = '',
      rootPath = '',
      isCustom = false,
      isDocumentTree = false,
      isWritable = false,
      mayBeRemovedOnUninstall = false,
      documentTreeUri = '',
      errorMessage = '',
      isLoading = true;

  final DownloadPreferences preferences;
  final String basePath;
  final String rootPath;
  final bool isCustom;
  final bool isDocumentTree;
  final bool isWritable;
  final bool mayBeRemovedOnUninstall;
  final String documentTreeUri;
  final String errorMessage;
  final bool isLoading;

  bool get isReady =>
      !isLoading &&
      errorMessage.isEmpty &&
      rootPath.trim().isNotEmpty &&
      isWritable;

  String get displayPath => rootPath.trim().isNotEmpty ? rootPath : basePath;
}

class DownloadStorageService {
  DownloadStorageService({
    AppPreferencesController? preferencesController,
    DownloadPreferencesProvider? preferencesProvider,
    DownloadBaseDirectoryProvider? defaultBaseDirectoryProvider,
    DownloadBaseDirectoriesProvider? customBaseDirectoriesProvider,
    StorageDirsProvider? storageDirsProvider,
    DownloadBaseDirectoriesProvider? cacheDirsProvider,
    AndroidDocumentTreeBridge? documentTreeBridge,
  }) : _preferencesController =
           preferencesController ?? AppPreferencesController.instance,
       _preferencesProvider = preferencesProvider,
       _defaultBaseDirectoryProvider =
           defaultBaseDirectoryProvider ?? _defaultBaseDirectory,
       _customBaseDirectoriesProvider = customBaseDirectoriesProvider,
       _storageDirsProvider = storageDirsProvider ?? _defaultStorageDirs,
       _cacheDirsProvider = cacheDirsProvider ?? _defaultCacheDirs,
       _documentTreeBridge =
           documentTreeBridge ?? AndroidDocumentTreeBridge.instance,
       _supportsCustomDirs =
           Platform.isAndroid ||
           Platform.isWindows ||
           customBaseDirectoriesProvider != null ||
           storageDirsProvider != null ||
           cacheDirsProvider != null;

  static final DownloadStorageService instance = DownloadStorageService();
  static const String downloadsDirectoryName = 'EasyCopyDownloads';

  final AppPreferencesController _preferencesController;
  final DownloadPreferencesProvider? _preferencesProvider;
  final DownloadBaseDirectoryProvider _defaultBaseDirectoryProvider;
  final DownloadBaseDirectoriesProvider? _customBaseDirectoriesProvider;
  final StorageDirsProvider _storageDirsProvider;
  final DownloadBaseDirectoriesProvider _cacheDirsProvider;
  final AndroidDocumentTreeBridge _documentTreeBridge;
  final bool _supportsCustomDirs;

  bool get supportsCustomDirs => _supportsCustomDirs;

  Future<DownloadStorageState> resolveState({
    DownloadPreferences? preferences,
    bool verifyWritable = true,
  }) async {
    final DownloadPreferences resolvedPreferences =
        preferences ?? await _loadPreferences();
    if (resolvedPreferences.usesDocumentTree) {
      return _resolveDocumentTreeState(
        resolvedPreferences,
        verifyWritable: verifyWritable,
      );
    }
    final String rawBasePath = resolvedPreferences.usesCustomDirectory
        ? resolvedPreferences.customBasePath.trim()
        : (await _defaultBaseDirectoryProvider()).path;
    final bool isCustom = resolvedPreferences.usesCustomDirectory;
    final bool usePickedDirectoryAsRoot =
        isCustom && resolvedPreferences.usePickedDirectoryAsRoot;
    if (rawBasePath.isEmpty) {
      return DownloadStorageState(
        preferences: resolvedPreferences,
        basePath: '',
        rootPath: '',
        isCustom: isCustom,
        isDocumentTree: false,
        isWritable: false,
        mayBeRemovedOnUninstall: _mayBeRemovedOnUninstall(
          isCustom: isCustom,
          basePath: rawBasePath,
        ),
        errorMessage: isCustom ? '尚未设置自定义缓存目录。' : '默认缓存目录不可用。',
      );
    }

    final Directory baseDirectory = Directory(rawBasePath);
    final Directory rootDirectory = usePickedDirectoryAsRoot
        ? baseDirectory
        : Directory(
            _joinPath(<String>[baseDirectory.path, downloadsDirectoryName]),
          );
    try {
      await rootDirectory.create(recursive: true);
      if (verifyWritable) {
        await _verifyWritable(rootDirectory);
      }
      return DownloadStorageState(
        preferences: resolvedPreferences,
        basePath: baseDirectory.path,
        rootPath: rootDirectory.path,
        isCustom: isCustom,
        isDocumentTree: false,
        isWritable: true,
        mayBeRemovedOnUninstall: _mayBeRemovedOnUninstall(
          isCustom: isCustom,
          basePath: baseDirectory.path,
        ),
      );
    } on FileSystemException catch (error) {
      return DownloadStorageState(
        preferences: resolvedPreferences,
        basePath: baseDirectory.path,
        rootPath: rootDirectory.path,
        isCustom: isCustom,
        isDocumentTree: false,
        isWritable: false,
        mayBeRemovedOnUninstall: _mayBeRemovedOnUninstall(
          isCustom: isCustom,
          basePath: baseDirectory.path,
        ),
        errorMessage: error.message,
      );
    } catch (error) {
      return DownloadStorageState(
        preferences: resolvedPreferences,
        basePath: baseDirectory.path,
        rootPath: rootDirectory.path,
        isCustom: isCustom,
        isDocumentTree: false,
        isWritable: false,
        mayBeRemovedOnUninstall: _mayBeRemovedOnUninstall(
          isCustom: isCustom,
          basePath: baseDirectory.path,
        ),
        errorMessage: error.toString(),
      );
    }
  }

  Future<List<DownloadStorageState>> loadCustomDirectoryCandidates() async {
    if (!supportsCustomDirs) {
      return const <DownloadStorageState>[];
    }

    final List<Directory> baseDirectories = await _loadCustomBaseDirectories();
    if (baseDirectories.isEmpty) {
      return const <DownloadStorageState>[];
    }

    final DownloadStorageState defaultState = await resolveState(
      preferences: const DownloadPreferences(),
      verifyWritable: false,
    );
    final String normalizedDefaultBasePath = _normalizedPath(
      defaultState.basePath,
    );
    final Set<String> seenPaths = <String>{};
    final List<DownloadStorageState> candidates = <DownloadStorageState>[];

    for (final Directory directory in baseDirectories) {
      final String basePath = directory.path.trim();
      if (basePath.isEmpty) {
        continue;
      }
      final String normalizedBasePath = _normalizedPath(basePath);
      if (!seenPaths.add(normalizedBasePath) ||
          normalizedBasePath == normalizedDefaultBasePath) {
        continue;
      }

      final DownloadStorageState candidate = await resolveState(
        preferences: DownloadPreferences(
          mode: DownloadStorageMode.customDirectory,
          customBasePath: basePath,
          usePickedDirectoryAsRoot: true,
        ),
        verifyWritable: true,
      );
      if (candidate.isReady) {
        candidates.add(candidate);
      }
    }

    candidates.sort(
      (DownloadStorageState left, DownloadStorageState right) =>
          left.basePath.compareTo(right.basePath),
    );
    return candidates;
  }

  Future<PickedDocumentTreeDirectory?> pickDocumentTreeDirectory() {
    if (!_documentTreeBridge.isSupported) {
      return Future<PickedDocumentTreeDirectory?>.value(null);
    }
    return _documentTreeBridge.pickDirectory();
  }

  String summarizePath(String path) {
    final String normalized = path.trim();
    if (normalized.isEmpty) {
      return '未设置';
    }
    if (normalized.length <= 42) {
      return normalized;
    }
    final int separatorIndex = normalized.lastIndexOf(Platform.pathSeparator);
    if (separatorIndex <= 0 || separatorIndex == normalized.length - 1) {
      return '...${normalized.substring(normalized.length - 39)}';
    }
    final String tail = normalized.substring(separatorIndex);
    final int headLength = 39 - tail.length;
    if (headLength <= 4) {
      return '...$tail';
    }
    return '${normalized.substring(0, headLength)}...$tail';
  }

  String storageKeyForState(DownloadStorageState state) {
    if (state.isDocumentTree) {
      final String treeUri = state.documentTreeUri.trim();
      if (treeUri.isNotEmpty) {
        return 'tree:$treeUri';
      }
      return 'tree:${state.displayPath}';
    }
    final String rootPath = state.rootPath.trim().isNotEmpty
        ? state.rootPath
        : state.basePath;
    return 'file:${_normalizedPath(rootPath)}';
  }

  Future<DownloadPreferences> _loadPreferences() async {
    if (_preferencesProvider != null) {
      return _preferencesProvider();
    }
    await _preferencesController.ensureInitialized();
    return _preferencesController.downloadPreferences;
  }

  Future<DownloadStorageState> _resolveDocumentTreeState(
    DownloadPreferences preferences, {
    required bool verifyWritable,
  }) async {
    final String treeUri = preferences.customTreeUri.trim();
    final String fallbackBasePath = preferences.displayPath;
    final bool usePickedDirectoryAsRoot = preferences.usePickedDirectoryAsRoot;
    final String fallbackRootPath =
        usePickedDirectoryAsRoot || fallbackBasePath.isEmpty
        ? fallbackBasePath
        : '$fallbackBasePath${Platform.pathSeparator}$downloadsDirectoryName';
    if (treeUri.isEmpty) {
      return DownloadStorageState(
        preferences: preferences,
        basePath: fallbackBasePath,
        rootPath: fallbackRootPath,
        isCustom: true,
        isDocumentTree: true,
        isWritable: false,
        mayBeRemovedOnUninstall: false,
        documentTreeUri: treeUri,
        errorMessage: '尚未设置自定义缓存目录。',
      );
    }

    try {
      final DocumentTreeDirectoryResolution resolution =
          await _documentTreeBridge.resolveDirectory(
            treeUri: treeUri,
            relativePath: usePickedDirectoryAsRoot
                ? ''
                : downloadsDirectoryName,
            verifyWritable: verifyWritable,
          );
      return DownloadStorageState(
        preferences: preferences,
        basePath: resolution.basePath.isEmpty
            ? fallbackBasePath
            : resolution.basePath,
        rootPath: resolution.rootPath.isEmpty
            ? fallbackRootPath
            : resolution.rootPath,
        isCustom: true,
        isDocumentTree: true,
        isWritable: resolution.isWritable,
        mayBeRemovedOnUninstall: false,
        documentTreeUri: treeUri,
        errorMessage: resolution.errorMessage,
      );
    } catch (error) {
      return DownloadStorageState(
        preferences: preferences,
        basePath: fallbackBasePath,
        rootPath: fallbackRootPath,
        isCustom: true,
        isDocumentTree: true,
        isWritable: false,
        mayBeRemovedOnUninstall: false,
        documentTreeUri: treeUri,
        errorMessage: error.toString(),
      );
    }
  }

  Future<List<Directory>> _loadCustomBaseDirectories() async {
    final DownloadBaseDirectoriesProvider? customProvider =
        _customBaseDirectoriesProvider;
    if (customProvider != null) {
      return (await customProvider()) ?? const <Directory>[];
    }
    if (!Platform.isAndroid && !_supportsInjectedAndroidPickers) {
      return const <Directory>[];
    }
    return _defaultCustomBaseDirectories(
      storageDirsProvider: _storageDirsProvider,
      cacheDirsProvider: _cacheDirsProvider,
    );
  }

  bool _mayBeRemovedOnUninstall({
    required bool isCustom,
    required String basePath,
  }) {
    if (Platform.isAndroid) {
      final String normalizedBasePath = _normalizedPath(basePath).toLowerCase();
      final String appSpecificMarker =
          '${Platform.pathSeparator}android${Platform.pathSeparator}'
          'data${Platform.pathSeparator}';
      if (normalizedBasePath.contains(appSpecificMarker)) {
        return true;
      }
      return !isCustom;
    }
    return Platform.isIOS;
  }

  Future<void> _verifyWritable(Directory rootDirectory) async {
    final File probe = File(
      _joinPath(<String>[
        rootDirectory.path,
        '.storage_probe_${DateTime.now().microsecondsSinceEpoch}',
      ]),
    );
    await probe.writeAsString('ok', flush: true);
    if (await probe.exists()) {
      await probe.delete();
    }
  }

  String _joinPath(List<String> segments) {
    return segments.join(Platform.pathSeparator);
  }

  static Future<Directory> _defaultBaseDirectory() async {
    if (Platform.isAndroid) {
      return (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  bool get _supportsInjectedAndroidPickers =>
      _storageDirsProvider != _defaultStorageDirs ||
      _cacheDirsProvider != _defaultCacheDirs;

  static Future<List<Directory>> _defaultCustomBaseDirectories({
    required StorageDirsProvider storageDirsProvider,
    required DownloadBaseDirectoriesProvider cacheDirsProvider,
  }) async {
    final Set<String> seenPaths = <String>{};
    final List<Directory> directories = <Directory>[];

    void addAll(List<Directory>? values) {
      for (final Directory directory in values ?? const <Directory>[]) {
        final String path = directory.path.trim();
        if (path.isEmpty || !seenPaths.add(path)) {
          continue;
        }
        directories.add(directory);
      }
    }

    addAll(await storageDirsProvider(null));
    addAll(await cacheDirsProvider());
    for (final StorageDirectory type in const <StorageDirectory>[
      StorageDirectory.downloads,
      StorageDirectory.documents,
      StorageDirectory.pictures,
      StorageDirectory.movies,
      StorageDirectory.dcim,
    ]) {
      addAll(await storageDirsProvider(type));
    }
    return directories;
  }

  static Future<List<Directory>?> _defaultStorageDirs(StorageDirectory? type) {
    return getExternalStorageDirectories(type: type);
  }

  static Future<List<Directory>?> _defaultCacheDirs() {
    return getExternalCacheDirectories();
  }

  String _normalizedPath(String value) => normalizeStoragePath(value);
}

  /// 归一化路径用于比较，Windows 下忽略大小写。
String normalizeStoragePath(String value) {
  final String normalized = value.trim().replaceAll(
    '/',
    Platform.pathSeparator,
  );
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
