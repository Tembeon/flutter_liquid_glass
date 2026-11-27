import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  List<String> ids = const ['a', 'b', 'c'];

  void change(List<String> next) => setState(() => ids = next);

  @override
  Widget build(BuildContext context) => GlassTabBar(
    destinations: [
      for (final id in ids)
        GlassTabDestination(
          id: id,
          icon: const SizedBox.square(dimension: 24),
          label: Text(id),
        ),
    ],
    selectedIndex: 0,
    onDestinationSelected: (_) {},
  );
}

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 402),
          child: child,
        ),
      ),
    ),
  ),
);

// The selector keys a tab's regular look by the destination's id.
Finder _item(String id) => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey(:final value) => value == (0, (id, null)),
    _ => false,
  },
);

// Where the tab is drawn: its layer's offset in the view, not
// where layout put it.
double _drawn(WidgetTester tester, String id) {
  final box = tester.renderObject<RenderBox>(_item(id));
  Layer? layer = box.debugLayer;
  var origin = Offset.zero;
  while (layer != null) {
    if (layer is OffsetLayer) origin += layer.offset;
    layer = layer.parent;
  }
  return origin.dx + box.size.width / 2;
}

double _opacity(WidgetTester tester, String id) {
  Layer? layer = tester.renderObject<RenderBox>(_item(id)).debugLayer;
  var opacity = 1.0;
  while (layer != null) {
    if (layer is OpacityLayer) opacity *= layer.alpha! / 255;
    layer = layer.parent;
  }
  return opacity;
}

// How far a critically damped spring of [response] has gone after [t].
double _critical(double response, double t) {
  final w = 2 * 3.141592653589793 / response;
  return 1 - (1 + w * t) * _exp(-w * t);
}

double _exp(double x) {
  var sum = 1.0;
  var term = 1.0;
  for (var i = 1; i < 30; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets("tabs change as UIKit's setTabs(animated:) runs: the tabs on "
      'a critically damped 0.3 s spring whatever the caller gave, a new one '
      'fading in out of the place of the tab before it, a removed one fading '
      'on 0.2 s (iOS 27.2 simulator, live layers)', (tester) async {
    await tester.pumpWidget(_app(const _Tabs()));
    await tester.pump();
    final tabs = tester.state<_TabsState>(find.byType(_Tabs));
    final b0 = _drawn(tester, 'b');
    final a0 = _drawn(tester, 'a');

    withSpring(
      const Spring.response(0.8),
      () => tabs.change(['a', 'x', 'b', 'c']),
    );
    await tester.pump();
    final xStart = _drawn(tester, 'x');
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    final b1 = _drawn(tester, 'b');
    await _settle(tester);
    final b2 = _drawn(tester, 'b');
    final share = (b1 - b0) / (b2 - b0);
    expect(share, closeTo(_critical(0.3, 0.096), 0.12));
    expect(xStart, closeTo(a0, 6), reason: 'out of the place of a');
    expect(_opacity(tester, 'x'), 1);

    withSpring(const Spring.response(0.8), () => tabs.change(['a', 'b', 'c']));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(_opacity(tester, 'x'), closeTo(1 - _critical(0.2, 0.096), 0.12));
  });
}
