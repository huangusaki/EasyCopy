import 'dart:async';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/services/app_preferences_store.dart';
import 'package:flutter/foundation.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({
    AppPreferencesStore? store,
    AppPreferences initialPreferences = const AppPreferences(),
  }) : _store = store ?? AppPreferencesStore(),
       _preferences = initialPreferences;

  static final AppPreferencesController instance = AppPreferencesController();

  final AppPreferencesStore _store;

  AppPreferences _preferences;
  Future<void>? _initialization;
  Future<void> _persistChain = Future<void>.value();

  AppPreferences get preferences => _preferences;

  AppThemePreference get themePreference => _preferences.themePreference;

  ReaderPreferences get readerPreferences => _preferences.readerPreferences;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> setThemePreference(AppThemePreference preference) {
    return _replacePreferences(
      _preferences.copyWith(themePreference: preference),
    );
  }

  Future<void> updateReaderPreferences(
    ReaderPreferences Function(ReaderPreferences current) transform,
  ) {
    return _replacePreferences(
      _preferences.copyWith(
        readerPreferences: transform(_preferences.readerPreferences),
      ),
    );
  }

  Future<void> _initialize() async {
    _preferences = await _store.read();
  }

  Future<void> _replacePreferences(AppPreferences nextPreferences) async {
    await ensureInitialized();
    if (nextPreferences == _preferences) {
      return;
    }
    _preferences = nextPreferences;
    notifyListeners();
    _persistChain = _persistChain.then((_) => _store.write(_preferences));
    unawaited(_persistChain);
  }
}
