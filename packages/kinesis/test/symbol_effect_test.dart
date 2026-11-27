import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  group('SymbolEffectMotion', () {
    test('queues same discrete effect and stacks distinct effects', () {
      const bounce = BounceSymbolEffect();
      const scale = ScaleSymbolEffect();
      final cycle = bounce.cycleDuration;
      final motion = SymbolEffectMotion();
      final completions = <String>[];

      motion.add(
        0,
        bounce,
        onComplete: (ok) => completions.add('bounce1:$ok'),
      );
      motion.add(
        0.1,
        bounce,
        onComplete: (ok) => completions.add('bounce2:$ok'),
      );
      motion.add(
        0.2,
        scale,
        onComplete: (ok) => completions.add('scale:$ok'),
      );

      const t = 0.26;
      final bounceAlone = SymbolEffectMotion()..add(0, bounce);
      expect(
        motion.poseAt(t).scale,
        greaterThan(bounceAlone.poseAt(t).scale),
      );

      motion.advance(0.2 + scale.cycleDuration + 0.01);
      expect(completions, ['scale:true']);

      motion.advance(cycle + 0.01);
      expect(completions, ['scale:true', 'bounce1:true']);

      motion.advance(2 * cycle + 0.01);
      expect(completions, ['scale:true', 'bounce1:true', 'bounce2:true']);
      expect(motion.pose.scale, closeTo(scale.targetScale, 1e-3));
    });

    test('speed and repeat scale and repeat discrete effects', () {
      const bounce = BounceSymbolEffect();
      final total = 2 * bounce.cycleDuration / 2;
      final motion = SymbolEffectMotion();
      var done = false;
      motion.add(
        0,
        bounce,
        options: const SymbolEffectOptions(
          speed: 2,
          repeat: SymbolEffectRepeat.times(2),
        ),
        onComplete: (ok) => done = ok,
      );
      motion.advance(total - 0.01);
      expect(done, isFalse);
      motion.advance(total + 0.01);
      expect(done, isTrue);
    });

    test('a pulse dips to an opacity', () {
      expect(() => PulseSymbolEffect(minOpacity: -0.2), throwsAssertionError);
      expect(() => PulseSymbolEffect(minOpacity: 1.5), throwsAssertionError);
    });

    test('removing a repeating indefinite effect fires removal(false) now '
        'and add(true) at cycle end', () {
      const pulse = PulseSymbolEffect();
      final motion = SymbolEffectMotion();
      final events = <String>[];
      motion.add(
        0,
        pulse,
        onComplete: (ok) => events.add('add:$ok'),
      );

      motion.advance(1);
      expect(motion.pose.opacity, lessThan(0.5));

      motion.remove<PulseSymbolEffect>(
        1,
        onComplete: (ok) => events.add('remove:$ok'),
      );
      expect(events, ['remove:false']);

      motion.advance(pulse.cycleDuration - 0.01);
      expect(events, ['remove:false']);

      motion.advance(pulse.cycleDuration + 0.01);
      expect(events, ['remove:false', 'add:true']);
      expect(motion.pose.opacity, 1);
    });

    test('removeAll animates indefinites back without aborting discrete '
        'effects', () {
      const bounce = BounceSymbolEffect();
      final motion = SymbolEffectMotion();
      var bounceDone = false;
      motion.add(0, bounce, onComplete: (ok) => bounceDone = ok);
      motion.add(0, const ScaleSymbolEffect());
      motion.advance(0.3);
      expect(motion.pose.scale, greaterThan(1.2));

      motion.removeAll(0.3);
      motion.advance(bounce.cycleDuration - 0.01);
      expect(bounceDone, isFalse);
      motion.advance(motion.restTime()!);
      expect(bounceDone, isTrue);
      expect(motion.pose, MotionPose.identity);
    });
  });

  testWidgets('MotionSymbol animates without per-frame widget rebuilds', (
    tester,
  ) async {
    final clock = ManualMotionClock();
    final motion = SymbolEffectMotion(clock: clock);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MotionClockScope(
          clock: clock,
          child: Center(
            child: MotionSymbol(
              motion: motion,
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    clock.input(0, () {
      motion.add(0, const WiggleSymbolEffect());
      motion.add(0, const RotateSymbolEffect());
    });
    for (var i = 1; i <= 20; i++) {
      clock.advanceTo(i / 60);
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);

    final layer =
        tester.renderObject(find.byType(MotionTransition)).debugLayer!
            as MotionTransitionLayer;
    final moved = motion.poseAt(20 / 60).offsetFor(const Size(40, 40));
    expect(moved.dx, isNot(0));
    const center = Offset(20, 20);
    final drawn = MatrixUtils.transformPoint(layer.total, center);
    final shift = drawn - layer.offset - center;
    expect(shift.dx, closeTo(moved.dx, 1e-9));
    expect(shift.dy, closeTo(moved.dy, 1e-9));
  });

  test('removing a repeating discrete effect ends it at its cycle end', () {
    const bounce = BounceSymbolEffect();
    final cycle = bounce.cycleDuration;
    final finished = <bool>[];
    final removed = <bool>[];
    final motion = SymbolEffectMotion()
      ..add(
        0,
        bounce,
        options: const SymbolEffectOptions(repeat: SymbolEffectRepeat.forever),
        onComplete: finished.add,
      )
      ..add(0, bounce);
    expect(motion.restTime(), double.infinity);

    motion.remove<BounceSymbolEffect>(cycle * 1.5, onComplete: removed.add);
    expect(removed, [false]);
    expect(motion.restTime(), closeTo(cycle * 3, 1e-9));
    motion.advance(cycle * 2);
    expect(finished, [true]);
    motion.advance(cycle * 3);
    expect(motion.isSettled, isTrue);
  });

  test('removeAll ends a repeating discrete effect at its cycle end', () {
    const bounce = BounceSymbolEffect();
    final motion = SymbolEffectMotion()
      ..add(
        0,
        bounce,
        options: const SymbolEffectOptions(repeat: SymbolEffectRepeat.forever),
      )
      ..removeAll(bounce.cycleDuration / 2);
    expect(motion.restTime(), closeTo(bounce.cycleDuration, 1e-9));
  });

  test('an effect replaced or cut short fires what it still owes', () {
    final added = <bool>[];
    final firstRemoval = <bool>[];
    final secondRemoval = <bool>[];
    final motion = SymbolEffectMotion()
      ..add(0, const ScaleSymbolEffect(), onComplete: added.add)
      ..add(0.01, const ScaleSymbolEffect());
    expect(added, [false]);

    motion
      ..remove<ScaleSymbolEffect>(1, onComplete: firstRemoval.add)
      ..remove<ScaleSymbolEffect>(1.05, onComplete: secondRemoval.add);
    expect(firstRemoval, [false]);
    motion.advance(3);
    expect(secondRemoval, [true]);

    final unanimated = <bool>[];
    SymbolEffectMotion()
      ..add(0, const ScaleSymbolEffect())
      ..remove<ScaleSymbolEffect>(1, onComplete: unanimated.add)
      ..removeAll(1.01, animated: false);
    expect(unanimated, [true]);
  });

  test('a held effect added without animation holds at once', () {
    final added = <bool>[];
    final motion = SymbolEffectMotion()
      ..add(
        0,
        const ScaleSymbolEffect(),
        options: const SymbolEffectOptions(animated: false),
        onComplete: added.add,
      );
    expect(added, [true]);
    expect(motion.poseAt(0).scale, const ScaleSymbolEffect().targetScale);
    expect(motion.restsAt(0), isTrue);
  });

  test('a completion may add an effect of another type', () {
    late final SymbolEffectMotion motion;
    motion = SymbolEffectMotion()
      ..add(
        0,
        const BounceSymbolEffect(),
        onComplete: (_) => motion.add(motion.now, const WiggleSymbolEffect()),
      );
    motion.advance(0.8);
    expect(motion.restsAt(0.8), isFalse);
    expect(motion.poseAt(1).offsetFraction, isNot(Offset.zero));
  });

  test('a run of cycles started again in its completion plays on', () {
    late final SymbolEffectMotion motion;
    var again = true;
    motion = SymbolEffectMotion()
      ..add(
        0,
        const BreatheSymbolEffect(),
        options: const SymbolEffectOptions(repeat: SymbolEffectRepeat.times(1)),
        onComplete: (_) {
          if (!again) return;
          again = false;
          motion.add(motion.now, const BreatheSymbolEffect());
        },
      );
    motion.advance(3.1);
    expect(again, isFalse);
    expect(motion.restsAt(3.2), isFalse);
    expect(motion.poseAt(4).scale, greaterThan(1));
  });
}
