import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const GlassRenderer.flat(),
  GlassThemeData theme = const GlassThemeData(),
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassTheme(
      data: theme.merge(GlassThemeData(renderer: renderer)),
      child: Center(child: SizedBox(width: 300, child: child)),
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Offset _thumbStart(WidgetTester tester) =>
    tester.getTopLeft(find.byType(RawGlassSlider)) +
    const Offset(37 / 2, RawGlassSlider.height / 2);

void main() {
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

  testWidgets('disabled it is dim and ignores the thumb; the theme styles '
      'the fill', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassSlider(value: 0.5, onChanged: null),
        theme: GlassThemeData(
          sliderStyle: GlassSlider.styleFrom(
            activeTrackColor: const Color(0xFF123456),
          ),
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
      _app(const _Controlled(), renderer: const GlassRenderer.liquid()),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(_thumbStart(tester));
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(find.byType(LiquidGlassLayer), findsNothing);
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
}
