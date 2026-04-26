import 'dart:async';
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
    required this.comicPathKey,
    required this.position,
    required this.updatedAt,
    this.chapterPathKey = '',
  });

  factory ReaderProgressEntry.fromRow(Map<String, Object?> row) {
    return ReaderProgressEntry(
      comicPathKey: (row['comic_path_key'] as String?)?.trim() ?? '',
      chapterPathKey: (row['chapter_path_key'] as String?)?.trim() ?? '',
      position: ReaderPosition(
        mode: ((row['mode'] as String?)?.trim() ?? 'scroll') == 'paged'
            ? ReaderProgressMode.paged
            : ReaderProgressMode.scroll,
        offset: ((row['offset'] as num?) ?? 0).toDouble(),
        pageIndex: ((row['page_index'] as num?) ?? 0).round().clamp(0, 999999),
        pageOffset: ((row['page_offset'] as num?) ?? 0).toDouble(),
      ),
      updatedAt:
          DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String comicPathKey;
  final String chapterPathKey;
  final ReaderPosition position;
  final DateTime updatedAt;

  ReaderProgressEntry copyWith({
    String? comicPathKey,
    String? chapterPathKey,
    ReaderPosition? position,
    DateTime? updatedAt,
  }) {
    return ReaderProgressEntry(
      comicPathKey: comicPathKey ?? this.comicPathKey,
      chapterPathKey: chapterPathKey ?? this.chapterPathKey,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'comic_path_key': comicPathKey,
      'chapter_path_key': chapterPathKey,
      'mode': switch (position.mode) {
        ReaderProgressMode.scroll => 'scroll',
        ReaderProgressMode.paged => 'paged',
      },
      'offset': position.offset,
      'page_index': position.pageIndex,
      'page_offset': position.pageOffset,
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

  static const String _tableName = 'reader_progress';
  static const String _databaseName = 'reader_state.db';
  static const String _updatedAtIndexName = 'idx_reader_progress_updated_at';
  static const Set<String> _expectedColumnNames = <String>{
    'comic_path_key',
    'chapter_path_key',
    'mode',
    'offset',
    'page_index',
    'page_offset',
    'updated_at',
  };
  static const String _createTableStatement =
      '''
    CREATE TABLE IF NOT EXISTS $_tableName (
      comic_path_key TEXT PRIMARY KEY,
      chapter_path_key TEXT NOT NULL DEFAULT '',
      mode TEXT NOT NULL DEFAULT 'scroll',
      offset REAL NOT NULL DEFAULT 0,
      page_index INTEGER NOT NULL DEFAULT 0,
      page_offset REAL NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT ''
    )
  ''';

  static String progressKeyForComicHref(String catalogHref) {
    return _pathKeyFromValue(catalogHref);
  }

  static String progressKeyForChapterHref(String chapterHref) {
    return _pathKeyFromValue(chapterHref);
  }

  final ReaderProgressDirectoryProvider _directoryProvider;
  final ReaderProgressNowProvider _now;
  final sqflite.DatabaseFactory _databaseFactory;

  Future<void>? _initialization;
  Future<void> _writeQueue = Future<void>.value();
  sqflite.Database? _database;
  List<ReaderProgressEntry> _entries = <ReaderProgressEntry>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<ReaderPosition?> readPosition({
    required String catalogHref,
    required String chapterHref,
  }) async {
    await ensureInitialized();
    final String comicPathKey = _comicPathKey(
      catalogHref: catalogHref,
      chapterHref: chapterHref,
    );
    final String chapterPathKey = _pathKey(chapterHref);
    if (comicPathKey.isEmpty || chapterPathKey.isEmpty) {
      return null;
    }
    final ReaderProgressEntry? entry = _entryForComicPathKey(comicPathKey);
    if (entry == null || entry.chapterPathKey != chapterPathKey) {
      return null;
    }
    return entry.position;
  }

  Future<double?> readOffset({
    required String catalogHref,
    required String chapterHref,
  }) async {
    final ReaderPosition? position = await readPosition(
      catalogHref: catalogHref,
      chapterHref: chapterHref,
    );
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
    final String targetComicPathKey = _pathKey(catalogHref);
    if (targetComicPathKey.isEmpty) {
      return null;
    }
    final ReaderProgressEntry? entry = _entryForComicPathKey(
      targetComicPathKey,
    );
    if (entry == null || entry.chapterPathKey.isEmpty) {
      return null;
    }
    return entry.chapterPathKey;
  }

  Future<void> markChapterOpened({
    required String catalogHref,
    required String chapterHref,
  }) async {
    await ensureInitialized();
    final String comicPathKey = _comicPathKey(
      catalogHref: catalogHref,
      chapterHref: chapterHref,
    );
    final String chapterPathKey = _pathKey(chapterHref);
    if (comicPathKey.isEmpty || chapterPathKey.isEmpty) {
      return;
    }
    await _runWrite(() async {
      final DateTime now = _now();
      final ReaderProgressEntry? existingEntry = _entryForComicPathKey(
        comicPathKey,
      );
      final bool isSameChapter =
          existingEntry != null &&
          existingEntry.chapterPathKey == chapterPathKey;
      final ReaderProgressEntry nextEntry = existingEntry != null
          ? existingEntry.copyWith(
              chapterPathKey: chapterPathKey,
              position: isSameChapter
                  ? existingEntry.position
                  : ReaderPosition.scroll(offset: 0),
              updatedAt: now,
            )
          : ReaderProgressEntry(
              comicPathKey: comicPathKey,
              chapterPathKey: chapterPathKey,
              position: ReaderPosition.scroll(offset: 0),
              updatedAt: now,
            );
      await _persistEntry(nextEntry);
    });
  }

  Future<void> writePosition(
    ReaderPosition position, {
    required String catalogHref,
    required String chapterHref,
  }) async {
    await ensureInitialized();
    final String comicPathKey = _comicPathKey(
      catalogHref: catalogHref,
      chapterHref: chapterHref,
    );
    final String chapterPathKey = _pathKey(chapterHref);
    if (comicPathKey.isEmpty || chapterPathKey.isEmpty) {
      return;
    }
    final ReaderPosition normalizedPosition = _normalizePosition(position);
    await _runWrite(() async {
      final DateTime now = _now();
      final ReaderProgressEntry? existingEntry = _entryForComicPathKey(
        comicPathKey,
      );
      final ReaderProgressEntry nextEntry = existingEntry != null
          ? existingEntry.copyWith(
              chapterPathKey: chapterPathKey,
              position: normalizedPosition,
              updatedAt: now,
            )
          : ReaderProgressEntry(
              comicPathKey: comicPathKey,
              chapterPathKey: chapterPathKey,
              position: normalizedPosition,
              updatedAt: now,
            );
      await _persistEntry(nextEntry);
    });
  }

  Future<void> writeOffset({
    required String catalogHref,
    required String chapterHref,
    required double offset,
  }) {
    return writePosition(
      ReaderPosition.scroll(offset: offset),
      catalogHref: catalogHref,
      chapterHref: chapterHref,
    );
  }

  Future<void> remove(String catalogHref) async {
    await ensureInitialized();
    final String comicPathKey = _pathKey(catalogHref);
    if (comicPathKey.isEmpty) {
      return;
    }
    await _runWrite(() async {
      _entries.removeWhere(
        (ReaderProgressEntry entry) => entry.comicPathKey == comicPathKey,
      );
      await _database!.delete(
        _tableName,
        where: 'comic_path_key = ?',
        whereArgs: <Object>[comicPathKey],
      );
    });
  }

  Future<void> close() async {
    try {
      await _writeQueue;
    } catch (_) {
      // Best-effort cleanup only.
    }
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

  ReaderProgressEntry? _entryForComicPathKey(String comicPathKey) {
    final String normalizedComicPathKey = comicPathKey.trim();
    if (normalizedComicPathKey.isEmpty) {
      return null;
    }
    return _entries.cast<ReaderProgressEntry?>().firstWhere(
      (ReaderProgressEntry? entry) =>
          entry?.comicPathKey == normalizedComicPathKey,
      orElse: () => null,
    );
  }

  Future<void> _initialize() async {
    final String path = await _databasePath();
    _database = await _databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 2,
        onCreate: (sqflite.Database db, int version) async {
          await _ensureDatabaseSchema(db);
        },
        onUpgrade: (sqflite.Database db, int oldVersion, int newVersion) async {
          await _recreateDatabaseSchema(db);
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

  String _comicPathKey({
    required String catalogHref,
    required String chapterHref,
  }) {
    final String catalogPathKey = _pathKey(catalogHref);
    if (catalogPathKey.isNotEmpty) {
      return catalogPathKey;
    }
    return _pathKey(chapterHref);
  }

  void _replaceEntry(ReaderProgressEntry nextEntry) {
    final int existingIndex = _entries.indexWhere(
      (ReaderProgressEntry entry) =>
          entry.comicPathKey == nextEntry.comicPathKey,
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
    _replaceEntry(entry);
    return _database!.insert(
      _tableName,
      entry.toRow(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<T> _runWrite<T>(Future<T> Function() action) async {
    final Future<void> previousWrite = _writeQueue;
    final Completer<void> nextWrite = Completer<void>();
    _writeQueue = nextWrite.future;
    try {
      try {
        await previousWrite;
      } catch (_) {
        // Keep later writes moving even if an earlier best-effort write failed.
      }
      return await action();
    } finally {
      if (!nextWrite.isCompleted) {
        nextWrite.complete();
      }
    }
  }

  Future<void> _ensureDatabaseSchema(sqflite.Database db) async {
    final Set<String> existingColumns = await _tableColumns(db);
    if (existingColumns.isNotEmpty &&
        !setEquals(existingColumns, _expectedColumnNames)) {
      await _recreateDatabaseSchema(db);
      return;
    }
    await db.execute(_createTableStatement);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_updatedAtIndexName
      ON $_tableName (updated_at DESC)
    ''');
  }

  Future<void> _recreateDatabaseSchema(sqflite.Database db) async {
    await db.execute('DROP TABLE IF EXISTS $_tableName');
    await db.execute(_createTableStatement);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_updatedAtIndexName
      ON $_tableName (updated_at DESC)
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
}

String _pathKeyFromValue(String href) {
  final Uri? uri = Uri.tryParse(href.trim());
  if (uri == null) {
    return '';
  }
  return uri.path.trim();
}
