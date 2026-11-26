import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/poses.dart';

// The tab sidebar passport: an 11 inch iPad Pro on iOS 27.2, its window's
// safe area 32 at the top and 20 at the bottom.
const _portrait = Size(1032, 1376);
const _landscape = Size(1210, 834);
const _top = 32.0;
const _bottom = 20.0;

final _padding = <String, EdgeInsets>{};

// The tab sidebar over the content in portrait and beside it from 1024
// wide in landscape, hiding into its button: where the automatic layout
// keeps the bottom bar in portrait, the layout these tests read the
// sidebar over the content in.
final _overInPortrait = GlassTabLayoutPolicy.custom((environment, size) {
  if (environment.formFactor == GlassFormFactor.phone ||
      !environment.isRegularWidth) {
    return const GlassTabLayout.bottom();
  }
  return GlassTabLayout.sidebar(
    beside: size.width >= 1024 && size.width >= size.height,
    list: size.width >= 728 ? GlassTabListMode.beside : GlassTabListMode.hidden,
  );
});

class _Page extends StatelessWidget {
  const _Page(this.name, {this.hidesTabBar = false});

  final String name;
  final bool hidesTabBar;

  @override
  Widget build(BuildContext context) {
    _padding[name] = MediaQuery.paddingOf(context);
    return GlassPageScaffold(
      hidesTabBar: hidesTabBar,
      navigationBar: GlassNavigationBar(title: Text('$name bar')),
      child: ListView(
        children: [
          Center(
            child: GestureDetector(
              onTap: () => GlassTabStack.of(
                context,
              ).push(_Page('$name.next', hidesTabBar: true)),
              child: Text('$name page'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  GlassTabController controller,
  Size size, {
  TextDirection direction = TextDirection.ltr,
  GlassSearchController? search,
  Widget? accessory,
  GlassTabBarAction? action,
  bool list = false,
  NotificationListenerCallback<ScrollNotification>? onScroll,
  int more = 0,
  Pose? pose,
  GlassTabLayoutPolicy layout = const GlassTabLayoutPolicy.automatic(),
  Widget? sidebarTopBackground,
}) async {
  if (pose != null) {
    pose.apply(tester);
  } else {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(
      top: _top * 2,
      bottom: _bottom * 2,
    );
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: NotificationListener<ScrollNotification>(
        onNotification: onScroll,
        child: Directionality(
          textDirection: direction,
          child: GlassScope(
            renderer: const FlatGlassRenderer(),
            child: GlassTabScaffold(
              controller: controller,
              layout: layout,
              searchController: search,
              searchBuilder: search == null
                  ? null
                  : (context) => const _Page('Search'),
              bottomAccessory: accessory,
              action: action,
              sidebarTopBackground: sidebarTopBackground,
              tabs: [
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('One'),
                  builder: (context) => const _Page('One'),
                  detailPlaceholder: list
                      ? (context) => const Text('Nothing open')
                      : null,
                ),
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('Two'),
                  builder: (context) => const _Page('Two'),
                ),
                for (var i = 0; i < more; i++)
                  GlassTab(
                    icon: const SizedBox.square(dimension: 24),
                    label: Text('More $i'),
                    builder: (context) => _Page('More $i'),
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
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder _private(String type) =>
    find.byWidgetPredicate((widget) => '${widget.runtimeType}' == type);

Finder get _alone => _private('_SidebarButton');
Finder get _sidebar => find.byType(GlassTabSidebar);
Finder get _rows => find.byType(GlassTabSidebarRow);

// The buttons read as [label], outermost first: a GlassButton holds a
// RawGlassButton of the same label.
Finder _buttons(String label) => find.byWidgetPredicate(
  (widget) =>
      (widget is RawGlassButton && widget.semanticLabel == label) ||
      (widget is GlassButton && widget.semanticLabel == label),
);

// Where the glass of the sidebar's button and of the sidebar is drawn.
Rect _glass(WidgetTester tester) => tester
    .widget<GlassSurface>(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlassSurface &&
            widget.role == GlassRole.bar &&
            widget.frame != null,
      ),
    )
    .frame!
    .value
    .rect!;

void main() {
  testWidgets('on an iPad in portrait the automatic layout keeps the tab bar '
      'at the bottom, laid out wide, where UIKit puts a bar at the top', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
    expect(_sidebar, findsNothing);
    expect(_alone, findsNothing);
    final bar = tester.getRect(find.byType(RawGlassSelector));
    expect(bar.height, 44);
    expect(bar.bottom, _portrait.height - 20);
    expect(bar.center.dx, moreOrLessEquals(_portrait.width / 2));
    expect(_padding['One']!.top, _top);
  });

  testWidgets('the sidebar button shows the sidebar over the content, which '
      'it dims, and a tap on the dimming hides it', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var heard = 0;
    controller.addListener(() => heard++);
    await _pump(tester, controller, _portrait, layout: _overInPortrait);
    tester.semantics.tap(find.semantics.byLabel('Show Sidebar').first);
    await _settle(tester);
    expect(controller.sidebarShown, isTrue);
    expect(heard, 1);
    expect(_alone, findsNothing);
    expect(
      tester.getRect(_sidebar),
      const Rect.fromLTWH(0, 0, 280, 1376),
    );
    expect(
      tester.getRect(_rows.first),
      const Rect.fromLTWH(20, _top + 63, 244, 44),
    );
    expect(tester.getRect(_rows.at(1)).top, _top + 63 + 44);
    expect(
      _padding['One']!.top,
      _top,
      reason: 'a sidebar over the content leaves its safe area alone',
    );
    await tester.tapAt(const Offset(700, 700));
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(_sidebar, findsNothing);
    expect(_alone, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a row of the sidebar selects its tab, and over the content '
      'leaves the sidebar up', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait, layout: _overInPortrait);
    controller.sidebarShown = true;
    await _settle(tester);
    await tester.tap(find.descendant(of: _sidebar, matching: find.text('Two')));
    await _settle(tester);
    expect(controller.index, 1);
    expect(find.text('Two page'), findsOneWidget);
    expect(_sidebar, findsOneWidget);
  });

  testWidgets('the band above the sidebar\'s rows takes every hit its '
      'button leaves, and the app fills it, as a bar does', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    const grip = Key('grip');
    final background = GestureDetector(
      key: grip,
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {},
      child: const SizedBox.expand(),
    );
    void probe(String name) {
      final band = tester.getRect(find.byKey(grip));
      expect(band.height, greaterThan(_top), reason: name);
      final button = tester.getRect(
        _buttons(
          (controller.sidebarShown ?? true) ? 'Hide Sidebar' : 'Show Sidebar',
        ).first,
      );
      final listener = tester.renderObject(
        find.descendant(of: find.byKey(grip), matching: find.byType(Listener)),
      );
      for (final y in [band.top + 2, band.center.dy, band.bottom - 2]) {
        for (var x = band.left + 8; x < band.right; x += 16) {
          final at = Offset(x, y);
          if (button.contains(at)) continue;
          final hit = tester.hitTestOnBinding(at);
          expect(
            hit.path.map((entry) => entry.target),
            contains(listener),
            reason: '$name at $at',
          );
        }
      }
    }

    await _pump(
      tester,
      controller,
      _landscape,
      more: 20,
      sidebarTopBackground: background,
    );
    probe('beside');
    await tester.drag(find.text('More 5'), const Offset(0, -300));
    await _settle(tester);
    final band = tester.getRect(find.byKey(grip));
    final under = tester.getRect(_rows.at(3));
    expect(under.top, lessThan(band.bottom - 10), reason: 'a row under it');
    await tester.tapAt(Offset(under.center.dx, band.bottom - 5));
    await _settle(tester);
    expect(controller.index, 0, reason: 'the row under the band is not hit');

    await _pump(
      tester,
      controller,
      _landscape,
      direction: TextDirection.rtl,
      sidebarTopBackground: background,
    );
    probe('beside, right to left');

    await _pump(
      tester,
      controller,
      _portrait,
      layout: _overInPortrait,
      sidebarTopBackground: background,
    );
    await tester.tap(_alone);
    await _settle(tester);
    probe('over the content');
  });

  testWidgets('a sidebar that loses tabs asks no frame of a row gone', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, more: 6);
    await _pump(tester, controller, _landscape);
    expect(tester.takeException(), isNull);
    expect(_rows, findsNWidgets(2));
  });

  testWidgets('from 1100 wide the sidebar stands beside the content, whose '
      'safe area and bars start past it', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    expect(_alone, findsNothing);
    expect(find.semantics.byLabel('Hide Sidebar'), findsOneWidget);
    expect(tester.getRect(_sidebar), const Rect.fromLTWH(0, 0, 280, 834));
    expect(_padding['One']!.left, 280);
    expect(_padding['One']!.top, _top);
    expect(
      tester.getCenter(find.text('One bar')).dx,
      moreOrLessEquals(280 + (1210 - 280) / 2, epsilon: 1),
      reason: 'the title centers on the content beside the sidebar',
    );

    tester.semantics.tap(find.semantics.byLabel('Hide Sidebar'));
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(_sidebar, findsNothing);
    expect(_alone, findsOneWidget);
    expect(_padding['One']!.left, 0);
    expect(_padding['One']!.top, _top);
    semantics.dispose();
  });

  testWidgets('the search page beside the sidebar starts past it', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await _pump(tester, controller, _landscape, search: search);
    search.openView();
    await _settle(tester);
    expect(_padding['Search']!.left, 280);
  });

  testWidgets('a change between over and beside forgets what the hand '
      'chose, as UIKit shows the sidebar on a rotation to landscape', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, layout: _overInPortrait);
    controller.sidebarShown = false;
    await _settle(tester);
    expect(_sidebar, findsNothing);
    await _pump(tester, controller, _portrait, layout: _overInPortrait);
    expect(controller.sidebarShown, isNull);
    expect(_sidebar, findsNothing);
    await _pump(tester, controller, _landscape, layout: _overInPortrait);
    expect(_sidebar, findsOneWidget);
  });

  testWidgets('a phone in landscape, an iPhone Duo open flat and iPad '
      'windows too narrow for a sidebar beside the content keep the bar at '
      'the bottom', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    for (final pose in [
      Poses.iPhoneLandscape,
      Poses.duoInnerClassic,
      Poses.iPadWindowShortRegular,
      Poses.iPadWindowCompactWidest,
    ]) {
      await _pump(tester, controller, pose.window, pose: pose);
      expect(find.byType(GlassFloatingTabBar), findsOneWidget, reason: '$pose');
      expect(_sidebar, findsNothing, reason: '$pose');
    }
  });

  testWidgets("a row of the sidebar selects its tab, the search's row opens "
      "the search, and a tab's row closes it", (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await _pump(tester, controller, _landscape, search: search);
    await tester.tap(find.descendant(of: _sidebar, matching: find.text('Two')));
    await _settle(tester);
    expect(controller.index, 1);
    expect(find.text('Two page'), findsOneWidget);
    await tester.tap(
      find.descendant(of: _sidebar, matching: find.text('Search')),
    );
    await _settle(tester);
    expect(search.isOpen, isTrue);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('Two page'), findsNothing);
    expect(
      find.byType(GlassSearchField),
      findsOneWidget,
      reason: "the search page's bar holds the field",
    );
    await tester.enterText(find.byType(EditableText), 'two');
    await _settle(tester);
    expect(search.text, 'two');
    await tester.tap(find.descendant(of: _sidebar, matching: find.text('One')));
    await _settle(tester);
    expect(search.isOpen, isFalse);
    expect(controller.index, 0);
    expect(find.text('One page'), findsOneWidget);
  });

  testWidgets('the tab chosen is flagged selected in the bar and in the '
      'sidebar', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    bool selected(String label) =>
        find.semantics
            .byLabel(label)
            .evaluate()
            .single
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
    expect(selected('Two'), isTrue);
    expect(selected('One'), isFalse);
    await _pump(tester, controller, _landscape);
    expect(_sidebar, findsOneWidget);
    expect(selected('Two'), isTrue);
    expect(selected('One'), isFalse);
    semantics.dispose();
  });

