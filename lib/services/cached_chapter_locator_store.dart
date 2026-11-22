import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef LocatorDirProvider = Future<Directory> Function();
typedef CachedChapterLocatorNowProvider = DateTime Function();

@immutable
class CachedChapterLocator {
  const CachedChapterLocator({
    required this.storageKey,
    required this.chapterPathKey,
    required this.sourcePathKey,
    required this.directoryPath,
    required this.comicTitle,
    required this.chapterTitle,
    required this.downloadedAt,
    required this.updatedAt,
  });

  factory CachedChapterLocator.fromRow(Map<String, Object?> row) {
    return CachedChapterLocator(
      storageKey: (row['storage_key'] as String?)?.trim() ?? '',
      chapterPathKey: (row['chapter_path_key'] as String?)?.trim() ?? '',
      sourcePathKey: (row['source_path_key'] as String?)?.trim() ?? '',
      directoryPath: (row['directory_path'] as String?)?.trim() ?? '',
      comicTitle: (row['comic_title'] as String?)?.trim() ?? '',
      chapterTitle: (row['chapter_title'] as String?)?.trim() ?? '',
      downloadedAt:
          DateTime.tryParse((row['downloaded_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String storageKey;
  final String chapterPathKey;
  final String sourcePathKey;
  final String directoryPath;
  final String comicTitle;
  final String chapterTitle;
  final DateTime downloadedAt;
  final DateTime updatedAt;

  CachedChapterLocator copyWith({
    String? storageKey,
    String? chapterPathKey,
    String? sourcePathKey,
    String? directoryPath,
    String? comicTitle,
    String? chapterTitle,
    DateTime? downloadedAt,
    DateTime? updatedAt,
  }) {
    return CachedChapterLocator(
      storageKey: storageKey ?? this.storageKey,
      chapterPathKey: chapterPathKey ?? this.chapterPathKey,
      sourcePathKey: sourcePathKey ?? this.sourcePathKey,
      directoryPath: directoryPath ?? this.directoryPath,
      comicTitle: comicTitle ?? this.comicTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': CachedChapterLocatorStore.entryId(storageKey, directoryPath),
      'storage_key': storageKey,
      'chapter_path_key': chapterPathKey,
      'source_path_key': sourcePathKey,
      'directory_path': directoryPath,
      'comic_title': comicTitle,
      'chapter_title': chapterTitle,
      'downloaded_at': downloadedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class CachedChapterLocatorStore {
  CachedChapterLocatorStore({
    LocatorDirProvider? directoryProvider,
    CachedChapterLocatorNowProvider? now,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _databaseFactory = databaseFactory;

  static final CachedChapterLocatorStore instance = CachedChapterLocatorStore();

  static const String _tableName = 'cached_chapter_locator';
  static const String _databaseName = 'cached_chapter_locator.db';

  final LocatorDirProvider _directoryProvider;
  final CachedChapterLocatorNowProvider _now;
  final sqflite.DatabaseFactory? _databaseFactory;

  Future<void>? _initialization;
  sqflite.Database? _database;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  static String entryId(String storageKey, String directoryPath) {
    return '${storageKey.trim()}::${directoryPath.trim()}';
  }

  Future<CachedChapterLocator?> findByPathKey({
    required String storageKey,
    required String targetPathKey,
  }) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    final String normalizedTargetPathKey = targetPathKey.trim();
    if (normalizedStorageKey.isEmpty || normalizedTargetPathKey.isEmpty) {
      return null;
    }
    final rows = await _database!.rawQuery(
      '''
      SELECT * FROM $_tableName WHERE storage_key = ? AND chapter_path_key = ?
      UNION ALL
      SELECT * FROM $_tableName WHERE storage_key = ? AND source_path_key = ?
      ORDER BY downloaded_at DESC, updated_at DESC LIMIT 1
    ''',
      [
        normalizedStorageKey,
        normalizedTargetPathKey,
        normalizedStorageKey,
        normalizedTargetPathKey,
      ],
    );
    if (rows.isEmpty) {
      return null;
    }
    return CachedChapterLocator.fromRow(rows.first);
  }

  Future<bool> hasEntriesForStorage(String storageKey) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      return false;
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      columns: <String>['id'],
      where: 'storage_key = ?',
      whereArgs: <Object>[normalizedStorageKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> upsert(CachedChapterLocator locator) async {
    await ensureInitialized();
    final String normalizedStorageKey = locator.storageKey.trim();
    final String normalizedDirectoryPath = locator.directoryPath.trim();
    if (normalizedStorageKey.isEmpty || normalizedDirectoryPath.isEmpty) {
      return;
    }
    final CachedChapterLocator normalizedLocator = locator.copyWith(
      storageKey: normalizedStorageKey,
      directoryPath: normalizedDirectoryPath,
      updatedAt: locator.updatedAt == DateTime.fromMillisecondsSinceEpoch(0)
          ? _now()
          : locator.updatedAt,
    );
    await _database!.insert(
      _tableName,
      normalizedLocator.toRow(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<void> writeLocators(
    String storageKey,
    Iterable<CachedChapterLocator> locators, {
    required bool replace,
  }) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      return;
    }
    final sqflite.Batch batch = _database!.batch();
    _queueLocators(batch, normalizedStorageKey, locators, replace: replace);
    await batch.commit(noResult: true);
  }

  void _queueLocators(
    sqflite.Batch batch,
    String normalizedStorageKey,
    Iterable<CachedChapterLocator> locators, {
    required bool replace,
  }) {
    if (replace) {
      batch.delete(
        _tableName,
        where: 'storage_key = ?',
        whereArgs: <Object>[normalizedStorageKey],
      );
    }
    final DateTime now = _now();
    for (final CachedChapterLocator locator in locators) {
      final String directoryPath = locator.directoryPath.trim();
      if (directoryPath.isEmpty) {
        continue;
      }
      batch.insert(
        _tableName,
        locator
            .copyWith(
              storageKey: normalizedStorageKey,
              directoryPath: directoryPath,
              updatedAt: now,
            )
            .toRow(),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> removeDirectoryPaths({
    required String storageKey,
    required Iterable<String> directoryPaths,
  }) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    final Set<String> normalizedPaths = directoryPaths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toSet();
    if (normalizedStorageKey.isEmpty || normalizedPaths.isEmpty) {
      return;
    }
    final sqflite.Batch batch = _database!.batch();
    for (final String path in normalizedPaths) {
      batch.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: <Object>[entryId(normalizedStorageKey, path)],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>?> readLibrary(String key) async {
    await ensureInitialized();
    return _database!.transaction((tx) async {
      final roots = await tx.query(
        'library_roots',
        columns: ['ordered_keys'],
        where: 'storage_key=?',
        whereArgs: [key],
      );
      if (roots.isEmpty) return null;
      final keys = (jsonDecode(roots.single['ordered_keys'] as String) as List)
          .cast<String>();
      final rows = await tx.query(
        'library_comics',
        columns: ['comic_key', 'payload'],
        where: 'storage_key=?',
        whereArgs: [key],
      );
      final comics = {
        for (final row in rows)
          row['comic_key'] as String:
              jsonDecode(row['payload'] as String) as Map<String, Object?>,
      };
      return [for (final id in keys) comics[id]!];
    });
  }

  Future<void> writeLibrary(
    String key,
    List<String> order,
    Map<String, Map<String, Object?>> changed, {
    required Iterable<String> removedKeys,
    required bool replace,
    Iterable<CachedChapterLocator> locators = const [],
    bool replaceLocators = false,
    Iterable<String> removedLocatorPaths = const [],
  }) async {
    await ensureInitialized();
    final batch = _database!.batch();
    _queueLocators(batch, key, locators, replace: replaceLocators);
    for (final path in removedLocatorPaths) {
      batch.delete(_tableName, where: 'id=?', whereArgs: [entryId(key, path)]);
    }
    if (replace) {
      batch.delete('library_comics', where: 'storage_key=?', whereArgs: [key]);
    } else {
      for (final id in removedKeys) {
        batch.delete(
          'library_comics',
          where: 'storage_key=? AND comic_key=?',
          whereArgs: [key, id],
        );
      }
    }
    for (final entry in changed.entries) {
      batch.insert('library_comics', {
        'storage_key': key,
        'comic_key': entry.key,
        'payload': jsonEncode(entry.value),
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    }
    batch.insert('library_roots', {
      'storage_key': key,
      'ordered_keys': jsonEncode(order),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final sqflite.Database? database = _database;
    _database = null;
    _initialization = null;
    if (database == null) {
      return;
    }
    try {
      await database.close();
    } catch (_) {
      return;
    }
  }

  Future<void> _initialize() async {
    final String path = await _databasePath();
    final sqflite.DatabaseFactory databaseFactory =
        _databaseFactory ?? sqflite.databaseFactory;
    _database = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onCreate: (sqflite.Database db, int version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id TEXT PRIMARY KEY,
              storage_key TEXT NOT NULL,
              chapter_path_key TEXT NOT NULL,
              source_path_key TEXT NOT NULL,
              directory_path TEXT NOT NULL,
              comic_title TEXT NOT NULL,
              chapter_title TEXT NOT NULL,
              downloaded_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
        onOpen: (sqflite.Database db) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS library_roots(storage_key TEXT PRIMARY KEY, ordered_keys TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS library_comics(storage_key TEXT NOT NULL,comic_key TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(storage_key,comic_key))',
          );

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_cached_chapter_locator_storage_chapter_path
            ON $_tableName (storage_key, chapter_path_key)
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_cached_chapter_locator_storage_source_path
            ON $_tableName (storage_key, source_path_key)
          ''');
        },
      ),
    );
  }

  Future<String> _databasePath() async {
    final Directory directory = await _directoryProvider();
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$_databaseName';
  }
}
