/// Writing motions: a measured control, a presentation or anything that
/// replays recorded input exactly.
///
/// A `Motion` is a tree of parts with one time cursor; every command takes
/// the time it happens at and every read answers at the motion's time, so a
/// motion is a pure function of its stamped inputs. This library adds the
/// explicit-time commands of `MotionValue` (`MotionValueCommands`) to
/// everything `package:kinesis/kinesis.dart` exports.
library;

export 'kinesis.dart';
export 'src/clock.dart' show MotionDriver;
export 'src/motion/motion.dart' show Motion, MotionCancel, MotionSelect;
export 'src/motion/part.dart' show MotionPart;
export 'src/motion/rest.dart' show MotionRest;
export 'src/timeline.dart' show MotionTimeline;
export 'src/value.dart' show MotionValueCommands;
