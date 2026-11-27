import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _spring = Spring.response(0.4);

class _Notes extends StatefulWidget {
  const _Notes({
    required this.notes,
    this.swipe = false,
    this.animation = GlassListRowAnimation.automatic,
  });

  final List<String> notes;
  final bool swipe;
  final GlassListRowAnimation animation;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  late List<String> notes = widget.notes;
  final List<String> pressed = [];
  final List<String> actions = [];

  void change(List<String> next) => setState(() => notes = next);

  Widget _row(String note) {
    final row = GlassListRow(
      key: ValueKey(note),
      title: Text(note),
      onPressed: () => pressed.add(note),
    );
    if (!widget.swipe) return row;
    return GlassSwipeActions(
      trailing: [
        GlassSwipeAction(
          title: 'Delete',
          destructive: true,
          onPressed: () {
            actions.add('delete $note');
            withSpring(
              _spring,
              () => change([
                for (final other in notes)
                  if (other != note) other,
              ]),
            );
          },
        ),
        GlassSwipeAction(
          title: 'Flag',
          onPressed: () => actions.add('flag $note'),
        ),
      ],
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: CustomScrollView(
          slivers: [
            GlassSliverListSection(
              ids: notes,
              itemCount: notes.length,
              rowAnimation: widget.animation,
              itemBuilder: (context, i) => _row(notes[i]),
            ),
          ],
        ),
      ),
    ),
  );
}

double _top(WidgetTester tester, String note) =>
    tester.getTopLeft(find.byKey(ValueKey(note))).dy;

