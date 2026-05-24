import 'package:easy_copy/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum AppThemePreference {
  system,
  pureWhite,
  pureBlack,
  warmLight,
  warmDark,
  lightOrange,
  softGreen,
  bluePink,
  lightBlueGreen,
}

String appThemePreferenceLabel(AppThemePreference value) {
  switch (value) {
    case AppThemePreference.system:
      return '跟随系统';
    case AppThemePreference.pureWhite:
      return '纯白';
    case AppThemePreference.pureBlack:
      return '纯黑';
    case AppThemePreference.warmLight:
      return '浅棕色';
    case AppThemePreference.warmDark:
      return '深棕色';
    case AppThemePreference.lightOrange:
      return '浅橙';
    case AppThemePreference.softGreen:
      return '豆沙绿';
    case AppThemePreference.bluePink:
      return '蓝粉渐变';
    case AppThemePreference.lightBlueGreen:
      return '浅蓝浅绿';
  }
}

enum ReaderScreenOrientation { portrait, landscape }

enum ReaderReadingDirection { topToBottom, leftToRight, rightToLeft }

enum ReaderPageFit { fitWidth, fitScreen }

enum ReaderOpeningPosition { top, center }

enum DownloadStorageMode { defaultDirectory, customDirectory }

String _enumName(Enum value) => value.name;

T _enumValue<T extends Enum>(Iterable<T> values, Object? rawValue, T fallback) {
  final String value = (rawValue as String?)?.trim() ?? '';
  for (final T entry in values) {
    if (_enumName(entry) == value) {
      return entry;
    }
  }
  return fallback;
}

int _primaryTabIndex(Object? rawValue) {
  final int? parsed = rawValue is num
      ? rawValue.round()
      : int.tryParse((rawValue as String?)?.trim() ?? '');
  return (parsed ?? 0).clamp(0, 3).toInt();
}

double _clampUnit(Object? rawValue, double fallback) {
  if (rawValue is num) {
    return rawValue.toDouble().clamp(0.0, 1.0);
  }
  if (rawValue is String) {
    final double? parsed = double.tryParse(rawValue.trim());
    if (parsed != null) {
      return parsed.clamp(0.0, 1.0);
    }
  }
  return fallback;
}

double _clampRange(Object? rawValue, double minValue, double maxValue, double fallback) {
  if (rawValue is num) {
    return rawValue.toDouble().clamp(minValue, maxValue);
  }
  if (rawValue is String) {
    final double? parsed = double.tryParse(rawValue.trim());
    if (parsed != null) {
      return parsed.clamp(minValue, maxValue);
    }
  }
  return fallback;
}

@immutable
class WallpaperPreferences {
  const WallpaperPreferences({
    this.enabled = false,
    this.imageFileName = '',
    this.brightness = defaultBrightness,
    this.blurSigma = defaultBlurSigma,
  });

  static const double defaultBrightness = 0.55;
  static const double defaultBlurSigma = 12.0;
  static const double maxBlurSigma = 40.0;

  factory WallpaperPreferences.fromJson(Map<String, Object?> json) {
    return WallpaperPreferences(
      enabled: (json['enabled'] as bool?) ?? false,
      imageFileName: ((json['imageFileName'] as String?) ?? '').trim(),
      brightness: _clampUnit(json['brightness'], defaultBrightness),
      blurSigma: _clampRange(
        json['blurSigma'],
        0.0,
        maxBlurSigma,
        defaultBlurSigma,
      ),
    );
  }

  final bool enabled;
  final String imageFileName;
  final double brightness;
  final double blurSigma;

  bool get hasImage => imageFileName.trim().isNotEmpty;

  bool get isActive => enabled && hasImage;

