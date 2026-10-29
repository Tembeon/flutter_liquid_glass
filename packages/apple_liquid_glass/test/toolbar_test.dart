import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/scroll_edge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child, {double keyboard = 0}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(402, 874),
    devicePixelRatio: 3,
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: child,
    ),
  ),
);

Widget _page({ScrollController? controller}) => GlassPageScaffold(
  toolbar: GlassToolbar(
    children: [
      GlassButton(
        key: const Key('first'),
        onPressed: () {},
        child: const Text('Edit'),
      ),
      const Spacer(),
      GlassButton(
        key: const Key('last'),
        onPressed: () {},
        child: const Text('Done'),
      ),
    ],
  ),
  child: GlassContentScroll(
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 50, child: Text('Row $i')),
      ],
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the items float 28 points from the sides and the bottom of '
      'the screen', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_page()));
    final first = tester.getRect(find.byKey(const Key('first')));
    final last = tester.getRect(find.byKey(const Key('last')));
    expect(first.left, 28);
    expect(last.right, 402 - 28);
    expect(first.center.dy, 874 - 28 - 24);
  });

  testWidgets('above a keyboard the items keep 8 points from it', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_page(), keyboard: 336));
    final first = tester.getRect(find.byKey(const Key('first')));
    expect(first.center.dy, 874 - 336 - 8 - 24);
  });

  testWidgets('the content scrolls clear of the toolbar, and no automatic '
      'edge effect lies under it', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_page(controller: controller)));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(tester.getBottomLeft(find.text('Row 39')).dy, 874 - 76);
    final edges = tester
        .widgetList<ScrollEdge>(find.byType(ScrollEdge))
        .map((edge) => edge.details.edge);
    expect(edges, isNot(contains(AxisDirection.down)));
  });
}
