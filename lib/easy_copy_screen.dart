import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/chapter_comment.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/page_transition_scope.dart';
import 'package:easy_copy/services/android_document_tree_bridge.dart';
import 'package:easy_copy/services/app_update_checker.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/deferred_viewport_coordinator.dart';
import 'package:easy_copy/services/debug_trace.dart';
import 'package:easy_copy/services/download_queue_manager.dart';
import 'package:easy_copy/services/discover_filter_selection.dart';
import 'package:easy_copy/services/display_mode_service.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/services/document_tree_image_provider.dart';
import 'package:easy_copy/services/document_tree_relative_image_provider.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/navigation_request_guard.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/rank_filter_selection.dart';
import 'package:easy_copy/services/primary_tab_session_store.dart';
import 'package:easy_copy/services/reader_platform_bridge.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/network_diagnostics.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_html_page_loader.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/services/standard_page_load_controller.dart';
import 'package:easy_copy/services/tab_activation_policy.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:easy_copy/widgets/download_management_page.dart';
import 'package:easy_copy/widgets/native_login_screen.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:easy_copy/widgets/top_notice.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'easy_copy_screen/reader_state.dart';
part 'easy_copy_screen/reader_progress.dart';
part 'easy_copy_screen/standard_mode.dart';
part 'easy_copy_screen/reader_mode.dart';
part 'easy_copy_screen/webview_pipeline.dart';
part 'easy_copy_screen/widgets.dart';

const Duration _pageFadeTransitionDuration = Duration(milliseconds: 200);
const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const String _detailAllChapterTabKey = '__detail_all__';
const double _readerNextChapterPullTriggerDistance = 280;
const double _readerNextChapterPagedTriggerDistance = 160;
const double _readerNextChapterPullActivationExtent = 100;

typedef ReaderPageMaybeLoader = Future<ReaderPageData?> Function(Uri uri);
typedef ReaderPageLoader = Future<ReaderPageData> Function(Uri uri);

@visibleForTesting
Future<ReaderPageData> resolveReaderPageForDownload(
  Uri chapterUri, {
  required ReaderPageMaybeLoader loadFromStorageCache,
  required ReaderPageMaybeLoader loadFromPageCache,
  required ReaderPageLoader loadFromLightweightSource,
  required ReaderPageLoader loadFromWebViewFallback,
}) async {
  bool hasUsableImageList(ReaderPageData? page) {
    return page != null && page.imageUrls.isNotEmpty;
  }

  final ReaderPageData? storageCachedPage = await loadFromStorageCache(
    chapterUri,
  );
  if (hasUsableImageList(storageCachedPage)) {
    return storageCachedPage!;
  }

  final ReaderPageData? pageCachedPage = await loadFromPageCache(chapterUri);
  if (hasUsableImageList(pageCachedPage)) {
    return pageCachedPage!;
  }

  try {
    final ReaderPageData lightweightPage = await loadFromLightweightSource(
      chapterUri,
    );
    if (hasUsableImageList(lightweightPage)) {
      return lightweightPage;
    }
  } catch (_) {
    // Let WebView fallback handle parser incompatibilities.
  }

  return loadFromWebViewFallback(chapterUri);
}

Widget _buildFadeSwitchTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  );
}

class _EasyCopyScreenDownloadTaskRunner implements DownloadTaskRunner {
  const _EasyCopyScreenDownloadTaskRunner(this._state);

  final _EasyCopyScreenState _state;

  @override
  Future<ReaderPageData> prepare(DownloadQueueTask task) async {
    await _state._session.ensureInitialized();
    return _state._prepareReaderPageForDownload(Uri.parse(task.chapterHref));
  }

  @override
  Future<void> download(
    DownloadQueueTask task,
    ReaderPageData page, {
    required ChapterDownloadPauseChecker shouldPause,
    required ChapterDownloadCancelChecker shouldCancel,
    ChapterDownloadProgressCallback? onProgress,
  }) {
    return _state._downloadService.downloadChapter(
      page,
      cookieHeader: _state._session.cookieHeader,
      comicUri: task.comicUri,
      chapterHref: task.chapterHref,
      chapterLabel: task.chapterLabel,
      coverUrl: task.coverUrl,
      detailSnapshot: task.detailSnapshot,
      shouldPause: shouldPause,
      shouldCancel: shouldCancel,
      onProgress: onProgress,
    );
  }
}

class EasyCopyScreen extends StatefulWidget {
  const EasyCopyScreen({super.key, this.preferencesController});

  final AppPreferencesController? preferencesController;

  @override
  State<EasyCopyScreen> createState() => _EasyCopyScreenState();
}

