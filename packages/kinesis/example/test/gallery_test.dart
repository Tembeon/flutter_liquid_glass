import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/gallery.dart';
import 'package:kinesis_example/kit.dart';

const _widths = {'narrow': 320.0, 'wide': 1200.0};
const _screens = {'phone': Size(320, 568), 'desktop': Size(1200, 800)};

final _page = find.descendant(
  of: find.byType(DemoPage),
  matching: find.byType(Scrollable),
);

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _hold(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 16);
  for (var held = Duration.zero; held < duration; held += frame) {
    await tester.pump(frame);
  }
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  await tester.scrollUntilVisible(target, 120, scrollable: scrollable.first);
  await tester.ensureVisible(target.first);
  await _settle(tester);
}

Future<void> _open(WidgetTester tester, Size size, String title) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const KinesisGallery());
  await _reveal(tester, find.text(title), find.byType(Scrollable));
  await tester.tap(find.text(title));
  await _settle(tester);
  expect(find.byType(DemoPage), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await _reveal(tester, find.text(label), _page);
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  setUp(MotionClock.debugReset);

  for (final MapEntry(key: name, value: width) in _widths.entries) {
    group(name, () {
      for (final demo in [for (final group in demoGroups) ...group.demos]) {
        testWidgets('${demo.title} lays out, takes every button and goes '
            'back', (tester) async {
          await _open(tester, Size(width, 6000), demo.title);
          if (demo.title != 'Presentations') {
            final buttons = find.byType(PushButton);
            final count = buttons.evaluate().length;
            for (var i = 0; i < count; i++) {
              await tester.tap(buttons.at(i), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 400));
            }
            await _settle(tester);
          }
          await tester.tap(find.text('Catalog'));
          await _settle(tester);
          expect(find.byType(DemoPage), findsNothing);
          expect(find.byType(CatalogPage), findsOneWidget);
          expect(tester.binding.hasScheduledFrame, isFalse);
        });
      }
    });
  }

  for (final MapEntry(key: name, value: size) in _screens.entries) {
    group(name, () {
      testWidgets('a popup completes with the answer', (tester) async {
        await _open(tester, size, 'Presentations');
        await _tap(tester, 'Ask');
        await tester.tap(find.text('Keep'));
        await _settle(tester);
        expect(find.text('Keep the change?'), findsNothing);
        expect(find.text('Kept.'), findsOneWidget);

        await _tap(tester, 'Ask');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.text('Dismissed without an answer.'), findsOneWidget);
        expect(find.byType(DemoPage), findsOneWidget);
      });

      testWidgets('a panel grows from its tile and goes back', (tester) async {
        await _open(tester, size, 'Presentations');
        await _tap(tester, 'Open');
        expect(find.text('Album'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await _settle(tester);
        expect(find.text('Album'), findsNothing);
      });

      testWidgets('a sheet stays under a short drag and goes with a long '
          'one', (tester) async {
        await _open(tester, size, 'Presentations');
        await _tap(tester, 'Show sheet');
        expect(find.text('Drag me down'), findsOneWidget);

        await tester.timedDrag(
          find.text('Drag me down'),
          const Offset(0, 60),
          const Duration(milliseconds: 600),
        );
        await _settle(tester);
        expect(find.text('Drag me down'), findsOneWidget);

        await tester.timedDrag(
          find.text('Drag me down'),
          const Offset(0, 220),
          const Duration(milliseconds: 300),
        );
        await _settle(tester);
        expect(find.text('Drag me down'), findsNothing);
        expect(find.byType(DemoPage), findsOneWidget);
      });
    });
  }

  group('gestures', () {
    const phone = Size(390, 844);

    double pageOffset(WidgetTester tester) =>
        tester.state<ScrollableState>(_page.first).position.pixels;

    Future<void> moveBy(
      TestGesture gesture,
      WidgetTester tester,
      Offset step,
      int count,
    ) async {
      for (var i = 0; i < count; i++) {
        await gesture.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('MotionDriven insets the box without a rebuild', (
      tester,
    ) async {
      await _open(tester, phone, 'Springs');
      final label = find.text('Padding and corners');
      await _reveal(tester, label, _page);
      final box = find.ancestor(of: label, matching: find.byType(ColoredBox));
      final before = tester.getSize(box.first).width;
      await _tap(tester, 'Inset');
      expect(tester.getSize(box.first).width, before - 96);
      await _tap(tester, 'Inset');
      expect(tester.getSize(box.first).width, before);
    });

    testWidgets('a keyframe tile plays its timeline and comes back', (
      tester,
    ) async {
      await _open(tester, phone, 'Keyframes and animators');
      final tile = find.byType(Tile).first;
      final rest = tester.getRect(tile);
      await tester.tap(find.text('cubic'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(tile).width, greaterThan(rest.width + 1));
      await _settle(tester);
      expect(tester.getRect(tile), rectMoreOrLessEquals(rest, epsilon: 0.5));
    });

    testWidgets('the scrub bar moves the animated tile', (tester) async {
      await _open(tester, phone, 'Keyframes and animators');
      await _reveal(tester, find.text('Reverse'), _page);
      final rail = tester.getRect(
        find.ancestor(of: find.text('A'), matching: find.byType(Rail)),
      );
      final start = tester.getCenter(find.text('A')).dx;
      final gesture = await tester.startGesture(
        Offset(rail.left + 4, rail.bottom + 34),
      );
      await moveBy(gesture, tester, const Offset(20, 0), 12);
      expect(tester.getCenter(find.text('A')).dx, greaterThan(start + 100));
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('a tapped row leaves the sliver list', (tester) async {
      await _open(tester, phone, 'Layout changes');
      await _tap(tester, 'Row 3');
      expect(find.text('Row 3'), findsNothing);
      expect(find.text('Row 4'), findsOneWidget);
    });

    testWidgets('a flicked knob lands on a stop', (tester) async {
      await _open(tester, phone, 'Release');
      final knob = find.byType(Dot).first;
      final rail = tester.getRect(
        find.ancestor(of: knob, matching: find.byType(Rail)),
      );
      final start = tester.getCenter(knob);
      await tester.flingFrom(start, const Offset(80, 0), 1200);
      await _settle(tester);
      final x = tester.getCenter(knob).dx;
      expect(x, greaterThan(start.dx + 40));
      final stops = [
        for (final stop in [0.0, 0.5, 1.0])
          rail.left + 18 + stop * (rail.width - 36),
      ];
      expect(stops.any((stop) => (stop - x).abs() < 0.5), isTrue);
    });

    testWidgets('a swipe turns the page', (tester) async {
      await _open(tester, phone, 'Release');
      await _reveal(tester, find.text('Page 1'), _page);
      final center = tester.getCenter(find.text('Page 1')).dx;
      await tester.fling(find.text('Page 1'), const Offset(-80, 0), 800);
      await _settle(tester);
      expect(
        tester.getCenter(find.text('Page 2')).dx,
        moreOrLessEquals(center, epsilon: 0.5),
      );
    });

    testWidgets('a flicked ruler glides and comes to rest', (tester) async {
      await _open(tester, phone, 'Release');
      await _reveal(tester, find.text('Glide'), _page);
      final ruler = find
          .descendant(
            of: find.byType(OverflowBox),
            matching: find.byType(CustomPaint),
          )
          .first;
      final before = tester.getRect(ruler).left;
      final from = tester.getCenter(
        find.ancestor(of: ruler, matching: find.byType(InputRegion)).first,
      );
      await tester.flingFrom(from, const Offset(-80, 0), 1500);
      await tester.pump(const Duration(milliseconds: 100));
      final moving = tester.getRect(ruler).left;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(ruler).left, lessThan(moving));
      await _settle(tester, 40);
      expect(tester.getRect(ruler).left, lessThan(before - 120));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the pad tells a tap, a double tap and a long press apart', (
      tester,
    ) async {
      await _open(tester, phone, 'Interactions');
      final pad = find.text('Press me');
      await tester.tap(pad);
      await _settle(tester);
      expect(find.text('tap'), findsOneWidget);

      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(pad);
      await _settle(tester);
      expect(find.text('double tap'), findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(pad));
      await _hold(tester, const Duration(milliseconds: 700));
      expect(find.text('long press'), findsOneWidget);
      await gesture.up();
      await _settle(tester);
      expect(find.text('long press released'), findsOneWidget);
    });

    testWidgets('the pad hears a right-click and a resting mouse', (
      tester,
    ) async {
      await _open(tester, phone, 'Interactions');
      final center = tester.getCenter(find.text('Press me'));
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: center - const Offset(0, 200));
      await mouse.moveTo(center);
      await _hold(tester, const Duration(milliseconds: 800));
      expect(find.text('mouse rested'), findsOneWidget);

      await mouse.down(center);
      await mouse.up();
      await _settle(tester);
      expect(find.textContaining('secondary click at'), findsOneWidget);
      await mouse.removePointer();
    });

    testWidgets('the puck follows a vertical drag, not the page', (
      tester,
    ) async {
      await _open(tester, phone, 'Interactions');
      await _reveal(tester, find.byType(Dot), _page);
      final puck = find.byType(Dot).first;
      final start = tester.getCenter(puck);
      final scroll = pageOffset(tester);
      final gesture = await tester.startGesture(start);
      await moveBy(gesture, tester, const Offset(0, 15), 6);
      expect(tester.getCenter(puck).dy, greaterThan(start.dy + 60));
      expect(pageOffset(tester), scroll);
      await gesture.up();
      await _settle(tester);
      expect(tester.getCenter(puck).dy, moreOrLessEquals(start.dy, epsilon: 1));
    });

    testWidgets('a held tile follows the finger, a quick swipe scrolls the '
        'page', (tester) async {
      await _open(tester, phone, 'Interactions');
      final hold = find.text('Hold');
      await _reveal(tester, hold, _page);
      final start = tester.getCenter(hold);
      final scroll = pageOffset(tester);

      final held = await tester.startGesture(start);
      await _hold(tester, const Duration(milliseconds: 500));
      await moveBy(held, tester, const Offset(20, 0), 4);
      expect(tester.getCenter(hold).dx, greaterThan(start.dx + 60));
      expect(pageOffset(tester), scroll);
      await held.up();
      await _settle(tester);

      final swipe = await tester.startGesture(tester.getCenter(hold));
      await moveBy(swipe, tester, const Offset(0, 30), 5);
      await swipe.up();
      await _settle(tester);
      expect(pageOffset(tester), lessThan(scroll - 60));
    });

    testWidgets('the light stays under the finger', (tester) async {
      await _open(tester, phone, 'Interactions');
      final area = find.text('Touch and move');
      await _reveal(tester, area, _page);
      final spot = find.byType(Dot).last;
      final down = tester.getCenter(area) + const Offset(-60, 10);
      final gesture = await tester.startGesture(down);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getCenter(spot), offsetMoreOrLessEquals(down, epsilon: 1));
      await gesture.moveBy(const Offset(50, -20));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getCenter(spot),
        offsetMoreOrLessEquals(down + const Offset(50, -20), epsilon: 1),
      );
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('keys, a screen reader and a drag step the level', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, phone, 'Interactions');
      final level = find.bySemanticsLabel('Level');
      await _reveal(tester, level, _page);
      SemanticsData data() => tester.getSemantics(level).getSemanticsData();
      bool inLevel() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<InputRegion>()
              ?.semantics
              ?.label ==
          'Level';
      for (var i = 0; i < 30 && !inLevel(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(inLevel(), isTrue);
      expect(data().value, '40%');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(data().value, '50%');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await _settle(tester);
      expect(data().value, '100%');
      expect(data().hasAction(SemanticsAction.increase), isFalse);
      expect(data().hasAction(SemanticsAction.decrease), isTrue);
      tester.semantics.performAction(
        find.semantics.byLabel('Level'),
        SemanticsAction.decrease,
      );
      await _settle(tester);
      expect(data().value, '90%');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await _settle(tester);
      expect(data().value, '0%');
      final width = tester.getSize(level).width;
      final gesture = await tester.startGesture(tester.getCenter(level));
      await moveBy(gesture, tester, Offset(width / 16, 0), 8);
      await gesture.up();
      await _settle(tester);
      expect(int.parse(data().value.replaceAll('%', '')), greaterThan(30));
      semantics.dispose();
    });

    testWidgets('segments select by tap and by a slide across', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      Iterable<String> selected() => find.semantics
          .byFlag(SemanticsFlag.isSelected)
          .evaluate()
          .map((node) => node.label);

      await _open(tester, phone, 'Input zones');
      expect(selected(), contains('Day'));
      await tester.tap(find.text('Week'));
      await _settle(tester);
      expect(selected(), contains('Week'));
      expect(selected(), isNot(contains('Day')));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Day')),
      );
      final to = tester.getCenter(find.text('Year'));
      final step = (to - tester.getCenter(find.text('Day'))) / 8;
      await moveBy(gesture, tester, step, 8);
      await gesture.up();
      await _settle(tester);
      expect(selected(), contains('Year'));
      semantics.dispose();
    });

    testWidgets('Tab reaches the segments and an arrow selects', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, phone, 'Input zones');
      bool inZones() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<InputZones<int>>() !=
          null;
      for (var i = 0; i < 8 && !inZones(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(inZones(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(
        find.semantics
            .byFlag(SemanticsFlag.isSelected)
            .evaluate()
            .map((node) => node.label),
        contains('Week'),
      );
      semantics.dispose();
    });

    testWidgets('a tapped bubble counts while it orbits', (tester) async {
      await _open(tester, phone, 'Input zones');
      await _tap(tester, 'Orbit');
      await tester.pump(const Duration(milliseconds: 700));
      final bubble = find.byType(Dot).first;
      await tester.tapAt(tester.getCenter(bubble));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('1'), findsOneWidget);
      await _tap(tester, 'Pause');
    });

    testWidgets('the inner list drives the title, Top scrolls back', (
      tester,
    ) async {
      await _open(tester, phone, 'Scroll');
      await _reveal(tester, find.text('Top'), _page);
      final list = _page.at(1);
      double inner() => tester.state<ScrollableState>(list).position.pixels;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Entry 1')),
      );
      await moveBy(gesture, tester, const Offset(0, -20), 8);
      expect(find.text('phase: dragging'), findsOneWidget);
      await gesture.up();
      await _settle(tester);
      expect(inner(), greaterThan(100));
      expect(find.text('phase: idle'), findsOneWidget);
      await _tap(tester, 'Top');
      expect(inner(), 0);
    });
  });
}
