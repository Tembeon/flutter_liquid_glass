import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/changes.dart';

const _spring = Spring.response(0.3, dampingRatio: 1);

void main() {
  test('a change runs from 0 to 1 and retires once it rests', () {
    final retired = <MotionValue<double>>[];
    final changes = MotionChanges(onRetire: retired.add);
    final change = changes.start(0, _spring);
    changes.advance(0.1);
    expect(changes.progress.single, inExclusiveRange(0, 1));
    expect(changes.runs(change), isTrue);
    changes.advance(5);
    expect(changes.isEmpty, isTrue);
    expect(changes.runs(change), isFalse);
    expect(retired, [change]);
    expect(changes.retired, 1);
  });

  test('a change during a change carries on, the oldest first', () {
    final changes = MotionChanges();
    changes.start(0, _spring);
    changes.start(0.1, _spring);
    changes.advance(0.15);
    final [older, newer] = changes.progress;
    expect(older, greaterThan(newer));
    expect(newer, greaterThan(0));
  });

  test('a change beyond the third ends the oldest at once', () {
    final retired = <MotionValue<double>>[];
    final changes = MotionChanges(onRetire: retired.add);
    final first = changes.start(0, _spring);
    changes
      ..start(0.01, _spring)
      ..start(0.02, _spring);
    expect(changes.progress, hasLength(MotionChanges.maxChanges));
    expect(retired, isEmpty);
    final fourth = changes.start(0.03, _spring);
    expect(retired, [first]);
    expect(first.valueAt(0.03), 1);
    expect(changes.progress, hasLength(MotionChanges.maxChanges));
    expect(changes.runs(fourth), isTrue);
  });

  test('end retires every change where it is', () {
    final retired = <MotionValue<double>>[];
    final changes = MotionChanges(onRetire: retired.add);
    final first = changes.start(0, _spring);
    final second = changes.start(0.05, _spring);
    changes.advance(0.1);
    final shown = first.valueAt(0.1);
    changes.end();
    expect(changes.isEmpty, isTrue);
    expect(retired, [first, second]);
    expect(first.valueAt(0.1), shown);
  });

  test('a change runs on the animation its traits resolve', () {
    final changes = MotionChanges()
      ..traits = const MotionTraits(reduceMotion: true);
    final change = changes.start(
      0,
      _spring.copyWith(reduced: Spring.immediate),
    );
    expect(change.valueAt(0), 1);
  });
  test('content arriving while it leaves wears both looks, and under Reduce '
      'Motion only their opacity', () {
    const arriving = MotionPose(
      offsetFraction: Offset(0, 0.5),
      scale: 0.8,
      opacity: 0.5,
    );
    const leaving = MotionPose(blur: 2, opacity: 0.4);
    expect(
      wornDuringChange(
        arriving: arriving,
        leaving: leaving,
        traits: const MotionTraits(),
      ),
      arriving.compose(leaving),
    );
    expect(
      wornDuringChange(
        arriving: arriving,
        leaving: leaving,
        traits: const MotionTraits(reduceMotion: true),
      ),
      MotionPose(opacity: arriving.compose(leaving).opacity),
    );
    expect(
      wornDuringChange(
        arriving: null,
        leaving: null,
        traits: const MotionTraits(reduceMotion: true),
      ),
      MotionPose.identity,
    );
  });
}
