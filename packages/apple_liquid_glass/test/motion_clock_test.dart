import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

import 'support/motion_clock.dart';

// The conformance check `motion-clock` drives every public widget at phone
// size; these are the motions it does not reach there.

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Widget _app(
  ManualMotionClock clock,
  Widget home, {
  GlassThemeData data = const GlassThemeData(),
}) => MotionClockScope(
  clock: clock,
  child: WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(settings, builder) =>
        GlassPageRoute<T>(builder: builder, settings: settings),
    builder: (context, child) => GlassScope(
      renderer: const FlatGlassRenderer(),
      data: data,
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _tap(
  WidgetTester tester,
  ManualMotionClock clock,
  Offset at,
) async {
  final gesture = await tester.startGesture(at);
  await runClock(tester, clock, 0.2);
  await gesture.up();
  await runClock(tester, clock, 1);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets("a popover on a wide screen fades its glass on its place's "
      'clock', (tester) async {
    _screen(tester, const Size(1024, 1366));
    final clock = ManualMotionClock();
    await tester.pumpWidget(
      _app(
        clock,
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 120),
            child: Builder(
              builder: (context) => GlassButton(
                onPressed: () => unawaited(
                  showGlassPopover<void>(
                    context,
                    anchor: context,
                    builder: (context) =>
                        const SizedBox(width: 300, height: 200),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await runClock(tester, clock, 0.5);
    await _tap(tester, clock, tester.getCenter(find.text('Open')));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlassSurface &&
            widget.role == GlassRole.panel &&
            widget.frame != null,
      ),
      findsOneWidget,
    );
    await expectOnClock(tester, clock, 'presenting');
  });

  testWidgets("a tab bar's accessory travels on its place's clock as the "
      'bar minimizes', (tester) async {
    _screen(tester, const Size(402, 874));
    final clock = ManualMotionClock();
    await tester.pumpWidget(
      _app(
        clock,
        GlassTabScaffold(
          tabBar: GlassTabBar(
            minimizeBehavior: GlassTabBarMinimizeBehavior.onScrollDown,
            bottomAccessory: const SizedBox.expand(key: Key('accessory')),
            destinations: const [
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('One'),
              ),
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('Two'),
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
          tabBuilder: (context, i) => GlassPageScaffold(
            child: GlassContentScroll(
              child: ListView(
                children: [
                  for (var r = 0; r < 60; r++) const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await runClock(tester, clock, 0.5);
    final expanded = tester.getRect(find.byKey(const Key('accessory')));
    final gesture = await tester.startGesture(const Offset(201, 400));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await runClock(tester, clock, 1 / 60);
    }
    await expectOnClock(tester, clock, 'minimizing');
    await runClock(tester, clock, 0.2);
    await gesture.up();
    await runClock(tester, clock, 1);
    expect(
      tester.getRect(find.byKey(const Key('accessory'))),
      isNot(expanded),
    );
    await expectOnClock(tester, clock, 'minimized');
  });

  testWidgets("a navigation bar's search field scales its text with its "
      "glass on its place's clock", (tester) async {
    _screen(tester, const Size(402, 874));
    final clock = ManualMotionClock();
    final search = TextEditingController();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(
        clock,
        GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            largeTitle: const Text('Notes'),
            searchField: GlassSearchField(
              key: const Key('field'),
              controller: search,
            ),
          ),
          child: GlassContentScroll(
            child: ListView(
              children: [
                for (var i = 0; i < 40; i++) const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
    await runClock(tester, clock, 0.5);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('field'))),
    );
    await runClock(tester, clock, 0.3);
    await expectOnClock(tester, clock, 'under a finger');
    await gesture.up();
    await runClock(tester, clock, 1);
    await expectOnClock(tester, clock, 'searching');
  });

  testWidgets("a theme change fades on its place's clock", (tester) async {
    _screen(tester, const Size(402, 874));
    final clock = ManualMotionClock();
    final seen = <Brightness?>[];
    final home = Builder(
      builder: (context) {
        seen.add(GlassTheme.of(context).brightness);
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(_app(clock, home));
    await runClock(tester, clock, 0.5);
    await tester.pumpWidget(
      _app(
        clock,
        home,
        data: const GlassThemeData(brightness: Brightness.dark),
      ),
    );
    await runClock(tester, clock, 2);
    await expectOnClock(tester, clock, 'after the change');
    expect(seen.last, Brightness.dark);
  });
}
