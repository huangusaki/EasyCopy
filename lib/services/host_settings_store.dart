import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/services/persistence/serial_executor.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

typedef HostSettingsDirectoryProvider = Future<Directory> Function();

class HostSettingsStore {
  HostSettingsStore({
    HostSettingsDirectoryProvider? directoryProvider,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _databaseFactory = databaseFactory;

  static const String databaseName = 'host_settings.db';
  static const String _tableName = 'hosts';
  static const String _activeIndexName = 'idx_hosts_active';

  final HostSettingsDirectoryProvider _directoryProvider;
  final sqflite.DatabaseFactory? _databaseFactory;

  Future<void>? _initialization;
  final SerialExecutor _writes = SerialExecutor();
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

  Future<void> addCustomHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    await _writes.run(() async {
      await _database!.transaction((transaction) async {
        await transaction.insert(_tableName, {
          'host': normalizedHost,
        }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
        await transaction.update(
          _tableName,
          {'is_deleted': 0},
          where: 'host = ? AND is_deleted != 0',
          whereArgs: [normalizedHost],
        );
      });
    });
  }

  Future<void> deleteHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return;
    }
    await _writes.run(() async {
      await _database!.update(
        _tableName,
        <String, Object?>{'is_deleted': 1},
        where: 'host = ?',
        whereArgs: <Object>[normalizedHost],
      );
    });
  }

  Future<void> close() async {
    await _writes.run(() {});
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

  Future<void> insertMissingHosts(Iterable<String> hosts) async {
    await ensureInitialized();
    final List<String> normalizedHosts = normalizeHosts(hosts);
    if (normalizedHosts.isEmpty) {
      return;
    }
    await _writes.run(() async {
      final sqflite.Batch batch = _database!.batch();
      for (final String host in normalizedHosts) {
        batch.insert(_tableName, <String, Object?>{
          'host': host,
          'is_deleted': 0,
        }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _ensureDatabaseSchema(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        host TEXT PRIMARY KEY,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS $_activeIndexName
      ON $_tableName (is_deleted, host)
    ''');
  }
}

String normalizeHost(String host) => host.trim().toLowerCase();

List<String> normalizeHosts(Iterable<String> hosts) =>
    hosts.map(normalizeHost).where((host) => host.isNotEmpty).toSet().toList();
