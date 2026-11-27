import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

// A tree under a MotionClockScope whose clock only the test moves runs
// every motion on that clock. With test time frozen, a ticker asks the
// binding for frames forever, and a motion on the binding's own clock keeps
// that clock busy.

/// Moves [clock] [seconds] on at 60 frames a second, a frame of the tree
/// after each step, and fails as soon as a step moves anything on the
/// binding's clock.
Future<void> runClock(
  WidgetTester tester,
  ManualMotionClock clock,
  double seconds,
) async {
  final end = clock.now + seconds;
  while (clock.now < end) {
    clock.advanceTo(clock.now + 1 / 60);
    if (!MotionClock.instance.debugIsIdle) {
      throw TestFailure("as its clock runs it moves on the binding's clock");
    }
    await tester.pump();
  }
}

/// Fails when, at [moment], the tree asks the binding for a frame, moves
/// anything on the binding's clock, or draws from a motion published on a
/// clock other than [clock].
Future<void> expectOnClock(
  WidgetTester tester,
  ManualMotionClock clock,
  String moment,
) async {
  await tester.pump();
  if (tester.binding.hasScheduledFrame) {
    throw TestFailure(
      '$moment it asks the binding for frames its clock does not run',
    );
  }
  if (!MotionClock.instance.debugIsIdle) {
    throw TestFailure("$moment it moves on the binding's clock");
  }
  for (final listenable in drawnFromMotion(tester)) {
    if (listenable case final RenderListenable value
        when !identical(value.clock, clock)) {
      throw TestFailure('$moment what it draws moves on another clock');
    }
  }
}

/// What the tree draws from motion: the frames of its glass and what its
/// motion transitions follow.
List<Listenable> drawnFromMotion(WidgetTester tester) => [
  for (final element in find.byWidgetPredicate((_) => true).evaluate())
    ...switch (element.widget) {
      GlassSurface(:final frame) => [?frame],
      final MotionTransition widget => [
        ?widget.offset,
        ?widget.translateX,
        ?widget.translateY,
        ?widget.scale,
        ?widget.scaleX,
        ?widget.scaleY,
        ?widget.rotation,
        ?widget.opacity,
        ?widget.blur,
        ?widget.pose,
        ?widget.width,
        ?widget.height,
      ],
      _ => const <Listenable>[],
    },
];
