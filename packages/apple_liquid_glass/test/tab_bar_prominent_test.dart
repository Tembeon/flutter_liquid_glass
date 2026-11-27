import 'package:apple_liquid_glass/apple_liquid_glass.dart';
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
}
