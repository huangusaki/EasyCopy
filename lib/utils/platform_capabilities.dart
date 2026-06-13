import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformCapabilities {
  PlatformCapabilities._();

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static bool get usesMobileWebView =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get supportsDesktopWebView => isWindows;
}
