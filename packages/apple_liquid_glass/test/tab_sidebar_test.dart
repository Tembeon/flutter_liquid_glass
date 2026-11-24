import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _top = 20.0;
const _bottom = 20.0;
const _height = 600.0;

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  bool header = true,
  bool footer = true,
  bool actionFirst = true,
  bool glass = true,
  VoidCallback? onToggle,
  ValueChanged<int>? onSelected,
}) async {
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      builder: (context, _) => GlassScope(
        renderer: const FlatGlassRenderer(),
        child: MediaQuery(
          data:
              MediaQuery.of(
                context,
              ).copyWith(
                padding: const EdgeInsets.only(top: _top, bottom: _bottom),
              ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: _height,
              child: GlassTabSidebar(
                destinations: const [
                  GlassTabDestination(
                    icon: SizedBox.square(dimension: 24),
                    label: Text('One'),
                  ),
                  GlassTabDestination(
                    icon: SizedBox.square(dimension: 24),
                    label: Text('Me'),
                    atSidebarEnd: true,
                  ),
                  GlassTabDestination(
                    icon: SizedBox.square(dimension: 24),
                    label: Text('Two'),
                  ),
                ],
                selectedIndex: 1,
                onDestinationSelected: onSelected ?? (index) {},
                header: header
                    ? const SizedBox(
                        key: ValueKey('header'),
                        height: 40,
                        child: Text('App'),
                      )
                    : null,
                footer: footer
                    ? const SizedBox(
                        key: ValueKey('footer'),
                        height: 30,
                        child: Text('Account'),
                      )
                    : null,
                action: GlassTabBarAction(
                  icon: const SizedBox.square(dimension: 24),
                  semanticLabel: 'Compose',
                  onPressed: () {},
                  atSidebarStart: actionFirst,
                ),
                onToggle: onToggle,
                glass: glass,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final _row = find.byWidgetPredicate(
  (widget) => widget is SizedBox && widget.height == 44,
);

Rect _firstRow(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(GlassTabSidebar), matching: _row).first,
);

Rect _rowOf(WidgetTester tester, String title) =>
    tester.getRect(find.ancestor(of: find.text(title), matching: _row).first);

void main() {
  testWidgets('the header stands above the rows, the action first, and the '
      'end tab and the footer at the bottom', (tester) async {
    await _pump(tester, width: 280);
    const rowsTop = _top + 63;
    expect(tester.getRect(find.byKey(const ValueKey('header'))).top, rowsTop);
    final compose = _rowOf(tester, 'Compose');
    expect(compose.top, rowsTop + 40);
    expect(compose.height, 44);
    expect(_rowOf(tester, 'One').top, compose.bottom);
    expect(_rowOf(tester, 'Two').top, compose.bottom + 44);
    final footer = tester.getRect(find.byKey(const ValueKey('footer')));
    expect(footer.bottom, _height - _bottom - 20);
    expect(_rowOf(tester, 'Me').bottom, footer.top);
    expect(compose.left, 20);
  });

  testWidgets('the action follows the tabs unless it stands first', (
    tester,
  ) async {
    await _pump(tester, width: 280, actionFirst: false, header: false);
    expect(_rowOf(tester, 'One').top, _top + 63);
    expect(_rowOf(tester, 'Compose').top, _rowOf(tester, 'Two').bottom);
  });

  testWidgets('a row selects its tab, the one at the end too', (tester) async {
    final selected = <int>[];
    await _pump(tester, width: 280, onSelected: selected.add);
    await tester.tap(find.text('Two'));
    await tester.tap(find.text('Me'));
    expect(selected, [2, 1]);
  });

  testWidgets('on the rail the header and the footer are gone, and halfway '
      'to the sidebar they show half their height', (tester) async {
    await _pump(tester, width: GlassTabLayout.defaultRailWidth);
    expect(_firstRow(tester).top, _top + 63);
    Opacity header() => tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('header')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(header().opacity, 0);
    const rail = GlassTabLayout.defaultRailWidth;
    final minimum = GlassTabLayout.defaultSidebarWidth.minimum;
    await _pump(tester, width: (rail + minimum) / 2);
    expect(_firstRow(tester).top, _top + 63 + 20);
    expect(header().opacity, 0.5);
  });

  testWidgets('the button reads Show Sidebar on the rail and Hide Sidebar '
      'on the sidebar', (tester) async {
    final handle = tester.ensureSemantics();
    var toggled = 0;
    await _pump(
      tester,
      width: GlassTabLayout.defaultRailWidth,
      onToggle: () => toggled++,
    );
    expect(find.bySemanticsLabel('Show Sidebar'), findsOneWidget);
    await _pump(tester, width: 280, onToggle: () => toggled++);
    expect(find.bySemanticsLabel('Hide Sidebar'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Hide Sidebar'));
    expect(toggled, 1);
    handle.dispose();
  });

  testWidgets('the sidebar draws its own glass unless told not to', (
    tester,
  ) async {
    Finder glass() => find.descendant(
      of: find.byType(GlassTabSidebar),
      matching: find.byType(GlassSurface),
    );
    await _pump(tester, width: 280);
    expect(glass(), findsOneWidget);
    await _pump(tester, width: 280, glass: false);
    expect(glass(), findsNothing);
  });

  testWidgets('a tab scaffold puts its sidebar header and footer in its '
      'sidebar', (tester) async {
    tester.view.physicalSize = const Size(1210, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, _) => GlassScope(
          renderer: const FlatGlassRenderer(),
          child: GlassTabScaffold(
            sidebarHeader: const Text('App'),
            sidebarFooter: const Text('Account'),
            tabs: [
              for (final name in ['One', 'Two'])
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: Text(name),
                  builder: (context) => Text('$name page'),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    for (final text in ['App', 'Account']) {
      expect(
        find.descendant(
          of: find.byType(GlassTabSidebar),
          matching: find.text(text),
        ),
        findsOneWidget,
      );
    }
  });
}