  WallpaperPreferences copyWith({
    bool? enabled,
    String? imageFileName,
    double? brightness,
    double? blurSigma,
  }) {
    return WallpaperPreferences(
      enabled: enabled ?? this.enabled,
      imageFileName: imageFileName ?? this.imageFileName,
      brightness: brightness ?? this.brightness,
      blurSigma: blurSigma ?? this.blurSigma,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'imageFileName': imageFileName,
      'brightness': brightness,
      'blurSigma': blurSigma,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is WallpaperPreferences &&
        other.enabled == enabled &&
        other.imageFileName == imageFileName &&
        other.brightness == brightness &&
        other.blurSigma == blurSigma;
  }

  @override
  int get hashCode => Object.hash(enabled, imageFileName, brightness, blurSigma);
}

@immutable
class DownloadPreferences {
  const DownloadPreferences({
    this.mode = DownloadStorageMode.defaultDirectory,
    this.customBasePath = '',
    this.customTreeUri = '',
    this.customDisplayPath = '',
    this.usePickedDirectoryAsRoot = false,
  });

  factory DownloadPreferences.fromJson(Map<String, Object?> json) {
    return DownloadPreferences(
      mode: _enumValue<DownloadStorageMode>(
        DownloadStorageMode.values,
        json['mode'],
        DownloadStorageMode.defaultDirectory,
      ),
      customBasePath: (json['customBasePath'] as String?)?.trim() ?? '',
      customTreeUri: (json['customTreeUri'] as String?)?.trim() ?? '',
      customDisplayPath: (json['customDisplayPath'] as String?)?.trim() ?? '',
      usePickedDirectoryAsRoot:
          (json['usePickedDirectoryAsRoot'] as bool?) ?? false,
    );
  }

  final DownloadStorageMode mode;
  final String customBasePath;
  final String customTreeUri;
  final String customDisplayPath;
  final bool usePickedDirectoryAsRoot;

  bool get usesDocumentTree =>
      mode == DownloadStorageMode.customDirectory &&
      customTreeUri.trim().isNotEmpty;

  bool get usesCustomDirectory =>
      mode == DownloadStorageMode.customDirectory &&
      (customTreeUri.trim().isNotEmpty || customBasePath.trim().isNotEmpty);

  String get displayPath {
    final String preferredDisplayPath = customDisplayPath.trim();
    if (preferredDisplayPath.isNotEmpty) {
      return preferredDisplayPath;
    }
    if (usesDocumentTree) {
      return customTreeUri.trim();
    }
    return customBasePath.trim();
  }

  bool hasSameStorageLocation(DownloadPreferences other) {
    return mode == other.mode &&
        customBasePath.trim() == other.customBasePath.trim() &&
        customTreeUri.trim() == other.customTreeUri.trim() &&
        usePickedDirectoryAsRoot == other.usePickedDirectoryAsRoot;
  }

