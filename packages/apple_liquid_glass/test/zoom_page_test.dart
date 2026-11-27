import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = Key('card');
const _page = Key('page');

Widget _app(GlobalKey<NavigatorState> navigator, MotionSource link) =>
    WidgetsApp(
      navigatorKey: navigator,
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) =>
          GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      home: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: Align(
          alignment: const Alignment(0, -0.3),
          child: GlassZoomSource(
            source: link,
            borderRadius: 16,
            child: const SizedBox(
              key: _card,
              width: 160,
              height: 100,
              child: ColoredBox(color: Color(0xFF3478F6)),
            ),
          ),
        ),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Route<void> _route(MotionSource link) => GlassPageRoute<void>(
  source: link,
  builder: (context) => const ColoredBox(
    key: _page,
    color: Color(0xFFFFFFFF),
    child: Center(child: Text('Detail')),
  ),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the page grows out of the card and fills the screen; the card '
      'hides meanwhile', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    final card = tester.getRect(find.byKey(_card));
    navigator.currentState!.push(_route(link));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = tester.getRect(find.byKey(_page));
    expect(early.width, lessThan(402));
    expect(early.width, greaterThan(card.width - 1));
    await _frames(tester, 90);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    expect(link.isHidden, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a pop zooms back into the card, which shows again', (
    tester,
  ) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    final card = tester.getRect(find.byKey(_card));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    navigator.currentState!.pop();
    await _frames(tester, 10);
    final shrinking = tester.getRect(find.byKey(_page));
    expect(shrinking.width, lessThan(402));
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
    expect(link.isHidden, isFalse);
    expect(tester.getRect(find.byKey(_card)), card);
  });

  testWidgets('a drag down past the threshold dismisses, a short one '
      'returns', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    final gesture = await tester.startGesture(const Offset(200, 400));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(find.byKey(_page)).width, lessThan(402));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await _frames(tester, 90);
    expect(find.byKey(_page), findsOneWidget, reason: 'a short drag returns');
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    await tester.flingFrom(const Offset(200, 300), const Offset(0, 300), 1500);
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('a drag from the leading edge takes the page with no cones '
      'and pops it only past 200 points from where it began, where a drag '
      'elsewhere pops past 150 (UIKit code)', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);

    Future<void> edgeDrag(int moves) async {
      final gesture = await tester.startGesture(const Offset(5, 400));
      for (var i = 0; i < moves; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(find.byKey(_page)).width, lessThan(402));
      await gesture.up();
      await _frames(tester, 90);
    }

    await edgeDrag(40);
    expect(find.byKey(_page), findsOneWidget, reason: '148 + 25 < 200');
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    await edgeDrag(60);
    expect(find.byKey(_page), findsNothing, reason: '228 + 25 > 200');

    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    await tester.flingFrom(const Offset(5, 300), const Offset(0, 300), 1500);
    await _frames(tester, 90);
    expect(
      find.byKey(_page),
      findsNothing,
      reason: 'a swipe down from the edge strip is the swipe down',
    );
  });

  testWidgets('two fingers pinching in shrink the page about the point '
      'between them, held over a quarter of its size by a rubber band, and '
      'pop it when released under half its size or 200 points lower; '
      'otherwise it returns (UIKit code)', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);

    Future<List<TestGesture>> pinch(double span, {double drop = 0}) async {
      final fingers = [
        await tester.startGesture(const Offset(150, 400), pointer: 1),
        await tester.startGesture(const Offset(250, 400), pointer: 2),
      ];
      const steps = 10;
      final inward = (100 - span) / 2 / steps;
      for (var i = 0; i < steps; i++) {
        await fingers[0].moveBy(Offset(inward, drop / steps));
        await fingers[1].moveBy(Offset(-inward, drop / steps));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return fingers;
    }

    Future<void> release(List<TestGesture> fingers) async {
      for (final finger in fingers) {
        await finger.up();
      }
      await _frames(tester, 90);
    }

    var fingers = await pinch(70);
    final held = tester.getRect(find.byKey(_page));
    expect(held.width, moreOrLessEquals(402 * 0.7, epsilon: 0.5));
    expect(
      held.center,
      offsetMoreOrLessEquals(
        const Offset(200 + 1 * 0.7, 400 + 37 * 0.7),
        epsilon: 0.5,
      ),
    );
    await release(fingers);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );

    await release(await pinch(70, drop: 250));
    expect(find.byKey(_page), findsNothing);

    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    fingers = await pinch(10);
    expect(
      tester.getRect(find.byKey(_page)).width,
      moreOrLessEquals(402 * 0.2048, epsilon: 0.5),
      reason: '0.1 shows 0.25 less a resisted 0.15 over 0.1',
    );
    await release(fingers);
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('a gate that refuses keeps the page under a drag, and a '
      'dimming color of its own dims the page below', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    const dim = Color(0x40FF0000);
    navigator.currentState!.push(
      GlassPageRoute<void>(
        source: link,
        zoomDismissShouldBegin: () => false,
        zoomDimmingColor: dim,
        builder: (context) => const ColoredBox(
          key: _page,
          color: Color(0xFFFFFFFF),
          child: Center(child: Text('Detail')),
        ),
      ),
    );
    await _frames(tester, 90);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == dim,
      ),
      findsOneWidget,
    );
    await tester.flingFrom(const Offset(200, 300), const Offset(0, 300), 1500);
    await _frames(tester, 90);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
  });

  testWidgets('a bar button zooms the page out of its place in the bar', (
    tester,
  ) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(
      WidgetsApp(
        navigatorKey: navigator,
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Notes'),
            trailing: [
              GlassBarItem(
                icon: const SizedBox.square(key: Key('new'), dimension: 22),
                semanticLabel: 'New',
                zoomSource: link,
                onPressed: () {},
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await _frames(tester, 2);
    final button = tester.getRect(find.byKey(const Key('new')));
    navigator.currentState!.push(_route(link));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = tester.getRect(find.byKey(_page));
    expect(early.width, lessThan(200));
    expect((early.center - button.center).distance, lessThan(60));
    await _frames(tester, 90);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    navigator.currentState!.pop();
    await _frames(tester, 12);
    final late = tester.getRect(find.byKey(_page));
    expect(late.width, lessThan(260));
    expect((late.center - button.center).distance, lessThan(120));
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
    expect(find.byKey(const Key('new')), findsOneWidget);
  });

  testWidgets('without an attached source the page slides', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, MotionSource()));
    navigator.currentState!.push(_route(MotionSource()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final rect = tester.getRect(find.byKey(_page));
    expect(rect.width, closeTo(402, 1e-9), reason: 'a slide keeps the width');
    expect(rect.left, greaterThan(0));
    await _frames(tester, 90);
  });
}
