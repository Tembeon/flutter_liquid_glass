import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(Widget home, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      ),
      home: home,
    );

Widget _page(String title, {List<GlassBarEntry> leading = const []}) =>
    GlassPageScaffold(
      navigationBar: GlassNavigationBar(title: Text(title), leading: leading),
      child: SizedBox.expand(key: Key(title)),
    );

Widget _split({
  GlassSplitViewController? controller,
  double? preferredPrimaryWidth,
  double? preferredPrimaryWidthFraction,
  double minimumPrimaryWidth = 0,
  double maximumPrimaryWidth = double.infinity,
  double minimumSecondaryWidth = GlassSplitView.defaultMinimumSecondaryWidth,
  bool resizable = false,
  Widget? secondary,
}) => GlassSplitView(
  controller: controller,
  preferredPrimaryWidth: preferredPrimaryWidth,
  preferredPrimaryWidthFraction: preferredPrimaryWidthFraction,
  minimumPrimaryWidth: minimumPrimaryWidth,
  maximumPrimaryWidth: maximumPrimaryWidth,
  minimumSecondaryWidth: minimumSecondaryWidth,
  resizable: resizable,
  primary: _page('Primary'),
  secondary: secondary ?? _page('Secondary'),
);

final _sidebarIcon = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == '_SidebarIcon',
);

Rect _column(WidgetTester tester, String title) =>
    tester.getRect(find.byKey(Key(title)));

