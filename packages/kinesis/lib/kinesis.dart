/// UIKit-grade motion for any Flutter app.
///
/// `MotionValue`s move on `Spring`s and carry their position and velocity
/// into every retarget; `withSpring` and `withoutAnimation` say how the
/// changes made inside them move, starting at the clock's time, which is
/// an input's own stamp while it is dispatched. A control or a
/// presentation of your own is a `Motion`, written with
/// `package:kinesis/motion.dart`.
library;

export 'src/clock.dart' show ManualMotionClock, MotionClock;
export 'src/converter.dart' show MotionConverter;
export 'src/effect.dart' show MotionEffect;
export 'src/input/follow.dart' show FollowInteraction, PointerFollower;
export 'src/input/interaction.dart'
    show
        ActivateInput,
        ActivationEvent,
        ActivationSource,
        DragInteraction,
        DragInteractionDetails,
        Interaction,
        InteractionEvent,
        InteractionInput,
        InteractionRole,
        InteractionSession,
        InteractionUpdate,
        LongPressInteraction,
        LongPressStartEvent,
        MotionHaptic,
        PointerCancelInput,
        PointerCancelReason,
        PointerDownInput,
        PointerHoverInput,
        PointerMoveInput,
        PointerUpInput,
        PressInteraction,
        ScrubChangeEvent,
        ScrubInteraction,
        SessionOutput,
        TapInteraction;
export 'src/input/port.dart' show InputPort;
export 'src/presentation/level.dart'
    show
        PresentationContext,
        PresentationLevel,
        presentationNavigatorOf,
        showPresentation;
export 'src/presentation/route.dart'
    show DismissTrigger, PresentationPageRoute, PresentationRoute;
export 'src/screen/driven.dart' show MotionDriven;
export 'src/screen/input_region.dart' show InputRegion;
export 'src/screen/layout.dart'
    show
        LayoutChange,
        LayoutEntry,
        LayoutItem,
        LayoutMotion,
        LayoutPhase,
        LayoutPlan,
        MotionLayout,
        MotionLayoutBuilder;
export 'src/screen/scope.dart' show MotionScope, MotionTraitsOverride;
export 'src/screen/scroll_observer.dart'
    show MotionScrollObserver, MotionScrollPhase;
export 'src/screen/transition.dart'
    show MotionTransition, MotionTransitionLayer;
export 'src/selection.dart' show MotionSelection;
export 'src/spring.dart' show Spring;
export 'src/transaction.dart' show MotionTraits, withSpring, withoutAnimation;
export 'src/value.dart' show MotionValue;
