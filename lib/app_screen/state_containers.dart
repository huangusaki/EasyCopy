import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/reader_screen.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppScreenUiState {
  final WebViewCookieManager cookieManager = WebViewCookieManager();
  final TextEditingController searchController = TextEditingController();
  final ScrollController standardScrollController = ScrollController();
  final ValueNotifier<bool> discoverFilterExpandedNotifier =
      ValueNotifier<bool>(false);
  final Map<String, GlobalKey<State<StatefulWidget>>> discoverListAnchorKeys =
      <String, GlobalKey<State<StatefulWidget>>>{};
  final GlobalKey<ReaderScreenState> readerScreenKey =
      GlobalKey<ReaderScreenState>();

  void dispose() {
    searchController.dispose();
    standardScrollController.dispose();
    discoverFilterExpandedNotifier.dispose();
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
  String appVersion = '';
  String appBuildNumber = '';
}
