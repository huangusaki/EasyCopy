part of '../easy_copy_screen.dart';

extension _EasyCopyScreenScrollRestore on _EasyCopyScreenState {
  bool _isUserDrivenScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    return switch (notification) {
      ScrollStartNotification(:final DragStartDetails? dragDetails) =>
        dragDetails != null,
      ScrollUpdateNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      OverscrollNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      _ => false,
    };
  }

  bool _handleStandardScrollNotification(ScrollNotification notification) {
    if (_isUserDrivenScrollNotification(notification)) {
      _noteStandardViewportUserInteraction();
    }
    return false;
  }

  void _noteStandardViewportUserInteraction() {
    _standardScrollRestoreCoordinator.noteUserInteraction();
    _detailChapterAutoScrollCoordinator.noteUserInteraction();
    _suspendStandardScrollTracking = false;
  }

  bool _isActiveStandardScrollRestore(
    DeferredViewportTicket ticket, {
    required int tabIndex,
    required String routeKey,
  }) {
    return mounted &&
        _standardScrollRestoreCoordinator.isActive(ticket) &&
        !_isReaderMode &&
        _selectedIndex == tabIndex &&
        _currentEntry.routeKey == routeKey;
  }

  void _finishStandardScrollRestore(DeferredViewportTicket ticket) {
    if (_standardScrollRestoreCoordinator.isLatestRequest(ticket)) {
      _suspendStandardScrollTracking = false;
    }
  }

  bool _isActiveDetailChapterAutoScroll(
    DeferredViewportTicket ticket, {
    required String routeKey,
  }) {
    return mounted &&
        _detailChapterAutoScrollCoordinator.isActive(ticket) &&
        _page is DetailPageData &&
        _currentEntry.routeKey == routeKey;
  }

  void _persistVisiblePageState() {
    final EasyCopyPage? page = _page;
    if (page is ReaderPageData) {
      unawaited(
        _readerScreenKey.currentState?.controller.flushProgressPersistence() ??
            Future<void>.value(),
      );
      return;
    }
    if (page == null || !_standardScrollController.hasClients) {
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
    final DeferredViewportTicket ticket = _standardScrollRestoreCoordinator
        .beginRequest();
    _suspendStandardScrollTracking = true;
    if (_standardScrollController.hasClients) {
      _standardScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_standardScrollRestoreCoordinator.isActive(ticket)) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (!mounted) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (!_standardScrollController.hasClients) {
        _finishStandardScrollRestore(ticket);
        return;
      }
      if (_standardScrollController.offset != 0) {
        _standardScrollController.jumpTo(0);
      }
      _finishStandardScrollRestore(ticket);
    });
  }

  void _restoreStandardScrollPosition(
    double offset, {
    required int tabIndex,
    required String routeKey,
  }) {
    final DeferredViewportTicket ticket = _standardScrollRestoreCoordinator
        .beginRequest();
    _suspendStandardScrollTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpStandardToOffset(
        offset,
        tabIndex: tabIndex,
        routeKey: routeKey,
        attempts: 10,
        ticket: ticket,
      );
    });
  }

  void _jumpStandardToOffset(
    double offset, {
    required int tabIndex,
    required String routeKey,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveStandardScrollRestore(
      ticket,
      tabIndex: tabIndex,
      routeKey: routeKey,
    )) {
      _finishStandardScrollRestore(ticket);
      return;
    }
    if (!_standardScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => _jumpStandardToOffset(
            offset,
            tabIndex: tabIndex,
            routeKey: routeKey,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
        return;
      }
      _finishStandardScrollRestore(ticket);
      return;
    }

    final double maxExtent = _standardScrollController.position.maxScrollExtent;
    final double clampedOffset = offset.clamp(0, maxExtent).toDouble();
    if ((offset - clampedOffset).abs() > 1 && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _jumpStandardToOffset(
          offset,
          tabIndex: tabIndex,
          routeKey: routeKey,
          attempts: attempts - 1,
          ticket: ticket,
        ),
      );
      return;
    }

    _standardScrollController.jumpTo(clampedOffset);
    _finishStandardScrollRestore(ticket);
    _tabSessionStore.updateScroll(tabIndex, routeKey, clampedOffset);
  }

  Future<void> _scrollCurrentStandardPageToTop() async {
    if (!_standardScrollController.hasClients) {
      return;
    }
    _noteStandardViewportUserInteraction();
    await _standardScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _tabSessionStore.updateScroll(_selectedIndex, _currentEntry.routeKey, 0);
  }
}
