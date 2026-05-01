import 'package:flutter/widgets.dart';

class ReaderPagedScrollPhysics extends PageScrollPhysics {
  const ReaderPagedScrollPhysics({this.triggerPageRatio = 0.5, super.parent})
    : assert(triggerPageRatio > 0 && triggerPageRatio < 1);

  final double triggerPageRatio;

  @override
  ReaderPagedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ReaderPagedScrollPhysics(
      triggerPageRatio: triggerPageRatio,
      parent: buildParent(ancestor),
    );
  }

  double _pageExtent(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.viewportDimension * position.viewportFraction;
    }
    return position.viewportDimension;
  }

  double _getPage(ScrollMetrics position) {
    if (position is PageMetrics && position.page != null) {
      return position.page!;
    }
    return position.pixels / _pageExtent(position);
  }

  double _getPixels(ScrollMetrics position, double page) {
    return page * _pageExtent(position);
  }

  double _getTargetPixels(
    ScrollMetrics position,
    Tolerance tolerance,
    double velocity,
  ) {
    double page = _getPage(position);
    if (velocity < -tolerance.velocity) {
      page -= triggerPageRatio;
    } else if (velocity > tolerance.velocity) {
      page += triggerPageRatio;
    } else {
      final double nearestPage = page.roundToDouble();
      final double delta = page - nearestPage;
      if (delta <= -triggerPageRatio) {
        page = nearestPage - 1;
      } else if (delta >= triggerPageRatio) {
        page = nearestPage + 1;
      } else {
        page = nearestPage;
      }
      return _getPixels(position, page);
    }
    return _getPixels(position, page.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
