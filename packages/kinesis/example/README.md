# Kinesis Studio

An interactive motion showcase built **entirely** on `kinesis` and
`package:flutter/widgets.dart` (no Material or Cupertino widget libraries, no
`AnimationController`).

Every button, sidebar highlight, switch, slider, sheet, and anchored popover in
the app is powered by `kinesis`, organized around six real UI patterns:

1. **Picture-in-Picture** -- Drag and toss a floating video player toward any
   corner (`Spring`, `Projection`, `RubberBand`, `DragInteraction`) with
   mid-flight interruption and feel presets.
2. **Now Playing** -- Scrub, pause, reverse, or finish with a spring as a
   compact mini player morphs into an expanded album card (`MotionAnimator`
   with staggered `delayFactor` tracks + `MotionKeyframes` orbit paths).
3. **Carousel & Feed** -- Swipe featured story cards (`PagingPhysics` 300 pt/s
   flick threshold) and fling an inertial message feed (`ScrollDeceleration`,
   `ScrollToTopCurve`, elastic edge bounce).
4. **Live Typography** -- Interactive balance widget with rolling digits
   (`MotionNumericText`), status transitions (`MotionContentTransition`),
   zero-rebuild font morphing (`MotionText`), and a UIKit stepped cursor
   (`CaretBlinkMotion`).
5. **Tactile Symbols** -- Tap Control Center-style tiles directly to trigger
   queued discrete and repeating indefinite symbol effects (`MotionSymbol`,
   `SymbolEffectMotion`), plus a Camera zoom dial with 25 Hz throttled
   selection haptics (`InputZones`, `MotionHaptic`).
6. **Fluid Layout** -- Rearrangeable Bento widget board (`MotionLayout`),
   slide-to-select toolbar (`InputZones`), draggable Share Sheet
   (`PresentationRoute`), and source-anchored Quick Menu (`PresentationPortal`
   + `MotionSourceBox`).

Toggle **Slow Motion (0.25x)**, **Reduce Motion**, **Dark Mode**, or
**Inspector** (to reveal live spring curves, projection vectors, rebuild
counts, and API telemetry) from the sidebar.

## Run

```sh
flutter run -d macos
```