  DownloadPreferences copyWith({
    DownloadStorageMode? mode,
    String? customBasePath,
    String? customTreeUri,
    String? customDisplayPath,
    bool? usePickedDirectoryAsRoot,
  }) {
    return DownloadPreferences(
      mode: mode ?? this.mode,
      customBasePath: customBasePath ?? this.customBasePath,
      customTreeUri: customTreeUri ?? this.customTreeUri,
      customDisplayPath: customDisplayPath ?? this.customDisplayPath,
      usePickedDirectoryAsRoot:
          usePickedDirectoryAsRoot ?? this.usePickedDirectoryAsRoot,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': _enumName(mode),
      'customBasePath': customBasePath,
      'customTreeUri': customTreeUri,
      'customDisplayPath': customDisplayPath,
      'usePickedDirectoryAsRoot': usePickedDirectoryAsRoot,
    };
  }
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
    this.showChapterComments = true,
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
      showChapterComments: (json['showChapterComments'] as bool?) ?? true,
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
  final bool showChapterComments;

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
    bool? showChapterComments,
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
      showChapterComments: showChapterComments ?? this.showChapterComments,
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
      'showChapterComments': showChapterComments,
    };
  }
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.themePreference = AppThemePreference.system,
    this.readerPreferences = const ReaderPreferences(),
    this.downloadPreferences = const DownloadPreferences(),
    this.wallpaperPreferences = const WallpaperPreferences(),
    this.lastPrimaryTabIndex = 0,
  });

  factory AppPreferences.fromJson(Map<String, Object?> json) {
    return AppPreferences(
      themePreference: _readThemePreference(json['themePreference']),
      readerPreferences: ReaderPreferences.fromJson(
        ((json['readerPreferences'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
      downloadPreferences: DownloadPreferences.fromJson(
        ((json['downloadPreferences'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
      wallpaperPreferences: WallpaperPreferences.fromJson(
        ((json['wallpaperPreferences'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
      lastPrimaryTabIndex: _primaryTabIndex(json['lastPrimaryTabIndex']),
    );
  }

  static AppThemePreference _readThemePreference(Object? raw) {
    final String value = (raw as String?)?.trim() ?? '';
    switch (value) {
      case 'light':
        return AppThemePreference.warmLight;
      case 'dark':
        return AppThemePreference.warmDark;
    }
    return _enumValue<AppThemePreference>(
      AppThemePreference.values,
      value,
      AppThemePreference.system,
    );
  }

  final AppThemePreference themePreference;
  final ReaderPreferences readerPreferences;
  final DownloadPreferences downloadPreferences;
  final WallpaperPreferences wallpaperPreferences;
  final int lastPrimaryTabIndex;

  ThemeMode get materialThemeMode {
    switch (themePreference) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.pureWhite:
      case AppThemePreference.warmLight:
      case AppThemePreference.lightOrange:
      case AppThemePreference.softGreen:
      case AppThemePreference.bluePink:
      case AppThemePreference.lightBlueGreen:
        return ThemeMode.light;
      case AppThemePreference.pureBlack:
      case AppThemePreference.warmDark:
        return ThemeMode.dark;
    }
  }

  ThemeData buildLightTheme() {
    switch (themePreference) {
      case AppThemePreference.system:
      case AppThemePreference.pureWhite:
        return AppTheme.buildPureWhiteTheme();
      case AppThemePreference.warmLight:
        return AppTheme.buildWarmLightTheme();
      case AppThemePreference.lightOrange:
        return AppTheme.buildLightOrangeTheme();
      case AppThemePreference.softGreen:
        return AppTheme.buildSoftGreenTheme();
      case AppThemePreference.bluePink:
        return AppTheme.buildBluePinkTheme();
      case AppThemePreference.lightBlueGreen:
        return AppTheme.buildLightBlueGreenTheme();
      case AppThemePreference.warmDark:
      case AppThemePreference.pureBlack:
        return AppTheme.buildPureWhiteTheme();
    }
  }

  ThemeData buildDarkTheme() {
    switch (themePreference) {
      case AppThemePreference.system:
      case AppThemePreference.pureBlack:
        return AppTheme.buildPureBlackTheme();
      case AppThemePreference.warmDark:
        return AppTheme.buildWarmDarkTheme();
      case AppThemePreference.pureWhite:
      case AppThemePreference.warmLight:
      case AppThemePreference.lightOrange:
      case AppThemePreference.softGreen:
      case AppThemePreference.bluePink:
      case AppThemePreference.lightBlueGreen:
        return AppTheme.buildPureBlackTheme();
    }
  }

  AppPreferences copyWith({
    AppThemePreference? themePreference,
    ReaderPreferences? readerPreferences,
    DownloadPreferences? downloadPreferences,
    WallpaperPreferences? wallpaperPreferences,
    int? lastPrimaryTabIndex,
  }) {
    return AppPreferences(
      themePreference: themePreference ?? this.themePreference,
      readerPreferences: readerPreferences ?? this.readerPreferences,
      downloadPreferences: downloadPreferences ?? this.downloadPreferences,
      wallpaperPreferences: wallpaperPreferences ?? this.wallpaperPreferences,
      lastPrimaryTabIndex: lastPrimaryTabIndex ?? this.lastPrimaryTabIndex,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themePreference': _enumName(themePreference),
      'readerPreferences': readerPreferences.toJson(),
      'downloadPreferences': downloadPreferences.toJson(),
      'wallpaperPreferences': wallpaperPreferences.toJson(),
      'lastPrimaryTabIndex': lastPrimaryTabIndex,
    };
  }
}