class _EasyCopyScreenState extends State<EasyCopyScreen>
    with WidgetsBindingObserver {
  static const List<DeviceOrientation> _defaultOrientations =
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];

  late final WebViewController _controller;
  late final WebViewController _downloadController;
  late final AppPreferencesController _preferencesController;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _readerCommentController =
      TextEditingController();
  final ScrollController _readerCommentScrollController = ScrollController();
  final ScrollController _standardScrollController = ScrollController();
  final ScrollController _readerScrollController = ScrollController();
  final GlobalKey _readerViewportKey = GlobalKey();
  final ReaderPlatformBridge _readerPlatformBridge =
      ReaderPlatformBridge.instance;
  final HostManager _hostManager = HostManager.instance;
  final SiteSession _session = SiteSession.instance;
  final SiteApiClient _siteApiClient = SiteApiClient.instance;
  final ReaderProgressStore _readerProgressStore = ReaderProgressStore.instance;
  final ComicDownloadService _downloadService = ComicDownloadService.instance;
  final DownloadStorageService _downloadStorageService =
      DownloadStorageService.instance;
  final DownloadQueueStore _downloadQueueStore = DownloadQueueStore.instance;
  late final DownloadQueueManager _downloadQueueManager;
  final PrimaryTabSessionStore _tabSessionStore = PrimaryTabSessionStore(
    rootUris: <int, Uri>{
      for (int index = 0; index < appDestinations.length; index += 1)
        index: appDestinations[index].uri,
    },
  );
  late final PageRepository _pageRepository;
  late PageController _readerPageController;

  int _selectedIndex = 0;
  int _activeLoadId = 0;
  int _nextNavigationRequestId = 0;
  bool _isFailingOver = false;
  int _consecutiveFrameFailures = 0;
  bool _isDiscoverThemeExpanded = false;
  List<CachedComicLibraryEntry> _cachedComics =
      const <CachedComicLibraryEntry>[];
  Future<void>? _cachedLibraryRefreshTask;
  Future<void>? _backgroundHostRefreshTask;
  CacheLibraryRefreshReason? _queuedCachedLibraryRefreshReason;
  bool _queuedCachedLibraryForceRescan = false;
  bool _isPrimaryWebViewAttached = false;
  bool _isDownloadWebViewAttached = false;
  int _downloadActiveLoadId = 0;
  Completer<ReaderPageData>? _downloadExtractionCompleter;
  Timer? _readerProgressDebounce;
  Timer? _readerAutoTurnTimer;
  Timer? _readerClockTimer;
  ReaderPosition? _lastPersistedReaderPosition;
  bool _isUpdatingHostSettings = false;
  bool _isCheckingForUpdates = false;
  bool _isUpdatingCollection = false;
  bool _isReaderSettingsOpen = false;
  bool _isReaderChapterControlsVisible = false;
  bool _isReaderExitTransitionActive = false;
  bool _isReaderScaleGestureActive = false;
  double _readerZoomScale = 1.0;
  double _readerZoomBaseScale = 1.0;
  double _readerPanOffsetX = 0;
  double _readerPanOffsetY = 0;
  bool _isReaderNextChapterLoading = false;
  bool _isReaderCommentsLoading = false;
  bool _isReaderCommentsLoadingMore = false;
  bool _isReaderCommentSubmitting = false;
  bool _readerPresentationSyncScheduled = false;
  bool _suspendStandardScrollTracking = false;
  String _selectedDetailChapterTabKey = _detailAllChapterTabKey;
  bool _isDetailChapterSortAscending = false;
  String _detailChapterStateRouteKey = '';
  String _readerCommentsChapterId = '';
  String _readerCommentsError = '';
  int _readerCommentsTotal = 0;
  int _currentReaderPageIndex = 0;
  int _currentVisibleReaderImageIndex = 0;
  double _readerPreviousChapterPullDistance = 0;
  double _readerNextChapterPullDistance = 0;
  final Map<String, double> _readerImageAspectRatios = <String, double>{};
  final Set<String> _zoomedReaderImageKeys = <String>{};
  int? _batteryLevel;
  int _discardedNavigationCommitCount = 0;
  int _discardedNavigationCallbackCount = 0;
  int _supersededNavigationRequestCount = 0;
  _AppliedReaderEnvironment? _appliedReaderEnvironment;
  ReaderPreferences? _lastObservedReaderPreferences;
  DownloadPreferences? _lastObservedDownloadPreferences;
  final Map<int, ScrollController> _readerPageScrollControllers =
      <int, ScrollController>{};
  final Map<int, GlobalKey> _readerImageItemKeys = <int, GlobalKey>{};
  final Map<String, GlobalKey> _detailChapterItemKeys = <String, GlobalKey>{};
  List<ChapterComment> _readerChapterComments = const <ChapterComment>[];
  final DeferredViewportCoordinator _standardScrollRestoreCoordinator =
      DeferredViewportCoordinator();
  final DeferredViewportCoordinator _detailChapterAutoScrollCoordinator =
      DeferredViewportCoordinator();
  final DeferredViewportCoordinator _readerRestoreCoordinator =
      DeferredViewportCoordinator();
  String _handledDetailAutoScrollSignature = '';
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<ReaderVolumeKeyAction>? _volumeKeySubscription;
  final StandardPageLoadController<EasyCopyPage> _standardPageLoadController =
      StandardPageLoadController<EasyCopyPage>();
  final String _bootId = DateTime.now().microsecondsSinceEpoch.toString();
  String _appVersion = '';
  String _appBuildNumber = '';

  ValueListenable<DownloadQueueSnapshot> get _downloadQueueSnapshotNotifier =>
      _downloadQueueManager.snapshotNotifier;

  ValueListenable<DownloadStorageState> get _downloadStorageStateNotifier =>
      _downloadQueueManager.storageStateNotifier;

  ValueListenable<bool> get _downloadStorageBusyNotifier =>
      _downloadQueueManager.storageBusyNotifier;

  ValueListenable<DownloadStorageMigrationProgress?>
  get _downloadStorageMigrationProgressNotifier =>
      _downloadQueueManager.storageMigrationProgressNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preferencesController =
        widget.preferencesController ?? AppPreferencesController.instance;
    _readerPageController = PageController();
    _lastObservedReaderPreferences = _preferencesController.readerPreferences;
    _lastObservedDownloadPreferences =
        _preferencesController.downloadPreferences;
    _controller = _buildController();
    _downloadController = _buildDownloadController();
    _pageRepository = PageRepository(
      standardPageLoader: _loadStandardPageFresh,
      htmlPageLoader: SiteHtmlPageLoader.instance.loadPage,
    );
    _downloadQueueManager = DownloadQueueManager(
      preferencesController: _preferencesController,
      downloadService: _downloadService,
      queueStore: _downloadQueueStore,
      taskRunner: _EasyCopyScreenDownloadTaskRunner(this),
      onLibraryChanged: (CacheLibraryRefreshReason reason) {
        return _refreshCachedComics(reason: reason);
      },
      onNotice: _handleDownloadQueueNotice,
    );
    _preferencesController.addListener(_handlePreferencesChanged);
    _standardScrollController.addListener(_handleStandardScroll);
    _readerScrollController.addListener(_handleReaderScroll);
    _readerCommentScrollController.addListener(_handleReaderCommentScroll);
    unawaited(_loadAppVersionInfo());
    if (_readerPlatformBridge.isAndroidSupported) {
      _batterySubscription = _readerPlatformBridge.batteryStream.listen((
        int level,
      ) {
        if (!mounted || _batteryLevel == level) {
          return;
        }
        setState(() {
          _batteryLevel = level;
        });
      });
      _volumeKeySubscription = _readerPlatformBridge.volumeKeyEventStream
          .listen(_handleReaderVolumeKeyAction);
    }
    unawaited(DisplayModeService.requestHighRefreshRate());
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readerProgressDebounce?.cancel();
    unawaited(_flushReaderProgressPersistence());
    _readerAutoTurnTimer?.cancel();
    _readerClockTimer?.cancel();
    _batterySubscription?.cancel();
    _volumeKeySubscription?.cancel();
    _preferencesController.removeListener(_handlePreferencesChanged);
    _standardScrollController.removeListener(_handleStandardScroll);
    _readerScrollController.removeListener(_handleReaderScroll);
    _readerCommentScrollController.removeListener(_handleReaderCommentScroll);
    _disposeReaderPagedScrollControllers();
    _readerPageController.dispose();
    _searchController.dispose();
    _readerCommentController.dispose();
    _readerCommentScrollController.dispose();
    _standardScrollController.dispose();
    _readerScrollController.dispose();
    _downloadQueueManager.dispose();
    unawaited(_restoreDefaultReaderEnvironment());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DisplayModeService.requestHighRefreshRate());
      return;
    }
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_flushReaderProgressPersistence());
        return;
      case AppLifecycleState.resumed:
        return;
    }
  }

  PrimaryTabRouteEntry get _currentEntry =>
      _tabSessionStore.currentEntry(_selectedIndex);

  StandardPageLoadHandle<EasyCopyPage>? get _pendingPageLoad =>
      _standardPageLoadController.pendingLoad;

  Uri get _currentUri => _currentEntry.uri;

  EasyCopyPage? get _page => _currentEntry.page;

  bool get _isLoading => _currentEntry.isLoading;

  String? get _errorMessage => _currentEntry.errorMessage;

  ReaderPreferences get _readerPreferences =>
      _preferencesController.readerPreferences;

  String _authScopeForUri(Uri uri) {
    if (_isProfileUri(uri) || _isUserScopedDetailUri(uri)) {
      return _session.authScope;
    }
    return 'guest';
  }

  PageQueryKey _pageQueryKeyForUri(Uri uri, {String? authScope}) {
    return PageQueryKey.forUri(
      uri,
      authScope: authScope ?? _authScopeForUri(uri),
    );
  }

  NavigationRequestContext _createNavigationRequestContext(
    Uri uri, {
    required int targetTabIndex,
    required NavigationIntent intent,
    required bool preserveVisiblePage,
    required NavigationRequestSourceKind sourceKind,
    bool allowBackgroundCache = true,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    return NavigationRequestContext(
      requestId: ++_nextNavigationRequestId,
      targetTabIndex: targetTabIndex,
      routeKey: AppConfig.routeKeyForUri(targetUri),
      intent: intent,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: sourceKind,
      allowBackgroundCache: allowBackgroundCache,
    );
  }

  bool _canCommitRequest(NavigationRequestContext request) {
    return canCommitNavigationRequest(
      currentSelectedIndex: _selectedIndex,
      currentEntry: _tabSessionStore.currentEntry(request.targetTabIndex),
      request: request,
    );
  }

  void _recordSupersededRequest(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _supersededNavigationRequestCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] superseded request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_supersededNavigationRequestCount',
    );
  }

  void _recordDiscardedNavigationMutation(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _discardedNavigationCommitCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded commit request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_discardedNavigationCommitCount',
    );
  }

  void _recordDiscardedNavigationCallback(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _discardedNavigationCallbackCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded callback request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_discardedNavigationCallbackCount',
    );
  }

  void _abandonCurrentRequest(int tabIndex, {required String phase}) {
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(tabIndex);
    if (entry.activeRequestId == 0) {
      return;
    }
    _recordSupersededRequest(
      NavigationRequestContext(
        requestId: entry.activeRequestId,
        targetTabIndex: tabIndex,
        routeKey: entry.routeKey,
        intent: NavigationIntent.preserve,
        preserveVisiblePage: true,
        sourceKind: NavigationRequestSourceKind.navigation,
      ),
      phase: phase,
    );
    _tabSessionStore.abandonCurrentRequest(tabIndex);
  }

  bool _mutateOwnedRequestEntry(
    NavigationRequestContext request,
    PrimaryTabRouteEntry Function(PrimaryTabRouteEntry entry) updater, {
    required String phase,
  }) {
    if (!_canCommitRequest(request)) {
      _recordDiscardedNavigationMutation(request, phase: phase);
      return false;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(request.targetTabIndex, updater);
    }, syncSearch: request.targetTabIndex == _selectedIndex);
    return true;
  }

  void _mutateSessionState(VoidCallback mutation, {bool syncSearch = true}) {
    if (!mounted) {
      mutation();
      if (syncSearch) {
        _syncSearchController();
      }
      return;
    }
    setState(mutation);
    if (syncSearch) {
      _syncSearchController();
    }
  }

  void _setStateIfMounted([VoidCallback? mutation]) {
    if (!mounted) {
      return;
    }
    setState(mutation ?? () {});
  }

  bool _isUserDrivenScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    return switch (notification) {
      ScrollStartNotification(:final DragStartDetails? dragDetails) =>
        dragDetails != null,
      ScrollUpdateNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      OverscrollNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      _ => false,
    };
  }

  bool _handleStandardScrollNotification(ScrollNotification notification) {
    if (_isUserDrivenScrollNotification(notification)) {
      _noteStandardViewportUserInteraction();
    }
    return false;
  }

  bool _handleReaderScrollNotification(ScrollNotification notification) {
    if (_isUserDrivenScrollNotification(notification)) {
      _readerRestoreCoordinator.noteUserInteraction();
    }
    return false;
  }

  void _noteStandardViewportUserInteraction() {
    _standardScrollRestoreCoordinator.noteUserInteraction();
    _detailChapterAutoScrollCoordinator.noteUserInteraction();
    _suspendStandardScrollTracking = false;
  }

  bool _isActiveStandardScrollRestore(
    DeferredViewportTicket ticket, {
    required int tabIndex,
    required String routeKey,
  }) {
    return mounted &&
        _standardScrollRestoreCoordinator.isActive(ticket) &&
        !_isReaderMode &&
        _selectedIndex == tabIndex &&
        _currentEntry.routeKey == routeKey;
  }

  void _finishStandardScrollRestore(DeferredViewportTicket ticket) {
    if (_standardScrollRestoreCoordinator.isLatestRequest(ticket)) {
      _suspendStandardScrollTracking = false;
    }
  }

  bool _isActiveDetailChapterAutoScroll(
    DeferredViewportTicket ticket, {
    required String routeKey,
  }) {
    return mounted &&
        _detailChapterAutoScrollCoordinator.isActive(ticket) &&
        _page is DetailPageData &&
        _currentEntry.routeKey == routeKey;
  }

  bool _isActiveReaderRestore(
    DeferredViewportTicket ticket, {
    required String pageUri,
    required bool isPaged,
  }) {
    final EasyCopyPage? page = _page;
    return mounted &&
        _readerRestoreCoordinator.isActive(ticket) &&
        page is ReaderPageData &&
        page.uri == pageUri &&
        _readerPreferences.isPaged == isPaged;
  }

  bool _shouldActivateAsyncResultTab(int targetTabIndex) {
    return shouldActivateTargetTab(
      currentSelectedIndex: _selectedIndex,
      targetTabIndex: targetTabIndex,
      phase: TabActivationPhase.asyncLoadResult,
    );
  }

  void _handlePreferencesChanged() {
    final ReaderPreferences previousPreferences =
        _lastObservedReaderPreferences ?? _readerPreferences;
    final ReaderPreferences nextPreferences = _readerPreferences;
    final DownloadPreferences previousDownloadPreferences =
        _lastObservedDownloadPreferences ??
        _preferencesController.downloadPreferences;
    final DownloadPreferences nextDownloadPreferences =
        _preferencesController.downloadPreferences;
    _lastObservedReaderPreferences = nextPreferences;
    _lastObservedDownloadPreferences = nextDownloadPreferences;

    if (!mounted) {
      return;
    }

    final EasyCopyPage? page = _page;
    final _ReaderRestoreTarget? readerRestoreTarget = page is ReaderPageData
        ? _captureCurrentReaderRestoreTarget(
            page,
            preferences: previousPreferences,
          )
        : null;
    setState(() {});

    final bool downloadPreferencesChanged = !previousDownloadPreferences
        .hasSameStorageLocation(nextDownloadPreferences);
    if (downloadPreferencesChanged) {
      unawaited(_refreshDownloadStorageState());
      if (_downloadStorageMigrationProgressNotifier.value == null) {
        unawaited(
          _refreshCachedComics(
            reason: CacheLibraryRefreshReason.preferencesChanged,
          ),
        );
      }
    }

    final bool requiresReaderRestore =
        previousPreferences.readingDirection !=
            nextPreferences.readingDirection ||
        previousPreferences.pageFit != nextPreferences.pageFit ||
        previousPreferences.openingPosition !=
            nextPreferences.openingPosition ||
        previousPreferences.showChapterComments !=
            nextPreferences.showChapterComments;
    if (requiresReaderRestore && page is ReaderPageData) {
      _handleReaderPageLoaded(
        page,
        previousUri: page.uri,
        forceRestore: true,
        preferredRestoreTarget: readerRestoreTarget,
      );
      return;
    }
    _scheduleReaderPresentationSync();
  }

  Future<void> _bootstrap() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    await Future.wait(<Future<void>>[
      _hostManager.ensureInitialized(),
      _session.ensureInitialized(),
      _preferencesController.ensureInitialized(),
      _readerProgressStore.ensureInitialized(),
      PageCacheStore.instance.ensureInitialized(),
    ]);
    DebugTrace.log('bootstrap.initialized', <String, Object?>{
      'bootId': _bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    Uri? debugUri;
    if (kDebugMode && AppConfig.debugStartUri.trim().isNotEmpty) {
      debugUri = Uri.tryParse(AppConfig.debugStartUri.trim());
      if (debugUri != null) {
        DebugTrace.log('bootstrap.debug_start_uri', <String, Object?>{
          'bootId': _bootId,
          'uri': debugUri.toString(),
        });
      }
    }
    final Uri homeUri = debugUri ?? appDestinations.first.uri;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIndex = tabIndexForUri(homeUri);
    });
    _syncSearchController();
    await _loadUri(homeUri, historyMode: NavigationIntent.resetToRoot);
    DebugTrace.log('bootstrap.home_ready', <String, Object?>{
      'bootId': _bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runDeferredBootstrapTasks());
    });
  }

  Future<void> _runDeferredBootstrapTasks() async {
    await Future.wait(<Future<void>>[
      _refreshHostsInBackgroundAfterBootstrap(),
      _prepareDeferredDownloadBootstrapState(),
    ]);
    await _downloadQueueManager.recoverInterruptedStorageMigration();
    if (!_downloadQueueManager.shouldBypassCachedReaderLookup) {
      await _refreshCachedComics(reason: CacheLibraryRefreshReason.bootstrap);
    } else {
      DebugTrace.log('cached_library.refresh_deferred', <String, Object?>{
        'bootId': _bootId,
        'reason': CacheLibraryRefreshReason.bootstrap.name,
        'deferReason': 'storage_migration_active',
      });
    }
    await _ensureDownloadQueueRunning();
  }

  Future<void> _prepareDeferredDownloadBootstrapState() {
    return Future.wait(<Future<void>>[
      _refreshDownloadStorageState(),
      _restoreDownloadQueue(),
    ]);
  }

  Future<void> _refreshHostsInBackgroundAfterBootstrap() {
    final Future<void>? activeTask = _backgroundHostRefreshTask;
    if (activeTask != null) {
      return activeTask;
    }
    final Future<void> refreshTask =
        _refreshHostsInBackgroundAfterBootstrapImpl();
    _backgroundHostRefreshTask = refreshTask;
    return refreshTask.whenComplete(() {
      if (identical(_backgroundHostRefreshTask, refreshTask)) {
        _backgroundHostRefreshTask = null;
      }
    });
  }

  Future<void> _refreshHostsInBackgroundAfterBootstrapImpl() async {
    final String previousHost = _hostManager.currentHost;
    final DateTime? previousCheckedAt = _hostManager.probeSnapshot?.checkedAt;
    DebugTrace.log('host.bootstrap_probe_start', <String, Object?>{
      'bootId': _bootId,
      'currentHost': previousHost,
      'checkedAt': previousCheckedAt?.toIso8601String(),
    });
    try {
      await _hostManager.refreshProbes(force: true);
      final String nextHost = _hostManager.currentHost;
      final DateTime? nextCheckedAt = _hostManager.probeSnapshot?.checkedAt;
      final bool hostChanged = nextHost != previousHost;
      if (hostChanged) {
        await _syncSessionCookiesToCurrentHost();
      }
      DebugTrace.log('host.bootstrap_probe_complete', <String, Object?>{
        'bootId': _bootId,
        'previousHost': previousHost,
        'nextHost': nextHost,
        'hostChanged': hostChanged,
        'checkedAt': nextCheckedAt?.toIso8601String(),
      });
      if (!mounted || (!hostChanged && nextCheckedAt == previousCheckedAt)) {
        return;
      }
      _mutateSessionState(() {}, syncSearch: false);
    } catch (error) {
      DebugTrace.log('host.bootstrap_probe_failed', <String, Object?>{
        'bootId': _bootId,
        'currentHost': previousHost,
        'checkedAt': previousCheckedAt?.toIso8601String(),
        'error': error.toString(),
      });
    }
  }

  Future<void> _refreshCachedComics({
    CacheLibraryRefreshReason reason = CacheLibraryRefreshReason.manual,
    bool forceRescan = false,
  }) {
    final Future<void>? activeTask = _cachedLibraryRefreshTask;
    if (activeTask != null) {
      _queuedCachedLibraryRefreshReason = reason;
      _queuedCachedLibraryForceRescan =
          _queuedCachedLibraryForceRescan || forceRescan;
      return activeTask;
    }
    late final Future<void> task;
    task = _runCachedLibraryRefreshLoop(reason, forceRescan: forceRescan)
        .whenComplete(() {
          if (identical(_cachedLibraryRefreshTask, task)) {
            _cachedLibraryRefreshTask = null;
          }
        });
    _cachedLibraryRefreshTask = task;
    return task;
  }

  Future<void> _runCachedLibraryRefreshLoop(
    CacheLibraryRefreshReason initialReason, {
    required bool forceRescan,
  }) async {
    CacheLibraryRefreshReason currentReason = initialReason;
    bool currentForceRescan = forceRescan;
    while (true) {
      _queuedCachedLibraryRefreshReason = null;
      _queuedCachedLibraryForceRescan = false;
      final Stopwatch stopwatch = Stopwatch()..start();
      DebugTrace.log('cached_library.refresh_start', <String, Object?>{
        'bootId': _bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
      });
      final List<CachedComicLibraryEntry> comics = await _downloadService
          .loadCachedLibrary(forceRescan: currentForceRescan);
      if (!mounted) {
        _cachedComics = comics;
      } else {
        setState(() {
          _cachedComics = comics;
        });
      }
      DebugTrace.log('cached_library.refresh_complete', <String, Object?>{
        'bootId': _bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
        'comicCount': comics.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      final CacheLibraryRefreshReason? queuedReason =
          _queuedCachedLibraryRefreshReason;
      final bool queuedForceRescan = _queuedCachedLibraryForceRescan;
      if (queuedReason == null && !queuedForceRescan) {
        break;
      }
      currentReason = queuedReason ?? currentReason;
      currentForceRescan = queuedForceRescan;
    }
  }

  Future<String> _rescanCurrentDownloadStorage() async {
    await _refreshCachedComics(
      reason: CacheLibraryRefreshReason.storageRescan,
      forceRescan: true,
    );
    if (!mounted) {
      return '';
    }
    final int comicCount = _cachedComics.length;
    final int chapterCount = _cachedComics.fold(
      0,
      (int total, CachedComicLibraryEntry entry) =>
          total + entry.cachedChapterCount,
    );
    return comicCount == 0
        ? '当前目录未发现可恢复缓存'
        : '已恢复 $comicCount 部漫画，$chapterCount 话缓存';
  }

  Future<void> _refreshDownloadStorageState({
    DownloadPreferences? preferences,
  }) async {
    await _downloadQueueManager.refreshStorageState(preferences: preferences);
  }

  void _handleDownloadQueueNotice(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    _showSnackBar(message);
  }

  DownloadQueueSnapshot get _downloadQueueSnapshot =>
      _downloadQueueSnapshotNotifier.value;

  Future<void> _restoreDownloadQueue() async {
    await _downloadQueueManager.restoreQueue();
  }

  String _comicQueueKey(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return value.trim();
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  Future<void> _persistCachedDetailSnapshot(DetailPageData page) async {
    final CachedComicDetailSnapshot snapshot = page.toCachedDetailSnapshot();
    if (snapshot.isEmpty) {
      return;
    }
    _updateCachedComicSnapshotInMemory(page, snapshot);
    try {
      await _downloadService.upsertCachedComicDetailSnapshot(page);
    } catch (_) {
      return;
    }
  }

  void _updateCachedComicSnapshotInMemory(
    DetailPageData page,
    CachedComicDetailSnapshot snapshot,
  ) {
    final String targetComicKey = _comicQueueKey(page.uri);
    final int index = _cachedComics.indexWhere((CachedComicLibraryEntry entry) {
      if (targetComicKey.isNotEmpty &&
          _comicQueueKey(entry.comicHref) == targetComicKey) {
        return true;
      }
      return entry.comicTitle == page.title;
    });
    if (index == -1) {
      return;
    }

    final CachedComicLibraryEntry current = _cachedComics[index];
    final CachedComicLibraryEntry next = current.copyWith(
      comicTitle: page.title.isEmpty ? current.comicTitle : page.title,
      comicHref: page.uri.isEmpty ? current.comicHref : page.uri,
      coverUrl: page.coverUrl.isEmpty ? current.coverUrl : page.coverUrl,
      detailSnapshot: snapshot,
    );
    if (mounted) {
      setState(() {
        _cachedComics = <CachedComicLibraryEntry>[
          ..._cachedComics.take(index),
          next,
          ..._cachedComics.skip(index + 1),
        ];
      });
      return;
    }
    _cachedComics = <CachedComicLibraryEntry>[
      ..._cachedComics.take(index),
      next,
      ..._cachedComics.skip(index + 1),
    ];
  }

  DownloadQueueTask _buildDownloadQueueTask(
    DetailPageData page,
    Uri chapterUri,
    ChapterData chapter,
  ) {
    final DateTime now = DateTime.now();
    final String comicKey = _comicQueueKey(page.uri);
    final String chapterKey = _chapterPathKey(chapterUri.toString());
    final String id = sha1
        .convert(utf8.encode('$comicKey::$chapterKey'))
        .toString();
    return DownloadQueueTask(
      id: id,
      comicKey: comicKey,
      chapterKey: chapterKey,
      comicTitle: page.title,
      comicUri: page.uri,
      coverUrl: page.coverUrl,
      chapterLabel: chapter.label,
      chapterHref: chapterUri.toString(),
      status: DownloadQueueTaskStatus.queued,
      progressLabel: '等待缓存',
      completedImages: 0,
      totalImages: 0,
      createdAt: now,
      updatedAt: now,
      detailSnapshot: page.toCachedDetailSnapshot(),
    );
  }

  Future<void> _enqueueSelectedChapters(
    DetailPageData page,
    List<ChapterData> chapters,
  ) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final Set<String> downloadedKeys = _downloadedChapterPathKeysForDetail(
      page,
    );
    final Set<String> queuedChapterKeys = snapshot.tasks
        .map((DownloadQueueTask task) => task.chapterKey)
        .toSet();
    final Uri detailUri = Uri.parse(page.uri);

    int addedCount = 0;
    int skippedCachedCount = 0;
    int skippedQueuedCount = 0;
    final List<DownloadQueueTask> newTasks = <DownloadQueueTask>[];

    for (final ChapterData chapter in chapters) {
      final Uri chapterUri = AppConfig.resolveNavigationUri(
        chapter.href,
        currentUri: detailUri,
      );
      final String chapterKey = _chapterPathKey(chapterUri.toString());
      if (downloadedKeys.contains(chapterKey)) {
        skippedCachedCount += 1;
        continue;
      }
      if (queuedChapterKeys.contains(chapterKey)) {
        skippedQueuedCount += 1;
        continue;
      }

      newTasks.add(_buildDownloadQueueTask(page, chapterUri, chapter));
      queuedChapterKeys.add(chapterKey);
      addedCount += 1;
    }

    if (addedCount == 0) {
      if (skippedCachedCount > 0 && skippedQueuedCount > 0) {
        _showSnackBar('所选章节已缓存或已在队列中');
      } else if (skippedCachedCount > 0) {
        _showSnackBar('所选章节都已经缓存过了');
      } else {
        _showSnackBar('所选章节已在后台缓存队列中');
      }
      return;
    }

    final bool keepPaused = await _downloadQueueManager.addTasks(newTasks);

    final StringBuffer message = StringBuffer('已加入后台缓存队列：$addedCount 话');
    if (skippedCachedCount > 0) {
      message.write('，已跳过已缓存 $skippedCachedCount 话');
    }
    if (skippedQueuedCount > 0) {
      message.write('，已跳过队列内 $skippedQueuedCount 话');
    }
    if (keepPaused) {
      message.write('（当前队列已暂停）');
    }
    _showSnackBar(message.toString());
  }

  Future<void> _pauseDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty || snapshot.isPaused) {
      return;
    }
    await _downloadQueueManager.pauseQueue();
    _showSnackBar('后台缓存将在当前图片完成后暂停');
  }

  Future<void> _resumeDownloadQueue() async {
    if (_downloadQueueSnapshot.isEmpty) {
      return;
    }
    await _downloadQueueManager.resumeQueue();
    _showSnackBar('已继续后台缓存');
  }

  Future<void> _confirmDeleteCachedComic(CachedComicLibraryEntry item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除已缓存漫画'),
          content: Text('确认删除《${item.comicTitle}》的本地缓存吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final String comicKey = item.comicHref.isEmpty
        ? item.comicTitle
        : _comicQueueKey(item.comicHref);
    await _downloadQueueManager.deleteCachedComic(item, comicKey: comicKey);
    _showSnackBar('已删除 ${item.comicTitle} 的缓存');
  }

  Future<void> _confirmRemoveQueuedComic(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移出缓存队列'),
          content: Text('确认停止《${task.comicTitle}》的后台缓存，并清理未完成文件吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.removeQueuedComic(task);
    _showSnackBar('已移出 ${task.comicTitle} 的缓存任务');
  }

  Future<void> _confirmRemoveQueuedComicAndCache(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移除漫画缓存'),
          content: Text('确认停止《${task.comicTitle}》的后台缓存，并删除这部漫画已缓存的章节吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.removeComicAndDeleteCache(task);
    _showSnackBar('已移除 ${task.comicTitle} 的下载任务和本地缓存');
  }

  Future<void> _confirmClearDownloadQueue() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移除全部下载任务'),
          content: const Text('确认清空当前下载队列，并清理未完成文件吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.clearQueue();
    _showSnackBar('已清空下载队列');
  }

  Future<void> _confirmRemoveQueuedTask(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移出章节任务'),
          content: Text('确认移出《${task.comicTitle}》的 ${task.chapterLabel} 吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.removeQueuedTask(task);
    _showSnackBar('已移出 ${task.chapterLabel}');
  }

  Future<void> _retryDownloadQueueTask(DownloadQueueTask task) async {
    await _downloadQueueManager.retryTask(task);
    _showSnackBar('已重新加入 ${task.chapterLabel}');
  }

  bool _canEditDownloadStorage() {
    final String? reason = _downloadQueueManager.storageEditBlockReason();
    if (reason != null) {
      _showSnackBar(reason);
      return false;
    }
    return true;
  }

  Future<void> _pickDownloadStorageDirectory() async {
    if (!_downloadQueueManager.supportsCustomStorageSelection ||
        !_canEditDownloadStorage()) {
      return;
    }
    final PickedDocumentTreeDirectory? pickedDirectory =
        await _downloadStorageService.pickDocumentTreeDirectory();
    if (pickedDirectory != null) {
      final DownloadPreferences nextPreferences = DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath: '',
        customTreeUri: pickedDirectory.treeUri,
        customDisplayPath: pickedDirectory.displayName,
        usePickedDirectoryAsRoot: true,
      );
      await _applyDownloadStoragePreferences(
        nextPreferences,
        successMessage: '已开始迁移到新的存储位置',
      );
    }
  }

  Future<void> _resetDownloadStorageDirectory() async {
    if (!_canEditDownloadStorage()) {
      return;
    }
    await _applyDownloadStoragePreferences(
      const DownloadPreferences(),
      successMessage: '已开始迁移到默认缓存目录',
    );
  }

  Future<void> _applyDownloadStoragePreferences(
    DownloadPreferences nextPreferences, {
    required String successMessage,
  }) async {
    try {
      final DownloadStorageMigrationResult? result = await _downloadQueueManager
          .applyStoragePreferences(nextPreferences);
      if (result == null) {
        return;
      }
      _showSnackBar('$successMessage，完成后自动切换');
    } catch (error) {
      await _refreshDownloadStorageState();
      _showSnackBar(_formatDownloadError(error));
    }
  }

  Future<void> _ensureDownloadQueueRunning() async {
    await _downloadQueueManager.ensureRunning();
  }

  String _formatDownloadError(Object error) {
    return switch (error) {
      TimeoutException _ => '章节解析超时',
      HttpException httpError => httpError.message,
      FileSystemException fileError => fileError.message,
      DownloadPausedException paused => paused.message,
      DownloadCancelledException cancelled => cancelled.message,
      _ => error.toString(),
    };
  }

  void _setPendingLocation(
    Uri uri, {
    required StandardPageLoadHandle<EasyCopyPage> pendingLoad,
  }) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    _mutateOwnedRequestEntry(
      pendingLoad.requestContext,
      (PrimaryTabRouteEntry entry) => entry.copyWith(uri: rewrittenUri),
      phase: 'set-pending-location',
    );
  }

  void _startLoading(
    Uri uri, {
    required StandardPageLoadHandle<EasyCopyPage> pendingLoad,
  }) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final bool preserveCurrentPage = pendingLoad.preserveCurrentPage;
    if (!preserveCurrentPage &&
        _canCommitRequest(pendingLoad.requestContext) &&
        pendingLoad.targetTabIndex == _selectedIndex) {
      _resetStandardScrollPosition();
    }
    final EasyCopyPage? visiblePage = preserveCurrentPage
        ? _tabSessionStore.currentEntry(pendingLoad.targetTabIndex).page
        : null;
    _mutateOwnedRequestEntry(
      pendingLoad.requestContext,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        uri: rewrittenUri,
        page: visiblePage,
        clearPage: !preserveCurrentPage,
        isLoading: true,
        clearError: true,
        standardScrollOffset: preserveCurrentPage
            ? entry.standardScrollOffset
            : 0,
      ),
      phase: 'start-loading',
    );
  }

  NavigationRequestContext _prepareRouteEntry(
    Uri uri, {
    required int targetTabIndex,
    required NavigationIntent intent,
    required bool preserveVisiblePage,
    required NavigationRequestSourceKind sourceKind,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex = targetTabIndex;
    final NavigationRequestContext requestContext =
        _createNavigationRequestContext(
          targetUri,
          targetTabIndex: tabIndex,
          intent: intent,
          preserveVisiblePage: preserveVisiblePage,
          sourceKind: sourceKind,
        );
    final bool shouldActivateTab = shouldActivateTargetTab(
      currentSelectedIndex: _selectedIndex,
      targetTabIndex: tabIndex,
      phase: TabActivationPhase.navigationRequest,
    );
    final EasyCopyPage? preservedPage = preserveVisiblePage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    final int previousSelectedIndex = _selectedIndex;
    _mutateSessionState(() {
      if (previousSelectedIndex != tabIndex) {
        _abandonCurrentRequest(
          previousSelectedIndex,
          phase: 'activate-tab-$tabIndex',
        );
      }
      if (intent == NavigationIntent.push) {
        _abandonCurrentRequest(tabIndex, phase: 'push-route');
      }
      switch (intent) {
        case NavigationIntent.push:
          _tabSessionStore.push(tabIndex, targetUri);
          break;
        case NavigationIntent.preserve:
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
        case NavigationIntent.resetToRoot:
          _tabSessionStore.resetToRoot(tabIndex);
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
      }
      if (shouldActivateTab) {
        _selectedIndex = tabIndex;
      }
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          uri: targetUri,
          page: preservedPage,
          clearPage: !preserveVisiblePage,
          isLoading: true,
          clearError: true,
          standardScrollOffset: preserveVisiblePage
              ? entry.standardScrollOffset
              : 0,
          activeRequestId: requestContext.requestId,
        ),
      );
    });
    if (preserveVisiblePage &&
        preservedPage != null &&
        preservedPage is! ReaderPageData &&
        tabIndex == _selectedIndex) {
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        tabIndex,
      );
      _restoreStandardScrollPosition(
        entry.standardScrollOffset,
        tabIndex: tabIndex,
        routeKey: entry.routeKey,
      );
    }
    return requestContext;
  }

  void _markTabEntryLoading(
    NavigationRequestContext request, {
    required bool preservePage,
  }) {
    _mutateOwnedRequestEntry(
      request,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: true,
        clearError: true,
        clearPage: !preservePage,
      ),
      phase: 'mark-loading',
    );
  }

  void _finishTabEntryLoading(
    NavigationRequestContext request, {
    String? message,
  }) {
    _mutateOwnedRequestEntry(
      request,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: false,
        errorMessage: message,
        clearError: message == null,
      ),
      phase: 'finish-loading',
    );
  }

  void _finishMatchingRouteLoading(
    NavigationRequestContext request, {
    String? message,
  }) {
    _finishTabEntryLoading(request, message: message);
  }

  Future<EasyCopyPage> _loadStandardPageFresh(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final NavigationRequestContext loadRequestContext =
        requestContext ??
        _createNavigationRequestContext(
          targetUri,
          targetTabIndex: resolveNavigationTabIndex(targetUri),
          intent: NavigationIntent.preserve,
          preserveVisiblePage: false,
          sourceKind: NavigationRequestSourceKind.navigation,
        );
    final int loadId = ++_activeLoadId;
    final StandardPageLoadHandle<EasyCopyPage> pendingLoad =
        StandardPageLoadHandle<EasyCopyPage>(
          requestedUri: targetUri,
          queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
          loadId: loadId,
          requestContext: loadRequestContext,
          completer: Completer<EasyCopyPage>(),
        );
    _standardPageLoadController.begin(pendingLoad);
    await _syncSessionCookiesToCurrentHost();
    if (!_standardPageLoadController.isCurrent(pendingLoad)) {
      _detachPrimaryWebViewIfIdle();
      throw const SupersededPageLoadException();
    }
    await _ensurePrimaryWebViewAttached();
    try {
      await _controller.loadRequest(targetUri);
    } catch (_) {
      _failPendingPageLoad('頁面加載失敗，請稍後重試。');
      rethrow;
    }
    return pendingLoad.completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _standardPageLoadController.clear(pendingLoad);
        _detachPrimaryWebViewIfIdle();
        throw TimeoutException('页面解析超时');
      },
    );
  }

  bool _applyLoadedPage(
    EasyCopyPage page, {
    NavigationRequestContext? requestContext,
    int? targetTabIndex,
    bool switchToTab = true,
    Uri? visibleUri,
  }) {
    final EasyCopyPage resolvedPage = _pageForVisibleUri(page, visibleUri);
    final Uri pageUri = AppConfig.rewriteToCurrentHost(
      Uri.parse(resolvedPage.uri),
    );
    final int tabIndex =
        requestContext?.targetTabIndex ??
        targetTabIndex ??
        tabIndexForUri(pageUri);
    if (requestContext != null && !_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(requestContext, phase: 'apply-page');
      return false;
    }
    final EasyCopyPage? previousPage =
        (switchToTab || tabIndex == _selectedIndex) ? _page : null;
    final String? previousReaderUri =
        tabIndex == _selectedIndex && _page is ReaderPageData
        ? (_page as ReaderPageData).uri
        : null;

    _mutateSessionState(() {
      if (switchToTab) {
        _selectedIndex = tabIndex;
      }
      _tabSessionStore.updatePage(tabIndex, resolvedPage);
      if (resolvedPage is DetailPageData) {
        _syncDetailChapterState(
          resolvedPage,
          forceReset:
              previousPage is! DetailPageData ||
              previousPage.uri != resolvedPage.uri,
        );
        unawaited(_persistCachedDetailSnapshot(resolvedPage));
      }
    }, syncSearch: switchToTab || tabIndex == _selectedIndex);
    _scheduleReaderPresentationSync();

    if (tabIndex != _selectedIndex) {
      return true;
    }
    if (resolvedPage is ReaderPageData) {
      _handleReaderPageLoaded(resolvedPage, previousUri: previousReaderUri);
      return true;
    }
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(tabIndex);
    _restoreStandardScrollPosition(
      entry.standardScrollOffset,
      tabIndex: tabIndex,
      routeKey: entry.routeKey,
    );
    return true;
  }

  EasyCopyPage _pageForVisibleUri(EasyCopyPage page, Uri? visibleUri) {
    if (visibleUri == null) {
      return page;
    }
    final Uri normalizedVisibleUri = AppConfig.rewriteToCurrentHost(visibleUri);
    if (page is ProfilePageData && _isProfileUri(normalizedVisibleUri)) {
      return page.copyWith(uri: normalizedVisibleUri.toString());
    }
    return page;
  }

  void _failPendingPageLoad(String message) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null) {
      _detachPrimaryWebViewIfIdle();
      return;
    }
    if (!pendingLoad.completer.isCompleted) {
      pendingLoad.completer.completeError(message);
    }
    _standardPageLoadController.clear(pendingLoad);
    _detachPrimaryWebViewIfIdle();
  }

  Future<void> _loadUri(
    Uri uri, {
    bool bypassCache = false,
    bool preserveVisiblePage = false,
    bool skipPersistVisiblePageState = false,
    NavigationIntent historyMode = NavigationIntent.push,
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    _CachedChapterNavigationContext cachedChapterContext =
        const _CachedChapterNavigationContext(),
  }) async {
    if (!skipPersistVisiblePageState) {
      _persistVisiblePageState();
    }
    await _hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int resolvedTargetTabIndex =
        targetTabIndexOverride ??
        resolveNavigationTabIndex(targetUri, sourceTabIndex: sourceTabIndex);
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (!bypassCache &&
        !preserveVisiblePage &&
        !_isLoading &&
        _page != null &&
        _currentEntry.routeKey == key.routeKey &&
        _isPrimaryTabContent) {
      _restoreStandardScrollPosition(
        _currentEntry.standardScrollOffset,
        tabIndex: _selectedIndex,
        routeKey: _currentEntry.routeKey,
      );
      return;
    }
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    if (_isProfileUri(targetUri)) {
      await _loadProfilePage(
        targetUri: targetUri,
        forceRefresh: bypassCache,
        historyMode: historyMode,
        preserveVisiblePage: preserveVisiblePage,
      );
      return;
    }
    if (!AppConfig.isAllowedNavigationUri(targetUri)) {
      _showSnackBar('已阻止跳转到站外页面');
      return;
    }
    _consecutiveFrameFailures = 0;
    final NavigationRequestContext requestContext = _prepareRouteEntry(
      targetUri,
      targetTabIndex: resolvedTargetTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: NavigationRequestSourceKind.navigation,
    );
    final bool isReaderChapterRoute = _isReaderChapterUri(targetUri);
    final bool shouldPreferFreshReaderLoad =
        isReaderChapterRoute &&
        _downloadQueueManager.shouldBypassCachedReaderLookup;
    final Stopwatch? readerLoadStopwatch = isReaderChapterRoute
        ? (Stopwatch()..start())
        : null;
    if (isReaderChapterRoute) {
      DebugTrace.log('reader.load_request', <String, Object?>{
        'bootId': _bootId,
        'uri': targetUri.toString(),
        'bypassCache': bypassCache,
        'historyMode': historyMode.name,
      });
    }
    if (isReaderChapterRoute) {
      if (shouldPreferFreshReaderLoad) {
        DebugTrace.log('reader.cached_lookup_skipped', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
          'reason': 'storage_migration_active',
        });
      } else {
        final bool openedFromCache = await _tryOpenCachedChapterReader(
          targetUri,
          requestContext: requestContext.copyWith(
            sourceKind: NavigationRequestSourceKind.cachedReader,
          ),
          context: cachedChapterContext,
        );
        if (openedFromCache) {
          DebugTrace.log('reader.load_complete', <String, Object?>{
            'bootId': _bootId,
            'uri': targetUri.toString(),
            'source': 'storage_cache',
            'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
          });
          return;
        }
      }
      if (!_canCommitRequest(requestContext)) {
        return;
      }
    }
    if (!bypassCache && !shouldPreferFreshReaderLoad) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedNavigationMutation(
          requestContext,
          phase: 'cached-read',
        );
        return;
      }
      if (cachedHit != null) {
        if (!_shouldBypassUnknownCache(targetUri, cachedHit.page)) {
          _applyLoadedPage(
            cachedHit.page,
            requestContext: requestContext,
            switchToTab: _shouldActivateAsyncResultTab(
              requestContext.targetTabIndex,
            ),
          );
          if (isReaderChapterRoute) {
            DebugTrace.log('reader.load_complete', <String, Object?>{
              'bootId': _bootId,
              'uri': targetUri.toString(),
              'source': 'page_cache',
              'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
            });
            final EasyCopyPage cachedPage = cachedHit.page;
            if (cachedPage is ReaderPageData &&
                cachedPage.imageUrls.isNotEmpty) {
              NetworkDiagnostics.probeImageVariants(
                cachedPage.imageUrls.first,
                referer: cachedPage.uri,
                label: 'reader.first_image_page_cache',
              );
            }
          }
          if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
            return;
          }
          _markTabEntryLoading(requestContext, preservePage: true);
          unawaited(
            _revalidateCachedPage(
              targetUri,
              key: key,
              cachedEntry: cachedHit.envelope,
              requestContext: requestContext.copyWith(
                sourceKind: NavigationRequestSourceKind.revalidate,
              ),
            ),
          );
          return;
        }
      }
    } else if (shouldPreferFreshReaderLoad) {
      DebugTrace.log('reader.page_cache_skipped', <String, Object?>{
        'bootId': _bootId,
        'uri': targetUri.toString(),
        'reason': 'storage_migration_active',
      });
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(requestContext, phase: 'fresh-load');
      return;
    }
    try {
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.fresh_load_start', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
        });
      }
      final EasyCopyPage freshPage = await _pageRepository.loadFresh(
        targetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.load_complete', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
          'source': 'fresh',
          'pageType': freshPage.type.name,
          'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
        });
        if (freshPage is ReaderPageData && freshPage.imageUrls.isNotEmpty) {
          NetworkDiagnostics.probeImageVariants(
            freshPage.imageUrls.first,
            referer: freshPage.uri,
            label: 'reader.first_image_fresh',
          );
        }
      }
      _applyLoadedPage(
        freshPage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
      );
    } catch (error) {
      if (isReaderChapterRoute) {
        DebugTrace.log('reader.load_failed', <String, Object?>{
          'bootId': _bootId,
          'uri': targetUri.toString(),
          'elapsedMs': readerLoadStopwatch?.elapsedMilliseconds,
          'error': error.toString(),
        });
      }
      await _handlePageLoadFailure(error, requestContext: requestContext);
    }
  }

  bool _shouldBypassUnknownCache(Uri uri, EasyCopyPage page) {
    if (page is! UnknownPageData) {
      return false;
    }
    final String path = uri.path.toLowerCase();
    return path == '/' ||
        path.startsWith('/comics') ||
        path.startsWith('/search') ||
        path.startsWith('/rank') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest') ||
        path.startsWith('/comic/') ||
        path.startsWith('/person') ||
        path.startsWith('/web/login');
  }

  _CachedChapterNavigationContext _resolvedCachedChapterContext(
    Uri targetUri, {
    required _CachedChapterNavigationContext context,
  }) {
    final EasyCopyPage? currentPage = _page;
    _CachedChapterNavigationContext resolvedContext = context;
    if (currentPage is ReaderPageData && !context.hasAnyValue) {
      final String targetKey = _chapterPathKey(targetUri.toString());
      final String currentKey = _chapterPathKey(currentPage.uri);
      final String prevKey = _chapterPathKey(currentPage.prevHref);
      final String nextKey = _chapterPathKey(currentPage.nextHref);

      if (targetKey == currentKey) {
        resolvedContext = _CachedChapterNavigationContext(
          prevHref: currentPage.prevHref,
          nextHref: currentPage.nextHref,
          catalogHref: currentPage.catalogHref,
        );
      } else if (targetKey == prevKey) {
        resolvedContext = _CachedChapterNavigationContext(
          nextHref: currentPage.uri,
          catalogHref: currentPage.catalogHref,
        );
      } else if (targetKey == nextKey) {
        resolvedContext = _CachedChapterNavigationContext(
          prevHref: currentPage.uri,
          catalogHref: currentPage.catalogHref,
        );
      } else {
        resolvedContext = _CachedChapterNavigationContext(
          catalogHref: currentPage.catalogHref,
        );
      }
    }

    final _CachedChapterNavigationContext detailContext =
        _cachedChapterNavigationContextFromDetail(
          targetUri,
          preferredCatalogHref: resolvedContext.catalogHref,
        );
    return resolvedContext.mergeMissing(detailContext);
  }

  _CachedChapterNavigationContext _cachedChapterNavigationContextFromDetail(
    Uri targetUri, {
    String preferredCatalogHref = '',
  }) {
    final String targetKey = _chapterPathKey(targetUri.toString());
    if (targetKey.isEmpty) {
      return const _CachedChapterNavigationContext();
    }
    final List<PrimaryTabRouteEntry> stackEntries = _tabSessionStore
        .stackForTab(_selectedIndex);
    final List<DetailPageData> detailPages = stackEntries
        .map((PrimaryTabRouteEntry entry) => entry.page)
        .whereType<DetailPageData>()
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    if (detailPages.isEmpty) {
      return const _CachedChapterNavigationContext();
    }

    _CachedChapterNavigationContext contextForPage(DetailPageData page) {
      final List<ChapterData> chapters = _detailChapterList(page);
      final int index = chapters.indexWhere(
        (ChapterData chapter) => _chapterPathKey(chapter.href) == targetKey,
      );
      if (index == -1) {
        return const _CachedChapterNavigationContext();
      }
      return _CachedChapterNavigationContext(
        prevHref: index > 0 ? chapters[index - 1].href : '',
        nextHref: index + 1 < chapters.length ? chapters[index + 1].href : '',
        catalogHref: page.uri,
      );
    }

    final String preferredCatalogRouteKey = preferredCatalogHref.trim().isEmpty
        ? ''
        : AppConfig.routeKeyForUri(Uri.parse(preferredCatalogHref));
    if (preferredCatalogRouteKey.isNotEmpty) {
      for (final DetailPageData page in detailPages) {
        if (AppConfig.routeKeyForUri(Uri.parse(page.uri)) !=
            preferredCatalogRouteKey) {
          continue;
        }
        final _CachedChapterNavigationContext context = contextForPage(page);
        if (context.hasAnyValue) {
          return context;
        }
      }
    }

    for (final DetailPageData page in detailPages) {
      final _CachedChapterNavigationContext context = contextForPage(page);
      if (context.hasAnyValue) {
        return context;
      }
    }
    return const _CachedChapterNavigationContext();
  }

  Future<void> _revalidateCachedPage(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope cachedEntry,
    required NavigationRequestContext requestContext,
    Uri? visibleUri,
  }) async {
    try {
      await _pageRepository.revalidate(
        uri,
        key: key,
        envelope: cachedEntry,
        requestContext: requestContext,
      );
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedNavigationMutation(
          requestContext,
          phase: 'revalidate-complete',
        );
        return;
      }
      final CachedPageHit? refreshedHit = await _pageRepository.readCached(key);
      if (refreshedHit != null) {
        _applyLoadedPage(
          refreshedHit.page,
          requestContext: requestContext,
          switchToTab: _shouldActivateAsyncResultTab(
            requestContext.targetTabIndex,
          ),
          visibleUri: visibleUri,
        );
        return;
      }
      _finishMatchingRouteLoading(requestContext);
    } on SupersededPageLoadException {
      _finishMatchingRouteLoading(requestContext);
    } catch (_) {
      _finishMatchingRouteLoading(requestContext);
    }
  }

  Future<void> _loadProfilePage({
    Uri? targetUri,
    bool forceRefresh = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _persistVisiblePageState();
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    final Uri resolvedTargetUri = AppConfig.rewriteToCurrentHost(
      targetUri ?? AppConfig.profileUri,
    );
    const int profileTabIndex = 3;
    final NavigationRequestContext requestContext = _prepareRouteEntry(
      resolvedTargetUri,
      targetTabIndex: profileTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: NavigationRequestSourceKind.profile,
    );
    final PageQueryKey key = _pageQueryKeyForUri(resolvedTargetUri);
    if (!forceRefresh) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (!_canCommitRequest(requestContext)) {
        _recordDiscardedNavigationMutation(
          requestContext,
          phase: 'profile-cached-read',
        );
        return;
      }
      if (cachedHit != null) {
        _applyLoadedPage(
          cachedHit.page,
          requestContext: requestContext,
          switchToTab: _shouldActivateAsyncResultTab(
            requestContext.targetTabIndex,
          ),
          visibleUri: resolvedTargetUri,
        );
        if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
          return;
        }
        _markTabEntryLoading(requestContext, preservePage: true);
        unawaited(
          _revalidateCachedPage(
            resolvedTargetUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            requestContext: requestContext.copyWith(
              sourceKind: NavigationRequestSourceKind.revalidate,
            ),
            visibleUri: resolvedTargetUri,
          ),
        );
        return;
      }
    }

    try {
      final EasyCopyPage profilePage = await _pageRepository.loadFresh(
        resolvedTargetUri,
        authScope: key.authScope,
        requestContext: requestContext,
      );
      _applyLoadedPage(
        profilePage,
        requestContext: requestContext,
        switchToTab: _shouldActivateAsyncResultTab(
          requestContext.targetTabIndex,
        ),
        visibleUri: resolvedTargetUri,
      );
    } catch (error) {
      await _handlePageLoadFailure(error, requestContext: requestContext);
    }
  }

  Future<void> _handlePageLoadFailure(
    Object error, {
    required NavigationRequestContext requestContext,
  }) async {
    if (error is SupersededPageLoadException) {
      _finishMatchingRouteLoading(requestContext);
      return;
    }

    if (!_canCommitRequest(requestContext)) {
      _recordDiscardedNavigationMutation(
        requestContext,
        phase: 'page-load-failure',
      );
      return;
    }

    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (requestContext.targetTabIndex == _selectedIndex) {
        _showSnackBar('登录已失效，请重新登录。');
      }
      return;
    }

    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
      requestContext.targetTabIndex,
    );
    if (entry.page != null) {
      _finishTabEntryLoading(requestContext);
      if (requestContext.targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }

    _finishTabEntryLoading(requestContext, message: message);
  }

  Future<void> _retryCurrentPage() async {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData ||
        (page == null && _isProfileUri(_currentUri))) {
      await _loadProfilePage(
        targetUri: _currentUri,
        forceRefresh: true,
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    await _loadUri(
      _currentUri,
      bypassCache: true,
      preserveVisiblePage: _page != null,
      sourceTabIndex: _selectedIndex,
      historyMode: NavigationIntent.preserve,
    );
  }

  Future<void> _loadHome() async {
    await _loadUri(
      _targetUriForPrimaryTab(0, resetToRoot: true),
      preserveVisiblePage: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  void _openProfileSubview(ProfileSubview view, {int page = 1}) {
    unawaited(
      _loadProfilePage(
        targetUri: AppConfig.buildProfileUri(view: view, page: page),
        preserveVisiblePage: _page is ProfilePageData,
        historyMode: NavigationIntent.push,
      ),
    );
  }

  void _navigateDiscoverFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    _applyOptimisticDiscoverFilterSelectionToCurrentPage(targetUri);
    unawaited(
      _loadUri(
        targetUri,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _navigateRankFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    _applyOptimisticRankFilterSelectionToCurrentPage(targetUri);
    unawaited(
      _loadUri(
        targetUri,
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _applyOptimisticDiscoverFilterSelectionToCurrentPage(Uri targetUri) {
    final EasyCopyPage? page = _page;
    if (page is! DiscoverPageData) {
      return;
    }
    final DiscoverPageData nextPage = applyOptimisticDiscoverFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _applyOptimisticRankFilterSelectionToCurrentPage(Uri targetUri) {
    final EasyCopyPage? page = _page;
    if (page is! RankPageData) {
      return;
    }
    final RankPageData nextPage = applyOptimisticRankFilterSelection(
      page,
      currentUri: _currentUri,
      targetUri: targetUri,
    );
    if (identical(nextPage, page)) {
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        _selectedIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(page: nextPage),
      );
    });
  }

  void _navigateToHref(String href, {int? sourceTabIndex}) {
    unawaited(
      _openHref(href, sourceTabIndex: sourceTabIndex ?? _selectedIndex),
    );
  }

  Future<void> _openHref(
    String href, {
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
    int? sourceTabIndex,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    await _loadUri(
      targetUri,
      sourceTabIndex: sourceTabIndex ?? _selectedIndex,
      historyMode: historyMode,
      cachedChapterContext: _CachedChapterNavigationContext(
        prevHref: prevHref,
        nextHref: nextHref,
        catalogHref: catalogHref,
      ),
    );
  }

  bool _isReaderChapterUri(Uri uri) {
    return uri.pathSegments.contains('chapter');
  }

  Future<bool> _tryOpenCachedChapterReader(
    Uri targetUri, {
    required NavigationRequestContext requestContext,
    _CachedChapterNavigationContext context =
        const _CachedChapterNavigationContext(),
  }) async {
    final _CachedChapterNavigationContext resolvedContext =
        _resolvedCachedChapterContext(targetUri, context: context);
    final ReaderPageData? cachedPage = await _downloadService
        .loadCachedReaderPage(
          targetUri.toString(),
          prevHref: resolvedContext.prevHref,
          nextHref: resolvedContext.nextHref,
          catalogHref: resolvedContext.catalogHref,
        );
    if (cachedPage == null) {
      return false;
    }
    return _applyLoadedPage(
      cachedPage,
      requestContext: requestContext,
      switchToTab: true,
    );
  }

  void _openDetailChapter(DetailPageData page, String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final _AdjacentChapterLinks links = _adjacentChapterLinksForDetail(
      page,
      href,
    );
    unawaited(
      _openHref(
        href,
        prevHref: links.prevHref,
        nextHref: links.nextHref,
        catalogHref: page.uri,
      ),
    );
  }

  List<ChapterData> _detailChapterList(DetailPageData page) {
    if (page.chapters.isNotEmpty) {
      return page.chapters;
    }
    if (page.chapterGroups.isNotEmpty) {
      return page.chapterGroups
          .expand((ChapterGroupData group) => group.chapters)
          .toList(growable: false);
    }
    return page.chapters;
  }

  _AdjacentChapterLinks _adjacentChapterLinksForDetail(
    DetailPageData page,
    String href,
  ) {
    final List<ChapterData> chapters = _detailChapterList(page);
    final String targetKey = _chapterPathKey(href);
    final int index = chapters.indexWhere(
      (ChapterData chapter) => _chapterPathKey(chapter.href) == targetKey,
    );
    if (index == -1) {
      return const _AdjacentChapterLinks();
    }
    return _AdjacentChapterLinks(
      prevHref: index > 0 ? chapters[index - 1].href : '',
      nextHref: index + 1 < chapters.length ? chapters[index + 1].href : '',
    );
  }

  Future<DetailPageData?> _refreshDetailPageForCollection(
    DetailPageData page, {
    required int sourceTabIndex,
    required bool preserveVisiblePage,
  }) async {
    await _loadUri(
      Uri.parse(page.uri),
      bypassCache: true,
      preserveVisiblePage: preserveVisiblePage,
      sourceTabIndex: sourceTabIndex,
      targetTabIndexOverride: sourceTabIndex,
      historyMode: NavigationIntent.preserve,
    );
    final EasyCopyPage? refreshedPage = _page;
    if (refreshedPage is! DetailPageData || refreshedPage.uri != page.uri) {
      return null;
    }
    return refreshedPage;
  }

  Future<DetailPageData?> _ensureDetailPageReadyForCollection(
    DetailPageData page, {
    required int sourceTabIndex,
  }) async {
    DetailPageData workingPage = page;
    if (!_session.isAuthenticated) {
      await _openAuthFlow();
      if (!_session.isAuthenticated || !mounted) {
        return null;
      }
      final DetailPageData? refreshedPage =
          await _refreshDetailPageForCollection(
            page,
            sourceTabIndex: sourceTabIndex,
            preserveVisiblePage: false,
          );
      if (refreshedPage == null) {
        return null;
      }
      workingPage = refreshedPage;
    }

    if (workingPage.comicId.trim().isNotEmpty) {
      return workingPage;
    }

    final DetailPageData? refreshedPage = await _refreshDetailPageForCollection(
      workingPage,
      sourceTabIndex: sourceTabIndex,
      preserveVisiblePage: true,
    );
    if (refreshedPage == null || refreshedPage.comicId.trim().isEmpty) {
      return null;
    }
    return refreshedPage;
  }

  Future<void> _toggleDetailCollection(DetailPageData page) async {
    if (_isUpdatingCollection) {
      return;
    }

    final int sourceTabIndex = _selectedIndex;
    final DetailPageData? detailPage =
        await _ensureDetailPageReadyForCollection(
          page,
          sourceTabIndex: sourceTabIndex,
        );
    if (detailPage == null) {
      if (mounted && _session.isAuthenticated) {
        _showSnackBar('收藏信息未准备好，请刷新详情页后重试。');
      }
      return;
    }

    final bool nextCollected = !detailPage.isCollected;
    _mutateSessionState(() {
      _isUpdatingCollection = true;
    }, syncSearch: false);
    try {
      await _siteApiClient.setComicCollection(
        comicId: detailPage.comicId,
        isCollected: nextCollected,
      );
      final DetailPageData updatedPage = detailPage.copyWith(
        isCollected: nextCollected,
      );
      _mutateSessionState(() {
        _tabSessionStore.updatePage(sourceTabIndex, updatedPage);
      }, syncSearch: sourceTabIndex == _selectedIndex);
      await _pageRepository.removeAuthScope(_session.authScope);
      if (mounted) {
        _showSnackBar(nextCollected ? '已加入书架' : '已取消收藏');
      }
    } catch (error) {
      final String message = error.toString();
      if (message.contains('登录已失效')) {
        await _logout(showFeedback: false);
        if (mounted) {
          _showSnackBar('登录已失效，请重新登录。');
        }
      } else if (mounted) {
        _showSnackBar(message.isEmpty ? '收藏操作失败，请稍后重试。' : message);
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingCollection = false;
        }, syncSearch: false);
      } else {
        _isUpdatingCollection = false;
      }
    }
  }

  Future<void> _openAuthFlow() async {
    await _hostManager.ensureInitialized();
    if (!mounted) {
      return;
    }
    final AuthSessionResult? result = await Navigator.of(context).push(
      MaterialPageRoute<AuthSessionResult>(
        builder: (BuildContext context) {
          return NativeLoginScreen(
            loginUri: AppConfig.resolvePath('/web/login/?url=person/home'),
            userAgent: AppConfig.desktopUserAgent,
          );
        },
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final String? token = result.cookies['token'];
    if ((token ?? '').isEmpty) {
      return;
    }
    await _session.updateFromCookieHeader(result.cookieHeader);
    await _session.saveToken(token!, cookies: result.cookies);
    await _syncSessionCookiesToCurrentHost();
    await _loadProfilePage(
      forceRefresh: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  Future<void> _logout({bool showFeedback = true}) async {
    _persistVisiblePageState();
    _resetStandardScrollPosition();
    await _pageRepository.removeAuthenticatedEntries();
    await _session.clear();
    await _cookieManager.clearCookies();
    _mutateSessionState(() {
      for (int index = 0; index < appDestinations.length; index += 1) {
        _abandonCurrentRequest(index, phase: 'logout');
      }
      _selectedIndex = 3;
      _tabSessionStore.resetToRoot(3);
      _tabSessionStore.updatePage(
        3,
        ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString()),
      );
    });
    if (showFeedback) {
      _showSnackBar('已退出登录');
    }
  }

  String get _appVersionLabel {
    if (_appVersion.isEmpty) {
      return '--';
    }
    if (_appBuildNumber.isEmpty) {
      return _appVersion;
    }
    return '$_appVersion+$_appBuildNumber';
  }

  Future<void> _loadAppVersionInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) {
        _appVersion = packageInfo.version.trim();
        _appBuildNumber = packageInfo.buildNumber.trim();
        return;
      }
      _setStateIfMounted(() {
        _appVersion = packageInfo.version.trim();
        _appBuildNumber = packageInfo.buildNumber.trim();
      });
    } catch (_) {
      // Keep placeholder values when package info is unavailable.
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) {
      return;
    }
    if (_appVersion.isEmpty) {
      await _loadAppVersionInfo();
    }
    final String currentVersion = _appVersion.trim();
    if (currentVersion.isEmpty) {
      _showSnackBar('版本信息不可用');
      return;
    }

    _mutateSessionState(() {
      _isCheckingForUpdates = true;
    }, syncSearch: false);
    try {
      final AppUpdateInfo updateInfo = await AppUpdateChecker.instance
          .checkForUpdates(currentVersion: currentVersion);
      if (!mounted) {
        return;
      }
      if (!updateInfo.hasUpdate) {
        _showSnackBar('已是最新版本');
        return;
      }

      final bool? shouldOpenRelease = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('发现新版本'),
            content: Text(
              '${updateInfo.currentVersion} -> ${updateInfo.latestVersion}',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('前往'),
              ),
            ],
          );
        },
      );
      if (shouldOpenRelease == true) {
        await _launchExternalUri(updateInfo.releaseUri);
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('检查更新失败');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isCheckingForUpdates = false;
        }, syncSearch: false);
      } else {
        _isCheckingForUpdates = false;
      }
    }
  }

  Future<void> _openProjectRepository() async {
    await _launchExternalUri(AppUpdateChecker.repositoryUri);
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnackBar('打开失败');
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('打开失败');
      }
    }
  }

  Future<void> _refreshHostSettings() async {
    if (_isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.refreshProbes(force: true);
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return;
      }
      final bool isPinned = _hostManager.sessionPinnedHost != null;
      _showSnackBar(
        isPinned
            ? '测速完成，当前仍手动锁定到域名 ${_hostManager.currentHost}'
            : '测速完成，已自动选择 ${_hostManager.currentHost}',
      );
    } catch (_) {
      if (mounted) {
        _showSnackBar('测速失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _selectHost(String host) async {
    final String normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty || _isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.pinSessionHost(normalizedHost);
      await _syncSessionCookiesToCurrentHost();
      if (mounted) {
        _showSnackBar('已切换到 $normalizedHost');
      }
    } catch (error) {
      if (mounted) {
        final String message = error is StateError
            ? error.message.toString()
            : '切换域名失败，请稍后重试';
        _showSnackBar(message);
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _useAutomaticHostSelection() async {
    if (_isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.clearSessionPin();
      await _hostManager.refreshProbes(force: true);
      await _syncSessionCookiesToCurrentHost();
      if (mounted) {
        _showSnackBar('已恢复自动选择，当前域名 ${_hostManager.currentHost}');
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('恢复自动选择失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    TopNotice.show(context, message, tone: _topNoticeToneFor(message));
  }

  TopNoticeTone _topNoticeToneFor(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return TopNoticeTone.info;
    }
    if (normalized.contains('失败') ||
        normalized.contains('异常') ||
        normalized.contains('错误') ||
        normalized.contains('失效') ||
        normalized.contains('不可用')) {
      return TopNoticeTone.error;
    }
    if (normalized.contains('警告') ||
        normalized.contains('稍后') ||
        normalized.contains('阻止')) {
      return TopNoticeTone.warning;
    }
    if (normalized.contains('已') ||
        normalized.contains('完成') ||
        normalized.contains('恢复') ||
        normalized.contains('继续')) {
      return TopNoticeTone.success;
    }
    return TopNoticeTone.info;
  }

  void _syncSearchController() {
    final String query = _currentUri.queryParameters['q'] ?? '';
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _primeSearchController(String query) {
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _submitSearch(
    String value, {
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    NavigationIntent historyMode = NavigationIntent.push,
  }) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    _primeSearchController(query);
    unawaited(
      _loadUri(
        AppConfig.buildSearchUri(query),
        sourceTabIndex: sourceTabIndex,
        targetTabIndexOverride: targetTabIndexOverride,
        historyMode: historyMode,
      ),
    );
  }

  void _submitSearchFromCurrentStack(String value) {
    _submitSearch(
      value,
      sourceTabIndex: _selectedIndex,
      targetTabIndexOverride: _selectedIndex,
    );
  }

  bool get _shouldKeepDiscoverSearchInCurrentStack =>
      _selectedIndex != 1 && _isPrimaryDiscoverUri(_currentUri);

  void _submitSearchFromVisibleDiscoverContext(String value) {
    if (_shouldKeepDiscoverSearchInCurrentStack) {
      _submitSearchFromCurrentStack(value);
      return;
    }
    _submitSearch(value);
  }

  void _clearVisibleDiscoverSearch() {
    if (_currentUri.path == '/search') {
      _searchController.clear();
      unawaited(
        _loadUri(
          AppConfig.resolvePath('/comics'),
          sourceTabIndex: _shouldKeepDiscoverSearchInCurrentStack
              ? _selectedIndex
              : null,
          targetTabIndexOverride: _shouldKeepDiscoverSearchInCurrentStack
              ? _selectedIndex
              : null,
          historyMode: NavigationIntent.preserve,
        ),
      );
      return;
    }
    _setStateIfMounted(_searchController.clear);
  }

  Uri _targetUriForPrimaryTab(int index, {bool resetToRoot = false}) {
    if (resetToRoot) {
      return appDestinations[index].uri;
    }
    return _tabSessionStore.currentEntry(index).uri;
  }

  Future<void> _onItemTapped(int index) async {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (index == _selectedIndex && _isPrimaryTabContent && !_isLoading) {
      await _scrollCurrentStandardPageToTop();
      return;
    }
    if (index == 3) {
      await _loadProfilePage(
        preserveVisiblePage: true,
        historyMode: index == _selectedIndex
            ? NavigationIntent.resetToRoot
            : NavigationIntent.preserve,
      );
      return;
    }
    final bool shouldResetToRoot = index == _selectedIndex;
    final Uri targetUri = _targetUriForPrimaryTab(
      index,
      resetToRoot: shouldResetToRoot,
    );
    await _loadUri(
      targetUri,
      preserveVisiblePage: !shouldResetToRoot,
      // Restoring a tab should keep the tab's own stack ownership even when
      // the visible route is a shared detail or reader URI like `/comic/...`.
      targetTabIndexOverride: index,
      historyMode: shouldResetToRoot
          ? NavigationIntent.resetToRoot
          : NavigationIntent.preserve,
    );
  }

  Future<void> _handleBackNavigation() async {
    if (_isReaderMode) {
      await _runReaderExitTransition(() async {
        await _handleReaderAwareBackNavigation();
      });
      return;
    }
    await _handleReaderAwareBackNavigation();
  }

  Future<void> _handleReaderAwareBackNavigation() async {
    final EasyCopyPage? page = _page;
    if (page is ReaderPageData) {
      await _flushReaderProgressPersistence();
    }
    _persistVisiblePageState();
    if (page is ReaderPageData && await _handleReaderBackNavigation(page)) {
      return;
    }
    final PrimaryTabRouteEntry? previousEntry = _tabSessionStore.pop(
      _selectedIndex,
    );
    if (previousEntry != null) {
      await _loadUri(
        previousEntry.uri,
        preserveVisiblePage: _page != null,
        skipPersistVisiblePageState: true,
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    if (_isTopicUri(_currentUri)) {
      await _loadHome();
      return;
    }
    if (_selectedIndex != 0) {
      await _loadHome();
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _runReaderExitTransition(Future<void> Function() action) async {
    if (!_isReaderMode || _isReaderExitTransitionActive || !mounted) {
      await action();
      return;
    }

    setState(() {
      _isReaderExitTransitionActive = true;
    });

    final Future<void> fadeFuture = Future<void>.delayed(
      _readerExitFadeDuration,
    );
    try {
      await action();
      await fadeFuture;
    } finally {
      if (!mounted) {
        _isReaderExitTransitionActive = false;
      } else if (_page is ReaderPageData) {
        setState(() {
          _isReaderExitTransitionActive = false;
        });
      } else {
        _isReaderExitTransitionActive = false;
      }
    }
  }

  Future<bool> _handleReaderBackNavigation(ReaderPageData page) async {
    final String catalogHref = page.catalogHref.trim();
    if (catalogHref.isEmpty) {
      return false;
    }
    final Uri catalogUri = AppConfig.resolveNavigationUri(
      catalogHref,
      currentUri: Uri.parse(page.uri),
    );
    final PrimaryTabRouteEntry? existingCatalogEntry = _tabSessionStore
        .popToRoute(_selectedIndex, catalogUri);
    if (existingCatalogEntry != null) {
      await _loadUri(
        existingCatalogEntry.uri,
        preserveVisiblePage: existingCatalogEntry.page != null,
        skipPersistVisiblePageState: true,
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return true;
    }
    await _loadUri(
      catalogUri,
      sourceTabIndex: _selectedIndex,
      historyMode: NavigationIntent.preserve,
    );
    return true;
  }

  Future<void> _handleMainFrameFailure(String message) async {
    _consecutiveFrameFailures += 1;
    if (!mounted) {
      return;
    }
    if (_pendingPageLoad != null) {
      _failPendingPageLoad(message);
    } else if (_page == null) {
      _mutateSessionState(() {
        _tabSessionStore.updateError(
          _selectedIndex,
          _currentEntry.routeKey,
          message,
        );
      });
    } else {
      _mutateSessionState(() {
        _tabSessionStore.updateCurrent(
          _selectedIndex,
          (PrimaryTabRouteEntry entry) =>
              entry.copyWith(isLoading: false, clearError: true),
        );
      });
      _showSnackBar(message);
    }
    if (_isFailingOver) {
      return;
    }
    if (await _tryAutoRecoverHostOnNetworkFailure(message)) {
      _consecutiveFrameFailures = 0;
      return;
    }
    if (_hostManager.sessionPinnedHost != null ||
        _consecutiveFrameFailures < 2) {
      return;
    }
    _isFailingOver = true;
    try {
      final String previousHost = _hostManager.currentHost;
      final String nextHost = await _hostManager.failover(
        exclude: <String>[previousHost],
      );
      if (nextHost == previousHost) {
        return;
      }
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return;
      }
      _showSnackBar('当前入口异常，已切换到备用站点。');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      _consecutiveFrameFailures = 0;
    } finally {
      _isFailingOver = false;
    }
  }

  Future<bool> _tryAutoRecoverHostOnNetworkFailure(String message) async {
    if (_hostManager.sessionPinnedHost != null ||
        !_isLikelyRecoverableNetworkFailure(message)) {
      return false;
    }
    _isFailingOver = true;
    final String previousHost = _hostManager.currentHost;
    try {
      DebugTrace.log('host.auto_probe_start', <String, Object?>{
        'bootId': _bootId,
        'currentHost': previousHost,
        'message': message,
      });
      await _hostManager.refreshProbes(force: true);
      final String nextHost = _hostManager.currentHost;
      DebugTrace.log('host.auto_probe_complete', <String, Object?>{
        'bootId': _bootId,
        'previousHost': previousHost,
        'nextHost': nextHost,
      });
      if (nextHost == previousHost) {
        return false;
      }
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return true;
      }
      _showSnackBar('网络异常，已自动切换到 $nextHost');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return true;
    } catch (error) {
      DebugTrace.log('host.auto_probe_failed', <String, Object?>{
        'bootId': _bootId,
        'currentHost': previousHost,
        'message': message,
        'error': error.toString(),
      });
      return false;
    } finally {
      _isFailingOver = false;
    }
  }

  bool _isLikelyRecoverableNetworkFailure(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const List<String> networkErrorKeywords = <String>[
      'err_connection_reset',
      'err_connection_closed',
      'err_connection_aborted',
      'err_connection_refused',
      'err_connection_timed_out',
      'err_timed_out',
      'err_name_not_resolved',
      'err_address_unreachable',
      'err_internet_disconnected',
      'err_network_changed',
      'err_proxy_connection_failed',
      'connection reset',
      'connection closed',
      'connection aborted',
      'connection refused',
      'connection timed out',
      'network is unreachable',
      'software caused connection abort',
      'failed to connect',
    ];
    return networkErrorKeywords.any(normalized.contains);
  }

  Future<void> _syncSessionCookiesToCurrentHost() async {
    await _session.ensureInitialized();
    if (_session.cookies.isEmpty) {
      return;
    }
    for (final MapEntry<String, String> cookie in _session.cookies.entries) {
      await _cookieManager.setCookie(
        WebViewCookie(
          name: cookie.key,
          value: cookie.value,
          domain: _hostManager.currentHost,
          path: '/',
        ),
      );
    }
  }

  String _readerChapterIdForPage(ReaderPageData page) {
    final Uri uri = Uri.parse(page.uri);
    final List<String> segments = uri.pathSegments;
    final int chapterIndex = segments.indexOf('chapter');
    if (chapterIndex < 0 || chapterIndex + 1 >= segments.length) {
      return '';
    }
    return segments[chapterIndex + 1].trim();
  }

  bool _shouldShowReaderCommentTailPage(ReaderPageData page) {
    return _readerPreferences.showChapterComments &&
        _readerChapterIdForPage(page).isNotEmpty;
  }

  void _handleReaderCommentScroll() {
    if (!_readerCommentScrollController.hasClients ||
        _isReaderCommentsLoading ||
        _isReaderCommentsLoadingMore) {
      return;
    }
    final EasyCopyPage? currentPage = _page;
    if (currentPage is! ReaderPageData ||
        !_shouldShowReaderCommentTailPage(currentPage)) {
      return;
    }
    final ScrollPosition position = _readerCommentScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    if (position.maxScrollExtent - position.pixels > 180) {
      return;
    }
    unawaited(_loadReaderComments(currentPage, append: true));
  }

  int _readerPagedPageCount(ReaderPageData page) {
    return page.imageUrls.length +
        (_shouldShowReaderCommentTailPage(page) ? 1 : 0);
  }

  void _prepareReaderComments(
    ReaderPageData page, {
    required bool resetForNewChapter,
  }) {
    final String chapterId = _readerChapterIdForPage(page);
    if (!_readerPreferences.showChapterComments || chapterId.isEmpty) {
      if (mounted) {
        _setStateIfMounted(() {
          _readerCommentsChapterId = '';
          _readerCommentsError = '';
          _readerChapterComments = const <ChapterComment>[];
          _readerCommentsTotal = 0;
          _isReaderCommentsLoading = false;
          _isReaderCommentsLoadingMore = false;
          if (resetForNewChapter) {
            _readerCommentController.clear();
          }
        });
      } else {
        _readerCommentsChapterId = '';
        _readerCommentsError = '';
        _readerChapterComments = const <ChapterComment>[];
        _readerCommentsTotal = 0;
        _isReaderCommentsLoading = false;
        _isReaderCommentsLoadingMore = false;
        if (resetForNewChapter) {
          _readerCommentController.clear();
        }
      }
      return;
    }

    final bool shouldRefresh =
        resetForNewChapter ||
        _readerCommentsChapterId != chapterId ||
        (_readerChapterComments.isEmpty && _readerCommentsError.isEmpty);
    if (!shouldRefresh ||
        (_isReaderCommentsLoading && _readerCommentsChapterId == chapterId)) {
      return;
    }
    if (resetForNewChapter) {
      _readerCommentController.clear();
      if (_readerCommentScrollController.hasClients) {
        _readerCommentScrollController.jumpTo(0);
      }
    }
    unawaited(_loadReaderComments(page));
  }

  Future<void> _loadReaderComments(
    ReaderPageData page, {
    bool append = false,
  }) async {
    final String chapterId = _readerChapterIdForPage(page);
    if (chapterId.isEmpty || !_readerPreferences.showChapterComments) {
      return;
    }
    if (mounted) {
      final EasyCopyPage? currentPage = _page;
      if (currentPage is! ReaderPageData ||
          _readerChapterIdForPage(currentPage) != chapterId) {
        return;
      }
    }

    final List<ChapterComment> existingComments =
        append && _readerCommentsChapterId == chapterId
        ? _readerChapterComments
        : const <ChapterComment>[];
    final int offset = append ? existingComments.length : 0;
    if (append) {
      if (_isReaderCommentsLoading || _isReaderCommentsLoadingMore) {
        return;
      }
      if (_readerCommentsTotal > 0 && offset >= _readerCommentsTotal) {
        return;
      }
    }

    if (!append && mounted) {
      _setStateIfMounted(() {
        _readerCommentsChapterId = chapterId;
        _readerCommentsError = '';
        _readerChapterComments = const <ChapterComment>[];
        _readerCommentsTotal = 0;
        _isReaderCommentsLoading = true;
        _isReaderCommentsLoadingMore = false;
      });
    } else if (!append) {
      _readerCommentsChapterId = chapterId;
      _readerCommentsError = '';
      _readerChapterComments = const <ChapterComment>[];
      _readerCommentsTotal = 0;
      _isReaderCommentsLoading = true;
      _isReaderCommentsLoadingMore = false;
    } else if (mounted) {
      _setStateIfMounted(() {
        _isReaderCommentsLoadingMore = true;
      });
    } else {
      _isReaderCommentsLoadingMore = true;
    }

    try {
      final ChapterCommentFeed feed = await _siteApiClient.loadChapterComments(
        chapterId: chapterId,
        limit: 40,
        offset: offset,
      );
      if (!mounted) {
        return;
      }
      final EasyCopyPage? currentPage = _page;
      if (currentPage is! ReaderPageData ||
          _readerChapterIdForPage(currentPage) != chapterId) {
        if (_readerCommentsChapterId == chapterId) {
          _setStateIfMounted(() {
            _isReaderCommentsLoading = false;
            _isReaderCommentsLoadingMore = false;
          });
        }
        return;
      }
      _setStateIfMounted(() {
        _readerCommentsChapterId = chapterId;
        _readerChapterComments = append
            ? _mergeReaderComments(existingComments, feed.comments)
            : feed.comments;
        _readerCommentsTotal = feed.total > 0
            ? feed.total
            : _readerChapterComments.length;
        _readerCommentsError = '';
        _isReaderCommentsLoading = false;
        _isReaderCommentsLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final EasyCopyPage? currentPage = _page;
      if (currentPage is! ReaderPageData ||
          _readerChapterIdForPage(currentPage) != chapterId) {
        if (_readerCommentsChapterId == chapterId) {
          _setStateIfMounted(() {
            _isReaderCommentsLoading = false;
            _isReaderCommentsLoadingMore = false;
          });
        }
        return;
      }
      final String message = error is SiteApiException
          ? error.message
          : '评论加载失败，请稍后重试。';
      if (append && existingComments.isNotEmpty) {
        _setStateIfMounted(() {
          _isReaderCommentsLoading = false;
          _isReaderCommentsLoadingMore = false;
        });
        return;
      }
      _setStateIfMounted(() {
        _readerCommentsChapterId = chapterId;
        _readerCommentsError = message;
        _readerChapterComments = const <ChapterComment>[];
        _readerCommentsTotal = 0;
        _isReaderCommentsLoading = false;
        _isReaderCommentsLoadingMore = false;
      });
    }
  }

  List<ChapterComment> _mergeReaderComments(
    List<ChapterComment> existing,
    List<ChapterComment> incoming,
  ) {
    final Set<String> seen = <String>{};
    final List<ChapterComment> merged = <ChapterComment>[];
    for (final ChapterComment comment in <ChapterComment>[
      ...existing,
      ...incoming,
    ]) {
      final String identity = comment.id.isNotEmpty
          ? comment.id
          : '${comment.avatarUrl}\n${comment.message}';
      if (!seen.add(identity)) {
        continue;
      }
      merged.add(comment);
    }
    return List<ChapterComment>.unmodifiable(merged);
  }

  Future<void> _submitReaderComment(ReaderPageData page) async {
    if (_isReaderCommentSubmitting) {
      return;
    }
    final String chapterId = _readerChapterIdForPage(page);
    if (chapterId.isEmpty) {
      _showSnackBar('章节评论信息缺失，请刷新后重试。');
      return;
    }
    final String content = _readerCommentController.text.trim();
    if (content.isEmpty) {
      _showSnackBar('请输入评论内容。');
      return;
    }

    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      await _openAuthFlow();
      if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
        return;
      }
    }

    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (mounted) {
      _setStateIfMounted(() {
        _isReaderCommentSubmitting = true;
      });
    } else {
      _isReaderCommentSubmitting = true;
    }

    try {
      await _siteApiClient.postChapterComment(
        chapterId: chapterId,
        content: content,
      );
      _readerCommentController.clear();
      _showSnackBar('已发送评论');
      await _loadReaderComments(page);
    } catch (error) {
      final String message = error is SiteApiException
          ? error.message
          : '评论发送失败，请稍后重试。';
      if (message.contains('登录已失效')) {
        await _logout(showFeedback: false);
      }
      if (mounted) {
        _showSnackBar(message);
      }
    } finally {
      if (mounted) {
        _setStateIfMounted(() {
          _isReaderCommentSubmitting = false;
        });
      } else {
        _isReaderCommentSubmitting = false;
      }
    }
  }

  void _persistVisiblePageState() {
    final EasyCopyPage? page = _page;
    if (page is ReaderPageData) {
      unawaited(_flushReaderProgressPersistence());
      return;
    }
    if (page == null || !_standardScrollController.hasClients) {
      return;
    }
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      _standardScrollController.offset,
    );
  }

  void _handleStandardScroll() {
    if (_suspendStandardScrollTracking ||
        !_standardScrollController.hasClients ||
        _page == null ||
        _isReaderMode) {
      return;
    }
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      _standardScrollController.offset,
    );
  }

  void _resetStandardScrollPosition() {
    final DeferredViewportTicket ticket = _standardScrollRestoreCoordinator
        .beginRequest();
    _suspendStandardScrollTracking = true;
    if (_standardScrollController.hasClients) {
      _standardScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_standardScrollRestoreCoordinator.isActive(ticket)) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (!mounted) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (!_standardScrollController.hasClients) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (_standardScrollController.offset != 0) {
        _standardScrollController.jumpTo(0);
      }
      _finishStandardScrollRestore(ticket);
    });
  }

  void _restoreStandardScrollPosition(
    double offset, {
    required int tabIndex,
    required String routeKey,
  }) {
    final DeferredViewportTicket ticket = _standardScrollRestoreCoordinator
        .beginRequest();
    _suspendStandardScrollTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpStandardToOffset(
        offset,
        tabIndex: tabIndex,
        routeKey: routeKey,
        attempts: 10,
        ticket: ticket,
      );
    });
  }

  void _jumpStandardToOffset(
    double offset, {
    required int tabIndex,
    required String routeKey,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveStandardScrollRestore(
      ticket,
      tabIndex: tabIndex,
      routeKey: routeKey,
    )) {
      _finishStandardScrollRestore(ticket);
      return;
    }
    if (!_standardScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => _jumpStandardToOffset(
            offset,
            tabIndex: tabIndex,
            routeKey: routeKey,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
        return;
      }
      _finishStandardScrollRestore(ticket);
      return;
    }

    final double maxExtent = _standardScrollController.position.maxScrollExtent;
    final double clampedOffset = offset.clamp(0, maxExtent).toDouble();
    if ((offset - clampedOffset).abs() > 1 && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _jumpStandardToOffset(
          offset,
          tabIndex: tabIndex,
          routeKey: routeKey,
          attempts: attempts - 1,
          ticket: ticket,
        ),
      );
      return;
    }

    _standardScrollController.jumpTo(clampedOffset);
    _finishStandardScrollRestore(ticket);
    _tabSessionStore.updateScroll(tabIndex, routeKey, clampedOffset);
  }

  Future<void> _scrollCurrentStandardPageToTop() async {
    if (!_standardScrollController.hasClients) {
      return;
    }
    _noteStandardViewportUserInteraction();
    await _standardScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _tabSessionStore.updateScroll(_selectedIndex, _currentEntry.routeKey, 0);
  }

  bool get _isReaderMode => _page is ReaderPageData;

  Widget _buildReaderLoadingScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  bool get _isDetailRoute {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData) {
      return true;
    }
    return _isDetailCatalogUri(_currentUri);
  }

  bool get _shouldShowSearchBar {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData ||
        page is DetailPageData ||
        _isProfileUri(_currentUri) ||
        _isTopicUri(_currentUri)) {
      return false;
    }
    return !_isDetailRoute;
  }

  bool get _isPrimaryTabContent {
    if (_isTopicListUri(_currentUri)) {
      return true;
    }
    if (_shouldShowBackButton) {
      return false;
    }
    final EasyCopyPage? page = _page;
    return page == null ||
        page is HomePageData ||
        page is DiscoverPageData ||
        page is RankPageData ||
        page is ProfilePageData;
  }

  bool get _shouldShowHeaderCard =>
      !_isPrimaryTabContent &&
      !_isDetailRoute &&
      !_isSecondaryProfileRoute &&
      !_shouldHideSecondaryDiscoverHeaderCard;

  bool get _shouldHideSecondaryDiscoverHeaderCard {
    if (!_isSecondaryDiscoverRoute) {
      return false;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/recommend') || path.startsWith('/newest');
  }

  bool get _shouldShowBackButton {
    final EasyCopyPage? page = _page;
    if (_isSecondaryDiscoverRoute) {
      return true;
    }
    if (_isSecondaryProfileRoute) {
      return true;
    }
    if (page is DetailPageData || page is UnknownPageData || _isDetailRoute) {
      return true;
    }
    if ((page is DiscoverPageData || page == null) &&
        _currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  bool _isPrimaryDiscoverUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/search');
  }

  bool _isDiscoverUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/search') ||
        path.startsWith('/topic') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest');
  }

  bool _isTopicUri(Uri uri) {
    return uri.path.toLowerCase().startsWith('/topic');
  }

  bool _isTopicListUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path == '/topic' || path == '/topic/';
  }

  bool get _isSecondaryDiscoverRoute {
    return _isDiscoverUri(_currentUri) && !_isPrimaryDiscoverUri(_currentUri);
  }

  bool get _isSecondaryProfileRoute {
    return _isProfileUri(_currentUri) &&
        AppConfig.profileSubviewForUri(_currentUri) != ProfileSubview.root;
  }

  String get _pageTitle {
    if (_isProfileUri(_currentUri)) {
      return AppConfig.profileSubviewTitle(
        AppConfig.profileSubviewForUri(_currentUri),
      );
    }
    if (_isTopicListUri(_currentUri)) {
      return '专题精选';
    }
    final EasyCopyPage? page = _page;
    if (page == null) {
      if (_isDetailRoute) {
        return '漫畫詳情';
      }
      return appDestinations[_selectedIndex].label;
    }
    return page.title;
  }

  bool _isLoginUri(Uri? uri) {
    if (uri == null) {
      return false;
    }
    return uri.path.startsWith('/web/login');
  }

  bool _isProfileUri(Uri uri) {
    return uri.path.startsWith('/person/home');
  }

  bool _isDetailCatalogUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.contains('/chapter/');
  }

  bool _isUserScopedDetailUri(Uri uri) {
    return _session.isAuthenticated && _isDetailCatalogUri(uri);
  }

  Uri get _visiblePageUriForTransition {
    final EasyCopyPage? page = _page;
    if (page == null) {
      return _currentUri;
    }
    return AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
  }

  String get _standardBodyTransitionScope =>
      standardPageTransitionScope(_page, _visiblePageUriForTransition);

  bool _isDiscoverMoreCategoryOption(LinkAction option) {
    return option.label.contains('查看全部分類') ||
        option.href.contains('/filter?point=');
  }

  List<LinkAction> _visibleDiscoverThemeOptions(List<LinkAction> options) {
    if (_isDiscoverThemeExpanded || options.length <= 16) {
      return options;
    }
    const int previewCount = 15;
    final List<LinkAction> visible = options
        .take(previewCount)
        .toList(growable: true);
    final int activeIndex = options.indexWhere(
      (LinkAction option) => option.active,
    );
    if (activeIndex >= previewCount) {
      visible.removeLast();
      visible.add(options[activeIndex]);
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final EasyCopyPage? page = _page;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: Stack(
        children: <Widget>[
          ..._buildHiddenWebViewHosts(),
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: AnimatedSwitcher(
                duration: _pageFadeTransitionDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: _buildFadeSwitchTransition,
                child: page is ReaderPageData
                    ? KeyedSubtree(
                        key: ValueKey<String>(
                          'reader-${AppConfig.routeKeyForUri(Uri.parse(page.uri))}',
                        ),
                        child: _buildReaderMode(context, page),
                      )
                    : _isReaderChapterUri(_currentUri)
                    ? KeyedSubtree(
                        key: const ValueKey<String>('reader-loading'),
                        child: _buildReaderLoadingScreen(context),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('standard-mode'),
                        child: _buildStandardMode(context),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
