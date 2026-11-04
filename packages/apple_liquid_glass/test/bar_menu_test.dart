import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Widget _app(Widget page) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: WidgetsApp(
        color: const Color(0xFFFFFFFF),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: page,
      ),
    ),
  ),
);

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  var _on = false;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(
      title: const Text('Page'),
      trailing: [
        GlassBarItem(
          icon: const SizedBox.square(key: Key('menu'), dimension: 22),
          semanticLabel: 'Look',
          menuChildren: [
            GlassMenuItem(
              title: _on ? 'On' : 'Off',
              keepsMenuOpen: true,
              onPressed: () => setState(() => _on = !_on),
            ),
            const GlassMenuItem(title: 'Other'),
          ],
        ),
        GlassBarItem(
          icon: const SizedBox.square(key: Key('plain'), dimension: 22),
          onPressed: () {},
        ),
      ],
    ),
    child: const SizedBox.expand(),
  );
}

List<double> _capsules(WidgetTester tester) => [
  for (final surface in tester.widgetList<GlassSurface>(
    find.descendant(
      of: find.byType(GlassBarView),
      matching: find.byType(GlassSurface),
    ),
  ))
    if (surface.frame!.value.rect != Rect.zero) surface.frame!.value.opacity,
];

void main() {
  setUp(MotionClock.debugReset);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const _Page()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a bar item with a menu stands in a capsule of its own', (
    tester,
  ) async {
    await phone(tester);
    expect(_capsules(tester), [1, 1]);
    final menu = tester.getCenter(find.byKey(const Key('menu')));
    final plain = tester.getCenter(find.byKey(const Key('plain')));
    expect(plain.dx - menu.dx, greaterThan(44));
  });

  testWidgets('the menu grows out of the capsule, which it replaces until it '
      'has closed, and lands on the capsule top', (tester) async {
    await phone(tester);
    final item = tester.getCenter(find.byKey(const Key('menu')));
    await tester.tapAt(item);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Off'), findsOneWidget);
    expect(_capsules(tester).where((opacity) => opacity == 0), hasLength(1));
    expect(
      tester.getTopLeft(find.text('Off')).dy,
      inInclusiveRange(62, 62 + 44),
    );
    await tester.tapAt(const Offset(40, 700));
    await _settle(tester);
    expect(find.text('Off'), findsNothing);
    expect(_capsules(tester), [1, 1]);
  });

  testWidgets('the open menu follows the entries the page declares', (
    tester,
  ) async {
    await phone(tester);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('menu'))));
    await tester.pump();
    await _settle(tester);
    await tester.tap(find.text('Off'));
    await _settle(tester);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
  });
}
