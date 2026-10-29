import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _size = Size(100, 40);

PointerDownInput _down(double time, {Set<Axis> scroll = const {}}) =>
    PointerDownInput(
      time: time,
      pointer: 1,
      position: const Offset(50, 20),
      regionSize: _size,
      scrollAxes: scroll,
    );

PointerMoveInput _move(double time, Offset position) =>
    PointerMoveInput(time: time, pointer: 1, position: position);

PointerUpInput _up(double time, Offset position, {Offset velocity = .zero}) =>
    PointerUpInput(
      time: time,
      pointer: 1,
      position: position,
      velocity: velocity,
    );

void main() {
  group('PressInteraction', () {
    test('highlights inside its slop and taps on a release inside', () {
      final highlights = <bool>[];
      var taps = 0;
      final press = PressInteraction(
        releaseSlop: const EdgeInsets.all(20),
        onHighlightChanged: highlights.add,
        onTap: () => taps++,
      );
      final session = InteractionSession([press]);
      expect(session.handle(_down(0)).claim, isTrue);
      session.handle(_move(0.1, const Offset(110, 20)));
      session.handle(_move(0.2, const Offset(130, 20)));
      session.handle(_move(0.3, const Offset(90, 20)));
      final release = session.handle(_up(0.4, const Offset(90, 20)));
      expect(highlights, [true, false, true, false]);
      expect(taps, 1);
      expect(release.events.single, isA<ActivationEvent>());
    });

    test('a release outside does not tap', () {
      var taps = 0;
      final session = InteractionSession([
        PressInteraction(onTap: () => taps++),
      ]);
      session.handle(_down(0));
      final release = session.handle(_up(0.1, const Offset(200, 20)));
      expect(taps, 0);
      expect(release.events, isEmpty);
      expect(session.isActive, isFalse);
    });
  });

  group('InteractionSession', () {
    test('a long press that is recognized cancels the press', () {
      final heard = <String>[];
      final session = InteractionSession([
        LongPressInteraction(onStart: () => heard.add('long')),
        PressInteraction(onTap: () => heard.add('tap')),
      ]);
      session.handle(_down(0));
      session.advance(0.5);
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, ['long']);
    });

    test('the claims of content are ignored', () {
      final session = InteractionSession([
        DragInteraction(role: InteractionRole.content),
      ]);
      session.handle(_down(0));
      expect(session.handle(_move(0.05, const Offset(50, 60))).claim, isFalse);
    });

    test('a press and a drag together each keep their own timing', () {
      final heard = <String>[];
      final session = InteractionSession([
        PressInteraction(
          onHighlightChanged: (on) => heard.add('press $on'),
        ).simultaneously(
          DragInteraction(
            axis: Axis.horizontal,
            onStart: (_) => heard.add('drag'),
          ),
        ),
      ]);
      final down = session.handle(_down(0, scroll: {Axis.vertical}));
      expect(down.claim, isFalse);
      session.handle(_move(0.05, const Offset(80, 20)));
      expect(heard, ['drag']);
    });

    test('a second pointer during a touch is rejected', () {
      final session = InteractionSession([PressInteraction()]);
      session.handle(_down(0));
      final second = session.handle(
        const PointerDownInput(
          time: 0.1,
          pointer: 2,
          position: Offset(10, 10),
          regionSize: _size,
        ),
      );
      expect(second.reject, isTrue);
    });

    test('a control in a scroll view hears the touch 0.15 s after contact '
        'and claims then', () {
      final highlights = <bool>[];
      final session = InteractionSession([
        PressInteraction(onHighlightChanged: highlights.add),
      ]);
      final down = session.handle(_down(0, scroll: {Axis.vertical}));
      expect(down.claim, isFalse);
      expect(highlights, isEmpty);
      expect(session.nextDue, closeTo(0.15, 1e-12));
      expect(session.advance(0.1).claim, isFalse);
      expect(session.advance(0.15).claim, isTrue);
      expect(highlights, [true]);
    });

    test('a quick tap held back is delivered with its release', () {
      final heard = <String>[];
      final session = InteractionSession([
        PressInteraction(
          onHighlightChanged: (on) => heard.add(on ? 'on' : 'off'),
          onTap: () => heard.add('tap'),
        ),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      session.handle(_up(0.08, const Offset(50, 20)));
      expect(heard, ['on', 'off', 'tap']);
      expect(session.isActive, isFalse);
    });

    test('a touch a scroll takes while held back never reaches content', () {
      final heard = <bool>[];
      final session = InteractionSession([
        PressInteraction(
          role: InteractionRole.content,
          onHighlightChanged: heard.add,
        ),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      session.lost(1, 0.05);
      session.advance(0.3);
      expect(heard, isEmpty);
    });

    test('a region nothing accepts rejects the touch at once', () {
      final session = InteractionSession([PressInteraction()]);
      final output = session.handle(
        const PointerDownInput(
          time: 0,
          pointer: 1,
          position: Offset.zero,
          regionSize: _size,
          buttons: 2,
        ),
      );
      expect(output.reject, isTrue);
    });
  });

  group('LongPressInteraction', () {
    test('is recognized at its duration from contact and claims', () {
      final heard = <String>[];
      final long = LongPressInteraction(
        onStart: () => heard.add('start'),
        onCommit: () => heard.add('commit'),
      );
      final session = InteractionSession([long]);
      session.handle(_down(0));
      expect(session.nextDue, 0.5);
      final due = session.advance(0.5);
      expect(due.claim, isTrue);
      expect(due.events.single, isA<LongPressStartEvent>());
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, ['start', 'commit']);
    });

    test('fails when the finger travels first', () {
      var started = false;
      final session = InteractionSession([
        LongPressInteraction(onStart: () => started = true),
      ]);
      session.handle(_down(0));
      final move = session.handle(_move(0.2, const Offset(80, 20)));
      session.advance(0.6);
      expect(started, isFalse);
      expect(move.reject, isTrue);
    });
  });

  group('DragInteraction', () {
    test('starts past its slop and counts travel from there', () {
      final updates = <DragInteractionDetails>[];
      DragInteractionDetails? end;
      final drag = DragInteraction(
        axis: Axis.horizontal,
        onStart: updates.add,
        onUpdate: updates.add,
        onEnd: (details) => end = details,
      );
      final session = InteractionSession([drag]);
      session.handle(_down(0));
      expect(session.handle(_move(0.01, const Offset(55, 20))).claim, isFalse);
      expect(session.handle(_move(0.02, const Offset(70, 30))).claim, isTrue);
      session.handle(_move(0.03, const Offset(90, 20)));
      session.handle(
        _up(0.04, const Offset(90, 20), velocity: const Offset(400, 50)),
      );
      expect(updates.map((d) => d.translation.dx), [10, 30]);
      expect(updates.first.translation.dy, 0);
      expect(end!.velocity, const Offset(400, 0));
      expect(end!.time, 0.04);
    });

    test('does not hold a touch a scroll view shares its axis with', () {
      final session = InteractionSession([
        DragInteraction(axis: Axis.vertical),
      ]);
      session.handle(_down(0, scroll: {Axis.vertical}));
      final move = session.handle(_move(0.02, const Offset(50, 60)));
      expect(move.claim, isFalse);
    });

    test('tracks with a rubber band and settles on the projected stop', () {
      const spring = Spring.response(0.3, projection: 0.143);
      const details = DragInteractionDetails(
        time: 1,
        translation: Offset(0, 300),
        velocity: Offset(0, 900),
      );
      final track = DragInteraction.track(
        details,
        grab: 0,
        spring: spring,
        dimension: 100,
        bounds: (0, 200),
      );
      expect(track.value, greaterThan(200));
      expect(track.value, lessThan(300));
      expect(track.tracking, isTrue);
      final settle = DragInteraction.settle(
        details,
        position: 150,
        spring: spring,
        stops: [0, 200, 400],
      );
      expect(settle.value, 200);
      expect(settle.velocity, 900);
      final value = MotionValue<double>(150);
      settle.applyTo(value);
      expect(value.velocityAt(1), 900);
      expect(value.target, 200);
    });
  });

  group('TapInteraction', () {
    test('a single tap waits for the double tap to time out', () {
      final heard = <String>[];
      final double = TapInteraction(count: 2, onTap: () => heard.add('two'));
      final single = TapInteraction(onTap: () => heard.add('one'));
      final session = InteractionSession([double.exclusively(single)]);
      session.handle(_down(0));
      session.handle(_up(0.05, const Offset(50, 20)));
      expect(heard, isEmpty);
      expect(session.nextDue, closeTo(0.35, 1e-12));
      session.advance(0.35);
      expect(heard, ['one']);
    });

    test('a double tap is preferred to a single one, which waits', () {
      final heard = <String>[];
      final double = TapInteraction(count: 2, onTap: () => heard.add('two'));
      final single = TapInteraction(onTap: () => heard.add('one'));
      final session = InteractionSession([double.exclusively(single)]);
      session.handle(_down(0));
      session.handle(_up(0.05, const Offset(50, 20)));
      expect(heard, isEmpty);
      session.handle(_down(0.15));
      session.handle(_up(0.2, const Offset(50, 20)));
      expect(heard, ['two']);
    });
  });

  group('ScrubInteraction', () {
    test('selects the region under the finger and commits on release', () {
      final changes = <Object?>[];
      Object? committed;
      final scrub = ScrubInteraction(
        regions: {
          'a': const Rect.fromLTWH(0, 0, 100, 20),
          'b': const Rect.fromLTWH(0, 20, 100, 20),
        },
        onChanged: changes.add,
        onCommit: (key) => committed = key,
      );
      final session = InteractionSession([scrub]);
      session.handle(
        const PointerDownInput(
          time: 0,
          pointer: 1,
          position: Offset(10, 10),
          regionSize: _size,
        ),
      );
      session.handle(_move(0.1, const Offset(10, 30)));
      session.handle(_up(0.2, const Offset(10, 30)));
      expect(changes, ['a', 'b']);
      expect(committed, 'b');
    });
  });
}
