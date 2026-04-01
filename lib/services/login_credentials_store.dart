import 'dart:convert';

import 'package:easy_copy/services/key_value_store.dart';

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

  Future<SavedLoginCredentials?> read() async {
    final String? rawValue = await _store.read(_credentialsKey);
    if ((rawValue ?? '').trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(rawValue!);
      if (decoded is! Map) {
        return null;
      }
      final SavedLoginCredentials credentials = SavedLoginCredentials.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
      return credentials.isEmpty ? null : credentials;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String username,
    required String password,
  }) async {
    final SavedLoginCredentials credentials = SavedLoginCredentials(
      username: username.trim(),
      password: password.trim(),
    );
    if (credentials.isEmpty) {
      await clear();
      return;
    }
    await _store.write(_credentialsKey, jsonEncode(credentials.toJson()));
  }

  Future<void> clear() {
    return _store.delete(_credentialsKey);
  }
}
