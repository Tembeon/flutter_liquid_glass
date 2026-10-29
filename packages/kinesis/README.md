# kinesis

UIKit-grade motion for any Flutter app.

A `MotionValue` holds the `target` you set and the value on screen. Assign
the target inside `withSpring` and the value springs there; assign it again
mid-flight and it continues from where it is, at the speed it has.

```dart
final height = MotionValue(120.0);

void toggle() => withSpring(
  Spring.bouncy,
  () => height.target = height.target == 120 ? 440 : 120,
);
```

The ambient `target` and `value` read the binding's frame clock,
`MotionClock.instance`. While a value moves, its listeners hear it once per
frame, before build; at rest the clock asks for no frames. A
`MotionComputed` derives a value from others; its listeners hear it at most
once per frame.

`Spring` speaks both dialects with an exact mapping:
`Spring(duration: Duration(milliseconds: 500), bounce: 0.3)` (SwiftUI) and
`Spring.response(0.5, dampingRatio: 0.7)` (UIKit).

Every operation also has a form with an explicit time, so a motion built
from these values is a pure function of its inputs and replays recorded input exactly
in tests.
