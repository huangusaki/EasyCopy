import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef CachedChapterLocatorDirectoryProvider = Future<Directory> Function();
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
    CachedChapterLocatorDirectoryProvider? directoryProvider,
    CachedChapterLocatorNowProvider? now,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static final CachedChapterLocatorStore instance = CachedChapterLocatorStore();

  static const String _tableName = 'cached_chapter_locator';
  static const String _databaseName = 'cached_chapter_locator.db';

  final CachedChapterLocatorDirectoryProvider _directoryProvider;
  final CachedChapterLocatorNowProvider _now;
  final sqflite.DatabaseFactory _databaseFactory;

  Future<void>? _initialization;
  sqflite.Database? _database;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  static String entryId(String storageKey, String directoryPath) {
    return '${storageKey.trim()}::${directoryPath.trim()}';
  }

  static String pathKeyForHref(String href) {
    final Uri? uri = Uri.tryParse(href.trim());
    if (uri == null) {
      return '';
    }
    return uri.path.trim();
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
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      where:
          'storage_key = ? AND (chapter_path_key = ? OR source_path_key = ?)',
      whereArgs: <Object>[
        normalizedStorageKey,
        normalizedTargetPathKey,
        normalizedTargetPathKey,
      ],
      orderBy: 'downloaded_at DESC, updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CachedChapterLocator.fromRow(rows.first);
  }

  Future<List<CachedChapterLocator>> entriesForStorage(
    String storageKey,
  ) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      return const <CachedChapterLocator>[];
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      where: 'storage_key = ?',
      whereArgs: <Object>[normalizedStorageKey],
      orderBy: 'downloaded_at DESC, updated_at DESC',
    );
    return rows.map(CachedChapterLocator.fromRow).toList(growable: false);
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

  Future<void> replaceStorage(
    String storageKey,
    Iterable<CachedChapterLocator> locators,
  ) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      return;
    }
    final sqflite.Batch batch = _database!.batch();
    batch.delete(
      _tableName,
      where: 'storage_key = ?',
      whereArgs: <Object>[normalizedStorageKey],
    );
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
    await batch.commit(noResult: true);
  }

  Future<void> copy(String fromStorageKey, String toStorageKey) async {
    await ensureInitialized();
    final String normalizedFromStorageKey = fromStorageKey.trim();
    final String normalizedToStorageKey = toStorageKey.trim();
    if (normalizedFromStorageKey.isEmpty ||
        normalizedToStorageKey.isEmpty ||
        normalizedFromStorageKey == normalizedToStorageKey) {
      return;
    }
    final List<CachedChapterLocator> entries = await entriesForStorage(
      normalizedFromStorageKey,
    );
    await replaceStorage(
      normalizedToStorageKey,
      entries.map(
        (CachedChapterLocator entry) =>
            entry.copyWith(storageKey: normalizedToStorageKey),
      ),
    );
  }

  Future<void> removeDirectoryPath({
    required String storageKey,
    required String directoryPath,
  }) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    final String normalizedDirectoryPath = directoryPath.trim();
    if (normalizedStorageKey.isEmpty || normalizedDirectoryPath.isEmpty) {
      return;
    }
    await _database!.delete(
      _tableName,
      where: 'storage_key = ? AND directory_path = ?',
      whereArgs: <Object>[normalizedStorageKey, normalizedDirectoryPath],
    );
  }

  Future<void> removeComicDirectory({
    required String storageKey,
    required String comicRelativePath,
  }) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    final String normalizedComicRelativePath = comicRelativePath.trim();
    if (normalizedStorageKey.isEmpty || normalizedComicRelativePath.isEmpty) {
      return;
    }
    await _database!.delete(
      _tableName,
      where:
          'storage_key = ? AND (directory_path = ? OR directory_path LIKE ?)',
      whereArgs: <Object>[
        normalizedStorageKey,
        normalizedComicRelativePath,
        '$normalizedComicRelativePath/%',
      ],
    );
  }

  Future<void> clear([String storageKey = '']) async {
    await ensureInitialized();
    final String normalizedStorageKey = storageKey.trim();
    if (normalizedStorageKey.isEmpty) {
      await _database!.delete(_tableName);
      return;
    }
    await _database!.delete(
      _tableName,
      where: 'storage_key = ?',
      whereArgs: <Object>[normalizedStorageKey],
    );
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
    _database = await _databaseFactory.openDatabase(
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
          await db.execute('''
            CREATE INDEX idx_cached_chapter_locator_storage_chapter_path
            ON $_tableName (storage_key, chapter_path_key)
          ''');
          await db.execute('''
            CREATE INDEX idx_cached_chapter_locator_storage_source_path
            ON $_tableName (storage_key, source_path_key)
          ''');
        },
        onOpen: (sqflite.Database db) async {
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
