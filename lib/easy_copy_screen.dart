import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/easy_copy_screen/download_enqueue_result.dart';
import 'package:easy_copy/easy_copy_screen/models.dart';
import 'package:easy_copy/easy_copy_screen/widgets.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/reader/reader_screen.dart';
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
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/local_library_store.dart';
import 'package:easy_copy/services/local_profile_page_loader.dart';
import 'package:easy_copy/services/navigation_request_guard.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/rank_filter_selection.dart';
import 'package:easy_copy/services/primary_tab_session_store.dart';
import 'package:easy_copy/services/reader_navigation_repairer.dart';
import 'package:easy_copy/services/reader_page_download_resolver.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/network_diagnostics.dart';
import 'package:easy_copy/services/search_history_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_html_page_loader.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/services/standard_page_load_controller.dart';
import 'package:easy_copy/services/tab_activation_policy.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:easy_copy/widgets/download_management_page.dart';
import 'package:easy_copy/widgets/native_login_screen.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:easy_copy/widgets/top_notice.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'easy_copy_screen/bootstrap_actions.dart';
part 'easy_copy_screen/navigation.dart';
part 'easy_copy_screen/page_load_actions.dart';
part 'easy_copy_screen/route_classifiers.dart';
part 'easy_copy_screen/tab_navigation.dart';
part 'easy_copy_screen/reader_navigation.dart';
part 'easy_copy_screen/scroll_restore.dart';
part 'easy_copy_screen/detail_chapter_state.dart';
part 'easy_copy_screen/search_actions.dart';
part 'easy_copy_screen/host_actions.dart';
part 'easy_copy_screen/download_actions.dart';
part 'easy_copy_screen/webview_pipeline.dart';
part 'easy_copy_screen/standard_mode.dart';

const Duration _pageFadeTransitionDuration = Duration(milliseconds: 320);
const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const String _detailAllChapterTabKey = '__detail_all__';

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
  late final WebViewController _controller;
  late final WebViewController _downloadController;
  late final AppPreferencesController _preferencesController;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _standardScrollController = ScrollController();
  final HostManager _hostManager = HostManager.instance;
  final SiteSession _session = SiteSession.instance;
  final SiteApiClient _siteApiClient = SiteApiClient.instance;
  final ReaderProgressStore _readerProgressStore = ReaderProgressStore.instance;
  final LocalLibraryStore _localLibraryStore = LocalLibraryStore.instance;
  final LocalProfilePageLoader _localProfilePageLoader =
      LocalProfilePageLoader.instance;
  final SearchHistoryStore _searchHistoryStore = SearchHistoryStore.instance;
  final ComicDownloadService _downloadService = ComicDownloadService.instance;
  final DownloadStorageService _downloadStorageService =
      DownloadStorageService.instance;
  final DownloadQueueStore _downloadQueueStore = DownloadQueueStore.instance;
  late final DownloadQueueManager _downloadQueueManager;
  final GlobalKey<ReaderScreenState> _readerScreenKey =
      GlobalKey<ReaderScreenState>();
  final PrimaryTabSessionStore _tabSessionStore = PrimaryTabSessionStore(
    rootUris: <int, Uri>{
      for (int index = 0; index < appDestinations.length; index += 1)
        index: appDestinations[index].uri,
    },
  );
  late final PageRepository _pageRepository;

  int _selectedIndex = 0;
  int _activeLoadId = 0;
  int _nextNavigationRequestId = 0;
  bool _isFailingOver = false;
  int _consecutiveFrameFailures = 0;
  final ValueNotifier<bool> _discoverFilterExpandedNotifier =
      ValueNotifier<bool>(false);
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
  List<String> _searchHistoryEntries = const <String>[];
  bool _isUpdatingHostSettings = false;
  bool _isCheckingForUpdates = false;
  bool _isUpdatingCollection = false;
  bool _isReaderExitTransitionActive = false;
  bool _suspendStandardScrollTracking = false;
  String _selectedDetailChapterTabKey = _detailAllChapterTabKey;
  bool _isDetailChapterSortAscending = false;
  String _detailChapterStateRouteKey = '';
  int _discardedNavigationCommitCount = 0;
  int _discardedNavigationCallbackCount = 0;
  int _supersededNavigationRequestCount = 0;
  DownloadPreferences? _lastObservedDownloadPreferences;
  final Map<String, GlobalKey> _detailChapterItemKeys = <String, GlobalKey>{};
  final Set<String> _readerNavigationRepairRouteKeys = <String>{};
  final DeferredViewportCoordinator _standardScrollRestoreCoordinator =
      DeferredViewportCoordinator();
  final DeferredViewportCoordinator _detailChapterAutoScrollCoordinator =
      DeferredViewportCoordinator();
  String _handledDetailAutoScrollSignature = '';
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
    _lastObservedDownloadPreferences =
        _preferencesController.downloadPreferences;
    _controller = _buildController();
    _downloadController = _buildDownloadController();
    _pageRepository = PageRepository(
      standardPageLoader: _loadStandardPageFresh,
      htmlPageLoader: SiteHtmlPageLoader.instance.loadPage,
      profilePageLoader: _localProfilePageLoader.loadProfile,
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
    _searchController.addListener(_handleSearchTextChanged);
    _standardScrollController.addListener(_handleStandardScroll);
    unawaited(_loadAppVersionInfo());
    unawaited(DisplayModeService.requestHighRefreshRate());
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferencesController.removeListener(_handlePreferencesChanged);
    _searchController.removeListener(_handleSearchTextChanged);
    _standardScrollController.removeListener(_handleStandardScroll);
    _searchController.dispose();
    _standardScrollController.dispose();
    _downloadQueueManager.dispose();
    _discoverFilterExpandedNotifier.dispose();
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
        unawaited(
          _readerScreenKey.currentState?.controller
                  .flushProgressPersistence() ??
              Future<void>.value(),
        );
        return;
      case AppLifecycleState.resumed:
        return;
    }
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
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: _buildFadeSwitchTransition,
                child: page is ReaderPageData
                    ? KeyedSubtree(
                        key: const ValueKey<String>('reader'),
                        child: ReaderScreen(
                          key: _readerScreenKey,
                          page: page,
                          isExitTransitionActive: _isReaderExitTransitionActive,
                          onRequestChapterNavigation:
                              (
                                String href, {
                                String prevHref = '',
                                String nextHref = '',
                                String catalogHref = '',
                              }) async {
                                await _openHref(
                                  href,
                                  prevHref: prevHref,
                                  nextHref: nextHref,
                                  catalogHref: catalogHref,
                                  sourceTabIndex: _selectedIndex,
                                );
                              },
                          onRequestAuth: _openAuthFlow,
                          onLogoutForExpiredSession: () =>
                              _logout(showFeedback: false),
                          onResolveHistoryCover: _resolveHistoryCoverForCatalog,
                        ),
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
