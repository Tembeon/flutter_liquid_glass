import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The tab sidebar passport's iPad: beside the content in landscape, over it
// in portrait.
const _landscape = Size(1210, 834);
const _portrait = Size(1032, 1376);
const _frame = Duration(milliseconds: 16);

final _padding = <String, EdgeInsets>{};
final _builds = <String, int>{};

// A page that counts its builds and records the safe area the tab gives
// it, without depending on it itself.
class _Page extends StatelessWidget {
  const _Page(this.name, {this.leading = false});

  final String name;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    _builds[name] = (_builds[name] ?? 0) + 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            leading: [
              if (leading)
                GlassBarButton(
                  icon: SizedBox.square(
                    key: ValueKey('$name leading'),
                    dimension: 20,
                  ),
                  onPressed: () {},
                ),
            ],
            title: Text('$name bar'),
          ),
          child: const SizedBox.expand(),
        ),
        _Probe(name),
      ],
    );
  }
}

class _Probe extends StatelessWidget {
  const _Probe(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    _padding[name] = MediaQuery.paddingOf(context);
    return const SizedBox.expand();
  }
}

Future<void> _pump(
  WidgetTester tester,
  GlassTabController controller,
  Size size, {
  TextDirection direction = TextDirection.ltr,
  bool resizable = true,
  bool list = false,
  bool showsListButton = true,
  GlassTabLayoutPolicy layout = const GlassTabLayoutPolicy.automatic(),
  GlassTabSidebarStyle? sidebarStyle,
  GlassWindowControls windowControls = GlassWindowControls.none,
  bool leading = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 64, bottom: 40);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: Directionality(
        textDirection: direction,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          child: GlassEnvironmentOverride(
            windowControls: windowControls,
            child: GlassTabScaffold(
              controller: controller,
              resizable: resizable,
              layout: layout,
              sidebarStyle: sidebarStyle,
              tabs: [
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('One'),
                  badge: const GlassBadge.count(3),
                  builder: (context) => _Page('One', leading: leading),
                  detailPlaceholder: list
                      ? (context) => const Text('Nothing open')
                      : null,
                  showsListButton: showsListButton,
                ),
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('Two'),
                  builder: (context) => const _Page('Two'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

Finder _private(String type) =>
    find.byWidgetPredicate((widget) => '${widget.runtimeType}' == type);

Finder get _bar => _private('_TopBar');
Finder get _sidebar => find.byType(GlassTabSidebar);

Finder get _divider => find.byWidgetPredicate(
  (widget) =>
      widget is InputRegion &&
      widget.mouseCursor == SystemMouseCursors.resizeColumn,
);

GlassFrame _glassFrame(WidgetTester tester) => tester
    .widget<GlassSurface>(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlassSurface &&
            widget.role == GlassRole.bar &&
            widget.frame != null,
      ),
    )
    .frame!
    .value;

Rect _glass(WidgetTester tester) => _glassFrame(tester).rect!;

// Where the side's edge stands: the glass's trailing edge, the divider's
// center and where the content's safe area starts, which agree.
double _edge(WidgetTester tester, {String page = 'One'}) {
  final glass = _glass(tester).right;
  expect(tester.getCenter(_divider).dx, moreOrLessEquals(glass));
  final probe = find.byWidgetPredicate(
    (widget) => widget is _Probe && widget.name == page,
  );
  expect(
    tester.getTopLeft(probe).dx + _padding[page]!.left,
    moreOrLessEquals(glass),
  );
  return glass;
}

Future<TestGesture> _grab(
  WidgetTester tester, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_divider),
    kind: kind,
  );
  addTearDown(gesture.removePointer);
  return gesture;
}

// Moves the hand [by] past the drag's 1 point slop the first time.
Future<void> _move(WidgetTester tester, TestGesture hand, double by) async {
  await hand.moveBy(Offset(by, 0));
  await tester.pump();
}

// The center of the divider whose center is at [x].
Offset _dividerAt(WidgetTester tester, double x) {
  final count = _divider.evaluate().length;
  for (var i = 0; i < count; i++) {
    final at = tester.getCenter(_divider.at(i));
    if ((at.dx - x).abs() < 1) return at;
  }
  fail('no divider at $x');
}

void _focusDivider(WidgetTester tester) => Focus.of(
  tester.element(
    find.descendant(of: _divider, matching: find.byType(SizedBox)),
  ),
).requestFocus();

void main() {
  setUp(() {
    _padding.clear();
    _builds.clear();
  });

  testWidgets('a mouse on the edge of the sidebar beside the content '
      'resizes it live, its content following without a build of the page, '
      'and the width is written when the hand lets go', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    expect(_edge(tester), 280);
    final builds = _builds['One'];

    final hand = await _grab(tester);
    await _move(tester, hand, 31);
    expect(_edge(tester), 310);
    await _move(tester, hand, 30);
    expect(_edge(tester), 340, reason: 'one frame after the hand');
    expect(controller.sidebarWidth, isNull, reason: 'written at release');
    expect(_builds['One'], builds, reason: 'the page does not rebuild');
    expect(tester.getSize(_sidebar).width, 340);

    await _move(tester, hand, 200);
    expect(_edge(tester), 400, reason: 'the widest');
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarWidth, 400);
    expect(_edge(tester), 400);
  });

  testWidgets('a drag past the minimum folds the sidebar into the rail, past '
      'the rail hides it, and the same drag brings both back at the width '
      'the sidebar had', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    final hand = await _grab(tester);
    await _move(tester, hand, -81);
    expect(_edge(tester), 200);
    await _move(tester, hand, -49);
    expect(_edge(tester), 200, reason: 'stuck short of the fold');
    expect(controller.sidebarRail, isFalse);

    await _move(tester, hand, -1);
    expect(controller.sidebarRail, isTrue);
    expect(controller.sidebarShown, isNot(isFalse));
    await _settle(tester);
    expect(_edge(tester), 72);
    expect(tester.getSize(_sidebar).width, 72);

    await _move(tester, hand, -50);
    expect(controller.sidebarShown, isFalse, reason: 'past the rail: hidden');
    await _settle(tester);
    expect(_bar, findsOneWidget);
    expect(_padding['One']!.left, 0);

    await _move(tester, hand, 50);
    expect(controller.sidebarShown, isTrue);
    expect(controller.sidebarRail, isTrue);
    await _settle(tester);
    expect(_edge(tester), 72);

    await _move(tester, hand, 50);
    expect(controller.sidebarRail, isFalse);
    await _settle(tester);
    expect(_edge(tester), 280, reason: 'the width it had');
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarWidth, isNull);
  });

  testWidgets('the titles fade with the side width on the way to the rail, '
      'so its edge never cuts one at full strength', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    final hand = await _grab(tester);
    await _move(tester, hand, -131);
    expect(controller.sidebarRail, isTrue);

    final title = find.descendant(of: _sidebar, matching: find.text('One'));
    var between = 0;
    while (title.evaluate().isNotEmpty) {
      final width = tester.getSize(_sidebar).width;
      final opacity = tester
          .widget<Opacity>(
            find.ancestor(of: title, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(
        opacity,
        moreOrLessEquals(((width - 72) / (200 - 72)).clamp(0.0, 1.0)),
      );
      if (opacity > 0.1 && opacity < 0.9) between++;
      await tester.pump(_frame);
    }
    expect(between, greaterThan(1), reason: 'a fade, not a cut');
    expect(tester.getSize(_sidebar).width, moreOrLessEquals(72));
  });

  testWidgets('a hand moving on while the side springs out of the rail aims '
      'the spring, which it does not jump', (tester) async {
    final controller = GlassTabController()
      ..sidebarShown = true
      ..sidebarRail = true;
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    expect(_edge(tester), 72);
    final hand = await _grab(tester, kind: PointerDeviceKind.touch);
    await _move(tester, hand, 51);
    expect(controller.sidebarRail, isFalse);
    await _move(tester, hand, 10);
    await tester.pump(_frame);
    expect(_edge(tester), lessThan(200), reason: 'still on the spring');
    await _settle(tester);
    expect(_edge(tester), 290);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarWidth, 290);
  });

  testWidgets('the rail stands beside the content where the sidebar covers '
      'it, unfolds over it, dimmed, and stays across a rotation', (
    tester,
  ) async {
    final controller = GlassTabController()..sidebarRail = true;
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    expect(controller.sidebarShown, isNull, reason: 'a rail shows by itself');
    expect(_edge(tester), 72);
    expect(_padding['One']!.top, 32, reason: 'no bar at the top');
    expect(_sidebar, findsOneWidget);
    expect(find.text('One'), findsNothing, reason: 'the rail has no titles');
    expect(find.byType(GlassBadge), findsOneWidget);

    await _pump(tester, controller, _landscape);
    expect(_edge(tester), 72);
    await _pump(tester, controller, _portrait);
    expect(_edge(tester), 72);

    final hand = await _grab(tester);
    await _move(tester, hand, 51);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarRail, isFalse);
    expect(_glass(tester).right, 280);
    expect(_padding['One']!.left, 0, reason: 'the sidebar covers the content');
    expect(_padding['One']!.top, 32 + 54);
    expect(find.text('One'), findsOneWidget);
    await tester.tapAt(const Offset(700, 700));
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(_bar, findsOneWidget);
  });

  testWidgets('the arrow keys and a screen reader step the edge, fold at the '
      'minimum and unfold from the rail', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController()..sidebarWidth = 220;
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    final divider = find.semantics.byPredicate(
      (node) => node.label == 'Column divider' && node.flagsCollection.isSlider,
    );
    expect(divider, findsOne);
    _focusDivider(tester);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(controller.sidebarWidth, 200, reason: 'a step stops at the minimum');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(controller.sidebarRail, isTrue);
    expect(_edge(tester), 72);

    tester.semantics.performAction(divider, SemanticsAction.increase);
    await _settle(tester);
    expect(controller.sidebarRail, isFalse);
    expect(_edge(tester), 200);
    tester.semantics.performAction(divider, SemanticsAction.decrease);
    await _settle(tester);
    tester.semantics.performAction(divider, SemanticsAction.decrease);
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(divider, findsNothing);
    semantics.dispose();
  });

  testWidgets('a double tap on the edge forgets the width and the rail', (
    tester,
  ) async {
    final controller = GlassTabController()
      ..sidebarShown = true
      ..sidebarRail = true
      ..sidebarWidth = 360;
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    final at = tester.getCenter(_divider);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(at);
    await _settle(tester);
    expect(controller.sidebarRail, isFalse);
    expect(controller.sidebarWidth, isNull);
    expect(_edge(tester), 280);
  });

  testWidgets('a narrow window draws the sidebar narrower, leaving the '
      'content 320, and keeps the width the hand gave', (tester) async {
    final controller = GlassTabController()..sidebarWidth = 400;
    addTearDown(controller.dispose);
    await _pump(tester, controller, const Size(1100, 834));
    expect(_edge(tester), 400);
    await _pump(tester, controller, const Size(700, 834));
    controller.sidebarShown = true;
    await _settle(tester);
    expect(_glass(tester).right, 700 - 320);
    expect(controller.sidebarWidth, 400);
  });

  testWidgets('right to left the edge is the left of the sidebar, and a drag '
      'to the left widens it', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _landscape,
      direction: TextDirection.rtl,
    );
    expect(tester.getCenter(_divider).dx, 1210 - 280);
    final hand = await _grab(tester);
    await _move(tester, hand, -61);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarWidth, 340);
    expect(_glass(tester).left, 1210 - 340);
    expect(_padding['One']!.right, 340);
  });

  testWidgets('without resizable the sidebar has no edge to drag', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, resizable: false);
    expect(_divider, findsNothing);
  });

  testWidgets(
    'the column of a list tab keeps the width a hand gave it across a '
    'change of tab and of width, and a drag past its minimum hides it',
    (
      tester,
    ) async {
      final controller = GlassTabController();
      addTearDown(controller.dispose);
      await _pump(tester, controller, _landscape, list: true);
      final split = controller.splitOf(0);
      final hand = await tester.startGesture(
        _dividerAt(tester, 280 + 320),
        kind: PointerDeviceKind.mouse,
      );
      await _move(tester, hand, 61);
      await hand.up();
      await _settle(tester);
      expect(split.primaryWidth, 380);

      controller.index = 1;
      await _settle(tester);
      controller.index = 0;
      await _settle(tester);
      expect(_dividerAt(tester, 280 + 380), isNotNull);
      await _pump(tester, controller, _portrait, list: true);
      expect(identical(controller.splitOf(0), split), isTrue);
      final away = await tester.startGesture(_dividerAt(tester, 380));
      await _move(tester, away, -141);
      await _move(tester, away, -50);
      await away.up();
      await _settle(tester);
      expect(split.isShowing(GlassSplitViewColumn.primary), isFalse);
      expect(split.primaryWidth, 380, reason: 'the width it had stays');
    },
  );

  testWidgets('without its button a list column stops at its minimum', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _portrait,
      list: true,
      showsListButton: false,
    );
    final hand = await tester.startGesture(_dividerAt(tester, 320));
    await _move(tester, hand, -301);
    await hand.up();
    await _settle(tester);
    final split = controller.splitOf(0);
    expect(split.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(split.primaryWidth, GlassTabLayout.defaultListWidth.minimum);
  });

  testWidgets('desktop keeps the sidebar beside the content, its button '
      'folds it into the rail and back, and a drag past the rail stops '
      'there', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    const desktop = GlassTabLayoutPolicy.desktop();
    await _pump(tester, controller, const Size(700, 834), layout: desktop);
    expect(_bar, findsNothing);
    expect(_glass(tester).right, 280);
    final button = find.descendant(
      of: _sidebar,
      matching: _private('GlassSidebarGlyph'),
    );
    await tester.tap(button);
    await _settle(tester);
    expect(controller.sidebarRail, isTrue);
    expect(_glass(tester).right, moreOrLessEquals(72));

    final hand = await _grab(tester);
    await _move(tester, hand, -60);
    await _move(tester, hand, -60);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarShown, isNot(isFalse));
    expect(_glass(tester).right, moreOrLessEquals(72));

    await tester.tap(button);
    await _settle(tester);
    expect(controller.sidebarRail, isFalse);
    expect(_glass(tester).right, moreOrLessEquals(280));

    await _pump(tester, controller, const Size(667, 834), layout: desktop);
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
  });

  testWidgets('a floating sidebar stands its margin from the window and '
      'the content beside it past the margin, its edge and its rail too', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    const floating = GlassTabLayoutPolicy.desktop(
      sidebarPanel: GlassTabSidebarPanel.floating,
    );
    await _pump(
      tester,
      controller,
      _landscape,
      layout: floating,
      sidebarStyle: const GlassTabSidebarStyle(
        backgroundColor: Color(0x33FF0000),
      ),
    );
    expect(_glassFrame(tester).tint, const Color(0x33FF0000));
    expect(_glassFrame(tester).tintAmount, 1);
    expect(_glass(tester), Rect.fromLTWH(8, 8, 280, _landscape.height - 16));
    expect(
      _glassFrame(tester).shape,
      const LiquidRoundedSuperellipse(radius: 22),
    );
    expect(_glassFrame(tester).opacity, 1);
    expect(tester.getCenter(_divider).dx, 288);
    expect(_padding['One']!.left, 296);

    final hand = await _grab(tester);
    await _move(tester, hand, 41);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarWidth, 320);
    expect(_glass(tester).right, 328);
    expect(_padding['One']!.left, 336);

    await tester.tap(
      find.descendant(of: _sidebar, matching: _private('GlassSidebarGlyph')),
    );
    await _settle(tester);
    expect(_glass(tester), Rect.fromLTWH(8, 8, 72, _landscape.height - 16));
    expect(_padding['One']!.left, 88);

    await _pump(
      tester,
      controller,
      _landscape,
      layout: floating,
      direction: TextDirection.rtl,
    );
    expect(_glass(tester).right, _landscape.width - 8);
  });

  testWidgets('a flush sidebar is an opaque fill with a hairline on the '
      "content's side and no glass at rest; hidden it is the bar's glass "
      'again, and over the content it floats', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    const style = GlassTabSidebarStyle(
      backgroundColor: Color(0xFF101010),
      separatorColor: Color(0xFF00FF00),
    );
    await _pump(
      tester,
      controller,
      _landscape,
      layout: const GlassTabLayoutPolicy.desktop(
        hides: true,
        sidebarPanel: GlassTabSidebarPanel.flush,
      ),
      sidebarStyle: style,
    );
    expect(_glass(tester), Rect.fromLTWH(0, 0, 280, _landscape.height));
    expect(_glassFrame(tester).opacity, 0);
    expect(_padding['One']!.left, 280);
    final element = tester.element(find.byType(GlassTabScaffold));
    final (bytes, width) = (await tester.runAsync<(ByteData, int)>(() async {
      final image = await captureImage(element);
      final bytes = (await image.toByteData())!;
      final width = image.width;
      image.dispose();
      return (bytes, width);
    }))!;
    int pixel(int x, int y) => bytes.getUint32((y * width + x) * 4);
    expect(pixel(100, 600), 0x101010FF);
    expect(pixel(278, 600), 0x101010FF);
    expect(pixel(279, 600) >> 16 & 0xFF, greaterThan(0x60));
    expect(pixel(279, 600) >> 24 & 0xFF, lessThan(0x20));

    controller.sidebarShown = false;
    await _settle(tester);
    expect(_glass(tester), tester.getRect(_bar));
    expect(_glassFrame(tester).opacity, 1);

    await _pump(
      tester,
      controller,
      _portrait,
      layout: const GlassTabLayoutPolicy.automatic(
        sidebarPanel: GlassTabSidebarPanel.flush,
      ),
      sidebarStyle: style,
    );
    controller.sidebarShown = true;
    await _settle(tester);
    expect(_glass(tester), Rect.fromLTWH(8, 8, 280, _portrait.height - 16));
    expect(_glassFrame(tester).opacity, 1);
    expect(_private('_FlushPanel'), findsNothing);
  });

  testWidgets('a sidebar that hides into its button leaves the button '
      "alone where the content's first bar item would stand, past the window "
      "buttons, the content's bars starting past it and its safe area "
      'kept', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    const controls = GlassWindowControls(left: 76);
    final item = find.byKey(const ValueKey('One leading'));
    Future<void> pump(
      GlassTabSidebarHidden hidden, {
      TextDirection direction = TextDirection.ltr,
    }) async {
      await _pump(
        tester,
        controller,
        _landscape,
        layout: GlassTabLayoutPolicy.desktop(hides: true, hidden: hidden),
        windowControls: controls,
        leading: true,
        direction: direction,
      );
      controller.sidebarShown = false;
      await _settle(tester);
    }

    await pump(GlassTabSidebarHidden.bar);
    final atBar = tester.getTopLeft(item).dx;
    expect(_padding['One']!.top, 32 + 54);

    await pump(GlassTabSidebarHidden.button);
    final button = _private('_SidebarButton');
    expect(_bar, findsNothing);
    expect(tester.getRect(button), const Rect.fromLTWH(92, 32, 44, 44));
    expect(_glass(tester), tester.getRect(button));
    expect(
      _glassFrame(tester).shape,
      const LiquidRoundedSuperellipse(radius: 22),
    );
    expect(_glassFrame(tester).opacity, 1);
    expect(_padding['One']!.top, 32);
    expect(
      GlassEnvironment.of(tester.element(item)).windowControls,
      const GlassWindowControls(left: 136, lineCenter: 54),
    );
    expect(tester.getTopLeft(item).dx, moreOrLessEquals(atBar + 136));

    await tester.tap(button);
    await _settle(tester);
    expect(controller.sidebarShown, isTrue);
    expect(_glass(tester), Rect.fromLTWH(0, 0, 280, _landscape.height));
    expect(_padding['One']!.left, 280);
    expect(
      GlassEnvironment.of(tester.element(item)).windowControls,
      controls,
    );

    await pump(GlassTabSidebarHidden.button, direction: TextDirection.rtl);
    expect(
      tester.getRect(button),
      Rect.fromLTWH(_landscape.width - 60, 32, 44, 44),
    );
    expect(
      GlassEnvironment.of(tester.element(item)).windowControls,
      const GlassWindowControls(left: 76, right: 60, lineCenter: 54),
    );

    await _pump(
      tester,
      controller,
      _portrait,
      layout: const GlassTabLayoutPolicy.automatic(
        hidden: GlassTabSidebarHidden.button,
      ),
    );
    controller.sidebarShown = null;
    await _settle(tester);
    expect(tester.getRect(button), const Rect.fromLTWH(16, 32, 44, 44));
    await tester.tap(button);
    await _settle(tester);
    expect(_glass(tester), Rect.fromLTWH(0, 0, 280, _portrait.height));
    expect(_padding['One']!.left, 0);
    await tester.tapAt(const Offset(800, 600));
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(_glass(tester), tester.getRect(button));
  });

  testWidgets('a custom layout draws its own widths: a hand folds a '
      'sidebar 140 to 320 wide into a rail 56 wide', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final layout = GlassTabLayoutPolicy.custom(
      (environment, size) => size.width < 900
          ? const GlassTabLayout.bottom()
          : const GlassTabLayout.sidebar(
              beside: true,
              hides: false,
              sidebarWidth: GlassWidthRange(
                minimum: 140,
                preferred: 220,
                maximum: 320,
              ),
              railWidth: 56,
            ),
    );
    await _pump(tester, controller, _landscape, layout: layout);
    expect(_edge(tester), 220);
    final hand = await _grab(tester);
    await _move(tester, hand, -81);
    expect(_glass(tester).right, moreOrLessEquals(140));
    await _move(tester, hand, -50);
    await hand.up();
    await _settle(tester);
    expect(controller.sidebarRail, isTrue);
    expect(_edge(tester), moreOrLessEquals(56));

    await _pump(tester, controller, const Size(899, 834), layout: layout);
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
  });

  testWidgets('across a change between over and beside the width a hand gave '
      'stays, and the sidebar the buttons hid follows the width again '
      'unless the policy remembers it', (tester) async {
    for (final remembers in [false, true]) {
      final controller = GlassTabController()..sidebarWidth = 340;
      addTearDown(controller.dispose);
      final layout = GlassTabLayoutPolicy.custom(
        (environment, size) =>
            GlassTabLayout.sidebar(beside: size.width >= 1024),
        remembersSidebar: remembers,
      );
      await _pump(tester, controller, _landscape, layout: layout);
      expect(_edge(tester), 340);
      controller.sidebarShown = false;
      await _settle(tester);
      expect(_bar, findsOneWidget);
      await _pump(tester, controller, const Size(834, 1194), layout: layout);
      await _pump(tester, controller, _landscape, layout: layout);
      expect(
        _bar,
        remembers ? findsOneWidget : findsNothing,
        reason: 'remembers: $remembers',
      );
      expect(controller.sidebarWidth, 340);
      if (!remembers) expect(_edge(tester), 340);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an iPad window too narrow for both columns hides the list '
      'until its button shows it, and the list keeps what the hand chose '
      'across a change of layout', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final split = controller.splitOf(0);
    GlassSplitView view() => tester.widget(find.byType(GlassSplitView));
    await _pump(tester, controller, const Size(700, 834), list: true);
    expect(view().showsPrimaryByDefault, isFalse);
    expect(split.isShowing(GlassSplitViewColumn.primary), isFalse);
    split.show(GlassSplitViewColumn.primary);
    await _settle(tester);
    expect(split.isShowing(GlassSplitViewColumn.primary), isTrue);

    await _pump(tester, controller, _landscape, list: true);
    expect(view().showsPrimaryByDefault, isTrue);
    split
      ..primaryWidth = 300
      ..hide(GlassSplitViewColumn.primary);
    await _settle(tester);
    for (final size in [const Size(700, 834), _landscape]) {
      await _pump(tester, controller, size, list: true);
      expect(split.isShowing(GlassSplitViewColumn.primary), isFalse);
      expect(split.primaryWidth, 300);
    }
  });

  testWidgets('a layout state saved under a policy that remembers the '
      'sidebar brings it back on the next launch, and automatic leaves the '
      'sidebar out', (tester) async {
    const desktop = GlassTabLayoutPolicy.desktop(hides: true);
    final first = GlassTabController();
    addTearDown(first.dispose);
    await _pump(tester, first, _landscape, list: true, layout: desktop);
    first
      ..sidebarWidth = 340
      ..sidebarShown = false
      ..splitOf(0).primaryWidth = 300;
    await _settle(tester);
    final saved = jsonEncode(first.layoutState.toJson());
    await tester.pumpWidget(const SizedBox());

    final next = GlassTabController()
      ..layoutState = GlassTabLayoutState.fromJson(
        jsonDecode(saved) as Map<String, Object?>,
      );
    addTearDown(next.dispose);
    await _pump(tester, next, _landscape, list: true, layout: desktop);
    expect(_bar, findsOneWidget);
    expect(next.splitOf(0).primaryWidth, 300);
    next.sidebarShown = true;
    await _settle(tester);
    expect(_glass(tester).right, 340);

    await _pump(tester, next, _landscape, list: true);
    expect(next.layoutState.sidebarShown, isNull);
    expect(next.layoutState.sidebarWidth, 340);
  });
}
