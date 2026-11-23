import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';

/// Result of a single [ScrollDeceleration.step].
@immutable
final class ScrollStep {
  /// Creates a scroll step result.
  const ScrollStep({
    required this.offset,
    required this.velocity,
    required this.settled,
  });

  /// The updated content offset, in logical pixels.
  final double offset;

  /// The updated velocity, in logical pixels per second.
  final double velocity;

  /// Whether the deceleration or edge bounce has come to rest.
  final bool settled;

  @override
  bool operator ==(Object other) =>
      other is ScrollStep &&
      other.offset == offset &&
      other.velocity == velocity &&
      other.settled == settled;

  @override
  int get hashCode => Object.hash(offset, velocity, settled);

  @override
  String toString() =>
      'ScrollStep(offset: $offset, velocity: $velocity, settled: $settled)';
}

/// UIKit `UIScrollView` exponential deceleration and unified edge-bounce
/// physics (`UIScrollView.DecelerationRate`).
///
/// Inside `[min, max]`, velocity decays exponentially at [rate] per
/// millisecond (`v(t) = v0 * rate^(1000 * t)`) until its speed falls below
/// [stopSpeed]. Past either edge, overscroll decays at the [fast] rate while
/// remaining velocity decays at both rates, snapping to the edge once within
/// [edgeSnapDistance].
@immutable
final class ScrollDeceleration {
  /// Creates a deceleration law with per-millisecond [rate] in `(0, 1)`.
  const ScrollDeceleration(this.rate)
    : assert(rate > 0 && rate < 1, 'rate must be strictly between 0 and 1');

  /// `UIScrollView.DecelerationRate.normal`; [Spring.normalProjection] is
  /// its [projectionTime].
  static const ScrollDeceleration normal = ScrollDeceleration(
    normalDecelerationRate,
  );

  /// `UIScrollView.DecelerationRate.fast`.
  static const ScrollDeceleration fast = ScrollDeceleration(0.99);

  /// Speed below which free deceleration stops, in logical pixels per
  /// second.
  static const double stopSpeed = 10;

  /// Distance from the boundary within which an edge bounce snaps to rest,
  /// in logical pixels.
  static const double edgeSnapDistance = 0.5;

  static final double _bounceDecayRate = math.log(fast.rate);

  /// Velocity retention factor per millisecond (`0 < rate < 1`).
  final double rate;

  /// How many seconds ahead at the current velocity a fling projects:
  /// `rate / (1000 * (1 - rate))`.
  double get projectionTime => rate / (1000 * (1 - rate));

  /// The velocity after [elapsedSeconds] of free deceleration from
  /// [initialVelocity] (logical pixels per second).
  double velocityAt(double initialVelocity, double elapsedSeconds) {
    if (elapsedSeconds <= 0) return initialVelocity;
    return initialVelocity * math.pow(rate, 1000 * elapsedSeconds);
  }

  /// The projected landing offset (UIKit `targetContentOffset`) for a release
  /// at [offset] moving at [velocity] logical pixels per second.
  double landingOffset(double offset, double velocity) {
    final speed = velocity.abs();
    if (speed <= stopSpeed) return offset;
    return offset + (velocity - stopSpeed * velocity.sign) * projectionTime;
  }

  /// Advances a decelerating or bouncing scroll offset by [dt] seconds inside
  /// `[min, max]`.
  ///
  /// [velocity] is in logical pixels per second. When [bounces] is false,
  /// crossing `[min, max]` clamps to the boundary and settles immediately.
  ScrollStep step({
    required double offset,
    required double velocity,
    required double dt,
    required double min,
    required double max,
    bool bounces = true,
  }) {
    if (dt <= 0) {
      return ScrollStep(offset: offset, velocity: velocity, settled: false);
    }
    final dtMs = dt * 1000;
    final vMs = velocity / 1000;
    final lnF = math.log(rate);

    if (offset < min || offset > max) {
      if (!bounces) {
        return ScrollStep(
          offset: offset.clamp(min, max),
          velocity: 0,
          settled: true,
        );
      }
      return _stepOutside(
        y: offset,
        vMs: vMs,
        tMs: dtMs,
        edge: offset < min ? min : max,
        lnF: lnF,
      );
    }

    final d = _approxExp(lnF * dtMs);
    final nextY = offset + vMs * rate * (1 - d) / (1 - rate);
    final nextV = vMs * d;

    if (nextY < min || nextY > max) {
      final edge = nextY < min ? min : max;
      if (!bounces) {
        return ScrollStep(offset: edge, velocity: 0, settled: true);
      }
      final frac = ((edge - offset) / (nextY - offset)).clamp(0.0, 1.0);
      final tInside = dtMs * frac;
      final tOutside = dtMs - tInside;
      final dIn = _approxExp(lnF * tInside);
      final vAtEdge = vMs * dIn;
      return _stepOutside(
        y: edge,
        vMs: vAtEdge,
        tMs: tOutside,
        edge: edge,
        lnF: lnF,
      );
    }

    if (nextV.abs() < stopSpeed / 1000) {
      return ScrollStep(offset: nextY, velocity: 0, settled: true);
    }
    return ScrollStep(offset: nextY, velocity: nextV * 1000, settled: false);
  }

