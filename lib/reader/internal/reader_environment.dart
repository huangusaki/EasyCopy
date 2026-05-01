import 'package:easy_copy/models/app_preferences.dart';
import 'package:flutter/foundation.dart';

@immutable
class AppliedReaderEnvironment {
  const AppliedReaderEnvironment.standard()
    : orientation = ReaderScreenOrientation.portrait,
      fullscreen = false,
      keepScreenOn = false,
      volumePagingEnabled = false,
      isReader = false;

  const AppliedReaderEnvironment.reader({
    required this.orientation,
    required this.fullscreen,
    required this.keepScreenOn,
    required this.volumePagingEnabled,
  }) : isReader = true;

  final ReaderScreenOrientation orientation;
  final bool fullscreen;
  final bool keepScreenOn;
  final bool volumePagingEnabled;
  final bool isReader;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppliedReaderEnvironment &&
        other.orientation == orientation &&
        other.fullscreen == fullscreen &&
        other.keepScreenOn == keepScreenOn &&
        other.volumePagingEnabled == volumePagingEnabled &&
        other.isReader == isReader;
  }

  @override
  int get hashCode => Object.hash(
    orientation,
    fullscreen,
    keepScreenOn,
    volumePagingEnabled,
    isReader,
  );
}
