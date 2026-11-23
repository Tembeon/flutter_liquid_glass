import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

import 'scrub_interaction.dart';

const _size = Size(100, 40);

PointerDownInput _down(double t, Offset p) =>
    PointerDownInput(time: t, pointer: 1, position: p, regionSize: _size);

PointerMoveInput _move(double t, Offset p) => PointerMoveInput(
  time: t,
  pointer: 1,
  position: p,
  regionBox: Offset.zero & _size,
);

PointerUpInput _up(double t, Offset p, {Offset velocity = Offset.zero}) =>
    PointerUpInput(
      time: t,
      pointer: 1,
      position: p,
      regionBox: Offset.zero & _size,
      velocity: velocity,
    );

class _Log extends PointerFollower {
  final List<String> log = [];

  @override
  void down(PointerDownInput input) =>
      log.add('down ${input.time} ${input.position}');

  @override
  void move(PointerMoveInput input) =>
      log.add('move ${input.time} ${input.position}');

  @override
  void up(PointerUpInput input) =>
      log.add('up ${input.time} ${input.position} ${input.velocity}');

  @override
  void cancel(PointerCancelInput input) => log.add('cancel ${input.time}');
}

class _Frames extends PointerFollower {
  final List<String> log = [];

  @override
  void down(PointerDownInput input) => log.add('down ${input.position}');

  @override
  void move(PointerMoveInput input) =>
      log.add('move ${input.position} ${input.regionBox}');

  @override
  void up(PointerUpInput input) {}

  @override
  void cancel(PointerCancelInput input) {}
}

