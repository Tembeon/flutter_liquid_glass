import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured tuning and geometry of an iOS 27 alert
/// (UIAlertController with the alert style).
@internal
abstract final class AlertTuning {
  /// The spring of every alert animation: the dimming, the alert's opacity
  /// and its scale, presenting and dismissing. UIKit runs a
  /// CASpringAnimation of stiffness 522.35 and damping 45.71, mass 1:
  /// response 0.275 s, critically damped.
  static const spring = Spring.response(0.2749);

  /// The scale an alert presents from: it shrinks from this size to its
  /// own while it fades in (fitted 1.199 on an iPhone 16 Pro, 0.02
  /// percent rms; 1.196 on the simulator). A dismissing alert only fades.
  static const double presentScale = 1.199;
}

/// The motion of an iOS 27 alert: the dimming, the alert's opacity and its
/// scale.
///
/// Presenting, the alert fades in with the dimming while it shrinks from
/// [AlertTuning.presentScale] to its size; dismissing, it fades out
/// with the dimming at its size. Both run on [AlertTuning.spring],
/// and a dismissal in the middle of the presentation reverses from where
/// the alert stands, velocity included.
///
/// Under Reduce Motion (the motion's [Motion.traits]) the alert does not
/// shrink: it fades in at its size on the same spring. Read from UIKit, notes
/// private: UIAlertController starts the presentation at scale 1 instead
/// of 1.2 under Reduce Motion and keeps the timing.
///
/// Times are seconds on the motion's timeline.
///
/// The fade and the dimming rest within [MotionRest.opacity], the scale
/// within [MotionRest.scale] of the alert's width (NEAR, invisible).
///
/// Android's predictive back runs the dismissal under the finger: the
/// alert and the dimming fade with the gesture's progress at the alert's
/// size, a commit fades the rest on the spring from the gesture's
/// velocity, and a cancel springs back to shown. Android has no alert of
/// iOS's to measure, so this is the dismissal's own path, not a recording.
class AlertMotion extends Motion with Presented, PredictiveBack {
  /// Creates the motion of an alert that is not shown yet.
  AlertMotion({
    this.spring = AlertTuning.spring,
    this.presentScale = AlertTuning.presentScale,
  });

  /// The width of an alert in points; the scale rests within a tolerance of
  /// it.
  static const double width = 320;

  // UIKit asks at least 80 Hz of this (read from UIKit, notes private).
  @override
  double get minFrameRate => 80;

  /// The spring of the progress and the scale.
  final Spring spring;

  /// The scale the alert presents from.
  final double presentScale;

  late final _progress = own(
    MotionValue<double>(0, spring: spring),
    rest: () => MotionRest.opacity,
  );
  late final _scale = own(
    MotionValue<double>(presentScale, spring: spring),
    rest: () => MotionRest.scale(AlertMotion.width),
  );
  bool _dismissing = false;

  /// Whether the alert was dismissed and leaves.
  bool get isLeaving => _dismissing;

  /// Whether the alert has left and nothing moves any more.
  bool get isDismissed =>
      _dismissing && _progress.restsAt(now, MotionRest.opacity);

  /// Starts presenting the alert at time [t].
  void present(double t) {
    advance(t);
    _dismissing = false;
    if (_progress.valueAt(t) <= 0 && _progress.velocityAt(t) == 0) {
      _scale.snap(t, presentScale);
    }
    _progress.retarget(t, 1);
    _scale.retarget(t, 1);
  }

  /// Starts dismissing the alert at time [t].
  void dismiss(double t) {
    advance(t);
    _dismissing = true;
    _progress.retarget(t, 0);
  }

  @override
  PresenceStatus get presence => _dismissing
      ? (isDismissed ? .hidden : .leaving)
      : _progress.target == 0
      ? .hidden
      : isSettled
      ? .shown
      : .opening;

  @override
  void open(double t) => present(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    dismiss(t);
    return true;
  }

  /// The presentation progress: 0 hidden, 1 shown.
  double get progress => _progress.valueAt(now);

  /// The opacity of the alert.
  double get opacity => progress.clamp(0.0, 1.0);

  /// The opacity of the dimming, as a fraction of
  /// the opacity of the black dimming behind the alert.
  double get dimming => progress.clamp(0.0, 1.0);

  /// The scale of the alert.
  double get scale => traits.reduceMotion ? 1 : _scale.valueAt(now);

  @override
  void backStarted(double t) => advance(t);

  @override
  void backMoved(double t, double progress) {
    advance(t);
    _progress.snap(t, 1 - progress.clamp(0.0, 1.0));
  }

  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    advance(t);
    _progress.setVelocity(t, -velocity);
    if (!commits) _progress.retarget(t, 1);
  }
}
