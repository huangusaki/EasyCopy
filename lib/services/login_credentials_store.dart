import 'dart:convert';

import 'package:reader/services/host_manager.dart';
import 'package:reader/services/key_value_store.dart';

class SavedLoginCredentials {
  const SavedLoginCredentials({required this.username, required this.password});

  factory SavedLoginCredentials.fromJson(Map<String, Object?> json) {
    return SavedLoginCredentials(
      username: (json['username'] as String?)?.trim() ?? '',
      password: (json['password'] as String?)?.trim() ?? '',
    );
  }

  final String username;
  final String password;

  bool get isEmpty => username.isEmpty || password.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{'username': username, 'password': password};
  }
}

class LoginCredentialsStore {
  LoginCredentialsStore({KeyValueStore? store})
    : _store = store ?? SecureKeyValueStore();

  static final LoginCredentialsStore instance = LoginCredentialsStore();
  static const String _credentialsKey = 'easy_copy.login_credentials';

  final KeyValueStore _store;

  Future<SavedLoginCredentials?> read({String? siteKey}) async {
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final String? rawValue = await _store.read(_credentialsKey);
    if ((rawValue ?? '').trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(rawValue!);
      if (decoded is! Map) {
        return null;
      }
      final Map<String, Object?> root = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final Map<String, Object?> sites = _mapValue(root['sites']);
      final Map<String, Object?> credentialsJson = sites.isEmpty
          ? (normalizedSiteKey == HostManager.copySiteKey
                ? root
                : const <String, Object?>{})
          : _mapValue(sites[normalizedSiteKey]);
      if (credentialsJson.isEmpty) {
        return null;
      }
      final SavedLoginCredentials credentials =
          SavedLoginCredentials.fromJson(credentialsJson);
      return credentials.isEmpty ? null : credentials;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    String? siteKey,
    required String username,
    required String password,
  }) async {
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final SavedLoginCredentials credentials = SavedLoginCredentials(
      username: username.trim(),
      password: password.trim(),
    );
    if (credentials.isEmpty) {
      await clear(siteKey: normalizedSiteKey);
      return;
    }
    final Map<String, Object?> payload = await _readRoot();
    final Map<String, Object?> sites = _credentialsBySite(payload);
    sites[normalizedSiteKey] = credentials.toJson();
    await _store.write(
      _credentialsKey,
      jsonEncode(<String, Object?>{'sites': sites}),
    );
  }

  Future<void> clear({String? siteKey}) async {
    final String normalizedSiteKey = _normalizeSiteKey(siteKey);
    final Map<String, Object?> payload = await _readRoot();
    final Map<String, Object?> sites = _credentialsBySite(payload);
    sites.remove(normalizedSiteKey);
    if (sites.isEmpty) {
      await _store.delete(_credentialsKey);
      return;
    }
    await _store.write(
      _credentialsKey,
      jsonEncode(<String, Object?>{'sites': sites}),
    );
  }

  Future<Map<String, Object?>> _readRoot() async {
    final String? rawValue = await _store.read(_credentialsKey);
    if ((rawValue ?? '').trim().isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(rawValue!);
      if (decoded is! Map) {
        return const <String, Object?>{};
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  Map<String, Object?> _credentialsBySite(Map<String, Object?> root) {
    final Map<String, Object?> sites = <String, Object?>{
      ..._mapValue(root['sites']),
    };
    if (sites.isEmpty && root.containsKey('username')) {
      sites[HostManager.copySiteKey] = root;
    }
    return sites;
  }

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
}
