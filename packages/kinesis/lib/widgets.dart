/// Motion and input bound to the widget tree.
///
/// For the app developer, who animates layout and transitions without
/// rebuilding widgets (`MotionLayout`, `SliverMotionList`,
/// `MotionTransition`, `MotionDriven`, `MotionMeasure`, `MotionScroll`),
/// and for the author of a control, whose input goes through one widget,
/// `InputRegion` for a box or `InputZones` for the many moving parts one
/// render object paints, and whose states live in one controller,
/// `ControlStates` (`InputZonesController` for zones). `MotionScope` gives
/// a subtree its motion settings. `MotionSource` names what a presentation
/// grows out of: a box (`MotionSourceBox`) or a zone.
///
/// It promises that `InputRegion` gives an interactive widget touch, mouse,
/// focus, keyboard activation and the semantics of a press in one place,
/// and that `InputZones` gives each zone of a control the same, with the
/// zones hit, focused and described where the motion paints them in each
/// frame; that a frame of motion rebuilds no widget; and that motion
/// reaches the screen one way.
///
/// It never knows a look or a control.
library;

export 'src/widgets/control_states.dart' show ControlStates;
export 'src/widgets/driven.dart' show MotionDriven;
export 'src/widgets/input_region.dart'
    show AdjustValueIntent, InputRegion, MotionHapticPlay, MotionHapticScope;
export 'src/widgets/input_zones.dart'
    show InputZone, InputZoneFrame, InputZones, InputZonesController;
export 'src/widgets/layout.dart' show MotionLayout, MotionLayoutBuilder;
export 'src/widgets/measure.dart' show MotionMeasure;
export 'src/widgets/resolve.dart' show MotionResolveHost;
export 'src/widgets/scope.dart' show MotionScope, MotionTraitsOverride;
export 'src/widgets/scroll.dart' show MotionScroll, MotionScrollPhase;
export 'src/widgets/sliver_layout.dart' show SliverMotionList;
export 'src/widgets/source.dart' show MotionSource, MotionSourceBox;
export 'src/widgets/transition.dart'
    show MotionTransition, MotionTransitionLayer;
