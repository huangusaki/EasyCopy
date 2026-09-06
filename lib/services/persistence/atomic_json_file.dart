import 'dart:convert';
import 'dart:io';

import 'package:reader/services/persistence/serial_executor.dart';

typedef JsonDirectoryProvider = Future<Directory> Function();

/// Shared JSON file protocol; model decoding and validation belong to the store.
///
/// Both files contain the original business JSON schema. A valid primary always
/// wins. The backup is published before the primary, so an interrupted write
/// leaves the previous primary readable and a successful write has two copies.
/// Operations on the same absolute path, including read/modify/write, share a
/// queue within this isolate. Temporary files are never recovery candidates.
class AtomicJsonFile<T extends Object> {
  AtomicJsonFile({
    required JsonDirectoryProvider directoryProvider,
    required String relativePath,
    required T Function(Object? json) decode,
    required Object? Function(T value) encode,
  }) : _directoryProvider = directoryProvider,
       _relativePath = relativePath,
       _decode = decode,
       _encode = encode;

  final JsonDirectoryProvider _directoryProvider;
  final String _relativePath;
  final T Function(Object? json) _decode;
  final Object? Function(T value) _encode;

  static final Map<String, _FileQueue> _queues = <String, _FileQueue>{};
  final SerialExecutor _operations = SerialExecutor();
  Future<File>? _file;

  Future<void> ensureInitialized() async {
    await _resolveFile();
  }

  Future<T?> read() => _run(_read);

  Future<void> write(T value) async {
    // Capture mutable caller data before waiting behind an earlier operation.
    final String contents = jsonEncode(_encode(value));
    await _run((File file) => _write(file, contents));
  }

  Future<void> update(T Function(T? current) change) {
    return _run((File file) async {
      final T next = change(await _read(file));
      await _write(file, jsonEncode(_encode(next)));
    });
  }

  Future<void> clear({bool Function(T? current)? when}) {
    return _run((File file) async {
      if (when != null && !when(await _read(file))) {
        return;
      }
      // Remove the backup first: interruption must not resurrect a cleared
      // primary by leaving only an older backup behind.
      await _deleteIfPresent(File('${file.path}.bak'));
      await _deleteIfPresent(File('${file.path}.bak.tmp'));
      await _deleteIfPresent(File('${file.path}.tmp'));
      await _deleteIfPresent(file);
    });
  }

  Future<File> _resolveFile() => _file ??= _initialize();

  Future<File> _initialize() async {
    try {
      final Directory directory = await _directoryProvider();
      final File file = File.fromUri(
        directory.absolute.uri.resolve(_relativePath).normalizePath(),
      );
      await file.parent.create(recursive: true);
      return file.absolute;
    } catch (_) {
      _file = null;
      rethrow;
    }
  }

  Future<R> _run<R>(Future<R> Function(File file) action) {
    return _operations.run(() => _runForPath(action));
  }

  Future<R> _runForPath<R>(Future<R> Function(File file) action) async {
    final File file = await _resolveFile();
    final String key = Platform.isWindows ? file.path.toLowerCase() : file.path;
    final _FileQueue queue = _queues.putIfAbsent(key, _FileQueue.new);
    queue.pending += 1;
    try {
      return await queue.executor.run(() => action(file));
    } finally {
      queue.pending -= 1;
      if (queue.pending == 0) {
        _queues.remove(key);
      }
    }
  }

  Future<T?> _read(File file) async {
    final _DecodedJson<T>? primary = await _readCandidate(file);
    if (primary != null) {
      return primary.value;
    }
    final _DecodedJson<T>? backup = await _readCandidate(
      File('${file.path}.bak'),
    );
    if (backup == null) {
      return null;
    }
    try {
      await _replace(file, backup.contents);
    } on FileSystemException {
      // Recovery is still useful when the directory is temporarily read-only.
    }
    return backup.value;
  }

  Future<_DecodedJson<T>?> _readCandidate(File file) async {
    try {
      final String contents = await file.readAsString();
      return _DecodedJson<T>(_decode(jsonDecode(contents)), contents);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _write(File file, String contents) async {
    await file.parent.create(recursive: true);
    // Never truncate a committed file. Renaming a flushed sibling replaces it.
    await _replace(File('${file.path}.bak'), contents);
    await _replace(file, contents);
  }

  Future<void> _replace(File file, String contents) async {
    final File temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    } finally {
      try {
        await _deleteIfPresent(temporary);
      } on FileSystemException {
        // A leftover temporary file is ignored on the next read/write.
      }
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _DecodedJson<T> {
  const _DecodedJson(this.value, this.contents);

  final T value;
  final String contents;
}

class _FileQueue {
  final SerialExecutor executor = SerialExecutor();
  int pending = 0;
}
