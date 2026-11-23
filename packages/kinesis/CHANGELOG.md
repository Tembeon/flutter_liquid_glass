# Changelog

## 0.1.0-dev.1

The first version: motion, input and presentations in four libraries,
each importable alone and all four through `package:kinesis/kinesis.dart`.

### Motion (`package:kinesis/motion.dart`)

No widgets; a motion is a pure function of its stamped inputs and replays
exactly in a test.

- `Spring` in SwiftUI's form (duration, bounce), UIKit's (response, damping
  ratio) and the physical one, with a tracking spring, a retarget impulse and
  a Reduce Motion alternative; `TimingCurve` with UIKit's curves. Both are a
  `MotionAnimation`.
- `MotionValue`: a value with a target, what is on screen and its velocity;
  every retarget continues from the current value and velocity, and listeners
  hear it every frame it moves and once more when it rests.
  `MotionConverter` and `TextStyleMotionConverter` animate doubles, offsets,
  sizes, rects, radii, colors, insets, alignments and text styles with their
  font variations.
- `withSpring`, `withAnimation` and `withoutAnimation` transactions
  (`MotionTransaction`), and `MotionTraits` for Reduce Motion and the other
  motion preferences.
- `MotionSelection`: a value derived from motions, recomputed once per frame
  when what it reads changed; a render listener hears it in the resolve
  phase, before paint (`RenderListenable`).
- `Motion`: a tree of parts on one time cursor, with one timeline of delayed
  reactions. Its parts (`MotionPart`) are `MotionValue`, `KeyframeValue`,
  `MotionSignal` (a value written from outside, such as scroll pixels),
  `MotionRect` on `RectSprings`, `Presence`, `MotionLoop` (a per-frame loop
  at its own fixed rate), `LayoutMotion` and smaller motions; their rest
  tolerances are `MotionRest`.
- `MotionPose`: one look (move, scale, turn, opacity, blur) for a layout
  item, a content change and a symbol effect alike.
- `MotionKeyframes`, and `MotionAnimator` (UIKit's
  `UIViewPropertyAnimator`: interruptible, scrubbable, reversible).
- Laws: `Projection` (where a release lands and which stop or exit it
  picks), `RubberBand`, `Ramp`, `ScrollDeceleration`, `PagingPhysics` and
  `ScrollToTopCurve`.
- Ready motions: `CaretBlinkMotion`, `NumericTextMotion` and
  `SymbolEffectMotion` with SF Symbols' effects (bounce, pulse, scale,
  wiggle, rotate, breathe, appear, disappear).
- `Presented`, `PredictiveBack`, `PresentedProgress` and `Sourced` connect a
  motion to a presentation shell and to its source; `DismissPolicy` and
  `DismissTrigger` say which dismissals go through.

### The clock

- `MotionClock`: one frame clock per binding. A frame runs the due scheduled
  actions, steps and publishes every moving value before build, on the
  display's frame grid, then resolves after layout. Pointer events are
  stamped at their own time. The clock dozes until a later change and asks
  for no frames at rest. `schedulePublish` runs a callback once in the
  coming publish phase.
- `ManualMotionClock` (`package:kinesis/testing.dart`) runs the same phases
  only when told to.
- Errors thrown by listeners and scheduled actions are reported through
  `FlutterError` and do not stop the frame.
- `FrameCadence`: on a display faster than 90 Hz, once started, the app draws
  every second vsync while nothing fast moves. A scroll or a finger past
  UIKit's speed and a `Motion` with a floor above 60 Hz draw every vsync; a
  device that cannot keep up stays at the lower rate.

### Input (`package:kinesis/input.dart`)

No widgets; an interaction is pure logic over stamped input.

- `Interaction`s: `PressInteraction`, `TapInteraction`,
  `LongPressInteraction`, `DragInteraction`, `FollowInteraction`,
  `DwellInteraction` and `SecondaryClickInteraction`. A region runs its
  interactions side by side; `exclusively` lets a second one have the touch
  only when the first fails, and `sequenced` adds one once the first
  recognizes.
- `InteractionSession` replays stamped input exactly, including UIKit's
  0.15 s scroll delay. Keyboard and accessibility commands (`ActivateInput`,
  `AdjustInput`, `ContextMenuInput`) arrive on the same path as touches.
- `MotionHaptic`, the haptic a control plays for an interaction event.
- `InputPort` hands the rest of a touch to another receiver without
  cancelling it.

### Widgets (`package:kinesis/widgets.dart`)

- `MotionTransition`: offset, scale, rotation, opacity, blur, clip and size
  from listenable values, through one composited layer, without building,
  laying out or repainting the child. `MotionDriven` drives any chain of
  single-child render-object widgets the same way.
- `MotionText`, `MotionNumericText` (digits roll glyph by glyph and the width
  slides), `MotionContentTransition` (the size slides between children) and
  `MotionSymbol`.
- `MotionLayout` and `SliverMotionList` animate whatever layout did to their
  children under the frame's transaction (`LayoutPlanner.flip`).
  `MotionMeasure` reports a child's size in the frame that laid it out, and
  `MotionResolveHost` places a render object from this frame's layout.
- `MotionVisibility` hides a child while keeping what it is asked to keep.
- `InputRegion` and `InputZones` feed interactions from pointer, keyboard,
  hover and accessibility input with stamped times; `InputCapture` takes the
  touches that land where no control lies yet. `KeyboardUse`,
  `ControlStates`, `ControlledValue` and `MotionHapticScope` serve the
  controls built on them.
- `MotionScope` holds a `Motion` on the clock while it is in the tree,
  `MotionClockScope` gives a subtree its clock, `MotionTraitsOverride` its
  motion preferences, and `MotionScroll` reads a scroll view as a motion.
- `MotionSource` and `MotionSourceBox`: what a presentation grows out of and
  back into.

### Presentations (`package:kinesis/presentation.dart`)

- `Presentation`: the motion a presentation plays and the content over it,
  with its `PresentationHandle`. `PresentationRoute` (a popup),
  `PresentationPageRoute` (a page), `PresentationRouteMixin` (a modal route
  of one's own) and `PresentationPortal` (the root overlay, no route) are its
  shells. A route's animation status follows the motion, and a push
  completes at the open's rest.
- One dismissal gate (`DismissPolicy`, then the content's `PopScope`s)
  serves outside taps, Escape, Back, Android's predictive back, a screen
  reader's dismiss and the content's own gestures; a dismissal closes its own
  presentation, never the top one. While modal, the barrier absorbs taps and
  hides what is below from screen readers. A presentation that is leaving
  takes no new touches, so what is below does not wait for its close to end.
- `showPresentation`, `PresentationLevel` and `PresentationContext` pick the
  navigator inside the presenting view.
