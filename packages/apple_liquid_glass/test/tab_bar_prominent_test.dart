import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _Bar extends StatefulWidget {
  const _Bar(this.picks);

  final List<int> picks;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => GlassTabBar(
    destinations: [
      for (final (i, name) in ['One', 'Two', 'Add', 'Four'].indexed)
        GlassTabDestination(
          icon: SizedBox.square(key: Key('glyph $i'), dimension: 24),
          label: Text(name),
          prominent: i == 2,
        ),
    ],
    selectedIndex: selected,
    onDestinationSelected: (index) => setState(() {
      widget.picks.add(index);
      selected = index;
    }),
  );
}

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 21),
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  ),
);

double _lens(WidgetTester tester) => tester
    .widgetList<GlassSurface>(find.byType(GlassSurface))
    .where((surface) => surface.role == GlassRole.lens)
    .single
    .frame!
    .value
    .opacity;

class _Toggle extends StatefulWidget {
  const _Toggle({required this.names, this.addsTab = false});

  final List<String> names;

  /// Whether the Add tab is there only while prominent.
  final bool addsTab;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool prominent = false;

  void toggle({required bool on}) => setState(() => prominent = on);

  @override
  Widget build(BuildContext context) => GlassTabBar(
    destinations: [
      for (final name in widget.names)
        if (prominent || name != 'Add' || !widget.addsTab)
          GlassTabDestination(
            id: name,
            icon: RepaintBoundary(
              child: SizedBox.square(key: Key('glyph $name'), dimension: 24),
            ),
            label: Text(name),
            prominent: prominent && name == 'Add',
          ),
    ],
    selectedIndex: 0,
    onDestinationSelected: (_) {},
  );
}

// Where a glyph is drawn and how opaque: its layer's offsets and
// translations in the view, and the opacities above it.
(double, double) _glyph(WidgetTester tester, Finder glyph) {
  final boundary = tester.renderObject<RenderBox>(
    find.ancestor(of: glyph, matching: find.byType(RepaintBoundary)).first,
  );
  Layer? layer = boundary.debugLayer;
  var x = 0.0;
  var opacity = 1.0;
  while (layer != null) {
    switch (layer) {
      case MotionTransitionLayer(:final total, :final alpha):
        x += total.getTranslation().x;
        opacity *= (alpha ?? 255) / 255;
      case TransformLayer(:final offset, :final transform?):
        x += offset.dx + transform.getTranslation().x;
      case OpacityLayer(:final offset, :final alpha?):
        x += offset.dx;
        opacity *= alpha / 255;
      case OffsetLayer(:final offset):
        x += offset.dx;
      default:
    }
    layer = layer.parent;
  }
  return (x + boundary.size.width / 2, opacity);
}

Finder _circleGlyph() => find.descendant(
  of: find.byType(RawGlassButton),
  matching: find.byKey(const Key('glyph Add')),
);

Finder _tabGlyph(String name) => find
    .descendant(
      of: find.byType(RawGlassSelector),
      matching: find.byKey(Key('glyph $name')),
    )
    .first;

