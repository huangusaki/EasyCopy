import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';
import 'package:reader/services/persistence/serial_executor.dart';

typedef SearchHistoryDirectoryProvider = Future<Directory> Function();

class SearchHistoryStore {
  SearchHistoryStore({
    SearchHistoryDirectoryProvider? directoryProvider,
    this.maxEntries = 10,
  }) : _file = AtomicJsonFile<List<String>>(
         directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
         relativePath: 'search_history.json',
         decode: (Object? json) => (json as List)
             .whereType<String>()
             .map((String value) => value.trim())
             .where((String value) => value.isNotEmpty)
             .toList(growable: false),
         encode: (List<String> items) => items,
       );

  static final SearchHistoryStore instance = SearchHistoryStore();

  final AtomicJsonFile<List<String>> _file;
  final SerialExecutor _operations = SerialExecutor();
  final int maxEntries;

  Future<void>? _initialization;
  List<String> _items = <String>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  List<String> get items => List<String>.unmodifiable(_items);

  Future<void> record(String query) {
    return _operations.run(() async {
      final String normalized = query.trim();
      if (normalized.isEmpty) {
        return;
      }
      await ensureInitialized();
      final List<String> next = <String>[
        normalized,
        ..._items.where((String item) => item != normalized),
      ];
      _items = next.length <= maxEntries
          ? next
          : next.take(maxEntries).toList(growable: false);
      await _persist();
    });
  }

  Future<void> remove(String query) {
    return _operations.run(() async {
      final String normalized = query.trim();
      if (normalized.isEmpty) {
        return;
      }
      await ensureInitialized();
      final List<String> next = _items
          .where((String item) => item != normalized)
          .toList(growable: false);
      if (next.length == _items.length) {
        return;
      }
      _items = next;
      await _persist();
    });
  }

  Future<void> clear() {
    return _operations.run(() async {
      await ensureInitialized();
      if (_items.isEmpty) {
        return;
      }
      _items = <String>[];
      await _persist();
    });
  }

  Future<void> _initialize() async {
    try {
      final List<String> items = await _file.read() ?? <String>[];
      _items = items.take(maxEntries).toList(growable: false);
    } catch (_) {
      _items = <String>[];
    }
  }

  Future<void> _persist() async {
    try {
      await _file.write(_items);
    } catch (_) {
      // Best-effort persistence only.
    }
  }
}