void main() {
  group('InputPort', () {
    test('a hold hands the rest of the touch on, stamps kept, positions '
        'mapped into the receiver', () {
      final port = InputPort();
      final menu = _Log();
      final receiver = InteractionSession([FollowInteraction(menu)]);
      port.attach(
        (event) => receiver.handle(
          event.input((p) => p + const Offset(-10, 100), regionBox: Rect.zero),
        ),
      );
      final source = InteractionSession([
        LongPressInteraction().sequenced(port.forward),
      ]);
      source.handle(_down(0, const Offset(50, 20)));
      source.advance(0.5);
      source.handle(_move(0.6, const Offset(50, 30)));
      source.handle(
        _up(0.7, const Offset(50, 30), velocity: const Offset(0, 200)),
      );
      expect(menu.log, [
        'down 0.5 Offset(40.0, 120.0)',
        'move 0.6 Offset(40.0, 130.0)',
        'up 0.7 Offset(40.0, 130.0) Offset(0.0, 200.0)',
      ]);
    });

    test('a staged press overdue on both stages hands on at its '
        'recognition, not at its arming', () {
      final port = InputPort();
      final menu = _Log();
      final receiver = InteractionSession([FollowInteraction(menu)]);
      port.attach(
        (event) => receiver.handle(event.input((p) => p, regionBox: Rect.zero)),
      );
      final source = InteractionSession([
        LongPressInteraction(
          duration: 0.78,
          armAfter: 0.42,
        ).sequenced(port.forward),
      ]);
      source.handle(_down(0, const Offset(50, 20)));
      source.advance(1);
      expect(menu.log, ['down 0.78 Offset(50.0, 20.0)']);
    });

    test('a touch that ends before a receiver comes is dropped: the '
        'receiver hears the next hand-off only', () {
      final port = InputPort();
      final source = InteractionSession([
        LongPressInteraction().sequenced(port.forward),
      ]);
      source.handle(_down(0, const Offset(50, 20)));
      source.advance(0.5);
      source.handle(_up(0.6, const Offset(50, 20)));
      final menu = _Log();
      final receiver = InteractionSession([FollowInteraction(menu)]);
      port.attach(
        (event) => receiver.handle(event.input((p) => p, regionBox: Rect.zero)),
      );
      expect(menu.log, isEmpty);
      source.handle(_down(1, const Offset(50, 30)));
      source.advance(1.5);
      expect(menu.log, ['down 1.5 Offset(50.0, 30.0)']);
    });

    test('inputs wait for a receiver and arrive with their own stamps', () {
      final port = InputPort();
      final source = InteractionSession([
        LongPressInteraction().sequenced(port.forward),
      ]);
      source.handle(_down(0, const Offset(50, 20)));
      source.advance(0.5);
      source.handle(_move(0.52, const Offset(51, 25)));
      final menu = _Log();
      final receiver = InteractionSession([FollowInteraction(menu)]);
      port.attach(
        (event) => receiver.handle(event.input((p) => p, regionBox: Rect.zero)),
      );
      source.handle(_move(0.6, const Offset(52, 30)));
      expect(menu.log, [
        'down 0.5 Offset(50.0, 20.0)',
        'move 0.52 Offset(51.0, 25.0)',
        'move 0.6 Offset(52.0, 30.0)',
      ]);
    });
  });

  testWidgets('a region that leaves lets go of its port: the next hand-off '
      'waits for the region that comes', (tester) async {
    MotionClock.debugReset();
    final port = InputPort();
    Widget region(_Log log) => Directionality(
      textDirection: TextDirection.ltr,
      child: InputRegion(
        port: port,
        interactions: [FollowInteraction(log)],
        child: const SizedBox.expand(),
      ),
    );
    final first = _Log();
    final second = _Log();
    await tester.pumpWidget(region(first));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final source = InteractionSession([
      LongPressInteraction().sequenced(port.forward),
    ]);
    source.handle(_down(0, const Offset(50, 20)));
    source.advance(0.5);
    await tester.pumpWidget(region(second));
    await tester.pump();
    expect(first.log, isEmpty);
    expect(second.log, ['down 0.5 Offset(50.0, 20.0)']);
  });

  testWidgets('a touch handed on stays in the coordinates of its hand-off '
      'while the receiver moves, as a landed touch stays in those of its '
      'down', (tester) async {
    MotionClock.debugReset();
    final port = InputPort();
    final follower = _Frames();
    final interactions = [
      ScrubInteraction(hit: (p) => 'row'),
      FollowInteraction(follower),
    ];
    Widget region(double left) => Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: 0,
            width: 100,
            height: 40,
            child: InputRegion(
              port: port,
              interactions: interactions,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(region(0));
    await tester.pump();
    final source = InteractionSession([
      LongPressInteraction().sequenced(port.forward),
    ]);
    source.handle(_down(0, const Offset(50, 20)));
    source.advance(0.5);
    await tester.pumpWidget(region(30));
    source.handle(_move(0.6, const Offset(60, 20)));
    expect(follower.log, [
      'down Offset(50.0, 20.0)',
      'move Offset(60.0, 20.0) Rect.fromLTRB(30.0, 0.0, 130.0, 40.0)',
    ]);
  });

  testWidgets('a held touch reaches a region in an overlay that appears '
      'above the finger, and the source never loses it', (tester) async {
    MotionClock.debugReset();
    final port = InputPort();
    final controller = OverlayPortalController();
    final hold = <String>[];
    final rows = <Object?>[];
    Object? committed;
    final interactions = [
      LongPressInteraction(
        onStart: (t) {
          hold.add('start');
          controller.show();
        },
        onCommit: (t) => hold.add('release'),
        onCancel: (t) => hold.add('cancel'),
      ).sequenced(port.forward),
    ];
    final menu = [
      ScrubInteraction(
        hit: (p) => p.dy < 40 ? 'copy' : 'paste',
        onChanged: (row, t) => rows.add(row),
        onCommit: (row, t) => committed = row,
      ),
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Center(
                child: OverlayPortal(
                  controller: controller,
                  overlayChildBuilder: (context) => Positioned(
                    left: 0,
                    top: 0,
                    width: 200,
                    height: 80,
                    child: InputRegion(
                      port: port,
                      interactions: menu,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  child: InputRegion(
                    interactions: interactions,
                    child: const SizedBox(width: 100, height: 40),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox).last),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.isShowing, isTrue);
    await gesture.moveTo(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(const Offset(20, 60));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(rows.last, 'paste');
    expect(committed, 'paste');
    expect(hold, ['start', 'release']);
  });
}