  testWidgets('the selected row is a gray pill while the list tab shows its '
      'list column, and a tint pill otherwise', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, list: true);
    Color? pill(String label) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.ancestor(of: find.text(label), matching: _rows),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as ShapeDecoration).color;
    }

    expect(pill('One'), const Color(0x14747480));
    expect(pill('Two'), isNull);
    await tester.tap(find.descendant(of: _sidebar, matching: find.text('Two')));
    await _settle(tester);
    expect(pill('Two')?.toARGB32(), GlassColors.systemBlue.color.toARGB32());
    expect(pill('One'), isNull);
  });

  testWidgets('right to left, the sidebar stands at the right', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _landscape,
      direction: TextDirection.rtl,
    );
    expect(
      tester.getRect(_sidebar),
      const Rect.fromLTWH(1210 - 280, 0, 280, 834),
    );
    expect(
      tester.getRect(_rows.first),
      const Rect.fromLTWH(1210 - 20 - 244, _top + 63, 244, 44),
    );
    expect(_padding['One']!.right, 280);
    expect(_padding['One']!.left, 0);
  });

  testWidgets('the accessory stands 20 above the bottom in the middle of the '
      'content', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _landscape,
      accessory: const SizedBox(width: 147, height: 20, child: Text('Now')),
    );
    final accessory = tester.getRect(
      find.ancestor(
        of: find.text('Now'),
        matching: _private('_RegularAccessory'),
      ),
    );
    expect(accessory.height, 64);
    expect(accessory.width, 187);
    expect(accessory.bottom, 834 - 20);
    expect(accessory.center.dx, 280 + (1210 - 280) / 2);
    expect(_padding['One']!.bottom, 84);
  });

  testWidgets('the action is a row at the end of the sidebar', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var pressed = 0;
    await _pump(
      tester,
      controller,
      _landscape,
      action: GlassTabBarAction(
        icon: const SizedBox.square(dimension: 20),
        semanticLabel: 'Compose',
        onPressed: () => pressed++,
      ),
    );
    expect(_buttons('Compose'), findsOneWidget);
    expect(
      find.descendant(of: _sidebar, matching: _buttons('Compose')),
      findsOneWidget,
      reason: 'the action is a row of the sidebar, not a circle',
    );
    final row = find.ancestor(of: find.text('Compose'), matching: _rows);
    expect(tester.getRect(row).top, _top + 63 + 2 * 44);
    await tester.tap(row);
    expect(pressed, 1);
  });

  testWidgets('a scroll of a sidebar of many tabs is not a scroll of the '
      'content', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final scrolled = <ScrollNotification>[];
    await _pump(
      tester,
      controller,
      _landscape,
      onScroll: (notification) {
        scrolled.add(notification);
        return false;
      },
      more: 20,
    );
    scrolled.clear();
    await tester.drag(_sidebar, const Offset(0, -200));
    await _settle(tester);
    expect(scrolled, isEmpty);
    await tester.drag(find.text('One page'), const Offset(0, 200));
    await _settle(tester);
    expect(scrolled, isNotEmpty, reason: 'the content scroll goes up');
  });

  testWidgets("the glass of the sidebar's button morphs into the sidebar, "
      'across first and down 0.105 s later, and back, up first and across '
      '0.13 s later', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait, layout: _overInPortrait);
    final bar = tester.getRect(_alone);
    expect(_glass(tester), bar);
    const sidebar = Rect.fromLTWH(0, 0, 280, 1376);

    controller.sidebarShown = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    var now = _glass(tester);
    expect(now.left, lessThan(bar.left));
    expect(now.width, isNot(bar.width));
    expect(now.top, bar.top, reason: 'down waits 0.105 s');
    expect(now.height, bar.height);
    expect(_alone, findsOneWidget, reason: 'both stand while it moves');
    expect(_sidebar, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 140));
    now = _glass(tester);
    expect(now.top, inExclusiveRange(sidebar.top, bar.top));
    expect(now.height, inExclusiveRange(bar.height, sidebar.height));
    await _settle(tester);
    expect(_glass(tester), sidebar);
    expect(_alone, findsNothing);

    controller.sidebarShown = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    now = _glass(tester);
    expect(now.height, lessThan(sidebar.height));
    expect(now.left, sidebar.left, reason: 'across waits 0.13 s');
    expect(now.width, sidebar.width);
    await tester.pump(const Duration(milliseconds: 140));
    now = _glass(tester);
    expect(now.left, inExclusiveRange(sidebar.left, bar.left));
    await _settle(tester);
    expect(_glass(tester), bar);
    expect(_sidebar, findsNothing);
  });

  testWidgets('a hide before the sidebar starts down drops the down stage: '
      "the glass goes back across at the button's height", (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait, layout: _overInPortrait);
    final bar = tester.getRect(_alone);
    controller.sidebarShown = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    controller.sidebarShown = false;
    await tester.pump();
    var tallest = 0.0;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      tallest = math.max(tallest, _glass(tester).height);
    }
    expect(tallest, bar.height);
    expect(_glass(tester), bar);
    expect(_sidebar, findsNothing);
    expect(_alone, findsOneWidget);
  });

  testWidgets("the search page keeps the bottom bar's field alone, and a "
      "change of chrome keeps the page's state", (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await _pump(tester, controller, const Size(874, 402), search: search);
    search.openView();
    await _settle(tester);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.byType(GlassSearchField), findsOneWidget);

    final page = find.ancestor(
      of: find.text('Search page'),
      matching: find.byType(Scrollable),
    );
    final state = tester.state(page.first);
    await _pump(tester, controller, _portrait, search: search);
    expect(find.byType(GlassSearchField), findsOneWidget);
    expect(tester.state(page.first), same(state));
    await _pump(tester, controller, const Size(402, 874), search: search);
    expect(tester.state(page.first), same(state));
  });
}
