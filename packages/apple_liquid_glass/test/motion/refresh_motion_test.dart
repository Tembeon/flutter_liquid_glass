import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('the reveal follows the pull alone, as the passport tables it', () {
    const table = {
      10: 0.00,
      50: 0.13,
      90: 0.48,
      130: 0.84,
      150: 0.94,
      170: 1.00,
    };
    for (final MapEntry(key: pull, value: opacity) in table.entries) {
      expect(
        RefreshMotion.revealOf(pull.toDouble()),
        moreOrLessEquals(opacity, epsilon: 0.04),
        reason: 'pull $pull',
      );
    }
  });

  test('pulled, tick i takes 1 + i (opacity - 1) of the reveal', () {
    final clock = ManualMotionClock(frameRate: 60);
    final motion = RefreshMotion(clock: clock)..pull(90);
    final reveal = RefreshMotion.revealOf(90);
    expect(motion.opacity, reveal);
    expect(motion.tickOpacity(0), 1);
    expect(motion.tickOpacity(1), moreOrLessEquals(reveal));
    expect(motion.tickOpacity(7), 0);
  });

  test('at the trigger the ticks settle into the tail and spin a step '
      'every 0.125 s over a half turn of wind-up', () {
    final clock = ManualMotionClock(frameRate: 60);
    final motion = RefreshMotion(clock: clock)
      ..pull(180)
      ..trigger(0);
    clock.advanceTo(0.13);
    motion.advance(0.13);
    expect(motion.rotation, greaterThan(1 / 8));
    clock.advanceTo(2.01);
    motion.advance(2.01);
    for (var i = 0; i < 8; i++) {
      expect(motion.tickOpacity(i), moreOrLessEquals(0.08 * i, epsilon: 0.01));
    }
    expect(
      motion.rotation,
      moreOrLessEquals(2 + RefreshMotion.windUpTurns, epsilon: 0.01),
    );
  });

  test('the wind-up is a critically damped half turn of omega 8.86', () {
    final clock = ManualMotionClock(frameRate: 60);
    final motion = RefreshMotion(clock: clock)..trigger(0);
    clock.advanceTo(0.124);
    motion.advance(0.124);
    const turns = RefreshMotion.windUpTurns;
    const w = 8.86;
    const t = 0.124;
    const expected = turns * (1 - (1 + w * t) * 0.3329);
    expect(motion.rotation, moreOrLessEquals(expected, epsilon: 0.01));
  });

  test('at the end the steps stop and the ticks turn on to the next half '
      'turn in 0.3 s', () {
    final clock = ManualMotionClock(frameRate: 60);
    final motion = RefreshMotion(clock: clock)..trigger(0);
    clock.advanceTo(2.13);
    motion.advance(2.13);
    motion.end(2.13);
    final from = motion.rotation;
    clock.advanceTo(2.25);
    motion.advance(2.25);
    expect(motion.rotation, greaterThan(from));
    clock.advanceTo(2.5);
    motion.advance(2.5);
    expect(
      motion.rotation,
      moreOrLessEquals(2.5 + RefreshMotion.windUpTurns, epsilon: 0.01),
    );
  });
}
