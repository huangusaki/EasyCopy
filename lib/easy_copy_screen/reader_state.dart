part of '../easy_copy_screen.dart';

extension _EasyCopyScreenReaderState on _EasyCopyScreenState {
  bool get _readerPreviousChapterPullReady =>
      _readerPreviousChapterPullDistance >= _readerNextChapterTriggerDistance;

  bool get _readerNextChapterPullReady =>
      _readerNextChapterPullDistance >= _readerNextChapterTriggerDistance;

  Axis get _readerNextChapterGestureAxis =>
      _readerPreferences.isPaged ? Axis.horizontal : Axis.vertical;

  double get _readerNextChapterTriggerDistance =>
      _readerPreferences.isPaged
      ? _readerNextChapterPagedTriggerDistance
      : _readerNextChapterPullTriggerDistance;

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
    _readerRestoreCoordinator.noteUserInteraction();
    if (_readerPreferences.isPaged) {
      final EasyCopyPage? page = _page;
      if (page is! ReaderPageData) {
        return;
      }
      final int totalPageCount = _readerPagedPageCount(page);
      final int nextPageIndex = _currentReaderPageIndex + 1;
      if (nextPageIndex >= totalPageCount) {
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
    _readerRestoreCoordinator.noteUserInteraction();
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
    await SystemChrome.setPreferredOrientations(
      _EasyCopyScreenState._defaultOrientations,
    );
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
      _setStateIfMounted();
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
          final int totalPageCount = _readerPagedPageCount(page);
          final int nextPageIndex = _currentReaderPageIndex + 1;
          if (nextPageIndex >= totalPageCount) {
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
    _setStateIfMounted(() {
      _currentVisibleReaderImageIndex = bestIndex;
    });
  }

  bool _readerScrollControllerAtBottom(
    ScrollController controller, {
    double tolerance = 1,
  }) {
    if (!controller.hasClients) {
      return false;
    }
    return controller.position.maxScrollExtent - controller.position.pixels <=
        tolerance;
  }

  bool _readerScrollControllerAtTop(
    ScrollController controller, {
    double tolerance = 1,
  }) {
    if (!controller.hasClients) {
      return false;
    }
    return controller.position.pixels - controller.position.minScrollExtent <=
        tolerance;
  }

  bool _readerMetricsNearChapterStart(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _readerNextChapterPullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentBefore <= threshold;
  }

  bool _readerMetricsNearChapterEnd(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _readerNextChapterPullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentAfter <= threshold;
  }

  bool _readerIsNextChapterForwardDrag(double dragDelta, {required Axis axis}) {
    if (axis == Axis.vertical) {
      return dragDelta < 0;
    }
    return switch (_readerPreferences.readingDirection) {
      ReaderReadingDirection.leftToRight => dragDelta < 0,
      ReaderReadingDirection.rightToLeft => dragDelta > 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  bool _readerIsNextChapterBackwardDrag(
    double dragDelta, {
    required Axis axis,
  }) {
    if (axis == Axis.vertical) {
      return dragDelta > 0;
    }
    return switch (_readerPreferences.readingDirection) {
      ReaderReadingDirection.leftToRight => dragDelta > 0,
      ReaderReadingDirection.rightToLeft => dragDelta < 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  void _updateReaderNextChapterPullDistance(double distance) {
    final double triggerDistance = _readerNextChapterTriggerDistance;
    final double clampedDistance = distance
        .clamp(0, triggerDistance * 1.6)
        .toDouble();
    final bool nextReady = clampedDistance >= triggerDistance;
    if ((_readerNextChapterPullDistance - clampedDistance).abs() < 0.5 &&
        _readerNextChapterPullReady == nextReady) {
      return;
    }
    if (!mounted) {
      _readerNextChapterPullDistance = clampedDistance;
      return;
    }
    _setStateIfMounted(() {
      _readerNextChapterPullDistance = clampedDistance;
    });
  }

  void _updateReaderPreviousChapterPullDistance(double distance) {
    final double triggerDistance = _readerNextChapterTriggerDistance;
    final double clampedDistance = distance
        .clamp(0, triggerDistance * 1.6)
        .toDouble();
    final bool nextReady = clampedDistance >= triggerDistance;
    if ((_readerPreviousChapterPullDistance - clampedDistance).abs() < 0.5 &&
        _readerPreviousChapterPullReady == nextReady) {
      return;
    }
    if (!mounted) {
      _readerPreviousChapterPullDistance = clampedDistance;
      return;
    }
    _setStateIfMounted(() {
      _readerPreviousChapterPullDistance = clampedDistance;
    });
  }

  void _clearReaderPreviousChapterPullState() {
    if (_readerPreviousChapterPullDistance <= 0) {
      return;
    }
    if (!mounted) {
      _readerPreviousChapterPullDistance = 0;
      return;
    }
    _setStateIfMounted(() {
      _readerPreviousChapterPullDistance = 0;
    });
  }

  void _clearReaderNextChapterPullState() {
    if (_readerNextChapterPullDistance <= 0) {
      return;
    }
    if (!mounted) {
      _readerNextChapterPullDistance = 0;
      return;
    }
    _setStateIfMounted(() {
      _readerNextChapterPullDistance = 0;
    });
  }

  void _resetReaderChapterBoundaryState() {
    if (_readerPreviousChapterPullDistance <= 0 &&
        _readerNextChapterPullDistance <= 0 &&
        !_isReaderNextChapterLoading) {
      return;
    }
    if (!mounted) {
      _readerPreviousChapterPullDistance = 0;
      _readerNextChapterPullDistance = 0;
      _isReaderNextChapterLoading = false;
      return;
    }
    _setStateIfMounted(() {
      _readerPreviousChapterPullDistance = 0;
      _readerNextChapterPullDistance = 0;
      _isReaderNextChapterLoading = false;
    });
  }

  Future<void> _triggerReaderPreviousChapter(ReaderPageData page) async {
    final String prevHref = page.prevHref.trim();
    if (prevHref.isEmpty || _isReaderNextChapterLoading) {
      _clearReaderPreviousChapterPullState();
      return;
    }
    final String currentReaderUri = page.uri;
    if (!mounted) {
      _isReaderNextChapterLoading = true;
    } else {
      _setStateIfMounted(() {
        _isReaderNextChapterLoading = true;
      });
    }
    _persistCurrentReaderProgress();
    try {
      await _openHref(
        prevHref,
        nextHref: page.uri,
        catalogHref: page.catalogHref,
        sourceTabIndex: _selectedIndex,
      );
    } finally {
      if (!mounted) {
        _isReaderNextChapterLoading = false;
        _readerPreviousChapterPullDistance = 0;
      } else {
        final EasyCopyPage? currentPage = _page;
        if (currentPage is ReaderPageData &&
            currentPage.uri == currentReaderUri) {
          _setStateIfMounted(() {
            _isReaderNextChapterLoading = false;
            _readerPreviousChapterPullDistance = 0;
          });
        }
      }
    }
  }

  Future<void> _triggerReaderNextChapter(ReaderPageData page) async {
    final String nextHref = page.nextHref.trim();
    if (nextHref.isEmpty || _isReaderNextChapterLoading) {
      _clearReaderNextChapterPullState();
      return;
    }
    final String currentReaderUri = page.uri;
    if (!mounted) {
      _isReaderNextChapterLoading = true;
    } else {
      _setStateIfMounted(() {
        _isReaderNextChapterLoading = true;
      });
    }
    _persistCurrentReaderProgress();
    try {
      await _openHref(
        nextHref,
        prevHref: page.uri,
        catalogHref: page.catalogHref,
        sourceTabIndex: _selectedIndex,
      );
    } finally {
      if (!mounted) {
        _isReaderNextChapterLoading = false;
        _readerNextChapterPullDistance = 0;
      } else {
        final EasyCopyPage? currentPage = _page;
        if (currentPage is ReaderPageData &&
            currentPage.uri == currentReaderUri) {
          _setStateIfMounted(() {
            _isReaderNextChapterLoading = false;
            _readerNextChapterPullDistance = 0;
          });
        }
      }
    }
  }

  void _handleReaderNextChapterPullNotification(
    ScrollNotification notification, {
    required ReaderPageData page,
    required ScrollController controller,
    Axis axis = Axis.vertical,
  }) {
    final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    if ((!hasPreviousChapter && !hasNextChapter) ||
        notification.depth != 0 ||
        notification.metrics.axis != axis ||
        _isReaderNextChapterLoading) {
      if (!_isReaderNextChapterLoading) {
        _clearReaderPreviousChapterPullState();
        _clearReaderNextChapterPullState();
      }
      return;
    }

    final bool nearChapterStart =
        hasPreviousChapter &&
        (_readerMetricsNearChapterStart(notification.metrics, axis: axis) ||
            _readerScrollControllerAtTop(
              controller,
              tolerance: _readerNextChapterPullActivationExtent,
            ));
    final bool nearChapterEnd =
        hasNextChapter &&
        (_readerMetricsNearChapterEnd(notification.metrics, axis: axis) ||
            _readerScrollControllerAtBottom(
              controller,
              tolerance: _readerNextChapterPullActivationExtent,
            ));

    if (notification is OverscrollNotification) {
      final double dragDelta = notification.dragDetails?.primaryDelta ?? 0;
      if (_readerIsNextChapterForwardDrag(dragDelta, axis: axis) &&
          nearChapterEnd) {
        _clearReaderPreviousChapterPullState();
        _updateReaderNextChapterPullDistance(
          _readerNextChapterPullDistance + dragDelta.abs(),
        );
        return;
      }
      if (_readerIsNextChapterBackwardDrag(dragDelta, axis: axis) &&
          nearChapterStart) {
        _clearReaderNextChapterPullState();
        _updateReaderPreviousChapterPullDistance(
          _readerPreviousChapterPullDistance + dragDelta.abs(),
        );
        return;
      }
      if (_readerIsNextChapterBackwardDrag(dragDelta, axis: axis) &&
          _readerNextChapterPullDistance > 0) {
        _updateReaderNextChapterPullDistance(
          _readerNextChapterPullDistance - dragDelta.abs(),
        );
      } else if (_readerIsNextChapterForwardDrag(dragDelta, axis: axis) &&
          _readerPreviousChapterPullDistance > 0) {
        _updateReaderPreviousChapterPullDistance(
          _readerPreviousChapterPullDistance - dragDelta.abs(),
        );
      } else {
        if (!nearChapterStart) {
          _clearReaderPreviousChapterPullState();
        }
        if (!nearChapterEnd) {
          _clearReaderNextChapterPullState();
        }
      }
      return;
    }

    if (notification is ScrollUpdateNotification) {
      final DragUpdateDetails? dragDetails = notification.dragDetails;
      if (dragDetails == null) {
        if (!_readerScrollControllerAtTop(controller)) {
          _clearReaderPreviousChapterPullState();
        }
        if (!_readerScrollControllerAtBottom(controller)) {
          _clearReaderNextChapterPullState();
        }
        return;
      }
      final double dragDelta = dragDetails.primaryDelta ?? 0;
      if (_readerIsNextChapterForwardDrag(dragDelta, axis: axis) &&
          nearChapterEnd) {
        _clearReaderPreviousChapterPullState();
        _updateReaderNextChapterPullDistance(
          _readerNextChapterPullDistance + dragDelta.abs(),
        );
      } else if (_readerIsNextChapterBackwardDrag(dragDelta, axis: axis) &&
          nearChapterStart) {
        _clearReaderNextChapterPullState();
        _updateReaderPreviousChapterPullDistance(
          _readerPreviousChapterPullDistance + dragDelta.abs(),
        );
      } else if (_readerIsNextChapterBackwardDrag(dragDelta, axis: axis) &&
          _readerNextChapterPullDistance > 0) {
        _updateReaderNextChapterPullDistance(
          _readerNextChapterPullDistance - dragDelta.abs(),
        );
      } else if (_readerIsNextChapterForwardDrag(dragDelta, axis: axis) &&
          _readerPreviousChapterPullDistance > 0) {
        _updateReaderPreviousChapterPullDistance(
          _readerPreviousChapterPullDistance - dragDelta.abs(),
        );
      } else {
        if (!nearChapterStart) {
          _clearReaderPreviousChapterPullState();
        }
        if (!nearChapterEnd) {
          _clearReaderNextChapterPullState();
        }
      }
      return;
    }

    if (notification is ScrollEndNotification) {
      if (_readerPreviousChapterPullReady) {
        unawaited(_triggerReaderPreviousChapter(page));
      } else if (_readerNextChapterPullReady) {
        unawaited(_triggerReaderNextChapter(page));
      } else {
        _clearReaderPreviousChapterPullState();
        _clearReaderNextChapterPullState();
      }
      return;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      if (_readerPreviousChapterPullReady) {
        unawaited(_triggerReaderPreviousChapter(page));
      } else if (_readerNextChapterPullReady) {
        unawaited(_triggerReaderNextChapter(page));
      } else {
        _clearReaderPreviousChapterPullState();
        _clearReaderNextChapterPullState();
      }
      return;
    }

    if (!nearChapterStart) {
      _clearReaderPreviousChapterPullState();
    }
    if (!nearChapterEnd) {
      _clearReaderNextChapterPullState();
    }
  }
}
