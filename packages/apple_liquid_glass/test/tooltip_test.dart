import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _button = Key('button');
const _under = Key('under');

Widget _app({
  required List<String> log,
  Alignment at = const Alignment(0, -0.5),
  bool tooltip = true,
}) {
  Widget button = GestureDetector(
    key: _button,
    onTap: () => log.add('button'),
    child: const SizedBox(
      width: 44,
      height: 44,
      child: ColoredBox(color: Color(0xFF3478F6)),
    ),
  );
  if (tooltip) {
    button = GlassTooltip(
      message: 'New letter',
      shortcut: const Text('N'),
      child: button,
    );
  }
  return WidgetsApp(
    color: const Color(0xFF000000),
    builder: (context, _) => GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: _under,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => log.add('under'),
                  ),
                ),
                Align(alignment: at, child: button),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void _screen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _wait(WidgetTester tester, int milliseconds) async {
  for (var t = 0; t < milliseconds; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder get _tip => find.text('New letter');

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a mouse resting half a second shows the hint 6 below the '
      'child, centered, with its shortcut after the message', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app(log: []));
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_button)));
    await _wait(tester, 400);
    expect(_tip, findsNothing);
    await _wait(tester, 200);
    expect(_tip, findsOneWidget);
    final button = tester.getRect(find.byKey(_button));
    final panel = tester.getRect(
      find.ancestor(of: _tip, matching: find.byType(GlassSurface)),
    );
    expect(panel.top, button.bottom + 6);
    expect(panel.center.dx, closeTo(button.center.dx, 1e-9));
    expect(
      tester.getTopLeft(find.text('N')).dx,
      greaterThan(tester.getTopRight(_tip).dx),
    );
  });

  testWidgets('the hint leaves when the mouse leaves or presses, and a click '
      'reaches what lies under it', (tester) async {
    _screen(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log: log));
    final mouse = await _mouse(tester);
    final center = tester.getCenter(find.byKey(_button));
    await mouse.moveTo(center);
    await _wait(tester, 600);
    final panel = tester.getRect(
      find.ancestor(of: _tip, matching: find.byType(GlassSurface)),
    );
    await mouse.moveTo(panel.center);
    await tester.pump();
    expect(_tip, findsNothing);
    await mouse.down(panel.center);
    await mouse.up();
    await tester.pump();
    expect(log, ['under']);

    await mouse.moveTo(center);
    await _wait(tester, 600);
    expect(_tip, findsOneWidget);
    await mouse.down(center);
    await mouse.up();
    await tester.pump();
    expect(_tip, findsNothing);
    expect(log, ['under', 'button']);
    await _wait(tester, 600);
    expect(_tip, findsNothing, reason: 'a press waits for the mouse to leave');
  });

  testWidgets('a touch shows nothing', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app(log: []));
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(_button)),
    );
    await _wait(tester, 800);
    expect(_tip, findsNothing);
    await touch.up();
  });

  testWidgets('a child near the bottom gets its hint above it', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_app(log: [], at: Alignment.bottomCenter));
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_button)));
    await _wait(tester, 600);
    final button = tester.getRect(find.byKey(_button));
    final panel = tester.getRect(
      find.ancestor(of: _tip, matching: find.byType(GlassSurface)),
    );
    expect(panel.bottom, button.top - 6);
  });

  testWidgets('screen readers read the message as the tooltip of the child '
      'and do not read the hint', (tester) async {
    _screen(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(log: []));
    expect(
      find.semantics.byPredicate((node) => node.tooltip == 'New letter'),
      findsOne,
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_button)));
    await _wait(tester, 600);
    expect(find.semantics.byLabel('New letter'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a glass button under a tooltip reads as one button named by '
      'the message', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Center(
                  child: GlassTooltip(
                    message: 'New letter',
                    child: GlassButton(
                      onPressed: () {},
                      child: const SizedBox.square(dimension: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final node = find.semantics.byPredicate(
      (node) => node.tooltip == 'New letter',
    );
    expect(node, findsOne);
    expect(
      node.evaluate().single.flagsCollection.isButton,
      isTrue,
      reason: 'the tooltip names the button, not a node around it',
    );
    semantics.dispose();
  });

  testWidgets('a closed tooltip puts no layer around its child', (
    tester,
  ) async {
    _screen(tester);
    List<Type> layers() => [
      for (final layer in tester.layers) layer.runtimeType,
    ];
    await tester.pumpWidget(_app(log: [], tooltip: false));
    final plain = layers();
    await tester.pumpWidget(_app(log: []));
    expect(layers(), plain);
  });

  testWidgets('a tooltip adds no Tab stop and takes no focus from a click', (
    tester,
  ) async {
    _screen(tester);
    Widget page({required bool tooltip}) {
      Widget button(String name) => GlassButton(
        key: Key(name),
        onPressed: () {},
        child: Text(name),
      );
      return WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tooltip)
                GlassTooltip(message: 'First', child: button('a'))
              else
                button('a'),
              button('b'),
            ],
          ),
        ),
      );
    }

    Key? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<GlassButton>()
        ?.key;

    Future<List<Key?>> walk() async {
      final stops = <Key?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        stops.add(focused());
      }
      return stops;
    }

    await tester.pumpWidget(page(tooltip: false));
    final plain = await walk();
    expect(plain, contains(const Key('a')));
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    final plainClick = focused();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page(tooltip: true));
    expect(await walk(), plain);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(focused(), plainClick);
  });
}
