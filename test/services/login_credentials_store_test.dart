import 'package:easy_copy/services/key_value_store.dart';
import 'package:easy_copy/services/login_credentials_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginCredentialsStore', () {
    late _MemoryKeyValueStore backingStore;
    late LoginCredentialsStore store;

    setUp(() {
      backingStore = _MemoryKeyValueStore();
      store = LoginCredentialsStore(store: backingStore);
    });

    test('saves and restores credentials', () async {
      await store.save(username: 'alice', password: 'secret');

      final SavedLoginCredentials? credentials = await store.read();

      expect(credentials, isNotNull);
      expect(credentials!.username, 'alice');
      expect(credentials.password, 'secret');
    });

    test('clears credentials when asked', () async {
      await store.save(username: 'alice', password: 'secret');

      await store.clear();

      expect(await store.read(), isNull);
    });
  });
}

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
