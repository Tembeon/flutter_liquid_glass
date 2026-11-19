# Kinesis Studio

An interactive motion and physics studio built **entirely** on `kinesis` and
`package:flutter/widgets.dart` (no Material or Cupertino widget libraries, no
`AnimationController`).

Every button, segmented bar, slider, toggle, sheet, and anchored popover in the
app shell is itself driven by `kinesis` primitives, alongside six interactive
labs:

1. **Springs** -- 2D retargetable puck with `Projection` magnetic docks and
   `RubberBand` boundaries, plus a live `Spring` / `TimingCurve` curve plotter
   with response/damping sliders and a zero-rebuild flip card.
2. **Animator** -- `MotionAnimator` (`UIViewPropertyAnimator`-style) scrub
   deck with staggered `delayFactor` tracks, pause, reverse, spring
   continuation, and stop/finish, plus a `MotionKeyframes` (`linear`, `cubic`,
   `discrete`) choreography stage.
3. **Scroll** -- pure `ScrollDeceleration` momentum reel with predicted
   `landingOffset` marker, `0.5 pt` edge-bounce snap, and `ScrollToTopCurve`
   button, plus a `PagingPhysics` (`300 pt/s` velocity flip) card deck.
4. **Text** -- `MotionNumericText` rolling counter/price display, zero-rebuild
   `MotionText` typography morph (`TextStyleMotionConverter`),
   `MotionContentTransition` (`fade`, `blurReplace`, `scale`, `slide`), and
   `CaretBlinkMotion` (`1.0 s` stepped UIKit blink with typing reset).
5. **Symbols** -- `SymbolEffectMotion` + `MotionSymbol` lab covering all 8
   `MotionSymbolEffect`s with discrete queueing, concurrent stacking, speed and
   repeat controls, and completion telemetry, plus a `MotionHaptic` pad and
   40 ms selection-throttle scrub ruler.
6. **Layout** -- `MotionLayout` spring-animated grid (shuffle, add/remove,
   column switch), `InputZones` multi-zone sliding dock, and `Presentation`
   demos (draggable `PresentationRoute` sheet + `PresentationPortal` popover
   growing out of a `MotionSourceBox`).

Global toolbar controls let you toggle **Slow-Mo** (`timeDilation = 4`),
**Reduce Motion** (`MotionTraitsOverride`), **Dark/Light** theme, and watch
live **Haptic** feedback captured via `MotionHapticScope.onFeedback`.

## Run

```sh
flutter run -d macos
```
