import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

class _Pages extends StatefulWidget {
  const _Pages({this.picks, this.accept = true, this.start = 2});

  final List<int>? picks;
  final bool accept;
  final int start;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  late int page = widget.start;

  @override
  Widget build(BuildContext context) => GlassPageControl(
    count: 5,
    page: page,
    semanticLabel: 'Pages',
    onChanged: (next) {
      widget.picks?.add(next);
      if (widget.accept) setState(() => page = next);
    },
  );
}

const _pitch = Offset(9.67 + 8, 0);

// The test's frames run on a fake clock the engine clock does not follow;
// pinning both to it lets pointer time stamps space taps as on a device.
Duration Function() _deviceTime(WidgetTester tester) {
  Duration now() =>
      Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  MotionClock.debugEngineNow = now;
  MotionClock.debugPointerClockOffset = () => Duration.zero;
  addTearDown(() {
    MotionClock.debugEngineNow = null;
    MotionClock.debugPointerClockOffset = null;
  });
  return now;
}

Offset _dot(Rect box, int index) =>
    box.centerLeft + const Offset(14 + 9.67 / 2, 0) + _pitch * index.toDouble();

Widget _keyApp(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

List<Object?> _haptics(WidgetTester tester) {
  final played = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') played.add(call.arguments);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return played;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap on either half steps toward it on the lift', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 2, 1]);
  });

  testWidgets('a finger that rests 0.15 s scrubs: it follows the nearest dot '
      'and plays a selection haptic per page', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 25));
    }
    await gesture.up();
    await tester.pump();
    expect(picks, [3, 4]);
    expect(haptics, hasLength(2));
  });

  testWidgets("a finger resting on another page's dot keeps the page, and a "
      'slide lifted within 0.15 s taps', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final resting = await tester.startGesture(box.center + _pitch * 2);
    await tester.pump(const Duration(milliseconds: 300));
    await resting.up();
    await tester.pump();
    expect(picks, isEmpty);

    final sliding = await tester.startGesture(box.center);
    await sliding.moveBy(_pitch * 2);
    await tester.pump(const Duration(milliseconds: 50));
    await sliding.up();
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('taps within 8 points of the last, within 0.75 s, keep its '
      'way (read from UIKit)', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks, start: 0)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final now = _deviceTime(tester);
    Future<void> tap() async {
      final finger = await tester.createGesture();
      await finger.down(_dot(box, 2), timeStamp: now());
      await finger.up(timeStamp: now());
      await tester.pump(const Duration(milliseconds: 200));
    }

    for (var i = 0; i < 3; i++) {
      await tap();
    }
    expect(picks, [1, 2, 3]);
    await tester.pump(const Duration(milliseconds: 600));
    await tap();
    expect(picks, [1, 2, 3, 2]);
  });

  testWidgets('a scrub runs from the current dot whatever dot the finger '
      'rests on (read from UIKit)', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final finger = await tester.startGesture(_dot(box, 4));
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 4; i++) {
      await finger.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pump();
    expect(picks, [1]);
  });

  testWidgets('a tap steps toward the side of the current dot it lands on, '
      'two pages toggle, and a mouse picks the dot under it', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(GlassPageControl(count: 5, page: 0, onChanged: picks.add)),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(_dot(box, 1));
    await tester.pump();
    expect(picks, [1]);

    await tester.tapAt(_dot(box, 3), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(picks, [1, 3]);

    await tester.pumpWidget(
      _app(GlassPageControl(count: 2, page: 0, onChanged: picks.add)),
    );
    final two = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(two.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(picks, [1, 3, 1]);
  });

  testWidgets('without continuous interaction a moving finger only taps, '
      'at its release', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          allowsContinuousInteraction: false,
          onChanged: picks.add,
        ),
      ),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(picks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('its size by the count, and with hidesForSinglePage one page '
      'keeps its place, draws nothing and is not read', (tester) async {
    final five = GlassPageControl.sizeFor(5);
    expect(five.width, moreOrLessEquals(108.33, epsilon: 0.05));
    expect(five.height, 25.67);
    expect(
      GlassPageControl.sizeFor(1).width,
      moreOrLessEquals(37.67, epsilon: 0.05),
    );
    expect(
      GlassPageControl.sizeFor(3).width,
      moreOrLessEquals(73, epsilon: 0.05),
    );
    await tester.pumpWidget(
      _app(GlassPageControl(count: 5, page: 0, onChanged: (_) {})),
    );
    final drawn = tester.getSize(find.byType(GlassPageControl));
    expect(drawn.width, moreOrLessEquals(five.width));
    expect(drawn.height, five.height);

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 1,
          page: 0,
          hidesForSinglePage: true,
          semanticLabel: 'Pages',
          onChanged: (_) {},
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(GlassPageControl)).width,
      moreOrLessEquals(GlassPageControl.sizeFor(1).width),
    );
    expect(find.byType(RawGlassPageControl), findsNothing);
    expect(find.bySemanticsLabel('Pages'), findsNothing);
    semantics.dispose();
  });

  testWidgets('keys and accessibility step; it reads as an adjustable value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          onChanged: picks.add,
          focusNode: focus,
          semanticLabel: 'Pages',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pages')),
      matchesSemantics(
        label: 'Pages',
        value: 'page 3 of 5',
        increasedValue: 'page 4 of 5',
        decreasedValue: 'page 2 of 5',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    expect(picks, [3, 1, 3]);
    semantics.dispose();
  });

  testWidgets('right to left the pages run from the right', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(_Pages(picks: picks), direction: TextDirection.rtl),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('down or up a vertical control the pages run from the top or '
      'the bottom, 25.67 wide, and a tap steps toward its half', (
    tester,
  ) async {
    for (final (direction, first) in const [
      (AxisDirection.down, true),
      (AxisDirection.up, false),
    ]) {
      final picks = <int>[];
      GlassPageControlPose? pose;
      await tester.pumpWidget(
        _app(
          GlassPageControl(
            count: 5,
            page: 2,
            direction: direction,
            progress: 0.5,
            onChanged: picks.add,
            style: GlassPageControlStyle(
              builder: (context, details) {
                pose = details.pose.value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(GlassPageControl));
      final across = GlassPageControl.sizeFor(5);
      expect(box.width, moreOrLessEquals(across.height, epsilon: 0.01));
      expect(pose!.direction, direction);
      final rects = pose!.indicators;
      expect(
        rects.every((r) => r.width <= r.height + 1e-9),
        isTrue,
      );
      expect(rects.first.center.dy < rects.last.center.dy, first);
      expect(rects.first.center.dx, moreOrLessEquals(box.width / 2));
      await tester.tapAt(box.bottomCenter - const Offset(0, 6));
      await tester.pump();
      expect(picks, [if (first) 3 else 1]);
    }
  });

  testWidgets('a progress that changes every frame keeps the same pose, '
      'which the look reads it beside', (tester) async {
    final poses = <ValueListenable<GlassPageControlPose>>[];
    final progresses = <double?>[];
    Widget control(double progress) => _app(
      GlassPageControl(
        count: 3,
        page: 1,
        progress: progress,
        onChanged: (_) {},
        style: GlassPageControlStyle(
          builder: (context, details) {
            poses.add(details.pose);
            progresses.add(details.progress);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pumpWidget(control(0.2));
    await tester.pumpWidget(control(0.6));
    expect(identical(poses.first, poses.last), isTrue);
    expect(progresses.last, 0.6);
    expect(poses.last.value.progress, isNull);
  });

  testWidgets("its states are UIKit's interaction state: pressed under a "
      'finger, dragged too while it scrubs', (tester) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          statesController: states,
          onChanged: (_) {},
        ),
      ),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    final finger = await tester.startGesture(box.center);
    await tester.pump(const Duration(milliseconds: 140));
    expect(states.value, contains(WidgetState.pressed));
    expect(states.value, isNot(contains(WidgetState.dragged)));
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      states.value,
      containsAll([WidgetState.pressed, WidgetState.dragged]),
    );
    await finger.up();
    await tester.pump();
    expect(states.value, isNot(contains(WidgetState.pressed)));
    expect(states.value, isNot(contains(WidgetState.dragged)));
  });

  testWidgets('a direction across runs the pages that way whatever the '
      'reading direction', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          direction: AxisDirection.right,
          onChanged: picks.add,
        ),
        direction: TextDirection.rtl,
      ),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [1]);
  });

  testWidgets('a control whose page does not follow returns to it; disabled '
      'it ignores taps', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks, accept: false)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 3]);

    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 2, onChanged: null)),
    );
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page the parent sets under the finger shows once the '
      'finger leaves', (tester) async {
    GlassPageControlDetails? seen;
    Widget raw(int page) => _app(
      RawGlassPageControl(
        count: 5,
        page: page,
        onChanged: (_) {},
        builder: (context, details) {
          seen = details;
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpWidget(raw(0));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassPageControl)),
    );
    await tester.pump();
    await tester.pumpWidget(raw(3));
    await tester.pump();
    expect(seen!.pose.value.page, 0);
    await gesture.cancel();
    await tester.pump();
    await tester.pump();
    expect(seen!.pose.value.page, 3);
  });

  testWidgets('a progress capsule widens the control by its extra width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 0, onChanged: null)),
    );
    final plain = tester.getSize(find.byType(GlassPageControl)).width;
    await tester.pumpWidget(
      _app(
        const GlassPageControl(
          count: 5,
          page: 0,
          progress: 0.5,
          onChanged: null,
        ),
      ),
    );
    final withProgress = tester.getSize(find.byType(GlassPageControl)).width;
    expect(withProgress - plain, closeTo(27.33 - 9.67, 1e-9));
  });

  testWidgets('minimal drops the platter padding and height', (tester) async {
    Widget control(GlassPageControlBackground style, {int count = 5}) => _app(
      GlassPageControl(
        count: count,
        page: 0,
        backgroundStyle: style,
        onChanged: null,
      ),
    );
    Size size() => tester.getSize(find.byType(RawGlassPageControl));

    await tester.pumpWidget(control(GlassPageControlBackground.prominent));
    expect(size().width, closeTo(108.33, 0.03));
    expect(size().height, 25.67);
    await tester.pumpWidget(control(GlassPageControlBackground.minimal));
    expect(size().width, closeTo(5 * 9.67 + 4 * 8, 1e-9));
    expect(size().height, 9.67);
    await tester.pumpWidget(
      control(GlassPageControlBackground.minimal, count: 1),
    );
    expect(size(), const Size(9.67, 9.67));
  });

  testWidgets('a prominent platter and its dots take the measured colors', (
    tester,
  ) async {
    Future<void> pumpIn(Brightness brightness) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(platformBrightness: brightness),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GlassPageControl(
              count: 3,
              page: 0,
              backgroundStyle: GlassPageControlBackground.prominent,
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    final painter = find.descendant(
      of: find.byType(GlassPageControl),
      matching: find.byType(CustomPaint),
    );

    await pumpIn(Brightness.light);
    expect(
      painter.last,
      paints
        ..rrect(color: const Color(0xFFF5F6F5))
        ..rrect(color: const Color(0xFFFFFFFF))
        ..rrect(color: const Color(0x40000000)),
    );
    await pumpIn(Brightness.dark);
    expect(
      painter.last,
      paints
        ..rrect(color: const Color(0xFF1F201F))
        ..rrect(color: const Color(0xFFFFFFFF))
        ..rrect(color: const Color(0x40FFFFFF)),
    );
  });

  testWidgets('without a platter a tap on either half still steps toward it', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          backgroundStyle: GlassPageControlBackground.minimal,
          onChanged: picks.add,
        ),
      ),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.center + const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tapAt(box.center - const Offset(4, 0));
    await tester.pump();
    expect(picks, [3, 1]);
  });

  testWidgets('a raw control builds its look from the pose, mirrored in a '
      'right-to-left context', (tester) async {
    GlassPageControlDetails? seen;
    Widget raw(TextDirection direction) => _app(
      RawGlassPageControl(
        count: 3,
        page: 0,
        onChanged: null,
        backgroundStyle: GlassPageControlBackground.prominent,
        builder: (context, details) {
          seen = details;
          return const SizedBox.expand();
        },
      ),
      direction: direction,
    );
    await tester.pumpWidget(raw(TextDirection.ltr));
    final box = tester.getSize(find.byType(RawGlassPageControl));
    final ltr = seen!.pose.value;
    expect(seen!.states, {WidgetState.disabled});
    expect(ltr.platter, 1);
    expect(ltr.indicators, hasLength(3));
    expect(ltr.indicators.first.center.dx, lessThan(box.width / 2));

    await tester.pumpWidget(raw(TextDirection.rtl));
    final rtl = seen!.pose.value;
    expect(rtl.indicators.first.center.dx, greaterThan(box.width / 2));
    expect(
      rtl.indicators.first.center.dx,
      closeTo(box.width - ltr.indicators.first.center.dx, 1e-9),
    );
  });

  testWidgets('under a WidgetsApp the value commands step it, mirrored in '
      'right to left; Page Up, Page Down, Space and Enter do nothing, and an '
      'app adds keys with Shortcuts', (tester) async {
    for (final direction in TextDirection.values) {
      final picks = <int>[];
      await tester.pumpWidget(
        _keyApp(
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyN): AdjustValueIntent(
                ValueCommand.increase,
              ),
            },
            child: GlassPageControl(
              key: ValueKey(direction),
              count: 5,
              page: 2,
              onChanged: picks.add,
              autofocus: true,
            ),
          ),
          direction: direction,
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyN,
      ]) {
        await tester.sendKeyEvent(key);
      }
      final right = direction == TextDirection.ltr ? 3 : 1;
      expect(picks, [right, 3, 0, 4, 3], reason: '$direction');
    }
  });

  testWidgets('it reads as one adjustable value over its 44 point target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 3,
          page: 2,
          onChanged: picks.add,
          semanticLabel: 'Pages',
        ),
      ),
    );
    final size = tester.getSize(find.byType(RawGlassPageControl));
    final node = tester.getSemantics(find.bySemanticsLabel('Pages'));
    expect(node.rect.size, Size(size.width, 44));
    expect(node.rect.top, closeTo((size.height - 44) / 2, 1e-9));
    expect(
      node,
      matchesSemantics(
        label: 'Pages',
        textDirection: TextDirection.ltr,
        value: 'page 3 of 3',
        increasedValue: 'page 3 of 3',
        decreasedValue: 'page 2 of 3',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    tester.semantics.decrease(find.semantics.byLabel('Pages'));
    expect(picks, [1]);
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension steps; one beyond does not', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    expect(box.height, lessThan(44));
    final above = box.centerRight + Offset(-6, -box.height / 2 - 2);
    await tester.tapAt(above);
    await tester.pump();
    expect(picks, [3]);
    await tester.tapAt(box.centerRight + const Offset(-6, 23));
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('keys and accessibility play no haptic, nor does a scrub '
      'under a haptic scope that turns them off', (tester) async {
    final semantics = tester.ensureSemantics();
    final played = _haptics(tester);
    await tester.pumpWidget(
      _keyApp(
        MotionHapticScope(
          enabled: false,
          child: GlassPageControl(
            count: 5,
            page: 2,
            onChanged: (_) {},
            autofocus: true,
            semanticLabel: 'Pages',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 25));
    }
    await gesture.up();
    await tester.pump();
    expect(played, isEmpty);
    semantics.dispose();
  });

  testWidgets('an app passes its own states controller, and the builder '
      'sees pressed', (tester) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    final seen = <Set<WidgetState>>[];
    await tester.pumpWidget(
      _app(
        RawGlassPageControl(
          count: 5,
          page: 2,
          onChanged: (_) {},
          statesController: states,
          builder: (context, details) {
            seen.add(details.states);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassPageControl)),
    );
    await tester.pump();
    expect(states.value, contains(WidgetState.pressed));
    expect(seen.last, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pump();
    expect(states.value, isNot(contains(WidgetState.pressed)));
  });

  testWidgets('an app that passes the page back late sees the control '
      'return, then follow', (tester) async {
    var page = 2;
    late StateSetter set;
    GlassPageControlPose? pose;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassPageControl(
              count: 5,
              page: page,
              onChanged: (_) {},
              builder: (context, details) {
                return ValueListenableBuilder(
                  valueListenable: details.pose,
                  builder: (context, value, _) {
                    pose = value;
                    return const SizedBox.expand();
                  },
                );
              },
            );
          },
        ),
      ),
    );
    final box = tester.getRect(find.byType(RawGlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pose!.page, 2);
    set(() => page = 3);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pose!.page, 3);
  });

  testWidgets('a change raised while the framework builds does not throw '
      'and reaches the app in the next frame', (tester) async {
    var page = 2;
    var raise = false;
    late StateSetter rebuild;
    late PageControlMotion motion;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (raise) {
                  raise = false;
                  motion.pointerUp(motion.clock.now, 1000);
                }
                return RawGlassPageControl(
                  count: 5,
                  page: page,
                  onChanged: (next) => setState(() => page = next),
                  builder: (context, details) => const SizedBox.expand(),
                );
              },
            );
          },
        ),
      ),
    );
    motion =
        tester
                .widget<MotionScope>(
                  find.descendant(
                    of: find.byType(RawGlassPageControl),
                    matching: find.byType(MotionScope),
                  ),
                )
                .motion
            as PageControlMotion;
    motion.pointerDown(motion.clock.now, 1000);
    rebuild(() => raise = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(page, 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(page, 3);
    expect(motion.page, 3);
  });

  testWidgets('a control of 12 pages stands 8 slots wide on page 9, the '
      "current one a progress capsule with a pager's progress", (tester) async {
    for (final progress in [null, 9.0, 9.4]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GlassPageControl(
              count: 12,
              page: 9,
              progress: progress,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(GlassPageControl)).width,
        moreOrLessEquals(
          progress == null ? 161.33 : 161.33 + 27.33 - 9.67,
          epsilon: 0.05,
        ),
      );
    }
  });
}
