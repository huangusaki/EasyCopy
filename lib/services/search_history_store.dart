import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef SearchHistoryDirectoryProvider = Future<Directory> Function();

class SearchHistoryStore {
  SearchHistoryStore({
    SearchHistoryDirectoryProvider? directoryProvider,
    this.maxEntries = 10,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final SearchHistoryStore instance = SearchHistoryStore();

  final SearchHistoryDirectoryProvider _directoryProvider;
  final int maxEntries;

  Future<void>? _initialization;
  List<String> _items = <String>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  List<String> get items => List<String>.unmodifiable(_items);

  Future<void> record(String query) async {
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
  }

  Future<void> _initialize() async {
    try {
      final File file = await _historyFile();
      if (!await file.exists()) {
        _items = <String>[];
        return;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        _items = <String>[];
        return;
      }
      final List<String> items = decoded
          .whereType<String>()
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);
      _items = items.length <= maxEntries
          ? items
          : items.take(maxEntries).toList(growable: false);
    } catch (_) {
      _items = <String>[];
    }
  }

  Future<void> _persist() async {
    try {
      final File file = await _historyFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_items));
    } catch (_) {
      // Best-effort persistence only.
    }
  }

  Future<File> _historyFile() async {
    final Directory directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}search_history.json');
  }
}

