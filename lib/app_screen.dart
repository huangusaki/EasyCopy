import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader/app_screen/dependencies.dart';
import 'package:reader/app_screen/detail_chapter_controller.dart';
import 'package:reader/app_screen/detail_download_picker.dart';
import 'package:reader/app_screen/download_enqueue_result.dart';
import 'package:reader/app_screen/models.dart';
import 'package:reader/app_screen/route_state.dart';
import 'package:reader/app_screen/route_utils.dart';
import 'package:reader/app_screen/scroll_state.dart';
import 'package:reader/app_screen/search_actions.dart';
import 'package:reader/app_screen/state_containers.dart';
import 'package:reader/app_screen/wallpaper_actions.dart';
import 'package:reader/app_screen/widgets.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/reader_screen.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/app_update_checker.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/discover_filter_selection.dart';
import 'package:reader/services/display_mode_service.dart';
import 'package:reader/services/download_queue_manager.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/network_diagnostics.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/page_repository.dart';
import 'package:reader/services/primary_tab_session_store.dart';
import 'package:reader/services/rank_filter_selection.dart';
import 'package:reader/services/reader_navigation_repairer.dart';
import 'package:reader/services/reader_page_download_resolver.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_html_page_loader.dart';
import 'package:reader/services/standard_page_load_controller.dart';
import 'package:reader/services/tab_activation_policy.dart';
import 'package:reader/webview/page_extractor_script.dart';
import 'package:reader/widgets/auth_webview_screen.dart';
import 'package:reader/widgets/comic_grid.dart';
import 'package:reader/widgets/download_management_page.dart';
import 'package:reader/widgets/native_login_screen.dart';
import 'package:reader/widgets/profile_page_view.dart';
import 'package:reader/widgets/settings_ui.dart';
import 'package:reader/widgets/top_notice.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'app_screen/bootstrap_actions.dart';
part 'app_screen/download_actions.dart';
part 'app_screen/host_actions.dart';
part 'app_screen/navigation.dart';
part 'app_screen/page_load_actions.dart';
part 'app_screen/reader_navigation.dart';
part 'app_screen/standard_discover_chrome.dart';
part 'app_screen/standard_mode.dart';
part 'app_screen/standard_page_sections.dart';
part 'app_screen/standard_profile.dart';
part 'app_screen/tab_navigation.dart';
part 'app_screen/webview_pipeline.dart';

const Duration _pageFadeTransitionDuration = Duration(milliseconds: 320);
const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const Duration _standardBodyFadeInDuration = Duration(milliseconds: 220);

Widget _buildFadeSwitchTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  );
}

/// Triggers a brief fade-in (with a subtle slide-up) every time [contentKey]
/// changes. Unlike [AnimatedSwitcher], it keeps a single subtree mounted at all
/// times, so descendants that own shared resources (like [ScrollController]s)
/// never collide with a transitioning twin.
class _TabContentFadeIn extends StatefulWidget {
  const _TabContentFadeIn({required this.contentKey, required this.child});

  final String contentKey;
  final Widget child;

  @override
  State<_TabContentFadeIn> createState() => _TabContentFadeInState();
}