void _window(WidgetTester tester, {double width = 867, double height = 500}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the primary column stands 320 wide beside the secondary, '
      'each column with its own bar, the sidebar button at the trailing end '
      'of the primary bar', (tester) async {
    _window(tester);
    await tester.pumpWidget(_app(_split()));
    await tester.pump();
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 320, 500));
    expect(
      _column(tester, 'Secondary'),
      const Rect.fromLTWH(320, 0, 547, 500),
    );
    expect(tester.getCenter(find.text('Primary')).dx, 160);
    expect(tester.getCenter(find.text('Secondary')).dx, (320 + 867) / 2);
    expect(_sidebarIcon, findsOneWidget);
    expect(tester.getRect(_sidebarIcon).right, 320 - 16 - 11);
  });

  testWidgets('the primary column keeps the secondary 448 wide, and takes '
      'its preferred width, fraction and maximum', (tester) async {
    for (final (width, fraction, preferred, maximum, expected) in [
      (867.0, 0.25, null, double.infinity, 216.75),
      (867.0, 0.5, null, double.infinity, 419.0),
      (834.0, 0.5, null, double.infinity, 386.0),
      (834.0, 0.5, 250.0, double.infinity, 250.0),
      (867.0, null, 400.0, double.infinity, 400.0),
      (867.0, null, null, 300.0, 300.0),
    ]) {
      _window(tester, width: width);
      await tester.pumpWidget(
        _app(
          _split(
            preferredPrimaryWidthFraction: fraction,
            preferredPrimaryWidth: preferred,
            maximumPrimaryWidth: maximum,
          ),
        ),
      );
      expect(_column(tester, 'Primary').width, expected);
      expect(_column(tester, 'Secondary').left, expected);
    }
  });

  testWidgets('a view too narrow for both minimums shares its width as the '
      'minimums do', (tester) async {
    _window(tester, width: 500);
    await tester.pumpWidget(
      _app(_split(minimumPrimaryWidth: 280, minimumSecondaryWidth: 280)),
    );
    expect(_column(tester, 'Primary').width, 250);
    expect(_column(tester, 'Secondary').width, 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the primary column takes the sidebar tint', (tester) async {
    _window(tester);
    await tester.pumpWidget(_app(_split()));
    expect(
      find.descendant(
        of: find.byKey(const Key('Primary')).first,
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    final tinted = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color.toARGB32() == 0xFFEAEFF2,
    );
    expect(tinted, findsOneWidget);
    expect(tester.getRect(tinted).width, 320);
  });

  testWidgets('the sidebar button hides the primary column, then stands at '
      'the leading end of the secondary bar and shows it again', (
    tester,
  ) async {
    _window(tester);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_split(controller: controller)));
    await tester.tap(_sidebarIcon);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    await tester.pump();
    await tester.pump(_frame * 4);
    final sliding = _column(tester, 'Secondary').left;
    expect(sliding, inExclusiveRange(0, 320));
    await _settle(tester);
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 867, 500));
    expect(find.text('Primary').hitTestable(), findsNothing);
    expect(tester.getCenter(find.text('Secondary')).dx, 867 / 2);
    expect(_sidebarIcon, findsOneWidget);
    expect(tester.getRect(_sidebarIcon).left, 16 + 11);
    await tester.tap(_sidebarIcon);
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 320, 500));
    expect(tester.getRect(_sidebarIcon).right, 320 - 16 - 11);
  });

  testWidgets('the sidebar button leaves the leading items of the secondary '
      'bar beside it, and showsSidebarButton false leaves it out', (
    tester,
  ) async {
    _window(tester);
    final controller = GlassSplitViewController(showsPrimary: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          secondary: _page(
            'Secondary',
            leading: [
              GlassBarItem(
                icon: const SizedBox(key: Key('edit'), width: 22, height: 22),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getRect(_sidebarIcon).left, 16 + 11);
    expect(
      tester.getRect(find.byKey(const Key('edit'))).left,
      greaterThan(tester.getRect(_sidebarIcon).right + 11),
    );
    await tester.pumpWidget(
      _app(
        GlassSplitView(
          controller: controller,
          showsSidebarButton: false,
          primary: _page('Primary'),
          secondary: _page('Secondary'),
        ),
      ),
    );
    await _settle(tester);
    expect(_sidebarIcon, findsNothing);
  });

  testWidgets('each column gets the safe area of the sides it touches', (
    tester,
  ) async {
    _window(tester);
    tester.view.padding = const FakeViewPadding(left: 20, right: 30, top: 24);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_split(controller: controller)));
    MediaQueryData media(String title) =>
        MediaQuery.of(tester.element(find.byKey(Key(title))));
    expect(media('Primary').size, const Size(320, 500));
    expect(media('Primary').padding.left, 20);
    expect(media('Primary').padding.right, 0);
    expect(media('Secondary').size, const Size(547, 500));
    expect(media('Secondary').padding.left, 0);
    expect(media('Secondary').padding.right, 30);
    controller.hide(GlassSplitViewColumn.primary);
    await _settle(tester);
    expect(media('Secondary').size, const Size(867, 500));
    expect(media('Secondary').padding.left, 20);
  });

  testWidgets('right to left, the primary column stands at the right', (
    tester,
  ) async {
    _window(tester);
    await tester.pumpWidget(_app(_split(), direction: TextDirection.rtl));
    expect(
      _column(tester, 'Primary'),
      const Rect.fromLTWH(867 - 320, 0, 320, 500),
    );
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 547, 500));
    expect(tester.getRect(_sidebarIcon).left, 867 - 320 + 16 + 11);
  });

  testWidgets('a drag of the divider resizes the columns, stops at the '
      'limits, and writes where it let go', (tester) async {
    _window(tester);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          resizable: true,
          minimumPrimaryWidth: 200,
        ),
      ),
    );
    final drag = await tester.startGesture(const Offset(320, 250));
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(10, 0));
      await tester.pump(_frame);
    }
    expect(_column(tester, 'Primary').width, 379);
    expect(_column(tester, 'Secondary').left, 379);
    expect(controller.primaryWidth, isNull);
    await drag.moveBy(const Offset(400, 0));
    await tester.pump(_frame);
    expect(_column(tester, 'Primary').width, 867 - 448);
    await drag.up();
    await _settle(tester);
    expect(controller.primaryWidth, 867 - 448);
    expect(_column(tester, 'Primary').width, 867 - 448);

    final back = await tester.startGesture(const Offset(867 - 448, 250));
    await back.moveBy(const Offset(-300, 0));
    await tester.pump(_frame);
    await back.moveBy(const Offset(-300, 0));
    await tester.pump(_frame);
    await back.up();
    await _settle(tester);
    expect(controller.primaryWidth, 200);
  });

  testWidgets('a reset returns the primary column to its preferred width on '
      'a spring', (tester) async {
    _window(tester);
    final controller = GlassSplitViewController(primaryWidth: 400);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_split(controller: controller)));
    expect(_column(tester, 'Primary').width, 400);
    controller.resetPrimaryWidth();
    expect(controller.primaryWidth, isNull);
    await tester.pump();
    await tester.pump(_frame * 4);
    expect(_column(tester, 'Primary').width, inExclusiveRange(320, 400));
    await _settle(tester);
    expect(_column(tester, 'Primary').width, 320);
  });

  testWidgets('a touch beside the divider reaches the secondary column', (
    tester,
  ) async {
    _window(tester);
    final taps = <String>[];
    await tester.pumpWidget(
      _app(
        GlassSplitView(
          resizable: true,
          primary: const SizedBox.expand(),
          secondary: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps.add('secondary'),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(322, 250));
    await tester.tapAt(const Offset(320 + GlassSplitView.dividerWidth, 250));
    expect(taps, ['secondary']);
  });

  testWidgets('the divider is a Tab stop whose arrows step a twentieth of '
      'the view, and a screen reader reads it as a slider', (tester) async {
    _window(tester);
    final semantics = tester.ensureSemantics();
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_split(controller: controller, resizable: true)),
    );
    final divider = find.semantics.byPredicate(
      (node) => node.label == 'Column divider' && node.flagsCollection.isSlider,
    );
    expect(divider, findsOne);
    expect(divider.evaluate().single.value, '37%');
    final region = find.byWidgetPredicate(
      (widget) =>
          widget is InputRegion &&
          widget.mouseCursor == SystemMouseCursors.resizeColumn,
    );
    Focus.of(
      tester.element(
        find.descendant(of: region, matching: find.byType(SizedBox)),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(controller.primaryWidth, closeTo(320 + 867 / 20, 0.001));
    tester.semantics.performAction(divider, SemanticsAction.decrease);
    await _settle(tester);
    expect(controller.primaryWidth, closeTo(320, 0.001));
    semantics.dispose();
  });

  testWidgets('a page pushed in the secondary column slides across that '
      'column and keeps its back button; the sidebar button stays with the '
      'first page', (tester) async {
    _window(tester);
    final navigator = GlobalKey<NavigatorState>();
    final controller = GlassSplitViewController(showsPrimary: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          secondary: Navigator(
            key: navigator,
            onGenerateRoute: (settings) =>
                GlassPageRoute<void>(builder: (_) => _page('Secondary')),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.show(GlassSplitViewColumn.primary);
    await _settle(tester);
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Detail')),
      ),
    );
    await tester.pump();
    await tester.pump(_frame);
    expect(_column(tester, 'Detail').left, lessThanOrEqualTo(867));
    expect(_column(tester, 'Detail').left, greaterThan(320));
    await _settle(tester);
    expect(_column(tester, 'Detail'), const Rect.fromLTWH(320, 0, 547, 500));
    expect(find.bySemanticsLabel('Secondary'), findsWidgets);
    controller.hide(GlassSplitViewColumn.primary);
    await _settle(tester);
    expect(_sidebarIcon, findsNothing);
    navigator.currentState!.pop();
    await _settle(tester);
    expect(_sidebarIcon, findsOneWidget);
  });

  testWidgets('a split view in a glass page gives its columns bars apart '
      "from the page's", (tester) async {
    _window(tester);
    await tester.pumpWidget(
      _app(
        GlassPageScaffold(
          navigationBar: const GlassNavigationBar(title: Text('Outer')),
          child: _split(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Outer'), findsOneWidget);
    expect(tester.getRect(_sidebarIcon).right, 320 - 16 - 11);
  });
}
