import 'dart:async';
import 'dart:math' as math;

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/chapter_comment.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/reader/internal/reader_environment.dart';
import 'package:easy_copy/reader/internal/reader_restore_target.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/deferred_viewport_coordinator.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/local_library_store.dart';
import 'package:easy_copy/services/reader_comment_utils.dart';
import 'package:easy_copy/services/reader_history_recorder.dart';
import 'package:easy_copy/services/reader_platform_bridge.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

const double _readerNextChapterPullTriggerDistance = 266;
const double _readerNextChapterPagedTriggerDistance = 152;
const double _readerNextChapterPullActivationExtent = 100;

typedef ReaderChapterNavigationCallback =
    Future<void> Function(
      String href, {
      String prevHref,
      String nextHref,
      String catalogHref,
    });

String readerChapterIdForPage(ReaderPageData page) {
  final Uri uri = Uri.parse(page.uri);
  final List<String> segments = uri.pathSegments;
  final int chapterIndex = segments.indexOf('chapter');
  if (chapterIndex < 0 || chapterIndex + 1 >= segments.length) {
    return '';
  }
  return segments[chapterIndex + 1].trim();
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.preferencesController,
    required this.progressStore,
    required this.platformBridge,
    required this.apiClient,
    required this.session,
    required this.localLibraryStore,
    required this.historyRecorder,
    required this.onRequestChapterNavigation,
    required this.onRequestAuth,
    required this.onLogoutForExpiredSession,
    required this.onShowMessage,
  });

  final AppPreferencesController preferencesController;
  final ReaderProgressStore progressStore;
  final ReaderPlatformBridge platformBridge;
  final SiteApiClient apiClient;
  final SiteSession session;
  final LocalLibraryStore localLibraryStore;
  final ReaderHistoryRecorder historyRecorder;
  final ReaderChapterNavigationCallback onRequestChapterNavigation;
  final Future<void> Function() onRequestAuth;
  final Future<void> Function() onLogoutForExpiredSession;
  final void Function(String message) onShowMessage;

  PageController pageController = PageController();
  final ScrollController scrollController = ScrollController();
  final TextEditingController commentController = TextEditingController();
  final ScrollController commentScrollController = ScrollController();
  final GlobalKey viewportKey = GlobalKey();
  final Map<int, ScrollController> _pagedScrollControllers =
      <int, ScrollController>{};
  final Map<int, GlobalKey> _imageItemKeys = <int, GlobalKey>{};
  final Map<String, double> _imageAspectRatios = <String, double>{};
  final Set<String> _zoomedImageKeys = <String>{};
  final DeferredViewportCoordinator restoreCoordinator =
      DeferredViewportCoordinator();

  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<ReaderVolumeKeyAction>? _volumeKeySubscription;
  Timer? _progressDebounce;
  Timer? _autoTurnTimer;
  Timer? _clockTimer;
  bool _disposed = false;

  ReaderPageData? _page;
  int _currentPageIndex = 0;
  int _visibleImageIndex = 0;
  ReaderPosition? _lastPersistedPosition;
  AppliedReaderEnvironment? _appliedEnvironment;
  ReaderPreferences? _lastObservedPreferences;
  bool _presentationSyncScheduled = false;

  bool _isSettingsOpen = false;
  bool _isChapterControlsVisible = false;
  bool _isNextChapterLoading = false;
  bool _isScaleGestureActive = false;

  double _zoomScale = 1.0;
  double _zoomBaseScale = 1.0;
  double _panOffsetX = 0;
  double _panOffsetY = 0;

  double _previousChapterPullDistance = 0;
  double _nextChapterPullDistance = 0;

  List<ChapterComment> _chapterComments = const <ChapterComment>[];
  String _commentsChapterId = '';
  String _commentsError = '';
  int _commentsTotal = 0;
  int _commentsLoadedStartOffset = 0;
  bool _isCommentsLoading = false;
  bool _isCommentsLoadingMore = false;
  bool _isCommentSubmitting = false;

  int? _batteryLevel;

  ReaderPageData? get page => _page;

  ReaderPreferences get preferences => preferencesController.readerPreferences;

  int get currentPageIndex => _currentPageIndex;

  int get visibleImageIndex => _visibleImageIndex;

  ReaderPosition? get lastPersistedPosition => _lastPersistedPosition;

  AppliedReaderEnvironment? get appliedEnvironment => _appliedEnvironment;

  bool get isSettingsOpen => _isSettingsOpen;

  bool get isChapterControlsVisible => _isChapterControlsVisible;

  bool get isNextChapterLoading => _isNextChapterLoading;

  bool get isScaleGestureActive => _isScaleGestureActive;

  bool get isZoomGestureLocked =>
      _isScaleGestureActive || _zoomedImageKeys.isNotEmpty;

  double get zoomScale => _zoomScale;

  double get panOffsetX => _panOffsetX;

  double get panOffsetY => _panOffsetY;

  double get previousChapterPullDistance => _previousChapterPullDistance;

  double get nextChapterPullDistance => _nextChapterPullDistance;

  bool get previousChapterPullReady =>
      _previousChapterPullDistance >= _nextChapterTriggerDistance;

  bool get nextChapterPullReady =>
      _nextChapterPullDistance >= _nextChapterTriggerDistance;

  double get _nextChapterTriggerDistance => preferences.isPaged
      ? _readerNextChapterPagedTriggerDistance
      : _readerNextChapterPullTriggerDistance;

  List<ChapterComment> get chapterComments => _chapterComments;

  String get commentsChapterId => _commentsChapterId;

  String get commentsError => _commentsError;

  int get commentsTotal => _commentsTotal;

  bool get isCommentsLoading => _isCommentsLoading;

  bool get isCommentsLoadingMore => _isCommentsLoadingMore;

  bool get isCommentSubmitting => _isCommentSubmitting;

  int? get batteryLevel => _batteryLevel;

  Map<String, double> get imageAspectRatios => _imageAspectRatios;

  ScrollController pagedScrollControllerFor(int pageIndex) {
    return _pagedScrollControllers.putIfAbsent(pageIndex, () {
      final ScrollController controller = ScrollController();
      controller.addListener(() => _handlePagedInnerScroll(pageIndex));
      return controller;
    });
  }

  GlobalKey imageItemKeyFor(int index) {
    return _imageItemKeys.putIfAbsent(index, GlobalKey.new);
  }

  bool shouldShowCommentTailPage(ReaderPageData page) {
    return preferences.showChapterComments &&
        readerChapterIdForPage(page).isNotEmpty;
  }

  int readerPagedPageCount(ReaderPageData page) {
    return page.imageUrls.length + (shouldShowCommentTailPage(page) ? 1 : 0);
  }

  ReaderRestoreTarget? captureCurrentRestoreTarget(
    ReaderPageData page, {
    required ReaderPreferences preferences,
  }) {
    if (preferences.isPaged) {
      final int maxPageIndex = math.max(0, readerPagedPageCount(page) - 1);
      final int pageIndex = _currentPageIndex.clamp(0, maxPageIndex);
      final ScrollController? controller = _pagedScrollControllers[pageIndex];
      return ReaderRestoreTarget(
        position: ReaderPosition.paged(
          pageIndex: pageIndex,
          pageOffset: controller != null && controller.hasClients
              ? controller.offset
              : 0,
        ),
        visibleImageIndex: page.imageUrls.isEmpty
            ? null
            : (pageIndex >= page.imageUrls.length
                  ? page.imageUrls.length - 1
                  : pageIndex),
      );
    }
    final double? offset = scrollController.hasClients
        ? scrollController.offset
        : null;
    return ReaderRestoreTarget(
      position: offset == null ? null : ReaderPosition.scroll(offset: offset),
      visibleImageIndex: page.imageUrls.isEmpty
          ? null
          : _visibleImageIndex.clamp(0, page.imageUrls.length - 1),
    );
  }

  void attachPlatformSubscriptions() {
    if (platformBridge.isAndroidSupported) {
      _batterySubscription = platformBridge.batteryStream.listen((int level) {
        if (_disposed || _batteryLevel == level) {
          return;
        }
        _batteryLevel = level;
        notifyListeners();
      });
      _volumeKeySubscription = platformBridge.volumeKeyEventStream.listen(
        _handleVolumeKeyAction,
      );
    }
    scrollController.addListener(_handleScroll);
    commentScrollController.addListener(_handleCommentScroll);
    preferencesController.addListener(_handlePreferencesChanged);
    _lastObservedPreferences = preferencesController.readerPreferences;
  }

  void setPage(
    ReaderPageData page, {
    String? previousUri,
    bool forceRestore = false,
    ReaderRestoreTarget? preferredRestoreTarget,
  }) {
    _page = page;
    _handlePageLoaded(
      page,
      previousUri: previousUri,
      forceRestore: forceRestore,
      preferredRestoreTarget: preferredRestoreTarget,
    );
    notifyListeners();
  }

  Future<void> flushProgressPersistence() async {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    await _persistCurrentProgress();
  }

  Future<void> restoreDefaultEnvironment() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await platformBridge.setKeepScreenOn(false);
    await platformBridge.setVolumePagingEnabled(false);
    _appliedEnvironment = const AppliedReaderEnvironment.standard();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressDebounce?.cancel();
    _autoTurnTimer?.cancel();
    _clockTimer?.cancel();
    _batterySubscription?.cancel();
    _volumeKeySubscription?.cancel();
    preferencesController.removeListener(_handlePreferencesChanged);
    scrollController.removeListener(_handleScroll);
    commentScrollController.removeListener(_handleCommentScroll);
    final List<ScrollController> pagedControllers = _pagedScrollControllers
        .values
        .toList(growable: false);
    _pagedScrollControllers.clear();
    for (final ScrollController controller in pagedControllers) {
      controller.dispose();
    }
    pageController.dispose();
    scrollController.dispose();
    commentController.dispose();
    commentScrollController.dispose();
    super.dispose();
  }

  void toggleChapterControls() {
    if (_disposed) return;
    _isChapterControlsVisible = !_isChapterControlsVisible;
    notifyListeners();
  }

  void hideChapterControls() {
    if (_disposed || !_isChapterControlsVisible) return;
    _isChapterControlsVisible = false;
    notifyListeners();
  }

  void setSettingsSheetOpen(bool open) {
    if (_isSettingsOpen == open) return;
    _isSettingsOpen = open;
    _scheduleReaderPresentationSync();
    notifyListeners();
  }

  void noteUserInteraction() {
    restoreCoordinator.noteUserInteraction();
  }

  void handlePinchZoomStart() {
    _zoomBaseScale = _zoomScale;
    _setScaleGestureActive(true);
  }

  void handlePinchZoomUpdate(double relativeScale) {
    final double newScale = (_zoomBaseScale * relativeScale).clamp(1.0, 4.0);
    if ((newScale - _zoomScale).abs() < 0.005) return;
    if (_disposed) {
      _zoomScale = newScale;
      return;
    }
    _zoomScale = newScale;
    notifyListeners();
  }

  void handlePinchZoomEnd() {
    _setScaleGestureActive(false);
    if (_zoomScale <= 1.02) {
      final bool wasLocked = isZoomGestureLocked;
      _zoomScale = 1.0;
      _panOffsetX = 0;
      _panOffsetY = 0;
      _zoomedImageKeys.remove('__viewport_zoom__');
      if (!_disposed) notifyListeners();
      _handleZoomLockChanged(wasLocked);
    } else {
      _setImageZoomed('__viewport_zoom__', true);
    }
  }

  void updatePanOffset({required double x, required double y}) {
    if (_disposed) {
      _panOffsetX = x;
      _panOffsetY = y;
      return;
    }
    _panOffsetX = x;
    _panOffsetY = y;
    notifyListeners();
  }

  void _setScaleGestureActive(bool value) {
    if (_isScaleGestureActive == value) return;
    final bool wasLocked = isZoomGestureLocked;
    _isScaleGestureActive = value;
    if (!_disposed) notifyListeners();
    _handleZoomLockChanged(wasLocked);
  }

  void _setImageZoomed(String imageKey, bool isZoomed) {
    final bool alreadyZoomed = _zoomedImageKeys.contains(imageKey);
    if (alreadyZoomed == isZoomed) return;
    final bool wasLocked = isZoomGestureLocked;
    if (isZoomed) {
      _zoomedImageKeys.add(imageKey);
    } else {
      _zoomedImageKeys.remove(imageKey);
    }
    if (!_disposed) notifyListeners();
    _handleZoomLockChanged(wasLocked);
  }

  void _resetZoomState() {
    if (!_isScaleGestureActive &&
        _zoomedImageKeys.isEmpty &&
        _zoomScale <= 1.01) {
      return;
    }
    final bool wasLocked = isZoomGestureLocked;
    _isScaleGestureActive = false;
    _zoomedImageKeys.clear();
    _zoomScale = 1.0;
    _panOffsetX = 0;
    _panOffsetY = 0;
    if (!_disposed) notifyListeners();
    _handleZoomLockChanged(wasLocked);
  }

  void _handleZoomLockChanged(bool wasLocked) {
    final bool isLocked = isZoomGestureLocked;
    if (wasLocked == isLocked) return;
    if (isLocked) {
      _autoTurnTimer?.cancel();
      _resetChapterBoundaryState();
      hideChapterControls();
      return;
    }
    _restartAutoTurn();
  }

  void handleZoomedOverscroll(ReaderPageData page, double overscrollDy) {
    final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    if (overscrollDy < -0.5 && hasNextChapter) {
      _clearPreviousChapterPullState();
      _updateNextChapterPullDistance(
        _nextChapterPullDistance + overscrollDy.abs(),
      );
    } else if (overscrollDy > 0.5 && hasPreviousChapter) {
      _clearNextChapterPullState();
      _updatePreviousChapterPullDistance(
        _previousChapterPullDistance + overscrollDy.abs(),
      );
    }
  }

  void handleZoomedPanEnd(ReaderPageData page) {
    if (previousChapterPullReady) {
      unawaited(triggerPreviousChapter(page));
    } else if (nextChapterPullReady) {
      unawaited(triggerNextChapter(page));
    } else {
      _clearPreviousChapterPullState();
      _clearNextChapterPullState();
    }
  }

  Future<void> stepForward() async {
    if (isZoomGestureLocked) return;
    restoreCoordinator.noteUserInteraction();
    if (preferences.isPaged) {
      final ReaderPageData? page = _page;
      if (page == null) return;
      final int totalPageCount = readerPagedPageCount(page);
      final int nextPageIndex = _currentPageIndex + 1;
      if (nextPageIndex >= totalPageCount) return;
      await animateToPage(nextPageIndex);
      return;
    }
    if (!scrollController.hasClients) return;
    final double viewportExtent = scrollController.position.viewportDimension;
    final double maxExtent = scrollController.position.maxScrollExtent;
    final double nextOffset = (scrollController.offset + viewportExtent)
        .clamp(0, maxExtent)
        .toDouble();
    if ((nextOffset - scrollController.offset).abs() < 1) return;
    await scrollController.animateTo(
      nextOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartAutoTurn();
  }

  Future<void> stepBackward() async {
    if (isZoomGestureLocked) return;
    restoreCoordinator.noteUserInteraction();
    if (preferences.isPaged) {
      final int previousPageIndex = _currentPageIndex - 1;
      if (previousPageIndex < 0) return;
      await animateToPage(previousPageIndex);
      return;
    }
    if (!scrollController.hasClients) return;
    final double viewportExtent = scrollController.position.viewportDimension;
    final double previousOffset = (scrollController.offset - viewportExtent)
        .clamp(0, scrollController.position.maxScrollExtent)
        .toDouble();
    if ((previousOffset - scrollController.offset).abs() < 1) return;
    await scrollController.animateTo(
      previousOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartAutoTurn();
  }

  Future<void> animateToPage(int pageIndex) async {
    if (!pageController.hasClients) return;
    await pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _restartAutoTurn();
  }

  void seekToImageIndex({
    required ReaderPageData page,
    required int imageIndex,
    required double estimatedScrollOffset,
  }) {
    if (isZoomGestureLocked || page.imageUrls.isEmpty) return;
    final int clampedIndex = imageIndex.clamp(0, page.imageUrls.length - 1);
    final DeferredViewportTicket ticket = restoreCoordinator.beginRequest();

    if (preferences.isPaged) {
      _jumpToPage(page.uri, clampedIndex, attempts: 8, ticket: ticket);
      _jumpPageOffset(
        page.uri,
        clampedIndex,
        offset: 0,
        attempts: 8,
        ticket: ticket,
      );
      return;
    }
    _jumpToOffset(page.uri, estimatedScrollOffset, attempts: 8, ticket: ticket);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToImageIndex(
        page.uri,
        clampedIndex,
        attempts: 8,
        ticket: ticket,
        alignment: 0,
      );
    });
  }

  void cancelAutoTurn() {
    _autoTurnTimer?.cancel();
    _autoTurnTimer = null;
  }

  void _scheduleReaderPresentationSync() {
    if (_presentationSyncScheduled) return;
    _presentationSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presentationSyncScheduled = false;
      if (_disposed) return;
      unawaited(_applyEnvironment(_page));
    });
  }

  Future<void> _applyEnvironment(ReaderPageData? page) async {
    final AppliedReaderEnvironment nextEnvironment = page == null
        ? const AppliedReaderEnvironment.standard()
        : AppliedReaderEnvironment.reader(
            orientation: preferences.screenOrientation,
            fullscreen: preferences.fullscreen,
            keepScreenOn: preferences.keepScreenOn,
            volumePagingEnabled:
                platformBridge.isAndroidSupported &&
                preferences.useVolumeKeysForPaging,
          );
    if (_appliedEnvironment != nextEnvironment) {
      if (page == null) {
        await restoreDefaultEnvironment();
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
        await platformBridge.setKeepScreenOn(nextEnvironment.keepScreenOn);
        await platformBridge.setVolumePagingEnabled(
          nextEnvironment.volumePagingEnabled,
        );
        _appliedEnvironment = nextEnvironment;
      }
    }

    _syncClockTicker(enabled: page != null && preferences.showClock);
    if (page == null) {
      _autoTurnTimer?.cancel();
      _autoTurnTimer = null;
      return;
    }
    _restartAutoTurn();
  }

  void _syncClockTicker({required bool enabled}) {
    if (!enabled) {
      _clockTimer?.cancel();
      _clockTimer = null;
      return;
    }
    if (_clockTimer != null) return;
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  void _restartAutoTurn() {
    _autoTurnTimer?.cancel();
    final ReaderPageData? page = _page;
    if (page == null ||
        preferences.autoPageTurnSeconds <= 0 ||
        _isSettingsOpen ||
        isZoomGestureLocked) {
      return;
    }
    _autoTurnTimer = Timer(
      Duration(seconds: preferences.autoPageTurnSeconds),
      () async {
        if (_disposed || _page == null) return;
        if (preferences.isPaged) {
          final int totalPageCount = readerPagedPageCount(page);
          final int nextPageIndex = _currentPageIndex + 1;
          if (nextPageIndex >= totalPageCount) return;
          await animateToPage(nextPageIndex);
          return;
        }
        if (!scrollController.hasClients) return;
        final double maxExtent = scrollController.position.maxScrollExtent;
        final double viewportExtent =
            scrollController.position.viewportDimension;
        final double nextOffset = (scrollController.offset + viewportExtent)
            .clamp(0, maxExtent)
            .toDouble();
        if ((nextOffset - scrollController.offset).abs() < 1) return;
        await scrollController.animateTo(
          nextOffset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        _restartAutoTurn();
      },
    );
  }

  void _handlePageLoaded(
    ReaderPageData page, {
    String? previousUri,
    bool forceRestore = false,
    ReaderRestoreTarget? preferredRestoreTarget,
  }) {
    final List<String> remoteImages = page.imageUrls
        .where((String imageUrl) {
          final Uri? uri = Uri.tryParse(imageUrl);
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
        })
        .toList(growable: false);
    unawaited(
      EasyCopyImageCaches.prefetchReaderImages(remoteImages, referer: page.uri),
    );
    unawaited(_markChapterVisited(page));
    final bool changedPage = previousUri != page.uri;
    if (changedPage || forceRestore) {
      _resetChapterBoundaryState();
      _resetZoomState();
    }
    if (changedPage) {
      _currentPageIndex = 0;
      _visibleImageIndex = 0;
      _isChapterControlsVisible = false;
      _disposePagedScrollControllers();
      _imageItemKeys.clear();
      _imageAspectRatios.clear();
      if (!preferences.isPaged && scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    }
    _prepareComments(page, resetForNewChapter: changedPage);
    _scheduleReaderPresentationSync();
    if (changedPage || forceRestore) {
      unawaited(
        _restorePosition(
          page,
          resetControllers: changedPage || forceRestore,
          preferredRestoreTarget: preferredRestoreTarget,
        ),
      );
    }
  }

  Future<void> _markChapterVisited(ReaderPageData page) {
    unawaited(historyRecorder.recordVisit(page));
    return progressStore.markChapterOpened(
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
  }

  Future<void> _restorePosition(
    ReaderPageData page, {
    required bool resetControllers,
    ReaderRestoreTarget? preferredRestoreTarget,
  }) async {
    final DeferredViewportTicket ticket = restoreCoordinator.beginRequest();
    final ReaderPosition? savedPosition = await progressStore.readPosition(
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
    if (_disposed || _page == null || _page!.uri != page.uri) return;

    final ReaderRestoreTarget restoreTarget =
        preferredRestoreTarget ?? ReaderRestoreTarget(position: savedPosition);

    if (preferences.isPaged) {
      final int maxPageIndex = math.max(0, readerPagedPageCount(page) - 1);
      final int? preferredImageIndex = restoreTarget.imageIndexFor(page);
      final ReaderPosition? sourcePosition =
          restoreTarget.position ?? savedPosition;
      final int pageIndex = sourcePosition?.isPaged == true
          ? sourcePosition!.pageIndex.clamp(0, maxPageIndex)
          : (preferredImageIndex ?? 0);
      final double? pageOffset = sourcePosition?.isPaged == true
          ? sourcePosition!.pageOffset
          : null;
      if (resetControllers) {
        _disposePagedScrollControllers();
        _replacePageController(initialPage: pageIndex);
      }
      _lastPersistedPosition = ReaderPosition.paged(
        pageIndex: pageIndex,
        pageOffset: pageOffset ?? 0,
      );
      _currentPageIndex = pageIndex;
      _visibleImageIndex = page.imageUrls.isEmpty
          ? 0
          : (pageIndex >= page.imageUrls.length
                ? page.imageUrls.length - 1
                : pageIndex);
      if (!_disposed) notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isActiveRestore(ticket, pageUri: page.uri, isPaged: true)) return;
        _jumpToPage(page.uri, pageIndex, attempts: 10, ticket: ticket);
        _jumpPageOffset(
          page.uri,
          pageIndex,
          offset: pageOffset,
          attempts: 10,
          ticket: ticket,
        );
      });
      return;
    }

    final int? restoreImageIndex = restoreTarget.imageIndexFor(page);
    final ReaderPosition? sourcePosition =
        restoreTarget.position ?? savedPosition;
    final double? savedOffset = sourcePosition?.isScroll == true
        ? sourcePosition!.offset
        : null;
    _lastPersistedPosition = savedOffset == null
        ? null
        : ReaderPosition.scroll(offset: savedOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isActiveRestore(ticket, pageUri: page.uri, isPaged: false)) return;
      if (restoreImageIndex != null) {
        _jumpToImageIndex(
          page.uri,
          restoreImageIndex,
          attempts: 10,
          ticket: ticket,
          alignment:
              preferredRestoreTarget == null &&
                  preferences.openingPosition == ReaderOpeningPosition.top
              ? 0
              : 0.5,
        );
      } else {
        _jumpToOffset(page.uri, savedOffset ?? 0, attempts: 10, ticket: ticket);
      }
      _scheduleVisibleImageIndexUpdate();
    });
  }

  bool _isActiveRestore(
    DeferredViewportTicket ticket, {
    required String pageUri,
    required bool isPaged,
  }) {
    return !_disposed &&
        restoreCoordinator.isActive(ticket) &&
        _page != null &&
        _page!.uri == pageUri &&
        preferences.isPaged == isPaged;
  }

  void _jumpToOffset(
    String pageUri,
    double? offset, {
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveRestore(ticket, pageUri: pageUri, isPaged: false)) return;
    if (!scrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpToOffset(
            pageUri,
            offset,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
      }
      return;
    }
    final double maxExtent = scrollController.position.maxScrollExtent;
    final double targetOffset =
        offset ??
        (preferences.openingPosition == ReaderOpeningPosition.center
            ? (scrollController.position.viewportDimension * 0.5)
            : 0);
    if (targetOffset > maxExtent && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 250),
        () => _jumpToOffset(
          pageUri,
          targetOffset,
          attempts: attempts - 1,
          ticket: ticket,
        ),
      );
      return;
    }
    final double clampedOffset = targetOffset.clamp(0, maxExtent).toDouble();
    scrollController.jumpTo(clampedOffset);
  }

  void _jumpToImageIndex(
    String pageUri,
    int imageIndex, {
    required int attempts,
    required DeferredViewportTicket ticket,
    required double alignment,
  }) {
    if (!_isActiveRestore(ticket, pageUri: pageUri, isPaged: false)) return;
    final BuildContext? itemContext = imageItemKeyFor(
      imageIndex,
    ).currentContext;
    if (itemContext == null) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpToImageIndex(
            pageUri,
            imageIndex,
            attempts: attempts - 1,
            ticket: ticket,
            alignment: alignment,
          ),
        );
      }
      return;
    }
    Scrollable.ensureVisible(
      itemContext,
      duration: Duration.zero,
      alignment: alignment,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _jumpToPage(
    String pageUri,
    int pageIndex, {
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveRestore(ticket, pageUri: pageUri, isPaged: true)) return;
    if (!pageController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpToPage(
            pageUri,
            pageIndex,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
      }
      return;
    }
    pageController.jumpToPage(pageIndex);
  }

  void _jumpPageOffset(
    String pageUri,
    int pageIndex, {
    required double? offset,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveRestore(ticket, pageUri: pageUri, isPaged: true)) return;
    final ScrollController? controller = _pagedScrollControllers[pageIndex];
    if (controller == null || !controller.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpPageOffset(
            pageUri,
            pageIndex,
            offset: offset,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
      }
      return;
    }
    final double maxExtent = controller.position.maxScrollExtent;
    final double targetOffset =
        offset ??
        (preferences.openingPosition == ReaderOpeningPosition.center
            ? maxExtent * 0.5
            : 0);
    controller.jumpTo(targetOffset.clamp(0, maxExtent).toDouble());
  }

  void _disposePagedScrollControllers() {
    final List<ScrollController> controllers = _pagedScrollControllers.values
        .toList(growable: false);
    _pagedScrollControllers.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ScrollController controller in controllers) {
        controller.dispose();
      }
    });
  }

  void _replacePageController({required int initialPage}) {
    final PageController previousController = pageController;
    pageController = PageController(initialPage: initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  void _handleScroll() {
    final ReaderPageData? page = _page;
    if (page == null || !scrollController.hasClients || preferences.isPaged) {
      return;
    }
    final double currentOffset = scrollController.offset;
    if (_lastPersistedPosition?.isScroll == true &&
        (currentOffset - _lastPersistedPosition!.offset).abs() < 48) {
      return;
    }
    _scheduleProgressPersistence();
    _restartAutoTurn();
    _scheduleVisibleImageIndexUpdate();
  }

  void handlePageChanged(int index) {
    if (_currentPageIndex == index) return;
    final ReaderPageData? currentPage = _page;
    final int visibleImageIndex =
        currentPage != null && currentPage.imageUrls.isNotEmpty
        ? (index >= currentPage.imageUrls.length
              ? currentPage.imageUrls.length - 1
              : index)
        : index;
    _resetChapterBoundaryState();
    _currentPageIndex = index;
    _visibleImageIndex = visibleImageIndex;
    if (!_disposed) notifyListeners();
    _scheduleProgressPersistence();
    _restartAutoTurn();
  }

  void _handlePagedInnerScroll(int pageIndex) {
    if (pageIndex != _currentPageIndex) return;
    final ScrollController? controller = _pagedScrollControllers[pageIndex];
    if (controller == null || !controller.hasClients) return;
    if (_lastPersistedPosition?.isPaged == true &&
        _lastPersistedPosition!.pageIndex == pageIndex &&
        (controller.offset - _lastPersistedPosition!.pageOffset).abs() < 32) {
      return;
    }
    _scheduleProgressPersistence();
    _restartAutoTurn();
  }

  void _scheduleVisibleImageIndexUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || preferences.isPaged) return;
      _updateVisibleImageIndex();
    });
  }

  void _updateVisibleImageIndex() {
    if (!scrollController.hasClients) return;
    final BuildContext? viewportContext = viewportKey.currentContext;
    if (viewportContext == null) return;
    final RenderObject? viewportRenderObject = viewportContext
        .findRenderObject();
    if (viewportRenderObject is! RenderBox) return;
    final double viewportTop = viewportRenderObject
        .localToGlobal(Offset.zero)
        .dy;
    final double viewportCenter =
        viewportTop + (viewportRenderObject.size.height / 2);
    int bestIndex = _visibleImageIndex;
    double bestDistance = double.infinity;
    for (final MapEntry<int, GlobalKey> entry in _imageItemKeys.entries) {
      final BuildContext? itemContext = entry.value.currentContext;
      if (itemContext == null) continue;
      final RenderObject? renderObject = itemContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final Offset topLeft = renderObject.localToGlobal(Offset.zero);
      final double centerY = topLeft.dy + (renderObject.size.height / 2);
      final double distance = (centerY - viewportCenter).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = entry.key;
      }
    }
    if (bestIndex == _visibleImageIndex) return;
    _visibleImageIndex = bestIndex;
    if (!_disposed) notifyListeners();
  }

  void recordImageAspectRatio(String imageUrl, double aspectRatio) {
    if (_imageAspectRatios[imageUrl] == aspectRatio) return;
    _imageAspectRatios[imageUrl] = aspectRatio;
    if (!_disposed) notifyListeners();
  }

  void setImageZoomed(String imageKey, bool isZoomed) =>
      _setImageZoomed(imageKey, isZoomed);

  bool _scrollControllerAtBottom(
    ScrollController controller, {
    double tolerance = 1,
  }) {
    if (!controller.hasClients) return false;
    return controller.position.maxScrollExtent - controller.position.pixels <=
        tolerance;
  }

  bool _scrollControllerAtTop(
    ScrollController controller, {
    double tolerance = 1,
  }) {
    if (!controller.hasClients) return false;
    return controller.position.pixels - controller.position.minScrollExtent <=
        tolerance;
  }

  bool _metricsNearChapterStart(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _readerNextChapterPullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentBefore <= threshold;
  }

  bool _metricsNearChapterEnd(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _readerNextChapterPullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentAfter <= threshold;
  }

  bool _isNextChapterForwardDrag(double dragDelta, {required Axis axis}) {
    if (axis == Axis.vertical) return dragDelta < 0;
    return switch (preferences.readingDirection) {
      ReaderReadingDirection.leftToRight => dragDelta < 0,
      ReaderReadingDirection.rightToLeft => dragDelta > 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  bool _isNextChapterBackwardDrag(double dragDelta, {required Axis axis}) {
    if (axis == Axis.vertical) return dragDelta > 0;
    return switch (preferences.readingDirection) {
      ReaderReadingDirection.leftToRight => dragDelta > 0,
      ReaderReadingDirection.rightToLeft => dragDelta < 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  void _updateNextChapterPullDistance(double distance) {
    final double triggerDistance = _nextChapterTriggerDistance;
    final double clampedDistance = distance
        .clamp(0, triggerDistance * 1.6)
        .toDouble();
    final bool nextReady = clampedDistance >= triggerDistance;
    if ((_nextChapterPullDistance - clampedDistance).abs() < 0.5 &&
        nextChapterPullReady == nextReady) {
      return;
    }
    _nextChapterPullDistance = clampedDistance;
    if (!_disposed) notifyListeners();
  }

  void _updatePreviousChapterPullDistance(double distance) {
    final double triggerDistance = _nextChapterTriggerDistance;
    final double clampedDistance = distance
        .clamp(0, triggerDistance * 1.6)
        .toDouble();
    final bool nextReady = clampedDistance >= triggerDistance;
    if ((_previousChapterPullDistance - clampedDistance).abs() < 0.5 &&
        previousChapterPullReady == nextReady) {
      return;
    }
    _previousChapterPullDistance = clampedDistance;
    if (!_disposed) notifyListeners();
  }

  void _clearPreviousChapterPullState() {
    if (_previousChapterPullDistance <= 0) return;
    _previousChapterPullDistance = 0;
    if (!_disposed) notifyListeners();
  }

  void _clearNextChapterPullState() {
    if (_nextChapterPullDistance <= 0) return;
    _nextChapterPullDistance = 0;
    if (!_disposed) notifyListeners();
  }

  void _resetChapterBoundaryState() {
    if (_previousChapterPullDistance <= 0 &&
        _nextChapterPullDistance <= 0 &&
        !_isNextChapterLoading) {
      return;
    }
    _previousChapterPullDistance = 0;
    _nextChapterPullDistance = 0;
    _isNextChapterLoading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> triggerPreviousChapter(ReaderPageData page) async {
    final String prevHref = page.prevHref.trim();
    if (prevHref.isEmpty || _isNextChapterLoading) {
      _clearPreviousChapterPullState();
      return;
    }
    _isNextChapterLoading = true;
    if (!_disposed) notifyListeners();
    try {
      await flushProgressPersistence();
      await onRequestChapterNavigation(
        prevHref,
        nextHref: page.uri,
        catalogHref: page.catalogHref,
      );
    } finally {
      _resetChapterBoundaryState();
    }
  }

  Future<void> triggerNextChapter(ReaderPageData page) async {
    final String nextHref = page.nextHref.trim();
    if (nextHref.isEmpty || _isNextChapterLoading) {
      _clearNextChapterPullState();
      return;
    }
    _isNextChapterLoading = true;
    if (!_disposed) notifyListeners();
    try {
      await flushProgressPersistence();
      await onRequestChapterNavigation(
        nextHref,
        prevHref: page.uri,
        catalogHref: page.catalogHref,
      );
    } finally {
      _resetChapterBoundaryState();
    }
  }

  void handleChapterPullScrollNotification(
    ScrollNotification notification, {
    required ReaderPageData page,
    required ScrollController controller,
    Axis axis = Axis.vertical,
  }) {
    final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    if ((!hasPreviousChapter && !hasNextChapter) ||
        isZoomGestureLocked ||
        notification.depth != 0 ||
        notification.metrics.axis != axis ||
        _isNextChapterLoading) {
      if (!_isNextChapterLoading) {
        _clearPreviousChapterPullState();
        _clearNextChapterPullState();
      }
      return;
    }

    final bool nearChapterStart =
        hasPreviousChapter &&
        (_metricsNearChapterStart(notification.metrics, axis: axis) ||
            _scrollControllerAtTop(
              controller,
              tolerance: _readerNextChapterPullActivationExtent,
            ));
    final bool nearChapterEnd =
        hasNextChapter &&
        (_metricsNearChapterEnd(notification.metrics, axis: axis) ||
            _scrollControllerAtBottom(
              controller,
              tolerance: _readerNextChapterPullActivationExtent,
            ));

    if (notification is OverscrollNotification) {
      final double dragDelta = notification.dragDetails?.primaryDelta ?? 0;
      if (_isNextChapterForwardDrag(dragDelta, axis: axis) && nearChapterEnd) {
        _clearPreviousChapterPullState();
        _updateNextChapterPullDistance(
          _nextChapterPullDistance + dragDelta.abs(),
        );
        return;
      }
      if (_isNextChapterBackwardDrag(dragDelta, axis: axis) &&
          nearChapterStart) {
        _clearNextChapterPullState();
        _updatePreviousChapterPullDistance(
          _previousChapterPullDistance + dragDelta.abs(),
        );
        return;
      }
      if (_isNextChapterBackwardDrag(dragDelta, axis: axis) &&
          _nextChapterPullDistance > 0) {
        _updateNextChapterPullDistance(
          _nextChapterPullDistance - dragDelta.abs(),
        );
      } else if (_isNextChapterForwardDrag(dragDelta, axis: axis) &&
          _previousChapterPullDistance > 0) {
        _updatePreviousChapterPullDistance(
          _previousChapterPullDistance - dragDelta.abs(),
        );
      } else {
        if (!nearChapterStart) _clearPreviousChapterPullState();
        if (!nearChapterEnd) _clearNextChapterPullState();
      }
      return;
    }

    if (notification is ScrollUpdateNotification) {
      final DragUpdateDetails? dragDetails = notification.dragDetails;
      if (dragDetails == null) {
        if (!_scrollControllerAtTop(controller)) {
          _clearPreviousChapterPullState();
        }
        if (!_scrollControllerAtBottom(controller)) {
          _clearNextChapterPullState();
        }
        return;
      }
      final double dragDelta = dragDetails.primaryDelta ?? 0;
      if (_isNextChapterForwardDrag(dragDelta, axis: axis) && nearChapterEnd) {
        _clearPreviousChapterPullState();
        _updateNextChapterPullDistance(
          _nextChapterPullDistance + dragDelta.abs(),
        );
      } else if (_isNextChapterBackwardDrag(dragDelta, axis: axis) &&
          nearChapterStart) {
        _clearNextChapterPullState();
        _updatePreviousChapterPullDistance(
          _previousChapterPullDistance + dragDelta.abs(),
        );
      } else if (_isNextChapterBackwardDrag(dragDelta, axis: axis) &&
          _nextChapterPullDistance > 0) {
        _updateNextChapterPullDistance(
          _nextChapterPullDistance - dragDelta.abs(),
        );
      } else if (_isNextChapterForwardDrag(dragDelta, axis: axis) &&
          _previousChapterPullDistance > 0) {
        _updatePreviousChapterPullDistance(
          _previousChapterPullDistance - dragDelta.abs(),
        );
      } else {
        if (!nearChapterStart) _clearPreviousChapterPullState();
        if (!nearChapterEnd) _clearNextChapterPullState();
      }
      return;
    }

    if (notification is ScrollEndNotification) {
      if (previousChapterPullReady) {
        unawaited(triggerPreviousChapter(page));
      } else if (nextChapterPullReady) {
        unawaited(triggerNextChapter(page));
      } else {
        _clearPreviousChapterPullState();
        _clearNextChapterPullState();
      }
      return;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      if (previousChapterPullReady) {
        unawaited(triggerPreviousChapter(page));
      } else if (nextChapterPullReady) {
        unawaited(triggerNextChapter(page));
      } else {
        _clearPreviousChapterPullState();
        _clearNextChapterPullState();
      }
      return;
    }

    if (!nearChapterStart) _clearPreviousChapterPullState();
    if (!nearChapterEnd) _clearNextChapterPullState();
  }

  void _handleVolumeKeyAction(ReaderVolumeKeyAction action) {
    if (_page == null ||
        !preferences.useVolumeKeysForPaging ||
        isZoomGestureLocked) {
      return;
    }
    switch (action) {
      case ReaderVolumeKeyAction.previous:
        unawaited(stepBackward());
      case ReaderVolumeKeyAction.next:
        unawaited(stepForward());
    }
  }

  void _scheduleProgressPersistence() {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_persistCurrentProgress()),
    );
  }

  Future<void> _persistCurrentProgress() async {
    final ReaderPageData? page = _page;
    if (page == null) return;
    if (preferences.isPaged) {
      final ScrollController? pageScrollController =
          _pagedScrollControllers[_currentPageIndex];
      final ReaderPosition position = ReaderPosition.paged(
        pageIndex: _currentPageIndex,
        pageOffset:
            pageScrollController != null && pageScrollController.hasClients
            ? pageScrollController.offset
            : 0,
      );
      _lastPersistedPosition = position;
      await progressStore.writePosition(
        position,
        catalogHref: page.catalogHref,
        chapterHref: page.uri,
      );
      return;
    }
    if (!scrollController.hasClients) return;
    final ReaderPosition position = ReaderPosition.scroll(
      offset: scrollController.offset,
    );
    _lastPersistedPosition = position;
    await progressStore.writePosition(
      position,
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
  }

  void _prepareComments(
    ReaderPageData page, {
    required bool resetForNewChapter,
  }) {
    final String chapterId = readerChapterIdForPage(page);
    if (!preferences.showChapterComments || chapterId.isEmpty) {
      _commentsChapterId = '';
      _commentsError = '';
      _chapterComments = const <ChapterComment>[];
      _commentsTotal = 0;
      _commentsLoadedStartOffset = 0;
      _isCommentsLoading = false;
      _isCommentsLoadingMore = false;
      if (resetForNewChapter) {
        commentController.clear();
      }
      if (!_disposed) notifyListeners();
      return;
    }

    final bool shouldRefresh =
        resetForNewChapter ||
        _commentsChapterId != chapterId ||
        (_chapterComments.isEmpty && _commentsError.isEmpty);
    if (!shouldRefresh ||
        (_isCommentsLoading && _commentsChapterId == chapterId)) {
      return;
    }
    if (resetForNewChapter) {
      commentController.clear();
      if (commentScrollController.hasClients) {
        commentScrollController.jumpTo(0);
      }
    }
    unawaited(loadComments(page));
  }

  Future<void> loadComments(ReaderPageData page, {bool append = false}) async {
    final String chapterId = readerChapterIdForPage(page);
    if (chapterId.isEmpty || !preferences.showChapterComments) return;
    if (!_disposed) {
      final ReaderPageData? currentPage = _page;
      if (currentPage == null ||
          readerChapterIdForPage(currentPage) != chapterId) {
        return;
      }
    }

    final List<ChapterComment> existingComments =
        append && _commentsChapterId == chapterId
        ? _chapterComments
        : const <ChapterComment>[];
    ReaderCommentPageWindow? appendWindow;
    if (append) {
      if (_isCommentsLoading || _isCommentsLoadingMore) return;
      appendWindow = nextReaderCommentAscendingWindow(
        loadedStartOffset: _commentsLoadedStartOffset,
      );
      if (appendWindow.isEmpty) return;
    }

    if (!append) {
      _commentsChapterId = chapterId;
      _commentsError = '';
      _chapterComments = const <ChapterComment>[];
      _commentsTotal = 0;
      _commentsLoadedStartOffset = 0;
      _isCommentsLoading = true;
      _isCommentsLoadingMore = false;
      if (!_disposed) notifyListeners();
    } else {
      _isCommentsLoadingMore = true;
      if (!_disposed) notifyListeners();
    }

    try {
      final (
        ChapterCommentFeed feed,
        int loadedStartOffset,
        int resolvedTotal,
      ) = append
          ? await _loadCommentsAscendingPage(
              chapterId: chapterId,
              window: appendWindow!,
              fallbackTotal: _commentsTotal,
            )
          : await _loadInitialCommentsAscendingPage(chapterId);
      if (_disposed) return;
      final ReaderPageData? currentPage = _page;
      if (currentPage == null ||
          readerChapterIdForPage(currentPage) != chapterId) {
        if (_commentsChapterId == chapterId) {
          _isCommentsLoading = false;
          _isCommentsLoadingMore = false;
          if (!_disposed) notifyListeners();
        }
        return;
      }
      _commentsChapterId = chapterId;
      _chapterComments = append
          ? mergeReaderCommentsByIdentity(existingComments, feed.comments)
          : mergeReaderCommentsByIdentity(
              const <ChapterComment>[],
              feed.comments,
            );
      _commentsTotal = resolvedTotal > 0
          ? resolvedTotal
          : _chapterComments.length;
      _commentsLoadedStartOffset = loadedStartOffset;
      _commentsError = '';
      _isCommentsLoading = false;
      _isCommentsLoadingMore = false;
      if (!_disposed) notifyListeners();
    } catch (error) {
      if (_disposed) return;
      final ReaderPageData? currentPage = _page;
      if (currentPage == null ||
          readerChapterIdForPage(currentPage) != chapterId) {
        if (_commentsChapterId == chapterId) {
          _isCommentsLoading = false;
          _isCommentsLoadingMore = false;
          if (!_disposed) notifyListeners();
        }
        return;
      }
      final String message = error is SiteApiException
          ? error.message
          : '评论加载失败，请稍后重试。';
      if (append && existingComments.isNotEmpty) {
        _isCommentsLoading = false;
        _isCommentsLoadingMore = false;
        if (!_disposed) notifyListeners();
        return;
      }
      _commentsChapterId = chapterId;
      _commentsError = message;
      _chapterComments = const <ChapterComment>[];
      _commentsTotal = 0;
      _commentsLoadedStartOffset = 0;
      _isCommentsLoading = false;
      _isCommentsLoadingMore = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<(ChapterCommentFeed, int, int)> _loadInitialCommentsAscendingPage(
    String chapterId,
  ) async {
    final ChapterCommentFeed probe = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: 1,
      offset: 0,
    );
    final int probeTotal = probe.total > 0
        ? probe.total
        : probe.comments.length;
    if (probeTotal <= 0) {
      return (probe, 0, 0);
    }

    final ReaderCommentPageWindow window = probeTotal <= 1
        ? const ReaderCommentPageWindow(offset: 0, limit: readerCommentPageSize)
        : initialReaderCommentAscendingWindow(total: probeTotal);
    final ChapterCommentFeed rawFeed = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: window.limit,
      offset: window.offset,
    );
    final int resolvedTotal = rawFeed.total > 0
        ? rawFeed.total
        : math.max(probeTotal, rawFeed.comments.length);
    return (
      ChapterCommentFeed(
        total: resolvedTotal,
        comments: normalizeReaderCommentAscendingPage(rawFeed.comments),
      ),
      window.offset,
      resolvedTotal,
    );
  }

  Future<(ChapterCommentFeed, int, int)> _loadCommentsAscendingPage({
    required String chapterId,
    required ReaderCommentPageWindow window,
    required int fallbackTotal,
  }) async {
    final ChapterCommentFeed rawFeed = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: window.limit,
      offset: window.offset,
    );
    final int resolvedTotal = rawFeed.total > 0 ? rawFeed.total : fallbackTotal;
    return (
      ChapterCommentFeed(
        total: resolvedTotal,
        comments: normalizeReaderCommentAscendingPage(rawFeed.comments),
      ),
      window.offset,
      resolvedTotal,
    );
  }

  void _handleCommentScroll() {
    if (!commentScrollController.hasClients ||
        _isCommentsLoading ||
        _isCommentsLoadingMore) {
      return;
    }
    final ReaderPageData? currentPage = _page;
    if (currentPage == null || !shouldShowCommentTailPage(currentPage)) {
      return;
    }
    final ScrollPosition position = commentScrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.maxScrollExtent - position.pixels > 180) return;
    unawaited(loadComments(currentPage, append: true));
  }

  Future<void> submitComment(ReaderPageData page) async {
    if (_isCommentSubmitting) return;
    final String chapterId = readerChapterIdForPage(page);
    if (chapterId.isEmpty) {
      onShowMessage('章节评论信息缺失，请刷新后重试。');
      return;
    }
    final String content = commentController.text.trim();
    if (content.isEmpty) {
      onShowMessage('请输入评论内容。');
      return;
    }

    if (!session.isAuthenticated || (session.token ?? '').isEmpty) {
      await onRequestAuth();
      if (!session.isAuthenticated || (session.token ?? '').isEmpty) {
        return;
      }
    }

    if (_disposed) return;
    _isCommentSubmitting = true;
    if (!_disposed) notifyListeners();

    try {
      await apiClient.postChapterComment(
        chapterId: chapterId,
        content: content,
      );
      commentController.clear();
      onShowMessage('已发送评论');
      await loadComments(page);
    } catch (error) {
      final String message = error is SiteApiException
          ? error.message
          : '评论发送失败，请稍后重试。';
      if (message.contains('登录已失效')) {
        await onLogoutForExpiredSession();
      }
      if (!_disposed) {
        onShowMessage(message);
      }
    } finally {
      _isCommentSubmitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _handlePreferencesChanged() {
    final ReaderPreferences previousPreferences =
        _lastObservedPreferences ?? preferences;
    final ReaderPreferences nextPreferences = preferences;
    _lastObservedPreferences = nextPreferences;
    if (_disposed) return;

    final ReaderPageData? page = _page;
    final ReaderRestoreTarget? readerRestoreTarget = page != null
        ? captureCurrentRestoreTarget(page, preferences: previousPreferences)
        : null;
    notifyListeners();

    final bool requiresReaderRestore =
        previousPreferences.readingDirection !=
            nextPreferences.readingDirection ||
        previousPreferences.pageFit != nextPreferences.pageFit ||
        previousPreferences.openingPosition !=
            nextPreferences.openingPosition ||
        previousPreferences.showChapterComments !=
            nextPreferences.showChapterComments;
    if (requiresReaderRestore && page != null) {
      _handlePageLoaded(
        page,
        previousUri: page.uri,
        forceRestore: true,
        preferredRestoreTarget: readerRestoreTarget,
      );
      return;
    }
    _scheduleReaderPresentationSync();
  }
}
