import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/page_models.dart';

typedef ReaderBoundaryNavigationCallback =
    Future<void> Function(
      String href, {
      String prevHref,
      String nextHref,
      String catalogHref,
    });

class ReaderChapterBoundaryController {
  ReaderChapterBoundaryController({
    required this.triggerDistance,
    required this.readingDirection,
    required this.isZoomLocked,
    required this.flushProgress,
    required this.onRequestChapterNavigation,
    required this.notify,
  });

  final double Function() triggerDistance;
  final ReaderReadingDirection Function() readingDirection;
  final bool Function() isZoomLocked;
  final Future<void> Function() flushProgress;
  final ReaderBoundaryNavigationCallback onRequestChapterNavigation;
  final VoidCallback notify;

  bool _isLoading = false;
  double _previousDistance = 0;
  double _nextDistance = 0;

  bool get isLoading => _isLoading;
  double get previousDistance => _previousDistance;
  double get nextDistance => _nextDistance;
  bool get previousReady => _previousDistance >= triggerDistance();
  bool get nextReady => _nextDistance >= triggerDistance();

  void clearPrevious() {
    if (_previousDistance <= 0) return;
    _previousDistance = 0;
    notify();
  }

  void clearNext() {
    if (_nextDistance <= 0) return;
    _nextDistance = 0;
    notify();
  }

  void reset() {
    if (_previousDistance <= 0 && _nextDistance <= 0 && !_isLoading) {
      return;
    }
    _previousDistance = 0;
    _nextDistance = 0;
    _isLoading = false;
    notify();
  }

  Future<void> triggerPrevious(ReaderPageData page) async {
    final String prevHref = page.prevHref.trim();
    if (prevHref.isEmpty || _isLoading) {
      clearPrevious();
      return;
    }
    _isLoading = true;
    notify();
    try {
      await flushProgress();
      await onRequestChapterNavigation(
        prevHref,
        nextHref: page.uri,
        catalogHref: page.catalogHref,
      );
    } finally {
      reset();
    }
  }

  Future<void> triggerNext(ReaderPageData page) async {
    final String nextHref = page.nextHref.trim();
    if (nextHref.isEmpty || _isLoading) {
      clearNext();
      return;
    }
    _isLoading = true;
    notify();
    try {
      await flushProgress();
      await onRequestChapterNavigation(
        nextHref,
        prevHref: page.uri,
        catalogHref: page.catalogHref,
      );
    } finally {
      reset();
    }
  }

  void handlePull(
    ScrollNotification notification, {
    required ReaderPageData page,
    required ScrollController controller,
    required bool Function(ScrollController controller, {double tolerance})
    controllerAtTop,
    required bool Function(ScrollController controller, {double tolerance})
    controllerAtBottom,
    Axis axis = Axis.vertical,
  }) {
    final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    if ((!hasPreviousChapter && !hasNextChapter) ||
        isZoomLocked() ||
        notification.depth != 0 ||
        notification.metrics.axis != axis ||
        _isLoading) {
      if (!_isLoading) {
        clearPrevious();
        clearNext();
      }
      return;
    }

    final bool nearChapterStart =
        hasPreviousChapter &&
        (_metricsNearChapterStart(notification.metrics, axis: axis) ||
            controllerAtTop(controller, tolerance: _pullActivationExtent));
    final bool nearChapterEnd =
        hasNextChapter &&
        (_metricsNearChapterEnd(notification.metrics, axis: axis) ||
            controllerAtBottom(controller, tolerance: _pullActivationExtent));

    if (notification is OverscrollNotification) {
      _handleDragDelta(
        notification.dragDetails?.primaryDelta ?? 0,
        axis: axis,
        nearChapterStart: nearChapterStart,
        nearChapterEnd: nearChapterEnd,
      );
      return;
    }

    if (notification is ScrollUpdateNotification) {
      final DragUpdateDetails? dragDetails = notification.dragDetails;
      if (dragDetails == null) {
        if (!controllerAtTop(controller)) {
          clearPrevious();
        }
        if (!controllerAtBottom(controller)) {
          clearNext();
        }
        return;
      }
      _handleDragDelta(
        dragDetails.primaryDelta ?? 0,
        axis: axis,
        nearChapterStart: nearChapterStart,
        nearChapterEnd: nearChapterEnd,
      );
      return;
    }

    if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      if (previousReady) {
        unawaited(triggerPrevious(page));
      } else if (nextReady) {
        unawaited(triggerNext(page));
      } else {
        clearPrevious();
        clearNext();
      }
      return;
    }

    if (!nearChapterStart) clearPrevious();
    if (!nearChapterEnd) clearNext();
  }

  void addNextDistance(double distance) {
    _updateNextDistance(_nextDistance + distance);
  }

  void addPreviousDistance(double distance) {
    _updatePreviousDistance(_previousDistance + distance);
  }

  bool _metricsNearChapterStart(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _pullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentBefore <= threshold;
  }

  bool _metricsNearChapterEnd(
    ScrollMetrics metrics, {
    required Axis axis,
    double threshold = _pullActivationExtent,
  }) {
    return metrics.axis == axis && metrics.extentAfter <= threshold;
  }

  bool _isForwardDrag(double dragDelta, {required Axis axis}) {
    if (axis == Axis.vertical) return dragDelta < 0;
    return switch (readingDirection()) {
      ReaderReadingDirection.leftToRight => dragDelta < 0,
      ReaderReadingDirection.rightToLeft => dragDelta > 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  bool _isBackwardDrag(double dragDelta, {required Axis axis}) {
    if (axis == Axis.vertical) return dragDelta > 0;
    return switch (readingDirection()) {
      ReaderReadingDirection.leftToRight => dragDelta > 0,
      ReaderReadingDirection.rightToLeft => dragDelta < 0,
      ReaderReadingDirection.topToBottom => false,
    };
  }

  void _handleDragDelta(
    double dragDelta, {
    required Axis axis,
    required bool nearChapterStart,
    required bool nearChapterEnd,
  }) {
    if (_isForwardDrag(dragDelta, axis: axis) && nearChapterEnd) {
      clearPrevious();
      _updateNextDistance(_nextDistance + dragDelta.abs());
      return;
    }
    if (_isBackwardDrag(dragDelta, axis: axis) && nearChapterStart) {
      clearNext();
      _updatePreviousDistance(_previousDistance + dragDelta.abs());
      return;
    }
    if (_isBackwardDrag(dragDelta, axis: axis) && _nextDistance > 0) {
      _updateNextDistance(_nextDistance - dragDelta.abs());
    } else if (_isForwardDrag(dragDelta, axis: axis) && _previousDistance > 0) {
      _updatePreviousDistance(_previousDistance - dragDelta.abs());
    } else {
      if (!nearChapterStart) clearPrevious();
      if (!nearChapterEnd) clearNext();
    }
  }

  void _updateNextDistance(double distance) {
    final double clampedDistance = distance
        .clamp(0, triggerDistance() * 1.6)
        .toDouble();
    final bool ready = clampedDistance >= triggerDistance();
    if ((_nextDistance - clampedDistance).abs() < 0.5 && nextReady == ready) {
      return;
    }
    _nextDistance = clampedDistance;
    notify();
  }

  void _updatePreviousDistance(double distance) {
    final double clampedDistance = distance
        .clamp(0, triggerDistance() * 1.6)
        .toDouble();
    final bool ready = clampedDistance >= triggerDistance();
    if ((_previousDistance - clampedDistance).abs() < 0.5 &&
        previousReady == ready) {
      return;
    }
    _previousDistance = clampedDistance;
    notify();
  }
}

const double _pullActivationExtent = 100;
