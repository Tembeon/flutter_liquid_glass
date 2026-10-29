# Changelog

## 0.1.0-dev.1

- `Spring` in SwiftUI's form (duration, bounce) and UIKit's (response,
  damping ratio), with a tracking spring, a retarget impulse, a release
  projection and a Reduce Motion alternative.
- `MotionValue`: a value with a target, what is on screen and its velocity;
  every retarget continues from the current value and velocity.
- `MotionConverter` for doubles, offsets, sizes, rects, radii and colors.
- `withSpring` and `withoutAnimation` transactions.
- `MotionClock`: one frame clock per binding. A frame runs timelines,
  drivers, the step and publish in a microtask after every ticker and before
  build, on the display's frame grid; pointer events are stamped at their own
  time; the clock dozes until a later change and asks for no frames at rest.
  `MotionDriver` for per-frame loops. `ManualMotionClock` runs the same
  phases on demand. The binding's clock, woken by a ticker or by a
  microtask of a frame that has not built yet, runs its phases in that
  frame.
- `MotionClock.schedulePublish` runs a callback once in the coming publish
  phase, after the frame's motions stepped and before build.
- `MotionValue` listeners hear the value every frame it moves, and once more
  when it rests and snaps to its target.
- `MotionComputed`: derived values that follow what they read and publish
  once per frame.
- `MotionTimeline` for explicit time.
- The resolve phase: after layout and before paint, layouts place what they
  just laid out; render listeners (`addRenderListener`) hear the values that
  change at once, other listeners in the next frame.
- `MotionTransition`: offset, scale, rotation, opacity, blur, clip and size
  from listenable values, through one composited layer, without building,
  laying out or repainting the child.
- `MotionDriven`: any chain of single-child render-object widgets driven by
  motion values without building.
- `MotionLayout`: animates whatever layout did to its children, under the
  frame's transaction, with `LayoutMotion.flip`, a pure `plan` and
  `MotionEffect` insert and remove effects.
- Errors thrown by listeners, drivers and scheduled actions are reported
  through `FlutterError` and do not stop the frame.
- Input: pure `Interaction`s (`PressInteraction`, `LongPressInteraction`,
  `DragInteraction`, `TapInteraction`, `ScrubInteraction`, with
  `exclusively` and `simultaneously`) and `InteractionSession`, which
  replays stamped input exactly, including UIKit's 0.15 s scroll delay.
  `InputRegion` feeds them from pointer, keyboard, hover and accessibility
  input with stamped times and the raw release velocity; `MotionPressable`
  and `MotionDragDetector` are built on it.
- `rubberBand`.
- Presentations: `PresentationRoute` (a popup) and `PresentationPageRoute`
  (a page), routes whose motion lives in their content: the animation's
  status follows the motion while its value stays 1, and a push completes
  at the open's rest. One dismissal gate (`allows`, then the content's
  `PopScope`s, `didVetoDismiss` on a refusal) serves outside taps, Escape,
  Back, a screen reader's dismiss and the content's own gestures; a
  dismissal closes its own route, never the top one, and one under another
  route closes under it. While `modal`, the barrier absorbs taps and hides
  the routes below from screen readers. `showPresentation`,
  `PresentationLevel` and `PresentationContext` pick the navigator inside
  the presenting view.
