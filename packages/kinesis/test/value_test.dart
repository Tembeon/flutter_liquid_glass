import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

void main() {
  const spring = Spring.response(0.4, dampingRatio: 0.375);
  const knob = Spring.response(0.3, dampingRatio: 0.99);

  group('MotionValue', () {
    test('moves exactly as the SDK spring simulation', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: spring);
      final reference = SpringSimulation(spring.description, 0, 10, 0);
      for (final t in [0.0, 0.01, 0.1, 0.25, 0.6, 2.0]) {
        expect(value.valueAt(t), reference.x(t));
        expect(value.velocityAt(t), reference.dx(t));
      }
    });

    test('a retarget continues from the current value and velocity', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: spring);
      final first = SpringSimulation(spring.description, 0, 10, 0);
      value.retarget(0.05, -4);
      final second = SpringSimulation(
        spring.description,
        first.x(0.05),
        -4,
        first.dx(0.05),
      );
      expect(value.valueAt(0.05), first.x(0.05));
      expect(value.velocityAt(0.05), first.dx(0.05));
      for (final t in [0.06, 0.1, 0.4]) {
        expect(value.valueAt(t), second.x(t - 0.05));
        expect(value.velocityAt(t), second.dx(t - 0.05));
      }
    });

    test('a change never reaches back before the previous one', () {
      final value = MotionValue<double>(0);
      value.retarget(0.1, 10, spring: spring);
      value.retarget(0.05, 20);
      final reference = MotionValue<double>(0);
      reference.retarget(0.1, 10, spring: spring);
      reference.retarget(0.1, 20);
      expect(value.valueAt(0.3), reference.valueAt(0.3));
    });

    test('snap puts the value at rest', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: spring);
      value.snap(0.1, 3);
      expect(value.valueAt(0.5), 3);
      expect(value.velocityAt(0.5), 0);
      expect(value.target, 3);
    });

    test('setVelocity keeps the position and the target', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: knob);
      final at = value.valueAt(0.05);
      value.setVelocity(0.05, 300);
      expect(value.valueAt(0.05), at);
      expect(value.velocityAt(0.05), 300);
      expect(value.target, 10);
    });

    test('setPresentation places the value and keeps the target', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: knob);
      value.setPresentation(0.1, 4, velocity: -2);
      expect(value.valueAt(0.1), 4);
      expect(value.velocityAt(0.1), -2);
      expect(value.target, 10);
    });

    test('a changed target pushes by stiffness x impulse x change', () {
      const settle = Spring.response(
        0.6,
        dampingRatio: 0.5,
        impulse: 0.016,
        tracking: Spring.response(0.15, dampingRatio: 0.5),
      );
      final value = MotionValue<double>(0, spring: settle);
      value.retarget(0, 2, spring: settle, tracking: true);
      expect(
        value.velocityAt(0),
        settle.trackingSpring.stiffness * 0.016 * 2,
      );
      final before = value.velocityAt(0.01);
      value.retarget(0.01, 1, spring: settle);
      expect(
        value.velocityAt(0.01) - before,
        moreOrLessEquals(-settle.stiffness * 0.016),
      );
    });

    test('a retarget that names no spring leaves the tracking spring', () {
      const tracking = Spring.response(0.15, dampingRatio: 0.86);
      const settle = Spring.response(0.4, tracking: tracking);
      final value = MotionValue<double>(0, spring: settle);
      value.retarget(0, 10, tracking: true);
      expect(value.spring, settle);
      value.retarget(0.05, 0);
      final reference = MotionValue<double>(0, spring: tracking);
      reference.retarget(0, 10);
      reference.retarget(0.05, 0, spring: settle);
      expect(value.valueAt(0.2), reference.valueAt(0.2));
    });

    test('vector components move exactly as scalars on one spring', () {
      final offset = MotionValue(Offset.zero);
      final x = MotionValue<double>(0);
      final y = MotionValue<double>(0);
      offset.retarget(0, const Offset(10, -30), spring: spring);
      x.retarget(0, 10, spring: spring);
      y.retarget(0, -30, spring: spring);
      offset.retarget(0.07, const Offset(-5, 4));
      x.retarget(0.07, -5);
      y.retarget(0.07, 4);
      for (final t in [0.03, 0.1, 0.33]) {
        expect(offset.valueAt(t), Offset(x.valueAt(t), y.valueAt(t)));
        expect(offset.velocityAt(t), Offset(x.velocityAt(t), y.velocityAt(t)));
      }
    });

    test('a delayed change keeps the course until it is due', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: spring);
      value.retarget(0.1, 0, delay: 0.04);
      expect(value.target, 0);
      final undelayed = MotionValue<double>(0);
      undelayed.retarget(0, 10, spring: spring);
      expect(value.valueAt(0.12), undelayed.valueAt(0.12));
      undelayed.retarget(0.14, 0);
      expect(value.valueAt(0.3), undelayed.valueAt(0.3));
      expect(value.isWithin(0.13), isFalse);
    });

    test('a delayed change comes due at its own time, even before any '
        'other change', () {
      final value = MotionValue<double>(0);
      value.retarget(-1, 10, spring: spring, delay: 0.5);
      final undelayed = MotionValue<double>(0);
      undelayed.retarget(-0.5, 10, spring: spring);
      expect(value.valueAt(0.1), undelayed.valueAt(0.1));
    });

    test('a change applies a delayed change that came due before it', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 10, spring: spring, delay: 0.1);
      value.retarget(0.3, 0, spring: spring);
      final undelayed = MotionValue<double>(0);
      undelayed.retarget(0.1, 10, spring: spring);
      undelayed.retarget(0.3, 0, spring: spring);
      expect(value.valueAt(0.4), undelayed.valueAt(0.4));
    });

    test('reach bounds the remaining swing and isWithin ends it', () {
      final value = MotionValue<double>(0);
      value.retarget(0, 100, spring: spring);
      final bound = value.reach(0.2);
      for (var t = 0.2; t < 3; t += 0.01) {
        expect((value.valueAt(t) - 100).abs(), lessThanOrEqualTo(bound + 1e-9));
      }
      expect(value.isWithin(0.2), isFalse);
      expect(value.isWithin(10), isTrue);
      value.settle(10);
      expect(value.valueAt(10), 100);
    });

    test('finds the first crossing of a level', () {
      final value = MotionValue<double>(1);
      value.retarget(0, 0, spring: spring);
      final t = value.crossing(0, from: 0)!;
      expect(value.valueAt(t), moreOrLessEquals(0, epsilon: 1e-6));
      expect(value.valueAt(t - 1e-3), greaterThan(0));
      expect(MotionValue<double>(1).crossing(0, from: 0), isNull);
    });

    test('listeners hear every frame of the motion and its rest', () {
      final clock = ManualMotionClock();
      final value = MotionValue<double>(0, clock: clock);
      final heard = <double>[];
      void listener() => heard.add(value.value);
      value.addListener(listener);
      value.retarget(0, 1, spring: knob);
      expect(heard, isEmpty);
      clock.advanceTo(0.1);
      expect(heard, [value.valueAt(0.1)]);
      clock.advanceTo(2);
      expect(heard.last, 1);
      final frames = heard.length;
      clock.advanceTo(3);
      expect(heard, hasLength(frames));
      value.removeListener(listener);
      value.snap(3, 2);
      clock.advanceTo(4);
      expect(heard, hasLength(frames));
    });

    test('a failing listener is reported and the others still hear', () {
      final clock = ManualMotionClock();
      final value = MotionValue<double>(0, clock: clock);
      final reported = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = original);
      var heard = 0;
      value.addListener(() => throw StateError('listener'));
      value.addListener(() => heard++);
      value.snap(0, 1);
      clock.advanceTo(0.01);
      expect(heard, 1);
      expect(reported.single.exception, isStateError);
      expect(reported.single.library, 'kinesis');
    });

    test('a jump is heard once, in the next frame', () {
      final clock = ManualMotionClock();
      final value = MotionValue<double>(0, clock: clock);
      var calls = 0;
      value.addListener(() => calls++);
      value.snap(0, 5);
      clock.advanceTo(0.01);
      clock.advanceTo(0.02);
      expect(calls, 1);
      expect(value.value, 5);
    });

    test('a follower may send a resting value somewhere new', () {
      final clock = ManualMotionClock();
      final value = MotionValue<double>(0, clock: clock);
      var sent = false;
      value.addListener(() {
        if (sent) return;
        sent = true;
        value.retarget(clock.now, 10, spring: knob);
      });
      value.snap(0, 1);
      clock.advanceTo(0.01);
      clock.advanceTo(0.1);
      expect(value.value, greaterThan(1));
    });

    test('colors move per channel and clamp to the gamut', () {
      final color = MotionValue(const Color(0xFF000000));
      color.retarget(0, const Color(0xFFFFFFFF), spring: spring);
      final mid = color.valueAt(0.2);
      expect(mid.r, greaterThan(0));
      expect(mid.r, lessThanOrEqualTo(1));
      expect(color.restDistance, 0.002);
    });

    test('projects the landing from the velocity', () {
      const sheet = Spring.response(0.3441, projection: 0.143);
      final value = MotionValue<double>(100, spring: sheet);
      value.setPresentation(0, 100, velocity: 1000);
      expect(value.projectAt(0), 100 + 1000 * 0.143);
      expect(
        value.projectAt(0, Spring.smooth),
        100 + 1000 * Spring.normalProjection,
      );
      final offset = MotionValue(Offset.zero);
      offset.setVelocity(0, const Offset(10, -20));
      expect(
        offset.projectAt(0),
        const Offset(10, -20) * Spring.normalProjection,
      );
    });

    test('a type without a converter is refused', () {
      expect(() => MotionValue<String>('a'), throwsArgumentError);
    });
  });
}
