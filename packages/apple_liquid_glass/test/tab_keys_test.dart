import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _landscape = Size(1210, 834);
const _portrait = Size(1032, 1376);
const _phone = Size(402, 874);

class _Page extends StatelessWidget {
  const _Page(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(title: Text('$name bar')),
    child: ListView(
      children: [
        GestureDetector(
          onTap: () => GlassTabStack.of(context).push(_Page('$name.next')),
          child: Text('$name page'),
        ),
      ],
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  GlassTabController controller,
  Size size, {
  bool list = false,
  bool disabledThird = false,
  Map<ShortcutActivator, Intent> shortcuts =
      GlassToggleSidebarIntent.defaultShortcuts,
  VoidCallback? onReselect,
  GlassSearchController? search,
  Map<Type, Action<Intent>> above = const {},
  GlassTabLayoutPolicy layout = const GlassTabLayoutPolicy.automatic(),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: InputCommands(
          actions: above,
          child: GlassTabScaffold(
            controller: controller,
            layout: layout,
            shortcuts: shortcuts,
            searchController: search,
            searchBuilder: search == null
                ? null
                : (context) => const _Page('Search'),
            tabs: [
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: const Text('One'),
                builder: (context) => const _Page('One'),
                onReselect: onReselect,
                detailPlaceholder: list
                    ? (context) => const Text('Nothing open')
                    : null,
              ),
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: const Text('Two'),
                builder: (context) => const _Page('Two'),
              ),
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: const Text('Three'),
                builder: (context) => const _Page('Three'),
                enabled: !disabledThird,
              ),
            ],
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

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _settle(tester);
}

Future<void> _toggle(WidgetTester tester) =>
    _press(tester, LogicalKeyboardKey.keyS, control: true);

// Whether the primary focus encloses what [finder] finds.
bool _focusEncloses(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  var encloses = false;
  finder.evaluate().single.visitAncestorElements((element) {
    encloses = identical(element, focused);
    return !encloses;
  });
  return encloses;
}

void main() {
  testWidgets('control-command-S hides and shows the tab sidebar, with '
      'nothing focused by the test', (tester) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    expect(find.byType(GlassTabSidebar), findsOneWidget);
    await _toggle(tester);
    expect(controller.sidebarShown, isFalse);
    expect(find.byType(GlassTabSidebar), findsNothing);
    await _toggle(tester);
    expect(controller.sidebarShown, isTrue);
    expect(find.byType(GlassTabSidebar), findsOneWidget);
  });

  testWidgets('the key shows the sidebar over the content too, and hides '
      'it', (tester) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _portrait,
      layout: GlassTabLayoutPolicy.custom(
        (environment, size) => const GlassTabLayout.sidebar(),
      ),
    );
    expect(find.byType(GlassTabSidebar), findsNothing);
    await _toggle(tester);
    expect(controller.sidebarShown, isTrue);
    await _toggle(tester);
    expect(controller.sidebarShown, isFalse);
  });

  testWidgets('on a list tab the key hides and shows its list column, and '
      'leaves the tab sidebar alone', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, list: true);
    final split = controller.splitOf(0);
    expect(split.isShowing(GlassSplitViewColumn.primary), isTrue);
    await _toggle(tester);
    expect(split.isShowing(GlassSplitViewColumn.primary), isFalse);
    expect(controller.sidebarShown, isNull);
    await _toggle(tester);
    expect(split.isShowing(GlassSplitViewColumn.primary), isTrue);
    expect(controller.sidebarShown, isNull);
  });

  testWidgets('an alert over the scaffold keeps the key from it', (
    tester,
  ) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape);
    unawaited(
      showGlassAlert(
        tester.element(find.text('Two page')),
        title: const Text('Alert'),
        actions: const [GlassAlertAction.cancel(child: Text('Cancel'))],
      ),
    );
    await _settle(tester);
    expect(find.text('Alert'), findsOneWidget);
    await _toggle(tester);
    expect(controller.sidebarShown, isNull);
    expect(find.byType(GlassTabSidebar), findsOneWidget);
  });

  testWidgets('where nothing can be toggled the key goes on to the '
      'commands above', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var heard = 0;
    await _pump(
      tester,
      controller,
      _phone,
      above: {
        GlassToggleSidebarIntent: CallbackAction<GlassToggleSidebarIntent>(
          onInvoke: (_) => heard++,
        ),
      },
    );
    await _toggle(tester);
    expect(heard, 1);
  });

  testWidgets('a scaffold given no shortcuts binds no keys', (tester) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, shortcuts: const {});
    await _toggle(tester);
    expect(controller.sidebarShown, isNull);
    expect(find.byType(GlassTabSidebar), findsOneWidget);
  });

  testWidgets('the number shortcuts select a tab, but not a disabled one', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _landscape,
      disabledThird: true,
      shortcuts: {
        ...GlassToggleSidebarIntent.defaultShortcuts,
        ...GlassSelectTabIntent.numberShortcuts,
      },
    );
    await _press(tester, LogicalKeyboardKey.digit2);
    expect(controller.index, 1);
    await _press(tester, LogicalKeyboardKey.digit3);
    expect(controller.index, 1);
    await _press(tester, LogicalKeyboardKey.digit9);
    expect(controller.index, 1);
    await _press(tester, LogicalKeyboardKey.digit1);
    expect(controller.index, 0);
  });

  testWidgets('the focus left in a tab goes to the tab shown', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    controller.index = 1;
    await _settle(tester);
    await tester.tap(find.text('Two page'));
    await _settle(tester);
    expect(_focusEncloses(find.text('Two.next page')), isTrue);
    controller.index = 0;
    await _settle(tester);
    expect(_focusEncloses(find.text('One page')), isTrue);
    controller.index = 1;
    await _settle(tester);
    expect(
      _focusEncloses(find.text('Two.next page')),
      isTrue,
      reason: 'a tab shown again gets back the focus it had',
    );
  });

  testWidgets('Tab enters the sidebar at the selected row, and an arrow '
      'selects the next tab and keeps the focus in the sidebar', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _landscape, disabledThird: true);
    bool inSidebar() {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused != null &&
          focused.findAncestorWidgetOfExactType<GlassTabSidebar>() != null;
    }

    for (var i = 0; i < 10 && !inSidebar(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
    }
    expect(inSidebar(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(controller.index, 1);
    expect(inSidebar(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(controller.index, 1, reason: 'the disabled tab is skipped');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    expect(controller.index, 0);
    expect(inSidebar(), isTrue);
  });

  testWidgets('an arrow on the tab bar selects a tab not built yet and keeps '
      'the focus on the bar', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    bool onBar() {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused != null &&
          focused.findAncestorWidgetOfExactType<GlassTabBar>() != null;
    }

    for (var i = 0; i < 10 && !onBar(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
    }
    expect(onBar(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(controller.index, 1);
    expect(onBar(), isTrue);
  });

  testWidgets('a tap on the selected tab calls its onReselect instead of '
      'popping its pages', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var reselected = 0;
    await _pump(tester, controller, _phone, onReselect: () => reselected++);
    await tester.tap(find.text('One page'));
    await _settle(tester);
    expect(controller.pagesOf(0), hasLength(1));
    await tester.tap(find.text('One').last);
    await _settle(tester);
    expect(reselected, 1);
    expect(controller.pagesOf(0), hasLength(1));
  });

  testWidgets('a row of the sidebar calls onReselect too, but a row that '
      'closes the search over its tab does not', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    var reselected = 0;
    await _pump(
      tester,
      controller,
      _landscape,
      search: search,
      onReselect: () => reselected++,
    );
    Finder row(String title) => find.descendant(
      of: find.byType(GlassTabSidebar),
      matching: find.text(title),
    );
    await tester.tap(row('One'));
    await _settle(tester);
    expect(reselected, 1);
    search.openView();
    await _settle(tester);
    await tester.tap(row('One'));
    await _settle(tester);
    expect(search.isOpen, isFalse);
    expect(controller.index, 0);
    expect(reselected, 1);
  });

  testWidgets('a split view toggles its primary column with the key, and '
      'collapsed leaves the key to the commands above', (tester) async {
    final controller = GlassSplitViewController();
    addTearDown(controller.dispose);
    var heard = 0;
    Future<void> pump(Size size) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, _) => GlassScope(
            renderer: const FlatGlassRenderer(),
            child: InputCommands(
              actions: {
                GlassToggleSidebarIntent:
                    CallbackAction<GlassToggleSidebarIntent>(
                      onInvoke: (_) => heard++,
                    ),
              },
              child: GlassSplitView(
                controller: controller,
                primary: const Focus(autofocus: true, child: Text('primary')),
                secondary: const Text('secondary'),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    await pump(_landscape);
    await _toggle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isFalse);
    expect(heard, 0);
    await _toggle(tester);
    expect(controller.isShowing(GlassSplitViewColumn.primary), isTrue);
    await pump(_phone);
    expect(controller.isCollapsed, isTrue);
    await _toggle(tester);
    expect(heard, 1);
  });
}