double _left(WidgetTester tester, String note) =>
    tester.getTopLeft(find.byKey(ValueKey(note))).dx;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  testWidgets('a row inserted inside withSpring pushes the rows below it '
      'down on a spring', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    final pitch = b - _top(tester, 'a');

    withSpring(_spring, () => list.change(['a', 'x', 'b', 'c']));
    await tester.pump(_frame);
    expect(_top(tester, 'b'), closeTo(b, 1));
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(_top(tester, 'b'), greaterThan(b + 1));
    expect(_top(tester, 'b'), lessThan(b + pitch - 1));
    await _settle(tester);
    expect(_top(tester, 'b'), closeTo(b + pitch, 0.5));
  });

  testWidgets("rows move on UIKit's table spring, critically damped at "
      '0.3, whatever spring the change came with', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    final pitch = b - _top(tester, 'a');
    withSpring(_spring, () => list.change(['a', 'x', 'b', 'c']));
    await tester.pump(_frame);
    final start = tester.binding.clock.now();
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    final t = tester.binding.clock.now().difference(start).inMicroseconds / 1e6;
    const omega = 2 * math.pi / 0.3;
    final expected = b + pitch * (1 - (1 + omega * t) * math.exp(-omega * t));
    expect(_top(tester, 'b'), moreOrLessEquals(expected, epsilon: 2.5));
  });

  testWidgets("an inserted row comes down from one row up, as UIKit's "
      'automatic insert', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final a = _top(tester, 'a');
    final b = _top(tester, 'b');
    withSpring(_spring, () => list.change(['a', 'x', 'b']));
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, 'x'), lessThan(b - 1));
    expect(_top(tester, 'x'), greaterThan(a - 1));
    await _settle(tester);
    expect(_top(tester, 'x'), closeTo(b, 0.5));
  });

  testWidgets('a row deleted with fade fades out where it stands', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Notes(
        notes: ['a', 'b', 'c'],
        animation: GlassListRowAnimation.fade,
      ),
    );
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    withSpring(_spring, () => list.change(['a', 'c']));
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    expect(_top(tester, 'b'), closeTo(b, 0.5));
    RenderObject? box = tester.renderObject(find.byKey(const ValueKey('b')));
    int? alpha;
    while (box != null && alpha == null) {
      if (box.debugLayer case final MotionTransitionLayer layer) {
        alpha = layer.alpha;
      }
      box = box.parent;
    }
    expect(alpha, lessThan(255));
    await _settle(tester);
    expect(find.text('b'), findsNothing);
  });

  testWidgets('a deleted row stays drawn, unfaded, while the rows below it '
      "slide up over it, as UIKit's automatic delete", (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    final c = _top(tester, 'c');

    withSpring(_spring, () => list.change(['a', 'c']));
    await tester.pump(_frame);
    expect(find.text('b'), findsOneWidget);
    expect(_top(tester, 'c'), closeTo(c, 1));
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    expect(_top(tester, 'b'), closeTo(b, 0.5));
    expect(_top(tester, 'c'), lessThan(c - 1));
    await _settle(tester);
    expect(find.text('b'), findsNothing);
    expect(_top(tester, 'c'), closeTo(b, 0.5));
  });

  testWidgets('a swipe opens the trailing actions; a tap on an action '
      'performs it and closes the row', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final left = _left(tester, 'a');
    expect(find.text('Delete'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-12, 0));
      await tester.pump(_frame);
    }
    expect(_left(tester, 'a'), lessThan(left - 80));
    await gesture.up();
    await _settle(tester);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Flag'), findsOneWidget);
    final open = _left(tester, 'a');
    expect(open, lessThan(left - 150));

    await tester.tap(find.text('Flag'));
    await _settle(tester);
    expect(list.actions, ['flag a']);
    expect(list.pressed, isEmpty);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
  });

  testWidgets('a tap on an open row closes it without pressing it', (
    tester,
  ) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final left = _left(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(_left(tester, 'a'), lessThan(left - 100));

    final top = tester.getTopLeft(find.byType(GlassSwipeActions).first).dy;
    await tester.tapAt(Offset(left + 30, top + 20));
    await _settle(tester);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
    expect(list.pressed, isEmpty);
  });

  testWidgets('a full swipe performs the first action, which deletes the '
      'row', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final a = _top(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-700, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(list.actions, ['delete a']);
    expect(find.text('a'), findsNothing);
    expect(_top(tester, 'b'), closeTo(a, 0.5));
  });

  testWidgets('one row of a list is open at a time', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final left = _left(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    await tester.drag(
      find.byKey(const ValueKey('b')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
    expect(_left(tester, 'b'), lessThan(left - 100));
  });

  testWidgets('accessibility offers the actions as custom actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const _Notes(notes: ['a'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final node = tester.getSemantics(find.byType(GlassSwipeActions));
    final data = node.getSemanticsData();
    expect(data.customSemanticsActionIds, hasLength(2));
    final flag = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Flag'),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.customAction,
        viewId: tester.view.viewId,
        nodeId: node.id,
        arguments: flag,
      ),
    );
    expect(list.actions, ['flag a']);
    semantics.dispose();
  });

  int? alphaOf(WidgetTester tester, String note) {
    RenderObject? box = tester.renderObject(find.byKey(ValueKey(note)));
    while (box != null) {
      if (box.debugLayer case final MotionTransitionLayer layer) {
        return layer.alpha;
      }
      box = box.parent;
    }
    return null;
  }

  int paintIndex(WidgetTester tester, String note) {
    RenderObject? box = tester.renderObject(find.byKey(ValueKey(note)));
    while (box != null && box.debugLayer is! MotionTransitionLayer) {
      box = box.parent;
    }
    final layer = box!.debugLayer!;
    var index = 0;
    var sibling = layer.parent!.firstChild;
    while (sibling != null && !identical(sibling, layer)) {
      index++;
      sibling = sibling.nextSibling;
    }
    return index;
  }

  testWidgets('an inserted row slides out from under the row above it', (
    tester,
  ) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    withSpring(_spring, () => list.change(['a', 'x', 'b']));
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(paintIndex(tester, 'x'), lessThan(paintIndex(tester, 'a')));
    await _settle(tester);
    expect(paintIndex(tester, 'x'), greaterThan(paintIndex(tester, 'a')));
  });

  testWidgets('a deleted last row, with no row below to cover it, fades', (
    tester,
  ) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    withSpring(_spring, () => list.change(['a', 'b']));
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    expect(alphaOf(tester, 'c'), lessThan(255));
    await _settle(tester);
    expect(find.text('c'), findsNothing);
  });
}
