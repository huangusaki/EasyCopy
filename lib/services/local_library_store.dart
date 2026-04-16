import 'dart:io';

import 'package:easy_copy/models/page_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef LocalLibraryDirectoryProvider = Future<Directory> Function();
typedef LocalLibraryNowProvider = DateTime Function();

class LocalLibraryStore {
  LocalLibraryStore({
    LocalLibraryDirectoryProvider? directoryProvider,
    LocalLibraryNowProvider? now,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static final LocalLibraryStore instance = LocalLibraryStore();

  static const String guestScope = 'guest';
  static const String continueReadingScope = 'continue';

  static const int maxHistoryEntries = 200;
  static const String _databaseName = 'library_state.db';
  static const String _collectionsTable = 'collections';
  static const String _historyTable = 'browse_history';
  static const String _metaTable = 'library_meta';

  final LocalLibraryDirectoryProvider _directoryProvider;
  final LocalLibraryNowProvider _now;
  final sqflite.DatabaseFactory _databaseFactory;

  Future<void>? _initialization;
  sqflite.Database? _database;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
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
      // Best-effort cleanup only.
    }
  }

  Future<bool> isSeeded(String scope, String key) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String normalizedKey = key.trim();
    if (normalizedScope.isEmpty || normalizedKey.isEmpty) {
      return false;
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _metaTable,
      columns: const <String>['value'],
      where: 'scope = ? AND key = ?',
      whereArgs: <Object>[normalizedScope, normalizedKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    return ((rows.first['value'] as String?) ?? '') == '1';
  }

  Future<void> markSeeded(String scope, String key) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String normalizedKey = key.trim();
    if (normalizedScope.isEmpty || normalizedKey.isEmpty) {
      return;
    }
    await _database!.insert(
      _metaTable,
      <String, Object?>{
        'scope': normalizedScope,
        'key': normalizedKey,
        'value': '1',
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<void> importCollections(
    String scope,
    Iterable<ProfileLibraryItem> items, {
    int? baseAddedAtMs,
  }) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      return;
    }
    final int baseMs = baseAddedAtMs ?? _now().millisecondsSinceEpoch;
    final sqflite.Batch batch = _database!.batch();
    int index = 0;
    for (final ProfileLibraryItem item in items) {
      final String href = item.href.trim();
      final String comicPathKey = _pathKeyForHref(href);
      if (comicPathKey.isEmpty) {
        continue;
      }
      final String id = _entryId(normalizedScope, comicPathKey);
      batch.insert(
        _collectionsTable,
        <String, Object?>{
          'id': id,
          'scope': normalizedScope,
          'comic_path_key': comicPathKey,
          'title': item.title.trim(),
          'cover_url': item.coverUrl.trim(),
          'href': href,
          'subtitle': item.subtitle.trim(),
          'secondary_text': item.secondaryText.trim(),
          'added_at_ms': baseMs - index,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
      index += 1;
    }
    await batch.commit(noResult: true);
  }

  Future<void> importHistory(
    String scope,
    Iterable<ProfileHistoryItem> items, {
    int maxEntries = maxHistoryEntries,
    int? baseVisitedAtMs,
  }) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      return;
    }
    final int effectiveMaxEntries = maxEntries < 1 ? 1 : maxEntries;
    final int baseMs = baseVisitedAtMs ?? _now().millisecondsSinceEpoch;
    final sqflite.Batch batch = _database!.batch();
    int index = 0;
    for (final ProfileHistoryItem item in items) {
      if (index >= effectiveMaxEntries) {
        break;
      }
      final String comicHref = item.comicHref.trim();
      final String comicPathKey = _pathKeyForHref(comicHref);
      if (comicPathKey.isEmpty) {
        continue;
      }
      final String id = _entryId(normalizedScope, comicPathKey);
      final int visitedAtMs =
          _parseTimestamp(item.visitedAt) ?? (baseMs - index);
      batch.insert(
        _historyTable,
        <String, Object?>{
          'id': id,
          'scope': normalizedScope,
          'comic_path_key': comicPathKey,
          'title': item.title.trim(),
          'cover_url': item.coverUrl.trim(),
          'comic_href': comicHref,
          'chapter_label': item.chapterLabel.trim(),
          'chapter_href': item.chapterHref.trim(),
          'visited_at_ms': visitedAtMs,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
      index += 1;
    }
    await batch.commit(noResult: true);
    await _trimHistory(normalizedScope);
  }

  Future<bool> isCollected(String scope, String comicHref) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String comicPathKey = _pathKeyForHref(comicHref);
    if (normalizedScope.isEmpty || comicPathKey.isEmpty) {
      return false;
    }
    final String id = _entryId(normalizedScope, comicPathKey);
    final List<Map<String, Object?>> rows = await _database!.query(
      _collectionsTable,
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> upsertCollection(String scope, ProfileLibraryItem item) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String href = item.href.trim();
    final String comicPathKey = _pathKeyForHref(href);
    if (normalizedScope.isEmpty || comicPathKey.isEmpty) {
      return;
    }
    final String id = _entryId(normalizedScope, comicPathKey);
    final DateTime now = _now();
    await _database!.insert(
      _collectionsTable,
      <String, Object?>{
        'id': id,
        'scope': normalizedScope,
        'comic_path_key': comicPathKey,
        'title': item.title.trim(),
        'cover_url': item.coverUrl.trim(),
        'href': href,
        'subtitle': item.subtitle.trim(),
        'secondary_text': item.secondaryText.trim(),
        'added_at_ms': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<void> removeCollection(String scope, String comicHref) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String comicPathKey = _pathKeyForHref(comicHref);
    if (normalizedScope.isEmpty || comicPathKey.isEmpty) {
      return;
    }
    await _database!.delete(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: <Object>[_entryId(normalizedScope, comicPathKey)],
    );
  }

  Future<(List<ProfileLibraryItem> items, int total)> readCollectionsPage(
    String scope, {
    required int page,
    int pageSize = 20,
  }) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      return (const <ProfileLibraryItem>[], 0);
    }
    final int normalizedPage = page < 1 ? 1 : page;
    final int normalizedPageSize = pageSize.clamp(1, 100);
    final int offset = (normalizedPage - 1) * normalizedPageSize;

    final int total = sqflite.Sqflite.firstIntValue(
          await _database!.rawQuery(
            'SELECT COUNT(*) FROM $_collectionsTable WHERE scope = ?',
            <Object>[normalizedScope],
          ),
        ) ??
        0;

    final List<Map<String, Object?>> rows = await _database!.query(
      _collectionsTable,
      where: 'scope = ?',
      whereArgs: <Object>[normalizedScope],
      orderBy: 'added_at_ms DESC',
      limit: normalizedPageSize,
      offset: offset,
    );

    final List<ProfileLibraryItem> items = rows
        .map((Map<String, Object?> row) {
          return ProfileLibraryItem(
            title: (row['title'] as String?)?.trim() ?? '',
            coverUrl: (row['cover_url'] as String?)?.trim() ?? '',
            href: (row['href'] as String?)?.trim() ?? '',
            subtitle: (row['subtitle'] as String?)?.trim() ?? '',
            secondaryText: (row['secondary_text'] as String?)?.trim() ?? '',
          );
        })
        .where((ProfileLibraryItem item) => item.title.isNotEmpty)
        .toList(growable: false);

    return (items, total);
  }

  Future<void> recordHistoryFromDetail(String scope, DetailPageData page) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String href = page.uri.trim();
    final String comicPathKey = _pathKeyForHref(href);
    if (normalizedScope.isEmpty || comicPathKey.isEmpty) {
      return;
    }
    final String id = _entryId(normalizedScope, comicPathKey);
    final Map<String, Object?> existing = await _historyRowForId(id);
    final String existingChapterLabel =
        (existing['chapter_label'] as String?)?.trim() ?? '';
    final String existingChapterHref =
        (existing['chapter_href'] as String?)?.trim() ?? '';
    final String coverUrl = page.coverUrl.trim().isNotEmpty
        ? page.coverUrl.trim()
        : (existing['cover_url'] as String?)?.trim() ?? '';
    final String title = page.title.trim().isNotEmpty
        ? page.title.trim()
        : (existing['title'] as String?)?.trim() ?? '';
    final String comicHref = href.isNotEmpty
        ? href
        : (existing['comic_href'] as String?)?.trim() ?? '';

    await _database!.insert(
      _historyTable,
      <String, Object?>{
        'id': id,
        'scope': normalizedScope,
        'comic_path_key': comicPathKey,
        'title': title,
        'cover_url': coverUrl,
        'comic_href': comicHref,
        // Preserve the last opened chapter so a detail view doesn't wipe
        // the continue-reading state.
        'chapter_label': existingChapterLabel,
        'chapter_href': existingChapterHref,
        'visited_at_ms': _now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    await _trimHistory(normalizedScope);
  }

  Future<void> recordHistoryFromReader(
    String scope,
    ReaderPageData page, {
    required String coverUrl,
  }) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    final String catalogHref = page.catalogHref.trim();
    final String comicPathKey = _pathKeyForHref(catalogHref);
    if (normalizedScope.isEmpty || comicPathKey.isEmpty) {
      return;
    }
    final String id = _entryId(normalizedScope, comicPathKey);
    await _database!.insert(
      _historyTable,
      <String, Object?>{
        'id': id,
        'scope': normalizedScope,
        'comic_path_key': comicPathKey,
        'title': page.comicTitle.trim(),
        'cover_url': coverUrl.trim(),
        'comic_href': catalogHref,
        'chapter_label': page.chapterTitle.trim(),
        'chapter_href': page.uri.trim(),
        'visited_at_ms': _now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    await _trimHistory(normalizedScope);
  }

  Future<(List<ProfileHistoryItem> items, int total)> readHistoryPage(
    String scope, {
    required int page,
    int pageSize = 20,
  }) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      return (const <ProfileHistoryItem>[], 0);
    }
    final int normalizedPage = page < 1 ? 1 : page;
    final int normalizedPageSize = pageSize.clamp(1, 100);
    final int offset = (normalizedPage - 1) * normalizedPageSize;

    final int total = sqflite.Sqflite.firstIntValue(
          await _database!.rawQuery(
            'SELECT COUNT(*) FROM $_historyTable WHERE scope = ?',
            <Object>[normalizedScope],
          ),
        ) ??
        0;

    final List<Map<String, Object?>> rows = await _database!.query(
      _historyTable,
      where: 'scope = ?',
      whereArgs: <Object>[normalizedScope],
      orderBy: 'visited_at_ms DESC',
      limit: normalizedPageSize,
      offset: offset,
    );

    final List<ProfileHistoryItem> items = rows
        .map((Map<String, Object?> row) {
          final int visitedAtMs = (row['visited_at_ms'] as num?)?.toInt() ?? 0;
          return ProfileHistoryItem(
            title: (row['title'] as String?)?.trim() ?? '',
            coverUrl: (row['cover_url'] as String?)?.trim() ?? '',
            comicHref: (row['comic_href'] as String?)?.trim() ?? '',
            chapterLabel: (row['chapter_label'] as String?)?.trim() ?? '',
            chapterHref: (row['chapter_href'] as String?)?.trim() ?? '',
            visitedAt: visitedAtMs <= 0 ? '' : _formatTimestamp(visitedAtMs),
          );
        })
        .where((ProfileHistoryItem item) => item.title.isNotEmpty)
        .toList(growable: false);

    return (items, total);
  }

  Future<ProfileHistoryItem?> latestContinueReading(String scope) async {
    await ensureInitialized();
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      return null;
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _historyTable,
      where: 'scope = ? AND chapter_href != ?',
      whereArgs: <Object>[normalizedScope, ''],
      orderBy: 'visited_at_ms DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Map<String, Object?> row = rows.first;
    final int visitedAtMs = (row['visited_at_ms'] as num?)?.toInt() ?? 0;
    return ProfileHistoryItem(
      title: (row['title'] as String?)?.trim() ?? '',
      coverUrl: (row['cover_url'] as String?)?.trim() ?? '',
      comicHref: (row['comic_href'] as String?)?.trim() ?? '',
      chapterLabel: (row['chapter_label'] as String?)?.trim() ?? '',
      chapterHref: (row['chapter_href'] as String?)?.trim() ?? '',
      visitedAt: visitedAtMs <= 0 ? '' : _formatTimestamp(visitedAtMs),
    );
  }

  Future<void> _initialize() async {
    final Directory directory = await _directoryProvider();
    final String path = '${directory.path}${Platform.pathSeparator}$_databaseName';
    _database = await _databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 2,
        onCreate: (sqflite.Database db, int version) async {
          await db.execute(
            '''
            CREATE TABLE IF NOT EXISTS $_collectionsTable (
              id TEXT PRIMARY KEY,
              scope TEXT NOT NULL,
              comic_path_key TEXT NOT NULL,
              title TEXT NOT NULL,
              cover_url TEXT NOT NULL,
              href TEXT NOT NULL,
              subtitle TEXT NOT NULL,
              secondary_text TEXT NOT NULL,
              added_at_ms INTEGER NOT NULL
            )
          ''',
          );
          await db.execute(
            '''
            CREATE INDEX IF NOT EXISTS idx_collections_scope_added_at
            ON $_collectionsTable(scope, added_at_ms)
          ''',
          );
          await db.execute(
            '''
            CREATE TABLE IF NOT EXISTS $_historyTable (
              id TEXT PRIMARY KEY,
              scope TEXT NOT NULL,
              comic_path_key TEXT NOT NULL,
              title TEXT NOT NULL,
              cover_url TEXT NOT NULL,
              comic_href TEXT NOT NULL,
              chapter_label TEXT NOT NULL,
              chapter_href TEXT NOT NULL,
              visited_at_ms INTEGER NOT NULL
            )
          ''',
          );
          await db.execute(
            '''
            CREATE INDEX IF NOT EXISTS idx_history_scope_visited_at
            ON $_historyTable(scope, visited_at_ms)
          ''',
          );
          await db.execute(
            '''
            CREATE TABLE IF NOT EXISTS $_metaTable (
              scope TEXT NOT NULL,
              key TEXT NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY(scope, key)
            )
          ''',
          );
        },
        onUpgrade: (sqflite.Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              '''
              CREATE TABLE IF NOT EXISTS $_metaTable (
                scope TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY(scope, key)
              )
            ''',
            );
          }
        },
      ),
    );
  }

  Future<Map<String, Object?>> _historyRowForId(String id) async {
    final List<Map<String, Object?>> rows = await _database!.query(
      _historyTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const <String, Object?>{};
    }
    return rows.first;
  }

  Future<void> _trimHistory(String scope) async {
    await _database!.execute(
      '''
      DELETE FROM $_historyTable
      WHERE scope = ?
        AND id NOT IN (
          SELECT id FROM $_historyTable
          WHERE scope = ?
          ORDER BY visited_at_ms DESC
          LIMIT $maxHistoryEntries
        )
    ''',
      <Object>[scope, scope],
    );
  }

  static String _entryId(String scope, String comicPathKey) {
    return '${scope.trim()}::${comicPathKey.trim()}';
  }

  static String _pathKeyForHref(String href) {
    final Uri? uri = Uri.tryParse(href.trim());
    if (uri == null) {
      return '';
    }
    return uri.path.trim();
  }

  static String _twoDigits(int value) => value >= 10 ? '$value' : '0$value';

  static int? _parseTimestamp(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final int? milliseconds = int.tryParse(trimmed);
    if (milliseconds != null && milliseconds > 0) {
      // Heuristic: treat large values as milliseconds, smaller as seconds.
      if (milliseconds > 100000000000) {
        return milliseconds;
      }
      if (milliseconds > 1000000000) {
        return milliseconds * 1000;
      }
    }
    final DateTime? parsed =
        DateTime.tryParse(trimmed) ??
        DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
    return parsed?.millisecondsSinceEpoch;
  }

  static String _formatTimestamp(int millisecondsSinceEpoch) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
    ).toLocal();
    return '${dt.year}-${_twoDigits(dt.month)}-${_twoDigits(dt.day)} '
        '${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}';
  }
}
