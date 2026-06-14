import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
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
import 'package:reader/models/shortcut_preferences.dart';
import 'package:reader/reader/reader_screen.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/app_update_checker.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/desktop_page_extractor.dart';
import 'package:reader/services/desktop_webview_environment.dart';
import 'package:reader/services/discover_filter_selection.dart';
import 'package:reader/services/display_mode_service.dart';
import 'package:reader/services/download_queue_manager.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/frame_jank_logger.dart';
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
import 'package:reader/services/uri_keys.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:reader/webview/page_extractor_script.dart';
import 'package:reader/widgets/auth_webview_screen.dart';
import 'package:reader/widgets/comic_grid.dart';
import 'package:reader/widgets/comic_quick_preview_sheet.dart';
import 'package:reader/widgets/desktop/ambient_backdrop.dart';
import 'package:reader/widgets/desktop/desktop_dock.dart';
import 'package:reader/widgets/desktop/desktop_floating_window_controls.dart';
import 'package:reader/widgets/desktop/desktop_search_field.dart';
import 'package:reader/widgets/desktop/desktop_shortcuts.dart';
import 'package:reader/widgets/desktop/desktop_title_bar.dart';
import 'package:reader/widgets/desktop/keyboard_shortcuts_page.dart';
import 'package:reader/widgets/download_management_page.dart';
import 'package:reader/widgets/mobile_floating_nav_bar.dart';
import 'package:reader/widgets/motion.dart';
import 'package:reader/widgets/native_login_screen.dart';
import 'package:reader/widgets/page_skeleton.dart';
import 'package:reader/widgets/profile_page_view.dart';
import 'package:reader/widgets/responsive_layout.dart';
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
const Duration _backToExitConfirmWindow = Duration(seconds: 2);

Widget _buildFadeSwitchTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  );
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
  WebViewController? _controller;
  WebViewController? _downloadController;
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
    FrameJankLogger.install();
    WidgetsBinding.instance.addObserver(this);
    _preferencesController =
        widget.preferencesController ?? AppPreferencesController.instance;
    _shell.lastDownloadPrefs = _preferencesController.downloadPreferences;
    if (PlatformCapabilities.usesMobileWebView) {
      _controller = _buildController();
      _downloadController = _buildDownloadController();
    }
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
      // 上方已处理 resumed。
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

  Widget _wrapDesktopReaderShell(BuildContext context, Widget child) {
    if (!PlatformCapabilities.isDesktop) {
      return child;
    }
    final ShortcutPreferences shortcuts =
        _preferencesController.shortcutPreferences;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        shortcuts.bindingFor(ShortcutAction.exitReader).activator: () =>
            unawaited(_handleBackNavigation()),
        shortcuts.bindingFor(ShortcutAction.readerPreviousPage).activator:
            _readerStepBackward,
        shortcuts.bindingFor(ShortcutAction.readerNextPage).activator:
            _readerStepForward,
        shortcuts.bindingFor(ShortcutAction.readerScrollUp).activator:
            _readerScrollUp,
        shortcuts.bindingFor(ShortcutAction.readerScrollDown).activator:
            _readerScrollDown,
        shortcuts.bindingFor(ShortcutAction.readerPreviousChapter).activator:
            _readerPreviousChapter,
        shortcuts.bindingFor(ShortcutAction.readerNextChapter).activator:
            _readerNextChapter,
        shortcuts.bindingFor(ShortcutAction.readerToggleFullscreen).activator:
            _toggleReaderFullscreen,
      },
      child: Focus(
        focusNode: _ui.readerShortcutFocusNode,
        autofocus: true,
        skipTraversal: true,
        includeSemantics: false,
        child: child,
      ),
    );
  }

  void _readerStepForward() {
    final ReaderScreenState? state = _ui.readerScreenKey.currentState;
    if (state != null) {
      unawaited(state.controller.stepForward());
    }
  }

  void _readerStepBackward() {
    final ReaderScreenState? state = _ui.readerScreenKey.currentState;
    if (state != null) {
      unawaited(state.controller.stepBackward());
    }
  }

  void _readerScrollUp() {
    final ReaderScreenState? state = _ui.readerScreenKey.currentState;
    if (state != null) {
      unawaited(state.controller.scrollCurrentPageUp());
    }
  }

  void _readerScrollDown() {
    final ReaderScreenState? state = _ui.readerScreenKey.currentState;
    if (state != null) {
      unawaited(state.controller.scrollCurrentPageDown());
    }
  }

  void _readerNextChapter() =>
      _ui.readerScreenKey.currentState?.goToNextChapter();

  void _readerPreviousChapter() =>
      _ui.readerScreenKey.currentState?.goToPreviousChapter();

  void _toggleReaderFullscreen() {
    unawaited(
      _preferencesController.updateReaderPreferences(
        (ReaderPreferences current) =>
            current.copyWith(fullscreen: !current.fullscreen),
      ),
    );
  }

  void _syncDesktopReaderShortcutFocus(bool isReaderRoute) {
    if (!PlatformCapabilities.isDesktop) {
      return;
    }
    if (!isReaderRoute) {
      _shell.readerShortcutFocusRouteKey = null;
      return;
    }
    final String routeKey = _currentEntry.routeKey;
    if (_shell.readerShortcutFocusRouteKey == routeKey) {
      return;
    }
    _shell.readerShortcutFocusRouteKey = routeKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final SitePage? page = _page;
      final bool stillReaderRoute =
          page is ReaderPageData || _isReaderChapterUri(_currentUri);
      if (stillReaderRoute && _ui.readerShortcutFocusNode.canRequestFocus) {
        _ui.readerShortcutFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final SitePage? page = _page;
    final bool isReaderRoute =
        page is ReaderPageData || _isReaderChapterUri(_currentUri);
    _syncDesktopReaderShortcutFocus(isReaderRoute);
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
                        child: _wrapDesktopReaderShell(
                          context,
                          ReaderScreen(
                            key: _ui.readerScreenKey,
                            page: page,
                            isExitTransitionActive:
                                _shell.isReaderExitTransitionActive,
                            openAtEnd:
                                _shell.pendingReaderOpenAtEndKey.isNotEmpty &&
                                _chapterKeys.pathKey(page.uri) ==
                                    _shell.pendingReaderOpenAtEndKey,
                            onOpenAtEndConsumed: () =>
                                _shell.pendingReaderOpenAtEndKey = '',
                            onRequestChapterNavigation:
                                (
                                  String href, {
                                  String prevHref = '',
                                  String nextHref = '',
                                  String catalogHref = '',
                                  bool openAtEnd = false,
                                }) async {
                                  _shell.pendingReaderOpenAtEndKey = openAtEnd
                                      ? _chapterKeys.pathKey(
                                          AppConfig.resolveNavigationUri(
                                            href,
                                            currentUri: _currentUri,
                                          ).toString(),
                                        )
                                      : '';
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
                            onResolveHistoryCover:
                                _resolveHistoryCoverForCatalog,
                          ),
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
          if (PlatformCapabilities.isDesktop && isReaderRoute)
            const Positioned(
              top: 0,
              right: 0,
              child: DesktopFloatingWindowControls(),
            ),
        ],
      ),
    );
  }
}
