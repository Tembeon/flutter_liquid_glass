import 'package:kinesis/motion.dart';

/// How a tab bar's circle, a prominent tab's or an action's, comes and
/// goes beside the bar: it slides in from half its width toward the
/// trailing side while it fades in, on a critically damped 0.3 s spring,
/// as UIKit's `setProminentTabIdentifier(_:animated:)` brings its circle
/// in while the platter shrinks (read off UIKit's live layers on the iOS
/// 27.2 simulator: x 350 to 319 for the 62 point circle). It goes as the
/// mirror (not captured).
final class TabCircleMotion extends Motion {
  /// Creates the motion of a circle that [shown] or not.
  TabCircleMotion({required bool shown, super.clock}) : _shown = shown ? 1 : 0;

  final double _shown;

  /// How far the circle shows, from 0 gone to 1 in place.
  late final shown = own(MotionValue<double>(_shown));

  /// How far the circle stands from its place along the bar, in points.
  late final slide = own(MotionValue<double>(0));

  /// The circle comes or goes at time [t]; [away] is where it stands when
  /// gone, half its width toward the trailing side.
  void show(double t, {required bool shown, required double away}) {
    advance(t);
    final target = shown ? 1.0 : 0.0;
    if (this.shown.target == target) return;
    if (shown && this.shown.valueAt(t) == 0) slide.snap(t, away);
    this.shown.retarget(t, target, spring: _spring);
    slide.retarget(t, shown ? 0 : away, spring: _spring);
  }

  /// Whether the circle has gone.
  bool get isGone =>
      shown.target == 0 && shown.valueAt(now) <= MotionRest.opacity;
}

const Spring _spring = Spring.response(0.3);
