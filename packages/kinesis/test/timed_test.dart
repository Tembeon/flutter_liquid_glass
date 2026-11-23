import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/value.dart' show MotionValueInternal;
import 'package:kinesis/testing.dart';

final class _Fade extends Motion {
  _Fade({super.clock});

  late final value = own(MotionValue<double>(0));
}

void main() {
  test('runs a curve over its duration and rests at its end', () {
    final m = _Fade();
    m.value.animate(0, 1, animation: const TimingCurve(0.5));
    expect(m.value.valueAt(0.25), Curves.easeInOut.transform(0.5));
    expect(m.value.restTime(), 0.5);
    expect(m.value.restsAt(0.3), isFalse);
    m.advance(0.5);
    expect(m.isSettled, isTrue);
    expect(m.value.valueAt(0.7), 1);
  });

  test('a plain curve turns from where its course has it when the next '
      'curve starts', () {
    final m = _Fade();
    m.value.animate(0, 1, animation: const TimingCurve.linear(duration: 1));
    m.value.animate(
      0.2,
      0,
      animation: const TimingCurve.linear(duration: 1),
      delay: 0.3,
    );
    expect(m.value.valueAt(0.4), moreOrLessEquals(0.4, epsilon: 1e-12));
    expect(m.value.valueAt(0.5), moreOrLessEquals(0.5, epsilon: 1e-12));
    expect(m.value.valueAt(1), moreOrLessEquals(0.25, epsilon: 1e-12));
    expect(m.value.target, 0);
  });

  test('additive curves sum on top of each other', () {
    final m = _Fade();
    m.value.animate(
      0,
      10,
      animation: const TimingCurve.linear(duration: 1, additive: true),
    );
    m.value.animate(
      0.5,
      20,
      animation: const TimingCurve.linear(duration: 1, additive: true),
    );
    expect(m.value.target, 20);
    expect(m.value.valueAt(0.5), moreOrLessEquals(5, epsilon: 1e-12));
    expect(m.value.valueAt(1), moreOrLessEquals(15, epsilon: 1e-12));
    expect(m.value.valueAt(1.5), 20);
  });

  test('a delayed curve rests until it is due, and the motion dozes until '
      'then', () {
    final m = _Fade();
    m.value.animate(
      0,
      1,
      animation: const TimingCurve.linear(duration: 0.2),
      delay: 0.5,
    );
    expect(m.value.restsAt(0.1), isTrue);
    expect(m.isSettled, isFalse);
    expect(m.wakeTime, 0.5);
    m.advance(1);
    m.settle();
    expect(m.value.valueAt(1), 1);
  });

  test('interrupting a curve with a spring inherits position and velocity', () {
    final value = MotionValue<double>(0);
    value.animate(0, 100, animation: const TimingCurve.linear(duration: 1));
    expect(value.valueAt(0.5), closeTo(50, 1e-9));
    expect(value.velocityAt(0.5), closeTo(100, 1e-2));

    value.retarget(0.5, 0, spring: const Spring.response(0.4));
    expect(value.valueAt(0.5), closeTo(50, 1e-9));
    // Positive inherited velocity carries it past 50 before turning toward 0.
    expect(value.valueAt(0.505), greaterThan(50));
    expect(value.valueAt(3), closeTo(0, 1e-3));
  });

  test('withAnimation drives MotionValue on TimingCurve and respects '
      'withoutAnimation and reduceMotion', () {
    final clock = ManualMotionClock();
    final v = MotionValue<double>(0, clock: clock);
    withAnimation(const TimingCurve.linear(duration: 1), () {
      v.target = 100;
    });
    clock.advanceTo(0.25);
    expect(v.value, closeTo(25, 1e-9));

    withoutAnimation(() {
      withAnimation(const TimingCurve.linear(duration: 1), () {
        v.target = 50;
      });
    });
    expect(v.value, 50);

    final reducedMotion = _Fade(clock: clock)
      ..traits = const MotionTraits(reduceMotion: true);
    withAnimation(
      const TimingCurve.linear(
        duration: 1,
        reduced: TimingCurve.linear(duration: 0.2),
      ),
      () => reducedMotion.value.target = 100,
    );
    expect(reducedMotion.value.valueAt(0.35), closeTo(50, 1e-9));
    expect(reducedMotion.value.valueAt(0.45), closeTo(100, 1e-9));
  });

  test(
    'Spring.mass, Spring.settling, Spring.keyboard and settlingDuration match '
    'UIKit numbers',
    () {
      expect(Spring.keyboard.mass, 3);
      expect(Spring.keyboard.stiffness, 1000);
      expect(Spring.keyboard.damping, 500);
      expect(Spring.keyboard.dampingRatio, closeTo(4.5643546, 1e-5));
      expect(Spring.keyboard.settlingDuration, closeTo(0.5058, 1e-3));

      expect(Spring.smooth.settlingDuration, closeTo(0.7349, 1e-3));
      expect(
        const Spring.response(0.3).settlingDuration,
        closeTo(0.4409, 1e-3),
      );
      expect(Spring.immediate.settlingDuration, 0);

      final legacyCritical = Spring.settling(duration: 0.5, dampingRatio: 1);
      expect(legacyCritical.stiffness, closeTo(341.0237, 1e-2));
      expect(legacyCritical.damping, closeTo(36.9337, 1e-2));
      expect(legacyCritical.settlingDuration, closeTo(0.5, 1e-6));

      const customMass = Spring.mass(mass: 2, stiffness: 300, damping: 20);
      expect(customMass.dampingRatio, closeTo(0.408248, 1e-4));
    },
  );

  test('TimingCurve.sineInOut matches half cosine', () {
    const sine = TimingCurve.sineInOut();
    expect(sine.progressAt(0), 0);
    expect(sine.progressAt(0.15), closeTo(0.5, 1e-12));
    expect(sine.progressAt(0.3), 1);
    expect(sine.progressAt(0.075), closeTo((1 - 0.70710678118) / 2, 1e-6));
  });

  test('a delayed plain curve lets an additive one run until it starts', () {
    final x = MotionValue<double>(0)
      ..animate(
        0,
        100,
        animation: const TimingCurve.linear(duration: 1, additive: true),
      )
      ..animate(
        0.2,
        0,
        animation: const TimingCurve.linear(duration: 1),
        delay: 0.5,
      );

    expect(x.valueAt(0.3), closeTo(30, 1e-9));
    expect(x.valueAt(0.7), closeTo(70, 1e-9));
    expect(x.valueAt(1.2), closeTo(35, 1e-9));
    expect(x.valueAt(1.7), closeTo(0, 1e-9));
  });

  test('a delayed additive curve lets a plain one run until it starts', () {
    final x = MotionValue<double>(0)
      ..animate(0, 100, animation: const TimingCurve.linear(duration: 1))
      ..animate(
        0.2,
        150,
        animation: const TimingCurve.linear(duration: 1, additive: true),
        delay: 0.5,
      );

    expect(x.valueAt(0.5), closeTo(50, 1e-9));
    expect(x.valueAt(0.7), closeTo(70, 1e-9));
    expect(x.valueAt(1), closeTo(115, 1e-9));
    expect(x.valueAt(1.7), closeTo(150, 1e-9));
  });

  test('a later delayed plain curve keeps the running one until its start', () {
    final x = MotionValue<double>(0)
      ..animate(0, 100, animation: const TimingCurve.linear(duration: 1))
      ..animate(
        0.2,
        200,
        animation: const TimingCurve.linear(duration: 1),
        delay: 0.3,
      )
      ..animate(
        0.3,
        0,
        animation: const TimingCurve.linear(duration: 1),
        delay: 0.5,
      );

    expect(x.valueAt(0.35), closeTo(35, 1e-9));
    expect(x.valueAt(0.5), closeTo(50, 1e-9));
    expect(x.valueAt(0.8), closeTo(50 + 150 * 0.3, 1e-9));
    expect(x.valueAt(1.8), closeTo(0, 1e-9));
  });

  test('a plain curve with an earlier start drops later pending ones', () {
    final x = MotionValue<double>(0)
      ..animate(
        0,
        100,
        animation: const TimingCurve.linear(duration: 1),
        delay: 1,
      )
      ..animate(
        0.1,
        -100,
        animation: const TimingCurve.linear(duration: 1),
        delay: 0.4,
      );

    expect(x.valueAt(0.3), 0);
    expect(x.valueAt(1), closeTo(-50, 1e-9));
    expect(x.valueAt(1.2), closeTo(-70, 1e-9));
    expect(x.restTime(), closeTo(1.5, 1e-9));
  });

  test('shift moves a running curve by the change once', () {
    final x = MotionValue<double>(0)
      ..animate(0, 100, animation: const TimingCurve.linear(duration: 1));
    expect(x.valueAt(0.5), closeTo(50, 1e-9));
    x.shift(0, 10);
    expect(x.valueAt(0.5), closeTo(60, 1e-9));
    expect(x.valueAt(1), closeTo(110, 1e-9));
  });

  test('reach counts a delayed curve that has not started', () {
    final x = MotionValue<double>(0)
      ..animate(
        0,
        100,
        animation: const TimingCurve.linear(duration: 1),
        delay: 0.5,
      );
    expect(x.restsAt(0.2), isTrue);
    expect(x.reach(0.2), greaterThanOrEqualTo(100));
    expect(x.reach(1), closeTo(50, 1e-9));
    expect(x.reach(1.5), 0);
  });
}
