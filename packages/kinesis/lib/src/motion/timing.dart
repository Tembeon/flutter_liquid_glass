part of 'package:kinesis/src/motion/animation.dart';

/// A duration-and-curve animation, matching UIKit's `UICubicTimingParameters`
/// / `CABasicAnimation` and SwiftUI's timed `Animation` presets.
///
/// By default a new [TimingCurve] retargets a `MotionValue` from where its
/// course stands when the curve starts. With [additive] true, the model jumps
/// to the new target and adds an offset curve from the previous target to 0,
/// so overlapping curves sum without discontinuity (Core Animation's
/// `isAdditive = YES`).
@immutable
final class TimingCurve extends MotionAnimation {
  /// Creates a timed curve of [duration] seconds using [curve].
  const TimingCurve(
    this.duration, {
    this.curve = uikitEaseInOut,
    this.additive = false,
    this.reduced,
  }) : assert(duration >= 0, 'duration must be non-negative');

  /// UIKit's default ease-in-out curve `(0.42, 0) -> (0.58, 1)` (curve 0).
  ///
  /// Defaults to SwiftUI's 0.35 s duration.
  const TimingCurve.easeInOut({
    double duration = 0.35,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitEaseInOut,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's ease-in curve `(0.42, 0) -> (1, 1)` (curve 1).
  const TimingCurve.easeIn({
    double duration = 0.35,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitEaseIn,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's ease-out curve `(0, 0) -> (0.58, 1)` (curve 2).
  const TimingCurve.easeOut({
    double duration = 0.35,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitEaseOut,
         additive: additive,
         reduced: reduced,
       );

  /// A constant-speed linear curve (UIKit curve 3).
  const TimingCurve.linear({
    double duration = 0.35,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitLinear,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's CSS ease curve `(0.25, 0.1) -> (0.25, 1)` (curve 5, the default
  /// of `UICubicTimingParameters()`).
  const TimingCurve.ease({
    double duration = 0.35,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitEase,
         additive: additive,
         reduced: reduced,
       );

  /// A half-cosine ease-in-out `(1 - cos(pi * t)) / 2`, matching
  /// `UIScrollView.setContentOffset(_:animated:)` (0.3 s default) and
  /// `UIDatePicker` month paging.
  const TimingCurve.sineInOut({
    double duration = 0.3,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: uikitSineInOut,
         additive: additive,
         reduced: reduced,
       );

  /// A custom cubic Bezier timing curve from control points `(x1, y1)` and
  /// `(x2, y2)` over [duration] seconds.
  TimingCurve.cubic(
    double x1,
    double y1,
    double x2,
    double y2, {
    required this.duration,
    this.additive = false,
    this.reduced,
  }) : assert(duration >= 0, 'duration must be non-negative'),
       curve = Cubic(x1, y1, x2, y2);

  /// UIKit animation curve 0 (`UIView.AnimationCurve.easeInOut`).
  static const Curve uikitEaseInOut = Cubic(0.42, 0, 0.58, 1);

  /// UIKit animation curve 1 (`UIView.AnimationCurve.easeIn`).
  static const Curve uikitEaseIn = Cubic(0.42, 0, 1, 1);

  /// UIKit animation curve 2 (`UIView.AnimationCurve.easeOut`).
  static const Curve uikitEaseOut = Cubic(0, 0, 0.58, 1);

  /// UIKit animation curve 3 (`UIView.AnimationCurve.linear`).
  static const Curve uikitLinear = Curves.linear;

  /// UIKit animation curve 4 (`(0.66, 0) -> (0.33, 1)`).
  static const Curve uikitSharpEaseInOut = Cubic(0.66, 0, 0.33, 1);

  /// UIKit animation curve 5 (`UICubicTimingParameters()`, CSS ease).
  static const Curve uikitEase = Cubic(0.25, 0.1, 0.25, 1);

  /// Half-cosine ease-in-out: `(1 - cos(pi * t)) / 2`.
  static const Curve uikitSineInOut = _SineInOutCurve();

  /// The duration of the curve, in seconds.
  final double duration;

  /// The unit-interval timing function mapping `[0, 1]` to progress.
  final Curve curve;

  /// Whether overlapping curves sum additively instead of replacing the
  /// running curve.
  final bool additive;

  @override
  final MotionAnimation? reduced;

  @override
  bool get isImmediate => duration <= 0;

  /// Evaluates the curve's normalized progress at [elapsed] seconds.
  double progressAt(double elapsed) {
    if (elapsed <= 0) return 0;
    if (duration <= 0 || elapsed >= duration) return 1;
    return curve.transform(elapsed / duration);
  }

  /// Evaluates the time derivative of progress at [elapsed] seconds
  /// (per second), via centered finite differences.
  double progressVelocityAt(double elapsed) {
    if (duration <= 0 || elapsed <= 0 || elapsed >= duration) return 0;
    const eps = 1e-5;
    final u = elapsed / duration;
    final lo = math.max(0, u - eps).toDouble();
    final hi = math.min(1, u + eps).toDouble();
    if (hi <= lo) return 0;
    return (curve.transform(hi) - curve.transform(lo)) / ((hi - lo) * duration);
  }

  /// Returns a copy of this timing curve with the given fields replaced.
  TimingCurve copyWith({
    double? duration,
    Curve? curve,
    bool? additive,
    MotionAnimation? reduced,
  }) => TimingCurve(
    duration ?? this.duration,
    curve: curve ?? this.curve,
    additive: additive ?? this.additive,
    reduced: reduced ?? this.reduced,
  );

  @override
  bool operator ==(Object other) =>
      other is TimingCurve &&
      other.duration == duration &&
      other.curve == curve &&
      other.additive == additive &&
      other.reduced == reduced;

  @override
  int get hashCode => Object.hash(duration, curve, additive, reduced);

  @override
  String toString() =>
      'TimingCurve($duration, curve: $curve'
      '${additive ? ', additive: true' : ''})';
}

final class _SineInOutCurve extends Curve {
  const _SineInOutCurve();

  @override
  double transformInternal(double t) => (1 - math.cos(math.pi * t)) / 2;

  @override
  String toString() => 'TimingCurve.sineInOut';
}
