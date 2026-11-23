import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/input.dart';

import 'scrub_interaction.dart';

const _size = Size(100, 40);

PointerDownInput _down(double time, {Set<Axis> scroll = const {}}) =>
    PointerDownInput(
      time: time,
      pointer: 1,
      position: const Offset(50, 20),
      regionSize: _size,
      scrollAxes: scroll,
    );

PointerDownInput _downAt(
  double time,
  Offset position, {
  TextDirection textDirection = .ltr,
}) => PointerDownInput(
  time: time,
  pointer: 1,
  position: position,
  regionSize: _size,
  textDirection: textDirection,
);

PointerMoveInput _move(
  double time,
  Offset position, {
  Rect box = const Rect.fromLTWH(0, 0, 100, 40),
}) => PointerMoveInput(
  time: time,
  pointer: 1,
  position: position,
  regionBox: box,
);

PointerUpInput _up(
  double time,
  Offset position, {
  Offset velocity = .zero,
  Rect box = const Rect.fromLTWH(0, 0, 100, 40),
}) => PointerUpInput(
  time: time,
  pointer: 1,
  position: position,
  regionBox: box,
  velocity: velocity,
);

final class _Value extends Interaction {
  final List<(ValueCommand, ActivationSource)> heard = [];

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.adjustment};

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) heard.add((input.command, input.source));
    return InteractionUpdate.none;
  }
}

final class _Wheel extends Interaction {
  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.wheel};

  @override
  InteractionUpdate handle(InteractionInput input) => InteractionUpdate.none;
}

