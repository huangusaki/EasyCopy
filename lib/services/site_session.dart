import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader/services/key_value_store.dart';
import 'package:reader/services/persistence/serial_executor.dart';

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
  final SerialExecutor _writes = SerialExecutor();

  Future<void>? _initialization;
  int _generation = 0;
  String? _token;
  String? _userId;
  Map<String, String> _cookies = <String, String>{};

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  String? get token => _token;

  String? get userId => _userId;

  int get generation => _generation;

  bool get isAuthenticated => (_token ?? '').isNotEmpty;

  Map<String, String> get cookies => Map<String, String>.unmodifiable(_cookies);

  String get cookieHeader => _cookies.entries
      .where((MapEntry<String, String> entry) => entry.value.trim().isNotEmpty)
      .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
      .join('; ');

  String get authScope {
    if (!isAuthenticated) {
      return 'guest';
    }
    if ((_userId ?? '').isNotEmpty) {
      return 'user:${_userId!}';
    }
    return 'token:${sha1.convert(utf8.encode(_token!)).toString()}';
  }

  Future<void> saveToken(String token, {Map<String, String>? cookies}) async {
    await ensureInitialized();
    _generation += 1;
    _userId = null;
    _cookies = <String, String>{};
    _token = token;
    _cookies = <String, String>{
      if (cookies != null) ...cookies,
      'token': token,
    };
    await _persist();
  }

  /// Preserve account identity and reject renewal after an explicit session change.
  Future<bool> renewToken(
    String token, {
    required Map<String, String> cookies,
    required int expectedGeneration,
    required String expiredToken,
  }) async {
    await ensureInitialized();
    if (_generation != expectedGeneration || _token != expiredToken) {
      return false;
    }
    _token = token;
    _cookies = <String, String>{...cookies, 'token': token};
    await _persist();
    return _generation == expectedGeneration;
  }

  Future<void> bindUserId(String? userId, {int? expectedGeneration}) async {
    await ensureInitialized();
    if (expectedGeneration != null && _generation != expectedGeneration) return;
    _userId = (userId ?? '').trim().isEmpty ? null : userId?.trim();
    await _persist();
  }

  Future<void> updateFromCookieHeader(String cookieHeader) async {
    await ensureInitialized();
    final Map<String, String> parsedCookies = parseCookieHeader(cookieHeader);
    if (parsedCookies.isEmpty) {
      return;
    }
    _cookies = <String, String>{..._cookies, ...parsedCookies};
    final String? nextToken = parsedCookies['token'];
    if ((nextToken ?? '').isNotEmpty) {
      if (_token != nextToken) _generation += 1;
      _token = nextToken;
    }
    await _persist();
  }

  Future<void> clear() async {
    _generation += 1;
    _token = null;
    _userId = null;
    _cookies = <String, String>{};
    await _writes.run(() => _store.delete(_sessionKey));
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
      final SiteSessionSnapshot snapshot = SiteSessionSnapshot.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
      _token = snapshot.token.isEmpty ? null : snapshot.token;
      _cookies = snapshot.cookies;
      _userId = snapshot.userId;
    } catch (_) {
      // Ignore corrupted session storage.
    }
  }

  Future<void> _persist() async {
    final SiteSessionSnapshot snapshot = SiteSessionSnapshot(
      token: _token ?? '',
      cookies: _cookies,
      updatedAt: _now(),
      userId: _userId,
    );
    final String encoded = jsonEncode(snapshot.toJson());
    await _writes.run(() => _store.write(_sessionKey, encoded));
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
