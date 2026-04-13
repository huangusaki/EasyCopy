import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef ReaderProgressDirectoryProvider = Future<Directory> Function();
typedef ReaderProgressNowProvider = DateTime Function();

enum ReaderProgressMode { scroll, paged }

@immutable
class ReaderPosition {
  const ReaderPosition({
    required this.mode,
    this.offset = 0,
    this.pageIndex = 0,
    this.pageOffset = 0,
  });

  factory ReaderPosition.scroll({double offset = 0}) {
    return ReaderPosition(mode: ReaderProgressMode.scroll, offset: offset);
  }

  factory ReaderPosition.paged({int pageIndex = 0, double pageOffset = 0}) {
    return ReaderPosition(
      mode: ReaderProgressMode.paged,
      pageIndex: pageIndex,
      pageOffset: pageOffset,
    );
  }

  factory ReaderPosition.fromJson(Map<String, Object?> json) {
    final String rawMode = (json['mode'] as String?)?.trim() ?? '';
    if (rawMode == 'paged' || json.containsKey('pageIndex')) {
      return ReaderPosition.paged(
        pageIndex: ((json['pageIndex'] as num?) ?? 0).round().clamp(0, 999999),
        pageOffset: ((json['pageOffset'] as num?) ?? 0).toDouble(),
      );
    }
    return ReaderPosition.scroll(
      offset: ((json['offset'] as num?) ?? 0).toDouble(),
    );
  }

  final ReaderProgressMode mode;
  final double offset;
  final int pageIndex;
  final double pageOffset;

  bool get isScroll => mode == ReaderProgressMode.scroll;

  bool get isPaged => mode == ReaderProgressMode.paged;

  ReaderPosition copyWith({
    ReaderProgressMode? mode,
    double? offset,
    int? pageIndex,
    double? pageOffset,
  }) {
    return ReaderPosition(
      mode: mode ?? this.mode,
      offset: offset ?? this.offset,
      pageIndex: pageIndex ?? this.pageIndex,
      pageOffset: pageOffset ?? this.pageOffset,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': switch (mode) {
        ReaderProgressMode.scroll => 'scroll',
        ReaderProgressMode.paged => 'paged',
      },
      'offset': offset,
      'pageIndex': pageIndex,
      'pageOffset': pageOffset,
    };
  }
}

@immutable
class ReaderProgressEntry {
  const ReaderProgressEntry({
    required this.key,
    required this.position,
    required this.updatedAt,
    this.catalogPathKey = '',
    this.chapterPathKey = '',
  });

