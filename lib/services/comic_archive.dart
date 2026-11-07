import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';

class ComicArchiveChapter {
  const ComicArchiveChapter(this.title, this.entries);

  final String title;
  final List<String> entries;
}

class ComicArchivePreview {
  const ComicArchivePreview(this.title, this.chapters);

  final String title;
  final List<ComicArchiveChapter> chapters;

  int get imageCount =>
      chapters.fold(0, (count, chapter) => count + chapter.entries.length);
}

class ComicArchiveChapterFiles {
  const ComicArchiveChapterFiles(this.title, this.files);

  final String title;
  final List<String> files;
}

class ComicArchiveCancelled implements Exception {
  const ComicArchiveCancelled();

  @override
  String toString() => '操作已取消';
}

class ComicArchive {
  const ComicArchive._();

  static Future<ComicArchivePreview> inspect(
    String path, {
    required String title,
  }) {
    return Isolate.run(() => _inspect(path, title));
  }

  static Future<List<ComicArchiveChapterFiles>> extract(
    String path,
    ComicArchivePreview preview,
    String outputDirectory, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final progress = ReceivePort();
    final subscription = _listenProgress(progress, onProgress, isCancelled);
    try {
      return await _extractIsolated(
        path,
        preview,
        outputDirectory,
        progress.sendPort,
      );
    } finally {
      await subscription.cancel();
      progress.close();
    }
  }

  static Future<void> encode(
    List<ComicArchiveChapterFiles> chapters,
    String outputPath, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final progress = ReceivePort();
    final subscription = _listenProgress(progress, onProgress, isCancelled);
    try {
      await _encodeIsolated(chapters, outputPath, progress.sendPort);
    } finally {
      await subscription.cancel();
      progress.close();
    }
  }
}

StreamSubscription<dynamic> _listenProgress(
  ReceivePort port,
  void Function(int, int)? onProgress,
  bool Function()? isCancelled,
) {
  return port.listen((message) {
    final (completed, total, reply) = message as (int, int, SendPort);
    try {
      onProgress?.call(completed, total);
      reply.send(isCancelled?.call() ?? false);
    } catch (error, stack) {
      reply.send((error, stack));
    }
  });
}

Future<void> _checkpoint(SendPort progress, int completed, int total) async {
  final reply = ReceivePort();
  try {
    progress.send((completed, total, reply.sendPort));
    final response = await reply.first;
    if (response == true) throw const ComicArchiveCancelled();
    if (response is (Object, StackTrace)) {
      Error.throwWithStackTrace(response.$1, response.$2);
    }
  } finally {
    reply.close();
  }
}

// These closures only capture file data and a port, never caller UI callbacks.
Future<List<ComicArchiveChapterFiles>> _extractIsolated(
  String path,
  ComicArchivePreview preview,
  String outputDirectory,
  SendPort progress,
) => Isolate.run(() => _extract(path, preview, outputDirectory, progress));

Future<void> _encodeIsolated(
  List<ComicArchiveChapterFiles> chapters,
  String outputPath,
  SendPort progress,
) => Isolate.run(() => _encode(chapters, outputPath, progress));

const _imageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.avif',
};

String _extension(String name) {
  final leaf = name.replaceAll('\\', '/').split('/').last;
  final dot = leaf.lastIndexOf('.');
  return dot < 0 ? '' : leaf.substring(dot).toLowerCase();
}

Map<String, ZipFileHeader> _imageHeaders(
  InputFileStream input, {
  required bool files,
}) {
  final directory = ZipDirectory();
  final images = <String, ZipFileHeader>{};
  for (final header in directory.headers(input, verify: true, files: files)) {
    final mode = (header.externalFileAttributes >> 16) & 0xf000;
    if (mode == 0xa000) {
      throw const FormatException('压缩包不能包含符号链接');
    }
    final name = header.filename.replaceAll('\\', '/');
    final parts = name.split('/');
    if (name.endsWith('/') ||
        mode == 0x4000 ||
        (header.versionMadeBy >> 8 == 0 &&
            header.externalFileAttributes & 0x10 != 0) ||
        parts.any((part) => part.toLowerCase() == '__macosx') ||
        parts.last.startsWith('._') ||
        !_imageExtensions.contains(_extension(name))) {
      continue;
    }
    if (header.generalPurposeBitFlag & 1 != 0) {
      throw const FormatException('不支持加密压缩包');
    }
    images[header.filename] = header;
  }
  if (directory.filePosition < 0) {
    throw const FormatException('不是有效的 ZIP 或 CBZ 文件');
  }
  if (images.isEmpty) throw const FormatException('压缩包中没有可用图片');
  return images;
}

