part of '../easy_copy_screen.dart';

class _ReaderRestoreTarget {
  const _ReaderRestoreTarget({this.position, this.visibleImageIndex});

  final ReaderPosition? position;
  final int? visibleImageIndex;

  int? imageIndexFor(ReaderPageData page) {
    if (page.imageUrls.isEmpty) {
      return null;
    }
    final int? rawIndex =
        visibleImageIndex ??
        (position?.isPaged == true ? position!.pageIndex : null);
    if (rawIndex == null) {
      return null;
    }
    return rawIndex.clamp(0, page.imageUrls.length - 1);
  }
}

extension _EasyCopyScreenReaderProgress on _EasyCopyScreenState {
  _ReaderRestoreTarget? _captureCurrentReaderRestoreTarget(
    ReaderPageData page, {
    required ReaderPreferences preferences,
  }) {
    if (preferences.isPaged) {
      final int maxPageIndex = math.max(0, _readerPagedPageCount(page) - 1);
      final int pageIndex = _currentReaderPageIndex.clamp(0, maxPageIndex);
      final ScrollController? controller =
          _readerPageScrollControllers[pageIndex];
      return _ReaderRestoreTarget(
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
    final double? offset = _readerScrollController.hasClients
        ? _readerScrollController.offset
        : null;
    return _ReaderRestoreTarget(
      position: offset == null ? null : ReaderPosition.scroll(offset: offset),
      visibleImageIndex: page.imageUrls.isEmpty
          ? null
          : _currentVisibleReaderImageIndex.clamp(0, page.imageUrls.length - 1),
    );
  }

  void _handleReaderPageLoaded(
    ReaderPageData page, {
    String? previousUri,
    bool forceRestore = false,
    _ReaderRestoreTarget? preferredRestoreTarget,
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
    if (changedPage || forceRestore) {
      _resetReaderChapterBoundaryState();
      _resetReaderZoomState();
    }
    if (changedPage) {
      _currentReaderPageIndex = 0;
      _currentVisibleReaderImageIndex = 0;
      _isReaderChapterControlsVisible = false;
      _disposeReaderPagedScrollControllers();
      _readerImageItemKeys.clear();
      _readerImageAspectRatios.clear();
    }
    _prepareReaderComments(page, resetForNewChapter: changedPage);
    _scheduleReaderPresentationSync();
    if (changedPage || forceRestore) {
      unawaited(
        _restoreReaderPosition(
          page,
          resetControllers: changedPage || forceRestore,
          preferredRestoreTarget: preferredRestoreTarget,
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
    _ReaderRestoreTarget? preferredRestoreTarget,
  }) async {
    final DeferredViewportTicket ticket = _readerRestoreCoordinator
        .beginRequest();
    final String progressKey = _readerProgressKeyForPage(page);
    final ReaderPosition? savedPosition = await _readerProgressStore
        .readPosition(progressKey);
    if (!mounted ||
        _page is! ReaderPageData ||
        (_page as ReaderPageData).uri != page.uri) {
      return;
    }

    final _ReaderRestoreTarget restoreTarget =
        preferredRestoreTarget ?? _ReaderRestoreTarget(position: savedPosition);

    if (_readerPreferences.isPaged) {
      final int maxPageIndex = math.max(0, _readerPagedPageCount(page) - 1);
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
        _disposeReaderPagedScrollControllers();
        _replaceReaderPageController(initialPage: pageIndex);
      }
      _lastPersistedReaderPosition = ReaderPosition.paged(
        pageIndex: pageIndex,
        pageOffset: pageOffset ?? 0,
      );
      _currentReaderPageIndex = pageIndex;
      _currentVisibleReaderImageIndex = page.imageUrls.isEmpty
          ? 0
          : (pageIndex >= page.imageUrls.length
                ? page.imageUrls.length - 1
                : pageIndex);
      _setStateIfMounted();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isActiveReaderRestore(ticket, pageUri: page.uri, isPaged: true)) {
          return;
        }
        _jumpReaderToPage(page.uri, pageIndex, attempts: 10, ticket: ticket);
        _jumpReaderPageOffset(
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
    _lastPersistedReaderPosition = savedOffset == null
        ? null
        : ReaderPosition.scroll(offset: savedOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isActiveReaderRestore(ticket, pageUri: page.uri, isPaged: false)) {
        return;
      }
      if (restoreImageIndex != null) {
        _jumpReaderToImageIndex(
          page.uri,
          restoreImageIndex,
          attempts: 10,
          ticket: ticket,
          alignment:
              preferredRestoreTarget == null &&
                  _readerPreferences.openingPosition ==
                      ReaderOpeningPosition.top
              ? 0
              : 0.5,
        );
      } else {
        _jumpReaderToOffset(
          page.uri,
          savedOffset,
          attempts: 10,
          ticket: ticket,
        );
      }
      _scheduleVisibleReaderImageIndexUpdate();
    });
  }

  void _jumpReaderToOffset(
    String pageUri,
    double? offset, {
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveReaderRestore(ticket, pageUri: pageUri, isPaged: false)) {
      return;
    }
    if (!_readerScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToOffset(
            pageUri,
            offset,
            attempts: attempts - 1,
            ticket: ticket,
          ),
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
        () => _jumpReaderToOffset(
          pageUri,
          targetOffset,
          attempts: attempts - 1,
          ticket: ticket,
        ),
      );
      return;
    }
    final double clampedOffset = targetOffset.clamp(0, maxExtent).toDouble();
    _readerScrollController.jumpTo(clampedOffset);
  }

  void _jumpReaderToImageIndex(
    String pageUri,
    int imageIndex, {
    required int attempts,
    required DeferredViewportTicket ticket,
    required double alignment,
  }) {
    if (!_isActiveReaderRestore(ticket, pageUri: pageUri, isPaged: false)) {
      return;
    }
    final BuildContext? itemContext = _readerImageItemKeyFor(
      imageIndex,
    ).currentContext;
    if (itemContext == null) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToImageIndex(
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

  void _jumpReaderToPage(
    String pageUri,
    int pageIndex, {
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveReaderRestore(ticket, pageUri: pageUri, isPaged: true)) {
      return;
    }
    if (!_readerPageController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToPage(
            pageUri,
            pageIndex,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
      }
      return;
    }
    _readerPageController.jumpToPage(pageIndex);
  }

  void _jumpReaderPageOffset(
    String pageUri,
    int pageIndex, {
    required double? offset,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveReaderRestore(ticket, pageUri: pageUri, isPaged: true)) {
      return;
    }
    final ScrollController? controller =
        _readerPageScrollControllers[pageIndex];
    if (controller == null || !controller.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderPageOffset(
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
    final EasyCopyPage? currentPage = _page;
    final int visibleImageIndex =
        currentPage is ReaderPageData && currentPage.imageUrls.isNotEmpty
        ? (index >= currentPage.imageUrls.length
              ? currentPage.imageUrls.length - 1
              : index)
        : index;
    _resetReaderChapterBoundaryState();
    if (!mounted) {
      _currentReaderPageIndex = index;
      _currentVisibleReaderImageIndex = visibleImageIndex;
      return;
    }
    _setStateIfMounted(() {
      _currentReaderPageIndex = index;
      _currentVisibleReaderImageIndex = visibleImageIndex;
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
      () => unawaited(_persistCurrentReaderProgress()),
    );
  }

  String _readerProgressKeyForPage(ReaderPageData page) {
    return ReaderProgressStore.progressKeyForChapterHref(page.uri);
  }

  Future<void> _flushReaderProgressPersistence() async {
    _readerProgressDebounce?.cancel();
    _readerProgressDebounce = null;
    await _persistCurrentReaderProgress();
  }

  Future<void> _persistCurrentReaderProgress() async {
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
      await _readerProgressStore.writePosition(
        progressKey,
        position,
        catalogHref: page.catalogHref,
        chapterHref: page.uri,
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
    await _readerProgressStore.writePosition(
      progressKey,
      position,
      catalogHref: page.catalogHref,
      chapterHref: page.uri,
    );
  }
}
