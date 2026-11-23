import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import 'menu_stage.dart';

const _tuning = MenuTuning.standard;

/// The touches of the button capture [name] (iPhone 16, 390 x 844 pt), from
/// its first touch, and the button they held.
({Rect button, List<({double t, int phase, Offset at})> touches})
_buttonCapture(String name) {
  final rows = [
    for (final line in Fixtures.lines('test/fixtures/ios27-device/menu/$name'))
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
  final frame = rows.firstWhere((Map<String, Object?> r) => r['k'] == 'f');
  final touches = [
    for (final row in rows)
      if (row['k'] == 'touch')
        (
          t: recorded(row, 't'),
          phase: row['phase']! as int,
          at: Offset(recorded(row, 'x'), recorded(row, 'y')),
        ),
  ];
  final t0 = touches.first.t;
  return (
    button: Rect.fromCenter(
      center: Offset(recorded(frame, 'S_px'), recorded(frame, 'S_py')),
      width: recorded(frame, 'S_bw'),
      height: recorded(frame, 'S_bh'),
    ),
    touches: [
      for (final touch in touches)
        (t: touch.t - t0, phase: touch.phase, at: touch.at),
    ],
  );
}

Widget _button(MenuStage stage, Rect rect, List<GlassMenuEntry> entries) =>
    Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: GlassMenuAnchor(
            controller: stage.controller,
            menuChildren: entries,
            builder: (context, controller, child) => GlassButton(
              onPressed: controller.open,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );

void main() {
  setUp(MotionClock.debugReset);

  group('a menu growing out of a bar capsule (bar_capsule_motion_test)', () {
    var plain = 0;

    Future<MenuStage> bar(WidgetTester tester) async {
      plain = 0;
      final stage = MenuStage(tester);
      await stage.show(
        GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Page'),
            trailing: [
              GlassBarItem(
                icon: const SizedBox.square(key: Key('menu'), dimension: 22),
                semanticLabel: 'Look',
                menuChildren: [stage.item('Off'), stage.item('Other')],
              ),
              GlassBarItem(
                icon: const SizedBox.square(key: Key('plain'), dimension: 22),
                onPressed: () => plain++,
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      );
      await stage.runTo(1);
      return stage;
    }

    Offset item(MenuStage stage, String key) =>
        stage.tester.getCenter(find.byKey(Key(key)).first);

    double opensAt(double up) =>
        up + _tuning.tapOpenDelay + MenuTuning.barItemTapLag;

    testWidgets('opens barItemTapLag later than an inline button after a '
        'tap', (tester) async {
      final s = await bar(tester);
      await s.tap(1, item(s, 'menu'));
      await s.runTo(opensAt(1.05) - 1e-6);
      expect(s.shows('Off'), isFalse);
      await s.runTo(opensAt(1.05) + 1e-6);
      expect(s.shows('Off'), isTrue);
    });

    testWidgets('ends its close within 0.72 s of its start and opens again '
        'on a tap of the item', (tester) async {
      final s = await bar(tester);
      await s.tap(1, item(s, 'menu'));
      await s.runTo(3);
      expect(s.shows('Off'), isTrue);
      await s.tap(3, const Offset(40, 700));
      final closes = 3.05 + _tuning.dismissDelay;
      await s.runTo(closes + 0.72);
      expect(s.shows('Off'), isFalse);
      final t = s.clock.now;
      await s.tap(t, item(s, 'menu'));
      await s.runTo(opensAt(t + 0.05) + 1e-6);
      expect(s.shows('Off'), isTrue);
      expect(s.chosen, isEmpty);
    });

    testWidgets('takes a touch on the item only, not on the rest of the '
        'capsule', (tester) async {
      final s = await bar(tester);
      await s.tap(1, item(s, 'plain'));
      await s.runTo(4);
      expect(s.shows('Off'), isFalse);
      expect(plain, 1);
    });
  });

  group('device captures of a glass button (button_replay_test)', () {
    const titles = ['Copy', 'Share', 'Delete'];

    Future<MenuStage> replay(
      WidgetTester tester,
      String name, {
      bool swallows = false,
    }) async {
      final capture = _buttonCapture(name);
      final s = MenuStage(tester);
      await s.show(
        _button(s, capture.button, [for (final t in titles) s.item(t)]),
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      );
      const start = 1.0;
      await s.runTo(start);
      TestGesture? finger;
      final touches = capture.touches;
      for (var i = 0; i < touches.length; i++) {
        final touch = touches[i];
        final t = start + touch.t;
        switch (touch.phase) {
          case 0:
            finger = await s.down(t, touch.at);
          case 3:
            await s.move(finger!, t, touch.at);
            await finger.up();
          case _:
            await s.move(finger!, t, touch.at);
        }
        if (swallows &&
            touch.phase == 3 &&
            i > 1 &&
            touches[i - 1].t == touches[i - 2].t) {
          await s.runTo(t + 1);
          expect(s.isOpen, isFalse, reason: '$name, the lift at $t');
          expect(s.shows('Copy'), isFalse, reason: '$name, the lift at $t');
        }
      }
      await s.runTo(start + touches.last.t + 1);
      return s;
    }

    testWidgets('a touch that starts as the close starts is swallowed', (
      tester,
    ) async {
      final s = await replay(
        tester,
        'center3-reopen-stroke.jsonl',
        swallows: true,
      );
      expect(s.chosen, isEmpty);
      expect(s.isOpen, isFalse);
    });

    for (final (name, chose) in const [
      ('center3-closemidopen.jsonl', <String>[]),
      ('center3-retap-midopen.jsonl', ['Copy']),
      ('center3-early-outside-10.jsonl', <String>[]),
      ('center3-early-outside-25.jsonl', <String>[]),
      ('center3-early-outside-50.jsonl', <String>[]),
      ('center3-early-outside-100.jsonl', <String>[]),
    ]) {
      testWidgets('a touch before the menu appears belongs to the menu: '
          '$name', (tester) async {
        final s = await replay(tester, name);
        expect(s.chosen, chose);
        expect(s.isOpen, isFalse);
        expect(s.shows('Copy'), isFalse);
      });
    }
  });

  group('a context menu (context_motion_test)', () {
    Future<MenuStage> held(WidgetTester tester) async {
      final s = MenuStage(tester);
      await s.show(
        Stack(
          children: [
            Positioned(
              left: 141,
              top: 260,
              width: 120,
              height: 80,
              child: GlassContextMenu(
                controller: s.controller,
                menuChildren: [
                  s.item('Copy'),
                  s.item('Share'),
                  s.item('Delete'),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      );
      return s;
    }

    const center = Offset(201, 300);

    testWidgets('a finger that held the menu open slides onto a row and '
        'chooses it on release', (tester) async {
      final s = await held(tester);
      final finger = await s.down(0, center);
      await s.runTo(ContextHold.openAfter - 1e-6);
      expect(s.isOpen, isFalse);
      await s.runTo(ContextHold.openAfter + 1e-6);
      expect(s.isOpen, isTrue);
      await s.runTo(1);
      await s.move(finger, 1.1, s.centerOf('Share'));
      expect(s.chosen, isEmpty);
      await s.up(finger, 1.2);
      await s.runTo(2.7);
      expect(s.chosen, ['Share']);
      expect(s.isOpen, isFalse);
    });

    testWidgets('released on the preview it keeps the menu open and chooses '
        'nothing', (tester) async {
      final s = await held(tester);
      final finger = await s.down(0, center);
      await s.runTo(1);
      expect(s.isOpen, isTrue);
      final preview = s.previewRect;
      final on = preview.center + const Offset(3, 2);
      await s.move(finger, 1.28, on);
      await s.up(finger, 1.38);
      await s.runTo(3);
      expect(s.isOpen, isTrue);
      expect(s.chosen, isEmpty);
    });
  });

  testWidgets('a finger held on the source opens the menu at the hold, '
      'slides into the rows and chooses the one it lifts from '
      '(hold_slide_test)', (tester) async {
    final s = MenuStage(tester);
    await s.show(
      Stack(
        children: [
          Positioned(
            left: 160,
            top: 200,
            width: 80,
            height: 44,
            child: GlassMenuAnchor(
              controller: s.controller,
              menuChildren: [
                for (final title in ['Copy', 'Share', 'Rename', 'Delete'])
                  s.item(title),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
    const source = Offset(200, 222);
    final finger = await s.down(0, source);
    await s.runTo(_tuning.holdDuration - 1e-6);
    expect(s.isOpen, isFalse);
    await s.runTo(_tuning.holdDuration + 1e-6);
    expect(s.isOpen, isTrue);
    await s.runTo(_tuning.holdDuration + 0.6);
    final rename = s.centerOf('Rename');
    var t = s.clock.now;
    for (var i = 1; i <= 20; i++) {
      t += 1 / 120;
      await s.move(finger, t, Offset.lerp(source, rename, i / 20)!);
    }
    expect(s.chosen, isEmpty);
    await s.up(finger, t + 1 / 120);
    await s.runTo(t + 1.5);
    expect(s.chosen, ['Rename']);
    expect(s.shows('Rename'), isFalse);
  });
}