void main() {
  test('a mirrored touch reflects its position, box and velocity about the '
      "region's width and keeps its global ones", () {
    const global = Offset(500, 300);
    final down = const PointerDownInput(
      time: 0,
      pointer: 1,
      position: Offset(30, 10),
      regionSize: _size,
      globalPosition: global,
    ).mirrored(100);
    final move = const PointerMoveInput(
      time: 0.1,
      pointer: 1,
      position: Offset(40, 10),
      regionBox: Rect.fromLTRB(10, 0, 110, 40),
      globalPosition: global,
    ).mirrored(100);
    final up = const PointerUpInput(
      time: 0.2,
      pointer: 1,
      position: Offset(40, 10),
      regionBox: Rect.fromLTRB(0, 0, 100, 40),
      velocity: Offset(200, 5),
      globalPosition: global,
      globalVelocity: Offset(200, 5),
    ).mirrored(100);
    expect(down.position, const Offset(70, 10));
    expect(down.globalPosition, global);
    expect(move.position, const Offset(60, 10));
    expect(move.regionBox, const Rect.fromLTRB(-10, 0, 90, 40));
    expect(move.globalPosition, global);
    expect(up.velocity, const Offset(-200, 5));
    expect(up.globalVelocity, const Offset(200, 5));
  });

  group('value commands', () {
    test('reach every interaction of a session with their source', () {
      final value = _Value();
      final session = InteractionSession([PressInteraction(), value]);
      session.handle(
        const AdjustInput(time: 1, command: ValueCommand.toMaximum),
      );
      session.handle(
        const AdjustInput(
          time: 2,
          command: ValueCommand.decrease,
          source: ActivationSource.accessibility,
        ),
      );
      expect(value.heard, [
        (ValueCommand.toMaximum, ActivationSource.keyboard),
        (ValueCommand.decrease, ActivationSource.accessibility),
      ]);
    });

    test('a relation adjusts when a part does', () {
      bool adjusts(Interaction i) => i.takes.contains(InputKind.adjustment);
      expect(adjusts(PressInteraction()), isFalse);
      expect(adjusts(PressInteraction().exclusively(_Value())), isTrue);
      expect(adjusts(_Value().sequenced(PressInteraction())), isTrue);
      expect(adjusts(PressInteraction().sequenced(_Value())), isFalse);
    });
  });

  group('CommandInteraction', () {
    test('takes what it has a callback for and no touch', () {
      final activates = CommandInteraction(onActivate: (_) {});
      expect(activates.takes, {InputKind.activation});
      expect(activates.accepts(_down(0)), isFalse);
      expect(CommandInteraction(onAdjust: (_) {}).takes, {
        InputKind.adjustment,
      });
    });

    test('answers an activation with an ActivationEvent, as a press does, '
        'and a value command with its callback', () {
      final heard = <Object>[];
      final command = CommandInteraction(
        onActivate: (input) => heard.add(input.source),
        onAdjust: (input) => heard.add(input.command),
      );
      final activated = command.handle(
        const ActivateInput(time: 1, source: ActivationSource.accessibility),
      );
      expect(
        activated.events.single,
        isA<ActivationEvent>()
            .having((e) => e.time, 'time', 1)
            .having((e) => e.source, 'source', ActivationSource.accessibility),
      );
      final adjusted = command.handle(
        const AdjustInput(time: 2, command: ValueCommand.increase),
      );
      expect(adjusted.events, isEmpty);
      expect(heard, [ActivationSource.accessibility, ValueCommand.increase]);
    });
  });

  group('SecondaryClickInteraction', () {
    test('a secondary press clicks at once and the press does not hear '
        'it', () {
      final clicks = <(double, Offset)>[];
      var taps = 0;
      final press = PressInteraction(onTap: (t) => taps++);
      final session = InteractionSession([
        press,
        SecondaryClickInteraction(
          onClick: (t, position) => clicks.add((t, position)),
        ),
      ]);
      final output = session.handle(
        const PointerDownInput(
          time: 1,
          pointer: 1,
          position: Offset(10, 5),
          regionSize: _size,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        ),
      );
      expect(output.claim, isTrue);
      expect(press.pressed, isFalse);
      session.handle(_up(1.1, const Offset(10, 5)));
      expect(clicks, [(1.0, const Offset(10, 5))]);
      session.handle(_down(2));
      session.handle(_up(2.1, const Offset(50, 20)));
      expect(clicks, hasLength(1));
      expect(taps, 1);
    });

    test('a relation takes the wheel when a part does', () {
      bool wheel(Interaction i) => i.takes.contains(InputKind.wheel);
      expect(wheel(PressInteraction()), isFalse);
      expect(wheel(PressInteraction().exclusively(_Wheel())), isTrue);
      expect(wheel(_Wheel().sequenced(PressInteraction())), isTrue);
    });
  });

  group('DwellInteraction', () {
    PointerHoverInput hover(double time, {bool inside = true}) =>
        PointerHoverInput(
          time: time,
          position: const Offset(10, 10),
          inside: inside,
        );

    test('fires once at its due time after the pointer enters, through a '
        'session between touches', () {
      final fired = <double>[];
      final dwell = DwellInteraction(duration: 0.3, onDwell: fired.add);
      final session = InteractionSession([PressInteraction(), dwell]);
      session.handle(hover(1));
      session.handle(hover(1.1));
      expect(session.nextDue, 1.3);
      session.advance(1.2);
      expect(fired, isEmpty);
      session.advance(1.5);
      expect(fired, [1.3]);
      expect(session.nextDue, isNull);
      session.advance(2);
      expect(fired, [1.3]);
    });

    test('leaving before the due time cancels it; a leave stamped after it '
        'fires it first', () {
      final fired = <double>[];
      final dwell = DwellInteraction(duration: 0.3, onDwell: fired.add);
      dwell.handle(hover(0));
      dwell.handle(hover(0.2, inside: false));
      expect(dwell.waiting, isFalse);
      dwell.advance(1);
      expect(fired, isEmpty);
      dwell.handle(hover(2));
      dwell.handle(hover(2.4, inside: false));
      expect(fired, [2.3]);
    });

    test('a touch waits from its contact, a held delivery too, and a lift '
        'before the due time ends the wait', () {
      final fired = <double>[];
      final dwell = DwellInteraction(duration: 0.525, onDwell: fired.add);
      final session = InteractionSession([dwell]);
      session.handle(_down(0));
      session.handle(_up(0.5, const Offset(50, 20)));
      session.advance(1);
      expect(fired, isEmpty);
      session.handle(
        const PointerDownInput(
          time: 1.2,
          contactTime: 1,
          pointer: 1,
          position: Offset(50, 20),
          regionSize: _size,
        ),
      );
      expect(session.nextDue, 1.525);
      final output = session.advance(1.6);
      expect(fired, [1.525]);
      expect(output.claim, isFalse);
    });

    test('a finger that leaves the reach ends the wait and one that comes '
        'back starts it again', () {
      final fired = <double>[];
      final dwell = DwellInteraction(duration: 0.5, onDwell: fired.add);
      dwell.handle(_down(0));
      dwell.handle(_move(0.3, const Offset(150, 20)));
      expect(dwell.waiting, isFalse);
      dwell.handle(_move(0.4, const Offset(60, 20)));
      dwell.handle(_move(0.6, const Offset(70, 20)));
      dwell.advance(0.85);
      expect(fired, isEmpty);
      dwell.advance(0.9);
      expect(fired, [0.9]);
    });

    test('without hovers the mouse starts nothing; with them, one that rests '
        'and presses keeps the wait its entry started', () {
      final touchOnly = <double>[];
      final menu = DwellInteraction(
        duration: 0.3,
        hovers: false,
        onDwell: touchOnly.add,
      );
      menu.handle(hover(0));
      menu.advance(1);
      expect(touchOnly, isEmpty);

      final fired = <double>[];
      final dwell = DwellInteraction(duration: 0.3, onDwell: fired.add);
      dwell.handle(hover(2));
      dwell.handle(_down(2.2));
      dwell.advance(2.4);
      expect(fired, [2.3]);
      dwell.handle(_up(2.5, const Offset(50, 20)));
      dwell.advance(3);
      expect(fired, [2.3]);
    });
  });

  group('PressInteraction', () {
    test('highlights inside the reach of its region and taps on a release '
        'inside', () {
      final highlights = <bool>[];
      var taps = 0;
      final press = PressInteraction(
        onHighlightChanged: (t, {required highlighted}) =>
            highlights.add(highlighted),
        onTap: (t) => taps++,
      );
      final session = InteractionSession([press]);
      const down = PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset(50, 20),
        regionSize: _size,
        reach: PressReach(slop: 20),
      );
      expect(session.handle(down).claim, isTrue);
      session.handle(_move(0.1, const Offset(110, 20)));
      session.handle(_move(0.2, const Offset(130, 20)));
      session.handle(_move(0.3, const Offset(90, 20)));
      final release = session.handle(_up(0.4, const Offset(90, 20)));
      expect(highlights, [true, false, true, false]);
      expect(taps, 1);
      expect(release.events.single, isA<ActivationEvent>());
    });

    test('the reach holds the box of the region as it is at each input', () {
      var taps = 0;
      final session = InteractionSession([
        PressInteraction(onTap: (t) => taps++),
      ]);
      PointerDownInput down() => const PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset(50, 20),
        regionSize: _size,
        reach: PressReach(minimumHit: Size(44, 44), slop: 10),
      );
      const shrunk = Rect.fromLTWH(30, 10, 40, 20);
      session.handle(down());
      session.handle(_up(0.1, const Offset(85, 20), box: shrunk));
      expect(taps, 0, reason: '15 past the shrunk box, within the old one');
      session.handle(down());
      session.handle(_up(0.2, const Offset(50, -1), box: shrunk));
      expect(taps, 1, reason: 'the 44 point minimum around the shrunk box');
      session.handle(down());
      session.handle(_up(0.3, const Offset(79, 20), box: shrunk));
      expect(taps, 2, reason: '9 past the shrunk box, within the slop');
    });

    test('a release outside does not tap', () {
      var taps = 0;
      final session = InteractionSession([
        PressInteraction(onTap: (t) => taps++),
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
        LongPressInteraction(onStart: (t) => heard.add('long')),
        PressInteraction(onTap: (t) => heard.add('tap')),
      ]);
      session.handle(_down(0));
      session.advance(0.5);
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, ['long']);
    });

    test('a press claims at the down; its role decides whether that holds', () {
      for (final (role, holds) in [
        (InteractionRole.gesture, true),
        (InteractionRole.control, true),
        (InteractionRole.content, false),
      ]) {
        final session = InteractionSession([PressInteraction(role: role)]);
        expect(session.handle(_down(0)).claim, holds, reason: '$role');
      }
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
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add('press $highlighted'),
        ),
        DragInteraction(
          axis: Axis.horizontal,
          onStart: (_) => heard.add('drag'),
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
        PressInteraction(
          onHighlightChanged: (t, {required highlighted}) =>
              highlights.add(highlighted),
        ),
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
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add(highlighted ? 'on' : 'off'),
          onTap: (t) => heard.add('tap'),
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
          onHighlightChanged: (t, {required highlighted}) =>
              heard.add(highlighted),
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
    test('is recognized at its duration from contact, however late the '
        'frame that runs it, and claims', () {
      final heard = <(String, double)>[];
      final long = LongPressInteraction(
        onStart: (t) => heard.add(('start', t)),
        onCommit: (t) => heard.add(('commit', t)),
      );
      final session = InteractionSession([long]);
      session.handle(_down(0.01));
      expect(session.nextDue, 0.51);
      final due = session.advance(0.523);
      expect(due.claim, isTrue);
      expect((due.events.single as LongPressStartEvent).time, 0.51);
      session.handle(_up(0.7, const Offset(50, 20)));
      expect(heard, [('start', 0.51), ('commit', 0.7)]);
    });

    test('fails when the finger travels first', () {
      var started = false;
      final session = InteractionSession([
        LongPressInteraction(onStart: (t) => started = true),
      ]);
      session.handle(_down(0));
      final move = session.handle(_move(0.2, const Offset(80, 20)));
      session.advance(0.6);
      expect(started, isFalse);
      expect(move.reject, isTrue);
    });

    test('without an allowable movement it holds the finger as far as its '
        "region's reach and fails beyond it, for good", () {
      final failed = <double>[];
      final long = LongPressInteraction(
        allowableMovement: null,
        onFail: failed.add,
      );
      final session = InteractionSession([long]);
      session.handle(
        const PointerDownInput(
          time: 0,
          pointer: 1,
          position: Offset(50, 20),
          regionSize: _size,
          reach: PressReach(slop: 30),
        ),
      );
      expect(session.handle(_move(0.1, const Offset(125, 60))).reject, false);
      expect(failed, isEmpty);
      expect(session.handle(_move(0.2, const Offset(131, 20))).reject, true);
      expect(failed, [0.2]);
      session.handle(_move(0.3, const Offset(50, 20)));
      expect(session.advance(1).events, isEmpty);
    });

    test('a staged press arms at its time and holds the touch; a release '
        'then recognizes it there', () {
      final heard = <(String, double)>[];
      final long = LongPressInteraction(
        duration: 0.78,
        armAfter: 0.42,
        allowableMovement: 18,
        onArmed: (t) => heard.add(('armed', t)),
        onStart: (t) => heard.add(('start', t)),
        onCommit: (t) => heard.add(('commit', t)),
        onFail: (t) => heard.add(('fail', t)),
      );
      final session = InteractionSession([long]);
      session.handle(_down(0));
      expect(session.nextDue, 0.42);
      final armed = session.advance(0.43);
      expect(armed.claim, isTrue);
      expect((armed.events.single as LongPressArmEvent).time, 0.42);
      expect(session.nextDue, 0.78);
      final up = session.handle(_up(0.6, const Offset(55, 20)));
      expect((up.events.single as LongPressStartEvent).time, 0.6);
      expect(heard, [('armed', 0.42), ('start', 0.6), ('commit', 0.6)]);
    });

    test('a staged press released before it arms fails, and travel fails '
        'it once armed, without giving up the touch it holds', () {
      final heard = <(String, double)>[];
      LongPressInteraction staged() => LongPressInteraction(
        duration: 0.78,
        armAfter: 0.42,
        allowableMovement: 18,
        onStart: (t) => heard.add(('start', t)),
        onFail: (t) => heard.add(('fail', t)),
      );
      final early = InteractionSession([staged()]);
      early.handle(_down(0));
      expect(early.handle(_up(0.4, const Offset(50, 20))).reject, isTrue);
      expect(heard, [('fail', 0.4)]);
      heard.clear();

      final dragged = InteractionSession([staged()]);
      dragged.handle(_down(0));
      dragged.advance(0.5);
      final move = dragged.handle(_move(0.55, const Offset(50, 39)));
      expect(move.reject, isFalse);
      dragged.advance(1);
      dragged.handle(_up(1.1, const Offset(50, 39)));
      expect(heard, [('fail', 0.55)]);
    });

    test('a late frame, or a late delivery, arms and recognizes each at its '
        'own time, in order', () {
      final heard = <(String, double)>[];
      LongPressInteraction staged() => LongPressInteraction(
        duration: 0.78,
        armAfter: 0.42,
        onArmed: (t) => heard.add(('armed', t)),
        onStart: (t) => heard.add(('start', t)),
      );
      final late = InteractionSession([staged()]);
      late.handle(_down(0));
      final update = late.advance(0.9);
      expect(update.events.map((e) => e.time), [0.42, 0.78]);
      expect(heard, [('armed', 0.42), ('start', 0.78)]);
      heard.clear();

      final held = staged();
      final update2 = held.handle(
        const PointerDownInput(
          time: 1,
          contactTime: 0,
          pointer: 1,
          position: Offset(50, 20),
          regionSize: _size,
        ),
      );
      expect(update2.recognizes, isTrue);
      expect(heard, [('armed', 0.42), ('start', 0.78)]);
    });

    test('contends with the controls inside its region when told, also '
        'sequenced or exclusive', () {
      expect(LongPressInteraction().contendsWithControls, isFalse);
      final contending = LongPressInteraction(contends: true);
      expect(contending.contendsWithControls, isTrue);
      expect(
        contending.sequenced(InputPort().forward).contendsWithControls,
        isTrue,
      );
      expect(
        contending.exclusively(PressInteraction()).contendsWithControls,
        isTrue,
      );
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

    test('contending, it waits out the arena slop of the touch: a pixel '
        'for a mouse, the touch slop for a finger', () {
      for (final (kind, starts) in [
        (PointerDeviceKind.mouse, true),
        (PointerDeviceKind.touch, false),
      ]) {
        var started = false;
        final drag = DragInteraction(
          axis: Axis.horizontal,
          slop: 2,
          contends: true,
          onStart: (_) => started = true,
        );
        drag.handle(
          PointerDownInput(
            time: 0,
            pointer: 1,
            position: const Offset(50, 20),
            regionSize: _size,
            kind: kind,
          ),
        );
        drag.handle(_move(0.02, const Offset(60, 20)));
        expect(started, starts, reason: '$kind');
      }
    });

    List<double> travelOf({
      required bool followsTextDirection,
      required TextDirection textDirection,
    }) {
      final travel = <double>[];
      final drag = DragInteraction(
        axis: Axis.horizontal,
        followsTextDirection: followsTextDirection,
        onStart: (d) => travel.add(d.translation.dx),
        onUpdate: (d) => travel.add(d.translation.dx),
      );
      final session = InteractionSession([drag]);
      session.handle(
        _downAt(0, const Offset(96, 20), textDirection: textDirection),
      );
      session.handle(_move(0.01, const Offset(80, 20)));
      session.handle(_move(0.02, const Offset(70, 20)));
      return travel;
    }

    test('following the text direction, a right-to-left touch travels '
        'from right to left', () {
      expect(
        travelOf(followsTextDirection: true, textDirection: .rtl),
        [6, 16],
      );
      expect(
        travelOf(followsTextDirection: true, textDirection: .ltr),
        [-6, -16],
      );
    });

    test('a drag that does not follow the text direction never mirrors', () {
      expect(
        travelOf(followsTextDirection: false, textDirection: .rtl),
        [-6, -16],
      );
    });
  });

  group('TapInteraction', () {
    test('without a slop of its own it moves as far as the touch allows', () {
      for (final (touchSlop, taps) in [(30.0, true), (18.0, false)]) {
        var tapped = false;
        final tap = TapInteraction(onTap: (t) => tapped = true);
        tap.handle(
          PointerDownInput(
            time: 0,
            pointer: 1,
            position: const Offset(50, 20),
            regionSize: _size,
            gestureSettings: DeviceGestureSettings(touchSlop: touchSlop),
          ),
        );
        tap.handle(_move(0.02, const Offset(74, 20)));
        tap.handle(_up(0.05, const Offset(74, 20)));
        expect(tapped, taps, reason: 'touch slop $touchSlop');
      }
    });

    test('a single tap waits for the double tap to time out', () {
      final heard = <String>[];
      final double = TapInteraction(count: 2, onTap: (t) => heard.add('two'));
      final single = TapInteraction(onTap: (t) => heard.add('one'));
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
      final double = TapInteraction(count: 2, onTap: (t) => heard.add('two'));
      final single = TapInteraction(onTap: (t) => heard.add('one'));
      final session = InteractionSession([double.exclusively(single)]);
      session.handle(_down(0));
      session.handle(_up(0.05, const Offset(50, 20)));
      expect(heard, isEmpty);
      session.handle(_down(0.15));
      session.handle(_up(0.2, const Offset(50, 20)));
      expect(heard, ['two']);
    });
  });

  group('relations', () {
    test('activates when a press or a tap is in it', () {
      bool activates(Interaction i) => i.takes.contains(InputKind.activation);
      expect(activates(PressInteraction()), isTrue);
      expect(activates(TapInteraction()), isTrue);
      expect(activates(DragInteraction()), isFalse);
      expect(
        activates(LongPressInteraction().sequenced(PressInteraction())),
        isFalse,
      );
    });

    test('an exclusive relation takes what either part takes, a sequence '
        'what its first part takes', () {
      final press = PressInteraction();
      final secondary = SecondaryClickInteraction();
      expect(press.exclusively(secondary).takes, {
        InputKind.pointer,
        InputKind.activation,
        InputKind.contextMenu,
      });
      expect(press.sequenced(secondary).takes, press.takes);
      expect(secondary.sequenced(press).takes, secondary.takes);
    });

    test('sequenced hands the rest of the touch on from the moment the '
        'first recognizes, where the finger is then', () {
      final heard = <String>[];
      final rows = ScrubInteraction(
        hit: (p) => p.dy > 30 ? 'row' : null,
        onChanged: (selected, t) => heard.add('over $selected at $t'),
        onCommit: (selected, t) => heard.add('commit $selected at $t'),
      );
      final session = InteractionSession([
        LongPressInteraction(
          onStart: (t) => heard.add('hold at $t'),
        ).sequenced(rows),
      ]);
      session.handle(_down(0));
      session.handle(_move(0.3, const Offset(52, 22)));
      session.advance(0.55);
      session.handle(_move(0.6, const Offset(52, 35)));
      session.handle(_up(0.7, const Offset(52, 35)));
      expect(heard, [
        'hold at 0.5',
        'over row at 0.6',
        'commit row at 0.7',
      ]);
    });

    test('sequenced continues the touch: a timed reaction of the next '
        'counts from the contact', () {
      final heard = <double>[];
      final session = InteractionSession([
        LongPressInteraction().sequenced(
          LongPressInteraction(duration: 0.8, onStart: heard.add),
        ),
      ]);
      session.handle(_down(0));
      session.advance(0.5);
      session.advance(0.8);
      expect(heard, [0.8]);
    });

    test('sequenced hears nothing on a touch the first gives up', () {
      var heard = 0;
      final session = InteractionSession([
        LongPressInteraction().sequenced(
          FollowInteraction(_Count(() => heard++)),
        ),
      ]);
      session.handle(_down(0));
      session.handle(_move(0.1, const Offset(90, 20)));
      session.handle(_up(0.2, const Offset(90, 20)));
      expect(heard, 0);
    });
  });

  group('FollowInteraction', () {
    test('feeds one pointer as it lands, in any text direction, and '
        'decides nothing', () {
      final follower = _Log();
      final follow = FollowInteraction(follower);
      final session = InteractionSession([follow]);
      final down = session.handle(
        _downAt(0, const Offset(50, 20), textDirection: .rtl),
      );
      session.handle(_move(0.1, const Offset(30, 20)));
      session.handle(
        _up(0.2, const Offset(30, 20), velocity: const Offset(100, 5)),
      );
      expect(down.claim, isFalse);
      expect(follower.log, [
        'down 50.0',
        'move 30.0',
        'up 30.0 100.0',
      ]);
    });
  });
}

class _Log extends PointerFollower {
  final List<String> log = [];

  @override
  void down(PointerDownInput input) => log.add('down ${input.position.dx}');

  @override
  void move(PointerMoveInput input) => log.add('move ${input.position.dx}');

  @override
  void up(PointerUpInput input) =>
      log.add('up ${input.position.dx} ${input.velocity.dx}');

  @override
  void cancel(PointerCancelInput input) => log.add('cancel');
}

class _Count extends PointerFollower {
  _Count(this.heard);

  final VoidCallback heard;

  @override
  void down(PointerDownInput input) => heard();

  @override
  void move(PointerMoveInput input) => heard();

  @override
  void up(PointerUpInput input) => heard();

  @override
  void cancel(PointerCancelInput input) => heard();
}
