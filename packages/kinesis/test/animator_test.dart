import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('runs forward to completion and invokes completions in order', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    );
    animator.addAnimation<double>(x, 200);
    final events = <String>[];
    animator.addCompletion((p) => events.add('a:$p'));
    animator.addCompletion((p) => events.add('b:$p'));

    expect(animator.state, MotionAnimatorState.inactive);
    expect(animator.isRunning, isFalse);

    animator.start();
    expect(animator.state, MotionAnimatorState.active);
    expect(animator.isRunning, isTrue);

    clock.advanceTo(0.5);
    expect(x.value, closeTo(100, 1e-6));
    expect(animator.fractionComplete, closeTo(0.5, 1e-6));

    clock.advanceTo(1);
    expect(x.value, 200);
    expect(animator.state, MotionAnimatorState.inactive);
    expect(animator.isRunning, isFalse);
    expect(animator.fractionComplete, 0);
    expect(events, ['a:AnimatorPosition.end', 'b:AnimatorPosition.end']);
    animator.dispose();
  });

  test('scrubs linearly by default and preserves curve/spring overshoot when '
      'scrubsLinearly is false', () {
    final clock = ManualMotionClock();
    final linearX = MotionValue<double>(0, clock: clock);
    final curvedX = MotionValue<double>(0, clock: clock);
    final springX = MotionValue<double>(0, clock: clock);

    final linearAnim = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 1),
      clock: clock,
    )..addAnimation<double>(linearX, 100);
    final curvedAnim = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 1),
      clock: clock,
      scrubsLinearly: false,
    )..addAnimation<double>(curvedX, 100);
    final springAnim = MotionAnimator(
      animation: Spring.damping(duration: 0.5, dampingRatio: 0.5),
      clock: clock,
      scrubsLinearly: false,
    )..addAnimation<double>(springX, 100);

    linearAnim.scrub(0.25);
    curvedAnim.scrub(0.25);
    springAnim.scrub(0.25);

    expect(linearX.value, closeTo(25, 1e-6));
    expect(
      curvedX.value,
      closeTo(TimingCurve.uikitEaseInOut.transform(0.25) * 100, 1e-4),
    );
    expect(curvedX.value, lessThan(20));
    expect(springX.value, greaterThan(100));

    linearAnim.dispose();
    curvedAnim.dispose();
    springAnim.dispose();
  });

  test('isReversed runs backward to start and resets state', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation<double>(x, 100);
    final positions = <AnimatorPosition>[];
    animator.addCompletion(positions.add);

    animator.start();
    clock.advanceTo(0.4);
    expect(x.value, closeTo(40, 1e-6));

    animator.isReversed = true;
    clock.advanceTo(0.6);
    expect(x.value, closeTo(20, 1e-6));

    clock.advanceTo(0.8);
    expect(x.value, 0);
    expect(animator.state, MotionAnimatorState.inactive);
    expect(animator.isReversed, isFalse);
    expect(positions, [AnimatorPosition.start]);
    animator.dispose();
  });

  test('continueWith resumes paused animator with a new animation and '
      'durationFactor', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation<double>(x, 100);
    final positions = <AnimatorPosition>[];
    animator.addCompletion(positions.add);

    animator.start();
    clock.advanceTo(0.3);
    animator.pause();
    expect(animator.isRunning, isFalse);
    expect(x.value, closeTo(30, 1e-6));

    animator.continueWith(
      animation: const TimingCurve.easeOut(duration: 1),
      durationFactor: 0.5,
    );
    expect(animator.isRunning, isTrue);
    clock.advanceTo(0.55);
    expect(x.value, greaterThan(65));
    clock.advanceTo(0.8);
    expect(x.value, 100);
    expect(positions, [AnimatorPosition.end]);
    animator.dispose();
  });

  test('stop and finish enforce UIKit state transitions', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation<double>(x, 200);
    final positions = <AnimatorPosition>[];
    animator.addCompletion(positions.add);

    animator.start();
    clock.advanceTo(0.3);
    expect(() => animator.finish(AnimatorPosition.end), throwsStateError);

    animator.stop(withoutFinishing: false);
    expect(animator.state, MotionAnimatorState.stopped);
    expect(animator.isRunning, isFalse);
    expect(x.value, closeTo(60, 1e-6));
    expect(positions, isEmpty);

    animator.finish(AnimatorPosition.current);
    expect(animator.state, MotionAnimatorState.inactive);
    expect(x.value, closeTo(60, 1e-6));
    expect(positions, [AnimatorPosition.current]);

    // stop(withoutFinishing: true) skips completions.
    positions.clear();
    animator.start();
    clock.advanceTo(0.8);
    animator.stop(withoutFinishing: true);
    expect(animator.state, MotionAnimatorState.inactive);
    expect(positions, isEmpty);
    animator.dispose();
  });

  test('pausesOnCompletion keeps animator active and scrubbable', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
      pausesOnCompletion: true,
    )..addAnimation<double>(x, 100);
    final positions = <AnimatorPosition>[];
    animator.addCompletion(positions.add);

    animator.start();
    clock.advanceTo(1);
    expect(animator.state, MotionAnimatorState.active);
    expect(animator.isRunning, isFalse);
    expect(animator.fractionComplete, 1.0);
    expect(positions, isEmpty);

    animator.fractionComplete = 0.5;
    expect(x.value, closeTo(50, 1e-6));
    animator.dispose();
  });

  test('non-interruptible animator throws on pause and stop', () {
    final clock = ManualMotionClock();
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
      isInterruptible: false,
    );
    animator.start();
    expect(animator.pause, throwsStateError);
    expect(() => animator.stop(withoutFinishing: true), throwsStateError);
    animator.dispose();
  });

  test('delayFactor delays individual tracks inside the run', () {
    final clock = ManualMotionClock();
    final a = MotionValue<double>(0, clock: clock);
    final b = MotionValue<double>(0, clock: clock);
    final animator =
        MotionAnimator(
            animation: const TimingCurve.linear(duration: 1),
            clock: clock,
          )
          ..addAnimation<double>(a, 100)
          ..addAnimation<double>(b, 100, delayFactor: 0.5);

    animator.start();
    clock.advanceTo(0.25);
    expect(a.value, closeTo(25, 1e-6));
    expect(b.value, 0);

    clock.advanceTo(0.75);
    expect(a.value, closeTo(75, 1e-6));
    expect(b.value, closeTo(50, 1e-6));
    animator.dispose();
  });

  test('pause keeps the eased value and resuming runs on from it', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 1),
      clock: clock,
    )..addAnimation(x, 100);

    animator.start();
    clock.advanceTo(0.25);
    final paused = x.value;
    expect(paused, lessThan(20));
    animator.pause();
    expect(x.value, closeTo(paused, 1e-9));

    animator.scrub(0.25);
    expect(x.value, closeTo(paused, 1e-9));
    animator.scrub(0.625);
    expect(x.value, closeTo(paused + (100 - paused) / 2, 1e-9));
    animator.scrub(0.25);

    animator.start();
    expect(x.value, closeTo(paused, 1e-9));
    clock.advanceTo(0.26);
    expect(x.value, closeTo(paused, 0.5));
    clock.advanceTo(1);
    expect(x.value, 100);
    animator.dispose();
  });

  test('isReversed before start keeps the value where it is', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(50, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation(x, 100);

    animator.isReversed = true;
    expect(x.value, 50);

    animator.start();
    expect(x.value, 100);
    clock.advanceTo(0.5);
    expect(x.value, closeTo(75, 1e-9));
    clock.advanceTo(1);
    expect(x.value, 50);
    animator.dispose();
  });

  test('a value added to a started animator moves on from where it is', () {
    final clock = ManualMotionClock();
    final a = MotionValue<double>(0, clock: clock);
    final b = MotionValue<double>(30, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation(a, 100);

    animator.start();
    clock.advanceTo(0.5);
    animator.pause();
    animator.addAnimation(b, 100);
    expect(b.value, 30);

    animator.scrub(0.5);
    expect(b.value, 30);
    animator.scrub(0.75);
    expect(a.value, closeTo(75, 1e-9));
    expect(b.value, closeTo(65, 1e-9));
    animator.scrub(1);
    expect(b.value, 100);
    animator.dispose();
  });

  test('an int target for a double value animates', () {
    final clock = ManualMotionClock();
    final opacity = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation(opacity, 1);

    animator.start();
    clock.advanceTo(0.5);
    expect(opacity.value, closeTo(0.5, 1e-9));
    clock.advanceTo(1);
    expect(opacity.value, 1.0);
    animator.dispose();
  });

  test('reversing after continueWith retraces from where the value is', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
    )..addAnimation(x, 100);

    animator.start();
    clock.advanceTo(0.2);
    animator.continueWith();
    clock.advanceTo(0.6);
    expect(x.value, closeTo(52, 1e-9));

    animator.isReversed = true;
    expect(x.value, closeTo(52, 1e-9));
    clock.advanceTo(0.7);
    expect(x.value, closeTo(44, 1e-9));
    animator.dispose();
  });

  test('a non-interruptible animator reverses from its fraction', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 1),
      clock: clock,
      isInterruptible: false,
    )..addAnimation(x, 100);

    animator.start();
    clock.advanceTo(0.6);
    animator.isReversed = true;
    expect(animator.fractionComplete, closeTo(0.6, 1e-9));
    clock.advanceTo(0.7);
    expect(x.value, closeTo(50, 1e-9));
    expect(animator.state, MotionAnimatorState.active);
    animator.dispose();
  });

  test('continueWith scales the duration of the animation it runs on', () {
    final clock = ManualMotionClock();
    final x = MotionValue<double>(0, clock: clock);
    final animator = MotionAnimator(
      animation: const TimingCurve.linear(duration: 2),
      clock: clock,
    )..addAnimation(x, 100);

    animator.start();
    clock.advanceTo(0.5);
    animator.continueWith(
      animation: const TimingCurve.linear(duration: 0.4),
    );
    clock.advanceTo(0.7);
    expect(x.value, closeTo(62.5, 1e-9));
    clock.advanceTo(0.9);
    expect(animator.state, MotionAnimatorState.inactive);
    expect(x.value, 100);

    const spring = Spring.response(0.3);
    double endOf(double factor) {
      final clock = ManualMotionClock();
      final x = MotionValue<double>(0, clock: clock);
      final animator = MotionAnimator(
        animation: const TimingCurve.linear(duration: 2),
        clock: clock,
      )..addAnimation(x, 100);
      animator
        ..start()
        ..pause()
        ..continueWith(animation: spring, durationFactor: factor);
      var t = 0.0;
      while (animator.state == MotionAnimatorState.active) {
        t += 1 / 120;
        clock.advanceTo(t);
      }
      animator.dispose();
      return t;
    }

    expect(endOf(1), closeTo(spring.settlingDuration, 0.01));
    expect(endOf(0.99), closeTo(spring.settlingDuration * 0.99, 0.01));
  });
}
