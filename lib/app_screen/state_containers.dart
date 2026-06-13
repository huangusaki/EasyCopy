import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/reader_screen.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppScreenUiState {
  final WebViewCookieManager? cookieManager =
      PlatformCapabilities.usesMobileWebView ? WebViewCookieManager() : null;
  final TextEditingController searchController = TextEditingController();
  final FocusNode desktopSearchFocusNode = FocusNode(
    debugLabel: 'desktop-global-search',
  );
  final FocusNode readerShortcutFocusNode = FocusNode(
    debugLabel: 'desktop-reader-shortcuts',
  );
  final ScrollController standardScrollController = ScrollController();
  final ValueNotifier<bool> discoverFilterExpandedNotifier =
      ValueNotifier<bool>(false);

  final ValueNotifier<bool> bottomBarVisibleNotifier = ValueNotifier<bool>(
    true,
  );

  double bottomBarScrollAccumulator = 0;
  final Map<String, GlobalKey<State<StatefulWidget>>> discoverListAnchorKeys =
      <String, GlobalKey<State<StatefulWidget>>>{};
  final GlobalKey<ReaderScreenState> readerScreenKey =
      GlobalKey<ReaderScreenState>();

  void dispose() {
    searchController.dispose();
    desktopSearchFocusNode.dispose();
    readerShortcutFocusNode.dispose();
    standardScrollController.dispose();
    discoverFilterExpandedNotifier.dispose();
    bottomBarVisibleNotifier.dispose();
  }
}

class AppNavigationState {
  int selectedIndex = 0;
  int activeLoadId = 0;
  int nextNavigationRequestId = 0;
  int discardedNavigationCommitCount = 0;
  int discardedCallbackCount = 0;
  int supersededRequestCount = 0;
  final Set<String> repairRouteKeys = <String>{};
}

class AppWebViewState {
  bool isFailingOver = false;
  int consecutiveFrameFailures = 0;
  bool isPrimaryWebViewAttached = false;
  bool isDownloadWebViewAttached = false;
  int downloadActiveLoadId = 0;
  Completer<ReaderPageData>? downloadExtractionCompleter;
}

class AppLibraryState {
  List<CachedComicLibraryEntry> cachedComics =
      const <CachedComicLibraryEntry>[];
  Future<void>? refreshTask;
  CacheLibraryRefreshReason? pendingRefresh;
  bool queuedForceRescan = false;
}

class AppShellState {
  final String bootId = DateTime.now().microsecondsSinceEpoch.toString();
  Future<void>? backgroundHostRefreshTask;
  DownloadPreferences? lastDownloadPrefs;
  bool isUpdatingHostSettings = false;
  bool isCheckingForUpdates = false;
  bool isUpdatingCollection = false;
  bool isReaderExitTransitionActive = false;
  String? readerShortcutFocusRouteKey;
  String appVersion = '';
  String appBuildNumber = '';

  /// 移动端 CookieManager 同步指纹。
  String? syncedHostCookieFingerprint;
}
