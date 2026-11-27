import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// An iPhone 16 Pro: 402 x 874, its safe area 62 at the top and 34 at the
// bottom (edit menu passport).
const _size = Size(402, 874);

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => MediaQuery(
    data: const MediaQueryData(
      size: _size,
      padding: EdgeInsets.only(top: 62, bottom: 34),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: Overlay(
          key: UniqueKey(),
          initialEntries: [OverlayEntry(builder: (context) => child)],
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = _size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Rect _bar(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(GlassEditMenu),
        matching: find.byType(GlassSurface),
      )
      .first,
);

GlassEditMenu _menu({
  required Offset at,
  List<ContextMenuButtonItem>? items,
}) => GlassEditMenu(
  anchorAbove: at,
  anchorBelow: at + const Offset(0, 20),
  buttonItems:
      items ??
      [
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {},
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {},
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {},
        ),
      ],
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the menu is 44 tall, its glass 4 past cells 16 a side '
      'around their titles, 15 under its anchor in the upper half and '
      'centered on it', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_menu(at: const Offset(201, 300))));
    await _settle(tester);
    final bar = _bar(tester);
    expect(bar.height, 44);
    expect(bar.top, 320 + 15);
    expect(bar.center.dx, moreOrLessEquals(201, epsilon: 0.5));
    final titles = ['Cut', 'Copy', 'Paste'];
    final cells = [
      for (final title in titles) tester.getSize(find.text(title)).width + 32,
    ];
    expect(bar.width, moreOrLessEquals(8 + cells.reduce((a, b) => a + b)));
    expect(tester.getRect(find.text('Cut')).left, bar.left + 4 + 16);
  });

  testWidgets('in the lower half of the safe area it stands 15 over its '
      'anchor, and inside the safe area where the anchor runs out', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_menu(at: const Offset(201, 600))));
    await _settle(tester);
    expect(_bar(tester).bottom, 600 - 15);

    await tester.pumpWidget(_app(_menu(at: const Offset(10, 70))));
    await _settle(tester);
    expect(_bar(tester).top, 90 + 15);
    expect(_bar(tester).left, 8);
  });

  testWidgets('it opens from a fifth of its size, fading in', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_menu(at: const Offset(201, 300))));
    final transition = tester.widget<MotionTransition>(
      find
          .descendant(
            of: find.byType(GlassEditMenu),
            matching: find.byType(MotionTransition),
          )
          .first,
    );
    expect(transition.scale!.value, moreOrLessEquals(0.2, epsilon: 0.05));
    expect(transition.opacity!.value, lessThan(0.1));
    expect(transition.alignment, Alignment.topCenter);
    await _settle(tester);
    expect(transition.scale!.value, moreOrLessEquals(1, epsilon: 0.01));
    expect(transition.opacity!.value, moreOrLessEquals(1, epsilon: 0.01));
  });

  testWidgets('a tap runs its item; an item without an action is gray and '
      'takes none', (tester) async {
    await _phone(tester);
    final pressed = <String>[];
    await tester.pumpWidget(
      _app(
        _menu(
          at: const Offset(201, 300),
          items: [
            ContextMenuButtonItem(
              label: 'Copy',
              onPressed: () => pressed.add('Copy'),
            ),
            const ContextMenuButtonItem(label: 'Paste', onPressed: null),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.delete,
              label: 'Delete',
              onPressed: () => pressed.add('Delete'),
            ),
          ],
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Copy'));
    await tester.tap(find.text('Paste'), warnIfMissed: false);
    await tester.pump();
    expect(pressed, ['Copy']);
    Color colorOf(String title) =>
        tester.widget<Text>(find.text(title)).style!.color!;
    expect(
      colorOf('Delete').toARGB32(),
      GlassColors.systemRed.color.toARGB32(),
    );
    expect(colorOf('Paste').a, lessThan(1));
  });

  testWidgets('items that do not fit stand behind a forward button, which '
      'turns the menu into a list of them all, 250 wide', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        _menu(
          at: const Offset(201, 300),
          items: [
            for (var i = 1; i <= 9; i++)
              ContextMenuButtonItem(label: 'Item $i', onPressed: () {}),
          ],
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Item 9'), findsNothing);
    expect(_bar(tester).width, lessThanOrEqualTo(402 - 16));
    await tester.tap(find.bySemanticsLabel('More'));
    await _settle(tester);
    for (var i = 1; i <= 9; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    expect(_bar(tester).width, 250);
  });

  testWidgets('a text field off iOS shows the glass edit menu on a double '
      'tap', (tester) async {
    final controller = TextEditingController(text: 'Hello world');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Center(
          child: SizedBox(
            width: 300,
            child: GlassTextField(controller: controller),
          ),
        ),
      ),
    );
    final word =
        tester.getTopLeft(find.byType(EditableText)) + const Offset(15, 11);
    await tester.tapAt(word);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(word);
    await _settle(tester);
    expect(find.byType(GlassEditMenu), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await _settle(tester);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
