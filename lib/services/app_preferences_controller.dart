import 'package:flutter/foundation.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/shortcut_preferences.dart';
import 'package:reader/services/app_preferences_store.dart';
import 'package:reader/services/persistence/serial_executor.dart';

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
  final SerialExecutor _updates = SerialExecutor();
  final SerialExecutor _writes = SerialExecutor();

  AppPreferences get preferences => _preferences;

  AppThemePreference get themePreference => _preferences.themePreference;

  int get lastPrimaryTabIndex => _preferences.lastPrimaryTabIndex;

  ReaderPreferences get readerPreferences => _preferences.readerPreferences;

  DownloadPreferences get downloadPreferences =>
      _preferences.downloadPreferences;

  WallpaperPreferences get wallpaperPreferences =>
      _preferences.wallpaperPreferences;

  ShortcutPreferences get shortcutPreferences =>
      _preferences.shortcutPreferences;

  ProfileCollectionSort get profileCollectionSort =>
      _preferences.profileCollectionSort;

  ChineseConversionMode get chineseConversionMode =>
      _preferences.chineseConversionMode;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> setThemePreference(AppThemePreference preference) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(themePreference: preference),
    );
  }

  Future<void> setLastPrimaryTabIndex(int index) {
    return _updatePreferences((AppPreferences current) {
      final int normalizedIndex = index.clamp(0, 3).toInt();
      return current.lastPrimaryTabIndex == normalizedIndex
          ? current
          : current.copyWith(lastPrimaryTabIndex: normalizedIndex);
    });
  }

  Future<void> setProfileCollectionSort(ProfileCollectionSort sort) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(profileCollectionSort: sort),
    );
  }

  Future<void> updateReaderPreferences(
    ReaderPreferences Function(ReaderPreferences current) transform,
  ) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(
        readerPreferences: transform(current.readerPreferences),
      ),
    );
  }

  /// Storage migration may remove its source only after this commit succeeds.
  Future<void> updateDownloadPreferences(
    DownloadPreferences Function(DownloadPreferences current) transform,
  ) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(
        downloadPreferences: transform(current.downloadPreferences),
      ),
      requirePersistence: true,
    );
  }

  Future<void> updateShortcutPreferences(
    ShortcutPreferences Function(ShortcutPreferences current) transform,
  ) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(
        shortcutPreferences: transform(current.shortcutPreferences),
      ),
    );
  }

  Future<void> setChineseConversionMode(ChineseConversionMode mode) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(chineseConversionMode: mode),
    );
  }

  Future<void> updateWallpaperPreferences(
    WallpaperPreferences Function(WallpaperPreferences current) transform, {
    bool persist = true,
  }) {
    return _updatePreferences(
      (AppPreferences current) => current.copyWith(
        wallpaperPreferences: transform(current.wallpaperPreferences),
      ),
      persist: persist,
    );
  }

  Future<void> _initialize() async {
    _preferences = await _store.read();
  }

  Future<void> _updatePreferences(
    AppPreferences Function(AppPreferences current) transform, {
    bool persist = true,
    bool requirePersistence = false,
  }) async {
    Future<void>? persistence;
    await _updates.run(() async {
      await ensureInitialized();
      final AppPreferences next = transform(_preferences);
      if (identical(next, _preferences) && !requirePersistence) {
        return;
      }
      if (requirePersistence) {
        await _writes.run(() async {
          await _store.write(next);
          final AppPreferences persisted = await _store.read();
          if (!mapEquals(
            persisted.downloadPreferences.toJson(),
            next.downloadPreferences.toJson(),
          )) {
            throw StateError('Download preferences were not persisted.');
          }
        });
      }
      _preferences = next;
      notifyListeners();
      if (persist && !requirePersistence) {
        persistence = _writes.run(() async {
          try {
            await _store.write(next);
          } catch (_) {
            // Ordinary UI preferences remain available if storage is unavailable.
          }
        });
      }
    });
    await persistence;
  }
}
