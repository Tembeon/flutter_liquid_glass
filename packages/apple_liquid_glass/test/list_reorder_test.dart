import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _List extends StatefulWidget {
  const _List({this.editing = true, this.reorders = true, this.grips = true});

  final bool editing;
  final bool reorders;
  final bool grips;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  List<String> ids = ['One', 'Two', 'Three', 'Four'];
  final List<(int, int)> moves = [];

  void reorder(int from, int to) {
    moves.add((from, to));
    setState(() => ids.insert(to, ids.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: const MediaQueryData(size: Size(402, 874)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: GlassListEditing(
          editing: widget.editing,
          child: CustomScrollView(
            slivers: [
              GlassSliverListSection(
                ids: ids,
                itemCount: ids.length,
                onReorderItem: widget.reorders ? reorder : null,
                itemBuilder: (context, i) => GlassListRow(
                  key: ValueKey(ids[i]),
                  title: Text(ids[i]),
                  detail: const Text('94'),
                  showsReorderControl: widget.grips,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder _row(String id) => find.byKey(ValueKey(id));

Finder _grip(String id) =>
    find.descendant(of: _row(id), matching: find.byType(RawGlassReorderHandle));

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

Finder _shadowOf(String id) => find
    .ancestor(
      of: _row(id),
      matching: find.byWidgetPredicate(
        (widget) => '${widget.runtimeType}' == '_LiftShadow',
      ),
    )
    .first;

PaintPattern get _lifted => paints
  ..something(
    (method, arguments) =>
        method == #drawRRect && (arguments[1] as Paint).maskFilter != null,
  );

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('in editing each row shows the grip 27 wide, its end 20 from '
      "the card's edge, and its value ends 8 before it", (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final row = tester.getRect(_row('One'));
    final grip = tester.getRect(_grip('One'));
    expect(grip.right, row.right);
    expect(grip.width, 47);
    expect(row.right - tester.getRect(find.text('94').first).right, 55);
    final glyph = tester.getRect(
      find.descendant(of: _grip('One'), matching: find.byType(CustomPaint)),
    );
    expect(glyph.left, grip.left);
    expect(glyph.size, const Size(27, 15));
    expect(glyph.center.dy, row.center.dy);
    expect(tester.getTopLeft(find.text('One')).dx - row.left, 20);
  });

  testWidgets('no grip out of editing, without onReorderItem, or on a row '
      'that hides it', (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List(editing: false));
    expect(find.byType(RawGlassReorderHandle), findsNothing);
    _view(tester);
    await tester.pumpWidget(const _List(reorders: false));
    expect(find.byType(RawGlassReorderHandle), findsNothing);
    expect(tester.getRect(find.text('94').first).right, 386 - 20);
    _view(tester);
    await tester.pumpWidget(const _List(grips: false));
    expect(find.byType(RawGlassReorderHandle), findsNothing);
  });

  testWidgets('a touch on the grip lifts the row at once; it follows the '
      'finger, and a row gives way on the table spring once the held '
      "row's center passes the edge it will stand on", (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final one = tester.getRect(_row('One'));
    final two = tester.getRect(_row('Two'));
    final finger = await tester.startGesture(tester.getCenter(_grip('One')));
    await tester.pump();
    expect(_shadowOf('One'), _lifted);
    await finger.moveBy(const Offset(0, 20));
    await tester.pump(_frame);
    expect(tester.getRect(_row('One')).top, one.top + 20);
    await _frames(tester, 3);
    expect(tester.getRect(_row('Two')).top, two.top);
    await finger.moveBy(const Offset(0, 8));
    await tester.pump(_frame);
    expect(tester.getRect(_row('One')).top, one.top + 28);
    final start = tester.binding.clock.now();
    await _frames(tester, 6);
    final t = tester.binding.clock.now().difference(start).inMicroseconds / 1e6;
    const omega = 2 * math.pi / 0.3;
    final expected =
        one.top + one.height * (1 + omega * t) * math.exp(-omega * t);
    expect(
      tester.getRect(_row('Two')).top,
      moreOrLessEquals(expected, epsilon: 2.5),
    );
    await _frames(tester, 40);
    expect(tester.getRect(_row('Two')).top, one.top);
    expect(tester.getRect(_row('One')).top, one.top + 28);
    await finger.up();
    await _frames(tester, 60);
    final state = tester.state<_ListState>(find.byType(_List));
    expect(state.moves, [(0, 1)]);
    expect(state.ids, ['Two', 'One', 'Three', 'Four']);
    expect(tester.getRect(_row('One')).top, one.top + two.height);
    expect(_shadowOf('One'), isNot(_lifted));
  });

  testWidgets('a dropped row lands on a critically damped spring of 0.0085 s '
      'a point, its shadow falling with it', (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final one = tester.getRect(_row('One'));
    final finger = await tester.startGesture(tester.getCenter(_grip('One')));
    await tester.pump();
    await finger.moveBy(const Offset(0, 20));
    await tester.pump(_frame);
    await finger.up();
    await tester.pump();
    final start = tester.binding.clock.now();
    await _frames(tester, 4);
    final t = tester.binding.clock.now().difference(start).inMicroseconds / 1e6;
    const omega = 2 * math.pi / (20 * 0.0085);
    final expected = one.top + 20 * (1 + omega * t) * math.exp(-omega * t);
    expect(
      tester.getRect(_row('One')).top,
      moreOrLessEquals(expected, epsilon: 1.5),
    );
    expect(
      tester.state<_ListState>(find.byType(_List)).moves,
      isEmpty,
    );
    await _frames(tester, 30);
    expect(tester.getRect(_row('One')).top, one.top);
    expect(_shadowOf('One'), isNot(_lifted));
  });

  testWidgets('dragged down and back up past the same edge the row keeps '
      'its place and nothing is reordered', (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final two = tester.getRect(_row('Two'));
    final finger = await tester.startGesture(tester.getCenter(_grip('Two')));
    await tester.pump();
    await finger.moveBy(const Offset(0, 40));
    await _frames(tester, 30);
    expect(tester.getRect(_row('Three')).top, two.top);
    await finger.moveBy(const Offset(0, -80));
    await _frames(tester, 30);
    expect(tester.getRect(_row('One')).top, two.top);
    await finger.moveBy(const Offset(0, 40));
    await _frames(tester, 30);
    await finger.up();
    await _frames(tester, 40);
    final state = tester.state<_ListState>(find.byType(_List));
    expect(state.moves, isEmpty);
    expect(tester.getRect(_row('Two')).top, two.top);
  });

  testWidgets('the grip holds the touch against the scroll around the list', (
    tester,
  ) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    final finger = await tester.startGesture(tester.getCenter(_grip('One')));
    for (var i = 0; i < 10; i++) {
      await finger.moveBy(const Offset(0, -12));
      await tester.pump(_frame);
    }
    expect(scroll.position.pixels, 0);
    await finger.up();
    await _frames(tester, 40);
  });

  testWidgets('leaving editing during a drag puts the rows back without a '
      'call', (tester) async {
    _view(tester);
    await tester.pumpWidget(const _List());
    final one = tester.getRect(_row('One'));
    final finger = await tester.startGesture(tester.getCenter(_grip('One')));
    await tester.pump();
    await finger.moveBy(const Offset(0, 60));
    await _frames(tester, 30);
    _view(tester);
    await tester.pumpWidget(const _List(editing: false));
    await _frames(tester, 40);
    await finger.up();
    await _frames(tester, 10);
    expect(tester.state<_ListState>(find.byType(_List)).moves, isEmpty);
    expect(tester.getRect(_row('One')).top, one.top);
    expect(_shadowOf('One'), isNot(_lifted));
  });

  testWidgets('a screen reader reads Reorder on the row, with move up and '
      'move down actions', (tester) async {
    final semantics = tester.ensureSemantics();
    _view(tester);
    await tester.pumpWidget(const _List());
    final node = tester.getSemantics(_row('Two'));
    final data = node.getSemanticsData();
    expect(data.label, contains('Reorder'));
    final labels = {
      for (final id in data.customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label,
    };
    expect(labels, {'Move up', 'Move down'});
    final down = data.customSemanticsActionIds!.firstWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == 'Move down',
    );
    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      down,
    );
    await _frames(tester, 40);
    expect(tester.state<_ListState>(find.byType(_List)).moves, [(1, 2)]);
    semantics.dispose();
  });
}
