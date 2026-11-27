import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  List<String> log, {
  Map<ShortcutActivator, Intent>? shortcuts,
  TextDirection direction = TextDirection.ltr,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  shortcuts: shortcuts,
  builder: (context, _) => Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 402,
            child: GlassSwipeActions(
              trailing: [
                GlassSwipeAction(
                  title: 'Delete',
                  destructive: true,
                  onPressed: () => log.add('Delete'),
                ),
                GlassSwipeAction(
                  title: 'Flag',
                  onPressed: () => log.add('Flag'),
                ),
              ],
              child: const GlassListRow(title: Text('Message')),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.drag(
    find.text('Message'),
    const Offset(-200, 0),
    touchSlopX: 0,
  );
  await _settle(tester);
}

Future<String?> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  return _focused(tester);
}

String? _focused(WidgetTester tester) {
  final node =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode;
  String? found;
  bool visit(SemanticsNode n) {
    final data = n.getSemanticsData();
    if (data.flagsCollection.isFocused == Tristate.isTrue) {
      found = data.label;
      return false;
    }
    n.visitChildren(visit);
    return found == null;
  }

  if (node != null) visit(node);
  return found;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a closed row is no Tab stop; an open row stops on each '
      'action, which shows its focus, and Space presses the focused one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    expect(await _tab(tester), isNull);
    expect(await _tab(tester), isNull);

    await _open(tester);
    final stops = {await _tab(tester), await _tab(tester)};
    expect(stops, {'Delete', 'Flag'});
    final focused = _focused(tester)!;
    final ring = tester.widget<GlassHighlightPaint>(
      find.ancestor(
        of: find.text(focused),
        matching: find.byType(GlassHighlightPaint),
      ),
    );
    expect(ring.states!.value, contains(WidgetState.focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log, [focused]);
    expect(await _tab(tester), isNull);
    semantics.dispose();
  });

  testWidgets("an app's own activation key presses the focused action", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        log,
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
          const SingleActivator(LogicalKeyboardKey.keyD):
              const ActivateIntent(),
        },
      ),
    );
    await _open(tester);
    final focused = await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await _settle(tester);
    expect(log, [focused]);
    semantics.dispose();
  });

  testWidgets('an open row reads its actions as buttons where they are '
      'drawn and keeps them as custom actions; a closed row reads none', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app([]));
    expect(find.bySemanticsLabel('Delete'), findsNothing);
    expect(find.bySemanticsLabel('Flag'), findsNothing);

    await _open(tester);
    for (final label in ['Delete', 'Flag']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final rect = tester.getRect(find.text(label));
      final drawn = node.transform == null
          ? node.rect
          : MatrixUtils.transformRect(node.transform!, node.rect);
      expect(drawn.width, greaterThanOrEqualTo(rect.width));
    }
    final row = tester.getSemantics(find.byType(GlassSwipeActions));
    expect(row.getSemanticsData().customSemanticsActionIds, hasLength(2));
    semantics.dispose();
  });

  testWidgets('a drag that starts on an action moves the row and presses '
      'nothing; a tap presses it', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    final closed = tester.getTopLeft(find.text('Message')).dx;
    await _open(tester);
    await tester.drag(find.text('Flag'), const Offset(200, 0), touchSlopX: 0);
    await _settle(tester);
    expect(log, isEmpty);
    expect(tester.getTopLeft(find.text('Message')).dx, closeTo(closed, 0.5));

    await _open(tester);
    await tester.tap(find.text('Flag'));
    await _settle(tester);
    expect(log, ['Flag']);
    expect(tester.getTopLeft(find.text('Message')).dx, closeTo(closed, 0.5));
  });

  testWidgets('right to left, the actions open on the left and take '
      'taps there', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(log, direction: TextDirection.rtl));
    await tester.drag(
      find.text('Message'),
      const Offset(200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    final row = tester.getRect(find.byType(GlassSwipeActions));
    expect(tester.getCenter(find.text('Delete')).dx - row.left, lessThan(80));
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(log, ['Delete']);
  });

  group('a release, as UIKit 27.2 measured', () {
    double shown(WidgetTester tester) =>
        tester.getTopLeft(find.text('Message')).dx -
        tester.getTopLeft(find.byType(GlassSwipeActions)).dx;

    testWidgets('a quick short flick only opens the row', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));
      final rest = shown(tester);
      await tester.flingFrom(
        tester.getCenter(find.text('Message')) + const Offset(120, 0),
        const Offset(-150, 0),
        3000,
      );
      await _settle(tester);
      expect(log, isEmpty);
      expect(find.text('Delete'), findsOneWidget);
      expect(shown(tester), lessThan(rest - 100));
      expect(shown(tester), greaterThan(rest - 250));
    });

    testWidgets('the row moves past the 25 point slop 1:1 and a full swipe '
        'commits only at 0.77 of the row, with a 50 point step', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));
      final rest = shown(tester);
      final finger = await tester.startGesture(const Offset(390, 26));
      await finger.moveBy(const Offset(-125, 0));
      await tester.pump(_frame);
      expect(shown(tester), moreOrLessEquals(rest - 100));
      await finger.moveBy(const Offset(-180, 0));
      await tester.pump(_frame);
      expect(shown(tester), moreOrLessEquals(rest - 280));
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump(_frame);
      expect(shown(tester), moreOrLessEquals(rest - 320 - 50.33));
      await finger.up();
      await _settle(tester);
      expect(log, ['Delete']);
    });

    testWidgets('a full swipe brought back under the commit closes the row '
        'on release, wherever it stands', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));
      final rest = shown(tester);
      final finger = await tester.startGesture(const Offset(390, 26));
      await finger.moveBy(const Offset(-345, 0));
      await tester.pump(_frame);
      await finger.moveBy(const Offset(200, 0));
      await tester.pump(_frame);
      await tester.pump(const Duration(milliseconds: 300));
      await finger.up();
      await _settle(tester);
      expect(log, isEmpty);
      expect(shown(tester), moreOrLessEquals(rest));
    });

    testWidgets("the finger's last movement decides: pulled open and held, "
        'it opens even a little open; pushed back, it closes', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));
      final rest = shown(tester);
      var finger = await tester.startGesture(const Offset(390, 26));
      await finger.moveBy(const Offset(-30, 0));
      await tester.pump(_frame);
      await tester.pump(const Duration(milliseconds: 300));
      await finger.up();
      await _settle(tester);
      expect(shown(tester), lessThan(rest - 100));
      finger = await tester.startGesture(const Offset(200, 26));
      await finger.moveBy(const Offset(-60, 0));
      await tester.pump(_frame);
      await finger.moveBy(const Offset(10, 0));
      await tester.pump(_frame);
      await finger.up();
      await _settle(tester);
      expect(shown(tester), moreOrLessEquals(rest));
      expect(log, isEmpty);
    });
  });

  group('the look and the leading side, as UIKit 27.2 measured', () {
    Widget both(List<String> log) => WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 402,
              child: GlassSwipeActions(
                trailing: [
                  GlassSwipeAction(
                    title: 'Delete',
                    destructive: true,
                    onPressed: () => log.add('Delete'),
                  ),
                  GlassSwipeAction(
                    title: 'Flag',
                    onPressed: () => log.add('Flag'),
                  ),
                ],
                leading: [
                  GlassSwipeAction(
                    title: 'Pin',
                    onPressed: () => log.add('Pin'),
                  ),
                  GlassSwipeAction(
                    title: 'Read',
                    onPressed: () => log.add('Read'),
                  ),
                ],
                child: const GlassListRow(title: Text('Message')),
              ),
            ),
          ),
        ),
      ),
    );

    Rect button(WidgetTester tester, String title) => tester.getRect(
      find
          .ancestor(of: find.text(title), matching: find.byType(ClipRRect))
          .first,
    );

    testWidgets('open, the buttons stand 44 tall 4.67 below the row, as wide '
        'as the widest, 10 apart and 10 from the edge, and the row moves by '
        'the strip', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(both(log));
      final row = tester.getRect(find.byType(GlassSwipeActions));
      final rest = tester.getTopLeft(find.text('Message')).dx;
      await tester.drag(
        find.text('Message'),
        const Offset(-200, 0),
        touchSlopX: 0,
      );
      await _settle(tester);
      final delete = button(tester, 'Delete');
      final flag = button(tester, 'Flag');
      expect(delete.height, 44);
      expect(delete.top - row.top, moreOrLessEquals(4.67));
      expect(flag.width, delete.width);
      expect(delete.right, moreOrLessEquals(row.right - 10));
      expect(delete.left - flag.right, moreOrLessEquals(10));
      final strip = 10 + delete.width + 10 + flag.width + 10;
      expect(
        tester.getTopLeft(find.text('Message')).dx,
        moreOrLessEquals(rest - strip),
      );
      expect(
        find.byType(GlassSwipeActions),
        paints..rrect(color: const Color(0xFFE5E5EA)),
      );
    });

    testWidgets('under a finger a button grows from nothing as its place '
        'opens, the outermost first', (tester) async {
      await tester.pumpWidget(both([]));
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Message')),
      );
      await finger.moveBy(const Offset(-25 - 40, 0));
      await tester.pump(_frame);
      expect(button(tester, 'Delete').width, greaterThan(0));
      expect(button(tester, 'Delete').width, lessThan(60));
      expect(find.text('Flag'), findsNothing);
      await finger.moveBy(const Offset(-130, 0));
      await tester.pump(_frame);
      final delete = button(tester, 'Delete');
      expect(find.text('Flag'), findsOneWidget);
      expect(button(tester, 'Flag').width, lessThan(delete.width));
      await finger.up();
      await _settle(tester);
    });

    testWidgets('a swipe toward the leading edge opens the leading actions '
        'there, the first outermost; past 0.53 of the row it commits and '
        'the row resists, and a release performs it', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(both(log));
      final row = tester.getRect(find.byType(GlassSwipeActions));
      await tester.drag(
        find.text('Message'),
        const Offset(150, 0),
        touchSlopX: 0,
      );
      await _settle(tester);
      expect(button(tester, 'Pin').left, moreOrLessEquals(row.left + 10));
      expect(
        button(tester, 'Read').left,
        greaterThan(button(tester, 'Pin').right),
      );
      expect(log, isEmpty);
      await tester.tapAt(row.centerRight - const Offset(20, 0));
      await _settle(tester);

      final rest = tester.getTopLeft(find.text('Message')).dx;
      final finger = await tester.startGesture(
        row.centerLeft + const Offset(40, 0),
      );
      await finger.moveBy(const Offset(25 + 300, 0));
      await tester.pump(_frame);
      const commit = 195.96 / 370 * 402;
      final at = tester.getTopLeft(find.text('Message')).dx - rest;
      expect(at, moreOrLessEquals(commit + (300 - commit) * 0.45 / 2.3));
      expect(find.text('Read'), findsNothing);
      await finger.up();
      await _settle(tester);
      expect(log, ['Pin']);
      expect(
        tester.getTopLeft(find.text('Message')).dx,
        moreOrLessEquals(rest),
      );
    });

    testWidgets('after a release the buttons scale in, overshooting, and '
        'stand whole', (tester) async {
      await tester.pumpWidget(both([]));
      final row = tester.getRect(find.byType(GlassSwipeActions));
      final finger = await tester.startGesture(row.center);
      await finger.moveBy(const Offset(-25 - 30, 0));
      await tester.pump(_frame);
      await finger.up();
      final widths = <double>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(_frame);
        var scale = 1.0;
        expect(
          find.byType(GlassSwipeActions),
          paints..everything((method, arguments) {
            if (method == #transform) {
              scale = (arguments[0] as List<double>)[0];
            }
            return true;
          }),
        );
        widths.add(scale);
      }
      expect(widths.reduce((a, b) => a < b ? a : b), lessThan(0.5));
      expect(widths.reduce((a, b) => a > b ? a : b), greaterThan(1.01));
      await _settle(tester);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Flag'), findsOneWidget);
    });
  });
}
