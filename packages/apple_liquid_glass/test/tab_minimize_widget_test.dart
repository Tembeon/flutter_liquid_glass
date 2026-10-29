import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app({
  required GlassTabBarMinimizeBehavior behavior,
  ScrollController? controller,
  int rows = 60,
}) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: GlassTabScaffold(
        tabBar: GlassTabBar(
          minimizeBehavior: behavior,
          destinations: const [
            GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('One'),
            ),
            GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('Two'),
            ),
            GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('Three'),
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
        tabBuilder: (context, i) => GlassPageScaffold(
          child: GlassContentScroll(
            child: ListView(
              controller: controller,
              children: [
                for (var r = 0; r < rows; r++) const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _dragUp(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(const Offset(201, 400));
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(Offset(0, -distance / 20));
    await tester.pump(_frame);
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await _settle(tester);
}

bool _expanded(WidgetTester tester) =>
    find.byType(RawGlassSelector).evaluate().isNotEmpty;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a bar that does not opt in never minimizes', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.automatic),
    );
    await tester.pump();
    await _dragUp(tester, 300);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a user scroll shrinks the bar into a circle 28 points from '
      'the screen corner; a tap on it expands the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
    );
    await tester.pump();
    expect(_expanded(tester), isTrue);
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    final group = tester.getTopLeft(find.byType(GlassSurface));
    final circle = surface.frame!.value.rect!.shift(group);
    expect(circle.left, closeTo(28, 0.5));
    expect(circle.bottom, closeTo(874 - 28, 0.5));
    expect(circle.width, closeTo(48, 0.5));
    await tester.tapAt(circle.center);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a scroll the app drives never minimizes the bar', (
    tester,
  ) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    controller.jumpTo(800);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('content with less than 96 points to scroll never minimizes '
      'the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown, rows: 16),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('scrolling back to the top expands the bar', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    controller.jumpTo(0);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });
}
