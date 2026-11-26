import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

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
  programmatic;

  /// Whether the user moves the content: a finger drags it or it glides on
  /// after one let go.
  bool get byUser => this == dragging || this == decelerating;
}

/// One scroll view as a motion: its metrics and phase as signals written
/// as its notifications arrive, so a selection over it (a large title's
/// fade, a bar that minimizes, an edge effect) follows the content without
/// a listener of its own.
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
/// once, and its extents are those of the last layout. A selection over
/// the scroll recomputes once per frame: a render listener hears it before
/// that frame paints, even when the notification came during layout.
final class MotionScroll extends Motion {
  /// Creates the motion of the scroll view whose notifications [predicate]
  /// accepts.
  MotionScroll({
    this.predicate = defaultScrollNotificationPredicate,
    super.clock,
  });

  /// Which scroll notifications the motion follows.
  final ScrollNotificationPredicate predicate;

  late final MotionSignal<ScrollMetrics?> _metrics = own(MotionSignal(null));
  late final MotionSignal<MotionScrollPhase> _phase = own(
    MotionSignal(MotionScrollPhase.idle),
  );
  ScrollPosition? _position;
  double? _glideTarget;
  ({double pixels, double t})? _glideStart;

  /// The scroll view's metrics from its latest notification, or null before
  /// its first.
  ScrollMetrics? get metrics => _metrics.value;

  /// What the content is doing.
  MotionScrollPhase get phase => _phase.value;

  /// The position of the scroll view the latest notification came from: to
  /// scroll it to its start when the status bar is tapped, say.
  ScrollPosition? get position => _position;

  /// Where the content comes to rest while it glides on after a finger let
  /// go of it, or null in any other phase.
  ///
  /// UIKit: a decelerating `UIScrollView`'s target offset. Flutter keeps a
  /// glide's simulation to its scroll position, so this one is the
  /// position's physics run on from the glide's second frame at the speed of
  /// its first, timed by the frames: known a frame into the glide, and off
  /// by the friction of one frame.
  double? get glideTarget => _glideTarget;

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
        ? this.phase
        : _next(scroll);
    final metrics = scroll.metrics.copyWith();
    final context = scroll.context;
    if (context != null && context.mounted) {
      _position = Scrollable.maybeOf(context)?.position ?? _position;
    }
    final t = clock.now;
    final frame =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds /
        Duration.microsecondsPerSecond;
    if (phase != MotionScrollPhase.decelerating) {
      _glideTarget = null;
      _glideStart = null;
    } else if (_glideStart == null) {
      _glideStart = (pixels: metrics.pixels, t: frame);
    } else {
      _glideTarget ??= _glideFrom(metrics, frame);
    }
    if (phase != this.phase) _phase.write(t, phase);
    if (!_same(metrics, this.metrics)) _metrics.write(t, metrics);
    return false;
  }

  // A glide's simulation runs out well within this many seconds.
  static const double _glideHorizon = 10;

  double? _glideFrom(ScrollMetrics metrics, double t) {
    final start = _glideStart!;
    final position = _position;
    if (position == null || t <= start.t) return null;
    final velocity = (metrics.pixels - start.pixels) / (t - start.t);
    final glide = position.physics.createBallisticSimulation(metrics, velocity);
    return glide?.x(_glideHorizon) ?? metrics.pixels;
  }

  MotionScrollPhase _next(ScrollNotification notification) {
    final user = phase.byUser;
    return switch (notification) {
      ScrollStartNotification(dragDetails: _?) => MotionScrollPhase.dragging,
      ScrollStartNotification() =>
        user ? MotionScrollPhase.decelerating : MotionScrollPhase.programmatic,
      ScrollUpdateNotification(dragDetails: _?) ||
      OverscrollNotification(dragDetails: _?) => MotionScrollPhase.dragging,
      ScrollUpdateNotification() || OverscrollNotification() =>
        user
            ? MotionScrollPhase.decelerating
            : phase == MotionScrollPhase.idle
            ? MotionScrollPhase.programmatic
            : phase,
      ScrollEndNotification() => MotionScrollPhase.idle,
      _ => phase,
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
