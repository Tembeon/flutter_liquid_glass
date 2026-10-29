import 'package:flutter/widgets.dart';

/// What a scroll view's content is doing.
///
/// UIKit: a `UIScrollView`'s `isTracking`, `isDecelerating` and
/// `setContentOffset(_:animated:)`. SwiftUI: `ScrollPhase`. Flutter: the
/// scroll activity behind `ScrollPosition`.
enum MotionScrollPhase {
  /// At rest.
  idle,

  /// A finger drags the content, or holds it after a drag.
  dragging,

  /// The content glides on after a finger let go of it.
  decelerating,

  /// The app moves the content: `animateTo`, `jumpTo`, a scroll to the top.
  programmatic,
}

/// Follows one scroll view through the notifications it dispatches, so any
/// scrollable reports to it without its controller being passed around.
///
/// UIKit: a `UIScrollView`'s delegate (`scrollViewDidScroll`).
/// SwiftUI: `onScrollGeometryChange` with `onScrollPhaseChange`. Flutter: a
/// `NotificationListener<ScrollNotification>` over a `ScrollController`.
///
/// Give [handle] to a `NotificationListener<Notification>` above the scroll
/// view. It takes the scroll notifications [predicate] accepts, depth 0 by
/// default, so the inner scroll of a nested scroll view goes unheard unless
/// the predicate selects it. A scroll view dispatches its notifications as
/// its offset changes, so [metrics] is current in the frame the content
/// moved in; it is null until the scroll view has laid out and reported
/// once, and its extents are those of the last layout. Listeners hear every
/// change of [metrics] or [phase].
class MotionScrollObserver extends ChangeNotifier {
  /// Creates an observer of the scroll notifications [predicate] accepts.
  MotionScrollObserver({this.predicate = defaultScrollNotificationPredicate});

  /// Which scroll notifications the observer follows.
  final ScrollNotificationPredicate predicate;

  ScrollMetrics? _metrics;
  MotionScrollPhase _phase = MotionScrollPhase.idle;
  ScrollPosition? _position;

  /// The scroll view's metrics from its latest notification, or null before
  /// its first.
  ScrollMetrics? get metrics => _metrics;

  /// What the content is doing.
  MotionScrollPhase get phase => _phase;

  /// The position of the scroll view the latest notification came from: to
  /// scroll it to its start when the status bar is tapped, say.
  ScrollPosition? get position => _position;

  /// Follows [notification] if it is a scroll or scroll metrics
  /// notification [predicate] accepts; lets every notification bubble on.
  bool handle(Notification notification) {
    final scroll = switch (notification) {
      ScrollNotification() => notification,
      ScrollMetricsNotification() => notification.asScrollUpdate(),
      _ => null,
    };
    if (scroll == null || !predicate(scroll)) return false;
    final phase = notification is ScrollMetricsNotification
        ? _phase
        : _next(scroll);
    final metrics = scroll.metrics.copyWith();
    final context = scroll.context;
    if (context != null && context.mounted) {
      _position = Scrollable.maybeOf(context)?.position ?? _position;
    }
    if (phase == _phase && _same(metrics, _metrics)) return false;
    _phase = phase;
    _metrics = metrics;
    notifyListeners();
    return false;
  }

  MotionScrollPhase _next(ScrollNotification notification) {
    final user =
        _phase == MotionScrollPhase.dragging ||
        _phase == MotionScrollPhase.decelerating;
    return switch (notification) {
      ScrollStartNotification(dragDetails: _?) => MotionScrollPhase.dragging,
      ScrollStartNotification() =>
        user ? MotionScrollPhase.decelerating : MotionScrollPhase.programmatic,
      ScrollUpdateNotification(dragDetails: _?) ||
      OverscrollNotification(dragDetails: _?) => MotionScrollPhase.dragging,
      ScrollUpdateNotification() || OverscrollNotification() =>
        user
            ? MotionScrollPhase.decelerating
            : _phase == MotionScrollPhase.idle
            ? MotionScrollPhase.programmatic
            : _phase,
      ScrollEndNotification() => MotionScrollPhase.idle,
      _ => _phase,
    };
  }

  static bool _same(ScrollMetrics a, ScrollMetrics? b) =>
      b != null &&
      a.pixels == b.pixels &&
      a.axisDirection == b.axisDirection &&
      a.hasContentDimensions == b.hasContentDimensions &&
      (!a.hasContentDimensions ||
          (a.minScrollExtent == b.minScrollExtent &&
              a.maxScrollExtent == b.maxScrollExtent)) &&
      (!a.hasViewportDimension ||
          !b.hasViewportDimension ||
          a.viewportDimension == b.viewportDimension);
}
