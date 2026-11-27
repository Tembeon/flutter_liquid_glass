import 'dart:math' as math;

import 'package:kinesis/motion.dart';

/// UIKit's progress view as its progress changes (progress view passport,
/// confirmed on an iPhone frame for frame): an animated change moves at
/// one bar a second, [fraction] travelling linearly for as many seconds as
/// the progress changes, and at least [fadeDuration] when the fill appears
/// or leaves, its [opacity] ramping on the same clock. Each change is
/// additive, as Core Animation's are: the new value at once with an offset
/// from the old one running to 0, so changes that overlap sum.
final class ProgressMotion {
  /// Creates the motion standing at [progress] on [clock].
  ProgressMotion({required double progress, required MotionClock clock})
    : fraction = MotionValue<double>(progress, clock: clock),
      opacity = MotionValue<double>(progress > 0 ? 1 : 0, clock: clock);

  /// The shortest change that shows or hides the fill, in seconds.
  static const double fadeDuration = 0.2;

  /// The fraction of the bar the fill covers.
  final MotionValue<double> fraction;

  /// The fill's opacity: 0 while the progress is 0.
  final MotionValue<double> opacity;

  /// Changes the progress to [progress], moving there when [animated].
  void set(double progress, {required bool animated}) {
    final from = fraction.target;
    if (progress == from) return;
    final shows = progress > 0;
    final turns = shows != (from > 0);
    void change() {
      fraction.target = progress;
      if (turns) opacity.target = shows ? 1 : 0;
    }

    if (!animated) return withoutAnimation(change);
    final seconds = (progress - from).abs();
    withAnimation(
      TimingCurve.linear(
        duration: turns ? math.max(seconds, fadeDuration) : seconds,
        additive: true,
      ),
      change,
    );
  }

  /// Runs the progress from [from] to [to] at a constant speed over
  /// [seconds] from time [t], as a progress over a time interval does; the
  /// fill fades in over [fadeDuration] as it leaves 0 and out as it reaches
  /// it.
  void run(double t, double from, double to, double seconds) {
    fraction.snap(t, from);
    opacity.snap(t, from > 0 ? 1 : 0);
    if (seconds <= 0) {
      fraction.snap(t, to);
      opacity.snap(t, to > 0 ? 1 : 0);
      return;
    }
    fraction.animate(t, to, animation: TimingCurve.linear(duration: seconds));
    final fade = math.min(fadeDuration, seconds);
    if (from <= 0 && to > 0) {
      opacity.animate(t, 1, animation: TimingCurve.linear(duration: fade));
    } else if (from > 0 && to <= 0) {
      opacity.animate(
        t,
        0,
        animation: TimingCurve.linear(duration: fade),
        delay: seconds - fade,
      );
    }
  }
}
