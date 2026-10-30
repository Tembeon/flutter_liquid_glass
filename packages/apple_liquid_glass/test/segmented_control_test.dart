import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:apple_liquid_glass/src/renderer/lens_shrink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
  double? width = 300,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassTheme(
      data: theme.merge(GlassThemeData(renderer: renderer)),
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

const _segments = [
  GlassSegment(value: 'a', label: Text('One')),
  GlassSegment(value: 'b', label: Text('Two')),
  GlassSegment(value: 'c', label: Text('Three')),
];

class _Controlled extends StatefulWidget {
  const _Controlled({this.onChanged, this.onReselected});

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onReselected;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  String value = 'a';

  @override
  Widget build(BuildContext context) => GlassSegmentedControl<String>(
    segments: _segments,
    groupValue: value,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => value = next);
    },
    onReselected: widget.onReselected,
  );
}

class _Probe {
  int builds = 0;
  GlassSelectorDetails? details;

  Widget build(BuildContext context, GlassSelectorDetails details) {
    builds++;
    this.details = details;
    return details.items();
  }

  GlassFrame get lens => details!.lens.value;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Offset _at(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap selects on release and the lens travels there', (
    tester,
  ) async {
    final probe = _Probe();
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final start = probe.lens.rect!.center.dx;
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    expect(values, ['c']);
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'c',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    await _settle(tester);
    expect(probe.lens.rect!.center.dx, closeTo(start + 200, 1));
    expect(probe.lens.lift, 0);
  });

  testWidgets('a drag lifts the lens and carries it without building; the '
      'release selects where it lands', (tester) async {
    final probe = _Probe();
    final values = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: values.add,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, 'One'));
    await tester.pump(_frame);
    final built = probe.builds;
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(_frame);
    }
    expect(probe.lens.lift, greaterThan(0.9));
    expect(probe.lens.rect!.center.dx, greaterThan(150));
    expect(probe.builds - built, lessThanOrEqualTo(2));
    await gesture.up();
    await _settle(tester);
    expect(values, ['c']);
    expect(probe.lens.lift, 0);
  });

  testWidgets('a release more than 70 points away selects nothing', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: values.add)));
    final gesture = await tester.startGesture(_at(tester, 'Two'));
    await tester.pump(_frame);
    await gesture.moveTo(_at(tester, 'Two') + const Offset(0, 90));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(values, isEmpty);

    final near = await tester.startGesture(_at(tester, 'Two'));
    await tester.pump(_frame);
    await near.moveTo(_at(tester, 'Two') + const Offset(0, 60));
    await tester.pump(_frame);
    await near.up();
    await _settle(tester);
    expect(values, ['b']);
  });

  testWidgets('with nothing selected there is no lens; a tap selects and the '
      'lens appears at rest', (tester) async {
    final probe = _Probe();
    final values = <String>[];
    Widget control(String? value) => _app(
      GlassSegmentedControl<String>(
        segments: _segments,
        groupValue: value,
        onChanged: values.add,
        style: GlassSegmentedStyle(builder: probe.build),
      ),
    );
    await tester.pumpWidget(control(null));
    expect(probe.details!.selectedIndex, isNull);
    await tester.tapAt(_at(tester, 'Two'));
    await tester.pump();
    expect(values, ['b']);
    await tester.pumpWidget(control('b'));
    await tester.pump(_frame);
    expect(probe.details!.selectedIndex, 1);
    expect(probe.lens.rect!.center.dx, closeTo(150, 1));
    expect(probe.lens.lift, 0);
  });

  testWidgets('a tap on the selected segment reselects it', (tester) async {
    final reselected = <String>[];
    final changed = <String>[];
    await tester.pumpWidget(
      _app(_Controlled(onChanged: changed.add, onReselected: reselected.add)),
    );
    await tester.tapAt(_at(tester, 'One'));
    await _settle(tester);
    expect(reselected, ['a']);
    expect(changed, isEmpty);
  });

  testWidgets('a disabled segment takes no tap and the arrow keys skip it', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final values = <String>[];
    var value = 'a';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _app(
          GlassSegmentedControl<String>(
            segments: const [
              GlassSegment(value: 'a', label: Text('One')),
              GlassSegment(value: 'b', label: Text('Two'), enabled: false),
              GlassSegment(value: 'c', label: Text('Three')),
            ],
            groupValue: value,
            focusNode: focus,
            onChanged: (next) {
              values.add(next);
              setState(() => value = next);
            },
          ),
        ),
      ),
    );
    await tester.tapAt(_at(tester, 'Two'));
    await _settle(tester);
    expect(values, isEmpty);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(values, ['c']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(values, ['c', 'a']);
  });

  testWidgets('right to left, the first segment sits at the right', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(
      _app(_Controlled(onChanged: values.add), direction: TextDirection.rtl),
    );
    expect(_at(tester, 'One').dx, greaterThan(_at(tester, 'Three').dx));
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    expect(values, ['c']);
  });

  testWidgets('segments read as a group of buttons, one selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final values = <String>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: values.add)));
    expect(
      tester.getSemantics(find.text('One')),
      matchesSemantics(
        label: 'One',
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Two'));
    await _settle(tester);
    expect(values, ['b']);
    semantics.dispose();
  });

  testWidgets('a pressed segment that is not selected dims its label', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Controlled(onChanged: (_) {})));
    double opacityOf(String label) {
      RenderObject? node = tester.renderObject(find.text(label));
      while (node != null && node.debugLayer is! OffsetLayer) {
        node = node.parent;
      }
      final layer = node?.debugLayer;
      return layer is OpacityLayer ? layer.alpha! / 255 : 1;
    }

    final gesture = await tester.startGesture(_at(tester, 'Three'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
    }
    final row = tester.layers.whereType<OpacityLayer>().map(
      (layer) => layer.alpha! / 255,
    );
    expect(row, contains(closeTo(0.2, 0.01)));
    expect(opacityOf('One'), 1);
    await gesture.up();
    await _settle(tester);
    expect(
      tester.layers.whereType<OpacityLayer>().where(
        (layer) => layer.alpha! < 255,
      ),
      isEmpty,
    );
  });

  testWidgets('disabled it is dim; the theme styles the track and the '
      'lens', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: null,
        ),
        theme: GlassThemeData(
          segmentedStyle: GlassSegmentedControl.styleFrom(
            backgroundColor: const Color(0xFF123456),
            thumbColor: const Color(0xFF654321),
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.5);
    final surfaces = tester.widgetList<GlassSurface>(
      find.byType(GlassSurface),
    );
    expect(surfaces.first.glass.tint, isSameColorAs(const Color(0xFF123456)));
    expect(surfaces.last.glass.tint, isSameColorAs(const Color(0xFF654321)));
  });

  testWidgets('sized by content, a longer label gets a wider segment; '
      'without a bound the control takes its natural width', (tester) async {
    const segments = [
      GlassSegment(value: 'a', label: Text('A')),
      GlassSegment(value: 'b', label: Text('A much longer label')),
    ];
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: segments,
          groupValue: 'a',
          onChanged: (_) {},
          proportionalWidth: true,
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    expect(probe.lens.rect!.width, lessThan(120));
    await tester.pumpWidget(
      _app(
        UnconstrainedBox(
          child: GlassSegmentedControl<String>(
            segments: segments,
            groupValue: 'a',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(RawGlassSelector));
    expect(size.height, 32);
    expect(size.width, lessThan(300));
    expect(size.width, greaterThan(100));
  });

  testWidgets('a control whose value does not follow returns to it', (
    tester,
  ) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        GlassSegmentedControl<String>(
          segments: _segments,
          groupValue: 'a',
          onChanged: (_) {},
          style: GlassSegmentedStyle(builder: probe.build),
        ),
      ),
    );
    final start = probe.lens.rect!.center.dx;
    await tester.tapAt(_at(tester, 'Three'));
    await _settle(tester);
    await _settle(tester);
    expect(probe.lens.rect!.center.dx, closeTo(start, 1));
  });

  testWidgets('on liquid glass the lens gets a glass layer only while '
      'lifted', (tester) async {
    await tester.pumpWidget(
      _app(
        _Controlled(onChanged: (_) {}),
        renderer: const GlassRenderer.liquid(),
      ),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(_at(tester, 'One'));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(find.byType(LiquidGlassLayer), findsNothing);
  });

  testWidgets('the item states reach a raw selector, once for the row '
      'under the lens and once for the selected copy inside it', (
    tester,
  ) async {
    final seen = <(int, bool), Set<WidgetState>>{};
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          disabledItems: const {1},
          itemBuilder: (context, index, states) {
            seen[(index, states.contains(WidgetState.selected))] = states;
            return Text('$index');
          },
          builder: (context, details) => details.items(),
        ),
      ),
    );
    expect(seen[(0, false)], isEmpty);
    expect(seen[(0, true)], {WidgetState.selected});
    expect(seen[(1, false)], {WidgetState.disabled});
    expect(seen[(1, true)], {WidgetState.selected, WidgetState.disabled});
    final gesture = await tester.startGesture(_at(tester, '0'));
    await tester.pump();
    expect(seen[(0, false)], {WidgetState.pressed});
    expect(seen[(0, true)], {WidgetState.selected, WidgetState.pressed});
    await gesture.up();
    await _settle(tester);
    expect(seen[(0, false)], isEmpty);
  });

  testWidgets('the lens draws over the regular items and under the selected '
      'copy it masks', (tester) async {
    const lens = Color(0xFF00FF00);
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('$index'),
          builder: (context, details) =>
              details.items(lens: const ColoredBox(color: lens)),
        ),
      ),
    );
    expect(
      find.byType(RawGlassSelector),
      paints
        ..paragraph()
        ..paragraph()
        ..rect(color: lens)
        ..clipRRect()
        ..paragraph(),
    );
  });

  testWidgets('a lifted lens draws over the copy it bends', (tester) async {
    const lens = Color(0xFF00FF00);
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 2,
          selectedIndex: 0,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('$index'),
          builder: (context, details) =>
              details.items(lens: const ColoredBox(color: lens)),
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, '0'));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(_frame);
    }
    expect(
      find.byType(RawGlassSelector),
      paints
        ..paragraph()
        ..paragraph()
        ..clipRRect()
        ..paragraph()
        ..rect(color: lens),
    );
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('through the shrinking glass of a lifted lens, the copy under '
      'it shows every item on its slot', (tester) async {
    late GlassSelectorDetails details;
    await tester.pumpWidget(
      _app(
        RawGlassSelector(
          itemCount: 3,
          selectedIndex: 1,
          onChanged: (_) {},
          itemBuilder: (context, index, states) => Text('Item $index'),
          builder: (context, d) {
            details = d;
            return d.items(lens: const _ShrinkingLens());
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(_at(tester, 'Item 1'));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(_frame);
    }
    final frame = details.lens.value;
    final lens = frame.drawnIn(tester.getSize(find.byType(RawGlassSelector)));
    final grow =
        1 +
        (1 / (1 - _ShrinkingLens.shrink * frame.lift) - 1) *
            FlatGlassLook.glassness(frame.lift);
    expect(grow, greaterThan(1.1));
    final half = (lens.longestSide - lens.shortestSide) / 2;
    // Where the glass reads what lies under the point it shows: farther
    // from the nearest point of its center line, as the shader does.
    Offset read(Offset shown) {
      final nearest = Offset(
        shown.dx.clamp(lens.center.dx - half, lens.center.dx + half),
        lens.center.dy,
      );
      return shown + (shown - nearest) * (grow - 1);
    }

    final drawn = <(Rect, Matrix4)>[];
    var strip = Rect.zero;
    expect(
      find.byType(RawGlassSelector),
      paints..everything((method, arguments) {
        if (method == #clipRect) strip = arguments[0]! as Rect;
        if (method == #transform) {
          drawn.add((
            strip,
            Matrix4.fromFloat64List(arguments[0]! as Float64List),
          ));
        }
        return true;
      }),
    );
    final checked = <Rect>{};
    for (final (strip, transform) in drawn) {
      for (var x = lens.left; x <= lens.right; x += 2) {
        for (var y = lens.top; y <= lens.bottom; y += 2) {
          final point = Offset(x, y);
          final at = MatrixUtils.transformPoint(transform, point);
          if (!strip.deflate(0.01).contains(at)) continue;
          expect((read(point) - at).distance, lessThan(1e-6));
          checked.add(strip);
        }
      }
    }
    expect(checked, hasLength(3));
    await gesture.up();
    await _settle(tester);
  });

  test('a style lerps its colors and merges state by state', () {
    final a = GlassSegmentedControl.styleFrom(
      backgroundColor: const Color(0xFF000000),
    );
    final b = GlassSegmentedControl.styleFrom(
      backgroundColor: const Color(0xFFFFFFFF),
      thumbColor: const Color(0xFF00FF00),
    );
    final half = GlassSegmentedStyle.lerp(a, b, 0.5)!;
    expect(
      half.backgroundColor!.resolve({}),
      isSameColorAs(const Color(0xFF808080)),
    );
    final merged = a.merge(b);
    expect(merged.backgroundColor!.resolve({}), const Color(0xFF000000));
    expect(merged.thumbColor!.resolve({}), const Color(0xFF00FF00));
    expect(listEquals([a], [a]), isTrue);
  });
}

class _ShrinkingLens extends StatelessWidget {
  const _ShrinkingLens();

  static const double shrink = 0.2;

  @override
  Widget build(BuildContext context) {
    GlassLensShrink.maybeOf(context)!.value = (shrink: shrink, rim: 1);
    return const SizedBox.expand();
  }
}
