import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(devicePixelRatio: 3),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 402, child: child),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

final _marks = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == '_EditMark',
);

Rect _markBox(WidgetTester tester, int index) => tester.getRect(
  find
      .descendant(of: _marks.at(index), matching: find.byType(CustomPaint))
      .last,
);

void main() {
  setUp(MotionClock.debugReset);

  for (final (layout, inset) in [
    (GlassListLayout.insetGrouped, 20.0),
    (GlassListLayout.grouped, 16.0),
    (GlassListLayout.plain, 16.0),
  ]) {
    testWidgets('editing in a ${layout.name} list puts the text at 60, the '
        'control 19.17 in and the separator from the text to $inset before '
        'the end, and hides the accessories', (tester) async {
      await tester.pumpWidget(
        _app(
          GlassListEditing(
            editing: true,
            child: GlassListSection(
              layout: layout,
              children: [
                GlassListRow(
                  title: const Text('One'),
                  accessory: GlassListAccessory.disclosureIndicator,
                  trailing: const SizedBox(key: Key('switch'), width: 51),
                  onDelete: () {},
                ),
                GlassListRow(title: const Text('Two'), onDelete: () {}),
              ],
            ),
          ),
        ),
      );
      final row = tester.getRect(find.byType(GlassListRow).first);
      expect(tester.getTopLeft(find.text('One')).dx - row.left, 60);
      final box = _markBox(tester, 0);
      expect(box.left - row.left, moreOrLessEquals(19.17));
      expect(box.width, moreOrLessEquals(25.67));
      expect(box.height, moreOrLessEquals(25.67));
      expect(box.center.dy, moreOrLessEquals(row.center.dy));
      expect(find.byKey(const Key('switch')), findsNothing);
      expect(
        find.byType(GlassListRow).first,
        paints..something((method, arguments) {
          if (method != #drawRect) return false;
          final rect = arguments[0] as Rect;
          return rect.height == 1 &&
              rect.left == 60 &&
              rect.right == row.width - inset;
        }),
      );
    });
  }

  testWidgets('a symbol moves the text 40 further past the control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        GlassListEditing(
          editing: true,
          child: GlassListSection(
            children: [
              GlassListRow(
                leading: const Icon(IconData(0x41)),
                title: const Text('One'),
                onDelete: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byType(GlassListRow));
    expect(tester.getTopLeft(find.text('One')).dx - row.left, 100);
  });

  testWidgets('the minus reveals the Delete action, whose tap deletes; the '
      'row takes no press while editing', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        GlassListEditing(
          editing: true,
          child: GlassListSection(
            children: [
              GlassListRow(
                title: const Text('One'),
                onPressed: () => log.add('pressed'),
                onDelete: () => log.add('deleted'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('One'));
    await _settle(tester);
    expect(log, isEmpty);
    expect(find.text('Delete'), findsNothing);
    await tester.tapAt(_markBox(tester, 0).center);
    await _settle(tester);
    expect(find.text('Delete'), findsOneWidget);
    final row = tester.getRect(find.byType(GlassListRow));
    expect(tester.getRect(find.text('Delete')).right, lessThan(row.right));
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(log, ['deleted']);
  });

  testWidgets('the plus inserts; out of editing the row presses as before', (
    tester,
  ) async {
    final log = <String>[];
    Widget list({required bool editing}) => _app(
      GlassListEditing(
        editing: editing,
        child: GlassListSection(
          children: [
            GlassListRow(
              title: const Text('One'),
              onPressed: () => log.add('pressed'),
              onInsert: () => log.add('inserted'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(list(editing: true));
    await tester.tapAt(_markBox(tester, 0).center);
    await _settle(tester);
    expect(log, ['inserted']);
    await tester.pumpWidget(list(editing: false));
    expect(_marks, findsNothing);
    final row = tester.getRect(find.byType(GlassListRow));
    expect(tester.getTopLeft(find.text('One')).dx - row.left, 20);
    await tester.tap(find.text('One'));
    await _settle(tester);
    expect(log, ['inserted', 'pressed']);
  });

  testWidgets('the controls read as Delete and Insert buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassListEditing(
          editing: true,
          child: GlassListSection(
            children: [
              GlassListRow(title: const Text('One'), onDelete: () {}),
              GlassListRow(title: const Text('Two'), onInsert: () {}),
            ],
          ),
        ),
      ),
    );
    for (final label in ['Delete', 'Insert']) {
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
    semantics.dispose();
  });

  testWidgets('selecting editing toggles a row by its value on a tap, one '
      'selection across sections, and fills a selected row', (tester) async {
    var selection = <Object>{'b'};
    Widget list() => _app(
      StatefulBuilder(
        builder: (context, setState) => GlassListEditing(
          editing: true,
          selection: selection,
          onSelectionChanged: (value) => setState(() => selection = value),
          child: Column(
            children: [
              GlassListSection(
                children: [
                  GlassListRow(
                    title: const Text('A'),
                    value: 'a',
                    onDelete: () {},
                  ),
                  const GlassListRow(title: Text('B'), value: 'b'),
                ],
              ),
              const GlassListSection(
                children: [GlassListRow(title: Text('C'), value: 'c')],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(list());
    expect(_marks, findsNWidgets(3));
    final row = tester.getRect(find.byType(GlassListRow).first);
    expect(tester.getTopLeft(find.text('A')).dx - row.left, 60);
    expect(
      find.byType(GlassListRow).at(1),
      paints..path(color: const Color(0xFFD1D1D6)),
    );
    expect(
      find.byType(GlassListRow).first,
      isNot(paints..path(color: const Color(0xFFD1D1D6))),
    );
    await tester.tap(find.text('A'));
    await _settle(tester);
    await tester.tap(find.text('C'));
    await _settle(tester);
    expect(selection, {'a', 'b', 'c'});
    await tester.tap(find.text('B'));
    await _settle(tester);
    expect(selection, {'a', 'c'});
    expect(find.bySemanticsLabel('Delete'), findsNothing);
  });

  testWidgets('a row without a value or an edit callback keeps its own '
      'layout in editing', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassListEditing(
          editing: true,
          child: GlassListSection(children: [GlassListRow(title: Text('One'))]),
        ),
      ),
    );
    expect(_marks, findsNothing);
    final row = tester.getRect(find.byType(GlassListRow));
    expect(tester.getTopLeft(find.text('One')).dx - row.left, 20);
  });
}