class _TabContentFadeInState extends State<_TabContentFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _standardBodyFadeInDuration,
      value: 1,
    );
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.012),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void didUpdateWidget(covariant _TabContentFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _AppScreenDownloadTaskRunner implements DownloadTaskRunner {
  const _AppScreenDownloadTaskRunner(this._state);

  final _AppScreenState _state;

  @override
  Future<ReaderPageData> prepare(DownloadQueueTask task) async {
    await _state._services.session.ensureInitialized();
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
    return _state._services.downloadService.downloadChapter(
      page,
      cookieHeader: _state._services.session.cookieHeader,
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

class AppScreen extends StatefulWidget {
  const AppScreen({super.key, this.preferencesController});

  final AppPreferencesController? preferencesController;

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final WebViewController _downloadController;
  late final AppPreferencesController _preferencesController;
  final AppScreenServices _services = AppScreenServices();
  final AppScreenUiState _ui = AppScreenUiState();
  final AppNavigationState _nav = AppNavigationState();
  final AppWebViewState _web = AppWebViewState();
  final AppLibraryState _library = AppLibraryState();
  final AppShellState _shell = AppShellState();
  late final DownloadQueueManager _downloadQueueManager;
  late final AppSearchActions _searchActions;
  late final AppScrollState _scrollState;
  late final DetailChapterController _detailChapters;
  late final ChapterPathResolver _chapterKeys;
  final PrimaryTabSessionStore _tabSessionStore = PrimaryTabSessionStore(
    rootUris: <int, Uri>{
      for (int index = 0; index < appDestinations.length; index += 1)
        index: appDestinations[index].uri,
    },
  );
  late final PageRepository _pageRepository;
  final StandardPageLoadController<SitePage> _standardPageLoadController =
      StandardPageLoadController<SitePage>();

  ValueListenable<DownloadQueueSnapshot> get _downloadQueueSnapshotNotifier =>
      _downloadQueueManager.snapshotNotifier;

  ValueListenable<DownloadStorageState> get _downloadStorageStateNotifier =>
      _downloadQueueManager.storageStateNotifier;

  ValueListenable<bool> get _downloadStorageBusyNotifier =>
      _downloadQueueManager.storageBusyNotifier;

  ValueListenable<StorageMigrationProgress?> get _storageMigrationProgress =>
      _downloadQueueManager.migrationProgressNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preferencesController =
        widget.preferencesController ?? AppPreferencesController.instance;
    _shell.lastDownloadPrefs = _preferencesController.downloadPreferences;
    _controller = _buildController();
    _downloadController = _buildDownloadController();
    _chapterKeys = ChapterPathResolver(_services.readerProgressStore);
    _searchActions = AppSearchActions(
      historyStore: _services.searchHistoryStore,
      currentUri: () => _currentUri,
      selectedIndex: () => _nav.selectedIndex,
      isMounted: () => mounted,
      updateUi: _setStateIfMounted,
      showNotice: _showNotice,
      loadUri:
          (
            Uri uri, {
            int? sourceTabIndex,
            int? targetTabIndexOverride,
            required NavigationIntent historyMode,
          }) {
            return _loadUri(
              uri,
              sourceTabIndex: sourceTabIndex,
              targetTabIndexOverride: targetTabIndexOverride,
              historyMode: historyMode,
            );
          },
    );
    _scrollState = AppScrollState(
      standardScrollController: _ui.standardScrollController,
      readerScreenKey: _ui.readerScreenKey,
      tabSessionStore: _tabSessionStore,
      isMounted: () => mounted,
      selectedIndex: () => _nav.selectedIndex,
      currentEntry: () => _currentEntry,
      page: () => _page,
      isReaderMode: () => _isReaderMode,
    );
    _detailChapters = DetailChapterController(
      isActiveRoute: (String routeKey) {
        return mounted &&
            _page is DetailPageData &&
            _currentEntry.routeKey == routeKey;
      },
      chapterPathKey: _chapterKeys.pathKey,
      lastReadChapterKey: _chapterKeys.lastReadKey,
      onViewportInteraction: _noteViewportInteraction,
      onChanged: _setStateIfMounted,
    );
    _pageRepository = PageRepository(
      standardPageLoader: _loadStandardPageFresh,
      htmlPageLoader: SiteHtmlPageLoader.instance.loadPage,
      profilePageLoader: _services.localProfilePageLoader.loadProfile,
    );
    _downloadQueueManager = DownloadQueueManager(
      preferencesController: _preferencesController,
      downloadService: _services.downloadService,
      queueStore: _services.downloadQueueStore,
      taskRunner: _AppScreenDownloadTaskRunner(this),
      onLibraryChanged: (CacheLibraryRefreshReason reason) {
        return _refreshCachedComics(reason: reason);
      },
      onNotice: _handleDownloadQueueNotice,
    );
    _preferencesController.addListener(_handlePreferencesChanged);
    _searchActions.attach();
    _ui.standardScrollController.addListener(_scrollState.handleStandardScroll);
    unawaited(_loadAppVersionInfo());
    unawaited(DisplayModeService.requestHighRefreshRate());
    unawaited(_bootstrap());
    _searchActions.syncFromCurrentUri();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferencesController.removeListener(_handlePreferencesChanged);
    _ui.standardScrollController.removeListener(
      _scrollState.handleStandardScroll,
    );
    _searchActions.dispose();
    _ui.dispose();
    _downloadQueueManager.dispose();
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
          _ui.readerScreenKey.currentState?.controller
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
        _searchActions.syncFromCurrentUri();
      }
      return;
    }
    setState(mutation);
    if (syncSearch) {
      _searchActions.syncFromCurrentUri();
    }
  }

  void _setStateIfMounted([VoidCallback? mutation]) {
    if (!mounted) {
      return;
    }
    setState(mutation ?? () {});
  }

  AppRouteState get _routes => AppRouteState(
    page: _page,
    currentUri: _currentUri,
    selectedIndex: _nav.selectedIndex,
    isAuthenticated: _services.session.isAuthenticated,
    discoverFilterExpanded: _ui.discoverFilterExpandedNotifier.value,
  );

  void _noteViewportInteraction() {
    _scrollState.noteViewportInteraction();
    _detailChapters.noteViewportInteraction();
  }

  @override
  Widget build(BuildContext context) {
    final SitePage? page = _page;
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
                          key: _ui.readerScreenKey,
                          page: page,
                          isExitTransitionActive:
                              _shell.isReaderExitTransitionActive,
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
                                  sourceTabIndex: _nav.selectedIndex,
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