ComicArchivePreview _inspect(String path, String title) {
  final input = InputFileStream(path);
  try {
    final groups = <String, List<String>>{};
    for (final name in _imageHeaders(input, files: false).keys) {
      final normalized = name.replaceAll('\\', '/');
      final slash = normalized.lastIndexOf('/');
      final folder = slash < 0 ? '' : normalized.substring(0, slash);
      groups.putIfAbsent(folder, () => <String>[]).add(name);
    }
    final folders = groups.keys.toList()..sort(comicArchiveNaturalCompare);
    final segments = folders
        .map((folder) => folder.isEmpty ? <String>[] : folder.split('/'))
        .toList();
    var shared = segments.first.length;
    for (final parts in segments.skip(1)) {
      shared = math.min(shared, parts.length);
      for (var i = 0; i < shared; i++) {
        if (parts[i] != segments.first[i]) {
          shared = i;
          break;
        }
      }
    }
    if (folders.length == 1 && shared > 0) shared--;
    final titles = segments
        .map((parts) => parts.skip(shared).join('/'))
        .toList();
    final numbered =
        folders.every((folder) => folder.isNotEmpty) &&
        titles.asMap().entries.every((entry) {
          final prefix = '${_number(entry.key, titles.length)} ';
          return !entry.value.contains('/') &&
              entry.value.startsWith(prefix) &&
              entry.value.length > prefix.length;
        });
    return ComicArchivePreview(title, <ComicArchiveChapter>[
      for (var i = 0; i < folders.length; i++)
        ComicArchiveChapter(
          numbered
              ? titles[i].substring(_number(i, titles.length).length + 1)
              : titles[i].isEmpty
              ? title
              : titles[i],
          groups[folders[i]]!..sort(comicArchiveNaturalCompare),
        ),
    ]);
  } finally {
    input.closeSync();
  }
}

final _sortParts = RegExp(r'\d+(?:\.\d+)?|\D+');

int comicArchiveNaturalCompare(String left, String right) {
  final a = _sortParts
      .allMatches(left.toLowerCase())
      .map((m) => m[0]!)
      .toList();
  final b = _sortParts
      .allMatches(right.toLowerCase())
      .map((m) => m[0]!)
      .toList();
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    final x = num.tryParse(a[i]);
    final y = num.tryParse(b[i]);
    final order = x != null && y != null
        ? x.compareTo(y)
        : a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  final lengthOrder = a.length.compareTo(b.length);
  return lengthOrder != 0 ? lengthOrder : left.compareTo(right);
}

String _number(int index, int total) =>
    (index + 1).toString().padLeft(math.max(3, total.toString().length), '0');

String _chapterFolder(int index, int total, String title) {
  final clean = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  final label = clean.isEmpty
      ? '章节'
      : String.fromCharCodes(clean.runes.take(80));
  return '${_number(index, total)} $label';
}

Future<List<ComicArchiveChapterFiles>> _extract(
  String path,
  ComicArchivePreview preview,
  String outputDirectory,
  SendPort progress,
) async {
  final total = preview.imageCount;
  await _checkpoint(progress, 0, total);
  final input = InputFileStream(path);
  try {
    final entries = _imageHeaders(input, files: true);
    final root = Directory(outputDirectory).absolute;
    root.createSync(recursive: true);
    final chapters = <ComicArchiveChapterFiles>[];
    var completed = 0;
    for (
      var chapterIndex = 0;
      chapterIndex < preview.chapters.length;
      chapterIndex++
    ) {
      final chapter = preview.chapters[chapterIndex];
      final directory = Directory(
        '${root.path}/${_chapterFolder(chapterIndex, preview.chapters.length, chapter.title)}',
      )..createSync();
      final files = <String>[];
      for (var i = 0; i < chapter.entries.length; i++) {
        final name = chapter.entries[i];
        final header = entries[name];
        if (header == null) {
          throw const FormatException('压缩包内容已变化，请重新选择');
        }
        final file = header.file!
          ..verify = true
          ..throwOnError = true;
        final outputPath =
            '${directory.path}/${_number(i, chapter.entries.length)}${_extension(name)}';
        final output = OutputFileStream(outputPath);
        try {
          file.decompress(output);
        } finally {
          output.closeSync();
        }
        files.add(outputPath);
        await _checkpoint(progress, ++completed, total);
      }
      chapters.add(ComicArchiveChapterFiles(chapter.title, files));
    }
    return chapters;
  } finally {
    input.closeSync();
  }
}

Future<void> _encode(
  List<ComicArchiveChapterFiles> chapters,
  String outputPath,
  SendPort progress,
) async {
  final total = chapters.fold(
    0,
    (count, chapter) => count + chapter.files.length,
  );
  await _checkpoint(progress, 0, total);
  File(outputPath).parent.createSync(recursive: true);
  final output = OutputFileStream(outputPath);
  try {
    final encoder = ZipEncoder(streamed: true)..startEncode(output);
    var completed = 0;
    for (var chapterIndex = 0; chapterIndex < chapters.length; chapterIndex++) {
      final chapter = chapters[chapterIndex];
      final folder = _chapterFolder(
        chapterIndex,
        chapters.length,
        chapter.title,
      );
      for (var i = 0; i < chapter.files.length; i++) {
        final path = chapter.files[i];
        final extension = _extension(path);
        if (!_imageExtensions.contains(extension)) {
          throw FormatException('不支持的图片格式：$extension');
        }
        if (FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FormatException('图片不能是符号链接');
        }
        final input = InputFileStream(path);
        try {
          encoder.add(
            ArchiveFile.stream(
              '$folder/${_number(i, chapter.files.length)}$extension',
              input,
            )..compression = CompressionType.none,
            autoClose: false,
          );
        } finally {
          input.closeSync();
        }
        await _checkpoint(progress, ++completed, total);
      }
    }
    encoder.endEncode();
  } finally {
    output.closeSync();
  }
}
