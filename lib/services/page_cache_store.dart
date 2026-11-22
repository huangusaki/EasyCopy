import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';
import 'package:reader/services/persistence/serial_executor.dart';
import 'package:sqflite/sqflite.dart' as sql;

typedef CacheNowProvider = DateTime Function();
typedef CacheDirectoryProvider = Future<Directory> Function();

@immutable
class PageCachePolicy {
  const PageCachePolicy({required this.softTtl, required this.hardTtl});

  final Duration softTtl;
  final Duration hardTtl;

  // 列表软过期别太短，移动端后台刷新会抢平台主线程。
  static const PageCachePolicy listPage = PageCachePolicy(
    softTtl: Duration(minutes: 12),
    hardTtl: Duration(hours: 2),
  );
  static const PageCachePolicy detailPage = PageCachePolicy(
    softTtl: Duration(minutes: 10),
    hardTtl: Duration(hours: 12),
  );
  static const PageCachePolicy readerPage = PageCachePolicy(
    softTtl: Duration(hours: 24),
    hardTtl: Duration(days: 30),
  );
  static const PageCachePolicy profilePage = PageCachePolicy(
    softTtl: Duration(minutes: 5),
    hardTtl: Duration(minutes: 30),
  );

  static PageCachePolicy forPage(SitePage page) {
    switch (page.type) {
      case SitePageType.detail:
        return detailPage;
      case SitePageType.reader:
        return readerPage;
      case SitePageType.profile:
        return profilePage;
      case SitePageType.home:
      case SitePageType.discover:
      case SitePageType.rank:
      case SitePageType.unknown:
        return listPage;
    }
  }
}

class CachedPageEnvelope {
  CachedPageEnvelope({
    required this.routeKey,
    required this.pageType,
    required this.payload,
    this.readerCacheVersion,
    required this.fetchedAt,
    required this.softTtlSeconds,
    required this.hardTtlSeconds,
    required this.authScope,
    DateTime? validatedAt,
    DateTime? lastAccessedAt,
  }) : validatedAt = validatedAt ?? fetchedAt,
       lastAccessedAt = lastAccessedAt ?? fetchedAt;

