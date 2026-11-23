import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/transaction.dart';
import 'package:meta/meta.dart';

/// Something a `Motion` owns and moves on its time cursor: a value on a
/// spring or a curve, keyframes, a signal, a rect, a loop or a smaller
/// motion.
///
/// Rest is a property of the part's course, not a change: [restTime] says
/// from when nothing visible moves, and [restFrom] declares it, so a
/// command stamped before that time still starts from the course at its own
/// time.
abstract class MotionPart {
  Motion? _owner;

  /// Tells the owning motion that the part changed, so its root wakes on
  /// the clock; a part calls it after every command that moves it.
  @protected
  void changed() => _owner?.partChanged();

  /// The earliest time from which every component stays within [tolerance]
  /// of where it comes to rest, or null while a change of the part's own
  /// is pending ([dueAfter]). A null [tolerance] is the part's own rest.
  double? restTime([double? tolerance]);

  /// Whether nothing visible moves at [t] until [dueAfter]: the part is
  /// within [tolerance] now, though a pending change of its own may move it
  /// later.
  bool restsAt(double t, [double? tolerance]);

  /// Declares the part at rest from [t], which is no earlier than
  /// [restTime]: reads at or after [t] answer where it comes to rest, with
  /// no velocity. The course is kept, so a later command stamped before [t]
  /// starts from the course at its own time; the declaration only rounds
  /// what is drawn, by less than the part's rest.
  void restFrom(double t);

  /// The time of the part's next change of its own after [t] (a delayed
  /// retarget, a curve that starts later, a keyframe's next step), or null.
  double? dueAfter(double t);

  /// Whether the part is settled at [t]: it rests and nothing of its own is
  /// due after.
  @nonVirtual
  bool settledAt(double t) => restsAt(t) && dueAfter(t) == null;
}

/// Internal ownership link for [MotionPart] within the package.
@internal
extension MotionPartInternal on MotionPart {
  Motion? get owner => _owner;
  set owner(Motion? value) => _owner = value;

  /// The clock of the owning motion, else [MotionClock.instance]: a part's
  /// clock when it was given none.
  MotionClock get ownerClock => _owner?.clock ?? MotionClock.instance;

  /// The preferences of the owning motion, else [MotionTraits.platform].
  MotionTraits get ownerTraits => _owner?.traits ?? MotionTraits.platform();
}
