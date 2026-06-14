import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/host_manager.dart';

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
    required this.fingerprint,
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
      fingerprint: (json['fingerprint'] as String?) ?? '',
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
  final String fingerprint;
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
    String? fingerprint,
    Map<String, Object?>? payload,
    String? authScope,
  }) {
    return CachedPageEnvelope(
      routeKey: routeKey,
      pageType: pageType,
      payload: payload ?? this.payload,
      fingerprint: fingerprint ?? this.fingerprint,
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
      'fingerprint': fingerprint,
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
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  static final PageCacheStore instance = PageCacheStore();

  static const int maxEntries = 120;
  static const int maxBytes = 10 * 1024 * 1024;

  final CacheDirectoryProvider _directoryProvider;
  final CacheNowProvider _now;

  Future<void>? _initialization;
  List<CachedPageEnvelope> _entries = <CachedPageEnvelope>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<CachedPageEnvelope?> read(
    String routeKey, {
    required String authScope,
  }) async {
    await ensureInitialized();
    final DateTime now = _now();
    final int entryCountBeforePrune = _entries.length;
    _entries = _entries
        .where((CachedPageEnvelope entry) => !entry.isHardExpired(now))
        .toList(growable: true);
    final bool prunedExpiredEntries = _entries.length != entryCountBeforePrune;
    final int index = _entries.indexWhere((CachedPageEnvelope entry) {
      return entry.routeKey == routeKey && entry.authScope == authScope;
    });
    if (index == -1) {
      if (prunedExpiredEntries) {
        await _persist();
      }
      return null;
    }
    final CachedPageEnvelope entry = _entries[index].copyWith(
      lastAccessedAt: now,
    );
    _entries[index] = entry;
    if (prunedExpiredEntries) {
      await _persist();
    }
    return entry;
  }

  Future<void> writeEnvelope(CachedPageEnvelope envelope) async {
    await ensureInitialized();
    _entries.removeWhere((CachedPageEnvelope entry) {
      return entry.routeKey == envelope.routeKey &&
          entry.authScope == envelope.authScope;
    });
    _entries.add(envelope.copyWith(lastAccessedAt: _now()));
    _trimToBudget();
    await _persist();
  }

  Future<void> refreshValidation(
    String routeKey, {
    required String authScope,
  }) async {
    await ensureInitialized();
    final DateTime now = _now();
    _entries = _entries
        .map((CachedPageEnvelope entry) {
          if (entry.routeKey == routeKey && entry.authScope == authScope) {
            return entry.copyWith(
              fetchedAt: now,
              validatedAt: now,
              lastAccessedAt: now,
            );
          }
          return entry;
        })
        .toList(growable: true);
    await _persist();
  }

  Future<void> removeAuthScope(String authScope) async {
    await ensureInitialized();
    _entries.removeWhere((CachedPageEnvelope entry) {
      return entry.authScope == authScope;
    });
    await _persist();
  }

  Future<void> removeAuthenticatedEntries() async {
    await ensureInitialized();
    _entries.removeWhere((CachedPageEnvelope entry) {
      return entry.authScope != 'guest';
    });
    await _persist();
  }

  Future<void> clear() async {
    _entries = <CachedPageEnvelope>[];
    await _persist();
  }

  Future<void> _initialize() async {
    try {
      final File file = await _cacheFile();
      if (!await file.exists()) {
        return;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return;
      }
      _entries = decoded
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> value) => CachedPageEnvelope.fromJson(
              value.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: true);
    } catch (_) {
      _entries = <CachedPageEnvelope>[];
    }
  }

  Future<File> _cacheFile() async {
    final Directory directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}page_cache.json');
  }

  void _trimToBudget() {
    _entries.sort((CachedPageEnvelope left, CachedPageEnvelope right) {
      return left.lastAccessedAt.compareTo(right.lastAccessedAt);
    });
    while (_entries.length > maxEntries || _serializedSize() > maxBytes) {
      if (_entries.isEmpty) {
        break;
      }
      _entries.removeAt(0);
    }
  }

  int _serializedSize() {
    return utf8
        .encode(
          jsonEncode(
            _entries.map((CachedPageEnvelope entry) => entry.toJson()).toList(),
          ),
        )
        .length;
  }

  Future<void> _persist() async {
    try {
      final File file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(
          _entries.map((CachedPageEnvelope entry) => entry.toJson()).toList(),
        ),
      );
    } catch (_) {
      // Best-effort persistence only.
    }
  }

  static CachedPageEnvelope buildEnvelope({
    required String routeKey,
    required SitePage page,
    required String fingerprint,
    required String authScope,
    DateTime? now,
  }) {
    final PageCachePolicy policy = PageCachePolicy.forPage(page);
    final DateTime timestamp = now ?? DateTime.now();
    return CachedPageEnvelope(
      routeKey: routeKey,
      pageType: page.type,
      payload: _cachePayloadForPage(page),
      fingerprint: fingerprint,
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
    final Map<String, Object?> payload = Map<String, Object?>.from(
      page.toJson(),
    );
    if (page is DetailPageData && page.chapterGroups.isNotEmpty) {
      // `chapterGroups` already contains full chapter metadata. Keeping
      // duplicated flattened `chapters` significantly increases cache size.
      payload.remove('chapters');
    }
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
      final Map<String, Object?> map = value.map(
        (Object? key, Object? nestedValue) =>
            MapEntry(key.toString(), nestedValue),
      );
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
