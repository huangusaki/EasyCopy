import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/page_transition_scope.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/primary_tab_session_store.dart';
import 'package:easy_copy/services/reader_platform_bridge.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/services/standard_page_load_controller.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:easy_copy/widgets/native_login_screen.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const Duration _pageFadeTransitionDuration = Duration(milliseconds: 200);

Widget _buildFadeSwitchTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  );
}

class EasyCopyScreen extends StatefulWidget {
  const EasyCopyScreen({super.key, this.preferencesController});

  final AppPreferencesController? preferencesController;

  @override
  State<EasyCopyScreen> createState() => _EasyCopyScreenState();
}

class _EasyCopyScreenState extends State<EasyCopyScreen> {
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
  final ScrollController _standardScrollController = ScrollController();
  final ScrollController _readerScrollController = ScrollController();
  final GlobalKey _readerViewportKey = GlobalKey();
  final ReaderPlatformBridge _readerPlatformBridge =
      ReaderPlatformBridge.instance;
  final HostManager _hostManager = HostManager.instance;
  final SiteSession _session = SiteSession.instance;
  final ReaderProgressStore _readerProgressStore = ReaderProgressStore.instance;
  final ComicDownloadService _downloadService = ComicDownloadService.instance;
  final DownloadQueueStore _downloadQueueStore = DownloadQueueStore.instance;
  final PrimaryTabSessionStore _tabSessionStore = PrimaryTabSessionStore(
    rootUris: <int, Uri>{
      for (int index = 0; index < appDestinations.length; index += 1)
        index: appDestinations[index].uri,
    },
  );
  final ValueNotifier<DownloadQueueSnapshot> _downloadQueueSnapshotNotifier =
      ValueNotifier<DownloadQueueSnapshot>(const DownloadQueueSnapshot());
  late final PageRepository _pageRepository;
  late PageController _readerPageController;

  int _selectedIndex = 0;
  int _activeLoadId = 0;
  bool _isFailingOver = false;
  int _consecutiveFrameFailures = 0;
  bool _isDiscoverThemeExpanded = false;
  List<CachedComicLibraryEntry> _cachedComics =
      const <CachedComicLibraryEntry>[];
  bool _isLoadingCachedComics = true;
  int _downloadActiveLoadId = 0;
  Completer<ReaderPageData>? _downloadExtractionCompleter;
  Timer? _readerProgressDebounce;
  Timer? _readerAutoTurnTimer;
  Timer? _readerClockTimer;
  ReaderPosition? _lastPersistedReaderPosition;
  bool _isProcessingDownloadQueue = false;
  bool _isUpdatingHostSettings = false;
  bool _isReaderSettingsOpen = false;
  bool _isReaderChapterControlsVisible = false;
  bool _readerPresentationSyncScheduled = false;
  bool _suspendStandardScrollTracking = false;
  int _currentReaderPageIndex = 0;
  int _currentVisibleReaderImageIndex = 0;
  int? _batteryLevel;
  _AppliedReaderEnvironment? _appliedReaderEnvironment;
  ReaderPreferences? _lastObservedReaderPreferences;
  final Set<String> _cancelledComicKeys = <String>{};
  final Map<String, String> _cancelledComicTitles = <String, String>{};
  final Map<int, ScrollController> _readerPageScrollControllers =
      <int, ScrollController>{};
  final Map<int, GlobalKey> _readerImageItemKeys = <int, GlobalKey>{};
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<ReaderVolumeKeyAction>? _volumeKeySubscription;
  final StandardPageLoadController<EasyCopyPage> _standardPageLoadController =
      StandardPageLoadController<EasyCopyPage>();
  NavigationIntent? _nextFreshNavigationIntent;
  bool? _nextFreshPreserveCurrentPage;

  @override
  void initState() {
    super.initState();
    _preferencesController =
        widget.preferencesController ?? AppPreferencesController.instance;
    _readerPageController = PageController();
    _lastObservedReaderPreferences = _preferencesController.readerPreferences;
    _controller = _buildController();
    _downloadController = _buildDownloadController();
    _pageRepository = PageRepository(
      standardPageLoader: _loadStandardPageFresh,
    );
    _preferencesController.addListener(_handlePreferencesChanged);
    _standardScrollController.addListener(_handleStandardScroll);
    _readerScrollController.addListener(_handleReaderScroll);
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
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    _persistCurrentReaderProgress();
    _readerProgressDebounce?.cancel();
    _readerAutoTurnTimer?.cancel();
    _readerClockTimer?.cancel();
    _batterySubscription?.cancel();
    _volumeKeySubscription?.cancel();
    _preferencesController.removeListener(_handlePreferencesChanged);
    _standardScrollController.removeListener(_handleStandardScroll);
    _readerScrollController.removeListener(_handleReaderScroll);
    _disposeReaderPagedScrollControllers();
    _readerPageController.dispose();
    _searchController.dispose();
    _standardScrollController.dispose();
    _readerScrollController.dispose();
    _downloadQueueSnapshotNotifier.dispose();
    unawaited(_restoreDefaultReaderEnvironment());
    super.dispose();
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
    if (_isProfileUri(uri)) {
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

  void _handlePreferencesChanged() {
    final ReaderPreferences previousPreferences =
        _lastObservedReaderPreferences ?? _readerPreferences;
    final ReaderPreferences nextPreferences = _readerPreferences;
    _lastObservedReaderPreferences = nextPreferences;

    if (!mounted) {
      return;
    }

    setState(() {});

    final bool requiresReaderRestore =
        previousPreferences.readingDirection !=
            nextPreferences.readingDirection ||
        previousPreferences.pageFit != nextPreferences.pageFit ||
        previousPreferences.openingPosition != nextPreferences.openingPosition;
    final EasyCopyPage? page = _page;
    if (requiresReaderRestore && page is ReaderPageData) {
      _handleReaderPageLoaded(page, previousUri: page.uri, forceRestore: true);
      return;
    }
    _scheduleReaderPresentationSync();
  }

  void _handleReaderVolumeKeyAction(ReaderVolumeKeyAction action) {
    if (!_isReaderMode || !_readerPreferences.useVolumeKeysForPaging) {
      return;
    }
    switch (action) {
      case ReaderVolumeKeyAction.previous:
        unawaited(_stepReaderBackward());
      case ReaderVolumeKeyAction.next:
        unawaited(_stepReaderForward());
    }
  }

  Future<void> _stepReaderForward() async {
    if (_readerPreferences.isPaged) {
      final EasyCopyPage? page = _page;
      if (page is! ReaderPageData) {
        return;
      }
      final int nextPageIndex = _currentReaderPageIndex + 1;
      if (nextPageIndex >= page.imageUrls.length) {
        return;
      }
      await _animateToReaderPage(nextPageIndex);
      return;
    }
    if (!_readerScrollController.hasClients) {
      return;
    }
    final double viewportExtent =
        _readerScrollController.position.viewportDimension;
    final double maxExtent = _readerScrollController.position.maxScrollExtent;
    final double nextOffset = (_readerScrollController.offset + viewportExtent)
        .clamp(0, maxExtent)
        .toDouble();
    if ((nextOffset - _readerScrollController.offset).abs() < 1) {
      return;
    }
    await _readerScrollController.animateTo(
      nextOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartReaderAutoTurn();
  }

  Future<void> _stepReaderBackward() async {
    if (_readerPreferences.isPaged) {
      final int previousPageIndex = _currentReaderPageIndex - 1;
      if (previousPageIndex < 0) {
        return;
      }
      await _animateToReaderPage(previousPageIndex);
      return;
    }
    if (!_readerScrollController.hasClients) {
      return;
    }
    final double viewportExtent =
        _readerScrollController.position.viewportDimension;
    final double previousOffset =
        (_readerScrollController.offset - viewportExtent)
            .clamp(0, _readerScrollController.position.maxScrollExtent)
            .toDouble();
    if ((previousOffset - _readerScrollController.offset).abs() < 1) {
      return;
    }
    await _readerScrollController.animateTo(
      previousOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartReaderAutoTurn();
  }

  Future<void> _animateToReaderPage(int pageIndex) async {
    if (!_readerPageController.hasClients) {
      return;
    }
    await _readerPageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartReaderAutoTurn();
  }

  void _scheduleReaderPresentationSync() {
    if (_readerPresentationSyncScheduled) {
      return;
    }
    _readerPresentationSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerPresentationSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final EasyCopyPage? page = _page;
      unawaited(_applyReaderEnvironment(page is ReaderPageData ? page : null));
    });
  }

  Future<void> _applyReaderEnvironment(ReaderPageData? page) async {
    final _AppliedReaderEnvironment nextEnvironment = page == null
        ? const _AppliedReaderEnvironment.standard()
        : _AppliedReaderEnvironment.reader(
            orientation: _readerPreferences.screenOrientation,
            fullscreen: _readerPreferences.fullscreen,
            keepScreenOn: _readerPreferences.keepScreenOn,
            volumePagingEnabled:
                _readerPlatformBridge.isAndroidSupported &&
                _readerPreferences.useVolumeKeysForPaging,
          );
    if (_appliedReaderEnvironment != nextEnvironment) {
      if (page == null) {
        await _restoreDefaultReaderEnvironment();
      } else {
        await SystemChrome.setPreferredOrientations(
          nextEnvironment.orientation == ReaderScreenOrientation.landscape
              ? const <DeviceOrientation>[
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]
              : const <DeviceOrientation>[DeviceOrientation.portraitUp],
        );
        await SystemChrome.setEnabledSystemUIMode(
          nextEnvironment.fullscreen
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge,
        );
        await _readerPlatformBridge.setKeepScreenOn(
          nextEnvironment.keepScreenOn,
        );
        await _readerPlatformBridge.setVolumePagingEnabled(
          nextEnvironment.volumePagingEnabled,
        );
        _appliedReaderEnvironment = nextEnvironment;
      }
    }

    _syncReaderClockTicker(
      enabled: page != null && _readerPreferences.showClock,
    );
    if (page == null) {
      _readerAutoTurnTimer?.cancel();
      _readerAutoTurnTimer = null;
      return;
    }
    _restartReaderAutoTurn();
  }

  Future<void> _restoreDefaultReaderEnvironment() async {
    await SystemChrome.setPreferredOrientations(_defaultOrientations);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _readerPlatformBridge.setKeepScreenOn(false);
    await _readerPlatformBridge.setVolumePagingEnabled(false);
    _appliedReaderEnvironment = const _AppliedReaderEnvironment.standard();
  }

  void _syncReaderClockTicker({required bool enabled}) {
    if (!enabled) {
      _readerClockTimer?.cancel();
      _readerClockTimer = null;
      return;
    }
    if (_readerClockTimer != null) {
      return;
    }
    _readerClockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _restartReaderAutoTurn() {
    _readerAutoTurnTimer?.cancel();
    final EasyCopyPage? page = _page;
    if (page is! ReaderPageData ||
        _readerPreferences.autoPageTurnSeconds <= 0 ||
        _isReaderSettingsOpen) {
      return;
    }
    _readerAutoTurnTimer = Timer(
      Duration(seconds: _readerPreferences.autoPageTurnSeconds),
      () async {
        if (!mounted || _page is! ReaderPageData) {
          return;
        }
        if (_readerPreferences.isPaged) {
          final int nextPageIndex = _currentReaderPageIndex + 1;
          if (nextPageIndex >= page.imageUrls.length) {
            return;
          }
          await _animateToReaderPage(nextPageIndex);
          return;
        }
        if (!_readerScrollController.hasClients) {
          return;
        }
        final double maxExtent =
            _readerScrollController.position.maxScrollExtent;
        final double viewportExtent =
            _readerScrollController.position.viewportDimension;
        final double nextOffset =
            (_readerScrollController.offset + viewportExtent)
                .clamp(0, maxExtent)
                .toDouble();
        if ((nextOffset - _readerScrollController.offset).abs() < 1) {
          return;
        }
        await _readerScrollController.animateTo(
          nextOffset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        _restartReaderAutoTurn();
      },
    );
  }

  void _disposeReaderPagedScrollControllers() {
    final List<ScrollController> controllers = _readerPageScrollControllers
        .values
        .toList(growable: false);
    _readerPageScrollControllers.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ScrollController controller in controllers) {
        controller.dispose();
      }
    });
  }

  void _replaceReaderPageController({required int initialPage}) {
    final PageController previousController = _readerPageController;
    _readerPageController = PageController(initialPage: initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  GlobalKey _readerImageItemKeyFor(int index) {
    return _readerImageItemKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _scheduleVisibleReaderImageIndexUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _readerPreferences.isPaged) {
        return;
      }
      _updateVisibleReaderImageIndex();
    });
  }

