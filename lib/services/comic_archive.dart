import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:reader/services/comic_image_files.dart';

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
    if (onProgress == null && isCancelled == null) {
      return _extractIsolated(path, preview, outputDirectory, null);
    }
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
    if (onProgress == null && isCancelled == null) {
      return _encodeIsolated(chapters, outputPath, null);
    }
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
  SendPort? control;
  bool stopped = false;
  return port.listen((message) {
    if (message is SendPort) {
      control = message;
      return;
    }
    if (stopped) return;
    final (completed, total) = message as (int, int);
    try {
      onProgress?.call(completed, total);
      if (isCancelled?.call() == true) throw const ComicArchiveCancelled();
      if (completed == 0 || completed == total) control!.send(completed);
    } catch (error, stack) {
      stopped = true;
      control!.send((completed, error, stack));
    }
  });
}

class _ArchiveProgress {
  _ArchiveProgress(this.events) {
    control.listen((message) {
      if (message is (int, Object, StackTrace)) {
        stop = message;
        if (!started.isCompleted) started.complete();
        if (!finished.isCompleted) finished.complete();
      } else if (message == 0 && !started.isCompleted) {
        started.complete();
      } else if (!finished.isCompleted) {
        finished.complete();
      }
    });
    events.send(control.sendPort);
  }

  final SendPort events;
  final control = ReceivePort();
  final started = Completer<void>();
  final finished = Completer<void>();
  (int, Object, StackTrace)? stop;

  Future<void> report(int completed, int total) async {
    events.send((completed, total));
    if (completed == 0) {
      await started.future;
    } else if (completed == total) {
      await finished.future;
    } else {
      // Give cancellation a chance to arrive while ordinary progress remains one-way.
      await Future<void>.delayed(Duration.zero);
    }
    final failure = stop;
    if (failure != null) Error.throwWithStackTrace(failure.$2, failure.$3);
  }
}

// These closures only capture file data and a port, never caller UI callbacks.
Future<List<ComicArchiveChapterFiles>> _extractIsolated(
  String path,
  ComicArchivePreview preview,
  String outputDirectory,
  SendPort? progress,
) => Isolate.run(() => _extract(path, preview, outputDirectory, progress));

Future<void> _encodeIsolated(
  List<ComicArchiveChapterFiles> chapters,
  String outputPath,
  SendPort? progress,
) => Isolate.run(() => _encode(chapters, outputPath, progress));

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
        !comicImageExtensions.contains(
          _extension(name).replaceFirst('.', ''),
        )) {
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
    final compare = comicArchiveNaturalComparator();
    final folders = groups.keys.toList()..sort(compare);
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
          groups[folders[i]]!..sort(compare),
        ),
    ]);
  } finally {
    input.closeSync();
  }
}

final _sortParts = RegExp(r'\d+(?:\.\d+)?|\D+');

Comparator<String> comicArchiveNaturalComparator() {
  final cache = <String, List<(String, num?)>>{};
  List<(String, num?)> tokens(String value) => cache.putIfAbsent(
    value,
    () => [
      for (final m in _sortParts.allMatches(value.toLowerCase()))
        (m[0]!, num.tryParse(m[0]!)),
    ],
  );
  return (left, right) {
    final a = tokens(left);
    final b = tokens(right);
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      final (partA, x) = a[i];
      final (partB, y) = b[i];
      final order = x != null && y != null
          ? x.compareTo(y)
          : partA.compareTo(partB);
      if (order != 0) return order;
    }
    final lengthOrder = a.length.compareTo(b.length);
    return lengthOrder != 0 ? lengthOrder : left.compareTo(right);
  };
}

String _number(int index, int total) =>
    (index + 1).toString().padLeft(math.max(3, total.toString().length), '0');

String _chapterFolder(int index, int total, String title) {
  final clean = cleanComicPathSegment(title);
  final label = clean.isEmpty
      ? '章节'
      : String.fromCharCodes(clean.runes.take(80));
  return '${_number(index, total)} $label';
}

Future<List<ComicArchiveChapterFiles>> _extract(
  String path,
  ComicArchivePreview preview,
  String outputDirectory,
  SendPort? progress,
) async {
  final total = preview.imageCount;
  final updates = progress == null ? null : _ArchiveProgress(progress);
  final written = <String>[];
  try {
    await updates?.report(0, total);
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
          if (updates != null) written.add(outputPath);
          await updates?.report(++completed, total);
        }
        chapters.add(ComicArchiveChapterFiles(chapter.title, files));
      }
      return chapters;
    } finally {
      input.closeSync();
    }
  } finally {
    updates?.control.close();
    final stop = updates?.stop;
    if (stop != null) {
      for (final path in written.skip(stop.$1)) {
        File(path).deleteSync();
      }
    }
  }
}

Future<void> _encode(
  List<ComicArchiveChapterFiles> chapters,
  String outputPath,
  SendPort? progress,
) async {
  final total = chapters.fold(
    0,
    (count, chapter) => count + chapter.files.length,
  );
  final updates = progress == null ? null : _ArchiveProgress(progress);
  try {
    await updates?.report(0, total);
    File(outputPath).parent.createSync(recursive: true);
    final output = OutputFileStream(outputPath);
    try {
      final encoder = ZipEncoder(streamed: true)..startEncode(output);
      var completed = 0;
      for (
        var chapterIndex = 0;
        chapterIndex < chapters.length;
        chapterIndex++
      ) {
        final chapter = chapters[chapterIndex];
        final folder = _chapterFolder(
          chapterIndex,
          chapters.length,
          chapter.title,
        );
        for (var i = 0; i < chapter.files.length; i++) {
          final path = chapter.files[i];
          final extension = _extension(path);
          if (!comicImageExtensions.contains(extension.replaceFirst('.', ''))) {
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
          await updates?.report(++completed, total);
        }
      }
      encoder.endEncode();
    } finally {
      output.closeSync();
    }
  } finally {
    updates?.control.close();
  }
}
