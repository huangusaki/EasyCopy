import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/app_preferences_controller.dart';

typedef DownloadPreferencesProvider = Future<DownloadPreferences> Function();
typedef DownloadBaseDirectoryProvider = Future<Directory> Function();

class DownloadSourceUnavailableException implements Exception {
  const DownloadSourceUnavailableException([
    this.message = '原缓存目录无法访问，请重新授权或选择仅切换目录。',
  ]);

  final String message;

  @override
  String toString() => message;
}

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
    this.storageIdentity = '',
    this.comparablePath = '',
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
      storageIdentity = '',
      comparablePath = '',
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
  final String storageIdentity;
  final String comparablePath;
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
    AndroidDocumentTreeBridge? documentTreeBridge,
  }) : _preferencesController =
           preferencesController ?? AppPreferencesController.instance,
       _preferencesProvider = preferencesProvider,
       _defaultBaseDirectoryProvider =
           defaultBaseDirectoryProvider ?? _defaultBaseDirectory,
       _documentTreeBridge =
           documentTreeBridge ?? AndroidDocumentTreeBridge.instance;

  static final DownloadStorageService instance = DownloadStorageService();
  static const String downloadsDirectoryName = 'EasyCopyDownloads';

  final AppPreferencesController _preferencesController;
  final DownloadPreferencesProvider? _preferencesProvider;
  final DownloadBaseDirectoryProvider _defaultBaseDirectoryProvider;
  final AndroidDocumentTreeBridge _documentTreeBridge;

  bool get supportsCustomDirs => Platform.isAndroid || Platform.isWindows;

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
      final String canonicalPath = normalizeStoragePath(
        await rootDirectory.resolveSymbolicLinks(),
      );
      return DownloadStorageState(
        preferences: resolvedPreferences,
        basePath: baseDirectory.path,
        rootPath: rootDirectory.path,
        isCustom: isCustom,
        isDocumentTree: false,
        isWritable: true,
        storageIdentity: 'file:$canonicalPath',
        comparablePath: canonicalPath,
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

  Future<PickedDocumentTreeDirectory?> pickDocumentTreeDirectory() {
    if (!_documentTreeBridge.isSupported) {
      return Future<PickedDocumentTreeDirectory?>.value(null);
    }
    return _documentTreeBridge.pickDirectory();
  }

  String storageKeyForState(DownloadStorageState state) {
    if (state.storageIdentity.isNotEmpty) {
      return state.storageIdentity;
    }
    // Keep inaccessible locations distinct until their permission is restored.
    final String legacy = legacyStorageKeyForState(state);
    return state.isDocumentTree && !state.preferences.usePickedDirectoryAsRoot
        ? '$legacy::$downloadsDirectoryName'
        : legacy;
  }

  String legacyStorageKeyForState(DownloadStorageState state) {
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
        storageIdentity: resolution.storageIdentity,
        comparablePath: resolution.comparablePath,
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