  factory CachedPageEnvelope.fromJson(Map<String, Object?> json) {
    final String pageTypeName = (json['pageType'] as String?) ?? '';
    return CachedPageEnvelope(
      routeKey: (json['routeKey'] as String?) ?? '',
      pageType: SitePageType.values.firstWhere(
        (SitePageType value) => value.name == pageTypeName,
        orElse: () => SitePageType.unknown,
      ),
      payload:
          ((json['payload'] as Map<Object?, Object?>?) ??
                  const <Object?, Object?>{})
              .map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
      readerCacheVersion: (json['readerCacheVersion'] as num?)?.toInt(),
      fetchedAt:
          DateTime.tryParse((json['fetchedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      validatedAt:
          DateTime.tryParse((json['validatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastAccessedAt:
          DateTime.tryParse((json['lastAccessedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      softTtlSeconds: (json['softTtlSeconds'] as num?)?.toInt() ?? 0,
      hardTtlSeconds: (json['hardTtlSeconds'] as num?)?.toInt() ?? 0,
      authScope: (json['authScope'] as String?) ?? 'guest',
    );
  }

  final String routeKey;
  final SitePageType pageType;
  final Map<String, Object?> payload;
  final int? readerCacheVersion;
  final DateTime fetchedAt;
  final DateTime validatedAt;
  final DateTime lastAccessedAt;
  final int softTtlSeconds;
  final int hardTtlSeconds;
  final String authScope;

  Duration get softTtl => Duration(seconds: softTtlSeconds);
  Duration get hardTtl => Duration(seconds: hardTtlSeconds);

  bool isSoftExpired(DateTime now) {
    return now.difference(validatedAt) > softTtl;
  }

  bool isHardExpired(DateTime now) {
    return now.difference(fetchedAt) > hardTtl;
  }

  CachedPageEnvelope copyWith({
    DateTime? fetchedAt,
    DateTime? validatedAt,
    DateTime? lastAccessedAt,
    Map<String, Object?>? payload,
    String? authScope,
  }) {
    return CachedPageEnvelope(
      routeKey: routeKey,
      pageType: pageType,
      payload: payload ?? this.payload,
      readerCacheVersion: readerCacheVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      validatedAt: validatedAt ?? this.validatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      softTtlSeconds: softTtlSeconds,
      hardTtlSeconds: hardTtlSeconds,
      authScope: authScope ?? this.authScope,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'routeKey': routeKey,
      'pageType': pageType.name,
      'payload': payload,
      if (readerCacheVersion != null) 'readerCacheVersion': readerCacheVersion,
      'fetchedAt': fetchedAt.toIso8601String(),
      'validatedAt': validatedAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt.toIso8601String(),
      'softTtlSeconds': softTtlSeconds,
      'hardTtlSeconds': hardTtlSeconds,
      'authScope': authScope,
    };
  }
}

class PageCacheStore {
  PageCacheStore({
    CacheDirectoryProvider? directoryProvider,
    CacheNowProvider? now,
    sql.DatabaseFactory? databaseFactory,
  }) : _directory = directoryProvider ?? getApplicationSupportDirectory,
       _factory = databaseFactory,
       _now = now ?? DateTime.now;

  static final PageCacheStore instance = PageCacheStore();
  static const int maxEntries = 120;
  static const int maxBytes = 10 * 1024 * 1024;
  static const int readerCacheVersion = 1;
  final CacheDirectoryProvider _directory;
  final CacheNowProvider _now;
  final sql.DatabaseFactory? _factory;
  final SerialExecutor _operations = SerialExecutor();
  sql.Database? _db;
  Future<void>? _initialization;

  late final _legacy = AtomicJsonFile<List<CachedPageEnvelope>>(
    directoryProvider: _directory,
    relativePath: 'page_cache.json',
    decode: (json) => (json as List)
        .whereType<Map>()
        .map(
          (row) => CachedPageEnvelope.fromJson(Map<String, Object?>.from(row)),
        )
        .toList(),
    encode: (entries) => entries.map((e) => e.toJson()).toList(),
  );

  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final dir = await _directory();
      await dir.create(recursive: true);
      _db = await (_factory ?? sql.databaseFactory).openDatabase(
        '${dir.path}/page_cache.db',
        options: sql.OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              """CREATE TABLE pages (
            scope TEXT NOT NULL, route TEXT NOT NULL,
            page_type TEXT NOT NULL, reader_version INTEGER, soft_ttl INTEGER NOT NULL,
            bytes INTEGER NOT NULL, fetched INTEGER NOT NULL,
            validated INTEGER NOT NULL, accessed INTEGER NOT NULL,
            expires INTEGER NOT NULL, body BLOB NOT NULL, PRIMARY KEY(scope,route))""",
            );
            final now = _now();
            for (final e in await _legacy.read() ?? <CachedPageEnvelope>[]) {
              if (!e.isHardExpired(now)) await _put(db, e);
            }
            await _trim(db);
          },
        ),
      );
    } catch (_) {
      // Page loading can continue while cache storage is unavailable.
      _initialization = null;
    }
  }

  static Future<void> _put(
    sql.DatabaseExecutor db,
    CachedPageEnvelope e,
  ) async {
    final body = utf8.encode(jsonEncode(e.payload));
    final size = body.length;
    if (size > maxBytes) {
      await db.delete(
        'pages',
        where: 'scope=? AND route=?',
        whereArgs: [e.authScope, e.routeKey],
      );
      return;
    }
    await db.insert('pages', {
      'scope': e.authScope,
      'route': e.routeKey,
      'body': body,
      'page_type': e.pageType.name,
      'reader_version': e.readerCacheVersion,
      'soft_ttl': e.softTtlSeconds,
      'bytes': size,
      'fetched': e.fetchedAt.microsecondsSinceEpoch,
      'validated': e.validatedAt.microsecondsSinceEpoch,
      'accessed': e.lastAccessedAt.microsecondsSinceEpoch,
      'expires': e.fetchedAt.add(e.hardTtl).microsecondsSinceEpoch,
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  static Future<void> _trim(sql.DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT rowid, bytes FROM pages ORDER BY accessed DESC, rowid DESC',
    );
    var bytes = 0;
    final expired = <int>[];
    for (var i = 0; i < rows.length; i++) {
      bytes += rows[i]['bytes'] as int;
      if (i >= maxEntries || bytes > maxBytes) {
        expired.add(rows[i]['rowid'] as int);
      }
    }
    if (expired.isNotEmpty) {
      await db.delete(
        'pages',
        where: 'rowid IN (${List.filled(expired.length, '?').join(',')})',
        whereArgs: expired,
      );
    }
  }

  Future<CachedPageEnvelope?> read(
    String routeKey, {
    required String authScope,
  }) => _operations.run(() async {
    await ensureInitialized();
    final db = _db;
    if (db == null) return null;
    final now = _now();
    try {
      final rows = await db.query(
        'pages',
        where: 'scope=? AND route=? AND expires>=?',
        whereArgs: [authScope, routeKey, now.microsecondsSinceEpoch],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      await db.update(
        'pages',
        {'accessed': now.microsecondsSinceEpoch},
        where: 'scope=? AND route=?',
        whereArgs: [authScope, routeKey],
      );
      final fetched = row['fetched'] as int;
      return CachedPageEnvelope(
        routeKey: routeKey,
        authScope: authScope,
        pageType: SitePageType.values.byName(row['page_type'] as String),
        readerCacheVersion: row['reader_version'] as int?,
        payload:
            jsonDecode(utf8.decode(row['body'] as List<int>))
                as Map<String, Object?>,
        fetchedAt: DateTime.fromMicrosecondsSinceEpoch(fetched),
        softTtlSeconds: row['soft_ttl'] as int,
        hardTtlSeconds:
            ((row['expires'] as int) - fetched) ~/
            Duration.microsecondsPerSecond,
        validatedAt: DateTime.fromMicrosecondsSinceEpoch(
          row['validated'] as int,
        ),
        lastAccessedAt: now,
      );
    } on sql.DatabaseException {
      return null;
    }
  });

  Future<void> writeEnvelope(CachedPageEnvelope envelope) => _operations.run(
    () async {
      await ensureInitialized();
      try {
        await _db?.transaction((tx) async {
          final now = _now();
          await tx.delete(
            'pages',
            where: 'expires<?',
            whereArgs: [now.microsecondsSinceEpoch],
          );
          await _put(tx, envelope.copyWith(lastAccessedAt: now));
          await _trim(tx);
        });
      } on sql.DatabaseException {
        // Disk cache is best effort. The original result is still deliverable.
      }
    },
  );

  Future<void> refreshValidation(
    String routeKey, {
    required String authScope,
  }) => _operations.run(() async {
    await ensureInitialized();
    final now = _now().microsecondsSinceEpoch;
    await _db?.rawUpdate(
      'UPDATE pages SET expires = ? + (expires - fetched), fetched=?, validated=?, accessed=? WHERE scope=? AND route=?',
      [now, now, now, now, authScope, routeKey],
    );
  });

  Future<void> removeAuthenticatedEntries() => _operations.run(() async {
    await ensureInitialized();
    await _db?.delete('pages', where: "scope != 'guest'");
    // An explicit logout also clears account pages from the old primary and backup.
    await _legacy.update(
      (old) => old!.where((entry) => entry.authScope == 'guest').toList(),
      whenEitherCopy: (entries) =>
          entries.any((entry) => entry.authScope != 'guest'),
    );
  });

  Future<void> close() => _operations.run(() async {
    await _initialization;
    await _db?.close();
    _db = null;
    _initialization = null;
  });

  static CachedPageEnvelope buildEnvelope({
    required String routeKey,
    required SitePage page,
    required String authScope,
    DateTime? now,
  }) {
    final PageCachePolicy policy = PageCachePolicy.forPage(page);
    final DateTime timestamp = now ?? DateTime.now();
    return CachedPageEnvelope(
      routeKey: routeKey,
      pageType: page.type,
      payload: _cachePayloadForPage(page),
      readerCacheVersion: page.type == SitePageType.reader
          ? readerCacheVersion
          : null,
      fetchedAt: timestamp,
      validatedAt: timestamp,
      lastAccessedAt: timestamp,
      softTtlSeconds: policy.softTtl.inSeconds,
      hardTtlSeconds: policy.hardTtl.inSeconds,
      authScope: authScope,
    );
  }

  static const Set<String> _rootPayloadKeys = <String>{'type', 'title', 'uri'};

  static Map<String, Object?> _cachePayloadForPage(SitePage page) {
    final payload = page is DetailPageData
        ? page.toJson(includeFlatChapters: page.chapterGroups.isEmpty)
        : page.toJson();
    return _compactMap(payload, isRoot: true);
  }

  static Map<String, Object?> _compactMap(
    Map<String, Object?> source, {
    required bool isRoot,
  }) {
    final Map<String, Object?> compacted = <String, Object?>{};
    source.forEach((String key, Object? value) {
      final Object? nextValue = _compactValue(value);
      if (nextValue == null) {
        if (isRoot && _rootPayloadKeys.contains(key)) {
          compacted[key] = value;
        }
        return;
      }
      compacted[key] = nextValue;
    });
    return compacted;
  }

  static Object? _compactValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value.isEmpty ? null : value;
    }
    if (value is List) {
      final List<Object?> items = value
          .map(_compactValue)
          .where((Object? item) => item != null)
          .toList(growable: false);
      return items.isEmpty ? null : items;
    }
    if (value is Map) {
      final map = value.cast<String, Object?>();
      final Map<String, Object?> compacted = _compactMap(map, isRoot: false);
      return compacted.isEmpty ? null : compacted;
    }
    return value;
  }

  static SitePage restorePage(
    CachedPageEnvelope envelope, {
    HostManager? hostManager,
  }) {
    return restorePagePayload(envelope.payload, hostManager: hostManager);
  }

  static SitePage restorePagePayload(
    Map<String, Object?> payload, {
    HostManager? hostManager,
  }) {
    final HostManager manager = hostManager ?? HostManager.instance;
    return SitePage.fromJson(
      _rewritePayloadHosts(payload, manager) as Map<String, Object?>,
    );
  }

  static Object? _rewritePayloadHosts(Object? value, HostManager manager) {
    if (value is String) {
      if (!value.contains('://')) return value;
      final Uri? uri = Uri.tryParse(value);
      if (uri != null &&
          uri.hasScheme &&
          AppConfig.isAllowedNavigationUri(uri)) {
        return manager.rewriteToCurrentHost(uri).toString();
      }
      return value;
    }
    if (value is List) {
      return value
          .map((Object? item) => _rewritePayloadHosts(item, manager))
          .toList();
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? nestedValue) => MapEntry(
          key.toString(),
          _rewritePayloadHosts(nestedValue, manager),
        ),
      );
    }
    return value;
  }
}
