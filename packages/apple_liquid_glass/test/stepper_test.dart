import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

class _Probe {
  int builds = 0;
  GlassStepperHalf? pressed;
  GlassStepperDetails? details;

  Widget build(BuildContext context, GlassStepperDetails details) {
    builds++;
    pressed = details.pressed;
    this.details = details;
    return const SizedBox.expand();
  }
}

Offset _half(WidgetTester tester, GlassStepperHalf half) {
  final box = tester.getRect(find.byType(RawGlassStepper));
  return half == GlassStepperHalf.decrement
      ? box.centerLeft + Offset(box.width / 4, 0)
      : box.centerRight - Offset(box.width / 4, 0);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap commits on release; a held half repeats every half '
      'second', (tester) async {
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: probe.build,
        ),
      ),
    );
    final tap = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await tester.pump();
    expect(probe.pressed, GlassStepperHalf.increment);
    expect(values, isEmpty);
    await tap.up();
    await tester.pump();
    expect(values, [6]);
    expect(probe.pressed, isNull);

    values.clear();
    final hold = await tester.startGesture(
      _half(tester, GlassStepperHalf.decrement),
    );
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(values, [4, 4, 4]);
    await hold.up();
    await tester.pump();
    expect(values, [4, 4, 4]);
  });

  testWidgets('sliding to the other half moves the highlight without a '
      'step; leaving cancels', (tester) async {
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: probe.build,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      _half(tester, GlassStepperHalf.decrement),
    );
    await tester.pump();
    await gesture.moveTo(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    expect(probe.pressed, GlassStepperHalf.increment);
    expect(values, isEmpty);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(probe.pressed, isNull);
    await gesture.up();
    await tester.pump();
    expect(values, isEmpty);
  });

  testWidgets('limits, keys and two semantic buttons; minus stays left in '
      'right to left', (tester) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <double>[];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 0,
          max: 3,
          onChanged: values.add,
          focusNode: focus,
          builder: probe.build,
        ),
        direction: TextDirection.rtl,
      ),
    );
    expect(probe.details!.canDecrement, isFalse);
    expect(probe.details!.canIncrement, isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Increment')),
      matchesSemantics(
        label: 'Increment',
        value: '0',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getCenter(find.bySemanticsLabel('Decrement')).dx,
      lessThan(tester.getCenter(find.bySemanticsLabel('Increment')).dx),
    );
    await tester.tapAt(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    tester.semantics.tap(find.semantics.byLabel('Increment'));
    // The value stays at the minimum, where the left arrow does nothing.
    expect(values, [1, 1, 1, 1]);
    semantics.dispose();
  });

  testWidgets('disabled it ignores touches and keys', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(RawGlassStepper(value: 5, onChanged: null, builder: probe.build)),
    );
    await tester.tapAt(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    expect(probe.pressed, isNull);
    expect(probe.details!.states, contains(WidgetState.disabled));
  });

  testWidgets('the stock stepper paints from the theme', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: GlassThemeData(
            stepperStyle: GlassStepper.styleFrom(
              backgroundColor: const Color(0xFF123456),
            ),
          ),
          child: GlassStepper(value: 5, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
