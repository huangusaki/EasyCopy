import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/chapter_comment.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/internal/reader_environment.dart';
import 'package:reader/reader/internal/reader_restore_target.dart';
import 'package:reader/reader/reader_controller/chapter_boundary.dart';
import 'package:reader/reader/reader_controller/comments.dart';
import 'package:reader/reader/reader_controller/zoom_state.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/deferred_viewport_coordinator.dart';
import 'package:reader/services/image_cache.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/reader_history_recorder.dart';
import 'package:reader/services/reader_platform_bridge.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';

const double _pullTriggerDistance = 266;
const double _pagedTriggerDistance = 152;
const double _readerScrollProgressStep = 96;
const double _readerPagedProgressStep = 48;

typedef ReaderChapterNavigationCallback =
    Future<void> Function(
      String href, {
      String prevHref,
      String nextHref,
      String catalogHref,
      bool openAtEnd,
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
  }) {
    _comments = ReaderCommentsController(
      apiClient: apiClient,
      session: session,
      preferences: () => preferences,
      currentPage: () => _page,
      chapterIdForPage: readerChapterIdForPage,
      isDisposed: () => _disposed,
      notify: notifyListeners,
      onRequestAuth: onRequestAuth,
      onLogoutForExpiredSession: onLogoutForExpiredSession,
      onShowMessage: onShowMessage,
    );
    _zoom = ReaderZoomController();
    _chapterBoundary = ReaderChapterBoundaryController(
      triggerDistance: () => _nextChapterTriggerDistance,
      readingDirection: () => preferences.readingDirection,
      isZoomLocked: () => isZoomGestureLocked,
      flushProgress: flushProgressPersistence,
      onRequestChapterNavigation: onRequestChapterNavigation,
      notify: () {
        if (!_disposed) {
          notifyListeners();
        }
      },
    );
  }

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
  final GlobalKey viewportKey = GlobalKey();
  final Map<int, ScrollController> _pagedScrollControllers =
      <int, ScrollController>{};
  final Map<int, GlobalKey> _imageItemKeys = <int, GlobalKey>{};
  final Map<String, double> _imageAspectRatios = <String, double>{};
  final DeferredViewportCoordinator restoreCoordinator =
      DeferredViewportCoordinator();
  late final ReaderCommentsController _comments;
  late final ReaderZoomController _zoom;
  late final ReaderChapterBoundaryController _chapterBoundary;

  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<ReaderVolumeKeyAction>? _volumeKeySubscription;
  Timer? _progressDebounce;
  Timer? _autoTurnTimer;
  bool _disposed = false;

  ReaderPageData? _page;
  int _currentPageIndex = 0;
  int _visibleImageIndex = 0;
  ReaderPosition? _lastPersistedPosition;
  ReaderPosition? _lastScheduledProgressPosition;
  AppliedReaderEnvironment? _appliedEnvironment;
  ReaderPreferences? _lastObservedPreferences;
  bool _presentationSyncScheduled = false;
  bool _visibleIndexUpdateQueued = false;

  bool _isSettingsOpen = false;
  bool _isChapterControlsVisible = false;
  int? _batteryLevel;

  ReaderPageData? get page => _page;

  ReaderPreferences get preferences => preferencesController.readerPreferences;

  int get currentPageIndex => _currentPageIndex;

  int get visibleImageIndex => _visibleImageIndex;

  ReaderPosition? get lastPersistedPosition => _lastPersistedPosition;

  AppliedReaderEnvironment? get appliedEnvironment => _appliedEnvironment;

  bool get isSettingsOpen => _isSettingsOpen;

  bool get isChapterControlsVisible => _isChapterControlsVisible;

  TextEditingController get commentController => _comments.textController;

  ScrollController get commentScrollController => _comments.scrollController;

  bool get isNextChapterLoading => _chapterBoundary.isLoading;

  bool get isScaleGestureActive => _zoom.isScaleGestureActive;

  bool get isZoomGestureLocked => _zoom.isLocked;

  double get zoomScale => _zoom.scale;

  double get panOffsetX => _zoom.panOffsetX;

  double get panOffsetY => _zoom.panOffsetY;

  double get previousChapterPullDistance => _chapterBoundary.previousDistance;

  double get nextChapterPullDistance => _chapterBoundary.nextDistance;

  bool get previousChapterPullReady => _chapterBoundary.previousReady;

  bool get nextChapterPullReady => _chapterBoundary.nextReady;

  double get _nextChapterTriggerDistance =>
      preferences.isPaged ? _pagedTriggerDistance : _pullTriggerDistance;

  List<ChapterComment> get chapterComments => _comments.items;

  String get commentsChapterId => _comments.chapterId;

  String get commentsError => _comments.error;

  int get commentsTotal => _comments.total;

  bool get isCommentsLoading => _comments.isLoading;

  bool get isCommentsLoadingMore => _comments.isLoadingMore;

  bool get isCommentSubmitting => _comments.isSubmitting;

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
    bool openAtEnd = false,
  }) {
    _page = page;
    _handlePageLoaded(
      page,
      previousUri: previousUri,
      forceRestore: forceRestore,
      preferredRestoreTarget: preferredRestoreTarget,
      openAtEnd: openAtEnd,
    );
    notifyListeners();
  }

  Future<void> flushProgressPersistence() async {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    _lastScheduledProgressPosition = null;
    await _persistCurrentProgress();
  }

  Future<void> restoreDefaultEnvironment() async {
    await platformBridge.restoreDefaultPresentation();
    await platformBridge.setKeepScreenOn(false);
    await platformBridge.setVolumePagingEnabled(false);
    _appliedEnvironment = const AppliedReaderEnvironment.standard();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressDebounce?.cancel();
    _autoTurnTimer?.cancel();
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
    _comments.dispose();
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

  Future<void> stepForward() async {
    if (isZoomGestureLocked) return;
    restoreCoordinator.noteUserInteraction();
    if (preferences.isPaged) {
      final ReaderPageData? page = _page;
      if (page == null) return;
      final int totalPageCount = readerPagedPageCount(page);
      final int nextPageIndex = _currentPageIndex + 1;
      if (nextPageIndex >= totalPageCount) {
        if (page.nextHref.trim().isNotEmpty) {
          await triggerNextChapter(page);
        } else {
          onShowMessage('已经是最后一话');
        }
        return;
      }
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
      if (previousPageIndex < 0) {
        final ReaderPageData? page = _page;
        if (page != null && page.prevHref.trim().isNotEmpty) {
          await triggerPreviousChapter(page);
        } else {
          onShowMessage('已经是第一话');
        }
        return;
      }
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

  Future<void> scrollCurrentPageDown() => _scrollCurrentPageBy(1);

  Future<void> scrollCurrentPageUp() => _scrollCurrentPageBy(-1);

  Future<void> _scrollCurrentPageBy(int direction) async {
    if (isZoomGestureLocked) return;
    restoreCoordinator.noteUserInteraction();
    final ScrollController? controller = preferences.isPaged
        ? _pagedScrollControllers[_currentPageIndex]
        : scrollController;
    if (controller == null || !controller.hasClients) return;
    final ScrollPosition position = controller.position;
    final double delta = position.viewportDimension * 0.72 * direction;
    final double targetOffset = (controller.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((targetOffset - controller.offset).abs() < 1) return;
    await controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
    _restartAutoTurn();
  }

  Future<void> animateToPage(int pageIndex) async {
    if (!pageController.hasClients) return;
    if (preferences.disablePageTransitionAnimation) {
      pageController.jumpToPage(pageIndex);
      if (_currentPageIndex != pageIndex) {
        handlePageChanged(pageIndex);
      }
      return;
    }
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

  void restartAutoTurnAfterScroll() {
    _restartAutoTurn();
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
        await platformBridge.applyReaderPresentation(
          orientation: nextEnvironment.orientation,
          fullscreen: nextEnvironment.fullscreen,
        );
        await platformBridge.setKeepScreenOn(nextEnvironment.keepScreenOn);
        await platformBridge.setVolumePagingEnabled(
          nextEnvironment.volumePagingEnabled,
        );
        _appliedEnvironment = nextEnvironment;
      }
    }

    if (page == null) {
      _autoTurnTimer?.cancel();
      _autoTurnTimer = null;
      return;
    }
    _restartAutoTurn();
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
    bool openAtEnd = false,
  }) {
    final List<String> remoteImages = page.imageUrls
        .where((String imageUrl) {
          final Uri? uri = Uri.tryParse(imageUrl);
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
        })
        .toList(growable: false);
    unawaited(
      AppImageCaches.prefetchReaderImages(remoteImages, referer: page.uri),
    );
    unawaited(_markChapterVisited(page));
    final bool changedPage = previousUri != page.uri;
    if (changedPage || forceRestore) {
      _chapterBoundary.reset();
      _resetZoomState();
    }
    if (changedPage) {
      _currentPageIndex = 0;
      _visibleImageIndex = 0;
      _lastScheduledProgressPosition = null;
      _visibleIndexUpdateQueued = false;
      _isChapterControlsVisible = false;
      _disposePagedScrollControllers();
      _imageItemKeys.clear();
      _imageAspectRatios.clear();
      if (!preferences.isPaged && scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    }
    _comments.prepare(page, resetForNewChapter: changedPage);
    _scheduleReaderPresentationSync();
    if (changedPage || forceRestore) {
      unawaited(
        _restorePosition(
          page,
          resetControllers: changedPage || forceRestore,
          preferredRestoreTarget: preferredRestoreTarget,
          openAtEnd: openAtEnd,
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
    bool openAtEnd = false,
  }) async {
    final DeferredViewportTicket ticket = restoreCoordinator.beginRequest();
    final bool restoreAtEnd =
        openAtEnd && resetControllers && preferredRestoreTarget == null;
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
      final int pageIndex = restoreAtEnd
          ? (page.imageUrls.isEmpty ? 0 : page.imageUrls.length - 1).clamp(
              0,
              maxPageIndex,
            )
          : (sourcePosition?.isPaged == true
                ? sourcePosition!.pageIndex.clamp(0, maxPageIndex)
                : (preferredImageIndex ?? 0));
      final double? pageOffset = restoreAtEnd
          ? null
          : (sourcePosition?.isPaged == true
                ? sourcePosition!.pageOffset
                : null);
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

    final int? restoreImageIndex = restoreAtEnd
        ? (page.imageUrls.isEmpty ? null : page.imageUrls.length - 1)
        : restoreTarget.imageIndexFor(page);
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
          alignment: restoreAtEnd
              ? 1
              : (preferredRestoreTarget == null &&
                        preferences.openingPosition ==
                            ReaderOpeningPosition.top
                    ? 0
                    : 0.5),
        );
      } else {
        _jumpToOffset(page.uri, savedOffset ?? 0, attempts: 10, ticket: ticket);
      }
      _scheduleVisibleIndexUpdate();
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
    if (_shouldScheduleScrollProgress(currentOffset)) {
      _lastScheduledProgressPosition = ReaderPosition.scroll(
        offset: currentOffset,
      );
      _scheduleProgressPersistence();
    }
    _scheduleVisibleIndexUpdate();
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
    _chapterBoundary.reset();
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
    if (_shouldSchedulePagedProgress(pageIndex, controller.offset)) {
      _lastScheduledProgressPosition = ReaderPosition.paged(
        pageIndex: pageIndex,
        pageOffset: controller.offset,
      );
      _scheduleProgressPersistence();
    }
  }

  void _scheduleVisibleIndexUpdate() {
    if (_visibleIndexUpdateQueued) return;
    _visibleIndexUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleIndexUpdateQueued = false;
      if (_disposed || preferences.isPaged) return;
      _updateVisibleImageIndex();
    });
  }

  bool _shouldScheduleScrollProgress(double offset) {
    final ReaderPosition? last =
        _lastScheduledProgressPosition ?? _lastPersistedPosition;
    if (last == null || !last.isScroll) return true;
    return (offset - last.offset).abs() >= _readerScrollProgressStep;
  }

  bool _shouldSchedulePagedProgress(int pageIndex, double pageOffset) {
    final ReaderPosition? last =
        _lastScheduledProgressPosition ?? _lastPersistedPosition;
    if (last == null || !last.isPaged || last.pageIndex != pageIndex) {
      return true;
    }
    return (pageOffset - last.pageOffset).abs() >= _readerPagedProgressStep;
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

  void setImageZoomed(String imageKey, bool isZoomed) {
    _setImageZoomed(imageKey, isZoomed);
  }

  void handlePinchZoomStart() {
    _mutateZoom(_zoom.startPinch);
  }

  void handlePinchZoomUpdate(double relativeScale) {
    _mutateZoom(() => _zoom.updatePinch(relativeScale));
  }

  void handlePinchZoomEnd() {
    _mutateZoom(_zoom.endPinch);
  }

  void updatePanOffset({required double x, required double y}) {
    _mutateZoom(() => _zoom.updatePanOffset(x: x, y: y));
  }

  void handleZoomedOverscroll(ReaderPageData page, double overscrollDy) {
    final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    if (overscrollDy < -0.5 && hasNextChapter) {
      _chapterBoundary.clearPrevious();
      _chapterBoundary.addNextDistance(overscrollDy.abs());
    } else if (overscrollDy > 0.5 && hasPreviousChapter) {
      _chapterBoundary.clearNext();
      _chapterBoundary.addPreviousDistance(overscrollDy.abs());
    }
  }

  void handleZoomedPanEnd(ReaderPageData page) {
    if (previousChapterPullReady) {
      unawaited(triggerPreviousChapter(page));
    } else if (nextChapterPullReady) {
      unawaited(triggerNextChapter(page));
    } else {
      _chapterBoundary.clearPrevious();
      _chapterBoundary.clearNext();
    }
  }

  Future<void> triggerPreviousChapter(ReaderPageData page) {
    return _chapterBoundary.triggerPrevious(page);
  }

  Future<void> triggerNextChapter(ReaderPageData page) {
    return _chapterBoundary.triggerNext(page);
  }

  void handleChapterPull(
    ScrollNotification notification, {
    required ReaderPageData page,
    required ScrollController controller,
    Axis axis = Axis.vertical,
  }) {
    _chapterBoundary.handlePull(
      notification,
      page: page,
      controller: controller,
      controllerAtTop: _scrollControllerAtTop,
      controllerAtBottom: _scrollControllerAtBottom,
      axis: axis,
    );
  }

  Future<void> loadComments(ReaderPageData page, {bool append = false}) {
    return _comments.load(page, append: append);
  }

  Future<void> submitComment(ReaderPageData page) {
    return _comments.submit(page);
  }

  void _handleCommentScroll() {
    _comments.handleScroll();
  }

  void _setImageZoomed(String imageKey, bool isZoomed) {
    _mutateZoom(() => _zoom.setImageZoomed(imageKey, isZoomed));
  }

  void _resetZoomState() {
    _mutateZoom(_zoom.reset);
  }

  void _mutateZoom(bool Function() mutation) {
    final bool wasLocked = _zoom.isLocked;
    final bool changed = mutation();
    if (changed && !_disposed) {
      notifyListeners();
    }
    _handleZoomLockChanged(wasLocked);
  }

  void _handleZoomLockChanged(bool wasLocked) {
    final bool isLocked = isZoomGestureLocked;
    if (wasLocked == isLocked) return;
    if (isLocked) {
      _autoTurnTimer?.cancel();
      _chapterBoundary.reset();
      hideChapterControls();
      return;
    }
    _restartAutoTurn();
  }

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
    _progressDebounce = Timer(const Duration(milliseconds: 900), () {
      _progressDebounce = null;
      unawaited(_persistCurrentProgress());
    });
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
      _lastScheduledProgressPosition = position;
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
    _lastScheduledProgressPosition = position;
    await progressStore.writePosition(
      position,
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
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
