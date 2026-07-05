import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef HostSettingsDirectoryProvider = Future<Directory> Function();
typedef HostSettingsNowProvider = DateTime Function();

class HostSettingsStore {
  HostSettingsStore({
    HostSettingsDirectoryProvider? directoryProvider,
    HostSettingsNowProvider? now,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _databaseFactory = databaseFactory;

  static const String databaseName = 'host_settings.db';
  static const String _tableName = 'hosts';
  static const String defaultSiteKey = 'copy';
  static const String _sourceBuiltin = 'builtin';
  static const String _sourceCustom = 'custom';
  static const String _activeIndexName = 'idx_hosts_active';

  final HostSettingsDirectoryProvider _directoryProvider;
  final HostSettingsNowProvider _now;
  final sqflite.DatabaseFactory? _databaseFactory;

  Future<void>? _initialization;
  Future<void> _writeQueue = Future<void>.value();
  sqflite.Database? _database;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<List<String>> activeHosts({String siteKey = defaultSiteKey}) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      columns: const <String>['host'],
      where: 'site_key = ? AND is_deleted = 0',
      whereArgs: <Object>[normalizedSiteKey],
      orderBy: 'rowid ASC',
    );
    return rows
        .map((Map<String, Object?> row) => (row['host'] as String?) ?? '')
        .where((String host) => host.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsertBuiltinHosts(
    Iterable<String> hosts, {
    String siteKey = defaultSiteKey,
  }) async {
    await _insertMissingHosts(hosts, source: _sourceBuiltin, siteKey: siteKey);
  }

  Future<void> upsertLegacyHosts(
    Iterable<String> hosts, {
    String siteKey = defaultSiteKey,
  }) async {
    await _insertMissingHosts(hosts, source: _sourceBuiltin, siteKey: siteKey);
  }

  Future<void> addCustomHost(
    String host, {
    String siteKey = defaultSiteKey,
  }) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    await _runWrite(() async {
      final DateTime now = _now();
      final String timestamp = now.toIso8601String();
      await _database!.insert(_tableName, <String, Object?>{
        'site_key': normalizedSiteKey,
        'host': normalizedHost,
        'source': _sourceCustom,
        'is_deleted': 0,
        'created_at': timestamp,
        'updated_at': timestamp,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
      await _database!.update(
        _tableName,
        <String, Object?>{
          'source': _sourceCustom,
          'is_deleted': 0,
          'updated_at': timestamp,
        },
        where: 'site_key = ? AND host = ?',
        whereArgs: <Object>[normalizedSiteKey, normalizedHost],
      );
    });
  }

  Future<void> deleteHost(
    String host, {
    String siteKey = defaultSiteKey,
  }) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    await _runWrite(() async {
      await _database!.update(
        _tableName,
        <String, Object?>{
          'is_deleted': 1,
          'updated_at': _now().toIso8601String(),
        },
        where: 'site_key = ? AND host = ?',
        whereArgs: <Object>[normalizedSiteKey, normalizedHost],
      );
    });
  }

  Future<bool> isActiveHost(
    String host, {
    String siteKey = defaultSiteKey,
  }) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return false;
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      columns: const <String>['host'],
      where: 'site_key = ? AND host = ? AND is_deleted = 0',
      whereArgs: <Object>[normalizedSiteKey, normalizedHost],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> close() async {
    try {
      await _writeQueue;
    } catch (_) {
      // 关闭时忽略队列中已处理过的失败。
    }
    final sqflite.Database? database = _database;
    _database = null;
    _initialization = null;
    if (database == null) {
      return;
    }
    await database.close();
  }

  Future<void> _initialize() async {
    final String path = await _databasePath();
    final sqflite.DatabaseFactory databaseFactory =
        _databaseFactory ?? sqflite.databaseFactory;
    _database = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 2,
        onCreate: (sqflite.Database db, int version) async {
          await _ensureDatabaseSchema(db);
        },
        onUpgrade: (sqflite.Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await _migrateLegacyHostsToSiteSchema(db);
          }
        },
        onOpen: (sqflite.Database db) async {
          await _ensureDatabaseSchema(db);
        },
      ),
    );
  }

  Future<String> _databasePath() async {
    final Directory directory = await _directoryProvider();
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$databaseName';
  }

  Future<void> _insertMissingHosts(
    Iterable<String> hosts, {
    required String source,
    required String siteKey,
  }) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final List<String> normalizedHosts = _normalizeHosts(hosts);
    if (normalizedHosts.isEmpty) {
      return;
    }
    await _runWrite(() async {
      final String timestamp = _now().toIso8601String();
      final sqflite.Batch batch = _database!.batch();
      for (final String host in normalizedHosts) {
        batch.insert(_tableName, <String, Object?>{
          'site_key': normalizedSiteKey,
          'host': host,
          'source': source,
          'is_deleted': 0,
          'created_at': timestamp,
          'updated_at': timestamp,
        }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _ensureDatabaseSchema(sqflite.Database db) async {
    if (await _needsLegacyMigration(db)) {
      await _migrateLegacyHostsToSiteSchema(db);
    }
    await _createHostsTable(db);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_activeIndexName
      ON $_tableName (site_key, is_deleted, host)
    ''');
  }

  Future<void> _createHostsTable(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        site_key TEXT NOT NULL DEFAULT '$defaultSiteKey',
        host TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT '$_sourceBuiltin',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (site_key, host)
      )
    ''');
  }

  Future<bool> _needsLegacyMigration(sqflite.Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[_tableName],
    );
    if (tables.isEmpty) {
      return false;
    }
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($_tableName)',
    );
    return !columns.any(
      (Map<String, Object?> column) => column['name'] == 'site_key',
    );
  }

  Future<void> _migrateLegacyHostsToSiteSchema(sqflite.Database db) async {
    if (!await _needsLegacyMigration(db)) {
      await _createHostsTable(db);
      return;
    }
    const String legacyTableName = 'hosts_legacy_v1';
    await db.execute('DROP INDEX IF EXISTS $_activeIndexName');
    await db.execute('ALTER TABLE $_tableName RENAME TO $legacyTableName');
    await _createHostsTable(db);
    await db.execute('''
      INSERT OR IGNORE INTO $_tableName (
        site_key,
        host,
        source,
        is_deleted,
        created_at,
        updated_at
      )
      SELECT
        '$defaultSiteKey',
        host,
        source,
        is_deleted,
        created_at,
        updated_at
      FROM $legacyTableName
      ORDER BY rowid ASC
    ''');
    await db.execute('DROP TABLE $legacyTableName');
  }

  Future<T> _runWrite<T>(Future<T> Function() action) async {
    final Future<void> previousWrite = _writeQueue;
    final Completer<void> nextWrite = Completer<void>();
    _writeQueue = nextWrite.future;
    try {
      try {
        await previousWrite;
      } catch (_) {
        // 前一次写入失败也不能阻塞后续写入。
      }
      return await action();
    } finally {
      if (!nextWrite.isCompleted) {
        nextWrite.complete();
      }
    }
  }

  static String _normalizeHost(String host) {
    return host.trim().toLowerCase();
  }

  static String _normalizeSiteKey(String siteKey) {
    final String normalized = siteKey.trim().toLowerCase();
    return normalized.isEmpty ? defaultSiteKey : normalized;
  }

  static List<String> _normalizeHosts(Iterable<String> hosts) {
    final List<String> values = <String>[];
    final Set<String> seenHosts = <String>{};
    for (final String host in hosts) {
      final String normalizedHost = _normalizeHost(host);
      if (normalizedHost.isEmpty || !seenHosts.add(normalizedHost)) {
        continue;
      }
      values.add(normalizedHost);
    }
    return values;
  }
}
