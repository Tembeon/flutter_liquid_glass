import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_stage.dart';

const _tuning = MenuTuning.standard;
const _outside = Offset(350, 500);

List<GlassMenuEntry> _sub(MenuStage stage, {int extra = 0}) => [
  stage.item('Copy', icon: const Icon(IconData(1))),
  stage.item('Share', icon: const Icon(IconData(2))),
  GlassSubmenu(
    title: 'More',
    icon: const Icon(IconData(3)),
    children: [
      stage.item('Sub one', icon: const Icon(IconData(11))),
      stage.item('Sub two', icon: const Icon(IconData(12))),
      GlassSubmenu(
        title: 'Deeper',
        icon: const Icon(IconData(13)),
        children: [stage.item('Deep one'), stage.item('Deep two')],
      ),
    ],
  ),
  stage.item('Delete', icon: const Icon(IconData(4)), destructive: true),
  for (var i = 0; i < extra; i++) stage.item('Row $i'),
];

/// The menu of [entries] on a 48 pt square centred at (201, 150), opened by
/// a hold, as the recordings' menus were.
Widget _held(MenuStage stage, List<GlassMenuEntry> entries) => Stack(
  children: [
    Positioned(
      left: 177,
      top: 126,
      width: 48,
      height: 48,
      child: GlassMenuAnchor(
        controller: stage.controller,
        menuChildren: entries,
        child: const SizedBox.expand(),
      ),
    ),
  ],
);

/// The menu of [entries] on a 44 pt glass button at (24, 80), opened by its
/// tap.
Widget _tapped(MenuStage stage, List<GlassMenuEntry> entries) => Stack(
  children: [
    Positioned(
      left: 24,
      top: 80,
      width: 44,
      height: 44,
      child: GlassMenuAnchor(
        controller: stage.controller,
        menuChildren: entries,
        builder: (context, controller, child) =>
            GlassButton(onPressed: controller.open, child: const Text('More')),
      ),
    ),
  ],
);

/// Opens the menu from code at the clock's time and lets it settle for a
/// second.
Future<void> _open(MenuStage stage) async {
  final t = stage.clock.now;
  stage.controller.open();
  await stage.runTo(t + 1);
  expect(stage.isOpen, isTrue);
}

/// Closes the menu from code and lets it go.
Future<void> _close(MenuStage stage) async {
  final t = stage.clock.now;
  stage.controller.close();
  await stage.runTo(t + 1.5);
  expect(stage.shows('Copy'), isFalse);
}

