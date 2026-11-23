/// The motion kernel: springs, values that move on them, the clock they
/// move by, and motions written as pure classes.
///
/// For the author of motion: a control's law, a presentation's or any
/// other is a `Motion` (a tree of parts such as `MotionLoop`, `MotionRect`,
/// `Presence` and `LayoutMotion`, which laws such as `Ramp`, `RubberBand`
/// and `Projection` compute with) that replays a recorded gesture exactly,
/// without a widget tree. `Spring` takes both UIKit forms and knows when it
/// comes to rest; `MotionValue` moves on springs; `withSpring` and
/// `withoutAnimation` say how the changes made inside them move;
/// `MotionSelection` derives values; the clock and `FrameCadence` say when
/// frames happen.
///
/// It promises that motion is a function of its time-stamped inputs: every
/// command takes the time it happens at and every read answers at the
/// motion's time. A retarget keeps position and velocity, so an
/// interruption never jumps. At rest it asks for no frames. Reduce Motion
/// reaches every motion through one channel, `Motion.traits`.
///
/// It never imports widgets or rendering, and never decides what is drawn.
library;

export 'src/motion/animation.dart' show MotionAnimation, Spring, TimingCurve;
export 'src/motion/animator.dart'
    show AnimatorPosition, MotionAnimator, MotionAnimatorState;
export 'src/motion/caret_blink.dart' show CaretBlinkMotion;
export 'src/motion/clock.dart' show MotionClock;
export 'src/motion/converter.dart'
    show MotionConverter, TextStyleMotionConverter;
export 'src/motion/frame_cadence.dart' show FrameCadence;
export 'src/motion/keyframes.dart'
    show KeyframeMode, KeyframeStop, KeyframeValue, MotionKeyframes;
export 'src/motion/layout.dart'
    show
        LayoutChange,
        LayoutEntry,
        LayoutItem,
        LayoutMotion,
        LayoutPhase,
        LayoutPlan,
        LayoutPlanner;
export 'src/motion/listen.dart' show RenderListenable, RenderListening;
export 'src/motion/loop.dart' show MotionLoop;
export 'src/motion/motion.dart' show Motion, MotionCancel, MotionSelect;
export 'src/motion/numeric_text.dart'
    show
        NumericGlyph,
        NumericGlyphRoll,
        NumericRollDirection,
        NumericTextFrame,
        NumericTextMotion;
export 'src/motion/part.dart' show MotionPart;
export 'src/motion/pose.dart' show MotionPose;
export 'src/motion/presence.dart' show Presence, PresenceStatus;
export 'src/motion/presented.dart'
    show
        DismissPolicy,
        DismissTrigger,
        PredictiveBack,
        Presented,
        PresentedProgress;
export 'src/motion/projection.dart'
    show
        Projection,
        ProjectionChoice,
        ProjectionDirection,
        ProjectionExit,
        ProjectionExited,
        ProjectionStop;
export 'src/motion/ramp.dart' show Ramp;
export 'src/motion/rect.dart' show MotionRect, RectSprings;
export 'src/motion/rest.dart' show MotionRest;
export 'src/motion/rubber_band.dart' show RubberBand;
export 'src/motion/scroll_physics.dart'
    show PagingPhysics, ScrollDeceleration, ScrollStep, ScrollToTopCurve;
export 'src/motion/selection.dart' show MotionSelection;
export 'src/motion/signal.dart' show MotionSignal;
export 'src/motion/source_geometry.dart' show SourceGeometry, Sourced;
export 'src/motion/symbol_effect.dart'
    show
        AppearSymbolEffect,
        BounceSymbolEffect,
        BreatheSymbolEffect,
        DisappearSymbolEffect,
        MotionSymbolEffect,
        PulseSymbolEffect,
        RotateSymbolEffect,
        ScaleSymbolEffect,
        SymbolEffectDirection,
        SymbolEffectMotion,
        SymbolEffectOptions,
        SymbolEffectRepeat,
        WiggleSymbolEffect;
export 'src/motion/transaction.dart'
    show
        MotionTraits,
        MotionTransaction,
        withAnimation,
        withSpring,
        withoutAnimation;
export 'src/motion/value.dart' show MotionValue, MotionValueCommands;
