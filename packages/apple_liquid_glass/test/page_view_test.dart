import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(402, 874)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a page control across the foot follows the pages and turns '
      'them', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final shown = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageView(
          onPageChanged: shown.add,
          children: const [Text('One'), Text('Two'), Text('Three')],
        ),
      ),
    );
    final control = find.byType(GlassPageControl);
    expect(tester.widget<GlassPageControl>(control).page, 0);
    expect(tester.getRect(control).bottom, 874);
    expect(tester.getCenter(control).dx, 201);
    await tester.fling(find.text('One'), const Offset(-200, 0), 1000);
    await _settle(tester);
    expect(shown, [1]);
    expect(tester.widget<GlassPageControl>(control).page, 1);
    final rect = tester.getRect(control);
    await tester.tapAt(rect.centerRight - const Offset(8, 0));
    await _settle(tester);
    expect(shown, [1, 2]);
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets('one page hides the control unless it shows always; never '
      'shows none', (tester) async {
    await tester.pumpWidget(_app(const GlassPageView(children: [Text('One')])));
    expect(find.byType(GlassPageControl), findsNothing);
    await tester.pumpWidget(
      _app(
        const GlassPageView(
          indexDisplay: GlassPageIndexDisplay.always,
          children: [Text('One')],
        ),
      ),
    );
    expect(find.byType(GlassPageControl), findsOneWidget);
    await tester.pumpWidget(
      _app(
        const GlassPageView(
          indexDisplay: GlassPageIndexDisplay.never,
          children: [Text('One'), Text('Two')],
        ),
      ),
    );
    expect(find.byType(GlassPageControl), findsNothing);
  });
}
