import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _spring = Spring.response(0.4);

class _Probe {
  GlassSelectorDetails? details;

  Widget build(BuildContext context, GlassSelectorDetails details) {
    this.details = details;
    return details.items();
  }

  GlassFrame get lens => details!.lens.value;
  GlassFrame get body => details!.body.value;
}

class _Segments extends StatefulWidget {
  const _Segments({required this.values, required this.probe});

  final List<String> values;
  final _Probe probe;

  @override
  State<_Segments> createState() => _SegmentsState();
}

class _SegmentsState extends State<_Segments> {
  late List<String> values = widget.values;

  void change(List<String> next) => setState(() => values = next);

  @override
  Widget build(BuildContext context) => GlassSegmentedControl<String>(
    segments: [
      for (final value in values)
        GlassSegment(value: value, label: Text(value)),
    ],
    groupValue: 'c',
    onChanged: (_) {},
    style: GlassSegmentedStyle(builder: widget.probe.build),
  );
}

Widget _app(
  Widget child, {
  double? width = 300,
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Finder _item(Object key) => find.byKey(ValueKey((0, key)));

// Where the item's regular look is drawn: its layer's offset in the view,
// not where layout put it.
Rect _drawn(WidgetTester tester, Object key) {
  final box = tester.renderObject<RenderBox>(_item(key));
  Layer? layer = box.debugLayer;
  var origin = Offset.zero;
  while (layer != null) {
    if (layer is OffsetLayer) origin += layer.offset;
    layer = layer.parent;
  }
  return origin & box.size;
}

// The opacity the item's regular look is drawn at.
double _opacity(WidgetTester tester, Object key) {
  Layer? layer = tester.renderObject<RenderBox>(_item(key)).debugLayer;
  var opacity = 1.0;
  while (layer != null) {
    if (layer is OpacityLayer) opacity *= layer.alpha! / 255;
    layer = layer.parent;
  }
  return opacity;
}

double _laidOutCenter(WidgetTester tester, Object key) =>
    tester.getCenter(_item(key)).dx;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  const a = ValueKey<String>('a');
  const b = ValueKey<String>('b');
  const c = ValueKey<String>('c');
  const x = ValueKey<String>('x');

  testWidgets("a segment inserted inside withSpring comes as UIKit's "
      'insertSegment(animated:) runs: out of the trailing edge of the '
      'segment before it at its own width, fading in, while the segments '
      'and the lens move, all on one 0.25 s ease in-out whatever the spring '
      '(iOS 27.2 simulator)', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(_Segments(values: const ['a', 'b', 'c'], probe: probe)),
    );
    final segments = tester.state<_SegmentsState>(find.byType(_Segments));
    final left = tester.getTopLeft(find.byType(_Segments)).dx;
    expect(_drawn(tester, b).center.dx, closeTo(_laidOutCenter(tester, b), 1));
    expect(probe.lens.rect!.center.dx, closeTo(250, 1));

    withSpring(_spring, () => segments.change(['a', 'x', 'b', 'c']));
    await tester.pump(_frame);
    expect(_laidOutCenter(tester, b), closeTo(left + 187.5, 1));
    expect(_drawn(tester, b).center.dx, closeTo(left + 150, 0.5));
    final start = _drawn(tester, x);
    expect(start.left - left, closeTo(100, 0.5));
    expect(start.width, closeTo(75, 0.5));
    expect(_opacity(tester, x), lessThan(0.05));
    expect(probe.lens.rect!.center.dx, closeTo(250, 0.5));

    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    const eased = 0.5207;
    expect(_drawn(tester, b).center.dx - left, closeTo(150 + 37.5 * eased, 1));
    expect(_opacity(tester, x), closeTo(eased, 0.02));
    expect(probe.lens.rect!.center.dx, closeTo(250 + 12.5 * eased, 1));
    expect(probe.lens.scaleX, closeTo(1, 0.01), reason: 'rigid, as a CA frame');
    expect(probe.lens.scaleY, closeTo(1, 0.01));

    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    expect(_drawn(tester, b).center.dx - left, closeTo(187.5, 0.5));
    expect(_opacity(tester, x), 1);
    expect(_drawn(tester, a).center.dx - left, closeTo(37.5, 0.5));
    await _settle(tester);
    expect(probe.lens.rect!.center.dx, closeTo(262.5, 0.5));
  });

  testWidgets('a segment removed inside withSpring fades out while its '
      'center slides onto the new trailing edge of the segment before it, '
      'then goes (iOS 27.2 simulator)', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(_Segments(values: const ['a', 'b', 'c'], probe: probe)),
    );
    final segments = tester.state<_SegmentsState>(find.byType(_Segments));
    final left = tester.getTopLeft(find.byType(_Segments)).dx;

    withSpring(_spring, () => segments.change(['a', 'b']));
    await tester.pump(_frame);
    expect(_drawn(tester, c).center.dx - left, closeTo(250, 0.5));
    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    const eased = 0.5207;
    expect(_drawn(tester, c).center.dx - left, closeTo(250 + 50 * eased, 1));
    expect(_opacity(tester, c), closeTo(1 - eased, 0.02));
    expect(_drawn(tester, b).center.dx - left, closeTo(150 + 75 * eased, 1));

    await _settle(tester);
    expect(find.text('c'), findsNothing);
    expect(_drawn(tester, b).center.dx - left, closeTo(225, 0.5));
  });

  testWidgets('a first segment removed slides half its width less 5 toward '
      'the leading side, its center ending 5 inside the control (iOS 27.2 '
      'simulator)', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(_Segments(values: const ['a', 'b', 'c'], probe: probe)),
    );
    final segments = tester.state<_SegmentsState>(find.byType(_Segments));
    final left = tester.getTopLeft(find.byType(_Segments)).dx;

    withSpring(_spring, () => segments.change(['b', 'c']));
    await tester.pump(_frame);
    for (var i = 0; i < 15; i++) {
      await tester.pump(_frame);
    }
    expect(_drawn(tester, a).center.dx - left, closeTo(5, 0.5));
    await _settle(tester);
    expect(find.text('a'), findsNothing);
    expect(probe.lens.rect!.center.dx, closeTo(225, 0.5));
  });

  testWidgets('right to left, a new segment starts on the trailing edge '
      'of the one before it, on its left, and a first one removed ends 5 '
      'inside the right edge', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        _Segments(values: const ['a', 'b', 'c'], probe: probe),
        direction: TextDirection.rtl,
      ),
    );
    final segments = tester.state<_SegmentsState>(find.byType(_Segments));
    final left = tester.getTopLeft(find.byType(_Segments)).dx;

    withSpring(_spring, () => segments.change(['a', 'x', 'b', 'c']));
    await tester.pump(_frame);
    final start = _drawn(tester, x);
    expect(start.right - left, closeTo(200, 0.5));
    expect(start.width, closeTo(75, 0.5));
    await _settle(tester);

    withSpring(_spring, () => segments.change(['x', 'b', 'c']));
    await tester.pump(_frame);
    for (var i = 0; i < 15; i++) {
      await tester.pump(_frame);
    }
    expect(_drawn(tester, a).center.dx - left, closeTo(295, 0.5));
  });

  testWidgets('a change outside withSpring jumps', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(_Segments(values: const ['a', 'b', 'c'], probe: probe)),
    );
    final segments = tester.state<_SegmentsState>(find.byType(_Segments));
    final left = tester.getTopLeft(find.byType(_Segments)).dx;

    segments.change(['a', 'c']);
    await tester.pump(_frame);
    expect(_drawn(tester, c).center.dx - left, closeTo(225, 0.5));
    expect(probe.lens.rect!.center.dx, closeTo(225, 0.5));
    await tester.pump(_frame);
    expect(find.text('b'), findsNothing);
  });

  testWidgets('a tab inserted inside withSpring grows the bar about where it '
      'stands', (tester) async {
    final probe = _Probe();
    var tabs = ['one', 'two', 'three'];
    late StateSetter setTabs;
    await tester.pumpWidget(
      _app(
        width: null,
        StatefulBuilder(
          builder: (context, setState) {
            setTabs = setState;
            return GlassTabBar(
              destinations: [
                for (final tab in tabs)
                  GlassTabDestination(
                    id: tab,
                    icon: const SizedBox(width: 24, height: 24),
                    label: Text(tab),
                  ),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              style: GlassTabBarStyle(builder: probe.build),
            );
          },
        ),
      ),
    );
    final before = tester.getSize(find.byType(GlassTabBar)).width;
    expect(probe.body.rect, isNull);

    withSpring(
      _spring,
      () => setTabs(() => tabs = ['one', 'four', 'two', 'three']),
    );
    await tester.pump(_frame);
    await tester.pump(_frame);
    final after = tester.getSize(find.byType(GlassTabBar)).width;
    expect(after, greaterThan(before));
    final body = probe.body.rect!;
    expect(body.width, lessThan(after - 1));
    expect(body.width, greaterThanOrEqualTo(before - 1));
    expect(body.center.dx, closeTo(after / 2, 1));

    await _settle(tester);
    expect(probe.body.rect, isNull);
  });
}
