import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(GlobalKey<NavigatorState> navigator, Widget home) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(padding: const EdgeInsets.only(top: 62, bottom: 34)),
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: child!,
    ),
  ),
  home: home,
);

Widget _page(String title, {List<GlassBarEntry> trailing = const []}) =>
    GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        title: Text(title),
        trailing: trailing,
      ),
      child: const ColoredBox(color: Color(0xFFFFFFFF)),
    );

GlassBarItem _icon(String name, {VoidCallback? onPressed}) => GlassBarItem(
  icon: SizedBox(key: Key(name), width: 22, height: 22),
  semanticLabel: name,
  onPressed: onPressed ?? () {},
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

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('pages share one bar: its capsules stay while the page '
      'slides, and the pushed page gets a back button named after the page '
      'below', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(navigator, _page('Home', trailing: [_icon('plus')])),
    );
    await tester.pump();
    expect(find.byType(GlassBarView), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('plus'))).dx, 364);

    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (_) => _page('Next', trailing: [_icon('share')]),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    expect(find.byType(GlassBarView), findsOneWidget);
    expect(
      tester.getCenter(find.text('Next')).dx,
      greaterThan(201),
      reason: 'the page is still sliding in',
    );
    await _settle(tester);
    expect(find.byType(GlassBarView), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('share'))).dx, 364);
    expect(find.byKey(const Key('plus')), findsNothing);
    final back = find.bySemanticsLabel('Home');
    expect(back, findsOneWidget);
    expect(tester.getRect(back).left, closeTo(16, 0.01));

    await tester.tap(back);
    await _settle(tester);
    expect(find.text('Next'), findsNothing);
    expect(tester.getCenter(find.byKey(const Key('plus'))).dx, 364);
    expect(
      find.bySemanticsLabel('Home'),
      findsOneWidget,
      reason: 'the title alone: the back button left',
    );
  });

  testWidgets('a dialog pushed over a page covers its bar', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        navigator,
        _page('Home', trailing: [_icon('plus', onPressed: () => taps++)]),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('plus')));
    expect(taps, 1);
    unawaited(
      navigator.currentState!.push(
        RawDialogRoute<void>(
          pageBuilder: (context, _, _) => const SizedBox.expand(
            child: ColoredBox(color: Color(0x80000000)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byKey(const Key('plus'))));
    expect(taps, 1);
  });

  testWidgets('an item whose label changes leaves and the new one arrives in '
      'the same capsule', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final editing = ValueNotifier(false);
    addTearDown(editing.dispose);
    await tester.pumpWidget(
      _app(
        navigator,
        ValueListenableBuilder(
          valueListenable: editing,
          builder: (context, value, _) => _page(
            'Notes',
            trailing: [
              GlassBarItem(
                label: Text(value ? 'Done' : 'Edit'),
                onPressed: () => editing.value = !editing.value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump(_frame);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget, reason: 'it is leaving');
    await _settle(tester);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a navigation bar outside a glass page route draws its own '
      'capsules', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(402, 874),
          padding: EdgeInsets.only(top: 62),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GlassTheme(
            data: const GlassThemeData(renderer: GlassRenderer.flat()),
            child: _page('Alone', trailing: [_icon('plus')]),
          ),
        ),
      ),
    );
    await tester.pump();
    final plus = tester.getCenter(find.byKey(const Key('plus')));
    expect(plus.dx, 364);
    expect(plus.dy, 62 + 22);
  });

  testWidgets('a swipe leans the capsules the page below has and pops on a '
      'fling', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(navigator, _page('Home', trailing: [_icon('plus')])),
    );
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (_) => _page('Next', trailing: [_icon('a'), _icon('b')]),
        ),
      ),
    );
    await _settle(tester);
    final rest = tester.getCenter(find.byKey(const Key('a')));
    final gesture = await tester.createGesture();
    await gesture.down(const Offset(10, 400));
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
      await gesture.moveBy(const Offset(15, 0));
    }
    await tester.pump(_frame);
    expect(
      tester.getCenter(find.byKey(const Key('a'))).dx,
      isNot(rest.dx),
      reason: "the trailing capsule leans toward Home's",
    );
    await gesture.up();
    await _settle(tester);
    expect(find.text('Next'), findsNothing);
    expect(tester.getCenter(find.byKey(const Key('plus'))).dx, 364);
  });
}
