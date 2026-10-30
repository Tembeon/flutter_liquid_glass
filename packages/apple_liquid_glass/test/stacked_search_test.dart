import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  TextEditingController search,
  ScrollController scroll, {
  double keyboard = 0,
}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(402, 874),
    devicePixelRatio: 3,
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: GlassPageScaffold(
        navigationBar: GlassNavigationBar(
          largeTitle: const Text('Notes'),
          searchField: GlassSearchField(
            key: const Key('field'),
            controller: search,
          ),
        ),
        child: GlassContentScroll(
          child: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 50, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Rect _field(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('field')));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('at rest the field stands under the large title, 44 points '
      'tall, 16 from the sides and 10 above the content', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    expect(_field(tester), const Rect.fromLTRB(16, 168, 386, 212));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222);
  });

  testWidgets('the field keeps its placeholder out of its glass, which a '
      'surface fades with its content', (tester) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    final placeholder = find.descendant(
      of: find.byKey(const Key('field')),
      matching: find.byType(Text),
    );
    expect(placeholder, findsOneWidget);
    expect(
      find.ancestor(of: placeholder, matching: find.byType(GlassSurface)),
      findsNothing,
    );
  });

  testWidgets('a scroll folds the field away before the large title moves', (
    tester,
  ) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    final title = find.text('Notes').last;
    final rest = tester.getTopLeft(title).dy;
    scroll.jumpTo(30);
    await tester.pump();
    expect(tester.getTopLeft(title).dy, rest);
    await tester.tapAt(_field(tester).center);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
      reason: 'a field folded past half takes no touch',
    );
    scroll.jumpTo(80);
    await tester.pump();
    expect(tester.getTopLeft(title).dy, rest - (80 - 54));
  });

  testWidgets('focused, the page rises until the field sits under the status '
      'bar, the field narrows and the close button ends the search', (
    tester,
  ) async {
    await _phone(tester);
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(search, scroll));
    await tester.pump();
    await tester.tap(find.byKey(const Key('field')));
    await _settle(tester);
    expect(_field(tester), const Rect.fromLTRB(16, 62, 332, 106));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222 - 106);
    final close = find.bySemanticsLabel('Close');
    expect(tester.getCenter(close).dx, closeTo(386 - 22, 1));
    search.text = 'milk';
    await tester.tap(close);
    await _settle(tester);
    expect(search.text, isEmpty);
    expect(_field(tester), const Rect.fromLTRB(16, 168, 386, 212));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 222);
  });
}
