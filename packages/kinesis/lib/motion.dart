/// Writing motions: a measured control, a presentation or anything that
/// replays recorded input exactly.
///
/// A `Motion` is a tree of parts with one time cursor; every command takes
/// the time it happens at and every read answers at the motion's time, so a
/// motion is a pure function of its stamped inputs. This library adds
/// `Motion`, its parts and the explicit-time commands of `MotionValue`
/// (`MotionValueCommands`) to everything `package:kinesis/kinesis.dart`
/// exports.
library;

export 'kinesis.dart';
export 'src/motion/band.dart' show Band;
export 'src/motion/layout.dart' show LayoutMotion;
export 'src/motion/loop.dart' show MotionLoop;
export 'src/motion/motion.dart' show Motion, MotionCancel, MotionSelect;
export 'src/motion/part.dart' show MotionPart;
export 'src/motion/presence.dart' show Presence, PresenceStatus;
export 'src/motion/projection.dart'
    show
        Projection,
        ProjectionChoice,
        ProjectionExit,
        ProjectionExited,
        ProjectionStop;
export 'src/motion/ramp.dart' show Ramp;
export 'src/motion/rect.dart' show MotionRect, RectSprings;
export 'src/motion/rest.dart' show MotionRest;
export 'src/motion/signal.dart' show MotionSignal;
export 'src/motion/timed.dart' show TimedValue;
export 'src/presentation/presented.dart' show Presented;
export 'src/presentation/route.dart' show DismissTrigger;
export 'src/presentation/source.dart' show Sourced;
export 'src/value.dart' show MotionValueCommands;
