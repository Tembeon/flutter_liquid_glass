import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The tab sidebar passport: an 11 inch iPad Pro on iOS 27.2, its window's
// safe area 32 at the top and 20 at the bottom.
const _portrait = Size(1032, 1376);
const _landscape = Size(1210, 834);
const _top = 32.0;
const _bottom = 20.0;

final _padding = <String, EdgeInsets>{};

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
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(
    top: _top * 2,
    bottom: _bottom * 2,
  );
  addTearDown(tester.view.reset);
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
              searchController: search,
              searchBuilder: search == null
                  ? null
                  : (context) => const _Page('Search'),
              bottomAccessory: accessory,
              action: action,
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

Finder get _bar => _private('_TopBar');
Finder get _sidebar => _private('_Sidebar');
Finder get _rows => _private('_SidebarRow');

// The buttons read as [label], outermost first: a GlassButton holds a
// RawGlassButton of the same label.
Finder _buttons(String label) => find.byWidgetPredicate(
  (widget) =>
      (widget is RawGlassButton && widget.semanticLabel == label) ||
      (widget is GlassButton && widget.semanticLabel == label),
);

Finder _button(String label) => _buttons(label).first;

void main() {
  testWidgets('on an iPad in portrait the tabs stand in a bar at the top, '
      'centered on the top safe area, with the content 54 below its top', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    expect(find.byType(GlassFloatingTabBar), findsNothing);
    expect(_sidebar, findsNothing);
    final bar = tester.getRect(_bar);
    expect(bar.top, _top);
    expect(bar.height, 44);
    expect(bar.center.dx, moreOrLessEquals(_portrait.width / 2));
    final button = tester.getRect(_button('Show Sidebar'));
    expect(button, Rect.fromLTWH(bar.left + 4, _top + 4, 56, 36));
    expect(_padding['One']!.top, _top + 54);
    expect(_padding['One']!.left, 0);
    semantics.dispose();
  });

  testWidgets('the sidebar button shows the sidebar over the content, which '
      'it dims, and a tap on the dimming hides it', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var heard = 0;
    controller.addListener(() => heard++);
    await _pump(tester, controller, _portrait);
    tester.semantics.tap(find.semantics.byLabel('Show Sidebar').first);
    await _settle(tester);
    expect(controller.sidebarShown, isTrue);
    expect(heard, 1);
    expect(_bar, findsNothing);
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
      _top + 54,
      reason: 'a sidebar over the content leaves its safe area alone',
    );
    await tester.tapAt(const Offset(700, 700));
    await _settle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(_sidebar, findsNothing);
    expect(_bar, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a row of the sidebar selects its tab, and over the content '
      'leaves the sidebar up', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    controller.sidebarShown = true;
    await _settle(tester);
    await tester.tap(find.descendant(of: _sidebar, matching: find.text('Two')));
    await _settle(tester);
    expect(controller.index, 1);
    expect(find.text('Two page'), findsOneWidget);
    expect(_sidebar, findsOneWidget);
  });

  testWidgets('from 1100 wide the sidebar stands beside the content, whose '
      'safe area and bars start past it', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    expect(_bar, findsNothing);
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
    expect(_bar, findsOneWidget);
    expect(_padding['One']!.left, 0);
    expect(_padding['One']!.top, _top + 54);
    semantics.dispose();
  });

  testWidgets('a change between over and beside forgets what the hand '
      'chose, as UIKit shows the sidebar on a rotation to landscape', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    controller.sidebarShown = false;
    await _settle(tester);
    expect(_sidebar, findsNothing);
    await _pump(tester, controller, _portrait);
    expect(controller.sidebarShown, isNull);
    expect(_sidebar, findsNothing);
    await _pump(tester, controller, _landscape);
    expect(_sidebar, findsOneWidget);
  });

  testWidgets('a phone in landscape and an iPhone Duo open flat keep the bar '
      'at the bottom; from 700 tall the bar goes to the top', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, const Size(874, 402));
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
    expect(_bar, findsNothing);
    await _pump(tester, controller, const Size(951, 669));
    expect(find.byType(GlassFloatingTabBar), findsOneWidget);
    await _pump(tester, controller, const Size(1032, 700));
    expect(find.byType(GlassFloatingTabBar), findsNothing);
    expect(_bar, findsOneWidget);
  });

  testWidgets('a tab of the bar at the top selects it, the search tab opens '
      'the search, and a tab closes it', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await _pump(tester, controller, _portrait, search: search);
    await tester.tap(find.descendant(of: _bar, matching: find.text('Two')));
    await _settle(tester);
    expect(controller.index, 1);
    expect(find.text('Two page'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('Search'));
    await _settle(tester);
    expect(search.isOpen, isTrue);
    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('Two page'), findsNothing);
    await tester.tap(find.descendant(of: _bar, matching: find.text('One')));
    await _settle(tester);
    expect(search.isOpen, isFalse);
    expect(controller.index, 0);
    expect(find.text('One page'), findsOneWidget);
    semantics.dispose();
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
    expect(selected('Two'), isTrue);
    expect(selected('One'), isFalse);
    controller.sidebarShown = true;
    await _settle(tester);
    expect(selected('Two'), isTrue);
    expect(selected('One'), isFalse);
    semantics.dispose();
  });

  testWidgets('a page that hides the tab bar slides the bar at the top away', (
    tester,
  ) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _portrait);
    await tester.tap(find.text('Two page'));
    await _settle(tester);
    expect(find.text('Two.next page'), findsOneWidget);
    expect(tester.getRect(_bar).bottom, lessThanOrEqualTo(0));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Two.next page'), findsNothing);
    expect(tester.getRect(_bar).top, _top);
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

  testWidgets('the action is a circle beside the bar at the top and a row at '
      'the end of the sidebar', (tester) async {
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
    expect(_buttons('Compose'), findsNothing);
    final row = find.ancestor(of: find.text('Compose'), matching: _rows);
    expect(tester.getRect(row).top, _top + 63 + 2 * 44);
    await tester.tap(row);
    expect(pressed, 1);

    controller.sidebarShown = false;
    await _settle(tester);
    final bar = tester.getRect(_bar);
    final action = tester.getRect(_button('Compose'));
    expect(action, Rect.fromLTWH(bar.right + 8, _top, 44, 44));
    expect(
      (bar.left + action.right) / 2,
      moreOrLessEquals(1210 / 2),
      reason: 'the bar and the action center together',
    );
    await tester.tap(_button('Compose'));
    expect(pressed, 2);
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
}