  ScrollStep _stepOutside({
    required double y,
    required double vMs,
    required double tMs,
    required double edge,
    required double lnF,
  }) {
    final p = _approxExp(lnF * tMs);
    final k = _approxExp(_bounceDecayRate * tMs);
    final nextY = edge + k * (y - edge) + (1 - p) * rate * k * vMs / (1 - rate);
    final nextV = p * k * vMs;
    final displacement = nextY - edge;
    if (displacement.abs() < edgeSnapDistance &&
        displacement.abs() <= (y - edge).abs()) {
      return ScrollStep(offset: edge, velocity: 0, settled: true);
    }
    return ScrollStep(offset: nextY, velocity: nextV * 1000, settled: false);
  }

  /// UIKit's 2nd-order Taylor approximation used for small negative exponents
  /// (`x >= -0.5`), falling back to `exp(x)` otherwise.
  static double _approxExp(double x) =>
      x >= -0.5 ? 1 + x + 0.5 * x * x : math.exp(x);

  /// UIKit's animated zoom duration for `setZoomScale(_:animated:)`:
  /// `min(0.1 + 0.3 * ln(max(s1, s0) / min(s1, s0)), 0.4)` seconds.
  static double zoomDuration(double fromScale, double toScale) {
    assert(fromScale > 0 && toScale > 0, 'zoom scales must be positive');
    final ratio = fromScale > toScale
        ? fromScale / toScale
        : toScale / fromScale;
    return math.min(0.1 + 0.3 * math.log(ratio), 0.4);
  }

  @override
  bool operator ==(Object other) =>
      other is ScrollDeceleration && other.rate == rate;

  @override
  int get hashCode => rate.hashCode;

  @override
  String toString() => 'ScrollDeceleration($rate)';
}

/// UIKit `UIScrollView.isPagingEnabled` and `UIPageViewController` page target
/// selection and settling spring.
///
/// A release faster than [velocityThreshold] flips one page in the gesture
/// direction; otherwise it settles to the nearest page. Settles on [spring].
@immutable
final class PagingPhysics {
  /// Creates paging physics.
  const PagingPhysics({
    this.velocityThreshold = defaultVelocityThreshold,
    this.spring = defaultSpring,
  }) : assert(velocityThreshold >= 0, 'velocityThreshold must be non-negative');

  /// Measured UIKit pan velocity threshold to flip a page, in logical pixels
  /// per second (`0.3 pt/ms`).
  static const double defaultVelocityThreshold = 300;

  /// Measured UIKit paging settle spring, from its natural frequency in
  /// radians a second.
  static const Spring defaultSpring = Spring.response(
    2 * math.pi / 15.9,
    dampingRatio: 0.88,
  );

  /// Minimum release velocity (logical pixels per second) that flips one page
  /// in the direction of motion regardless of distance.
  final double velocityThreshold;

  /// The spring settling the scroll offset onto the chosen page.
  final Spring spring;

  /// Chooses the destination page index in `0 .. pageCount - 1` for a release
  /// at [offset] (logical pixels) with pan [velocity] (logical pixels per
  /// second, positive toward higher page indices) and page width/height
  /// [pageExtent].
  int targetPage({
    required double offset,
    required double pageExtent,
    required double velocity,
    required int pageCount,
  }) {
    if (pageCount <= 1 || pageExtent <= 0) return 0;
    final raw = offset / pageExtent;
    final int candidate;
    if (velocity > velocityThreshold) {
      candidate = raw.floor() + 1;
    } else if (velocity < -velocityThreshold) {
      candidate = raw.ceil() - 1;
    } else {
      candidate = raw.round();
    }
    return candidate.clamp(0, pageCount - 1);
  }

  /// Chooses the destination scroll offset (`targetPage * pageExtent`).
  double targetOffset({
    required double offset,
    required double pageExtent,
    required double velocity,
    required int pageCount,
  }) =>
      targetPage(
        offset: offset,
        pageExtent: pageExtent,
        velocity: velocity,
        pageCount: pageCount,
      ) *
      pageExtent;

  @override
  bool operator ==(Object other) =>
      other is PagingPhysics &&
      other.velocityThreshold == velocityThreshold &&
      other.spring == spring;

  @override
  int get hashCode => Object.hash(velocityThreshold, spring);

  @override
  String toString() =>
      'PagingPhysics(velocityThreshold: $velocityThreshold, spring: $spring)';
}

/// UIKit's status-bar tap scroll-to-top curve (`UIScrollView.scrollsToTop`).
///
/// Runs over [duration] as a critically damped spring evaluated through a
/// cubic Bezier timing function, both measured: it reaches about half the
/// distance at 0.07 s and nine tenths at 0.24 s, whatever the distance.
final class ScrollToTopCurve extends Curve {
  /// Creates the scroll-to-top curve.
  const ScrollToTopCurve();

  /// Total duration of a UIKit scroll-to-top animation, in seconds.
  static const double duration = 1.6;

  /// Ready-to-use [TimingCurve] for scroll-to-top animations.
  static const TimingCurve timing = TimingCurve(
    duration,
    curve: ScrollToTopCurve(),
  );

  static const Cubic _timeCurve = Cubic(0, 0.2, 1, 1);
  static const double _omega = 2 * math.pi / 0.6;

  @override
  double transformInternal(double t) {
    final u = _timeCurve.transform(t);
    final s = _omega * duration * u;
    return 1 - math.exp(-s) * (1 + s);
  }

  @override
  String toString() => 'ScrollToTopCurve()';
}
