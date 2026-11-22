import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';
import 'package:reader/services/persistence/serial_executor.dart';

typedef SearchHistoryDirectoryProvider = Future<Directory> Function();

class SearchHistoryStore extends ChangeNotifier {
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
  List<String> _items = const <String>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  List<String> get items => _items;

  Future<void> record(String query) async {
    await ensureInitialized();
    final term = query.trim();
    if (term.isEmpty || (_items.isNotEmpty && _items.first == term)) return;
    await _replace(
      [term, ..._items.where((item) => item != term)].take(maxEntries),
    );
  }

  Future<void> remove(String query) async {
    await ensureInitialized();
    final term = query.trim();
    if (!_items.contains(term)) return;
    await _replace(_items.where((item) => item != term));
  }

  Future<void> clear() async {
    await ensureInitialized();
    if (_items.isNotEmpty) await _replace(const []);
  }

  Future<void> _replace(Iterable<String> next) {
    final snapshot = _items = List.unmodifiable(next);
    final pending = _operations.run(() async {
      try {
        await _file.write(snapshot);
      } catch (_) {
        // Search history remains available in memory if the disk is unavailable.
      }
    });
    notifyListeners();
    return pending;
  }

  Future<void> _initialize() async {
    try {
      final List<String> items = await _file.read() ?? <String>[];
      _items = List.unmodifiable(items.take(maxEntries));
    } catch (_) {
      _items = const <String>[];
    }
  }
}
