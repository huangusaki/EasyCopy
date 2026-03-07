import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

enum ReaderScreenOrientation { portrait, landscape }

enum ReaderReadingDirection { topToBottom, leftToRight, rightToLeft }

enum ReaderPageFit { fitWidth, fitScreen }

enum ReaderOpeningPosition { top, center }

String _enumName(Enum value) => value.name;

T _enumValue<T extends Enum>(
  Iterable<T> values,
  Object? rawValue,
  T fallback,
) {
  final String value = (rawValue as String?)?.trim() ?? '';
  for (final T entry in values) {
    if (_enumName(entry) == value) {
      return entry;
    }
  }
  return fallback;
}

@immutable
class ReaderPreferences {
  const ReaderPreferences({
    this.screenOrientation = ReaderScreenOrientation.portrait,
    this.readingDirection = ReaderReadingDirection.topToBottom,
    this.pageFit = ReaderPageFit.fitWidth,
    this.openingPosition = ReaderOpeningPosition.center,
    this.autoPageTurnSeconds = 0,
    this.keepScreenOn = false,
    this.showClock = false,
    this.showProgress = true,
    this.showBattery = true,
    this.showPageGap = true,
    this.useVolumeKeysForPaging = false,
    this.fullscreen = true,
  });

  factory ReaderPreferences.fromJson(Map<String, Object?> json) {
    return ReaderPreferences(
      screenOrientation: _enumValue<ReaderScreenOrientation>(
        ReaderScreenOrientation.values,
        json['screenOrientation'],
        ReaderScreenOrientation.portrait,
      ),
      readingDirection: _enumValue<ReaderReadingDirection>(
        ReaderReadingDirection.values,
        json['readingDirection'],
        ReaderReadingDirection.topToBottom,
      ),
      pageFit: _enumValue<ReaderPageFit>(
        ReaderPageFit.values,
        json['pageFit'],
        ReaderPageFit.fitWidth,
      ),
      openingPosition: _enumValue<ReaderOpeningPosition>(
        ReaderOpeningPosition.values,
        json['openingPosition'],
        ReaderOpeningPosition.center,
      ),
      autoPageTurnSeconds: ((json['autoPageTurnSeconds'] as num?) ?? 0)
          .round()
          .clamp(0, 10),
      keepScreenOn: (json['keepScreenOn'] as bool?) ?? false,
      showClock: (json['showClock'] as bool?) ?? false,
      showProgress: (json['showProgress'] as bool?) ?? true,
      showBattery: (json['showBattery'] as bool?) ?? true,
      showPageGap: (json['showPageGap'] as bool?) ?? true,
      useVolumeKeysForPaging:
          (json['useVolumeKeysForPaging'] as bool?) ?? false,
      fullscreen: (json['fullscreen'] as bool?) ?? true,
    );
  }

  final ReaderScreenOrientation screenOrientation;
  final ReaderReadingDirection readingDirection;
  final ReaderPageFit pageFit;
  final ReaderOpeningPosition openingPosition;
  final int autoPageTurnSeconds;
  final bool keepScreenOn;
  final bool showClock;
  final bool showProgress;
  final bool showBattery;
  final bool showPageGap;
  final bool useVolumeKeysForPaging;
  final bool fullscreen;

  bool get isPaged =>
      readingDirection == ReaderReadingDirection.leftToRight ||
      readingDirection == ReaderReadingDirection.rightToLeft;

  ReaderPreferences copyWith({
    ReaderScreenOrientation? screenOrientation,
    ReaderReadingDirection? readingDirection,
    ReaderPageFit? pageFit,
    ReaderOpeningPosition? openingPosition,
    int? autoPageTurnSeconds,
    bool? keepScreenOn,
    bool? showClock,
    bool? showProgress,
    bool? showBattery,
    bool? showPageGap,
    bool? useVolumeKeysForPaging,
    bool? fullscreen,
  }) {
    return ReaderPreferences(
      screenOrientation: screenOrientation ?? this.screenOrientation,
      readingDirection: readingDirection ?? this.readingDirection,
      pageFit: pageFit ?? this.pageFit,
      openingPosition: openingPosition ?? this.openingPosition,
      autoPageTurnSeconds: autoPageTurnSeconds ?? this.autoPageTurnSeconds,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showClock: showClock ?? this.showClock,
      showProgress: showProgress ?? this.showProgress,
      showBattery: showBattery ?? this.showBattery,
      showPageGap: showPageGap ?? this.showPageGap,
      useVolumeKeysForPaging:
          useVolumeKeysForPaging ?? this.useVolumeKeysForPaging,
      fullscreen: fullscreen ?? this.fullscreen,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'screenOrientation': _enumName(screenOrientation),
      'readingDirection': _enumName(readingDirection),
      'pageFit': _enumName(pageFit),
      'openingPosition': _enumName(openingPosition),
      'autoPageTurnSeconds': autoPageTurnSeconds,
      'keepScreenOn': keepScreenOn,
      'showClock': showClock,
      'showProgress': showProgress,
      'showBattery': showBattery,
      'showPageGap': showPageGap,
      'useVolumeKeysForPaging': useVolumeKeysForPaging,
      'fullscreen': fullscreen,
    };
  }
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.themePreference = AppThemePreference.system,
    this.readerPreferences = const ReaderPreferences(),
  });

  factory AppPreferences.fromJson(Map<String, Object?> json) {
    return AppPreferences(
      themePreference: _enumValue<AppThemePreference>(
        AppThemePreference.values,
        json['themePreference'],
        AppThemePreference.system,
      ),
      readerPreferences: ReaderPreferences.fromJson(
        ((json['readerPreferences'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
    );
  }

  final AppThemePreference themePreference;
  final ReaderPreferences readerPreferences;

  ThemeMode get materialThemeMode {
    switch (themePreference) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  AppPreferences copyWith({
    AppThemePreference? themePreference,
    ReaderPreferences? readerPreferences,
  }) {
    return AppPreferences(
      themePreference: themePreference ?? this.themePreference,
      readerPreferences: readerPreferences ?? this.readerPreferences,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themePreference': _enumName(themePreference),
      'readerPreferences': readerPreferences.toJson(),
    };
  }
}
