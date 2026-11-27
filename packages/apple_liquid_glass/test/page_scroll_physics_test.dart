import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 402.0;

Widget _pages(PageController controller) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: _width,
      height: 300,
      child: PageView(
        controller: controller,
        pageSnapping: false,
        physics: const GlassPageScrollPhysics(),
        children: [
          for (var i = 0; i < 4; i++) ColoredBox(color: Color(0xFF000000 + i)),
        ],
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// A drag that holds still before it lifts, so it leaves no speed.
Future<void> _heldDrag(WidgetTester tester, double dx) async {
  final gesture = await tester.startGesture(const Offset(201, 437));
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
}

void main() {
  testWidgets('a held release goes to the nearest page: back short of half '
      'a page, on past it', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_pages(controller));
    await _heldDrag(tester, -(180.0 + 18));
    await _settle(tester);
    expect(controller.page, 0);
    await _heldDrag(tester, -(240.0 + 18));
    await _settle(tester);
    expect(controller.page, 1);
  });

  testWidgets('a release faster than 300 points a second turns a page '
      'whatever the distance, a slower one does not', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_pages(controller));
    await tester.flingFrom(const Offset(201, 437), const Offset(-60, 0), 1400);
    await _settle(tester);
    expect(controller.page, 1);
    await tester.flingFrom(const Offset(201, 437), const Offset(-60, 0), 200);
    await _settle(tester);
    expect(controller.page, 1);
  });

  testWidgets('the settle takes about 0.35 s whatever the distance', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_pages(controller));
    await _heldDrag(tester, -(240.0 + 18));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(controller.position.pixels, lessThan(_width - 2));
    await tester.pump(const Duration(milliseconds: 240));
    expect(controller.position.pixels, moreOrLessEquals(_width, epsilon: 1));
  });

  test('past the first page the content follows on the rubber band, '
      'slope 0.55 over a page', () {
    const physics = GlassPageScrollPhysics();
    var pixels = 0.0;
    for (var i = 0; i < 15; i++) {
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 3 * _width,
        pixels: pixels,
        viewportDimension: _width,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 3,
      );
      pixels -= physics.applyPhysicsToUserOffset(metrics, 10);
    }
    const travel = 150;
    const shown = 0.55 * travel * _width / (_width + 0.55 * travel);
    expect(pixels, moreOrLessEquals(-shown, epsilon: 0.01));
  });

  testWidgets('a pull past the first page springs back', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_pages(controller));
    final gesture = await tester.startGesture(const Offset(201, 437));
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.position.pixels, inExclusiveRange(-100, -30));
    await gesture.up();
    await _settle(tester);
    expect(controller.position.pixels, 0);
  });
}
