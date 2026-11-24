import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
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
  bool showsSidebarButton = true,
  bool? collapsed,
  GlassSplitViewColumn topColumnWhenCollapsed = GlassSplitViewColumn.secondary,
  Widget? primary,
  Widget? secondary,
}) => GlassSplitView(
  collapsed: collapsed,
  topColumnWhenCollapsed: topColumnWhenCollapsed,
  controller: controller,
  preferredPrimaryWidth: preferredPrimaryWidth,
  preferredPrimaryWidthFraction: preferredPrimaryWidthFraction,
  minimumPrimaryWidth: minimumPrimaryWidth,
  maximumPrimaryWidth: maximumPrimaryWidth,
  minimumSecondaryWidth: minimumSecondaryWidth,
  resizable: resizable,
  showsSidebarButton: showsSidebarButton,
  primary: primary ?? _page('Primary'),
  secondary: secondary ?? _page('Secondary'),
);

final _sidebarIcon = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == 'GlassSidebarGlyph',
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
      _app(
        _split(
          minimumPrimaryWidth: 280,
          minimumSecondaryWidth: 280,
          collapsed: false,
        ),
      ),
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

  testWidgets('a touch at the top of a column goes to the page at rest on '
      'top of its navigator, slid or zoomed in, never to the page under it', (
    tester,
  ) async {
    _window(tester, width: 1280, height: 800);
    tester.view.padding = const FakeViewPadding(top: 28);
    final source = MotionSource();
    for (final zoom in [false, true]) {
      final navigator = GlobalKey<NavigatorState>();
      var under = 0;
      var top = 0;
      Widget page(String title, VoidCallback onTap, {Widget? child}) =>
          GlassPageScaffold(
            navigationBar: GlassNavigationBar(title: Text(title)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Center(child: child),
            ),
          );
      await tester.pumpWidget(
        _app(
          GlassSplitView(
            key: ValueKey(zoom),
            primary: _page('Primary'),
            secondary: Navigator(
              key: navigator,
              onGenerateRoute: (settings) => GlassPageRoute<void>(
                settings: settings,
                builder: (_) => page(
                  'Under',
                  () => under++,
                  child: GlassZoomSource(
                    source: source,
                    child: const SizedBox(width: 100, height: 60),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      unawaited(
        navigator.currentState!.push(
          GlassPageRoute<void>(
            source: zoom ? source : null,
            builder: (_) => page('Top', () => top++),
          ),
        ),
      );
      await _settle(tester);
      for (final y in [2.0, 10.0, 40.0, 100.0]) {
        await tester.tapAt(Offset(1000, y));
        await _settle(tester);
      }
      expect(under, 0, reason: zoom ? 'zoomed' : 'slid');
      expect(top, 2, reason: zoom ? 'zoomed' : 'slid');
    }
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

  testWidgets('a leading inset widens the primary column under it, and is '
      'the leading safe area of the column at the leading side', (
    tester,
  ) async {
    _window(tester, width: 1210, height: 834);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    Widget split({double? fraction}) => _app(
      GlassSplitView(
        controller: controller,
        leadingInset: 280,
        preferredPrimaryWidthFraction: fraction,
        primary: _page('Primary'),
        secondary: _page('Secondary'),
      ),
    );
    MediaQueryData media(String title) =>
        MediaQuery.of(tester.element(find.byKey(Key(title))));
    await tester.pumpWidget(split());
    await tester.pump();
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 600, 834));
    expect(
      _column(tester, 'Secondary'),
      const Rect.fromLTWH(600, 0, 610, 834),
    );
    expect(media('Primary').padding.left, 280);
    expect(media('Secondary').padding.left, 0);
    expect(
      tester.getCenter(find.text('Primary')).dx,
      moreOrLessEquals((280 + 600) / 2, epsilon: 0.5),
      reason: 'the title centers on the part the inset leaves',
    );
    expect(tester.getRect(_sidebarIcon).right, 600 - 16 - 11);

    await tester.pumpWidget(split(fraction: 0.5));
    await _settle(tester);
    expect(
      _column(tester, 'Primary').width,
      280 + (1210 - 280) / 2,
      reason: 'the width rule takes the view beside the inset',
    );

    await tester.pumpWidget(split());
    controller.hide(GlassSplitViewColumn.primary);
    await _settle(tester);
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 1210, 834));
    expect(media('Secondary').padding.left, 280);
    expect(tester.getRect(_sidebarIcon).left, 280 + 16 + 11);
    expect(
      tester.getCenter(find.text('Secondary')).dx,
      moreOrLessEquals((280 + 1210) / 2, epsilon: 0.5),
    );
  });

  for (final direction in TextDirection.values) {
    testWidgets('a leading inset over columns that are navigators, '
        '${direction.name}', (tester) async {
      _window(tester, width: 1210, height: 834);
      final controller = GlassSplitViewController();
      addTearDown(controller.dispose);
      Widget stack(String title) => Navigator(
        onGenerateRoute: (settings) => GlassPageRoute<void>(
          settings: settings,
          builder: (context) => _page(title),
        ),
      );
      await tester.pumpWidget(
        _app(
          GlassSplitView(
            controller: controller,
            leadingInset: 280,
            primary: stack('Primary'),
            secondary: stack('Secondary'),
          ),
          direction: direction,
        ),
      );
      await tester.pump();
      final ltr = direction == TextDirection.ltr;
      double x(double fromLeading) => ltr ? fromLeading : 1210 - fromLeading;
      expect(
        _column(tester, 'Primary'),
        Rect.fromLTWH(ltr ? 0 : 610, 0, 600, 834),
      );
      expect(
        tester.getCenter(find.text('Primary')).dx,
        moreOrLessEquals(x((280 + 600) / 2), epsilon: 0.5),
      );
      expect(
        ltr
            ? tester.getRect(_sidebarIcon).right
            : tester.getRect(_sidebarIcon).left,
        x(600 - 16 - 11),
      );

      controller.hide(GlassSplitViewColumn.primary);
      await _settle(tester);
      expect(
        tester.getCenter(find.text('Secondary')).dx,
        moreOrLessEquals(x((280 + 1210) / 2), epsilon: 0.5),
      );
      expect(
        ltr
            ? tester.getRect(_sidebarIcon).left
            : tester.getRect(_sidebarIcon).right,
        x(280 + 16 + 11),
      );
    });
  }

  testWidgets('a large title starts past the leading inset', (tester) async {
    _window(tester, width: 1210, height: 834);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        GlassSplitView(
          controller: controller,
          leadingInset: 280,
          primary: _page('Primary'),
          secondary: GlassPageScaffold(
            navigationBar: const GlassNavigationBar(largeTitle: Text('Large')),
            child: GlassContentScroll(
              child: ListView(children: const [SizedBox(height: 2000)]),
            ),
          ),
        ),
      ),
    );
    controller.hide(GlassSplitViewColumn.primary);
    await _settle(tester);
    final titles = [
      for (final element in find.text('Large').evaluate())
        tester.getRect(
          find.byElementPredicate((each) => identical(each, element)),
        ),
    ]..sort((a, b) => b.height.compareTo(a.height));
    expect(titles.first.left, moreOrLessEquals(280 + 16, epsilon: 0.5));
  });

  testWidgets('a navigator in the primary column leaves the secondary '
      'column to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    _window(tester, width: 1210, height: 834);
    await tester.pumpWidget(
      _app(
        GlassSplitView(
          primary: Navigator(
            onGenerateRoute: (settings) => GlassPageRoute<void>(
              settings: settings,
              builder: (context) => _page('Primary'),
            ),
          ),
          secondary: _page('Secondary'),
        ),
      ),
    );
    await tester.pump();
    expect(find.semantics.byLabel('Primary'), findsOneWidget);
    expect(find.semantics.byLabel('Secondary'), findsOneWidget);
    semantics.dispose();
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
    await back.moveBy(const Offset(-200, 0));
    await tester.pump(_frame);
    await back.moveBy(const Offset(-40, 0));
    await tester.pump(_frame);
    expect(_column(tester, 'Primary').width, 200);
    await back.up();
    await _settle(tester);
    expect(controller.primaryWidth, 200);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
  });

  testWidgets('a mouse dragging the divider past the minimum hides the '
      'primary column, and in the same drag brings it back at the width it '
      'had', (tester) async {
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
    final drag = await tester.startGesture(
      const Offset(320, 250),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(-120, 0));
    await tester.pump(_frame);
    await drag.moveBy(const Offset(-45, 0));
    await tester.pump(_frame);
    expect(_column(tester, 'Primary').width, 200);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    await drag.moveBy(const Offset(-10, 0));
    await tester.pump(_frame);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    await _settle(tester);
    expect(_column(tester, 'Secondary').left, 0);

    await drag.moveBy(const Offset(50, 0));
    await tester.pump(_frame);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    await _settle(tester);
    expect(_column(tester, 'Primary').width, 320);
    await drag.moveBy(const Offset(30, 0));
    await tester.pump(_frame);
    expect(_column(tester, 'Primary').width, 350);
    await drag.moveBy(const Offset(-30, 0));
    await drag.up();
    await _settle(tester);
    expect(controller.primaryWidth, isNull, reason: 'back where it was');

    final away = await tester.startGesture(const Offset(320, 250));
    await away.moveBy(const Offset(-300, 0));
    await tester.pump(_frame);
    await away.up();
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    expect(controller.primaryWidth, isNull, reason: 'not the stuck minimum');
    controller.show(GlassSplitViewColumn.primary);
    await _settle(tester);
    expect(_column(tester, 'Primary').width, 320);
  });

  testWidgets('without the sidebar button the divider stops at the minimum, '
      'and a double tap forgets the width a hand gave', (tester) async {
    _window(tester);
    final controller = GlassSplitViewController(primaryWidth: 400);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          resizable: true,
          minimumPrimaryWidth: 200,
          showsSidebarButton: false,
        ),
      ),
    );
    final drag = await tester.startGesture(const Offset(400, 250));
    await drag.moveBy(const Offset(-390, 0));
    await tester.pump(_frame);
    await drag.up();
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(controller.primaryWidth, 200);

    await tester.tapAt(const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(200, 250));
    await _settle(tester);
    expect(controller.primaryWidth, isNull);
    expect(_column(tester, 'Primary').width, 320);
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
      'the view in whole points, and a screen reader reads it as a slider', (
    tester,
  ) async {
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
    expect(
      controller.primaryWidth,
      closeTo(320 + (867 / 20).roundToDouble(), 0.001),
    );
    tester.semantics.performAction(divider, SemanticsAction.decrease);
    await _settle(tester);
    expect(controller.primaryWidth, closeTo(320, 0.001));
    semantics.dispose();
  });

  testWidgets('a step down from the minimum hides the primary column', (
    tester,
  ) async {
    _window(tester);
    final controller = GlassSplitViewController(primaryWidth: 200);
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    expect(controller.primaryWidth, 200);
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

  testWidgets('narrower than collapseBelow the columns collapse into one '
      'stack, the secondary on top with a back button to the primary', (
    tester,
  ) async {
    _window(tester, width: 402, height: 874);
    final semantics = tester.ensureSemantics();
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    final heard = <bool>[];
    controller.addListener(() => heard.add(controller.isCollapsed));
    await tester.pumpWidget(_app(_split(controller: controller)));
    await tester.pump();
    expect(controller.isCollapsed, isTrue);
    expect(heard, [true]);
    expect(controller.isShowing(GlassSplitViewColumn.secondary), isTrue);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 402, 874));
    expect(find.byKey(const Key('Primary')), findsNothing);
    expect(_sidebarIcon, findsNothing);
    await _settle(tester);
    final back = find.bySemanticsLabel('Primary');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 402, 874));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color.toARGB32() == 0xFFEAEFF2,
      ),
      findsNothing,
    );
    controller.show(GlassSplitViewColumn.secondary);
    await _settle(tester);
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 402, 874));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.secondary), isFalse);
    semantics.dispose();
  });

  testWidgets('the columns keep their state and their bars across a '
      'collapse and an expansion', (tester) async {
    _window(tester);
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          secondary: const GlassPageScaffold(
            navigationBar: GlassNavigationBar(title: Text('Secondary')),
            child: _Counter(key: Key('Secondary')),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('Secondary')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    _window(tester, width: 402, height: 874);
    await _settle(tester);
    expect(controller.isCollapsed, isTrue);
    expect(find.text('1'), findsOneWidget);
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 402, 874));
    await tester.tap(find.byKey(const Key('Secondary')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    _window(tester);
    await _settle(tester);
    expect(controller.isCollapsed, isFalse);
    expect(find.text('2'), findsOneWidget);
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 320, 500));
    expect(tester.getRect(_sidebarIcon).right, 320 - 16 - 11);
    expect(tester.getCenter(find.text('Secondary')).dx, (320 + 867) / 2);
  });

  testWidgets('a primary column that scrolls goes under the secondary as '
      'the columns collapse, with semantics on', (tester) async {
    final semantics = tester.ensureSemantics();
    _window(tester);
    await tester.pumpWidget(
      _app(
        _split(
          primary: GlassPageScaffold(
            navigationBar: const GlassNavigationBar(title: Text('Primary')),
            child: ListView(
              children: [for (var i = 0; i < 3; i++) Text('row $i')],
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    for (final width in [402.0, 867.0, 402.0]) {
      _window(tester, width: width, height: width < 500 ? 874 : 500);
      await _settle(tester);
      expect(tester.takeException(), isNull);
    }
    expect(_column(tester, 'Secondary'), const Rect.fromLTWH(0, 0, 402, 874));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('row 0'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('collapsed, a navigator in the secondary column gets a back '
      'button to the primary on its first page', (tester) async {
    _window(tester, width: 402, height: 874);
    final semantics = tester.ensureSemantics();
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _split(
          controller: controller,
          secondary: Navigator(
            onGenerateRoute: (settings) =>
                GlassPageRoute<void>(builder: (_) => _page('Secondary')),
          ),
        ),
      ),
    );
    await tester.pump();
    final back = find.bySemanticsLabel('Back');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await _settle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 402, 874));
    semantics.dispose();
  });

  testWidgets('collapsed false keeps the columns side by side, and '
      'topColumnWhenCollapsed puts the primary on top', (tester) async {
    _window(tester, width: 402, height: 874);
    await tester.pumpWidget(_app(_split(collapsed: false)));
    expect(_column(tester, 'Primary').left, 0);
    expect(_column(tester, 'Secondary').right, 402);
    await tester.pumpWidget(
      _app(
        _split(
          collapsed: true,
          topColumnWhenCollapsed: GlassSplitViewColumn.primary,
        ),
      ),
    );
    await _settle(tester);
    expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 402, 874));
    expect(find.byKey(const Key('Secondary')), findsNothing);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _count++),
    child: Center(child: Text('$_count')),
  );
}
