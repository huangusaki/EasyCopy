import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

typedef WallpaperDirectoryProvider = Future<Directory> Function();

class WallpaperStorage {
  WallpaperStorage({WallpaperDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final WallpaperStorage instance = WallpaperStorage();

  static const String _wallpaperDirName = 'wallpapers';
  static const Set<String> _allowedExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  };

  final WallpaperDirectoryProvider _directoryProvider;

  Directory? _cachedWallpaperDir;
  final Completer<Directory> _wallpaperDirReady = Completer<Directory>();
  bool _resolutionStarted = false;

  Future<Directory> _resolveWallpaperDir() async {
    final Directory? cached = _cachedWallpaperDir;
    if (cached != null) {
      return cached;
    }
    if (!_resolutionStarted) {
      _resolutionStarted = true;
      try {
        final Directory root = await _directoryProvider();
        final Directory wallpaperDir = Directory(
          '${root.path}${Platform.pathSeparator}$_wallpaperDirName',
        );
        if (!await wallpaperDir.exists()) {
          await wallpaperDir.create(recursive: true);
        }
        _cachedWallpaperDir = wallpaperDir;
        if (!_wallpaperDirReady.isCompleted) {
          _wallpaperDirReady.complete(wallpaperDir);
        }
      } catch (error, stackTrace) {
        if (!_wallpaperDirReady.isCompleted) {
          _wallpaperDirReady.completeError(error, stackTrace);
        }
        rethrow;
      }
    }
    return _wallpaperDirReady.future;
  }

  /// 已初始化的壁纸目录。
  Directory? get cachedWallpaperDir => _cachedWallpaperDir;

  Future<void> ensureReady() async {
    await _resolveWallpaperDir();
  }

  /// 同步解析已保存壁纸路径。
  String? resolvePathSync(String fileName) {
    final String trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final Directory? dir = _cachedWallpaperDir;
    if (dir == null) {
      return null;
    }
    return '${dir.path}${Platform.pathSeparator}$trimmed';
  }

  Future<String> resolvePath(String fileName) async {
    final Directory dir = await _resolveWallpaperDir();
    final String trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      return dir.path;
    }
    return '${dir.path}${Platform.pathSeparator}$trimmed';
  }

  /// 保存图片并返回文件名。
  Future<String> saveImage(File source) async {
    final Directory dir = await _resolveWallpaperDir();
    final String extension = _normalizedExtension(source.path);
    final String fileName = _buildUniqueFileName(extension);
    final File target = File('${dir.path}${Platform.pathSeparator}$fileName');
    await source.copy(target.path);
    return fileName;
  }

  Future<void> deleteFile(String fileName) async {
    final String trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final Directory dir = await _resolveWallpaperDir();
      final File file = File('${dir.path}${Platform.pathSeparator}$trimmed');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 清理失败不影响主流程。
    }
  }

  /// 清理未使用的壁纸文件。
  Future<void> pruneExcept(String keepFileName) async {
    try {
      final Directory dir = await _resolveWallpaperDir();
      final String keep = keepFileName.trim();
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        final String name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (name == keep) {
          continue;
        }
        try {
          await entity.delete();
        } catch (_) {
          // 跳过被占用文件。
        }
      }
    } catch (_) {
      // 清理失败不影响主流程。
    }
  }

  String _normalizedExtension(String path) {
    final int dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == path.length - 1) {
      return '.jpg';
    }
    final String ext = path.substring(dotIndex).toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      return '.jpg';
    }
    return ext;
  }

  String _buildUniqueFileName(String extension) {
    final int millis = DateTime.now().millisecondsSinceEpoch;
    final int suffix = math.Random().nextInt(0xFFFFFF);
    return 'wp_${millis}_${suffix.toRadixString(16).padLeft(6, '0')}$extension';
  }
}
