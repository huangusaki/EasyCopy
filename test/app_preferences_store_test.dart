import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/services/app_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppPreferencesStore returns defaults when storage is empty', () async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'easy_copy_prefs_defaults_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final AppPreferencesStore store = AppPreferencesStore(
      directoryProvider: () async => tempDirectory,
    );

    final AppPreferences preferences = await store.read();

    expect(preferences.themePreference, AppThemePreference.system);
    expect(
      preferences.readerPreferences.readingDirection,
      ReaderReadingDirection.topToBottom,
    );
    expect(preferences.readerPreferences.showProgress, isTrue);
  });

  test('AppPreferencesStore persists theme and reader preferences', () async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'easy_copy_prefs_write_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final AppPreferencesStore store = AppPreferencesStore(
      directoryProvider: () async => tempDirectory,
    );
    const AppPreferences original = AppPreferences(
      themePreference: AppThemePreference.dark,
      readerPreferences: ReaderPreferences(
        screenOrientation: ReaderScreenOrientation.landscape,
        readingDirection: ReaderReadingDirection.rightToLeft,
        pageFit: ReaderPageFit.fitScreen,
        openingPosition: ReaderOpeningPosition.top,
        autoPageTurnSeconds: 5,
        keepScreenOn: true,
        showClock: true,
        showProgress: false,
        showBattery: false,
        showPageGap: false,
        useVolumeKeysForPaging: true,
        fullscreen: false,
      ),
    );

    await store.write(original);
    final AppPreferences restored = await store.read();

    expect(restored.themePreference, AppThemePreference.dark);
    expect(
      restored.readerPreferences.screenOrientation,
      ReaderScreenOrientation.landscape,
    );
    expect(
      restored.readerPreferences.readingDirection,
      ReaderReadingDirection.rightToLeft,
    );
    expect(restored.readerPreferences.pageFit, ReaderPageFit.fitScreen);
    expect(restored.readerPreferences.autoPageTurnSeconds, 5);
    expect(restored.readerPreferences.keepScreenOn, isTrue);
    expect(restored.readerPreferences.useVolumeKeysForPaging, isTrue);
    expect(restored.readerPreferences.fullscreen, isFalse);
  });
}
