import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/key_value_store.dart';

typedef SessionNowProvider = DateTime Function();

class SiteSessionSnapshot {
  const SiteSessionSnapshot({
    required this.token,
    required this.cookies,
    required this.updatedAt,
    this.userId,
  });

  factory SiteSessionSnapshot.fromJson(Map<String, Object?> json) {
    return SiteSessionSnapshot(
      token: (json['token'] as String?) ?? '',
      cookies:
          ((json['cookies'] as Map<Object?, Object?>?) ??
                  const <Object?, Object?>{})
              .map(
                (Object? key, Object? value) =>
                    MapEntry(key.toString(), value?.toString() ?? ''),
              ),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      userId: json['userId'] as String?,
    );
  }

  final String token;
  final Map<String, String> cookies;
  final DateTime updatedAt;
  final String? userId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'token': token,
      'cookies': cookies,
      'updatedAt': updatedAt.toIso8601String(),
      'userId': userId,
    };
  }
}

class SiteSession {
  SiteSession({KeyValueStore? store, SessionNowProvider? now})
    : _store = store ?? SecureKeyValueStore(),
      _now = now ?? DateTime.now;

  static final SiteSession instance = SiteSession();

  static const String _sessionKey = 'easy_copy.session';

  final KeyValueStore _store;
  final SessionNowProvider _now;

  Future<void>? _initialization;
  String _activeSiteKey = HostManager.copySiteKey;
  final Map<String, SiteSessionSnapshot> _sessions =
      <String, SiteSessionSnapshot>{};

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  String get activeSiteKey => _activeSiteKey;

  String? get token {
    final String token = _activeSnapshot.token.trim();
    return token.isEmpty ? null : token;
  }

  String? get userId {
    final String? userId = _activeSnapshot.userId?.trim();
    return (userId ?? '').isEmpty ? null : userId;
  }

  bool get isAuthenticated => (token ?? '').isNotEmpty;

  Map<String, String> get cookies =>
      Map<String, String>.unmodifiable(_activeSnapshot.cookies);

  String get cookieHeader => _cookies.entries
      .where((MapEntry<String, String> entry) => entry.value.trim().isNotEmpty)
      .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
      .join('; ');

  String get authScope {
    return _authScopeForSnapshot(_activeSiteKey, _activeSnapshot);
  }

  String get guestAuthScope => '$_activeSiteKey:guest';

