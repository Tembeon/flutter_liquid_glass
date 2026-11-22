import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

const _open = Spring.response(0.4, dampingRatio: 0.7);
const _close = Spring.response(0.25);

class _Card extends Motion {
  late final lift = own(Presence(openSpring: _open, closeSpring: _close));
}

void main() {
  test('opens and hides on its springs; status follows target and rest', () {
    final card = _Card();
    final twin = MotionValue<double>(0, spring: _open);
    expect(card.lift.status, PresenceStatus.hidden);
    card.lift.open(0);
    twin.retarget(0, 1);
    expect(card.lift.status, PresenceStatus.opening);
    card.advance(0.1);
    expect(card.lift.progress, twin.valueAt(0.1));
    card.advance(3);
    expect(card.lift.status, PresenceStatus.shown);
    card.lift.hide(3);
    expect(card.lift.status, PresenceStatus.leaving);
    card.advance(6);
    expect(card.lift.isHidden, isTrue);
  });

  test('turns from where it stands, velocity included', () {
    final card = _Card();
    final twin = MotionValue<double>(0, spring: _open);
    card.lift.open(0);
    twin.retarget(0, 1);
    card.advance(0.05);
    card.lift.hide(0.05);
    twin.retarget(0.05, 0, spring: _close);
    for (final t in [0.08, 0.15, 0.3]) {
      expect(card.lift.progressAt(t), twin.valueAt(t));
    }
  });

  test('a delayed open keeps it hidden until it starts', () {
    final card = _Card();
    card.lift.open(0, delay: 0.2);
    expect(card.lift.status, PresenceStatus.opening);
    expect(card.isSettled, isFalse);
    card.advance(0.1);
    expect(card.lift.progress, 0);
    card.advance(0.3);
    expect(card.lift.progress, greaterThan(0));
  });

  test('opacity clamps an overshoot', () {
    final card = _Card();
    card.lift.snap(0, 1.08);
    expect(card.lift.opacity, 1);
  });

  test('turn animates, snaps, and ignores redundant retargets', () {
    final presence = Presence(openSpring: _open, closeSpring: _close);
    expect(presence.isShown, isFalse);
    presence.turn(0, shown: true, animated: false);
    expect(presence.isShown, isTrue);
    expect(presence.progress, 1);
    expect(presence.status, PresenceStatus.shown);

    presence.turn(0.1, shown: false);
    expect(presence.isShown, isFalse);
    expect(presence.status, PresenceStatus.leaving);
    presence.advance(0.2);
    final mid = presence.progress;
    presence.turn(0.2, shown: false);
    presence.advance(0.25);
    expect(presence.progress, lessThan(mid));

    presence.hold(0.3, 0.4);
    expect(presence.progress, 0.4);
    presence.setVelocity(0.3, 5);
    presence.open(0.3);
    presence.advance(0.35);
    expect(presence.progress, greaterThan(0.5));
  });

  test('resolves open and close springs under reduceMotion', () {
    const reducedOpen = Spring.response(0.2);
    const open = Spring.response(0.4, dampingRatio: 0.7, reduced: reducedOpen);
    final reduced = Presence(openSpring: open, closeSpring: _close)
      ..traits = const MotionTraits(reduceMotion: true);
    final normal = Presence(openSpring: open, closeSpring: _close);
    reduced.open(0);
    normal.open(0);
    final twin = MotionValue<double>(0, spring: reducedOpen)..retarget(0, 1);
    reduced.advance(0.15);
    normal.advance(0.15);
    expect(reduced.progress, closeTo(twin.valueAt(0.15), 1e-9));
    expect(reduced.progress, isNot(closeTo(normal.progress, 1e-3)));
  });

  test('a snap that turns the direction where a hold left the progress is '
      'heard', () {
    final presence = Presence(openSpring: _open, clock: ManualMotionClock());
    final status = presence.select((motion) => motion.status);
    void listener() {}
    status.addListener(listener);
    addTearDown(() => status.removeListener(listener));
    presence.hold(0, 0.8);
    expect(status.value, PresenceStatus.hidden);
    presence.snap(0, 0.8);
    expect(status.value, PresenceStatus.shown);
  });

  test('a selection of a motion is settled only when the motion is', () {
    final presence = Presence(openSpring: _open, clock: ManualMotionClock())
      ..open(0);
    final selection = presence.select((motion) => motion.progress);
    void listener() {}
    selection.addListener(listener);
    presence.advance(0.05);
    expect(presence.isSettled, isFalse);
    expect(selection.isSettled, isFalse);
    presence
      ..advance(5)
      ..settle();
    expect(selection.isSettled, isTrue);
    selection.removeListener(listener);
  });
}
