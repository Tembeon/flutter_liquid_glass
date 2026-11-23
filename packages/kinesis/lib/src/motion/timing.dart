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
    this.curve = Curves.easeInOut,
    this.additive = false,
    this.reduced,
  }) : assert(duration >= 0, 'duration must be non-negative');

  /// UIKit's default ease-in-out curve (`UIView.AnimationCurve.easeInOut`),
  /// the SDK's [Curves.easeInOut].
  const TimingCurve.easeInOut({
    double duration = defaultDuration,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: Curves.easeInOut,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's ease-in curve (`UIView.AnimationCurve.easeIn`), the SDK's
  /// [Curves.easeIn].
  const TimingCurve.easeIn({
    double duration = defaultDuration,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: Curves.easeIn,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's ease-out curve (`UIView.AnimationCurve.easeOut`), the SDK's
  /// [Curves.easeOut].
  const TimingCurve.easeOut({
    double duration = defaultDuration,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: Curves.easeOut,
         additive: additive,
         reduced: reduced,
       );

  /// A constant-speed linear curve (UIKit curve 3).
  const TimingCurve.linear({
    double duration = defaultDuration,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: Curves.linear,
         additive: additive,
         reduced: reduced,
       );

  /// UIKit's CSS ease curve, the default of `UICubicTimingParameters()`:
  /// the SDK's [Curves.ease].
  const TimingCurve.ease({
    double duration = defaultDuration,
    bool additive = false,
    MotionAnimation? reduced,
  }) : this(
         duration,
         curve: Curves.ease,
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

  /// SwiftUI's duration of a timed animation, in seconds, which the named
  /// curves default to.
  static const double defaultDuration = 0.35;

  /// UIKit animation curve 4 (`(0.66, 0) -> (0.33, 1)`).
  static const Curve uikitSharpEaseInOut = Cubic(0.66, 0, 0.33, 1);

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
    final lo = math.max<double>(0, u - eps);
    final hi = math.min<double>(1, u + eps);
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
