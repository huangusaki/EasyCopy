import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

typedef IndexDirProvider = Future<Directory> Function();

class CachedLibraryIndexStore {
  CachedLibraryIndexStore({IndexDirProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final CachedLibraryIndexStore instance = CachedLibraryIndexStore();

  final IndexDirProvider _directoryProvider;
  final Map<String, AtomicJsonFile<_LibraryIndex>> _files =
      <String, AtomicJsonFile<_LibraryIndex>>{};

  Future<void> ensureInitialized() async {
    final Directory directory = await _directoryProvider();
    await Directory(
      '${directory.path}${Platform.pathSeparator}cached_library_index',
    ).create(recursive: true);
  }

  Future<List<Map<String, Object?>>?> read(String storageKey) async {
    final _LibraryIndex? index = await _fileForKey(storageKey).read();
    return index?.storageKey == storageKey ? index!.entries : null;
  }

  Future<void> write(String storageKey, List<Map<String, Object?>> entries) =>
      _fileForKey(storageKey).write(_LibraryIndex(storageKey, entries));

  Future<void> copy(String fromStorageKey, String toStorageKey) async {
    final List<Map<String, Object?>>? entries = await read(fromStorageKey);
    if (entries != null) {
      await write(toStorageKey, entries);
    }
  }

  Future<void> clear(String storageKey) => _fileForKey(storageKey).clear();

  AtomicJsonFile<_LibraryIndex> _fileForKey(String storageKey) {
    return _files.putIfAbsent(storageKey, () {
      final String hash = sha1.convert(utf8.encode(storageKey)).toString();
      return AtomicJsonFile<_LibraryIndex>(
        directoryProvider: _directoryProvider,
        relativePath: 'cached_library_index/$hash.json',
        decode: _LibraryIndex.fromJson,
        encode: (_LibraryIndex index) => index.toJson(),
      );
    });
  }
}

class _LibraryIndex {
  const _LibraryIndex(this.storageKey, this.entries);

  factory _LibraryIndex.fromJson(Object? value) {
    final Map<String, Object?> json = Map<String, Object?>.from(value as Map);
    return _LibraryIndex(
      (json['storageKey'] as String?)?.trim() ?? '',
      ((json['entries'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map>()
          .map((Map entry) => Map<String, Object?>.from(entry))
          .toList(growable: false),
    );
  }

  final String storageKey;
  final List<Map<String, Object?>> entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'storageKey': storageKey,
    'entries': entries,
  };
}
