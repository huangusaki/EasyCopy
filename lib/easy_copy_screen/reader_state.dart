part of '../easy_copy_screen.dart';

extension _EasyCopyScreenReaderState on _EasyCopyScreenState {
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
    _setStateIfMounted(() {
      _currentVisibleReaderImageIndex = bestIndex;
    });
  }
}
