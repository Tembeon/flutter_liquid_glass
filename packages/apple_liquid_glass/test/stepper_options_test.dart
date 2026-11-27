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

Offset _half(WidgetTester tester, GlassStepperHalf half) => half
    .rectIn(tester.getRect(find.byType(RawGlassStepper)), TextDirection.ltr)
    .center;

Future<void> _hold(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds - 1e-9; t += 0.01) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('with wraps a step past the maximum goes on from the minimum '
      'and back, no half disables', (tester) async {
    var value = 9.0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _app(
          GlassStepper(
            value: value,
            max: 10,
            wraps: true,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );
    final plus = _half(tester, GlassStepperHalf.increment);
    final minus = _half(tester, GlassStepperHalf.decrement);
    await tester.tapAt(plus);
    await tester.pump();
    expect(value, 10);
    await tester.tapAt(plus);
    await tester.pump();
    expect(value, 0);
    await tester.tapAt(minus);
    await tester.pump();
    expect(value, 10);
  });

  testWidgets('without autorepeat a hold steps once, at its release', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        GlassStepper(value: 0, autorepeat: false, onChanged: values.add),
      ),
    );
    final gesture = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await _hold(tester, 2);
    expect(values, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(values, [1]);
  });

  testWidgets('a hold starts and ends the change once, the end with the '
      'value the steps reached even where the app does not rebuild', (
    tester,
  ) async {
    final starts = <double>[];
    final ends = <double>[];
    final steps = <double>[];
    await tester.pumpWidget(
      _app(
        GlassStepper(
          value: 3,
          onChanged: steps.add,
          onChangeStart: starts.add,
          onChangeEnd: ends.add,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    expect(starts, [3]);
    await _hold(tester, 1.55);
    await gesture.up();
    await tester.pump();
    expect(steps, [4, 5, 6]);
    expect(ends, [6]);
  });

  testWidgets("the divider takes the style's color", (tester) async {
    await tester.pumpWidget(
      _app(
        GlassStepper(
          value: 3,
          onChanged: (_) {},
          style: GlassStepper.styleFrom(dividerColor: const Color(0xFFFF0000)),
        ),
      ),
    );
    expect(
      find.byType(GlassStepper),
      paints..something(
        (method, arguments) => arguments.any(
          (argument) =>
              argument is Paint && argument.color == const Color(0xFFFF0000),
        ),
      ),
    );
  });
}