// How far a critically damped spring of [response] has gone after [t].
double _critical(double response, double t) {
  final w = 2 * math.pi / response;
  return 1 - (1 + w * t) * math.exp(-w * t);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a prominent tab stands in a 62 point circle at the trailing '
      'side beside a 290 point bar; selected, its glyph takes the tint and '
      "the bar's lens fades over 0.25 s (iOS 27.2 simulator)", (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Bar(picks)));
    await tester.pump();
    final circle = tester.getRect(find.byType(RawGlassButton));
    expect(circle.size, const Size(62, 62));
    expect(circle.left, moreOrLessEquals(319));
    expect(
      tester.getSize(find.byType(RawGlassSelector)).width,
      moreOrLessEquals(290),
    );
    expect(find.text('Add'), findsNothing, reason: 'the circle has no title');
    expect(_lens(tester), 1);

    await tester.tap(find.byType(RawGlassButton));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    expect(picks, [2]);
    expect(_lens(tester), inExclusiveRange(0.2, 0.8));
    for (var i = 0; i < 30; i++) {
      await tester.pump(_frame);
    }
    expect(_lens(tester), 0);
    final glyph = find.descendant(
      of: find.byType(RawGlassButton),
      matching: find.byKey(const Key('glyph 2')),
    );
    expect(
      IconTheme.of(tester.element(glyph)).color,
      isSameColorAs(const Color(0xFF0088FF)),
    );

    await tester.tap(find.text('Four').first);
    for (var i = 0; i < 30; i++) {
      await tester.pump(_frame);
    }
    expect(picks, [2, 3]);
    expect(_lens(tester), 1);
  });
  testWidgets('a prominent tab set inside an animation brings its circle in '
      'from half its width toward the trailing side, fading in, on a '
      'critically damped 0.3 s spring while the bar shrinks to 290, and '
      'takes it out as the mirror (iOS 27.2 simulator: x 350 to 319); the '
      'bar keeps its state', (tester) async {
    await tester.pumpWidget(
      _app(const _Toggle(names: ['One', 'Two', 'Add', 'Four'])),
    );
    await tester.pump();
    final toggle = tester.state<_ToggleState>(find.byType(_Toggle));
    final selector = tester.state(find.byType(RawGlassSelector));
    expect(find.byType(RawGlassButton), findsNothing);
    final four = _glyph(tester, _tabGlyph('Four')).$1;

    withSpring(const Spring.response(0.8), () => toggle.toggle(on: true));
    await tester.pump();
    expect(tester.state(find.byType(RawGlassSelector)), same(selector));
    await _frames(tester, 6);
    final shown = _critical(0.3, 0.096);
    final (x, opacity) = _glyph(tester, _circleGlyph());
    expect(opacity, closeTo(shown, 0.12));
    expect(x - 350, closeTo(31 * (1 - shown), 4));
    expect(_glyph(tester, _tabGlyph('Four')).$1, lessThan(four - 1));
    await _frames(tester, 60);
    final (restX, restOpacity) = _glyph(tester, _circleGlyph());
    expect(restX, moreOrLessEquals(350));
    expect(restOpacity, 1);
    expect(
      tester.getSize(find.byType(RawGlassSelector)).width,
      moreOrLessEquals(290),
    );

    withSpring(const Spring.response(0.8), () => toggle.toggle(on: false));
    await tester.pump();
    await _frames(tester, 6);
    final (outX, outOpacity) = _glyph(tester, _circleGlyph());
    expect(outOpacity, closeTo(1 - shown, 0.12));
    expect(outX - 350, closeTo(31 * shown, 4));
    await _frames(tester, 60);
    expect(find.byType(RawGlassButton), findsNothing);
    expect(tester.state(find.byType(RawGlassSelector)), same(selector));
    expect(
      tester.getSize(find.byType(RawGlassSelector)).width,
      moreOrLessEquals(360),
    );
    expect(_glyph(tester, _tabGlyph('Four')).$1, moreOrLessEquals(four));
  });

  testWidgets('a bar moved beside a new circle keeps its tabs where they '
      'were drawn and slides them to their new places; outside an '
      'animation its tabs jump while the circle still slides', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const _Toggle(names: ['One', 'Two', 'Add'], addsTab: true)),
    );
    await tester.pump();
    final toggle = tester.state<_ToggleState>(find.byType(_Toggle));
    final one = _glyph(tester, _tabGlyph('One')).$1;

    withSpring(const Spring.response(0.8), () => toggle.toggle(on: true));
    await tester.pump();
    expect(_glyph(tester, _tabGlyph('One')).$1, moreOrLessEquals(one));
    await _frames(tester, 60);
    final moved = _glyph(tester, _tabGlyph('One')).$1;
    expect(moved, lessThan(one - 10));

    toggle.toggle(on: false);
    await tester.pump();
    expect(_glyph(tester, _tabGlyph('One')).$1, moreOrLessEquals(one));
    await _frames(tester, 60);
    expect(find.byType(RawGlassButton), findsNothing);
    toggle.toggle(on: true);
    await tester.pump();
    expect(_glyph(tester, _tabGlyph('One')).$1, moreOrLessEquals(moved));
    await _frames(tester, 6);
    expect(
      _glyph(tester, _circleGlyph()).$2,
      closeTo(_critical(0.3, 0.096), 0.12),
    );
  });
}
