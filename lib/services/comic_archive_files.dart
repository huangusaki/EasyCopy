import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class PickedComicArchive {
  const PickedComicArchive({
    required this.path,
    required this.name,
    required this.temporary,
  });

  final String path;
  final String name;
  final bool temporary;

  Future<void> dispose() async {
    if (temporary) {
      await File(path).parent.delete(recursive: true);
    }
  }
}

class ComicArchiveFiles {
  ComicArchiveFiles._();

  static const MethodChannel _channel = MethodChannel(
    'easy_copy/comic_archive',
  );
  static const XTypeGroup _archives = XTypeGroup(
    label: '漫画压缩包',
    extensions: <String>['zip', 'cbz'],
  );
  static const XTypeGroup _zip = XTypeGroup(
    label: 'ZIP 压缩包',
    extensions: <String>['zip'],
  );

  static Future<PickedComicArchive?> pick() async {
    if (Platform.isAndroid) {
      final Map<String, dynamic>? picked = await _channel
          .invokeMapMethod<String, dynamic>('pick');
      if (picked == null) return null;
      return PickedComicArchive(
        path: picked['path'] as String,
        name: picked['name'] as String,
        temporary: true,
      );
    }

    final XFile? picked = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_archives],
    );
    if (picked == null) return null;
    return PickedComicArchive(
      path: picked.path,
      name: picked.name,
      temporary: false,
    );
  }

  static Future<bool> save(String sourcePath, String suggestedName) async {
    final String name = suggestedName.toLowerCase().endsWith('.zip')
        ? suggestedName
        : '$suggestedName.zip';
    if (Platform.isAndroid) {
      return (await _channel.invokeMethod<bool>('save', <String, String>{
        'sourcePath': sourcePath,
        'suggestedName': name,
      }))!;
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const <XTypeGroup>[_zip],
    );
    if (location == null) return false;
    await XFile(sourcePath, mimeType: 'application/zip').saveTo(location.path);
    return true;
  }
}
