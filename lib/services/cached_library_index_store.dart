import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

typedef IndexDirProvider = Future<Directory> Function();

class CachedLibraryIndexStore {
  CachedLibraryIndexStore({IndexDirProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final CachedLibraryIndexStore instance = CachedLibraryIndexStore();

  final IndexDirProvider _directoryProvider;

  Future<void>? _initialization;
  Directory? _directory;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<List<Map<String, Object?>>?> read(String storageKey) async {
    await ensureInitialized();
    final File file = _fileForKey(storageKey);
    if (!await file.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final String persistedStorageKey =
          (decoded['storageKey'] as String?)?.trim() ?? '';
      if (persistedStorageKey != storageKey) {
        return null;
      }
      final List<Object?> rawEntries =
          (decoded['entries'] as List<Object?>?) ?? const <Object?>[];
      return rawEntries
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> entry) => entry.map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String storageKey,
    List<Map<String, Object?>> entries,
  ) async {
    await ensureInitialized();
    final File file = _fileForKey(storageKey);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'storageKey': storageKey,
        'entries': entries,
      }),
      flush: true,
    );
  }

  Future<void> copy(String fromStorageKey, String toStorageKey) async {
    final List<Map<String, Object?>>? entries = await read(fromStorageKey);
    if (entries == null) {
      return;
    }
    await write(toStorageKey, entries);
  }

  Future<void> clear(String storageKey) async {
    await ensureInitialized();
    final File file = _fileForKey(storageKey);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _initialize() async {
    final Directory directory = await _directoryProvider();
    _directory = Directory(
      '${directory.path}${Platform.pathSeparator}cached_library_index',
    );
    await _directory!.create(recursive: true);
  }

  File _fileForKey(String storageKey) {
    final String hash = sha1.convert(utf8.encode(storageKey)).toString();
    return File('${_directory!.path}${Platform.pathSeparator}$hash.json');
  }
}
