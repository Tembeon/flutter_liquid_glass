import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_shown.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const FlatGlassRenderer(),
  GlassThemeData theme = const GlassThemeData(),
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: renderer,
      child: GlassTheme(
        data: theme,
        child: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  ),
);

class _Controlled extends StatefulWidget {
  const _Controlled({this.ticks = 0, this.builder, this.onChanged});

  final int ticks;
  final GlassSliderBuilder? builder;
  final ValueChanged<double>? onChanged;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  double value = 0;

  void _set(double next) {
    widget.onChanged?.call(next);
    setState(() => value = next);
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder != null) {
      return RawGlassSlider(
        value: value,
        ticks: widget.ticks,
        onChanged: _set,
        builder: builder,
      );
    }
    return GlassSlider(value: value, ticks: widget.ticks, onChanged: _set);
  }
}

class _Probe {
  int builds = 0;
  ValueListenable<GlassFrame>? thumb;
  ValueListenable<GlassFrame>? fill;
  List<Offset> ticks = const [];

  Widget build(BuildContext context, GlassSliderDetails details) {
    builds++;
    thumb = details.thumb;
    fill = details.fill;
    ticks = details.ticks;
    return const SizedBox.expand();
  }
}

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

Widget _keyApp(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(child: SizedBox(width: 300, child: child)),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Offset _thumbStart(WidgetTester tester) =>
    tester.getTopLeft(find.byType(RawGlassSlider)) +
    const Offset(37 / 2, RawGlassSlider.height / 2);

void main() {
  testWidgets('with snapsToTicks off a value between ticks rests where it '
      "is, and enabled bounds in the slider's own range stop a drag", (
    tester,
  ) async {
    var value = 45.0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => GlassSlider(
            value: value,
            max: 100,
            ticks: 4,
            snapsToTicks: false,
            enabledBounds: (20, 60),
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(GlassSlider));
    final thumb = Offset(
      box.left + 18.5 + 0.45 * (box.width - 37),
      box.center.dy,
    );
    final finger = await tester.startGesture(thumb);
    await finger.moveBy(const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await finger.moveBy(const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(value, inInclusiveRange(48.0, 56.0));
    await finger.moveBy(const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(value, moreOrLessEquals(60));
    await finger.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(value, lessThanOrEqualTo(60));
  });

  setUp(MotionClock.debugReset);

  testWidgets('a drag on the thumb moves the value without rebuilding the '
      'look; a release glides on and ends', (tester) async {
    final probe = _Probe();
    final values = <double>[];
    await tester.pumpWidget(
      _app(_Controlled(builder: probe.build, onChanged: values.add)),
    );
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 4; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    final built = probe.builds;
    for (var i = 5; i <= 20; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    expect(values, isNotEmpty);
    expect(values.last, greaterThan(0.2));
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1]));
    }
    expect(probe.thumb!.value.lift, greaterThan(0.9));
    expect(probe.builds, built);
    await gesture.up();
    await _settle(tester);
    expect(probe.builds - built, lessThanOrEqualTo(1));
    expect(probe.thumb!.value.lift, 0);
  });

  testWidgets('with a neutral value the fill runs from it to the thumb, on '
      'either side (slider passport, 300 wide)', (tester) async {
    for (final (value, left, right) in [
      (0.2, 71.1, 150.0),
      (0.8, 150.0, 228.9),
    ]) {
      final probe = _Probe();
      await tester.pumpWidget(
        _app(
          RawGlassSlider(
            value: value,
            neutralValue: 0.5,
            onChanged: (_) {},
            builder: probe.build,
          ),
        ),
      );
      await tester.pump();
      final fill = probe.fill!.value.rect!;
      expect(fill.left, moreOrLessEquals(left, epsilon: 0.5), reason: '$value');
      expect(
        fill.right,
        moreOrLessEquals(right, epsilon: 0.5),
        reason: '$value',
      );
    }
  });

  testWidgets('screen readers read the value through its formatter', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassSlider(
          value: 30,
          max: 100,
          semanticLabel: 'Volume',
          semanticFormatterCallback: (value) => '${value.round()} dB',
          onChanged: (_) {},
        ),
      ),
    );
    expect(
      find.semantics.byPredicate(
        (node) => node.label == 'Volume' && node.value == '30 dB',
      ),
      findsOne,
    );
    semantics.dispose();
  });

  for (final direction in TextDirection.values) {
    testWidgets('value labels stand at the ends at their own size, the track '
        '11 points from each, ${direction.name} (UIKit value images, iOS '
        '27.2 simulator)', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: 370,
                child: GlassSlider(
                  value: 0.5,
                  onChanged: (_) {},
                  minimumValueLabel: const SizedBox(
                    key: Key('min'),
                    width: 17,
                    height: 17.33,
                  ),
                  maximumValueLabel: const SizedBox(
                    key: Key('max'),
                    width: 27.67,
                    height: 19,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(GlassSlider));
      final track = tester
          .getRect(find.byType(RawGlassSlider))
          .shift(-box.topLeft);
      final ltr = direction == TextDirection.ltr;
      expect(track.left, moreOrLessEquals(ltr ? 28 : 38.67, epsilon: 0.01));
      expect(track.right, moreOrLessEquals(ltr ? 331.33 : 342, epsilon: 0.01));
      expect(
        tester.getSize(find.byKey(const Key('max'))),
        const Size(27.67, 19),
      );
      expect(
        tester.getCenter(find.byKey(const Key('min'))).dy,
        moreOrLessEquals(tester.getCenter(find.byType(RawGlassSlider)).dy),
      );
    });
  }

  testWidgets('without its thumb the track is 7 points tall and no thumb '
      'draws (UIKit thumbless, iOS 27.2 simulator)', (tester) async {
    GlassSliderDetails? seen;
    await tester.pumpWidget(
      _app(
        RawGlassSlider(
          value: 0.5,
          onChanged: (_) {},
          showsThumb: false,
          builder: (context, details) {
            seen = details;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();
    expect(seen!.showsThumb, isFalse);
    expect(seen!.track.value.rect!.height, 7);
    await tester.pumpWidget(
      _app(GlassSlider(value: 0.5, onChanged: (_) {}, showsThumb: false)),
    );
    await tester.pump();
    expect(
      tester
          .widgetList<GlassSurface>(find.byType(GlassSurface))
          .where((surface) => surface.role == GlassRole.lens),
      isEmpty,
    );
  });

  testWidgets('a tap on the track does nothing', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: values.add)));
    await tester.tapAt(
      tester.getCenter(find.byType(RawGlassSlider)) + const Offset(60, 0),
    );
    await _settle(tester);
    expect(values, isEmpty);
  });

  testWidgets('arrow keys and accessibility step it; it reads as a slider', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        GlassSlider(
          value: 0.5,
          onChanged: values.add,
          focusNode: focus,
          semanticLabel: 'Volume',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Volume')),
      matchesSemantics(
        label: 'Volume',
        value: '50%',
        increasedValue: '60%',
        decreasedValue: '40%',
        isSlider: true,
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
    tester.semantics.increase(find.semantics.byLabel('Volume'));
    expect(values, [
      closeTo(0.6, 1e-9),
      closeTo(0.4, 1e-9),
      closeTo(0.6, 1e-9),
    ]);
    semantics.dispose();
  });

  testWidgets('right to left, the value grows to the left', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      _app(_Controlled(onChanged: values.add), direction: TextDirection.rtl),
    );
    final start =
        tester.getTopRight(find.byType(RawGlassSlider)) +
        const Offset(-37 / 2, RawGlassSlider.height / 2);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 15; i++) {
      await gesture.moveBy(const Offset(-6, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _settle(tester);
    expect(values.last, greaterThan(0.1));
  });

  testWidgets('a stepped slider reports stops and hands its ticks to the '
      'look', (tester) async {
    final probe = _Probe();
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        _Controlled(ticks: 5, builder: probe.build, onChanged: values.add),
      ),
    );
    expect(probe.ticks, hasLength(5));
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _settle(tester);
    for (final value in values) {
      expect((value * 4 - (value * 4).round()).abs(), lessThan(1e-9));
    }
    expect(values.last, greaterThan(0));
  });

  testWidgets('a slider whose value does not follow returns to it', (
    tester,
  ) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSlider(value: 0, onChanged: (_) {}, builder: probe.build),
      ),
    );
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _settle(tester);
    await _settle(tester);
    expect(probe.fill!.value.rect!.width, lessThan(1));
  });

  testWidgets('a value the parent sets under the finger shows once the '
      'finger leaves', (tester) async {
    final probe = _Probe();
    Widget slider(double value) => _app(
      RawGlassSlider(value: value, onChanged: (_) {}, builder: probe.build),
    );
    await tester.pumpWidget(slider(0));
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    final held = probe.fill!.value.rect!.width;
    await tester.pumpWidget(slider(1));
    await _settle(tester);
    expect(probe.fill!.value.rect!.width, closeTo(held, 1));
    await gesture.cancel();
    await _settle(tester);
    expect(probe.fill!.value.rect!.width, greaterThan(held + 100));
  });

  testWidgets('disabled it is dim and ignores the thumb; the theme styles '
      'the fill', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassSlider(value: 0.5, onChanged: null),
        theme: GlassThemeData(
          styles: [
            GlassSlider.styleFrom(
              activeTrackColor: const Color(0xFF123456),
            ),
          ],
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.5);
    final fill = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .elementAt(1);
    expect(fill.glass.tint, isSameColorAs(const Color(0xFF123456)));
  });

  testWidgets('on liquid glass the thumb gets a glass layer only while '
      'lifted', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const LiquidGlassRenderer()),
    );
    expect(findShown(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(findShown(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(findShown(LiquidGlassLayer), findsNothing);
  });

  testWidgets('a theme, brightness or style change reaches the cached look', (
    tester,
  ) async {
    Color fillTint() => tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .elementAt(1)
        .glass
        .tint!;
    Widget slider({Color? primary, Brightness? brightness}) => _app(
      GlassSlider(value: 0.5, onChanged: (_) {}),
      theme: GlassThemeData(primaryColor: primary, brightness: brightness),
    );
    await tester.pumpWidget(slider());
    expect(fillTint(), isSameColorAs(const Color(0xFF0088FF)));
    await tester.pumpWidget(slider(brightness: .dark));
    expect(fillTint(), isSameColorAs(const Color(0xFF0091FF)));
    await tester.pumpWidget(slider(primary: const Color(0xFF123456)));
    expect(fillTint(), isSameColorAs(const Color(0xFF123456)));
  });

  testWidgets('a tap on the thumb starts and ends a change', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSlider(
          value: 0,
          onChanged: (_) => calls.add('changed'),
          onChangeStart: (_) => calls.add('start'),
          onChangeEnd: (_) => calls.add('end'),
        ),
      ),
    );
    await tester.tapAt(_thumbStart(tester));
    await _settle(tester);
    expect(calls, ['start', 'end']);
  });

  testWidgets('a value set from outside at rest moves the thumb; so do keys '
      'and a new range', (tester) async {
    final probe = _Probe();
    Widget slider(double value, {double max = 1}) => _app(
      RawGlassSlider(
        value: value,
        max: max,
        onChanged: (_) {},
        builder: probe.build,
      ),
    );
    await tester.pumpWidget(slider(0.2));
    await tester.pump(_frame);
    final at = probe.thumb!.value.rect!.center.dx;
    await tester.pumpWidget(slider(0.8));
    await tester.pump(_frame);
    expect(probe.thumb!.value.rect!.center.dx, greaterThan(at + 100));
    final full = probe.thumb!.value.rect!.center.dx;
    await tester.pumpWidget(slider(0.8, max: 2));
    await tester.pump(_frame);
    expect(probe.thumb!.value.rect!.center.dx, lessThan(full - 100));
  });

  testWidgets('a drag reports pressed and dragged to the look', (tester) async {
    final probe = _Probe();
    final seen = <WidgetState>{};
    await tester.pumpWidget(
      _app(
        _Controlled(
          builder: (context, details) {
            seen.addAll(details.states);
            return probe.build(context, details);
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 6; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    expect(seen, containsAll([WidgetState.pressed, WidgetState.dragged]));
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('under a WidgetsApp the value commands step it, Home and End '
      'end it, and Page Up, Page Down, Space and Enter do nothing', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      _keyApp(
        GlassSlider(
          value: 15,
          onChanged: values.add,
          autofocus: true,
          min: 10,
          max: 20,
        ),
      ),
    );
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.enter,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(values, [closeTo(16, 1e-9), closeTo(14, 1e-9), 10, 20]);
  });

  testWidgets('an adjustment step sets how far a key steps a continuous '
      'slider, and screen readers hear the values a step away', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      _keyApp(
        GlassSlider(
          value: 15,
          onChanged: values.add,
          autofocus: true,
          min: 10,
          max: 20,
          adjustmentStep: 0.5,
          semanticFormatterCallback: (value) => value.toStringAsFixed(1),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(values, [closeTo(15.5, 1e-9), closeTo(14.5, 1e-9)]);
    expect(
      tester.getSemantics(find.byType(GlassSlider)),
      matchesSemantics(
        value: '15.0',
        increasedValue: '15.5',
        decreasedValue: '14.5',
        isSlider: true,
        isFocusable: true,
        isFocused: true,
        hasEnabledState: true,
        isEnabled: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
      ),
    );
  });

  testWidgets('an app adds keys with Shortcuts, and right-to-left mirrors '
      'the arrows', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      _keyApp(
        Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyJ): AdjustValueIntent(
              ValueCommand.decrease,
            ),
          },
          child: GlassSlider(
            value: 0.5,
            onChanged: values.add,
            autofocus: true,
          ),
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(values, [
      closeTo(0.4, 1e-9),
      closeTo(0.6, 1e-9),
      closeTo(0.4, 1e-9),
    ]);
  });

  testWidgets('it reads as a slider over its 44 point target, its actions '
      'the value commands', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <double>[];
    await tester.pumpWidget(
      _app(
        GlassSlider(value: 1, onChanged: values.add, semanticLabel: 'Volume'),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Volume')),
      matchesSemantics(
        label: 'Volume',
        rect: const Rect.fromLTWH(0, -5, 300, 44),
        textDirection: TextDirection.ltr,
        value: '100%',
        increasedValue: '100%',
        decreasedValue: '90%',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    tester.semantics.increase(find.semantics.byLabel('Volume'));
    tester.semantics.decrease(find.semantics.byLabel('Volume'));
    expect(values, [closeTo(0.9, 1e-9)]);
    semantics.dispose();
  });

  testWidgets('a drag that starts in the 44 point extension takes the '
      'thumb', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 100,
              child: Center(child: _Controlled(onChanged: values.add)),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      _thumbStart(tester) + const Offset(0, -21),
    );
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _settle(tester);
    expect(values, isNotEmpty);
    expect(values.last, greaterThan(0.1));
  });

  testWidgets('a finger dragged into an end plays a light impact; keys and '
      'a haptic scope play none', (tester) async {
    final played = _haptics(tester);
    Widget slider({bool haptics = true}) => _keyApp(
      MotionHapticScope(enabled: haptics, child: const _Focused()),
    );
    await tester.pumpWidget(slider());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settle(tester);
    expect(played, isEmpty);
    Future<void> dragToEnd() async {
      final gesture = await tester.startGesture(_thumbStart(tester));
      for (var i = 1; i <= 20; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(_frame);
      }
      await gesture.up();
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await _settle(tester);
    }

    await dragToEnd();
    expect(played, ['HapticFeedbackType.lightImpact']);
    await tester.pumpWidget(slider(haptics: false));
    await dragToEnd();
    expect(played, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('Reduce Motion from MotionTraitsOverride keeps the thumb '
      'down', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: RawGlassSlider(
            value: 0,
            onChanged: (_) {},
            builder: probe.build,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
    }
    expect(probe.thumb!.value.lift, 0);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('an app that passes the value back late sees the slider '
      'return, then follow', (tester) async {
    final probe = _Probe();
    var value = 0.0;
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassSlider(
              value: value,
              onChanged: (_) {},
              builder: probe.build,
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _settle(tester);
    expect(probe.fill!.value.rect!.width, lessThan(1));
    set(() => value = 0.5);
    await _settle(tester);
    expect(probe.fill!.value.rect!.width, greaterThan(100));
  });

  testWidgets('the ticks of the first frame span the track', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSlider(
          value: 0,
          ticks: 3,
          onChanged: (_) {},
          builder: probe.build,
        ),
      ),
    );
    expect(probe.ticks.map((tick) => tick.dx), [18, 149.5, 281]);
  });

  testWidgets('a change raised while the framework builds does not throw '
      'and reaches the app in the next frame', (tester) async {
    var value = 0.0;
    var raise = false;
    late StateSetter rebuild;
    late SliderMotion motion;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, setRaiser) {
                  rebuild = setRaiser;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (raise) {
                        raise = false;
                        final t = motion.clock.now;
                        motion.pointerMove(t, 18.5 + 90);
                        motion.pointerUp(t, 18.5 + 90, velocity: 0);
                      }
                      return const SizedBox();
                    },
                  );
                },
              ),
              RawGlassSlider(
                value: value,
                onChanged: (next) => setState(() => value = next),
                builder: (context, details) => const SizedBox.expand(),
              ),
            ],
          ),
        ),
      ),
    );
    motion =
        tester
                .widget<MotionScope>(
                  find.descendant(
                    of: find.byType(RawGlassSlider),
                    matching: find.byType(MotionScope),
                  ),
                )
                .motion
            as SliderMotion;
    motion.pointerDown(motion.clock.now, 18.5);
    motion.pointerMove(motion.clock.now, 18.5, begin: true);
    rebuild(() => raise = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(value, 0);
    await tester.pump(_frame);
    expect(value, closeTo(0.3, 1e-9));
    await _settle(tester);
    expect(motion.reportedValue, closeTo(0.3, 1e-9));
  });
}

class _Focused extends StatefulWidget {
  const _Focused();

  @override
  State<_Focused> createState() => _FocusedState();
}

class _FocusedState extends State<_Focused> {
  double value = 0;

  @override
  Widget build(BuildContext context) => GlassSlider(
    value: value,
    autofocus: true,
    onChanged: (next) => setState(() => value = next),
  );
}