void main() {
  setUp(MotionClock.debugReset);

  group('a close comes due at its deadline, after the action it chose '
      '(close_deadline_test)', () {
    const rows = ['Row 0', 'Row 1', 'Row 2'];

    Future<MenuStage> stage(WidgetTester tester) async {
      final stage = MenuStage(tester);
      await stage.show(
        _tapped(stage, [for (final title in rows) stage.item(title)]),
      );
      return stage;
    }

    Future<void> closesAt(
      MenuStage stage,
      double due, {
      Map<String, double> chose = const {},
    }) async {
      await stage.runTo(due - 1e-6);
      expect(stage.isOpen, isTrue);
      await stage.runTo(due + 1e-6);
      expect(stage.isOpen, isFalse);
      expect(stage.chosen, chose.keys);
      expect(stage.chosenAt, [
        for (final at in chose.values)
          inInclusiveRange(at - 1e-6, at + stage.step),
      ]);
      await stage.runTo(due + 1.5);
      expect(stage.shows('Row 0'), isFalse);
    }

    testWidgets('a tap outside the open menu chooses nothing', (tester) async {
      final s = await stage(tester);
      await _open(s);
      await s.tap(1.01, _outside, hold: 0.01);
      await closesAt(s, 1.02 + _tuning.dismissDelay);
    });

    testWidgets('a tap on a row of the open menu chooses it', (tester) async {
      final s = await stage(tester);
      await _open(s);
      await s.tap(1.01, s.centerOf('Row 1'), hold: 0.01);
      await closesAt(
        s,
        1.02 + _tuning.dismissDelay,
        chose: {'Row 1': 1.02 + _tuning.actionDelay},
      );
    });

    Future<Offset> firstRow(MenuStage s) async {
      await _open(s);
      final row = s.centerOf('Row 0');
      await _close(s);
      return row;
    }

    testWidgets('a tap outside before the menu appears chooses nothing', (
      tester,
    ) async {
      final s = await stage(tester);
      await firstRow(s);
      final t = s.clock.now;
      await s.tap(t, const Offset(46, 102), hold: 0.01);
      await s.tap(t + 0.02, _outside, hold: 0.01);
      await closesAt(
        s,
        t + 0.01 + _tuning.tapOpenDelay + _tuning.earlyCloseDelay,
      );
    });

    testWidgets('a tap on a row before the menu appears chooses it', (
      tester,
    ) async {
      final s = await stage(tester);
      final row = await firstRow(s);
      final t = s.clock.now;
      await s.tap(t, const Offset(46, 102), hold: 0.01);
      await s.tap(t + 0.02, row, hold: 0.01);
      final due = t + 0.01 + _tuning.tapOpenDelay + _tuning.earlyCloseDelay;
      await closesAt(s, due, chose: {'Row 0': due});
    });
  });

  group('touches beside the menu (api_test)', () {
    testWidgets('a still finger holds the menu open and closes it at the '
        'lift', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      await _open(s);
      final beside = s.menuRect.centerRight.translate(6, 0);
      final finger = await s.down(1, beside);
      await s.runTo(2.2);
      expect(s.isOpen, isTrue);
      await s.up(finger, 2.2);
      await s.runTo(2.2 + _tuning.dismissDelay - 1e-6);
      expect(s.isOpen, isTrue);
      await s.runTo(2.2 + _tuning.dismissDelay + 1e-6);
      expect(s.isOpen, isFalse);
      expect(s.chosen, isEmpty);
    });

    testWidgets('a finger that moves closes it, and sliding onto a row '
        'highlights and chooses nothing; a finger put down on a row '
        'chooses it', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      await _open(s);
      final beside = s.menuRect.centerRight.translate(6, 0);
      final finger = await s.down(1, beside);
      await s.move(finger, 1.03, beside.translate(-10, 0));
      expect(s.isOpen, isTrue);
      expect(s.rowAt(beside.translate(-10, 0)), isNotNull);
      expect(s.highlightOn(0), isNull);
      await s.move(finger, 1.08, beside.translate(-20, 0));
      expect(s.isOpen, isFalse);
      await s.up(finger, 1.1);
      await s.runTo(3);
      expect(s.chosen, isEmpty);

      await _open(s);
      await s.tap(s.clock.now, s.centerOf('Share'));
      await s.runTo(s.clock.now + 1);
      expect(s.chosen, ['Share']);
    });
  });

  group('touches around a submenu (api_test)', () {
    Future<MenuStage> opened(WidgetTester tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s, extra: 5)));
      await _open(s);
      await s.tap(1, s.centerOf('More'), hold: 0.02);
      await s.runTo(3);
      expect(s.shows('Sub one'), isTrue);
      return s;
    }

    Rect card(MenuStage s) => s.cardRect(1);

    testWidgets('a finger on the card lifted off the menu leaves the card '
        'open and chooses nothing; lifted on a row it chooses that row', (
      tester,
    ) async {
      final s = await opened(tester);
      final rest = card(s);
      final start = rest.center.translate(0, 31);
      final finger = await s.down(3, start);
      for (var i = 1; i <= 10; i++) {
        await s.move(finger, 3 + i * 0.05, start.translate(0, 22.3 * i));
      }
      final past = Offset(rest.center.dx, s.menuRect.bottom + 19);
      await s.move(finger, 5, past);
      await s.up(finger, 5.1);
      await s.runTo(8);
      expect(s.isOpen, isTrue);
      expect(s.shows('Sub one'), isTrue);
      expect(s.chosen, isEmpty);

      await s.tap(8, s.centerOf('Sub two'));
      await s.runTo(9);
      expect(s.chosen, ['Sub two']);
    });

    testWidgets('a finger on the parent under the card highlights nothing; '
        'its lift in place closes the card', (tester) async {
      final s = await opened(tester);
      final rest = card(s);
      final parent = Offset(rest.center.dx, rest.bottom + 6);
      expect(s.rootRect.contains(parent), isTrue);
      final finger = await s.down(3, parent);
      await s.move(finger, 3.05, parent.translate(0, 8));
      await s.runTo(4);
      expect(s.highlightOn(0), isNull);
      expect(s.highlightOn(1), isNull);
      await s.move(finger, 4, parent);
      await s.up(finger, 4);
      await s.runTo(6);
      expect(s.shows('Sub one'), isFalse);
      expect(s.isOpen, isTrue);
      expect(s.chosen, isEmpty);

      final row = await s.down(6, s.centerOf('Share'));
      await s.runTo(6.2);
      expect(s.highlightOn(0), isNotNull);
      await s.up(row, 6.2);
    });

    testWidgets('a finger from the parent lifted far past the menu does '
        'nothing; lifted in place it closes the card', (tester) async {
      final s = await opened(tester);
      final rest = card(s);
      final parent = Offset(rest.center.dx, rest.bottom + 6);
      final far = Offset(parent.dx, s.menuRect.bottom + 140);
      final finger = await s.down(3, parent);
      await s.move(finger, 3.1, far);
      await s.up(finger, 3.2);
      await s.runTo(5);
      expect(s.isOpen, isTrue);
      expect(s.shows('Sub one'), isTrue);

      await s.tap(5, parent);
      await s.runTo(7);
      expect(s.isOpen, isTrue);
      expect(s.shows('Sub one'), isFalse);
      expect(s.chosen, isEmpty);
    });
  });

  testWidgets('a finger resting on a submenu row opens its card '
      'hoverOpenDelay after it landed (api_test)', (tester) async {
    final s = MenuStage(tester);
    await s.show(_held(s, _sub(s)));
    await _open(s);
    final finger = await s.down(1, s.centerOf('More'));
    await s.runTo(1 + _tuning.hoverOpenDelay - 1e-6);
    expect(s.shows('Sub one'), isFalse);
    await s.runTo(1 + _tuning.hoverOpenDelay + 1e-6);
    expect(s.shows('Sub one'), isTrue);
    await s.up(finger, 2);
  });

  group('a card row closes the menu sooner than a touch outside it '
      '(api_test)', () {
    Future<double> closeStart(WidgetTester tester, String name) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      final rows = menuRecording(name);
      final touches = [
        for (final row in rows)
          if (row['k'] == 'touch') row,
      ];
      final menu = rows.firstWhere(
        (Map<String, Object?> r) =>
            r['k'] == 'frame' && r['cls'] == '_UIContextMenuView',
      );
      final t0 = recorded(touches.firstWhere((r) => r['phase'] == 3), 't');
      await _open(s);
      final dy =
          s.menuRect.top - (recorded(menu, 'y') - recorded(menu, 'h') / 2);
      final from = recorded(touches[2], 't');
      await s.replay(
        rows,
        start: from - t0,
        from: from,
        shift: Offset(0, dy),
      );
      final lift = recorded(touches.last, 't') - t0;
      s.step = 0.001;
      while (s.isOpen && s.clock.now < lift + 0.2) {
        await s.runTo(s.clock.now + 0.001);
      }
      return s.clock.now - lift;
    }

    double deviceStart(String name) {
      final rows = menuRecording(name);
      final lift = recorded(
        rows.lastWhere(
          (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
        ),
        't',
      );
      String? before;
      for (final row in rows) {
        if (row['k'] != 'frame' || row['cls'] != '_UIContextMenuView') {
          continue;
        }
        final shape = '${row['w']} ${row['h']} ${row['y']}';
        if (recorded(row, 't') > lift && before != null && shape != before) {
          return recorded(row, 't') - lift;
        }
        before = shape;
      }
      throw StateError('no close in $name');
    }

    testWidgets('as on the device', (tester) async {
      final select = await closeStart(tester, 'mm-sub-select');
      final outside = await closeStart(tester, 'mm-sub-tap');
      expect(select, moreOrLessEquals(0.031, epsilon: 0.002));
      expect(outside, moreOrLessEquals(0.059, epsilon: 0.002));
      expect(
        (deviceStart('mm-sub-tap') - deviceStart('mm-sub-select')) -
            (outside - select),
        inInclusiveRange(-0.0085, 0.0085),
      );
    });
  });

  group('behaviours no test pinned before (m-design step 1)', () {
    testWidgets('a finger put down on a free-form row and slid onto a row '
        'chooses nothing; put down on the row it chooses it', (tester) async {
      final s = MenuStage(tester);
      await s.show(
        _held(s, [
          GlassMenuWidget(
            height: 44,
            builder: (context) => const Center(child: Text('Free')),
          ),
          s.item('Copy'),
          s.item('Share'),
        ]),
      );
      await _open(s);
      final finger = await s.down(1, s.centerOf('Free'));
      final copy = s.centerOf('Copy');
      for (var i = 1; i <= 10; i++) {
        await s.move(
          finger,
          1 + i / 60,
          Offset.lerp(s.centerOf('Free'), copy, i / 10)!,
        );
      }
      await s.up(finger, 1.3);
      await s.runTo(2);
      expect(s.chosen, isEmpty);
      expect(s.isOpen, isTrue);

      await s.tap(2, copy);
      await s.runTo(3);
      expect(s.chosen, ['Copy']);
    });

    Widget context(MenuStage s, {Widget? child}) => Stack(
      children: [
        Positioned(
          left: 141,
          top: 260,
          width: 120,
          height: 80,
          child: GlassContextMenu(
            controller: s.controller,
            menuChildren: [s.item('Copy'), s.item('Share')],
            child: child ?? const SizedBox.expand(),
          ),
        ),
      ],
    );
    const held = Offset(201, 300);

    testWidgets('a context hold committed and then dragged away does not '
        'open; released in place after the commit it opens', (tester) async {
      final s = MenuStage(tester);
      await s.show(context(s));
      var finger = await s.down(0, held);
      await s.runTo(0.5);
      await s.move(finger, 0.55, held.translate(0, 30));
      await s.runTo(1);
      expect(s.isOpen, isFalse);
      await s.up(finger, 1);
      await s.runTo(2);
      expect(s.isOpen, isFalse);

      finger = await s.down(2, held);
      await s.up(finger, 2.5);
      await s.runTo(3.5);
      expect(s.isOpen, isTrue);
      expect(s.chosen, isEmpty);
    });

    Future<(MenuStage, int Function())> overButton(WidgetTester tester) async {
      var pressed = 0;
      final s = MenuStage(tester);
      await s.show(
        context(
          s,
          child: GlassButton(
            onPressed: () => pressed++,
            child: const SizedBox.expand(),
          ),
        ),
      );
      return (s, () => pressed);
    }

    testWidgets('a context menu over a glass button opens on a hold; a tap '
        'runs the button and opens nothing', (tester) async {
      final (s, pressed) = await overButton(tester);
      final finger = await s.down(0, held);
      await s.runTo(1);
      expect(s.isOpen, isTrue);
      await s.up(finger, 1);
      await _close(s);
      final before = pressed();
      await s.tap(s.clock.now, held);
      await s.runTo(s.clock.now + 1.5);
      expect(pressed(), before + 1);
      expect(s.isOpen, isFalse);
    });

    group(
      'UIKit, which today differs',
      skip:
          'Today it runs: the button wins the arena at the down and the hold '
          'only hears the touch. Step 5 of m-design makes the hold contend.',
      () {
        testWidgets(
          'the glass button under a context menu that opened does not run on '
          'the release, as UIKit cancels its touch',
          (tester) async {
            final (s, pressed) = await overButton(tester);
            final finger = await s.down(0, held);
            await s.runTo(1);
            await s.up(finger, 1);
            await s.runTo(2);
            expect(pressed(), 0);
          },
        );
      },
    );

    testWidgets('the finger that held the menu open plays no haptic until it '
        'slides onto another row', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      final finger = await s.down(0, const Offset(201, 150));
      await s.runTo(1);
      expect(s.isOpen, isTrue);
      expect(s.haptics, isEmpty);
      const from = Offset(201, 150);
      final to = s.centerOf('Delete');
      for (var i = 1; i <= 20; i++) {
        await s.move(finger, 1 + i / 60, Offset.lerp(from, to, i / 20)!);
      }
      expect(s.haptics, isNotEmpty);
      expect(
        s.haptics.map((h) => h.$2).toSet(),
        {'HapticFeedbackType.selectionClick'},
      );
      expect(s.haptics.first.$1, greaterThan(1));
      await s.up(finger, 1.5);
      await s.runTo(2.5);
      expect(s.chosen, ['Delete']);
    });

    testWidgets('a second finger on the open menu is ignored: the first one '
        'chooses where it lifts', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      await _open(s);
      final first = await s.down(1, s.centerOf('Copy'));
      await s.tap(1.1, s.centerOf('Delete'), hold: 0.1);
      await s.runTo(1.5);
      expect(s.chosen, isEmpty);
      expect(s.isOpen, isTrue);
      await s.up(first, 1.6);
      await s.runTo(2.5);
      expect(s.chosen, ['Copy']);
    });

    testWidgets('a tap on a menu button released 40 pt past it still opens '
        'the menu after the tap delay; 80 pt past it opens nothing', (
      tester,
    ) async {
      final s = MenuStage(tester);
      await s.show(_tapped(s, [s.item('Copy'), s.item('Share')]));
      await s.runTo(1);
      const button = Offset(46, 102);
      var finger = await s.down(1, button);
      await s.move(finger, 1.05, button.translate(22 + 40, 0));
      await s.up(finger, 1.1);
      await s.runTo(1.1 + _tuning.tapOpenDelay - 1e-6);
      expect(s.isOpen, isFalse);
      await s.runTo(1.1 + _tuning.tapOpenDelay + 1e-6);
      expect(s.isOpen, isTrue);
      await _close(s);

      final t = s.clock.now;
      finger = await s.down(t, button);
      await s.move(finger, t + 0.05, button.translate(22 + 80, 0));
      await s.up(finger, t + 0.1);
      await s.runTo(t + 1.5);
      expect(s.isOpen, isFalse);
      expect(s.shows('Copy'), isFalse);
    });

    testWidgets('a hold that opened the menu and lifted in place, or moved a '
        'little inside the source, chooses nothing; moved out and back onto '
        'a row it chooses that row', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      const source = Offset(201, 150);
      var finger = await s.down(0, source);
      await s.runTo(1);
      expect(s.isOpen, isTrue);
      expect(s.rowAt(source), isNotNull);
      await s.up(finger, 1);
      await s.runTo(2);
      expect(s.chosen, isEmpty);
      expect(s.isOpen, isTrue);
      await _close(s);

      var t = s.clock.now;
      finger = await s.down(t, source);
      await s.runTo(t + 1);
      expect(s.rowAt(source.translate(0, 8)), isNotNull);
      await s.move(finger, t + 1.1, source.translate(0, 8));
      await s.up(finger, t + 1.2);
      await s.runTo(t + 2);
      expect(s.chosen, isEmpty);
      expect(s.isOpen, isTrue);
      await _close(s);

      t = s.clock.now;
      finger = await s.down(t, source);
      await s.runTo(t + 1);
      final row = s.rowAt(source.translate(0, 8));
      final out = source.translate(0, 60);
      await s.move(finger, t + 1.1, out);
      await s.move(finger, t + 1.2, source.translate(0, 8));
      await s.up(finger, t + 1.3);
      await s.runTo(t + 2);
      expect(row, isNotNull);
      expect(s.chosen, hasLength(1));
    });

    group(
      'UIKit, which today differs',
      skip:
          'Today the rows keep the touch: the drag slides the highlight and '
          'chooses the row under the release, as no Scrollable wins the '
          'arena (menu-api.md: a scrolling finger chooses nothing). Step 4 '
          'of m-design puts the rows in the content role.',
      () {
        testWidgets(
          'a finger that drags a tall root list scrolls it and chooses nothing',
          (tester) async {
            final s = MenuStage(tester);
            await s.show(
              _held(s, [for (var i = 0; i < 40; i++) s.item('Row $i')]),
            );
            await _open(s);
            final from = s.centerOf('Row 5');
            final tenth = s.centerOf('Row 10');
            final finger = await s.down(1, from);
            for (var i = 1; i <= 20; i++) {
              await s.move(finger, 1 + i / 60, from.translate(0, -10.0 * i));
            }
            await s.up(finger, 1.4);
            await s.runTo(3);
            expect(s.chosen, isEmpty);
            expect(s.isOpen, isTrue);
            expect(s.centerOf('Row 10').dy, lessThan(tenth.dy - 100));
          },
        );
      },
    );
  });

  group('a menu closed from code under the finger it took lets the finger '
      'go once it has gone', () {
    testWidgets('after a hold: the next hold opens it again', (tester) async {
      final s = MenuStage(tester);
      await s.show(_held(s, _sub(s)));
      const source = Offset(201, 150);
      final finger = await s.down(0, source);
      await s.runTo(1);
      expect(s.isOpen, isTrue);
      await s.move(finger, 1.1, source.translate(0, 60));
      await _close(s);
      await s.up(finger, s.clock.now);
      final t = s.clock.now + 0.1;
      final again = await s.down(t, source);
      await s.runTo(t + 1);
      expect(s.isOpen, isTrue);
      await s.up(again, t + 1.1);
    });

    testWidgets('after an early touch: a row of the menu opened again '
        'takes a tap', (tester) async {
      final s = MenuStage(tester);
      await s.show(_tapped(s, [s.item('Copy'), s.item('Paste')]));
      await _open(s);
      final copy = s.centerOf('Copy');
      final paste = s.centerOf('Paste');
      await _close(s);
      const button = Offset(46, 102);
      var t = s.clock.now;
      await s.tap(t, button, hold: 0.01);
      final finger = await s.down(t + 0.02, copy);
      await s.runTo(t + 1);
      expect(s.isOpen, isTrue);
      await s.move(finger, t + 1.1, copy.translate(2, 0));
      await _close(s);
      await s.up(finger, s.clock.now);
      t = s.clock.now + 0.1;
      await s.tap(t, button, hold: 0.01);
      await s.runTo(t + 1);
      expect(s.isOpen, isTrue);
      await s.tap(t + 1, paste, hold: 0.01);
      await s.runTo(t + 2);
      expect(s.chosen, ['Paste']);
    });
  });
}
