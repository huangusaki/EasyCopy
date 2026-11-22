import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader/services/key_value_store.dart';
import 'package:reader/services/persistence/serial_executor.dart';

class SiteSessionSnapshot {
  const SiteSessionSnapshot({
    required this.token,
    required this.cookies,
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
      userId: json['userId'] as String?,
    );
  }

  final String token;
  final Map<String, String> cookies;
  final String? userId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'token': token,
      'cookies': cookies,
      'userId': userId,
    };
  }
}

class SiteSession {
  SiteSession({KeyValueStore? store}) : _store = store ?? SecureKeyValueStore();

  static final SiteSession instance = SiteSession();

  static const String _sessionKey = 'easy_copy.session';

  final KeyValueStore _store;
  final SerialExecutor _writes = SerialExecutor();

  Future<void>? _initialization;
  int _generation = 0;
  String? _token;
  String? _userId;
  Map<String, String> _cookies = const {};

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

  Map<String, String> get cookies => _cookies;

  String? _cookieHeader;
  String get cookieHeader => _cookieHeader ??= _cookies.entries
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
    _token = token;
    _cookieHeader = null;
    _cookies = Map.unmodifiable({
      if (cookies != null) ...cookies,
      'token': token,
    });
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
    _cookieHeader = null;
    _cookies = Map.unmodifiable({...cookies, 'token': token});
    await _persist();
    return _generation == expectedGeneration;
  }

  Future<void> bindUserId(String? userId, {int? expectedGeneration}) async {
    await ensureInitialized();
    if (expectedGeneration != null && _generation != expectedGeneration) return;
    final String? next = (userId ?? '').trim().isEmpty ? null : userId!.trim();
    if (_userId == next) return;
    _userId = next;
    await _persist();
  }

  Future<void> clear() async {
    _generation += 1;
    _token = null;
    _userId = null;
    _cookieHeader = null;
    _cookies = const {};
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
      _cookies = Map.unmodifiable(snapshot.cookies);
      _cookieHeader = null;
      _userId = snapshot.userId;
    } catch (_) {
      // Ignore corrupted session storage.
    }
  }

  Future<void> _persist() async {
    final SiteSessionSnapshot snapshot = SiteSessionSnapshot(
      token: _token ?? '',
      cookies: _cookies,
      userId: _userId,
    );
    final String encoded = jsonEncode(snapshot.toJson());
    await _writes.run(() => _store.write(_sessionKey, encoded));
  }

  static String cookieFingerprint(Map<String, String> cookies) {
    final List<String> entries =
        cookies.entries
            .map(
              (MapEntry<String, String> cookie) =>
                  '${cookie.key}=${cookie.value}',
            )
            .toList()
          ..sort();
    return entries.join(';');
  }

  static String cookieScript(Map<String, String> cookies) {
    final String statements = cookies.entries
        .where(
          (MapEntry<String, String> cookie) =>
              cookie.key.trim().isNotEmpty && cookie.value.trim().isNotEmpty,
        )
        .map((MapEntry<String, String> cookie) {
          // WebView2 进程重启会丢会话 Cookie。
          final String value =
              '${cookie.key}=${cookie.value}; path=/; max-age=2592000';
          return 'document.cookie = ${jsonEncode(value)};';
        })
        .join('\n');
    return '(() => {$statements})();';
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
