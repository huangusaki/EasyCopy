import 'dart:async';

import 'package:easy_copy/config/app_config.dart';
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

  int get lastPrimaryTabIndex => _preferences.lastPrimaryTabIndex;

  ReaderPreferences get readerPreferences => _preferences.readerPreferences;

  DownloadPreferences get downloadPreferences =>
      _preferences.downloadPreferences;

  WallpaperPreferences get wallpaperPreferences =>
      _preferences.wallpaperPreferences;

  ProfileCollectionSort get profileCollectionSort =>
      _preferences.profileCollectionSort;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> setThemePreference(AppThemePreference preference) {
    return _replacePreferences(
      _preferences.copyWith(themePreference: preference),
    );
  }

  Future<void> setLastPrimaryTabIndex(int index) async {
    await ensureInitialized();
    final int normalizedIndex = index.clamp(0, 3).toInt();
    if (_preferences.lastPrimaryTabIndex == normalizedIndex) {
      return;
    }
    return _replacePreferences(
      _preferences.copyWith(lastPrimaryTabIndex: normalizedIndex),
    );
  }

  Future<void> setProfileCollectionSort(ProfileCollectionSort sort) {
    return _replacePreferences(
      _preferences.copyWith(profileCollectionSort: sort),
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

  Future<void> updateDownloadPreferences(
    DownloadPreferences Function(DownloadPreferences current) transform,
  ) {
    return _replacePreferences(
      _preferences.copyWith(
        downloadPreferences: transform(_preferences.downloadPreferences),
      ),
    );
  }

  Future<void> updateWallpaperPreferences(
    WallpaperPreferences Function(WallpaperPreferences current) transform, {
    bool persist = true,
  }) {
    return _replacePreferences(
      _preferences.copyWith(
        wallpaperPreferences: transform(_preferences.wallpaperPreferences),
      ),
      persist: persist,
    );
  }

  Future<void> _initialize() async {
    _preferences = await _store.read();
  }

  Future<void> _replacePreferences(
    AppPreferences nextPreferences, {
    bool persist = true,
  }) async {
    await ensureInitialized();
    if (nextPreferences == _preferences) {
      return;
    }
    _preferences = nextPreferences;
    notifyListeners();
    if (!persist) {
      return;
    }
    final AppPreferences preferencesToPersist = nextPreferences;
    _persistChain = _persistChain.then(
      (_) => _store.write(preferencesToPersist),
    );
    await _persistChain;
  }
}
