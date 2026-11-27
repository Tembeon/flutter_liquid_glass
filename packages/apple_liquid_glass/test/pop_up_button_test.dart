import 'package:apple_liquid_glass/apple_liquid_glass.dart';
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
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
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

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a pop-up button shows the chosen title and its chevrons 4 '
      'after it, and a row chosen from its menu is reported', (tester) async {
    await _phone(tester);
    final chosen = <String>[];
    await tester.pumpWidget(
      _app(
        Center(
          child: GlassPopUpButton<String>(
            value: 'one',
            items: const [
              GlassPopUpItem(value: 'one', title: 'One'),
              GlassPopUpItem(value: 'two', title: 'Two'),
            ],
            onChanged: chosen.add,
          ),
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(find.text('One'));
    final chevrons = tester.getRect(
      find
          .descendant(
            of: find.byType(GlassPopUpButton<String>),
            matching: find.byType(CustomPaint),
          )
          .last,
    );
    expect(chevrons.width, moreOrLessEquals(12.33, epsilon: 0.01));
    expect(chevrons.height, moreOrLessEquals(14.67, epsilon: 0.01));
    expect(chevrons.left - title.right, moreOrLessEquals(4, epsilon: 0.01));
    await tester.tap(find.text('One'));
    await _settle(tester);
    expect(find.text('Two'), findsOneWidget);
    await tester.tap(find.text('Two'));
    await _settle(tester);
    expect(chosen, ['two']);
  });

  testWidgets("a title menu's circle stands 6 after the title, the two "
      'centered as one block, and a tap on the title opens the menu', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        const GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: Text('Inbox'),
            titleMenu: [GlassMenuItem(title: 'Rename')],
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(find.text('Inbox'));
    final block = tester.getRect(find.byType(RawGlassButton));
    expect(block.width, moreOrLessEquals(title.width + 6 + 20, epsilon: 0.01));
    expect(block.center.dx, moreOrLessEquals(201, epsilon: 0.5));
    await tester.tap(find.text('Inbox'));
    await _settle(tester);
    expect(find.text('Rename'), findsOneWidget);
  });
}
