import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
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

Offset _half(
  WidgetTester tester,
  GlassStepperHalf half, {
  TextDirection direction = TextDirection.ltr,
}) =>
    half.rectIn(tester.getRect(find.byType(RawGlassStepper)), direction).center;

Future<void> _hold(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds - 1e-9; t += 0.01) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Widget _keyApp(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

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
      'step; leaving drops it and keeps the touch, a release outside steps '
      'nothing', (tester) async {
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
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(probe.pressed, GlassStepperHalf.increment);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(values, isEmpty);

    final back = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await tester.pump();
    await back.moveBy(const Offset(0, 60));
    await tester.pump();
    await back.moveBy(const Offset(0, -60));
    await tester.pump();
    await back.up();
    await tester.pump();
    expect(values, [6]);
  });

  testWidgets('a hold steps six times at half a second, then at a tenth up '
      'to the twentieth step, then at a twentieth', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    final hold = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await _hold(tester, 3.05);
    expect(values, hasLength(6));
    await _hold(tester, 1.37);
    expect(values, hasLength(20));
    await _hold(tester, 0.05);
    expect(values, hasLength(21));
    await hold.up();
    await tester.pump();
    expect(values, hasLength(21));
  });

  testWidgets('a repeat that finds the finger off the halves steps nothing '
      'and slows the clock back to half a second without restarting it', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    final hold = await tester.startGesture(
      _half(tester, GlassStepperHalf.increment),
    );
    await _hold(tester, 3.15);
    expect(values, hasLength(7));
    await hold.moveBy(const Offset(0, 60));
    await _hold(tester, 0.1);
    await hold.moveBy(const Offset(0, -60));
    await _hold(tester, 0.4);
    expect(values, hasLength(7));
    await _hold(tester, 0.1);
    expect(values, hasLength(8));
    await _hold(tester, 0.45);
    expect(values, hasLength(8));
    await _hold(tester, 0.1);
    expect(values, hasLength(9));
    await hold.up();
    await tester.pump();
  });

  testWidgets('a step that would cross a limit is refused, not clamped', (
    tester,
  ) async {
    Future<_Probe> stepper(double value, double max, double step) async {
      final probe = _Probe();
      await tester.pumpWidget(
        _app(
          RawGlassStepper(
            key: UniqueKey(),
            value: value,
            max: max,
            step: step,
            onChanged: (_) {},
            builder: probe.build,
          ),
        ),
      );
      return probe;
    }

    expect((await stepper(0.95, 1, 0.1)).details!.canIncrement, isFalse);
    expect((await stepper(0.9, 1, 0.1)).details!.canIncrement, isTrue);
    expect((await stepper(9, 10, 3)).details!.canIncrement, isFalse);
    expect((await stepper(0.05, 1, 0.1)).details!.canDecrement, isFalse);
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 0.95,
          max: 1,
          step: 0.1,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    await tester.tapAt(_half(tester, GlassStepperHalf.increment));
    await tester.pump();
    expect(values, isEmpty);
  });

  testWidgets('limits, keys and two semantic buttons; minus lies on the '
      'right in right to left', (tester) async {
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
      greaterThan(tester.getCenter(find.bySemanticsLabel('Increment')).dx),
    );
    await tester.tapAt(
      _half(tester, GlassStepperHalf.increment, direction: TextDirection.rtl),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    tester.semantics.tap(find.semantics.byLabel('Increment'));
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

  testWidgets('the stock stepper mirrors its glyphs in right to left and '
      'draws them 13.33 long, 14 at a limit', (tester) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        _app(
          GlassStepper(key: ValueKey(direction), value: 0, onChanged: (_) {}),
          direction: direction,
        ),
      );
      final minus = direction == TextDirection.ltr ? 23.5 : 70.5;
      final plus = 94 - minus;
      expect(
        find.byType(CustomPaint).first,
        paints
          ..line(p1: Offset(minus - 6, 16), p2: Offset(minus + 6, 16))
          ..line(p1: Offset(plus - 5.665, 16), p2: Offset(plus + 5.665, 16))
          ..line(p1: Offset(plus, 16 - 5.665), p2: Offset(plus, 16 + 5.665)),
        reason: '$direction',
      );
    }
  });

  testWidgets('the stock stepper paints from the theme', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: GlassThemeData(
            styles: [
              GlassStepper.styleFrom(
                backgroundColor: const Color(0xFF123456),
              ),
            ],
          ),
          child: GlassStepper(value: 5, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under a WidgetsApp the arrows step it toward the half they '
      'point at in either direction, Home and End end it, and Page Up, Page '
      'Down, Space and Enter do nothing', (tester) async {
    for (final direction in TextDirection.values) {
      final values = <double>[];
      await tester.pumpWidget(
        _keyApp(
          RawGlassStepper(
            key: ValueKey(direction),
            value: 5,
            max: 10,
            onChanged: values.add,
            autofocus: true,
            builder: _Probe().build,
          ),
          direction: direction,
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(
        values,
        direction == TextDirection.ltr
            ? [6, 4, 6, 4, 0, 10]
            : [4, 6, 6, 4, 0, 10],
        reason: '$direction',
      );
    }
  });

  testWidgets('an app adds keys with Shortcuts and replaces a command with '
      'Actions, for the keys and the buttons alike', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <double>[];
    final overridden = <ValueCommand>[];
    Widget stepper({bool override = false}) => _keyApp(
      Actions(
        actions: {
          if (override)
            AdjustValueIntent: CallbackAction<AdjustValueIntent>(
              onInvoke: (intent) => overridden.add(intent.command),
            ),
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.equal): AdjustValueIntent(
              ValueCommand.increase,
            ),
          },
          child: RawGlassStepper(
            value: 5,
            onChanged: values.add,
            autofocus: true,
            builder: _Probe().build,
          ),
        ),
      ),
    );
    await tester.pumpWidget(stepper());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    tester.semantics.tap(find.semantics.byLabel('Decrement'));
    expect(values, [6, 4]);
    await tester.pumpWidget(stepper(override: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    tester.semantics.tap(find.semantics.byLabel('Increment'));
    expect(values, [6, 4]);
    expect(overridden, [ValueCommand.increase, ValueCommand.increase]);
    semantics.dispose();
  });

  testWidgets('the adjustable node carries the semantic label and the value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          semanticLabel: 'Quantity',
          onChanged: (_) {},
          builder: _Probe().build,
        ),
      ),
    );
    await tester.pump();
    final node = tester.getSemantics(find.byType(RawGlassStepper));
    expect(node.label, 'Quantity');
    expect(node.value, '5');
    semantics.dispose();
  });

  testWidgets('one adjustable node with the value over its 44 point target '
      'holds the two buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    // A zone's box takes its size at the start of the next frame.
    await tester.pump();
    final node = tester.getSemantics(find.byType(RawGlassStepper));
    expect(
      node,
      matchesSemantics(
        rect: const Rect.fromLTWH(0, -6, 94, 44),
        value: '5',
        increasedValue: '6',
        decreasedValue: '4',
        textDirection: TextDirection.ltr,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        children: [
          matchesSemantics(
            label: 'Decrement',
            value: '5',
            rect: const Rect.fromLTWH(0, 0, 47, 44),
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
          matchesSemantics(
            label: 'Increment',
            value: '5',
            rect: const Rect.fromLTWH(0, 0, 47, 44),
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        ],
      ),
    );
    final origin = tester.getTopLeft(find.byType(RawGlassStepper));
    expect(
      tester.getRect(find.bySemanticsLabel('Decrement')).shift(-origin),
      const Rect.fromLTWH(0, -6, 47, 44),
    );
    expect(
      tester.getRect(find.bySemanticsLabel('Increment')).shift(-origin),
      const Rect.fromLTWH(47, -6, 47, 44),
    );
    tester.semantics.increase(
      find.semantics.byAction(SemanticsAction.increase),
    );
    tester.semantics.decrease(
      find.semantics.byAction(SemanticsAction.decrease),
    );
    expect(values, [6, 4]);
    semantics.dispose();
  });

  testWidgets('a tap in the 44 point extension steps the half above or '
      'below it; one beyond does not', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        RawGlassStepper(
          value: 5,
          onChanged: values.add,
          builder: _Probe().build,
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassStepper)), RawGlassStepper.size);
    await tester.tapAt(
      _half(tester, GlassStepperHalf.increment) + const Offset(0, -21),
    );
    await tester.tapAt(
      _half(tester, GlassStepperHalf.decrement) + const Offset(0, 21),
    );
    await tester.tapAt(
      _half(tester, GlassStepperHalf.increment) + const Offset(0, 23),
    );
    await tester.pump();
    expect(values, [6, 4]);
  });

  testWidgets('the half labels come from GlassLocalizations', (tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [_FrenchDelegate()],
        builder: (context, _) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GlassStepper(value: 5, onChanged: (_) {}),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Moins'), findsOneWidget);
    expect(find.bySemanticsLabel('Plus'), findsOneWidget);
    expect(find.bySemanticsLabel('Decrement'), findsNothing);
  });
}

class _French extends DefaultGlassLocalizations {
  const _French();

  @override
  String get decrementLabel => 'Moins';

  @override
  String get incrementLabel => 'Plus';
}

class _FrenchDelegate extends LocalizationsDelegate<GlassLocalizations> {
  const _FrenchDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture<GlassLocalizations>(const _French());

  @override
  bool shouldReload(_FrenchDelegate old) => false;
}
