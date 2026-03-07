import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:path_provider/path_provider.dart';

typedef AppPreferencesDirectoryProvider = Future<Directory> Function();

class AppPreferencesStore {
  AppPreferencesStore({
    AppPreferencesDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final AppPreferencesDirectoryProvider _directoryProvider;

  Future<AppPreferences> read() async {
    try {
      final File file = await _preferencesFile();
      if (!await file.exists()) {
        return const AppPreferences();
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const AppPreferences();
      }
      return AppPreferences.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> write(AppPreferences preferences) async {
    try {
      final File file = await _preferencesFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
      );
    } catch (_) {
      // Best-effort persistence only.
    }
  }

  Future<File> _preferencesFile() async {
    final Directory directory = await _directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}app_preferences.json',
    );
  }
}
