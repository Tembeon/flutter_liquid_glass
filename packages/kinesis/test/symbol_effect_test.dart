import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  group('SymbolEffectMotion', () {
    test('queues same discrete effect and stacks distinct effects', () {
      final motion = SymbolEffectMotion();
      final completions = <String>[];

      motion.add(
        0,
        const BounceSymbolEffect(),
        onComplete: (ok) => completions.add('bounce1:$ok'),
      );
      motion.add(
        0.1,
        const BounceSymbolEffect(),
        onComplete: (ok) => completions.add('bounce2:$ok'),
      );
      motion.add(
        0.2,
        const ScaleSymbolEffect(),
        onComplete: (ok) => completions.add('scale:$ok'),
      );

      // Peak of first bounce at 0.26 s combines with growing scale.
      expect(motion.poseAt(0.26).scale, greaterThan(1.246));

      // Scale completes at 0.2 + 0.27 = 0.47 s.
      motion.advance(0.48);
      expect(completions, ['scale:true']);

      // First bounce finishes at 0.73 s; second starts right after.
      motion.advance(0.74);
      expect(completions, ['scale:true', 'bounce1:true']);

      // Second bounce finishes at 1.46 s.
      motion.advance(1.47);
      expect(completions, ['scale:true', 'bounce1:true', 'bounce2:true']);
      expect(motion.pose.scale, closeTo(1.246, 1e-3));
    });

    test('speed and repeatCount scale and repeat discrete effects', () {
      final motion = SymbolEffectMotion();
      var done = false;
      motion.add(
        0,
        const BounceSymbolEffect(),
        options: const SymbolEffectOptions(speed: 2, repeatCount: 2),
        onComplete: (ok) => done = ok,
      );
      // 2 cycles at speed 2 -> 0.73 s total.
      motion.advance(0.5);
      expect(done, isFalse);
      motion.advance(0.74);
      expect(done, isTrue);
    });

    test('removing a repeating indefinite effect fires removal(false) now '
        'and add(true) at cycle end', () {
      final motion = SymbolEffectMotion();
      final events = <String>[];
      motion.add(
        0,
        const PulseSymbolEffect(),
        onComplete: (ok) => events.add('add:$ok'),
      );

      motion.advance(1);
      expect(motion.pose.opacity, lessThan(0.5));

      motion.remove<PulseSymbolEffect>(
        1,
        onComplete: (ok) => events.add('remove:$ok'),
      );
      expect(events, ['remove:false']);

      // Still finishing the 2.09 s cycle.
      motion.advance(1.8);
      expect(events, ['remove:false']);

      motion.advance(2.10);
      expect(events, ['remove:false', 'add:true']);
      expect(motion.pose.opacity, 1);
    });

    test('removeAll animates indefinites back without aborting discrete '
        'effects', () {
      final motion = SymbolEffectMotion();
      var bounceDone = false;
      motion.add(
        0,
        const BounceSymbolEffect(),
        onComplete: (ok) => bounceDone = ok,
      );
      motion.add(0, const ScaleSymbolEffect());
      motion.advance(0.3);
      expect(motion.pose.scale, greaterThan(1.2));

      motion.removeAll(0.3);
      motion.advance(0.6);
      // Scale returned (0.3 + 0.28 = 0.58), bounce still running to 0.73.
      expect(bounceDone, isFalse);
      motion.advance(0.75);
      expect(bounceDone, isTrue);
      expect(motion.pose, SymbolEffectPose.identity);
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
        options: const SymbolEffectOptions(repeating: true),
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
      ..add(0, bounce, options: const SymbolEffectOptions(repeating: true))
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
}
