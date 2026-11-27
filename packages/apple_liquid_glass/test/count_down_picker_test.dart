import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

// 64 points in 0.375 s turns a wheel by two rows (date picker test).
Future<void> _turnTwo(
  WidgetTester tester,
  Finder wheel, {
  bool up = true,
}) async {
  await tester.timedDrag(
    wheel,
    Offset(0, up ? -64 : 64),
    const Duration(milliseconds: 375),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

void main() {
  setUp(MotionClock.debugReset);

  test('a value shows floored to the interval, at least one interval and '
      'at most 23 hours and the last interval', () {
    Duration shown(int seconds, int interval) => GlassCountDownPicker.shownFor(
      Duration(seconds: seconds),
      minuteInterval: interval,
    );
    expect(shown(3725, 5), const Duration(hours: 1));
    expect(shown(86399, 5), const Duration(hours: 23, minutes: 55));
    expect(shown(100, 15), const Duration(minutes: 15));
    expect(shown(0, 1), const Duration(minutes: 1));
  });

  testWidgets('the units stand beside the numbers, "hour" for one and '
      '"hours" for more, and a wheel at rest reports the duration', (
    tester,
  ) async {
    final picked = <Duration>[];
    await tester.pumpWidget(
      _app(
        GlassCountDownPicker(
          value: const Duration(hours: 1, minutes: 30),
          onChanged: picked.add,
        ),
      ),
    );
    final box = tester.getTopLeft(find.byType(GlassCountDownPicker));
    expect(
      tester.getSize(find.byType(GlassCountDownPicker)),
      GlassCountDownPicker.size,
    );
    final hour = tester.getTopLeft(find.text('hour')) - box;
    expect(hour.dx, moreOrLessEquals(112.67, epsilon: 0.01));
    expect(hour.dy, moreOrLessEquals(98.33, epsilon: 0.01));
    expect(
      tester.getTopLeft(find.text('min')).dx - box.dx,
      moreOrLessEquals(197.67, epsilon: 0.01),
    );
    final wheels = find.byType(ListWheelScrollView);
    await _turnTwo(tester, wheels.first);
    expect(picked, [const Duration(hours: 3, minutes: 30)]);
    expect(find.text('hours'), findsOneWidget);
  });

  testWidgets('wheels that stop on 0:00 report one interval and the minute '
      'wheel turns on to it', (tester) async {
    final picked = <Duration>[];
    await tester.pumpWidget(
      _app(
        GlassCountDownPicker(
          value: const Duration(minutes: 10),
          minuteInterval: 5,
          onChanged: picked.add,
        ),
      ),
    );
    await _turnTwo(tester, find.byType(ListWheelScrollView).last, up: false);
    expect(picked, [const Duration(minutes: 5)]);
  });
}
