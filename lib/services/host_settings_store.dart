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

  Future<List<String>> activeHosts() async {
    await ensureInitialized();
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      columns: const <String>['host'],
      where: 'is_deleted = 0',
      orderBy: 'rowid ASC',
    );
    return rows
        .map((Map<String, Object?> row) => (row['host'] as String?) ?? '')
        .where((String host) => host.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsertBuiltinHosts(Iterable<String> hosts) async {
    await _insertMissingHosts(hosts, source: _sourceBuiltin);
  }

  Future<void> upsertLegacyHosts(Iterable<String> hosts) async {
    await _insertMissingHosts(hosts, source: _sourceBuiltin);
  }

  Future<void> addCustomHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    await _runWrite(() async {
      final DateTime now = _now();
      final String timestamp = now.toIso8601String();
      await _database!.insert(_tableName, <String, Object?>{
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
        where: 'host = ?',
        whereArgs: <Object>[normalizedHost],
      );
    });
  }

  Future<void> deleteHost(String host) async {
    await ensureInitialized();
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
        where: 'host = ?',
        whereArgs: <Object>[normalizedHost],
      );
    });
  }

  Future<bool> isActiveHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return false;
    }
    final List<Map<String, Object?>> rows = await _database!.query(
      _tableName,
      columns: const <String>['host'],
      where: 'host = ? AND is_deleted = 0',
      whereArgs: <Object>[normalizedHost],
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
        version: 1,
        onCreate: (sqflite.Database db, int version) async {
          await _ensureDatabaseSchema(db);
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
  }) async {
    await ensureInitialized();
    final List<String> normalizedHosts = _normalizeHosts(hosts);
    if (normalizedHosts.isEmpty) {
      return;
    }
    await _runWrite(() async {
      final String timestamp = _now().toIso8601String();
      final sqflite.Batch batch = _database!.batch();
      for (final String host in normalizedHosts) {
        batch.insert(_tableName, <String, Object?>{
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        host TEXT PRIMARY KEY,
        source TEXT NOT NULL DEFAULT '$_sourceBuiltin',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_activeIndexName
      ON $_tableName (is_deleted, host)
    ''');
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
