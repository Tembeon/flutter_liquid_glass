import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('the coming page fades in over the going one, which shrinks at once '
      'and fades after its delay, and both rest within a second', () {
    final clock = ManualMotionClock();
    final motion = TabSwitchMotion(clock: clock)
      ..start(TabSwitchSpec.compact, reduceMotion: false);
    clock.advanceTo(0.04);
    expect(motion.comingOpacity.value, 0, reason: 'fade in waits 0.05 s');
    expect(motion.goingScale.value, lessThan(1));
    clock.advanceTo(0.15);
    expect(motion.comingOpacity.value, inExclusiveRange(0.5, 1));
    expect(motion.goingOpacity.value, 1, reason: 'fade out waits 0.183 s');
    expect(motion.comingScale.value, inExclusiveRange(0.9933, 1));
    clock.advanceTo(1);
    expect(motion.settledAt(1), isTrue);
    expect(motion.goingOpacity.value, closeTo(0, 1e-3));
    expect(motion.goingScale.value, closeTo(0.9933, 1e-4));
    expect(motion.comingOpacity.value, closeTo(1, 1e-3));
    expect(motion.comingScale.value, closeTo(1, 1e-4));
  });

  test('under Reduce Motion the pages only fade', () {
    final clock = ManualMotionClock();
    final motion = TabSwitchMotion(clock: clock)
      ..start(TabSwitchSpec.regular, reduceMotion: true);
    for (final t in [0.05, 0.2, 0.5, 1.0]) {
      clock.advanceTo(t);
      expect(motion.goingScale.value, 1);
      expect(motion.comingScale.value, 1);
    }
    expect(motion.goingOpacity.value, closeTo(0, 1e-3));
  });
}
