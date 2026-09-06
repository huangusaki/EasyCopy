import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

typedef AppPreferencesDirectoryProvider = Future<Directory> Function();

class AppPreferencesStore {
  AppPreferencesStore({AppPreferencesDirectoryProvider? directoryProvider})
    : _file = AtomicJsonFile<AppPreferences>(
        directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
        relativePath: 'app_preferences.json',
        decode: (Object? json) =>
            AppPreferences.fromJson(Map<String, Object?>.from(json as Map)),
        encode: (AppPreferences preferences) => preferences.toJson(),
      );

  final AtomicJsonFile<AppPreferences> _file;

  Future<AppPreferences> read() async {
    try {
      return await _file.read() ?? const AppPreferences();
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> write(AppPreferences preferences) => _file.write(preferences);
}
