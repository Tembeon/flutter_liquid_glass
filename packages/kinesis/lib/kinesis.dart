/// UIKit-grade motion for any Flutter app.
///
/// `MotionValue`s move on `Spring`s and carry their position and velocity
/// into every retarget; `withSpring` and `withoutAnimation` say how the
/// changes made inside them move. Every operation also has a form with an
/// explicit time, so a motion replays recorded input exactly
/// (`ManualMotionClock`, `MotionTimeline`).
library;

export 'src/clock.dart' show ManualMotionClock, MotionClock, MotionDriver;
export 'src/computed.dart';
export 'src/converter.dart';
export 'src/effect.dart';
export 'src/input/interaction.dart' hide flattenInteraction;
export 'src/presentation/level.dart';
export 'src/presentation/route.dart';
export 'src/rubber_band.dart';
export 'src/screen/driven.dart';
export 'src/screen/input_region.dart';
export 'src/screen/layout.dart';
export 'src/screen/scroll_observer.dart';
export 'src/screen/transition.dart' show MotionTransition;
export 'src/spring.dart';
export 'src/timeline.dart';
export 'src/transaction.dart'
    show MotionAccessibility, withSpring, withoutAnimation;
export 'src/value.dart';
