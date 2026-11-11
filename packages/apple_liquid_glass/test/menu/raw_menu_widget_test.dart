import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  Future<List<String>> pumpMenu(
    WidgetTester tester, {
    VoidCallback? onPressed,
    GlassMenuStyle? style,
    GlassMenuStyle? themeStyle,
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
        builder: (context, child) => GlassRendererScope(
          renderer: const GlassRenderer.flat(),
          child: GlassTheme(
            data: GlassThemeData(
              menuStyle: themeStyle,
            ),
            child: child!,
          ),
        ),
        home: Center(
          child: RawGlassMenu(
            key: const Key('source'),
            onPressed: onPressed,
            style: style,
            entries: [
              for (final title in ['Copy', 'Share'])
                GlassMenuItem(title: title, onPressed: () => log.add(title)),
              GlassMenuItem(
                title: 'Delete',
                destructive: true,
                onPressed: () => log.add('Delete'),
              ),
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

  testWidgets('the theme styles the rows and the menu style overrides it', (
    tester,
  ) async {
    Color? color(String title) => tester
        .renderObject<RenderParagraph>(find.text(title))
        .text
        .style
        ?.color;
    await pumpMenu(
      tester,
      themeStyle: const GlassMenuStyle(
        textStyle: TextStyle(color: Color(0xFF00AA00)),
        destructiveColor: Color(0xFFAA00AA),
      ),
      style: const GlassMenuStyle(destructiveColor: Color(0xFF0000AA)),
    );
    await tester.tap(find.byKey(const Key('source')));
    await settle(tester);
    expect(color('Copy'), const Color(0xFF00AA00));
    expect(color('Delete'), const Color(0xFF0000AA));
  });
}
