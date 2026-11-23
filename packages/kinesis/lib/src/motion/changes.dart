import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/pose.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/transaction.dart';
import 'package:kinesis/src/motion/value.dart';
import 'package:meta/meta.dart';

/// The look of content that a change brings in with [arriving] and another
/// takes away with [leaving], null for a change it is not part of: content
/// still arriving when the next change replaces it wears both, under
/// [traits] (`MotionPoseWorn.wornUnder`).
@internal
MotionPose wornDuringChange({
  required MotionPose? arriving,
  required MotionPose? leaving,
  required MotionTraits traits,
}) {
  var pose = arriving ?? MotionPose.identity;
  if (leaving != null) pose = pose.compose(leaving);
  return pose.wornUnder(traits);
}

/// The changes of a text or a content that run at once, each a progress of
/// its own from 0 to 1.
///
/// A change during a change carries on: at most [maxChanges] run, a further
/// one ends the oldest at once, and a change retires once its progress
/// rests within `MotionRest.opacity`. `NumericTextMotion` owns one;
/// `MotionContentTransition` holds one in a `MotionScope`.
@internal
final class MotionChanges extends Motion {
  /// Creates the changes, none running; [onRetire] hears each change as it
  /// retires.
  MotionChanges({super.clock, this.onRetire});

  /// How many changes run at once.
  static const int maxChanges = 3;

  /// Called with each change as it retires.
  final void Function(MotionValue<double> change)? onRetire;

  final List<MotionValue<double>> _running = [];
  int _retired = 0;

  /// How many changes have retired so far.
  int get retired => _retired;

  /// Whether no change runs.
  bool get isEmpty => _running.isEmpty;

  /// The progress of each running change at [now], the oldest first.
  List<double> get progress => [
    for (final change in _running) change.valueAt(now),
  ];

  /// Whether [change] still runs.
  bool runs(MotionValue<double> change) => _running.contains(change);

  /// Starts a change at [t] on [animation], resolved by [traits]; with
  /// [maxChanges] running, the oldest ends at once.
  MotionValue<double> start(double t, MotionAnimation animation) {
    advance(t);
    if (_running.length >= maxChanges) _retire(_running.first..snap(t, 1));
    final change = own(
      MotionValue<double>(0, restDistance: MotionRest.opacity),
    );
    _running.add(change);
    change.animate(
      t,
      1,
      animation: animation.resolve(reduceMotion: traits.reduceMotion),
    );
    return change;
  }

  /// Retires every running change where it is.
  void end() {
    while (_running.isNotEmpty) {
      _retire(_running.first);
    }
  }

  @override
  void didAdvance(double t) {
    for (var i = _running.length - 1; i >= 0; i--) {
      final change = _running[i];
      if (change.restsAt(t)) _retire(change);
    }
  }

  void _retire(MotionValue<double> change) {
    _running.remove(change);
    disown(change);
    _retired++;
    onRetire?.call(change);
    changed();
  }
}
