import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// UIKit's paging for a `PageView`: the page view controller's scroll
/// style, or a scroll view with `isPagingEnabled`.
///
/// UIKit: `UIPageViewController` with `.scroll`, and
/// `UIScrollView.isPagingEnabled`. SwiftUI: `TabView` with
/// `.tabViewStyle(.page)`. Flutter: `PageScrollPhysics`.
///
/// ```dart
/// PageView(
///   pageSnapping: false,
///   physics: const GlassPageScrollPhysics(),
///   children: pages,
/// )
/// ```
///
/// A release turns one page the way the finger moves when it moves faster
/// than 300 points a second, whatever the distance, and goes to the
/// nearest page otherwise: past half a page it turns. Either way the page
/// settles on one spring (omega 15.9, damping 0.88, about 0.35 s whatever
/// the distance) from the release's speed. Past the first and the last
/// page the content follows the finger on UIKit's rubber band (slope 0.55
/// over a page) and springs back on the same spring ([PagingPhysics]).
/// Give the page view `pageSnapping: false`, which leaves the choice of the
/// page to these physics; with Flutter's snapping on, the page still
/// settles on UIKit's spring but turns at any speed. A page turned from
/// code moves as UIKit's does with [turnFromCode].
///
/// Fidelity. The page choice, the settle and the edge are measured on the
/// iOS 27.2 simulator (page view and scroll view passports); the finger's
/// slop is Flutter's (18 points), not UIKit's 10.
class GlassPageScrollPhysics extends ScrollPhysics {
  /// Creates UIKit's paging physics.
  const GlassPageScrollPhysics({super.parent});

  static const _paging = PagingPhysics();

  /// How a page turned from code moves: ease in and out over 0.32 s
  /// (`setViewControllers(_:direction:animated: true)`).
  static const turnFromCode = (
    duration: Duration(milliseconds: 320),
    curve: Curves.easeInOut,
  );

  @override
  GlassPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      GlassPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring {
    final spring = _paging.spring;
    return SpringDescription(
      mass: 1,
      stiffness: spring.stiffness,
      damping: spring.damping,
    );
  }

  double _pageOf(ScrollMetrics position) => position is PageMetrics
      ? position.viewportDimension * position.viewportFraction
      : position.viewportDimension;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final band = RubberBand(
      position.minScrollExtent,
      position.maxScrollExtent,
      dimension: position.viewportDimension,
    );
    final raw = band.invert(position.pixels) - offset;
    return position.pixels - band.apply(raw);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) => 0;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    final page = _pageOf(position);
    final double target;
    if (position.outOfRange || page <= 0) {
      target = position.pixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
    } else {
      final count =
          ((position.maxScrollExtent - position.minScrollExtent) / page)
              .round() +
          1;
      target =
          position.minScrollExtent +
          _paging.targetOffset(
            offset: position.pixels - position.minScrollExtent,
            pageExtent: page,
            velocity: velocity,
            pageCount: count,
          );
    }
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
