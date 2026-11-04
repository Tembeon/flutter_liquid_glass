import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  Future<List<String>> pumpMenu(
    WidgetTester tester, {
    VoidCallback? onPressed,
  }) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final log = <String>[];
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) => GlassTheme(
          data: const GlassThemeData(renderer: GlassRenderer.flat()),
          child: child!,
        ),
        home: Center(
          child: RawGlassMenu(
            key: const Key('source'),
            onPressed: onPressed,
            entries: [
              for (final title in ['Copy', 'Share'])
                GlassMenuItem(title: title, onPressed: () => log.add(title)),
            ],
            label: const Text('Label'),
            child: const SizedBox(width: 120, height: 44, child: Text('Face')),
          ),
        ),
      ),
    );
    return log;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('an app face opens the menu on a tap and chooses a row', (
    tester,
  ) async {
    final log = await pumpMenu(tester);
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    expect(log, ['Copy']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('with onPressed a tap calls it and opens no menu', (
    tester,
  ) async {
    var pressed = 0;
    await pumpMenu(tester, onPressed: () => pressed++);
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(pressed, 1);
    expect(find.text('Copy'), findsNothing);
  });
}
