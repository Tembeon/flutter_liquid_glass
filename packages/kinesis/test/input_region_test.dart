import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

Widget _list(Widget item) => _app(
  ListView(
    children: [
      const SizedBox(height: 100),
      SizedBox(height: 60, child: item),
      const SizedBox(height: 2000),
    ],
  ),
);

void main() {
  final haptics = <String>[];

  setUp(() {
    MotionClock.debugReset();
    haptics.clear();
  });

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  testWidgets('a press activates on release with its states and haptic', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    var presses = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: MotionPressable(
            onPressed: () => presses++,
            haptic: MotionHaptic.lightImpact,
            statesController: states,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MotionPressable)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(states.value, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(presses, 1);
    expect(states.value, isNot(contains(WidgetState.pressed)));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('in a scroll view a held press highlights after 0.15 s', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _list(
        MotionPressable(
          onPressed: () {},
          statesController: states,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MotionPressable)),
    );
    // A test's frame clock and engine clock disagree, so the motion clock
    // starts counting at the first frame after the touch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.value, isNot(contains(WidgetState.pressed)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.value, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a quick swipe scrolls the list and never presses', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    var presses = 0;
    final pressed = <bool>[];
    states.addListener(
      () => pressed.add(states.value.contains(WidgetState.pressed)),
    );
    await tester.pumpWidget(
      _list(
        MotionPressable(
          onPressed: () => presses++,
          statesController: states,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(MotionPressable), const Offset(0, -200));
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(list.position.pixels, greaterThan(0));
    expect(presses, 0);
    expect(pressed, isNot(contains(true)));
  });

  testWidgets('a region nothing in takes never blocks a scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _list(const InputRegion(interactions: [], child: SizedBox.expand())),
    );
    final before = tester.getTopLeft(find.byType(InputRegion)).dy;
    await tester.drag(find.byType(InputRegion), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(InputRegion)).dy, lessThan(before));
  });

  testWidgets('a drag ends with the velocity of its own release sample', (
    tester,
  ) async {
    DragInteractionDetails? end;
    await tester.pumpWidget(
      _app(
        Center(
          child: MotionDragDetector(
            axis: Axis.horizontal,
            onEnd: (details) => end = details,
            child: const SizedBox(width: 300, height: 100),
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.byType(MotionDragDetector));
    final reference = VelocityTracker.withKind(PointerDeviceKind.touch);
    final gesture = await tester.createGesture();
    await gesture.down(start);
    reference.addPosition(.zero, const Offset(150, 50));
    for (var i = 1; i <= 6; i++) {
      final time = Duration(milliseconds: 8 * i);
      await gesture.moveTo(start + Offset(12.0 * i, 0), timeStamp: time);
      reference.addPosition(time, Offset(150 + 12.0 * i, 50));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 56));
    reference.addPosition(
      const Duration(milliseconds: 56),
      const Offset(222, 50),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(end, isNotNull);
    expect(
      end!.velocity.dx,
      closeTo(reference.getVelocity().pixelsPerSecond.dx, 1e-6),
    );
  });

  testWidgets('a long press does not press as well', (tester) async {
    final heard = <String>[];
    await tester.pumpWidget(
      _app(
        Center(
          child: MotionPressable(
            onPressed: () => heard.add('press'),
            onLongPress: () => heard.add('long'),
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MotionPressable)),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(heard, ['long']);
  });

  testWidgets('a pressable without onPressed is disabled', (tester) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _app(
        MotionPressable(
          onPressed: null,
          statesController: states,
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    );
    expect(states.value, contains(WidgetState.disabled));
  });

  testWidgets('Space activates a focused pressable', (tester) async {
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        Center(
          child: Focus(
            focusNode: focus,
            child: MotionPressable(
              onPressed: () => presses++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      ),
    );
    final inner = Focus.of(tester.element(find.byType(SizedBox)));
    inner.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 1);
    expect(haptics, isEmpty);
  });
}
