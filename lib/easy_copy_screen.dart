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
import 'package:easy_copy/services/display_mode_service.dart';
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
import 'package:easy_copy/services/tab_activation_policy.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:easy_copy/widgets/comic_grid.dart';
import 'package:easy_copy/widgets/native_login_screen.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'easy_copy_screen/reader_state.dart';
part 'easy_copy_screen/standard_mode.dart';
part 'easy_copy_screen/reader_mode.dart';
part 'easy_copy_screen/widgets.dart';

const Duration _pageFadeTransitionDuration = Duration(milliseconds: 200);
const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const String _detailAllChapterTabKey = '__detail_all__';

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
  bool _isReaderExitTransitionActive = false;
  bool _readerPresentationSyncScheduled = false;
  bool _suspendStandardScrollTracking = false;
  String _selectedDetailChapterTabKey = _detailAllChapterTabKey;
  bool _isDetailChapterSortAscending = false;
  String _detailChapterStateRouteKey = '';
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
  final Map<String, GlobalKey> _detailChapterItemKeys = <String, GlobalKey>{};
  String _handledDetailAutoScrollSignature = '';
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<ReaderVolumeKeyAction>? _volumeKeySubscription;
  final StandardPageLoadController<EasyCopyPage> _standardPageLoadController =
      StandardPageLoadController<EasyCopyPage>();
  NavigationIntent? _nextFreshNavigationIntent;
  bool? _nextFreshPreserveCurrentPage;
  int? _nextFreshTargetTabIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    unawaited(DisplayModeService.requestHighRefreshRate());
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DisplayModeService.requestHighRefreshRate());
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

  void _setStateIfMounted([VoidCallback? mutation]) {
    if (!mounted) {
      return;
    }
    setState(mutation ?? () {});
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
        switchToTab: _shouldActivateAsyncResultTab(pendingLoad.targetTabIndex),
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
    required int targetTabIndex,
    required NavigationIntent intent,
    required bool preserveVisiblePage,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex = targetTabIndex;
    final bool shouldActivateTab = shouldActivateTargetTab(
      currentSelectedIndex: _selectedIndex,
      targetTabIndex: tabIndex,
      phase: TabActivationPhase.navigationRequest,
    );
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
    final int targetTabIndex =
        _nextFreshTargetTabIndex ?? resolveNavigationTabIndex(targetUri);
    final StandardPageLoadHandle<EasyCopyPage> pendingLoad =
        StandardPageLoadHandle<EasyCopyPage>(
          requestedUri: targetUri,
          queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
          intent: _nextFreshNavigationIntent ?? NavigationIntent.preserve,
          preserveCurrentPage: preserveCurrentPage,
          loadId: loadId,
          targetTabIndex: targetTabIndex,
          completer: Completer<EasyCopyPage>(),
        );
    _nextFreshNavigationIntent = null;
    _nextFreshPreserveCurrentPage = null;
    _nextFreshTargetTabIndex = null;
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
      _tabSessionStore.updatePage(tabIndex, page);
      if (page is DetailPageData) {
        _syncDetailChapterState(
          page,
          forceReset:
              previousPage is! DetailPageData || previousPage.uri != page.uri,
        );
      }
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
    int? sourceTabIndex,
    int? targetTabIndexOverride,
    _CachedChapterNavigationContext cachedChapterContext =
        const _CachedChapterNavigationContext(),
  }) async {
    _persistVisiblePageState();
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
        targetTabIndex: resolvedTargetTabIndex,
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
      targetTabIndex: resolvedTargetTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    if (!bypassCache) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (cachedHit != null) {
        if (!_shouldBypassUnknownCache(targetUri, cachedHit.page)) {
          _applyLoadedPage(
            cachedHit.page,
            targetTabIndex: targetTabIndex,
            switchToTab: _shouldActivateAsyncResultTab(targetTabIndex),
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
    }

    _nextFreshNavigationIntent = historyMode;
    _nextFreshPreserveCurrentPage = preserveVisiblePage;
    _nextFreshTargetTabIndex = targetTabIndex;
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
      _nextFreshTargetTabIndex = null;
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
      _nextFreshTargetTabIndex = targetTabIndex;
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
          switchToTab: _shouldActivateAsyncResultTab(targetTabIndex),
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
      _nextFreshTargetTabIndex = null;
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
    const int profileTabIndex = 3;
    final int targetTabIndex = _prepareRouteEntry(
      profileUri,
      targetTabIndex: profileTabIndex,
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
          switchToTab: _shouldActivateAsyncResultTab(targetTabIndex),
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
        switchToTab: _shouldActivateAsyncResultTab(targetTabIndex),
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
    required int targetTabIndex,
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
    final int preparedTabIndex = _prepareRouteEntry(
      Uri.parse(cachedPage.uri),
      targetTabIndex: targetTabIndex,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    _applyLoadedPage(
      cachedPage,
      targetTabIndex: preparedTabIndex,
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
    if (_isReaderMode) {
      await _runReaderExitTransition(() async {
        await _handleReaderAwareBackNavigation();
      });
      return;
    }
    await _handleReaderAwareBackNavigation();
  }

  Future<void> _handleReaderAwareBackNavigation() async {
    _persistVisiblePageState();
    final EasyCopyPage? page = _page;
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
        sourceTabIndex: _selectedIndex,
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
        sourceTabIndex: _selectedIndex,
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
}