  void _updateVisibleReaderImageIndex() {
    if (!_readerScrollController.hasClients) {
      return;
    }
    final BuildContext? viewportContext = _readerViewportKey.currentContext;
    if (viewportContext == null) {
      return;
    }
    final RenderObject? viewportRenderObject = viewportContext
        .findRenderObject();
    if (viewportRenderObject is! RenderBox) {
      return;
    }
    final double viewportTop = viewportRenderObject
        .localToGlobal(Offset.zero)
        .dy;
    final double viewportCenter =
        viewportTop + (viewportRenderObject.size.height / 2);
    int bestIndex = _currentVisibleReaderImageIndex;
    double bestDistance = double.infinity;
    for (final MapEntry<int, GlobalKey> entry in _readerImageItemKeys.entries) {
      final BuildContext? itemContext = entry.value.currentContext;
      if (itemContext == null) {
        continue;
      }
      final RenderObject? renderObject = itemContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final Offset topLeft = renderObject.localToGlobal(Offset.zero);
      final double centerY = topLeft.dy + (renderObject.size.height / 2);
      final double distance = (centerY - viewportCenter).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = entry.key;
      }
    }
    if (bestIndex == _currentVisibleReaderImageIndex) {
      return;
    }
    setState(() {
      _currentVisibleReaderImageIndex = bestIndex;
    });
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      _hostManager.ensureInitialized(),
      _session.ensureInitialized(),
      _downloadQueueStore.ensureInitialized(),
      _readerProgressStore.ensureInitialized(),
    ]);
    await _refreshCachedComics();
    await _restoreDownloadQueue();
    final Uri homeUri = appDestinations.first.uri;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIndex = tabIndexForUri(homeUri);
    });
    _syncSearchController();
    await _loadUri(homeUri, historyMode: NavigationIntent.resetToRoot);
    unawaited(_ensureDownloadQueueRunning());
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.desktopUserAgent)
      ..addJavaScriptChannel(
        'easyCopyBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri? nextUri = Uri.tryParse(request.url);
            if (_isLoginUri(nextUri)) {
              unawaited(_openAuthFlow());
              return NavigationDecision.prevent;
            }
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              _showSnackBar('已阻止跳转到站外页面');
              return NavigationDecision.prevent;
            }

            final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(
              nextUri ?? _currentUri,
            );
            if (_shouldAcceptPendingNavigationUri(
              rewrittenUri,
              source: StandardPageLoadEventSource.navigationRequest,
            )) {
              _setPendingLocation(rewrittenUri);
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            final Uri startedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(url) ?? _currentUri,
            );
            if (!_shouldAcceptPendingNavigationUri(
              startedUri,
              source: StandardPageLoadEventSource.pageStarted,
            )) {
              return;
            }
            _startLoading(
              startedUri,
              preserveCurrentPage:
                  _pendingPageLoad?.preserveCurrentPage ?? false,
            );
          },
          onPageFinished: (String url) async {
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
                _pendingPageLoad;
            if (pendingLoad == null || pendingLoad.completer.isCompleted) {
              return;
            }
            final Uri finishedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(url) ?? _currentUri,
            );
            if (!pendingLoad.accepts(
              finishedUri,
              source: StandardPageLoadEventSource.pageFinished,
            )) {
              return;
            }
            try {
              await _controller.runJavaScript(
                buildPageExtractionScript(pendingLoad.loadId),
              );
            } catch (_) {
              if (!mounted ||
                  !_standardPageLoadController.isCurrent(pendingLoad)) {
                return;
              }
              _failPendingPageLoad('頁面已加載，但轉換內容失敗。');
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url == null) {
              return;
            }
            final Uri changedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(change.url!) ?? _currentUri,
            );
            if (_shouldAcceptPendingNavigationUri(
              changedUri,
              source: StandardPageLoadEventSource.urlChange,
            )) {
              _setPendingLocation(changedUri);
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            final Uri? failingUri = error.url == null
                ? null
                : Uri.tryParse(error.url!);
            if (failingUri != null &&
                !_shouldAcceptPendingNavigationUri(
                  AppConfig.rewriteToCurrentHost(failingUri),
                  source: StandardPageLoadEventSource.mainFrameError,
                )) {
              return;
            }
            unawaited(
              _handleMainFrameFailure(
                error.description.isEmpty ? '頁面加載失敗，請稍後重試。' : error.description,
              ),
            );
          },
        ),
      );
  }

  WebViewController _buildDownloadController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.desktopUserAgent)
      ..addJavaScriptChannel(
        'easyCopyBridge',
        onMessageReceived: _handleDownloadBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri? nextUri = Uri.tryParse(request.url);
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String _) async {
            final int loadId = _downloadActiveLoadId;
            if (_downloadExtractionCompleter == null) {
              return;
            }
            try {
              await _downloadController.runJavaScript(
                buildPageExtractionScript(loadId),
              );
            } catch (error) {
              _downloadExtractionCompleter?.completeError(error);
              _downloadExtractionCompleter = null;
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _downloadExtractionCompleter?.completeError(
              error.description.isEmpty ? '章节解析失败' : error.description,
            );
            _downloadExtractionCompleter = null;
          },
        ),
      );
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null || pendingLoad.completer.isCompleted) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );

      final int loadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (loadId != pendingLoad.loadId) {
        return;
      }

      payload.remove('loadId');
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
      if (!pendingLoad.accepts(
        pageUri,
        source: StandardPageLoadEventSource.payload,
      )) {
        return;
      }
      _consecutiveFrameFailures = 0;
      _applyLoadedPage(
        page,
        targetTabIndex: pendingLoad.targetTabIndex,
        switchToTab: _selectedIndex == pendingLoad.targetTabIndex,
      );
      pendingLoad.completer.complete(page);
      _standardPageLoadController.clear(pendingLoad);
    } catch (_) {
      _failPendingPageLoad('轉換資料解析失敗。');
    }
  }

  void _handleDownloadBridgeMessage(JavaScriptMessage message) {
    final Completer<ReaderPageData>? completer = _downloadExtractionCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final int loadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (loadId != _downloadActiveLoadId) {
        return;
      }

      payload.remove('loadId');
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      if (page is ReaderPageData) {
        completer.complete(page);
      } else {
        completer.completeError('章节解析失败');
      }
    } catch (error) {
      completer.completeError(error);
    } finally {
      _downloadExtractionCompleter = null;
    }
  }

  Future<void> _refreshCachedComics() async {
    final List<CachedComicLibraryEntry> comics = await _downloadService
        .loadCachedLibrary();
    if (!mounted) {
      _cachedComics = comics;
      _isLoadingCachedComics = false;
      return;
    }
    setState(() {
      _cachedComics = comics;
      _isLoadingCachedComics = false;
    });
  }

  Future<ReaderPageData> _extractReaderPageForDownload(Uri uri) async {
    if (_downloadExtractionCompleter != null) {
      throw StateError('正在准备其他章节下载，请稍后再试。');
    }
    await _syncSessionCookiesToCurrentHost();
    final Completer<ReaderPageData> completer = Completer<ReaderPageData>();
    _downloadExtractionCompleter = completer;
    _downloadActiveLoadId += 1;
    await _downloadController.loadRequest(AppConfig.rewriteToCurrentHost(uri));
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _downloadExtractionCompleter = null;
        throw TimeoutException('章节解析超时');
      },
    );
  }

  DownloadQueueSnapshot get _downloadQueueSnapshot =>
      _downloadQueueSnapshotNotifier.value;

  Future<void> _restoreDownloadQueue() async {
    _downloadQueueSnapshotNotifier.value = await _downloadQueueStore.read();
  }

  Future<void> _persistDownloadQueueSnapshot(
    DownloadQueueSnapshot snapshot,
  ) async {
    _downloadQueueSnapshotNotifier.value = snapshot;
    if (snapshot.isEmpty) {
      await _downloadQueueStore.clear();
      return;
    }
    await _downloadQueueStore.write(snapshot);
  }

  void _setDownloadQueueSnapshotInMemory(DownloadQueueSnapshot snapshot) {
    _downloadQueueSnapshotNotifier.value = snapshot;
  }

  DownloadQueueTask? _downloadQueueTaskById(String taskId) {
    for (final DownloadQueueTask task in _downloadQueueSnapshot.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  Future<void> _updateDownloadQueueTask(
    DownloadQueueTask updatedTask, {
    bool persist = true,
  }) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final int index = snapshot.tasks.indexWhere(
      (DownloadQueueTask task) => task.id == updatedTask.id,
    );
    if (index == -1) {
      return;
    }

    final List<DownloadQueueTask> tasks = snapshot.tasks.toList(growable: true);
    tasks[index] = updatedTask;
    final DownloadQueueSnapshot nextSnapshot = snapshot.copyWith(
      tasks: tasks.toList(growable: false),
    );
    if (persist) {
      await _persistDownloadQueueSnapshot(nextSnapshot);
      return;
    }
    _setDownloadQueueSnapshotInMemory(nextSnapshot);
  }

  String _comicQueueKey(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return value.trim();
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
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
    );
  }

  Future<void> _enqueueSelectedChapters(
    DetailPageData page,
    List<ChapterData> chapters,
  ) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final List<DownloadQueueTask> tasks = snapshot.tasks.toList(growable: true);
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

      tasks.add(_buildDownloadQueueTask(page, chapterUri, chapter));
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

    final bool keepPaused = snapshot.isPaused && snapshot.isNotEmpty;
    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(
        isPaused: keepPaused,
        tasks: tasks.toList(growable: false),
      ),
    );

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

    if (!keepPaused) {
      unawaited(_ensureDownloadQueueRunning());
    }
  }

  Future<void> _pauseDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty || snapshot.isPaused) {
      return;
    }
    await _persistDownloadQueueSnapshot(snapshot.copyWith(isPaused: true));
    _showSnackBar('后台缓存将在当前图片完成后暂停');
  }

  Future<void> _resumeDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<DownloadQueueTask> tasks = snapshot.tasks
        .map((DownloadQueueTask task) {
          if (task.status == DownloadQueueTaskStatus.failed ||
              task.status == DownloadQueueTaskStatus.paused ||
              task.status == DownloadQueueTaskStatus.parsing ||
              task.status == DownloadQueueTaskStatus.downloading) {
            return task.copyWith(
              status: DownloadQueueTaskStatus.queued,
              progressLabel: '等待缓存',
              errorMessage: '',
              updatedAt: now,
            );
          }
          return task;
        })
        .toList(growable: false);

    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(isPaused: false, tasks: tasks),
    );
    _showSnackBar('已继续后台缓存');
    unawaited(_ensureDownloadQueueRunning());
  }

  Future<void> _removeComicFromDownloadQueue(
    String comicKey, {
    required String comicTitle,
    bool markFilesForDeletion = false,
  }) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty) {
      return;
    }

    final bool containsComic = snapshot.tasks.any(
      (DownloadQueueTask task) => task.comicKey == comicKey,
    );
    if (!containsComic) {
      return;
    }

    final bool removesActiveComic = snapshot.activeTask?.comicKey == comicKey;
    final List<DownloadQueueTask> remainingTasks = snapshot.tasks
        .where((DownloadQueueTask task) => task.comicKey != comicKey)
        .toList(growable: false);

    if (removesActiveComic) {
      _cancelledComicKeys.add(comicKey);
      if (markFilesForDeletion) {
        _cancelledComicTitles[comicKey] = comicTitle;
      }
    }

    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(
        isPaused: remainingTasks.isEmpty ? false : snapshot.isPaused,
        tasks: remainingTasks,
      ),
    );
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
    final bool removesActiveComic =
        _downloadQueueSnapshot.activeTask?.comicKey == comicKey;

    await _removeComicFromDownloadQueue(
      comicKey,
      comicTitle: item.comicTitle,
      markFilesForDeletion: removesActiveComic,
    );

    if (!removesActiveComic) {
      await _downloadService.deleteCachedComic(item);
      await _refreshCachedComics();
    }

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

    final bool removesActiveComic =
        _downloadQueueSnapshot.activeTask?.comicKey == task.comicKey;
    await _removeComicFromDownloadQueue(
      task.comicKey,
      comicTitle: task.comicTitle,
      markFilesForDeletion: true,
    );
    if (!removesActiveComic) {
      await _downloadService.deleteComicCacheByTitle(task.comicTitle);
      await _refreshCachedComics();
    }
    _showSnackBar('已移出 ${task.comicTitle} 的缓存任务');
  }

  bool _shouldPauseActiveDownload(DownloadQueueTask task) {
    return _downloadQueueSnapshot.isPaused &&
        _downloadQueueTaskById(task.id) != null;
  }

  bool _shouldCancelActiveDownload(DownloadQueueTask task) {
    return _cancelledComicKeys.contains(task.comicKey) ||
        _downloadQueueTaskById(task.id) == null;
  }

  Future<void> _ensureDownloadQueueRunning() async {
    if (_isProcessingDownloadQueue ||
        _downloadQueueSnapshot.isPaused ||
        _downloadQueueSnapshot.isEmpty ||
        !mounted) {
      return;
    }

    _isProcessingDownloadQueue = true;
    try {
      while (mounted) {
        final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
        if (snapshot.isPaused || snapshot.isEmpty) {
          break;
        }
        final DownloadQueueTask task = snapshot.activeTask!;
        await _runDownloadQueueTask(task);
      }
    } finally {
      _isProcessingDownloadQueue = false;
    }
  }

  Future<void> _runDownloadQueueTask(DownloadQueueTask task) async {
    await _updateDownloadQueueTask(
      task.copyWith(
        status: DownloadQueueTaskStatus.parsing,
        progressLabel: '正在解析 ${task.chapterLabel}',
        completedImages: 0,
        totalImages: 0,
        errorMessage: '',
        updatedAt: DateTime.now(),
      ),
    );

    try {
      await _session.ensureInitialized();
      final ReaderPageData readerPage = await _extractReaderPageForDownload(
        Uri.parse(task.chapterHref),
      );

      if (_shouldCancelActiveDownload(task)) {
        throw const DownloadCancelledException();
      }
      if (_shouldPauseActiveDownload(task)) {
        throw const DownloadPausedException();
      }

      await _updateDownloadQueueTask(
        task.copyWith(
          status: DownloadQueueTaskStatus.downloading,
          progressLabel: '正在缓存 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: readerPage.imageUrls.length,
          errorMessage: '',
          updatedAt: DateTime.now(),
        ),
      );

      await _downloadService.downloadChapter(
        readerPage,
        cookieHeader: _session.cookieHeader,
        comicUri: task.comicUri,
        chapterHref: task.chapterHref,
        chapterLabel: task.chapterLabel,
        coverUrl: task.coverUrl,
        shouldPause: () => _shouldPauseActiveDownload(task),
        shouldCancel: () => _shouldCancelActiveDownload(task),
        onProgress: (ChapterDownloadProgress progress) async {
          final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
          if (latestTask == null) {
            return;
          }
          await _updateDownloadQueueTask(
            latestTask.copyWith(
              status: DownloadQueueTaskStatus.downloading,
              progressLabel: '${task.chapterLabel} · ${progress.currentLabel}',
              completedImages: progress.completedCount,
              totalImages: progress.totalCount,
              errorMessage: '',
              updatedAt: DateTime.now(),
            ),
            persist: false,
          );
        },
      );

      final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
      final List<DownloadQueueTask> remainingTasks = snapshot.tasks
          .where((DownloadQueueTask item) => item.id != task.id)
          .toList(growable: false);
      await _persistDownloadQueueSnapshot(
        snapshot.copyWith(
          isPaused: remainingTasks.isEmpty ? false : snapshot.isPaused,
          tasks: remainingTasks,
        ),
      );
      await _refreshCachedComics();

      if (mounted && remainingTasks.isEmpty) {
        _showSnackBar('后台缓存已完成');
      }
    } on DownloadPausedException {
      final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
      if (latestTask != null) {
        final String pauseLabel =
            latestTask.totalImages > 0 && latestTask.completedImages > 0
            ? '已暂停 ${latestTask.completedImages}/${latestTask.totalImages}'
            : '已暂停';
        await _updateDownloadQueueTask(
          latestTask.copyWith(
            status: DownloadQueueTaskStatus.paused,
            progressLabel: pauseLabel,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } on DownloadCancelledException {
      final String comicTitle =
          _cancelledComicTitles.remove(task.comicKey) ?? task.comicTitle;
      _cancelledComicKeys.remove(task.comicKey);
      await _downloadService.deleteComicCacheByTitle(comicTitle);
      await _refreshCachedComics();
    } catch (error) {
      final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
      final String message = _formatDownloadError(error);
      if (latestTask != null) {
        final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
        final List<DownloadQueueTask> tasks = snapshot.tasks
            .map((DownloadQueueTask item) {
              if (item.id != latestTask.id) {
                return item;
              }
              return latestTask.copyWith(
                status: DownloadQueueTaskStatus.failed,
                progressLabel: '失败：$message',
                errorMessage: message,
                updatedAt: DateTime.now(),
              );
            })
            .toList(growable: false);
        await _persistDownloadQueueSnapshot(
          snapshot.copyWith(isPaused: true, tasks: tasks),
        );
      }
      if (mounted) {
        _showSnackBar('缓存失败：$message');
      }
    }
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

  bool _shouldAcceptPendingNavigationUri(
    Uri uri, {
    required StandardPageLoadEventSource source,
  }) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null || pendingLoad.completer.isCompleted) {
      return true;
    }
    return pendingLoad.accepts(uri, source: source);
  }

  void _setPendingLocation(Uri uri) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex =
        _pendingPageLoad?.targetTabIndex ?? tabIndexForUri(rewrittenUri);
    _mutateSessionState(() {
      _tabSessionStore.replaceCurrent(tabIndex, rewrittenUri);
    }, syncSearch: tabIndex == _selectedIndex);
  }

  void _startLoading(Uri uri, {required bool preserveCurrentPage}) {
    if (!preserveCurrentPage) {
      _resetStandardScrollPosition();
    }
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex =
        _pendingPageLoad?.targetTabIndex ?? tabIndexForUri(rewrittenUri);
    final EasyCopyPage? visiblePage = preserveCurrentPage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    _mutateSessionState(() {
      _tabSessionStore.replaceCurrent(tabIndex, rewrittenUri);
      _tabSessionStore.updateCurrent(
        tabIndex,
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
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  int _prepareRouteEntry(
    Uri uri, {
    required NavigationIntent intent,
    required bool preserveVisiblePage,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex = tabIndexForUri(targetUri);
    final EasyCopyPage? preservedPage = preserveVisiblePage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    _mutateSessionState(() {
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
      _selectedIndex = tabIndex;
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
        ),
      );
    });
    if (preserveVisiblePage &&
        preservedPage != null &&
        preservedPage is! ReaderPageData) {
      _restoreStandardScrollPosition(
        _tabSessionStore.currentEntry(tabIndex).standardScrollOffset,
      );
    }
    return tabIndex;
  }

  void _markTabEntryLoading(int tabIndex, {required bool preservePage}) {
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          isLoading: true,
          clearError: true,
          clearPage: !preservePage,
        ),
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  void _finishTabEntryLoading(int tabIndex, {String? message}) {
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          isLoading: false,
          errorMessage: message,
          clearError: message == null,
        ),
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  void _finishMatchingRouteLoading(
    int tabIndex,
    String routeKey, {
    String? message,
  }) {
    _mutateSessionState(() {
      _tabSessionStore.updateError(tabIndex, routeKey, message);
    }, syncSearch: tabIndex == _selectedIndex);
  }

  Future<EasyCopyPage> _loadStandardPageFresh(
    Uri uri, {
    required String authScope,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int loadId = ++_activeLoadId;
    final bool preserveCurrentPage = _nextFreshPreserveCurrentPage ?? false;
    final StandardPageLoadHandle<EasyCopyPage> pendingLoad =
        StandardPageLoadHandle<EasyCopyPage>(
          requestedUri: targetUri,
          queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
          intent: _nextFreshNavigationIntent ?? NavigationIntent.preserve,
          preserveCurrentPage: preserveCurrentPage,
          loadId: loadId,
          targetTabIndex: tabIndexForUri(targetUri),
          completer: Completer<EasyCopyPage>(),
        );
    _nextFreshNavigationIntent = null;
    _nextFreshPreserveCurrentPage = null;
    _standardPageLoadController.begin(pendingLoad);
    await _syncSessionCookiesToCurrentHost();
    if (!_standardPageLoadController.isCurrent(pendingLoad)) {
      throw const SupersededPageLoadException();
    }
    await _controller.loadRequest(targetUri);
    return pendingLoad.completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _standardPageLoadController.clear(pendingLoad);
        throw TimeoutException('页面解析超时');
      },
    );
  }

  void _applyLoadedPage(
    EasyCopyPage page, {
    int? targetTabIndex,
    bool switchToTab = true,
  }) {
    final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
    final int tabIndex = targetTabIndex ?? tabIndexForUri(pageUri);
    final String? previousReaderUri =
        tabIndex == _selectedIndex && _page is ReaderPageData
        ? (_page as ReaderPageData).uri
        : null;

    _mutateSessionState(() {
      if (switchToTab) {
        _selectedIndex = tabIndex;
      }
      _tabSessionStore.updatePage(tabIndex, page);
    }, syncSearch: switchToTab || tabIndex == _selectedIndex);
    _scheduleReaderPresentationSync();

    if (tabIndex != _selectedIndex) {
      return;
    }
    if (page is ReaderPageData) {
      _handleReaderPageLoaded(page, previousUri: previousReaderUri);
      return;
    }
    _restoreStandardScrollPosition(
      _tabSessionStore.currentEntry(tabIndex).standardScrollOffset,
    );
  }

  void _failPendingPageLoad(String message) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null) {
      return;
    }
    if (!pendingLoad.completer.isCompleted) {
      pendingLoad.completer.completeError(message);
    }
    _standardPageLoadController.clear(pendingLoad);

    final PrimaryTabRouteEntry currentEntry = _tabSessionStore.currentEntry(
      pendingLoad.targetTabIndex,
    );
    if (currentEntry.page != null) {
      _finishTabEntryLoading(pendingLoad.targetTabIndex);
      if (pendingLoad.targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateError(
        pendingLoad.targetTabIndex,
        currentEntry.routeKey,
        message,
      );
    }, syncSearch: pendingLoad.targetTabIndex == _selectedIndex);
  }

  Future<void> _loadUri(
    Uri uri, {
    bool bypassCache = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
    _CachedChapterNavigationContext cachedChapterContext =
        const _CachedChapterNavigationContext(),
  }) async {
    _persistVisiblePageState();
    await _hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (!bypassCache &&
        !preserveVisiblePage &&
        !_isLoading &&
        _page != null &&
        _currentEntry.routeKey == key.routeKey &&
        _isPrimaryTabContent) {
      _restoreStandardScrollPosition(_currentEntry.standardScrollOffset);
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
    if (_isReaderChapterUri(targetUri)) {
      final bool openedFromCache = await _tryOpenCachedChapterReader(
        targetUri,
        historyMode: historyMode,
        preserveVisiblePage: preserveVisiblePage,
        context: cachedChapterContext,
      );
      if (openedFromCache) {
        return;
      }
    }

    _consecutiveFrameFailures = 0;
    final int targetTabIndex = _prepareRouteEntry(
      targetUri,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    if (!bypassCache) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (cachedHit != null) {
        _applyLoadedPage(
          cachedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: true,
        );
        if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
          return;
        }
        _markTabEntryLoading(targetTabIndex, preservePage: true);
        unawaited(
          _revalidateCachedPage(
            targetUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            targetTabIndex: targetTabIndex,
          ),
        );
        return;
      }
    }

    _nextFreshNavigationIntent = historyMode;
    _nextFreshPreserveCurrentPage = preserveVisiblePage;
    try {
      await _pageRepository.loadFresh(targetUri, authScope: key.authScope);
    } catch (error) {
      await _handlePageLoadFailure(
        error,
        targetTabIndex: targetTabIndex,
        routeKey: key.routeKey,
      );
    } finally {
      _nextFreshNavigationIntent = null;
      _nextFreshPreserveCurrentPage = null;
    }
  }

  _CachedChapterNavigationContext _resolvedCachedChapterContext(
    Uri targetUri, {
    required _CachedChapterNavigationContext context,
  }) {
    if (context.hasAnyValue) {
      return context;
    }
    final EasyCopyPage? currentPage = _page;
    if (currentPage is! ReaderPageData) {
      return const _CachedChapterNavigationContext();
    }
    final String targetKey = _chapterPathKey(targetUri.toString());
    final String currentKey = _chapterPathKey(currentPage.uri);
    final String prevKey = _chapterPathKey(currentPage.prevHref);
    final String nextKey = _chapterPathKey(currentPage.nextHref);

    if (targetKey == currentKey) {
      return _CachedChapterNavigationContext(
        prevHref: currentPage.prevHref,
        nextHref: currentPage.nextHref,
        catalogHref: currentPage.catalogHref,
      );
    }
    if (targetKey == prevKey) {
      return _CachedChapterNavigationContext(
        nextHref: currentPage.uri,
        catalogHref: currentPage.catalogHref,
      );
    }
    if (targetKey == nextKey) {
      return _CachedChapterNavigationContext(
        prevHref: currentPage.uri,
        catalogHref: currentPage.catalogHref,
      );
    }
    return _CachedChapterNavigationContext(
      catalogHref: currentPage.catalogHref,
    );
  }

  Future<void> _revalidateCachedPage(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope cachedEntry,
    required int targetTabIndex,
  }) async {
    try {
      _nextFreshPreserveCurrentPage = true;
      await _pageRepository.revalidate(uri, key: key, envelope: cachedEntry);
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        targetTabIndex,
      );
      if (entry.routeKey != key.routeKey) {
        return;
      }
      final CachedPageHit? refreshedHit = await _pageRepository.readCached(key);
      if (refreshedHit != null) {
        _applyLoadedPage(
          refreshedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: targetTabIndex == _selectedIndex,
        );
        return;
      }
      _finishMatchingRouteLoading(targetTabIndex, key.routeKey);
    } on SupersededPageLoadException {
      _finishMatchingRouteLoading(targetTabIndex, key.routeKey);
    } catch (_) {
      _finishMatchingRouteLoading(targetTabIndex, key.routeKey);
    } finally {
      _nextFreshPreserveCurrentPage = null;
    }
  }

  Future<void> _loadProfilePage({
    bool forceRefresh = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _persistVisiblePageState();
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    final Uri profileUri = AppConfig.profileUri;
    final int targetTabIndex = _prepareRouteEntry(
      profileUri,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    final PageQueryKey key = _pageQueryKeyForUri(profileUri);
    if (!forceRefresh) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (cachedHit != null) {
        _applyLoadedPage(
          cachedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: true,
        );
        if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
          return;
        }
        _markTabEntryLoading(targetTabIndex, preservePage: true);
        unawaited(
          _revalidateCachedPage(
            profileUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            targetTabIndex: targetTabIndex,
          ),
        );
        return;
      }
    }

    try {
      final EasyCopyPage profilePage = await _pageRepository.loadFresh(
        profileUri,
        authScope: key.authScope,
      );
      _applyLoadedPage(
        profilePage,
        targetTabIndex: targetTabIndex,
        switchToTab: true,
      );
    } catch (error) {
      await _handlePageLoadFailure(
        error,
        targetTabIndex: targetTabIndex,
        routeKey: key.routeKey,
      );
    }
  }

  Future<void> _handlePageLoadFailure(
    Object error, {
    required int targetTabIndex,
    required String routeKey,
  }) async {
    if (error is SupersededPageLoadException) {
      _finishMatchingRouteLoading(targetTabIndex, routeKey);
      return;
    }

    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (targetTabIndex == _selectedIndex) {
        _showSnackBar('登录已失效，请重新登录。');
      }
      return;
    }

    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
      targetTabIndex,
    );
    if (entry.page != null) {
      _finishTabEntryLoading(targetTabIndex);
      if (targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }

    _mutateSessionState(() {
      _tabSessionStore.updateError(targetTabIndex, routeKey, message);
    }, syncSearch: targetTabIndex == _selectedIndex);
  }

  Future<void> _retryCurrentPage() async {
    if (_page is ProfilePageData || _selectedIndex == 3) {
      await _loadProfilePage(
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

  void _navigateDiscoverFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadUri(
        AppConfig.resolveNavigationUri(href, currentUri: _currentUri),
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _navigateRankFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadUri(
        AppConfig.resolveNavigationUri(href, currentUri: _currentUri),
        preserveVisiblePage: true,
        historyMode: NavigationIntent.preserve,
      ),
    );
  }

  void _navigateToHref(String href) {
    unawaited(_openHref(href));
  }

  Future<void> _openHref(
    String href, {
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
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
    required NavigationIntent historyMode,
    required bool preserveVisiblePage,
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
    final int targetTabIndex = _prepareRouteEntry(
      Uri.parse(cachedPage.uri),
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    _applyLoadedPage(
      cachedPage,
      targetTabIndex: targetTabIndex,
      switchToTab: true,
    );
    return true;
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
    await _hostManager.pinSessionHost(_hostManager.currentHost);
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
    await _hostManager.clearSessionPin();
    await _cookieManager.clearCookies();
    _mutateSessionState(() {
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
            ? '测速完成，当前仍手动锁定到 ${_hostManager.currentHost}'
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
    } catch (_) {
      if (mounted) {
        _showSnackBar('切换节点失败，请稍后重试');
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
        _showSnackBar('已恢复自动选择，当前节点 ${_hostManager.currentHost}');
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
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
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

  void _submitSearch(String value) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    unawaited(_loadUri(AppConfig.buildSearchUri(query)));
  }

  Uri _targetUriForPrimaryTab(int index, {bool resetToRoot = false}) {
    if (resetToRoot) {
      return _tabSessionStore.resetToRoot(index).uri;
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
      historyMode: shouldResetToRoot
          ? NavigationIntent.resetToRoot
          : NavigationIntent.preserve,
    );
  }

  Future<void> _handleBackNavigation() async {
    _persistVisiblePageState();
    final PrimaryTabRouteEntry? previousEntry = _tabSessionStore.pop(
      _selectedIndex,
    );
    if (previousEntry != null) {
      await _loadUri(
        previousEntry.uri,
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    if (_selectedIndex != 0) {
      await _loadHome();
      return;
    }
    await SystemNavigator.pop();
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
      _finishTabEntryLoading(_selectedIndex);
      _showSnackBar(message);
    }
    if (_isFailingOver || _consecutiveFrameFailures < 2) {
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
        historyMode: NavigationIntent.preserve,
      );
      _consecutiveFrameFailures = 0;
    } finally {
      _isFailingOver = false;
    }
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

  void _handleReaderPageLoaded(
    ReaderPageData page, {
    String? previousUri,
    bool forceRestore = false,
  }) {
    final List<String> remoteImages = page.imageUrls
        .where((String imageUrl) {
          final Uri? uri = Uri.tryParse(imageUrl);
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
        })
        .toList(growable: false);
    unawaited(EasyCopyImageCaches.prefetchReaderImages(remoteImages));
    unawaited(_markReaderChapterVisited(page));
    final bool changedPage = previousUri != page.uri;
    if (changedPage) {
      _currentReaderPageIndex = 0;
      _currentVisibleReaderImageIndex = 0;
      _isReaderChapterControlsVisible = false;
      _disposeReaderPagedScrollControllers();
      _readerImageItemKeys.clear();
    }
    _scheduleReaderPresentationSync();
    if (changedPage || forceRestore) {
      unawaited(
        _restoreReaderPosition(
          page,
          resetControllers: changedPage || forceRestore,
        ),
      );
    }
  }

  Future<void> _markReaderChapterVisited(ReaderPageData page) {
    return _readerProgressStore.markChapterOpened(
      key: _readerProgressKeyForPage(page),
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
  }

  Future<void> _restoreReaderPosition(
    ReaderPageData page, {
    required bool resetControllers,
  }) async {
    final String progressKey = _readerProgressKeyForPage(page);
    final ReaderPosition? savedPosition = await _readerProgressStore
        .readPosition(progressKey);
    if (!mounted ||
        _page is! ReaderPageData ||
        (_page as ReaderPageData).uri != page.uri) {
      return;
    }

    if (_readerPreferences.isPaged) {
      final int pageIndex = savedPosition?.isPaged == true
          ? savedPosition!.pageIndex.clamp(0, page.imageUrls.length - 1)
          : 0;
      final double? pageOffset = savedPosition?.isPaged == true
          ? savedPosition!.pageOffset
          : null;
      if (resetControllers) {
        _disposeReaderPagedScrollControllers();
        _replaceReaderPageController(initialPage: pageIndex);
      }
      _lastPersistedReaderPosition = savedPosition;
      _currentReaderPageIndex = pageIndex;
      _currentVisibleReaderImageIndex = pageIndex;
      if (mounted) {
        setState(() {});
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpReaderToPage(pageIndex, attempts: 10);
        _jumpReaderPageOffset(pageIndex, offset: pageOffset, attempts: 10);
      });
      return;
    }

    final double? savedOffset = savedPosition?.isScroll == true
        ? savedPosition!.offset
        : null;
    _lastPersistedReaderPosition = savedPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpReaderToOffset(savedOffset, attempts: 10);
      _scheduleVisibleReaderImageIndexUpdate();
    });
  }

  void _jumpReaderToOffset(double? offset, {required int attempts}) {
    if (!_readerScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToOffset(offset, attempts: attempts - 1),
        );
      }
      return;
    }

    final double maxExtent = _readerScrollController.position.maxScrollExtent;
    final double targetOffset =
        offset ??
        (_readerPreferences.openingPosition == ReaderOpeningPosition.center
            ? (_readerScrollController.position.viewportDimension * 0.5)
            : 0);
    if (targetOffset > maxExtent && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 250),
        () => _jumpReaderToOffset(targetOffset, attempts: attempts - 1),
      );
      return;
    }
    final double clampedOffset = targetOffset.clamp(0, maxExtent).toDouble();
    _readerScrollController.jumpTo(clampedOffset);
  }

  void _jumpReaderToPage(int pageIndex, {required int attempts}) {
    if (!_readerPageController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToPage(pageIndex, attempts: attempts - 1),
        );
      }
      return;
    }
    _readerPageController.jumpToPage(pageIndex);
  }

  void _jumpReaderPageOffset(
    int pageIndex, {
    required double? offset,
    required int attempts,
  }) {
    final ScrollController? controller =
        _readerPageScrollControllers[pageIndex];
    if (controller == null || !controller.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderPageOffset(
            pageIndex,
            offset: offset,
            attempts: attempts - 1,
          ),
        );
      }
      return;
    }
    final double maxExtent = controller.position.maxScrollExtent;
    final double targetOffset =
        offset ??
        (_readerPreferences.openingPosition == ReaderOpeningPosition.center
            ? maxExtent * 0.5
            : 0);
    controller.jumpTo(targetOffset.clamp(0, maxExtent).toDouble());
  }

  void _handleReaderScroll() {
    final EasyCopyPage? page = _page;
    if (page is! ReaderPageData ||
        !_readerScrollController.hasClients ||
        _readerPreferences.isPaged) {
      return;
    }

    final double currentOffset = _readerScrollController.offset;
    if (_lastPersistedReaderPosition?.isScroll == true &&
        (currentOffset - _lastPersistedReaderPosition!.offset).abs() < 48) {
      return;
    }
    _scheduleReaderProgressPersistence();
    _restartReaderAutoTurn();
    _scheduleVisibleReaderImageIndexUpdate();
  }

  void _handleReaderPageChanged(int index) {
    if (_currentReaderPageIndex == index) {
      return;
    }
    if (!mounted) {
      _currentReaderPageIndex = index;
      _currentVisibleReaderImageIndex = index;
      return;
    }
    setState(() {
      _currentReaderPageIndex = index;
      _currentVisibleReaderImageIndex = index;
    });
    _scheduleReaderProgressPersistence();
    _restartReaderAutoTurn();
  }

  void _handleReaderPagedInnerScroll(int pageIndex) {
    if (pageIndex != _currentReaderPageIndex) {
      return;
    }
    final ScrollController? controller =
        _readerPageScrollControllers[pageIndex];
    if (controller == null || !controller.hasClients) {
      return;
    }
    if (_lastPersistedReaderPosition?.isPaged == true &&
        _lastPersistedReaderPosition!.pageIndex == pageIndex &&
        (controller.offset - _lastPersistedReaderPosition!.pageOffset).abs() <
            32) {
      return;
    }
    _scheduleReaderProgressPersistence();
    _restartReaderAutoTurn();
  }

  void _scheduleReaderProgressPersistence() {
    _readerProgressDebounce?.cancel();
    _readerProgressDebounce = Timer(
      const Duration(milliseconds: 900),
      _persistCurrentReaderProgress,
    );
  }

  String _readerProgressKeyForPage(ReaderPageData page) {
    final Uri uri = Uri.parse(page.uri);
    return '${uri.path}::${page.contentKey}';
  }

  void _persistCurrentReaderProgress() {
    final EasyCopyPage? page = _page;
    if (page is! ReaderPageData) {
      return;
    }
    final String progressKey = _readerProgressKeyForPage(page);
    if (_readerPreferences.isPaged) {
      final ScrollController? pageController =
          _readerPageScrollControllers[_currentReaderPageIndex];
      final ReaderPosition position = ReaderPosition.paged(
        pageIndex: _currentReaderPageIndex,
        pageOffset: pageController != null && pageController.hasClients
            ? pageController.offset
            : 0,
      );
      _lastPersistedReaderPosition = position;
      unawaited(
        _readerProgressStore.writePosition(
          progressKey,
          position,
          catalogHref: page.catalogHref,
          chapterHref: page.uri,
        ),
      );
      return;
    }
    if (!_readerScrollController.hasClients) {
      return;
    }
    final ReaderPosition position = ReaderPosition.scroll(
      offset: _readerScrollController.offset,
    );
    _lastPersistedReaderPosition = position;
    unawaited(
      _readerProgressStore.writePosition(
        progressKey,
        position,
        catalogHref: page.catalogHref,
        chapterHref: page.uri,
      ),
    );
  }

  void _persistVisiblePageState() {
    _persistCurrentReaderProgress();
    if (_page == null ||
        _isReaderMode ||
        !_standardScrollController.hasClients) {
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
    _suspendStandardScrollTracking = true;
    if (_standardScrollController.hasClients) {
      _standardScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _suspendStandardScrollTracking = false;
        return;
      }
      if (!_standardScrollController.hasClients) {
        _suspendStandardScrollTracking = false;
        return;
      }
      if (_standardScrollController.offset != 0) {
        _standardScrollController.jumpTo(0);
      }
      _suspendStandardScrollTracking = false;
    });
  }

  void _restoreStandardScrollPosition(double offset) {
    _suspendStandardScrollTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpStandardToOffset(offset, attempts: 10);
    });
  }

  void _jumpStandardToOffset(double offset, {required int attempts}) {
    if (!mounted) {
      _suspendStandardScrollTracking = false;
      return;
    }
    if (!_standardScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => _jumpStandardToOffset(offset, attempts: attempts - 1),
        );
        return;
      }
      _suspendStandardScrollTracking = false;
      return;
    }

    final double maxExtent = _standardScrollController.position.maxScrollExtent;
    final double clampedOffset = offset.clamp(0, maxExtent).toDouble();
    if ((offset - clampedOffset).abs() > 1 && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _jumpStandardToOffset(offset, attempts: attempts - 1),
      );
      return;
    }

    _standardScrollController.jumpTo(clampedOffset);
    _suspendStandardScrollTracking = false;
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      clampedOffset,
    );
  }

  Future<void> _scrollCurrentStandardPageToTop() async {
    if (!_standardScrollController.hasClients) {
      return;
    }
    await _standardScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _tabSessionStore.updateScroll(_selectedIndex, _currentEntry.routeKey, 0);
  }

  bool get _isReaderMode => _page is ReaderPageData;

  bool get _isDetailRoute {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData) {
      return true;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.startsWith('/comic/chapter');
  }

  bool get _shouldShowSearchBar {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData || page is DetailPageData) {
      return false;
    }
    return !_isDetailRoute;
  }

  bool get _isPrimaryTabContent {
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

  bool get _shouldShowHeaderCard => !_isPrimaryTabContent && !_isDetailRoute;

  bool get _shouldShowBackButton {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData || page is UnknownPageData || _isDetailRoute) {
      return true;
    }
    if ((page is DiscoverPageData || page == null) &&
        _currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  String get _pageTitle {
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
          Positioned(
            left: -8,
            top: -8,
            width: 4,
            height: 4,
            child: IgnorePointer(child: WebViewWidget(controller: _controller)),
          ),
          Positioned(
            left: -16,
            top: -16,
            width: 4,
            height: 4,
            child: IgnorePointer(
              child: WebViewWidget(controller: _downloadController),
            ),
          ),
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

  Widget _buildStandardMode(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('standard-scaffold'),
      backgroundColor: Colors.transparent,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: appDestinations
            .map(
              (AppDestination destination) => NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
      body: SafeArea(child: _buildStandardBody(context)),
    );
  }

  Widget _buildStandardBody(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _retryCurrentPage,
      child: ListView(
        controller: _standardScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          _buildAnimatedSectionContent(
            contentKey: _standardContentTransitionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildStandardBodyChildren(context),
            ),
          ),
        ],
      ),
    );
  }

  String get _standardContentTransitionKey {
    final String prefix = _errorMessage != null && _page == null
        ? 'error'
        : 'page';
    return '$prefix::$_standardBodyTransitionScope';
  }

  List<Widget> _buildStandardBodyChildren(BuildContext context) {
    if (_errorMessage != null && _page == null) {
      return _buildErrorSections(context);
    }
    return _buildStandardChildren(context);
  }

  List<Widget> _buildStandardChildren(BuildContext context) {
    final List<Widget> children = <Widget>[
      ..._buildStandardTopContent(context),
      _buildDownloadQueueBanner(),
    ];

    if (_page == null) {
      children.addAll(_buildLoadingSections(context));
      return children;
    }

    final EasyCopyPage page = _page!;
    switch (page) {
      case HomePageData homePage:
        children.addAll(_buildHomeSections(homePage));
      case DiscoverPageData discoverPage:
        children.addAll(_buildDiscoverSections(discoverPage));
      case RankPageData rankPage:
        children.addAll(_buildRankSections(rankPage));
      case DetailPageData detailPage:
        children.addAll(_buildDetailSections(detailPage));
      case ProfilePageData profilePage:
        children.addAll(_buildProfileSections(profilePage));
      case UnknownPageData unknownPage:
        children.addAll(_buildMessageSections(unknownPage.message));
      case ReaderPageData _:
        break;
    }

    return children;
  }

  List<Widget> _buildStandardTopContent(BuildContext context) {
    if (_shouldShowDiscoverSearchChrome) {
      return <Widget>[
        _buildDiscoverSearchChrome(context),
        const SizedBox(height: 18),
      ];
    }

    if (_shouldShowHeaderCard) {
      return <Widget>[
        _buildHeaderCard(
          context,
          title: _pageTitle,
          showBackButton: _shouldShowBackButton,
          showSearchBar: _shouldShowSearchBar,
        ),
        const SizedBox(height: 18),
      ];
    }

    return const <Widget>[];
  }

  bool get _shouldShowDiscoverSearchChrome {
    if (_selectedIndex != 1 || _isDetailRoute) {
      return false;
    }
    final EasyCopyPage? page = _page;
    if (page == null || page is DiscoverPageData) {
      return true;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/comics') || path.startsWith('/search');
  }

  Widget _buildDiscoverSearchChrome(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        if (_shouldShowBackButton) ...<Widget>[
          IconButton.filledTonal(
            onPressed: _handleBackNavigation,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _submitSearch,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: '搜索漫画、作者或题材',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchController.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: () {
                      if (_currentUri.path == '/search') {
                        _searchController.clear();
                        unawaited(
                          _loadUri(
                            AppConfig.resolvePath('/comics'),
                            historyMode: NavigationIntent.preserve,
                          ),
                        );
                        return;
                      }
                      setState(_searchController.clear);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton(
                  onPressed: () => _submitSearch(_searchController.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: _submitSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '搜尋漫畫、作者或題材',
              ),
            ),
          ),
          IconButton(
            onPressed: () => _submitSearch(_searchController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadQueueBanner() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder: (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
        if (snapshot.isEmpty || (_selectedIndex == 3 && _isPrimaryTabContent)) {
          return const SizedBox.shrink();
        }

        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final DownloadQueueTask activeTask = snapshot.activeTask!;
        final bool isPaused = snapshot.isPaused;
        final String statusLabel = isPaused
            ? (activeTask.progressLabel.isEmpty
                  ? '后台缓存已暂停'
                  : activeTask.progressLabel)
            : activeTask.progressLabel;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Material(
            color: isPaused
                ? colorScheme.secondaryContainer.withValues(alpha: 0.52)
                : colorScheme.primaryContainer.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        isPaused
                            ? Icons.pause_circle_rounded
                            : Icons.download_for_offline_rounded,
                        color: isPaused
                            ? colorScheme.secondary
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${activeTask.comicTitle} · 剩余 ${snapshot.remainingCount} 话',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: isPaused
                            ? _resumeDownloadQueue
                            : _pauseDownloadQueue,
                        child: Text(isPaused ? '继续' : '暂停'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: activeTask.fraction > 0 ? activeTask.fraction : null,
                    borderRadius: BorderRadius.circular(999),
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadQueueSection() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder:
          (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
            if (snapshot.isEmpty) {
              return const SizedBox.shrink();
            }

            final Map<String, List<DownloadQueueTask>> groupedTasks =
                <String, List<DownloadQueueTask>>{};
            for (final DownloadQueueTask task in snapshot.tasks) {
              groupedTasks
                  .putIfAbsent(task.comicKey, () => <DownloadQueueTask>[])
                  .add(task);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _SurfaceBlock(
                title: '缓存任务',
                actionLabel: snapshot.isPaused ? '继续' : '暂停',
                onActionTap: snapshot.isPaused
                    ? _resumeDownloadQueue
                    : _pauseDownloadQueue,
                child: Column(
                  children: groupedTasks.entries
                      .map((MapEntry<String, List<DownloadQueueTask>> entry) {
                        final List<DownloadQueueTask> tasks = entry.value;
                        final DownloadQueueTask displayTask = tasks.first;
                        final bool isActiveComic =
                            snapshot.activeTask?.comicKey ==
                            displayTask.comicKey;
                        final DownloadQueueTask taskForStatus = isActiveComic
                            ? snapshot.activeTask!
                            : displayTask;
                        final String subtitle = isActiveComic
                            ? taskForStatus.progressLabel
                            : '等待缓存 ${tasks.length} 话';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                8,
                                8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isActiveComic
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                foregroundColor: Colors.white,
                                child: Text('${tasks.length}'),
                              ),
                              title: Text(
                                displayTask.comicTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: IconButton(
                                onPressed: () =>
                                    _confirmRemoveQueuedComic(displayTask),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            );
          },
    );
  }

  List<Widget> _buildProfileSections(ProfilePageData page) {
    final List<Widget> sections = <Widget>[
      ProfilePageView(
        page: page,
        onAuthenticate: _openAuthFlow,
        onLogout: _logout,
        onOpenComic: _navigateToHref,
        onOpenHistory: (ProfileHistoryItem item) {
          final String targetHref = item.chapterHref.isNotEmpty
              ? item.chapterHref
              : item.comicHref;
          _navigateToHref(targetHref);
        },
        currentHost: _hostManager.currentHost,
        candidateHosts: _hostManager.candidateHosts,
        hostSnapshot: _hostManager.probeSnapshot,
        isRefreshingHosts: _isUpdatingHostSettings,
        onRefreshHosts: () {
          unawaited(_refreshHostSettings());
        },
        onUseAutomaticHostSelection: () {
          unawaited(_useAutomaticHostSelection());
        },
        onSelectHost: (String host) {
          unawaited(_selectHost(host));
        },
        themePreference: _preferencesController.themePreference,
        onThemePreferenceChanged: (AppThemePreference preference) {
          unawaited(_preferencesController.setThemePreference(preference));
        },
        afterContinueReading: _buildCachedComicsSection(),
      ),
    ];

    sections.add(const SizedBox(height: 18));
    sections.add(_buildDownloadQueueSection());
    return sections;
  }

  Widget _buildCachedComicsSection() {
    if (_isLoadingCachedComics) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: Row(
          children: const <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在读取本地缓存…'),
          ],
        ),
      );
    }

    if (_cachedComics.isEmpty) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: const Text('还没有缓存章节，去漫画详情页挑几话下载吧。'),
      );
    }

    return _SurfaceBlock(
      title: '已缓存漫画',
      child: SizedBox(
        height: 218,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _cachedComics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (BuildContext context, int index) {
            final CachedComicLibraryEntry item = _cachedComics[index];
            return SizedBox(
              width: 144,
              child: _CachedComicCard(
                item: item,
                onTap: item.comicHref.isEmpty
                    ? null
                    : () => _navigateToHref(item.comicHref),
                onDelete: () => _confirmDeleteCachedComic(item),
              ),
            );
          },
        ),
      ),
    );
  }

  Set<String> _downloadedChapterPathKeysForDetail(DetailPageData page) {
    final Uri currentDetailUri = Uri.parse(page.uri);
    final String targetPath = currentDetailUri.path;
    final CachedComicLibraryEntry? match = _cachedComics
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? item) =>
              item != null && Uri.tryParse(item.comicHref)?.path == targetPath,
          orElse: () => null,
        );
    if (match == null) {
      return const <String>{};
    }
    return match.chapters
        .map(
          (CachedChapterEntry chapter) => _chapterPathKey(chapter.chapterHref),
        )
        .where((String key) => key.isNotEmpty)
        .toSet();
  }

  String _chapterPathKey(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return '';
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  String _lastReadChapterPathKeyForDetail(DetailPageData page) {
    return _readerProgressStore.latestChapterPathKeyForCatalog(page.uri) ?? '';
  }

  List<_ChapterPickerSection> _chapterPickerSections(DetailPageData page) {
    if (page.chapterGroups.isNotEmpty) {
      return page.chapterGroups
          .map(
            (ChapterGroupData group) => _ChapterPickerSection(
              label: group.label,
              chapters: group.chapters,
            ),
          )
          .toList(growable: false);
    }
    return <_ChapterPickerSection>[
      _ChapterPickerSection(label: '全部章节', chapters: page.chapters),
    ];
  }

  Future<void> _showDetailDownloadPicker(DetailPageData page) async {
    final List<_ChapterPickerSection> sections = _chapterPickerSections(page);
    final Set<String> downloadedKeys = _downloadedChapterPathKeysForDetail(
      page,
    );
    final List<ChapterData>?
    selectedChapters = await showModalBottomSheet<List<ChapterData>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        final Set<String> selectedKeys = <String>{};
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            List<ChapterData> selectedChapterValues() {
              return sections
                  .expand((section) => section.chapters)
                  .where(
                    (ChapterData chapter) =>
                        selectedKeys.contains(_chapterPathKey(chapter.href)),
                  )
                  .toList(growable: false);
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '选择要缓存的章节',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedKeys
                                  ..clear()
                                  ..addAll(
                                    sections
                                        .expand((section) => section.chapters)
                                        .map(
                                          (ChapterData chapter) =>
                                              _chapterPathKey(chapter.href),
                                        ),
                                  );
                              });
                            },
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(selectedKeys.clear);
                            },
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          shrinkWrap: true,
                          children: sections
                              .expand((section) {
                                return <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      10,
                                      4,
                                      4,
                                    ),
                                    child: Text(
                                      section.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  ...section.chapters.map((
                                    ChapterData chapter,
                                  ) {
                                    final String key = _chapterPathKey(
                                      chapter.href,
                                    );
                                    final bool isDownloaded = downloadedKeys
                                        .contains(key);
                                    final bool selected = selectedKeys.contains(
                                      key,
                                    );
                                    return CheckboxListTile(
                                      value: selected,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged: (bool? nextValue) {
                                        setModalState(() {
                                          if (nextValue ?? false) {
                                            selectedKeys.add(key);
                                          } else {
                                            selectedKeys.remove(key);
                                          }
                                        });
                                      },
                                      secondary: isDownloaded
                                          ? const Icon(
                                              Icons.check_circle_rounded,
                                              color: Color(0xFF18A558),
                                            )
                                          : null,
                                      title: Text(chapter.label),
                                    );
                                  }),
                                ];
                              })
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedKeys.isEmpty
                              ? null
                              : () {
                                  Navigator.of(
                                    context,
                                  ).pop(selectedChapterValues());
                                },
                          child: Text(
                            selectedKeys.isEmpty
                                ? '请选择章节'
                                : '缓存 ${selectedKeys.length} 话',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedChapters == null || selectedChapters.isEmpty || !mounted) {
      return;
    }
    await _enqueueSelectedChapters(page, selectedChapters);
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String title,
    required bool showBackButton,
    required bool showSearchBar,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showBackButton)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: IconButton.filledTonal(
                    onPressed: _handleBackNavigation,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerLow,
                      foregroundColor: colorScheme.onSurface,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _retryCurrentPage,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerLow,
                  foregroundColor: colorScheme.primary,
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (showSearchBar) ...<Widget>[
            const SizedBox(height: 14),
            _buildSearchField(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildLoadingSections(BuildContext context) {
    return <Widget>[_buildLoadingIndicator(context)];
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double height = MediaQuery.sizeOf(context).height * 0.52;
    return SizedBox(
      height: height.clamp(260, 480),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '正在整理可读内容',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.88),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildErrorSections(BuildContext context) {
    return <Widget>[
      ..._buildStandardTopContent(context),
      _buildDownloadQueueBanner(),
      AppSurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            const Text(
              '内容整理失败',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(_errorMessage ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              _currentUri.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _loadHome,
                    child: const Text('回到首頁'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _retryCurrentPage,
                    child: const Text('重新整理'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildInlineSectionLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: const LinearProgressIndicator(minHeight: 6),
      ),
    );
  }

  Widget _buildAnimatedSectionContent({
    required String contentKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: _pageFadeTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: _buildFadeSwitchTransition,
      child: KeyedSubtree(key: ValueKey<String>(contentKey), child: child),
    );
  }

  String _discoverListContentKey(DiscoverPageData page) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      page.pager.currentLabel,
      '${page.items.length}',
      page.items.isEmpty ? '' : page.items.first.href,
      page.items.isEmpty ? '' : page.items.last.href,
    ].join('::');
  }

  String _rankListContentKey(RankPageData page) {
    return <String>[
      AppConfig.routeKeyForUri(Uri.parse(page.uri)),
      '${page.items.length}',
      page.items.isEmpty ? '' : page.items.first.href,
      page.items.isEmpty ? '' : page.items.last.href,
    ].join('::');
  }

  List<Widget> _buildHomeSections(HomePageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.heroBanners.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '推薦焦點',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: page.heroBanners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (BuildContext context, int index) {
                  final HeroBannerData banner = page.heroBanners[index];
                  return SizedBox(
                    width: 300,
                    child: _HeroBannerCard(
                      banner: banner,
                      onTap: () => _navigateToHref(banner.href),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    if (page.feature != null) {
      sections.add(
        _FeatureBannerCard(
          banner: page.feature!,
          onTap: () => _navigateToHref(page.feature!.href),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    for (final ComicSectionData section in page.sections) {
      sections.add(
        _SurfaceBlock(
          title: section.title,
          actionLabel: section.href.isNotEmpty ? '更多' : null,
          onActionTap: section.href.isNotEmpty
              ? () => _navigateToHref(section.href)
              : null,
          child: ComicGrid(items: section.items, onTap: _navigateToHref),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    return sections;
  }

  List<Widget> _buildDiscoverSections(DiscoverPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.filters.isNotEmpty) {
      final FilterGroupData primaryGroup = page.filters.first;
      final List<LinkAction> themeOptions = primaryGroup.options
          .where((LinkAction option) => !_isDiscoverMoreCategoryOption(option))
          .toList(growable: false);
      final List<FilterGroupData> secondaryGroups = page.filters
          .skip(1)
          .toList(growable: false);

      sections.add(
        _SurfaceBlock(
          title: '篩選器',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FilterGroup(
                group: FilterGroupData(
                  label: primaryGroup.label,
                  options: _visibleDiscoverThemeOptions(themeOptions),
                ),
                onTap: _navigateDiscoverFilter,
                actionLabel: _isDiscoverThemeExpanded ? '收起分類' : '查看全部分類',
                onActionTap: () {
                  setState(() {
                    _isDiscoverThemeExpanded = !_isDiscoverThemeExpanded;
                  });
                },
              ),
              if (secondaryGroups.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Builder(
                  builder: (BuildContext context) {
                    return Container(
                      height: 1,
                      color: Theme.of(context).dividerColor,
                    );
                  },
                ),
                const SizedBox(height: 18),
                ...secondaryGroups.map(
                  (FilterGroupData group) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _FilterGroup(
                      group: group,
                      onTap: _navigateDiscoverFilter,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      _SurfaceBlock(
        title: '內容列表',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_isLoading) _buildInlineSectionLoadingIndicator(),
            _buildAnimatedSectionContent(
              contentKey: _discoverListContentKey(page),
              child: ComicGrid(items: page.items, onTap: _navigateToHref),
            ),
          ],
        ),
      ),
    );
    sections.add(const SizedBox(height: 18));
    sections.add(
      IgnorePointer(
        ignoring: _isLoading,
        child: Opacity(
          opacity: _isLoading ? 0.72 : 1,
          child: _PagerCard(
            pager: page.pager,
            onPrev: page.pager.hasPrev
                ? () {
                    unawaited(
                      _loadUri(
                        AppConfig.resolveNavigationUri(
                          page.pager.prevHref,
                          currentUri: _currentUri,
                        ),
                        preserveVisiblePage: true,
                        historyMode: NavigationIntent.preserve,
                      ),
                    );
                  }
                : null,
            onNext: page.pager.hasNext
                ? () {
                    unawaited(
                      _loadUri(
                        AppConfig.resolveNavigationUri(
                          page.pager.nextHref,
                          currentUri: _currentUri,
                        ),
                        preserveVisiblePage: true,
                        historyMode: NavigationIntent.preserve,
                      ),
                    );
                  }
                : null,
          ),
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildRankSections(RankPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.categories.isNotEmpty || page.periods.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '榜單切換',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (page.categories.isNotEmpty)
                _RankFilterGroup(
                  label: '榜單類型',
                  items: page.categories,
                  onTap: _navigateRankFilter,
                ),
              if (page.categories.isNotEmpty && page.periods.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Builder(
                    builder: (BuildContext context) {
                      return Container(
                        height: 1,
                        color: Theme.of(context).dividerColor,
                      );
                    },
                  ),
                ),
              if (page.periods.isNotEmpty)
                _RankFilterGroup(
                  label: '統計週期',
                  items: page.periods,
                  onTap: _navigateRankFilter,
                ),
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      _SurfaceBlock(
        title: '榜单列表',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_isLoading) _buildInlineSectionLoadingIndicator(),
            _buildAnimatedSectionContent(
              contentKey: _rankListContentKey(page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: page.items
                    .map(
                      (RankEntryData item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RankCard(
                          item: item,
                          onTap: () => _navigateToHref(item.href),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildDetailSections(DetailPageData page) {
    final Set<String> downloadedChapterKeys =
        _downloadedChapterPathKeysForDetail(page);
    final String lastReadChapterPathKey = _lastReadChapterPathKeyForDetail(
      page,
    );
    final List<Widget> sections = <Widget>[
      _DetailHeroCard(
        page: page,
        onReadNow: page.startReadingHref.isNotEmpty
            ? () => _openDetailChapter(page, page.startReadingHref)
            : null,
        onDownload: () => _showDetailDownloadPicker(page),
        onTagTap: _navigateToHref,
      ),
      const SizedBox(height: 18),
    ];

    if (page.summary.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '內容簡介',
          child: Text(page.summary, style: const TextStyle(height: 1.7)),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> infoChips = <Widget>[
      if (page.authors.isNotEmpty) _InfoChip(label: '作者', value: page.authors),
      if (page.status.isNotEmpty) _InfoChip(label: '狀態', value: page.status),
      if (page.updatedAt.isNotEmpty)
        _InfoChip(label: '更新', value: page.updatedAt),
      if (page.heat.isNotEmpty) _InfoChip(label: '熱度', value: page.heat),
      if (page.aliases.isNotEmpty) _InfoChip(label: '別名', value: page.aliases),
    ];
    if (infoChips.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '作品信息',
          child: Wrap(spacing: 10, runSpacing: 10, children: infoChips),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> chapterWidgets = <Widget>[];
    if (page.chapterGroups.isNotEmpty) {
      for (final ChapterGroupData group in page.chapterGroups) {
        chapterWidgets.add(
          Text(
            group.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        );
        chapterWidgets.add(const SizedBox(height: 12));
        chapterWidgets.add(
          _ChapterGrid(
            chapters: group.chapters,
            onTap: (String href) => _openDetailChapter(page, href),
            downloadedChapterPathKeys: downloadedChapterKeys,
            lastReadChapterPathKey: lastReadChapterPathKey,
          ),
        );
        chapterWidgets.add(const SizedBox(height: 18));
      }
    } else if (page.chapters.isNotEmpty) {
      chapterWidgets.add(
        _ChapterGrid(
          chapters: page.chapters,
          onTap: (String href) => _openDetailChapter(page, href),
          downloadedChapterPathKeys: downloadedChapterKeys,
          lastReadChapterPathKey: lastReadChapterPathKey,
        ),
      );
    }

    sections.add(
      _SurfaceBlock(
        title: '章節目錄',
        actionLabel: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? '选择下载'
            : null,
        onActionTap: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? () => _showDetailDownloadPicker(page)
            : null,
        child: chapterWidgets.isEmpty
            ? const Text('章節還在整理中，向下刷新可重試。')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: chapterWidgets,
              ),
      ),
    );

    return sections;
  }

  List<Widget> _buildMessageSections(String message) {
    return <Widget>[
      AppSurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            const Icon(Icons.layers_clear_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _loadHome, child: const Text('回到首頁')),
          ],
        ),
      ),
    ];
  }

  Future<void> _showReaderSettingsSheet() async {
    if (_isReaderSettingsOpen) {
      return;
    }
    _isReaderSettingsOpen = true;
    _scheduleReaderPresentationSync();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: _buildReaderSettingsSheet,
    );
    _isReaderSettingsOpen = false;
    if (mounted) {
      _scheduleReaderPresentationSync();
    }
  }

  void _toggleReaderChapterControls() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isReaderChapterControlsVisible = !_isReaderChapterControlsVisible;
    });
  }

  void _hideReaderChapterControls() {
    if (!mounted || !_isReaderChapterControlsVisible) {
      return;
    }
    setState(() {
      _isReaderChapterControlsVisible = false;
    });
  }

  void _handleReaderTapUp(TapUpDetails details) {
    final BuildContext? viewportContext = _readerViewportKey.currentContext;
    final RenderBox? renderBox =
        viewportContext?.findRenderObject() as RenderBox?;
    final double viewportHeight = renderBox != null && renderBox.hasSize
        ? renderBox.size.height
        : details.localPosition.dy * 2;
    if (details.localPosition.dy <= viewportHeight * 0.5) {
      _hideReaderChapterControls();
      unawaited(_showReaderSettingsSheet());
      return;
    }
    _toggleReaderChapterControls();
  }

  Widget _buildReaderSettingsSheet(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return AnimatedBuilder(
      animation: _preferencesController,
      builder: (BuildContext context, Widget? _) {
        final ReaderPreferences preferences = _readerPreferences;
        return SafeArea(
          child: SizedBox(
            key: const ValueKey<String>('reader-settings-sheet'),
            height: maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
                          child: Text(
                            '菜单',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SettingsSection(
                          children: <Widget>[
                            SettingsSelectRow<ReaderScreenOrientation>(
                              label: '屏幕方向',
                              value: preferences.screenOrientation,
                              items: ReaderScreenOrientation.values
                                  .map((ReaderScreenOrientation value) {
                                    return DropdownMenuItem<
                                      ReaderScreenOrientation
                                    >(
                                      value: value,
                                      child: Text(
                                        value ==
                                                ReaderScreenOrientation.portrait
                                            ? '竖屏'
                                            : '横屏',
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                              onChanged: (ReaderScreenOrientation? value) {
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(screenOrientation: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSelectRow<ReaderReadingDirection>(
                              label: '阅读方向',
                              value: preferences.readingDirection,
                              items: ReaderReadingDirection.values
                                  .map((ReaderReadingDirection value) {
                                    return DropdownMenuItem<
                                      ReaderReadingDirection
                                    >(
                                      value: value,
                                      child: Text(switch (value) {
                                        ReaderReadingDirection.topToBottom =>
                                          '从上到下',
                                        ReaderReadingDirection.leftToRight =>
                                          '从左到右',
                                        ReaderReadingDirection.rightToLeft =>
                                          '从右到左',
                                      }),
                                    );
                                  })
                                  .toList(growable: false),
                              onChanged: (ReaderReadingDirection? value) {
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(readingDirection: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSelectRow<ReaderPageFit>(
                              label: '页面缩放',
                              value: preferences.pageFit,
                              items: ReaderPageFit.values
                                  .map((ReaderPageFit value) {
                                    return DropdownMenuItem<ReaderPageFit>(
                                      value: value,
                                      child: Text(
                                        value == ReaderPageFit.fitWidth
                                            ? '匹配宽度'
                                            : '适应屏幕',
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                              onChanged: (ReaderPageFit? value) {
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(pageFit: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSelectRow<ReaderOpeningPosition>(
                              label: '开页位置',
                              value: preferences.openingPosition,
                              items: ReaderOpeningPosition.values
                                  .map((ReaderOpeningPosition value) {
                                    return DropdownMenuItem<
                                      ReaderOpeningPosition
                                    >(
                                      value: value,
                                      child: Text(
                                        value == ReaderOpeningPosition.top
                                            ? '顶部'
                                            : '中心',
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                              onChanged: (ReaderOpeningPosition? value) {
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(openingPosition: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSliderRow(
                              label:
                                  '自动翻页(${preferences.autoPageTurnSeconds}秒)',
                              value: preferences.autoPageTurnSeconds.toDouble(),
                              max: 10,
                              divisions: 10,
                              onChanged: (double value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(
                                              autoPageTurnSeconds: value
                                                  .round(),
                                            ),
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SettingsSection(
                          children: <Widget>[
                            SettingsSwitchRow(
                              label: '屏幕常亮',
                              value: preferences.keepScreenOn,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(keepScreenOn: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSwitchRow(
                              label: '显示时钟',
                              value: preferences.showClock,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(showClock: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSwitchRow(
                              label: '显示进度',
                              value: preferences.showProgress,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(showProgress: value),
                                      ),
                                );
                              },
                            ),
                            if (_readerPlatformBridge.isAndroidSupported)
                              SettingsSwitchRow(
                                label: '显示电量',
                                value: preferences.showBattery,
                                onChanged: (bool value) {
                                  unawaited(
                                    _preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(showBattery: value),
                                        ),
                                  );
                                },
                              ),
                            SettingsSwitchRow(
                              label: '显示页面间隔',
                              value: preferences.showPageGap,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(showPageGap: value),
                                      ),
                                );
                              },
                            ),
                            if (_readerPlatformBridge.isAndroidSupported)
                              SettingsSwitchRow(
                                label: '使用音量键翻页',
                                value: preferences.useVolumeKeysForPaging,
                                onChanged: (bool value) {
                                  unawaited(
                                    _preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(
                                                useVolumeKeysForPaging: value,
                                              ),
                                        ),
                                  );
                                },
                              ),
                            SettingsSwitchRow(
                              label: '全屏',
                              value: preferences.fullscreen,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(fullscreen: value),
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ScrollController _readerPageScrollControllerFor(int pageIndex) {
    return _readerPageScrollControllers.putIfAbsent(pageIndex, () {
      final ScrollController controller = ScrollController();
      controller.addListener(() => _handleReaderPagedInnerScroll(pageIndex));
      return controller;
    });
  }

  Widget _buildReaderOverlay(BuildContext context, ReaderPageData page) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (_readerPreferences.showClock)
            Positioned(
              left: 12,
              top: viewPadding.top + 12,
              child: _ReaderStatusPill(
                label: _readerClockLabel(),
                icon: Icons.schedule_rounded,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.88),
                foregroundColor: colorScheme.onSurface,
              ),
            ),
          if (_readerPlatformBridge.isAndroidSupported &&
              _readerPreferences.showBattery)
            Positioned(
              right: 12,
              top: viewPadding.top + 12,
              child: _ReaderStatusPill(
                label: _batteryLevel == null ? '--%' : '${_batteryLevel!}%',
                icon: Icons.battery_std_rounded,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.88),
                foregroundColor: colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  String _readerClockLabel() {
    final DateTime now = DateTime.now();
    final String hour = now.hour.toString().padLeft(2, '0');
    final String minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _readerPageCountLabel(ReaderPageData page) {
    if (page.imageUrls.isEmpty) {
      return '-- / --';
    }
    if (_readerPreferences.isPaged) {
      return '${_currentReaderPageIndex + 1} / ${page.imageUrls.length}';
    }
    final int visibleIndex = _currentVisibleReaderImageIndex.clamp(
      0,
      page.imageUrls.length - 1,
    );
    return '${visibleIndex + 1} / ${page.imageUrls.length}';
  }

  Widget _buildReaderChapterControls(
    BuildContext context,
    ReaderPageData page,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: page.prevHref.isEmpty
                  ? null
                  : () => _navigateToHref(page.prevHref),
              child: const Text('上一话'),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88, maxWidth: 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_readerPreferences.showProgress)
                  Text(
                    _readerPageCountLabel(page),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                if (page.chapterTitle.isNotEmpty) ...<Widget>[
                  SizedBox(height: _readerPreferences.showProgress ? 2 : 0),
                  Text(
                    page.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.66),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: page.nextHref.isEmpty
                  ? null
                  : () => _navigateToHref(page.nextHref),
              child: const Text('下一话'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderChapterControlsOverlay(
    BuildContext context,
    ReaderPageData page,
  ) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final double horizontalPadding = _readerPreferences.showPageGap ? 12 : 0;
    final double bottomPadding =
        (viewPadding.bottom > 0 ? viewPadding.bottom : 0) + 12;
    return Positioned(
      left: horizontalPadding,
      right: horizontalPadding,
      bottom: bottomPadding,
      child: IgnorePointer(
        ignoring: !_isReaderChapterControlsVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: _isReaderChapterControlsVisible
              ? Offset.zero
              : const Offset(0, 1.08),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: _isReaderChapterControlsVisible ? 1 : 0,
            child: _buildReaderChapterControls(context, page),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderScrollableContent(
    BuildContext context,
    ReaderPageData page,
  ) {
    final bool showGap = _readerPreferences.showPageGap;
    final double topPadding = _readerPreferences.fullscreen && showGap ? 0 : 8;
    return RefreshIndicator(
      onRefresh: _retryCurrentPage,
      child: ListView.builder(
        key: ValueKey<String>(
          'reader-scroll-${page.uri}-${_readerPreferences.pageFit.name}-$showGap',
        ),
        controller: _readerScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: showGap
            ? EdgeInsets.fromLTRB(12, topPadding, 12, 16)
            : const EdgeInsets.only(bottom: 16),
        itemCount: page.imageUrls.length,
        itemBuilder: (BuildContext context, int index) {
          return Padding(
            key: _readerImageItemKeyFor(index),
            padding: EdgeInsets.only(bottom: showGap ? 10 : 0),
            child: _buildReaderImageFrame(
              context,
              imageUrl: page.imageUrls[index],
              viewportHeight:
                  _readerPreferences.pageFit == ReaderPageFit.fitScreen
                  ? MediaQuery.sizeOf(context).height * 0.72
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderPagedContent(BuildContext context, ReaderPageData page) {
    final bool reverse =
        _readerPreferences.readingDirection ==
        ReaderReadingDirection.rightToLeft;
    final double topPadding =
        _readerPreferences.fullscreen && _readerPreferences.showPageGap ? 0 : 8;
    return PageView.builder(
      key: ValueKey<String>(
        'reader-paged-${page.uri}-${_readerPreferences.readingDirection.name}-${_readerPreferences.pageFit.name}-${_readerPreferences.showPageGap}',
      ),
      controller: _readerPageController,
      reverse: reverse,
      itemCount: page.imageUrls.length,
      onPageChanged: _handleReaderPageChanged,
      itemBuilder: (BuildContext context, int index) {
        final ScrollController scrollController =
            _readerPageScrollControllerFor(index);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Padding(
              padding: _readerPreferences.showPageGap
                  ? EdgeInsets.fromLTRB(12, topPadding, 12, 8)
                  : EdgeInsets.zero,
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: _buildReaderImageFrame(
                    context,
                    imageUrl: page.imageUrls[index],
                    viewportHeight:
                        _readerPreferences.pageFit == ReaderPageFit.fitScreen
                        ? constraints.maxHeight
                        : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReaderImageFrame(
    BuildContext context, {
    required String imageUrl,
    double? viewportHeight,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool showGap = _readerPreferences.showPageGap;
    final double borderRadius = showGap ? 22 : 0;
    final BoxFit fit = _readerPreferences.pageFit == ReaderPageFit.fitWidth
        ? BoxFit.fitWidth
        : BoxFit.contain;
    final Uri? parsedUri = Uri.tryParse(imageUrl);
    final bool isLocalFile = parsedUri != null && parsedUri.scheme == 'file';
    final Widget image = isLocalFile
        ? Image.file(
            File.fromUri(parsedUri),
            fit: fit,
            width: double.infinity,
            height: viewportHeight,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) {
                  return SizedBox(
                    height: viewportHeight ?? 220,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 36),
                    ),
                  );
                },
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: fit,
            width: double.infinity,
            height: viewportHeight,
            cacheManager: EasyCopyImageCaches.readerCache,
            progressIndicatorBuilder:
                (BuildContext context, String url, DownloadProgress progress) {
                  return SizedBox(
                    height: viewportHeight ?? 260,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.progress,
                      ),
                    ),
                  );
                },
            errorWidget: (BuildContext context, String url, Object error) {
              return SizedBox(
                height: viewportHeight ?? 220,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 36),
                ),
              );
            },
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: showGap
            ? colorScheme.surface
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: image,
      ),
    );
  }

  Widget _buildReaderMode(BuildContext context, ReaderPageData page) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SizedBox(
        key: _readerViewportKey,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: _handleReaderTapUp,
                child: _readerPreferences.isPaged
                    ? _buildReaderPagedContent(context, page)
                    : _buildReaderScrollableContent(context, page),
              ),
            ),
            _buildReaderOverlay(context, page),
            _buildReaderChapterControlsOverlay(context, page),
          ],
        ),
      ),
    );
  }
}

class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      title: title,
      action: actionLabel != null && onActionTap != null
          ? TextButton(onPressed: onActionTap, child: Text(actionLabel!))
          : null,
      child: child,
    );
  }
}

class _ReaderStatusPill extends StatelessWidget {
  const _ReaderStatusPill({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _AppliedReaderEnvironment {
  const _AppliedReaderEnvironment.standard()
    : orientation = ReaderScreenOrientation.portrait,
      fullscreen = false,
      keepScreenOn = false,
      volumePagingEnabled = false,
      isReader = false;

  const _AppliedReaderEnvironment.reader({
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
    return other is _AppliedReaderEnvironment &&
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

class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF18222D) : const Color(0xFF102038),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _NetworkImageBox(imageUrl: banner.imageUrl, aspectRatio: 1),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: isDark
                      ? const <Color>[Color(0xDD0D1117), Color(0x550D1117)]
                      : const <Color>[Color(0xCC0F1320), Color(0x330F1320)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBannerCard extends StatelessWidget {
  const _FeatureBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    colorScheme.surfaceContainerHigh,
                    colorScheme.surfaceContainerHighest,
                  ]
                : const <Color>[Color(0xFFFFEEE1), Color(0xFFFFD1B8)],
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '专题精选',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? colorScheme.secondary
                          : const Color(0xFF995630),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 116,
              height: 116,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _NetworkImageBox(
                  imageUrl: banner.imageUrl,
                  aspectRatio: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.group,
    required this.onTap,
    this.actionLabel,
    this.onActionTap,
  });

  final FilterGroupData group;
  final ValueChanged<String> onTap;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (actionLabel != null && onActionTap != null)
                TextButton(
                  onPressed: onActionTap,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: group.options
              .map(
                (LinkAction option) => _LinkChip(
                  label: option.label,
                  active: option.active,
                  onTap: () => onTap(option.href),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _RankFilterGroup extends StatelessWidget {
  const _RankFilterGroup({
    required this.label,
    required this.items,
    required this.onTap,
  });

  final String label;
  final List<LinkAction> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (LinkAction item) => _LinkChip(
                  label: item.label,
                  active: item.active,
                  onTap: () => onTap(item.href),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color backgroundColor = active
        ? colorScheme.primaryContainer.withValues(alpha: 0.76)
        : colorScheme.surfaceContainerLow;
    final Color borderColor = active
        ? colorScheme.primary.withValues(alpha: 0.82)
        : colorScheme.outlineVariant;
    final Color textColor = active
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: active ? FontWeight.w800 : FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PagerCard extends StatelessWidget {
  const _PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: onPrev,
              child: const Text('上一页'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                Text(
                  pager.currentLabel.isEmpty ? '--' : pager.currentLabel,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (pager.totalLabel.isNotEmpty)
                  Text(
                    pager.totalLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.64),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FilledButton(onPressed: onNext, child: const Text('下一页')),
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.item, required this.onTap});

  final RankEntryData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final IconData trendIcon;
    final Color trendColor;
    switch (item.trend) {
      case 'up':
        trendIcon = Icons.trending_up_rounded;
        trendColor = const Color(0xFF18A558);
      case 'down':
        trendIcon = Icons.trending_down_rounded;
        trendColor = const Color(0xFFD64545);
      default:
        trendIcon = Icons.trending_flat_rounded;
        trendColor = const Color(0xFF7A8494);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.secondary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                item.rankLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              height: 112,
              child: _NetworkImageBox(
                imageUrl: item.coverUrl,
                aspectRatio: 0.72,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.authors.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.authors,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.heat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.78,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: trendColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(trendIcon, size: 16, color: trendColor),
                            const SizedBox(width: 4),
                            Text(
                              item.trend,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeroCard extends StatelessWidget {
  const _DetailHeroCard({
    required this.page,
    required this.onReadNow,
    required this.onDownload,
    required this.onTagTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
  final VoidCallback? onDownload;
  final ValueChanged<String> onTagTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 122,
                child: _NetworkImageBox(
                  imageUrl: page.coverUrl,
                  aspectRatio: 0.72,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      page.title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (page.authors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        page.authors,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: page.tags
                          .take(6)
                          .map(
                            (LinkAction tag) => _LinkChip(
                              label: tag.label,
                              active: false,
                              onTap: () => onTagTap(tag.href),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReadNow,
                  icon: const Icon(Icons.chrome_reader_mode_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('缓存章节'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({
    required this.chapters,
    required this.onTap,
    this.downloadedChapterPathKeys = const <String>{},
    this.lastReadChapterPathKey = '',
  });

  final List<ChapterData> chapters;
  final ValueChanged<String> onTap;
  final Set<String> downloadedChapterPathKeys;
  final String lastReadChapterPathKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    const Color lastReadColor = Color(0xFF1F4B99);
    const Color lastReadBorderColor = Color(0xFF173872);
    final bool showsLastReadState = lastReadChapterPathKey.isNotEmpty;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: showsLastReadState ? 2.15 : 2.42,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ChapterData chapter = chapters[index];
        final String chapterPathKey = Uri.tryParse(chapter.href) == null
            ? ''
            : Uri(path: Uri.parse(chapter.href).path).toString();
        final bool isDownloaded = downloadedChapterPathKeys.contains(
          chapterPathKey,
        );
        final bool isLastRead =
            lastReadChapterPathKey.isNotEmpty &&
            chapterPathKey == lastReadChapterPathKey;
        return InkWell(
          onTap: () => onTap(chapter.href),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isLastRead
                  ? lastReadColor
                  : isDownloaded
                  ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: isLastRead
                  ? Border.all(color: lastReadBorderColor, width: 1.2)
                  : isDownloaded
                  ? Border.all(color: const Color(0xFF18A558))
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        chapter.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: isLastRead ? Colors.white : null,
                        ),
                      ),
                      if (isLastRead) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '上次看到这里',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.84),
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isLastRead || isDownloaded) ...<Widget>[
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (isLastRead)
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      if (isDownloaded) ...<Widget>[
                        if (isLastRead) const SizedBox(height: 4),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF18A558),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CachedComicCard extends StatelessWidget {
  const _CachedComicCard({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

  final CachedComicLibraryEntry item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  item.coverUrl.isEmpty
                      ? const _PlaceholderImage()
                      : CachedNetworkImage(
                          imageUrl: item.coverUrl,
                          fit: BoxFit.cover,
                          cacheManager: EasyCopyImageCaches.coverCache,
                          errorWidget:
                              (BuildContext context, String url, Object error) {
                                return const _PlaceholderImage();
                              },
                        ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.cachedChapterCount}话',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (onDelete != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: onDelete,
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.comicTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (item.chapters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '最近缓存：${item.chapters.first.chapterTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.64),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterPickerSection {
  const _ChapterPickerSection({required this.label, required this.chapters});

  final String label;
  final List<ChapterData> chapters;
}

class _AdjacentChapterLinks {
  const _AdjacentChapterLinks({this.prevHref = '', this.nextHref = ''});

  final String prevHref;
  final String nextHref;
}

class _CachedChapterNavigationContext {
  const _CachedChapterNavigationContext({
    this.prevHref = '',
    this.nextHref = '',
    this.catalogHref = '',
  });

  final String prevHref;
  final String nextHref;
  final String catalogHref;

  bool get hasAnyValue =>
      prevHref.trim().isNotEmpty ||
      nextHref.trim().isNotEmpty ||
      catalogHref.trim().isNotEmpty;
}

class _NetworkImageBox extends StatelessWidget {
  const _NetworkImageBox({required this.imageUrl, required this.aspectRatio});

  final String imageUrl;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: imageUrl.isEmpty
            ? const _PlaceholderImage()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                cacheManager: EasyCopyImageCaches.coverCache,
                errorWidget: (BuildContext context, String url, Object error) {
                  return const _PlaceholderImage();
                },
              ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: colorScheme.onSurface.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}
