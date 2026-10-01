import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureStorageException implements Exception {
  const SecureStorageException(this.cause);

  final PlatformException cause;

  @override
  String toString() => '登录信息暂时不可用，请重试。';
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: androidOptions);

  // Keep the existing namespace so v9 data can migrate before any reset.
  static const AndroidOptions androidOptions = AndroidOptions(
    resetOnError: true,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _run(() => _storage.read(key: key));
  }

  @override
  Future<void> write(String key, String value) {
    return _run(() => _storage.write(key: key, value: value));
  }

  @override
  Future<void> delete(String key) {
    return _run(() => _storage.delete(key: key));
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      throw SecureStorageException(error);
    }
  }
}
