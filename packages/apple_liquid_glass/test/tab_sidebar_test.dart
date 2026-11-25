import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
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
  GlassTabSidebarRowBuilder? rowBuilder,
  TextDirection direction = TextDirection.ltr,
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
          child: Directionality(
            textDirection: direction,
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
                  rowBuilder: rowBuilder,
                  glass: glass,
                ),
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

  testWidgets("a row builder draws every row, the action's too, as tall as "
      'it makes it; the sidebar keeps the layout, the input and the fold', (
    tester,
  ) async {
    final seen = <int?, GlassTabSidebarRowDetails>{};
    Widget row(BuildContext context, GlassTabSidebarRowDetails details) {
      seen[details.index] = details;
      return SizedBox(
        key: ValueKey('row ${details.index}'),
        height: 60,
        child: ExcludeSemantics(child: details.destination.label),
      );
    }

    final selected = <int>[];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      width: 280,
      footer: false,
      onSelected: selected.add,
      rowBuilder: row,
    );
    expect(seen.keys, unorderedEquals([null, 0, 1, 2]));
    expect(find.byType(GlassTabSidebarRow), findsNothing);
    expect(
      [
        for (final i in [0, 1, 2]) seen[i]!.selected,
      ],
      [
        false,
        true,
        false,
      ],
    );
    expect(seen[null]!.destination.label, isA<Text>());
    final open = seen[0]!;
    expect(open.open, 1);
    const sidebar = GlassTabLayout.defaultSidebarWidth;
    expect(open.openWidth, sidebar.minimum - sidebar.preferred + 244);

    Rect rect(int? index) => tester.getRect(find.byKey(ValueKey('row $index')));
    const rowsTop = _top + 63 + 40;
    expect(rect(null), const Rect.fromLTWH(20, rowsTop, 244, 60));
    expect(rect(0).top, rowsTop + 60);
    expect(rect(2).top, rowsTop + 120);
    expect(rect(1).bottom, _height - _bottom - 20);

    await tester.tap(find.text('Two'));
    await tester.tap(find.text('Me'));
    expect(selected, [2, 1]);
    expect(find.bySemanticsLabel('Two'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: rect(2).center);
    await tester.pump();
    expect(seen[2]!.states.value, contains(WidgetState.hovered));
    semantics.dispose();

    await _pump(
      tester,
      width: GlassTabLayout.defaultRailWidth,
      footer: false,
      rowBuilder: row,
    );
    expect(seen[0]!.open, 0);
    expect(rect(0).width, 44);
  });

  testWidgets('a control inside a row takes its own tap and stays readable, '
      'and leaves the tab unselected', (tester) async {
    final taps = <String>[];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      width: 280,
      onSelected: (index) => taps.add('tab $index'),
      rowBuilder: (context, details) => SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(child: ExcludeSemantics(child: details.destination.label)),
            if (details.index == 2)
              GlassButton(
                onPressed: () => taps.add('add'),
                semanticLabel: 'Add',
                child: const Text('+'),
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('+'));
    await tester.tap(find.text('Two'));
    expect(taps, ['add', 'tab 2']);
    expect(find.bySemanticsLabel('Add'), findsOneWidget);
    expect(find.bySemanticsLabel('Two'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the default row centers its glyph 30 from its start, 22 on '
      'the rail, and starts its title 54 from it, either way round', (
    tester,
  ) async {
    final glyph = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.width == 24,
    );
    Rect glyphOf(String title) => tester.getRect(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(GlassTabSidebarRow),
        ),
        matching: glyph,
      ),
    );

    await _pump(tester, width: 280);
    final row = _rowOf(tester, 'One');
    expect(glyphOf('One').center, Offset(row.left + 30, row.center.dy));
    expect(tester.getRect(find.text('One')).left, row.left + 54);

    await _pump(tester, width: 280, direction: TextDirection.rtl);
    final rtl = _rowOf(tester, 'One');
    expect(glyphOf('One').center, Offset(rtl.right - 30, rtl.center.dy));
    expect(tester.getRect(find.text('One')).right, rtl.right - 54);

    await _pump(tester, width: GlassTabLayout.defaultRailWidth);
    final rail = tester.getRect(
      find
          .descendant(
            of: find.byType(GlassTabSidebar),
            matching: find.byType(GlassTabSidebarRow),
          )
          .at(1),
    );
    expect(rail.width, 44);
    expect(
      tester
          .getRect(
            find.descendant(
              of: find
                  .descendant(
                    of: find.byType(GlassTabSidebar),
                    matching: find.byType(GlassTabSidebarRow),
                  )
                  .at(1),
              matching: glyph,
            ),
          )
          .center,
      rail.center,
    );
  });

  testWidgets('a row builder can stack its own parts over the default row', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 280,
      rowBuilder: (context, details) => Stack(
        children: [
          GlassTabSidebarRow(details: details),
          if (details.index == 2)
            const PositionedDirectional(end: 12, top: 12, child: Text('9')),
        ],
      ),
    );
    expect(find.byType(GlassTabSidebarRow), findsNWidgets(4));
    expect(_rowOf(tester, 'Two').height, 44);
    expect(
      tester.getRect(find.text('9')).right,
      _rowOf(tester, 'Two').right - 12,
    );
  });

  testWidgets('a tab scaffold puts its sidebar header, footer and rows in '
      'its sidebar', (tester) async {
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
            sidebarRowBuilder: (context, details) =>
                Text('Row ${details.index}'),
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
    for (final text in ['App', 'Account', 'Row 0', 'Row 1']) {
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