  factory ReaderProgressEntry.fromRow(Map<String, Object?> row) {
    return ReaderProgressEntry(
      key: (row['key'] as String?)?.trim() ?? '',
      position: ReaderPosition(
        mode: ((row['mode'] as String?)?.trim() ?? 'scroll') == 'paged'
            ? ReaderProgressMode.paged
            : ReaderProgressMode.scroll,
        offset: ((row['offset'] as num?) ?? 0).toDouble(),
        pageIndex: ((row['page_index'] as num?) ?? 0).round().clamp(0, 999999),
        pageOffset: ((row['page_offset'] as num?) ?? 0).toDouble(),
      ),
      catalogPathKey: (row['catalog_path_key'] as String?)?.trim() ?? '',
      chapterPathKey: (row['chapter_path_key'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String key;
  final ReaderPosition position;
  final DateTime updatedAt;
  final String catalogPathKey;
  final String chapterPathKey;

  ReaderProgressEntry copyWith({
    String? key,
    ReaderPosition? position,
    DateTime? updatedAt,
    String? catalogPathKey,
    String? chapterPathKey,
  }) {
    return ReaderProgressEntry(
      key: key ?? this.key,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
      catalogPathKey: catalogPathKey ?? this.catalogPathKey,
      chapterPathKey: chapterPathKey ?? this.chapterPathKey,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'key': key,
      'mode': switch (position.mode) {
        ReaderProgressMode.scroll => 'scroll',
        ReaderProgressMode.paged => 'paged',
      },
      'offset': position.offset,
      'page_index': position.pageIndex,
      'page_offset': position.pageOffset,
      'catalog_path_key': catalogPathKey,
      'chapter_path_key': chapterPathKey,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ReaderProgressStore {
  ReaderProgressStore({
    ReaderProgressDirectoryProvider? directoryProvider,
    ReaderProgressNowProvider? now,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static final ReaderProgressStore instance = ReaderProgressStore();

  static const int maxEntries = 60;
  static const String _tableName = 'reader_progress';
  static const String _databaseName = 'reader_state.db';
  static const String _catalogUpdatedAtIndexName =
      'idx_reader_progress_catalog_updated_at';
  static const Map<String, String> _requiredColumnDefinitions =
      <String, String>{
        'mode': "TEXT NOT NULL DEFAULT 'scroll'",
        'offset': 'REAL NOT NULL DEFAULT 0',
        'page_index': 'INTEGER NOT NULL DEFAULT 0',
        'page_offset': 'REAL NOT NULL DEFAULT 0',
        'catalog_path_key': "TEXT NOT NULL DEFAULT ''",
        'chapter_path_key': "TEXT NOT NULL DEFAULT ''",
        'updated_at': "TEXT NOT NULL DEFAULT ''",
      };
  static const String _createTableStatement =
      '''
    CREATE TABLE IF NOT EXISTS $_tableName (
      key TEXT PRIMARY KEY,
      mode TEXT NOT NULL DEFAULT 'scroll',
      offset REAL NOT NULL DEFAULT 0,
      page_index INTEGER NOT NULL DEFAULT 0,
      page_offset REAL NOT NULL DEFAULT 0,
      catalog_path_key TEXT NOT NULL DEFAULT '',
      chapter_path_key TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL DEFAULT ''
    )
  ''';

  static String progressKeyForChapterHref(String chapterHref) {
    return _pathKeyFromValue(chapterHref);
  }

  final ReaderProgressDirectoryProvider _directoryProvider;
  final ReaderProgressNowProvider _now;
  final sqflite.DatabaseFactory _databaseFactory;

  Future<void>? _initialization;
  sqflite.Database? _database;
  List<ReaderProgressEntry> _entries = <ReaderProgressEntry>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<ReaderPosition?> readPosition(String key) async {
    await ensureInitialized();
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }
    final ReaderProgressEntry? exactEntry = _entryForKey(normalizedKey);
    if (exactEntry != null) {
      return exactEntry.position;
    }
    final ReaderProgressEntry? migratedEntry = await _migrateLegacyEntryForKey(
      normalizedKey,
    );
    return migratedEntry?.position;
  }

  Future<double?> readOffset(String key) async {
    final ReaderPosition? position = await readPosition(key);
    if (position == null || !position.isScroll) {
      return null;
    }
    return position.offset;
  }

  /// Returns the most recently updated progress entry, or `null` if the
  /// store is empty.
  ReaderProgressEntry? get latestEntry =>
      _entries.isEmpty ? null : _entries.first;

  String? latestChapterPathKeyForCatalog(String catalogHref) {
    final String targetCatalogPathKey = _pathKey(catalogHref);
    if (targetCatalogPathKey.isEmpty) {
      return null;
    }
    for (final ReaderProgressEntry entry in _entries) {
      if (entry.catalogPathKey == targetCatalogPathKey &&
          entry.chapterPathKey.isNotEmpty) {
        return entry.chapterPathKey;
      }
    }
    return null;
  }

  Future<void> markChapterOpened({
    required String key,
    required String catalogHref,
    required String chapterHref,
  }) async {
    await ensureInitialized();
    final String normalizedKey = _normalizedEntryKey(
      key,
      chapterHref: chapterHref,
    );
    if (normalizedKey.isEmpty) {
      return;
    }
    final String catalogPathKey = _pathKey(catalogHref);
    final String chapterPathKey = _pathKey(chapterHref);
    if (catalogPathKey.isEmpty || chapterPathKey.isEmpty) {
      return;
    }
    final DateTime now = _now();
    final ReaderProgressEntry? existingEntry =
        _entryForKey(normalizedKey) ??
        await _migrateLegacyEntryForKey(normalizedKey);
    final ReaderProgressEntry nextEntry = existingEntry != null
        ? existingEntry.copyWith(
            updatedAt: now,
            catalogPathKey: catalogPathKey,
            chapterPathKey: chapterPathKey,
          )
        : ReaderProgressEntry(
            key: normalizedKey,
            position: ReaderPosition.scroll(offset: 0),
            updatedAt: now,
            catalogPathKey: catalogPathKey,
            chapterPathKey: chapterPathKey,
          );
    await _persistCanonicalEntry(nextEntry);
    await _trimPersistedEntries();
  }

  Future<void> writePosition(
    String key,
    ReaderPosition position, {
    String catalogHref = '',
    String chapterHref = '',
  }) async {
    await ensureInitialized();
    final String normalizedKey = _normalizedEntryKey(
      key,
      chapterHref: chapterHref,
    );
    if (normalizedKey.isEmpty) {
      return;
    }
    final ReaderPosition normalizedPosition = _normalizePosition(position);
    final String catalogPathKey = _pathKey(catalogHref);
    final String chapterPathKey = _pathKey(chapterHref);
    final DateTime now = _now();
    final ReaderProgressEntry? existingEntry =
        _entryForKey(normalizedKey) ??
        await _migrateLegacyEntryForKey(normalizedKey);
    final ReaderProgressEntry nextEntry = existingEntry != null
        ? existingEntry.copyWith(
            position: normalizedPosition,
            updatedAt: now,
            catalogPathKey: catalogPathKey.isEmpty
                ? existingEntry.catalogPathKey
                : catalogPathKey,
            chapterPathKey: chapterPathKey.isEmpty
                ? existingEntry.chapterPathKey
                : chapterPathKey,
          )
        : ReaderProgressEntry(
            key: normalizedKey,
            position: normalizedPosition,
            updatedAt: now,
            catalogPathKey: catalogPathKey,
            chapterPathKey: chapterPathKey,
          );
    await _persistCanonicalEntry(nextEntry);
    await _trimPersistedEntries();
  }

  Future<void> writeOffset(String key, double offset) {
    return writePosition(key, ReaderPosition.scroll(offset: offset));
  }

  Future<void> remove(String key) async {
    await ensureInitialized();
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    _entries.removeWhere(
      (ReaderProgressEntry entry) => entry.key == normalizedKey,
    );
    await _database!.delete(
      _tableName,
      where: 'key = ?',
      whereArgs: <Object>[normalizedKey],
    );
  }

  Future<void> close() async {
    final sqflite.Database? database = _database;
    _database = null;
    _initialization = null;
    _entries = <ReaderProgressEntry>[];
    if (database == null) {
      return;
    }
    try {
      await database.close();
    } catch (_) {
      return;
    }
  }

  ReaderProgressEntry? _entryForKey(String key) {
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }
    return _entries.cast<ReaderProgressEntry?>().firstWhere(
      (ReaderProgressEntry? entry) => entry?.key == normalizedKey,
      orElse: () => null,
    );
  }

  ReaderProgressEntry? _latestEntryForChapterPathKey(String chapterPathKey) {
    final String normalizedChapterPathKey = chapterPathKey.trim();
    if (normalizedChapterPathKey.isEmpty) {
      return null;
    }
    return _entries.cast<ReaderProgressEntry?>().firstWhere(
      (ReaderProgressEntry? entry) =>
          entry?.chapterPathKey == normalizedChapterPathKey,
      orElse: () => null,
    );
  }

  Future<ReaderProgressEntry?> _migrateLegacyEntryForKey(String key) async {
    final String canonicalChapterPathKey = progressKeyForChapterHref(key);
    if (canonicalChapterPathKey.isEmpty) {
      return null;
    }
    final ReaderProgressEntry? legacyEntry = _latestEntryForChapterPathKey(
      canonicalChapterPathKey,
    );
    if (legacyEntry == null) {
      return null;
    }
    final ReaderProgressEntry canonicalEntry = legacyEntry.copyWith(
      key: canonicalChapterPathKey,
      chapterPathKey: canonicalChapterPathKey,
    );
    await _persistCanonicalEntry(canonicalEntry);
    await _trimPersistedEntries();
    return canonicalEntry;
  }

  Future<void> _initialize() async {
    final String path = await _databasePath();
    _database = await _databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onCreate: (sqflite.Database db, int version) async {
          await _ensureDatabaseSchema(db);
        },
        onOpen: (sqflite.Database db) async {
          await _ensureDatabaseSchema(db);
        },
      ),
    );

    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      orderBy: 'updated_at DESC',
    );
    _entries = rows.map(ReaderProgressEntry.fromRow).toList(growable: true);
    _sortEntries();
    await _trimPersistedEntries();
  }

  Future<String> _databasePath() async {
    final Directory directory = await _directoryProvider();
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$_databaseName';
  }

  ReaderPosition _normalizePosition(ReaderPosition position) {
    if (position.isPaged) {
      return ReaderPosition.paged(
        pageIndex: position.pageIndex < 0 ? 0 : position.pageIndex,
        pageOffset: position.pageOffset.isFinite && position.pageOffset >= 0
            ? position.pageOffset
            : 0,
      );
    }
    return ReaderPosition.scroll(
      offset: position.offset.isFinite && position.offset >= 0
          ? position.offset
          : 0,
    );
  }

  String _pathKey(String href) {
    return _pathKeyFromValue(href);
  }

  String _normalizedEntryKey(String key, {String chapterHref = ''}) {
    final String chapterPathKey = _pathKey(chapterHref);
    if (chapterPathKey.isNotEmpty) {
      return chapterPathKey;
    }
    return key.trim();
  }

  void _replaceEntry(ReaderProgressEntry nextEntry) {
    final int existingIndex = _entries.indexWhere(
      (ReaderProgressEntry entry) => entry.key == nextEntry.key,
    );
    if (existingIndex >= 0) {
      _entries[existingIndex] = nextEntry;
    } else {
      _entries.add(nextEntry);
    }
    _sortEntries();
  }

  void _sortEntries() {
    _entries.sort(
      (ReaderProgressEntry left, ReaderProgressEntry right) =>
          right.updatedAt.compareTo(left.updatedAt),
    );
  }

  Future<void> _persistEntry(ReaderProgressEntry entry) {
    return _database!.insert(
      _tableName,
      entry.toRow(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<void> _persistCanonicalEntry(ReaderProgressEntry entry) async {
    final String normalizedChapterPathKey = entry.chapterPathKey.trim();
    final List<ReaderProgressEntry> duplicateEntries =
        normalizedChapterPathKey.isEmpty
        ? const <ReaderProgressEntry>[]
        : _entries
              .where(
                (ReaderProgressEntry candidate) =>
                    candidate.chapterPathKey == normalizedChapterPathKey &&
                    candidate.key != entry.key,
              )
              .toList(growable: false);
    if (duplicateEntries.isNotEmpty) {
      final Set<String> duplicateKeys = duplicateEntries
          .map((ReaderProgressEntry candidate) => candidate.key)
          .where((String candidate) => candidate.trim().isNotEmpty)
          .toSet();
      _entries.removeWhere(
        (ReaderProgressEntry candidate) =>
            duplicateKeys.contains(candidate.key),
      );
      if (duplicateKeys.isNotEmpty) {
        final sqflite.Batch batch = _database!.batch();
        for (final String duplicateKey in duplicateKeys) {
          batch.delete(
            _tableName,
            where: 'key = ?',
            whereArgs: <Object>[duplicateKey],
          );
        }
        await batch.commit(noResult: true);
      }
    }
    _replaceEntry(entry);
    await _persistEntry(entry);
  }

  Future<void> _ensureDatabaseSchema(sqflite.Database db) async {
    await db.execute(_createTableStatement);
    final Set<String> existingColumns = await _tableColumns(db);
    for (final MapEntry<String, String> entry
        in _requiredColumnDefinitions.entries) {
      if (existingColumns.contains(entry.key)) {
        continue;
      }
      await db.execute(
        'ALTER TABLE $_tableName ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_catalogUpdatedAtIndexName
      ON $_tableName (catalog_path_key, updated_at DESC)
    ''');
  }

  Future<Set<String>> _tableColumns(sqflite.Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'PRAGMA table_info($_tableName)',
    );
    return rows
        .map(
          (Map<String, Object?> row) => (row['name'] as String?)?.trim() ?? '',
        )
        .where((String name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _trimPersistedEntries() async {
    if (_entries.length <= maxEntries) {
      return;
    }
    final List<ReaderProgressEntry> removedEntries = _entries
        .skip(maxEntries)
        .toList(growable: false);
    _entries = _entries.take(maxEntries).toList(growable: true);
    final sqflite.Batch batch = _database!.batch();
    for (final ReaderProgressEntry entry in removedEntries) {
      batch.delete(
        _tableName,
        where: 'key = ?',
        whereArgs: <Object>[entry.key],
      );
    }
    await batch.commit(noResult: true);
  }
}

String _pathKeyFromValue(String href) {
  final Uri? uri = Uri.tryParse(href.trim());
  if (uri == null) {
    return '';
  }
  return uri.path.trim();
}
