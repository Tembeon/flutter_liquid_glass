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

// 64 points up in 0.375 s turns a wheel by two rows (date picker test).
Future<void> _turnTwo(WidgetTester tester, Finder wheel) async {
  await tester.timedDrag(
    wheel,
    const Offset(0, -64),
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

  testWidgets('a wheel at rest on a new month or year reports its first '
      'day, moved into the bounds by month', (tester) async {
    final picked = <DateTime>[];
    await tester.pumpWidget(
      _app(
        GlassMonthYearPicker(
          value: DateTime(2026, 10, 17, 9, 30),
          maximumDate: DateTime(2027, 2, 10),
          onChanged: picked.add,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(GlassMonthYearPicker)),
      GlassMonthYearPicker.size,
    );
    final wheels = find.byType(ListWheelScrollView);
    expect(wheels, findsNWidgets(2));
    await _turnTwo(tester, wheels.first);
    expect(picked, [DateTime(2026, 12)]);
    await _turnTwo(tester, wheels.last);
    expect(picked.last, DateTime(2027, 2));
  });
}
