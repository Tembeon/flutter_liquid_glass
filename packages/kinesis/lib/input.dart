/// Gestures as pure logic: interactions, their combinations, the handoff of
/// a touch between regions, and time-stamped input events.
///
/// For the author of a control: an `Interaction` (press, tap, long press,
/// drag, scrub, follow) takes `InteractionInput`s and answers with
/// `InteractionEvent`s, so a gesture is checked by replaying a recording,
/// with no screen. `InputPort` hands a touch from one region to another.
///
/// It promises one way to stamp an event with its time, and that keyboard
/// and accessibility activation (`ActivateInput`) arrive on the same path
/// as touches.
///
/// It never knows about widgets, focus or semantics, and imports neither
/// widgets nor rendering.
library;

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
