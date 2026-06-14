import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/reader_screen.dart';
import 'package:reader/services/deferred_viewport_coordinator.dart';
import 'package:reader/services/primary_tab_session_store.dart';

const double standardScrollSessionStep = 96;

class AppScrollState {
  AppScrollState({
    required this.standardScrollController,
    required this.readerScreenKey,
    required this.tabSessionStore,
    required this.isMounted,
    required this.selectedIndex,
    required this.currentEntry,
    required this.page,
    required this.isReaderMode,
  });

  final ScrollController standardScrollController;
  final GlobalKey<ReaderScreenState> readerScreenKey;
  final PrimaryTabSessionStore tabSessionStore;
  final bool Function() isMounted;
  final int Function() selectedIndex;
  final PrimaryTabRouteEntry Function() currentEntry;
  final SitePage? Function() page;
  final bool Function() isReaderMode;

  final DeferredViewportCoordinator _restore = DeferredViewportCoordinator();

  bool _suspendTracking = false;
  double? _lastOffset;
  String _lastRouteKey = '';

  bool handleScrollNotification(
    ScrollNotification notification, {
    required VoidCallback onUserInteraction,
  }) {
    if (_isUserDrivenScrollNotification(notification)) {
      onUserInteraction();
    }
    return false;
  }

  void noteViewportInteraction() {
    _restore.noteUserInteraction();
    _suspendTracking = false;
  }

  void pauseTrackingForRoute() {
    _suspendTracking = true;
  }

  void persistVisiblePageState() {
    final SitePage? currentPage = page();
    if (currentPage is ReaderPageData) {
      unawaited(
        readerScreenKey.currentState?.controller.flushProgressPersistence() ??
            Future<void>.value(),
      );
      return;
    }
    if (currentPage == null ||
        _suspendTracking ||
        !standardScrollController.hasClients) {
      return;
    }
    final PrimaryTabRouteEntry entry = currentEntry();
    final double offset = standardScrollController.offset;
    if (_lastRouteKey == entry.routeKey &&
        _lastOffset != null &&
        (offset - _lastOffset!).abs() < standardScrollSessionStep) {
      return;
    }
    _lastRouteKey = entry.routeKey;
    _lastOffset = offset;
    tabSessionStore.updateScroll(selectedIndex(), entry.routeKey, offset);
  }

  void handleStandardScroll() {
    if (_suspendTracking ||
        !standardScrollController.hasClients ||
        page() == null ||
        isReaderMode()) {
      return;
    }
    final PrimaryTabRouteEntry entry = currentEntry();
    tabSessionStore.updateScroll(
      selectedIndex(),
      entry.routeKey,
      standardScrollController.offset,
    );
  }

  void resetStandardScrollPosition() {
    final DeferredViewportTicket ticket = _restore.beginRequest();
    _suspendTracking = true;
    if (_canJumpScroll) {
      standardScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_restore.isActive(ticket) ||
          !isMounted() ||
          !_canJumpScroll) {
        _finishRestore(ticket);
        return;
      }
      if (standardScrollController.offset != 0) {
        standardScrollController.jumpTo(0);
      }
      _finishRestore(ticket);
    });
  }

  /// hasClients 早于布局完成，jumpTo 前必须确认 extent。
  bool get _canJumpScroll =>
      standardScrollController.hasClients &&
      standardScrollController.position.hasContentDimensions;

  void restoreStandardScrollPosition(
    double offset, {
    required int tabIndex,
    required String routeKey,
  }) {
    final DeferredViewportTicket ticket = _restore.beginRequest();
    _suspendTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToOffset(
        offset,
        tabIndex: tabIndex,
        routeKey: routeKey,
        attempts: 10,
        ticket: ticket,
      );
    });
  }

  Future<void> scrollCurrentStandardPageToTop({
    required VoidCallback onUserInteraction,
  }) async {
    if (!_canJumpScroll) {
      return;
    }
    onUserInteraction();
    await standardScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    final PrimaryTabRouteEntry entry = currentEntry();
    _lastRouteKey = entry.routeKey;
    _lastOffset = 0;
    tabSessionStore.updateScroll(selectedIndex(), entry.routeKey, 0);
  }

  void moveToAnchor({
    required String routeKey,
    required BuildContext? Function() anchorContext,
  }) {
    final DeferredViewportTicket ticket = _restore.beginRequest();
    _suspendTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToAnchor(
        routeKey,
        anchorContext: anchorContext,
        attempts: 10,
        ticket: ticket,
      );
    });
  }

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

  bool _isActiveRestore(
    DeferredViewportTicket ticket, {
    required int tabIndex,
    required String routeKey,
  }) {
    return isMounted() &&
        _restore.isActive(ticket) &&
        !isReaderMode() &&
        selectedIndex() == tabIndex &&
        currentEntry().routeKey == routeKey;
  }

  void _finishRestore(DeferredViewportTicket ticket) {
    if (_restore.isLatestRequest(ticket)) {
      _suspendTracking = false;
    }
  }

  void _jumpToOffset(
    double offset, {
    required int tabIndex,
    required String routeKey,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    if (!_isActiveRestore(ticket, tabIndex: tabIndex, routeKey: routeKey)) {
      _finishRestore(ticket);
      return;
    }
    if (!_canJumpScroll) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => _jumpToOffset(
            offset,
            tabIndex: tabIndex,
            routeKey: routeKey,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
        return;
      }
      _finishRestore(ticket);
      return;
    }

    final double maxExtent = standardScrollController.position.maxScrollExtent;
    final double clampedOffset = offset.clamp(0, maxExtent).toDouble();
    if ((offset - clampedOffset).abs() > 1 && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _jumpToOffset(
          offset,
          tabIndex: tabIndex,
          routeKey: routeKey,
          attempts: attempts - 1,
          ticket: ticket,
        ),
      );
      return;
    }

    standardScrollController.jumpTo(clampedOffset);
    _finishRestore(ticket);
    _lastRouteKey = routeKey;
    _lastOffset = clampedOffset;
    tabSessionStore.updateScroll(tabIndex, routeKey, clampedOffset);
  }

  void _jumpToAnchor(
    String routeKey, {
    required BuildContext? Function() anchorContext,
    required int attempts,
    required DeferredViewportTicket ticket,
  }) {
    final int tabIndex = selectedIndex();
    if (!_isActiveRestore(ticket, tabIndex: tabIndex, routeKey: routeKey)) {
      _finishRestore(ticket);
      return;
    }
    final BuildContext? context = anchorContext();
    if (context == null || !standardScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 80),
          () => _jumpToAnchor(
            routeKey,
            anchorContext: anchorContext,
            attempts: attempts - 1,
            ticket: ticket,
          ),
        );
        return;
      }
      _jumpToOffset(
        0,
        tabIndex: tabIndex,
        routeKey: routeKey,
        attempts: 0,
        ticket: ticket,
      );
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        context,
        duration: Duration.zero,
        alignment: 0,
      ).whenComplete(() {
        if (_isActiveRestore(ticket, tabIndex: tabIndex, routeKey: routeKey) &&
            standardScrollController.hasClients) {
          tabSessionStore.updateScroll(
            tabIndex,
            routeKey,
            standardScrollController.offset,
          );
        }
        _finishRestore(ticket);
      }),
    );
  }
}