  Future<void> switchSite(String siteKey) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    if (_activeSiteKey == normalizedSiteKey) {
      return;
    }
    _activeSiteKey = normalizedSiteKey;
    await _persist();
  }

  Future<void> saveToken(String token, {Map<String, String>? cookies}) async {
    await ensureInitialized();
    _sessions[_activeSiteKey] = SiteSessionSnapshot(
      token: token,
      cookies: <String, String>{
        if (cookies != null) ...cookies,
        'token': token,
      },
      updatedAt: _now(),
    );
    await _persist();
  }

  Future<void> bindUserId(String? userId) async {
    await ensureInitialized();
    final SiteSessionSnapshot current = _activeSnapshot;
    _sessions[_activeSiteKey] = SiteSessionSnapshot(
      token: current.token,
      cookies: current.cookies,
      updatedAt: _now(),
      userId: (userId ?? '').trim().isEmpty ? null : userId?.trim(),
    );
    await _persist();
  }

  Future<void> updateFromCookieHeader(String cookieHeader) async {
    await ensureInitialized();
    final Map<String, String> parsedCookies = parseCookieHeader(cookieHeader);
    if (parsedCookies.isEmpty) {
      return;
    }
    final SiteSessionSnapshot current = _activeSnapshot;
    final Map<String, String> nextCookies = <String, String>{
      ...current.cookies,
      ...parsedCookies,
    };
    final String? nextToken = parsedCookies['token'];
    _sessions[_activeSiteKey] = SiteSessionSnapshot(
      token: (nextToken ?? '').isNotEmpty ? nextToken! : current.token,
      cookies: nextCookies,
      updatedAt: _now(),
      userId: current.userId,
    );
    await _persist();
  }

  Future<void> clear() async {
    await ensureInitialized();
    _sessions.remove(_activeSiteKey);
    await _persist();
  }

  Future<void> _initialize() async {
    final String? rawSnapshot = await _store.read(_sessionKey);
    if ((rawSnapshot ?? '').isEmpty) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(rawSnapshot!);
      if (decoded is! Map) {
        return;
      }
      final Map<String, Object?> root = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final Map<String, Object?> sessions = _mapValue(root['sessions']);
      if (sessions.isNotEmpty) {
        _activeSiteKey = _normalizeSiteKey(root['activeSiteKey'] as String?);
        for (final MapEntry<String, Object?> entry in sessions.entries) {
          final Map<String, Object?> snapshotJson = _mapValue(entry.value);
          if (snapshotJson.isEmpty) {
            continue;
          }
          final SiteSessionSnapshot snapshot = SiteSessionSnapshot.fromJson(
            snapshotJson,
          );
          if (snapshot.token.isEmpty && snapshot.cookies.isEmpty) {
            continue;
          }
          _sessions[_normalizeSiteKey(entry.key)] = snapshot;
        }
        return;
      }

      final SiteSessionSnapshot legacySnapshot = SiteSessionSnapshot.fromJson(
        root,
      );
      if (legacySnapshot.token.isNotEmpty ||
          legacySnapshot.cookies.isNotEmpty) {
        _sessions[HostManager.copySiteKey] = legacySnapshot;
      }
    } catch (_) {
      // Ignore corrupted session storage.
    }
  }

  Future<void> _persist() async {
    final Map<String, Object?> payload = <String, Object?>{
      'activeSiteKey': _activeSiteKey,
      'sessions': _sessions.map((String siteKey, SiteSessionSnapshot snapshot) {
        return MapEntry(siteKey, snapshot.toJson());
      }),
    };
    await _store.write(_sessionKey, jsonEncode(payload));
  }

  SiteSessionSnapshot get _activeSnapshot {
    return _sessions[_activeSiteKey] ??
        SiteSessionSnapshot(
          token: '',
          cookies: const <String, String>{},
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
  }

  Map<String, String> get _cookies => _activeSnapshot.cookies;

  static String _normalizeSiteKey(String? siteKey) {
    final String normalized = (siteKey ?? '').trim().toLowerCase();
    return normalized == HostManager.hotSiteKey
        ? HostManager.hotSiteKey
        : HostManager.copySiteKey;
  }

  static Map<String, Object?> _mapValue(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, Object?>{};
  }

  static String _authScopeForSnapshot(
    String siteKey,
    SiteSessionSnapshot snapshot,
  ) {
    final String prefix = _normalizeSiteKey(siteKey);
    final String token = snapshot.token.trim();
    if (token.isEmpty) {
      return '$prefix:guest';
    }
    final String? userId = snapshot.userId?.trim();
    if ((userId ?? '').isNotEmpty) {
      return '$prefix:user:$userId';
    }
    return '$prefix:token:${sha1.convert(utf8.encode(token)).toString()}';
  }

  Future<void> clearAll() async {
    await ensureInitialized();
    _sessions.clear();
    await _store.delete(_sessionKey);
  }

  Future<void> clearSite(String siteKey) async {
    await ensureInitialized();
    _sessions.remove(_normalizeSiteKey(siteKey));
    await _persist();
  }

  Future<void> saveTokenForSite(
    String siteKey,
    String token, {
    Map<String, String>? cookies,
  }) async {
    await switchSite(siteKey);
    await saveToken(token, cookies: cookies);
  }

  Future<void> updateFromCookieHeaderForSite(
    String siteKey,
    String cookieHeader,
  ) async {
    await switchSite(siteKey);
    await updateFromCookieHeader(cookieHeader);
  }

  Future<void> bindUserIdForSite(String siteKey, String? userId) async {
    await switchSite(siteKey);
    await bindUserId(userId);
  }

  SiteSessionSnapshot snapshotForSite(String siteKey) {
    return _sessions[_normalizeSiteKey(siteKey)] ??
        SiteSessionSnapshot(
          token: '',
          cookies: const <String, String>{},
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
  }

  String authScopeForSite(String siteKey) {
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    return _authScopeForSnapshot(
      normalizedSiteKey,
      snapshotForSite(normalizedSiteKey),
    );
  }

  String guestAuthScopeForSite(String siteKey) {
    return '${_normalizeSiteKey(siteKey)}:guest';
  }

  bool isAuthenticatedForSite(String siteKey) {
    return snapshotForSite(siteKey).token.trim().isNotEmpty;
  }

  String cookieHeaderForSite(String siteKey) {
    final Map<String, String> targetCookies = snapshotForSite(siteKey).cookies;
    return targetCookies.entries
        .where(
          (MapEntry<String, String> entry) => entry.value.trim().isNotEmpty,
        )
        .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  String? tokenForSite(String siteKey) {
    final String token = snapshotForSite(siteKey).token.trim();
    return token.isEmpty ? null : token;
  }

  Map<String, String> cookiesForSite(String siteKey) {
    return Map<String, String>.unmodifiable(snapshotForSite(siteKey).cookies);
  }

  static Map<String, String> parseCookieHeader(String cookieHeader) {
    final Map<String, String> cookies = <String, String>{};
    for (final String segment in cookieHeader.split(';')) {
      final String trimmed = segment.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) {
        continue;
      }
      final int separatorIndex = trimmed.indexOf('=');
      final String key = trimmed.substring(0, separatorIndex).trim();
      final String value = trimmed.substring(separatorIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      cookies[key] = value;
    }
    return cookies;
  }
}
