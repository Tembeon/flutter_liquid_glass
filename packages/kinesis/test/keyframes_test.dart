import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

class _Blinker extends Motion {
  _Blinker(MotionKeyframes<double> frames, {super.clock}) {
    opacity = own(KeyframeValue<double>(frames));
  }

  late final KeyframeValue<double> opacity;
}

void main() {
  test('linear keyframes interpolate between stops with optional segment '
      'curves', () {
    const kf = MotionKeyframes<double>(
      duration: 2,
      stops: [
        KeyframeStop(0, 0),
        KeyframeStop(0.5, 100, curve: Curves.easeIn),
        KeyframeStop(1, 200),
      ],
    );
    expect(kf.valueAt(0), 0);
    expect(kf.valueAt(0.5), closeTo(50, 1e-9));
    expect(kf.valueAt(1), closeTo(100, 1e-9));
    expect(
      kf.valueAt(1.5),
      closeTo(100 + 100 * Curves.easeIn.transform(0.5), 1e-9),
    );
    expect(kf.valueAt(2), 200);
    expect(kf.valueAt(3), 200);
  });

  test('discrete keyframes hold each stop until the next keyTime', () {
    const kf = MotionKeyframes<double>(
      duration: 1,
      mode: KeyframeMode.discrete,
      stops: [
        KeyframeStop(0, 1),
        KeyframeStop(0.5, 0.5),
        KeyframeStop(0.75, 0),
        KeyframeStop(1, 1),
      ],
    );
    expect(kf.valueAt(0), 1);
    expect(kf.valueAt(0.49), 1);
    expect(kf.valueAt(0.5), 0.5);
    expect(kf.valueAt(0.74), 0.5);
    expect(kf.valueAt(0.75), 0);
    expect(kf.valueAt(1), 1);
  });

  test('cubic keyframes pass smoothly through every stop', () {
    const kf = MotionKeyframes<double>(
      duration: 1,
      mode: KeyframeMode.cubic,
      stops: [
        KeyframeStop(0, 0),
        KeyframeStop(0.25, 10),
        KeyframeStop(0.75, 0),
        KeyframeStop(1, 10),
      ],
    );
    expect(kf.valueAt(0), closeTo(0, 1e-9));
    expect(kf.valueAt(0.25), closeTo(10, 1e-9));
    expect(kf.valueAt(0.75), closeTo(0, 1e-9));
    expect(kf.valueAt(1), closeTo(10, 1e-9));
    expect(kf.valueAt(0.5), closeTo(5, 1e-6));
  });

  test('repeatCount and autoreverses cycle accurately', () {
    const kf = MotionKeyframes<double>(
      duration: 1,
      repeatCount: 3,
      autoreverses: true,
      stops: [KeyframeStop(0, 0), KeyframeStop(1, 100)],
    );
    expect(kf.totalDuration, 3);
    expect(kf.valueAt(0.25), closeTo(25, 1e-9));
    expect(kf.valueAt(1.25), closeTo(75, 1e-9));
    expect(kf.valueAt(2.25), closeTo(25, 1e-9));
    expect(kf.valueAt(3), closeTo(100, 1e-9));
  });

  test('KeyframeValue drives listeners on a ManualMotionClock and supports '
      'pause, resume, reset, and finite settling', () {
    final clock = ManualMotionClock();
    const kf = MotionKeyframes<double>(
      duration: 1,
      repeatCount: double.infinity,
      stops: [KeyframeStop(0, 0), KeyframeStop(1, 10)],
    );
    final host = _Blinker(kf, clock: clock);
    final heard = <double>[];
    host.opacity.addListener(() => heard.add(host.opacity.value));

    clock.advanceTo(0.25);
    expect(host.opacity.value, closeTo(2.5, 1e-9));
    expect(heard, isNotEmpty);

    host.opacity.pause(0.25);
    clock.advanceTo(0.75);
    expect(host.opacity.value, closeTo(2.5, 1e-9));

    host.opacity.resume(0.75);
    clock.advanceTo(1);
    expect(host.opacity.value, closeTo(5, 1e-9));

    host.opacity.reset(1);
    expect(host.opacity.valueAt(1), closeTo(0, 1e-9));
    expect(host.opacity.valueAt(1.5), closeTo(5, 1e-9));

    // Finite sequence settles automatically.
    final finite = KeyframeValue<double>(
      const MotionKeyframes<double>(
        duration: 0.5,
        stops: [KeyframeStop(0, 0), KeyframeStop(1, 1)],
      ),
      clock: clock,
      startTime: 1,
    );
    finite.addListener(() {});
    clock.advanceTo(1.25);
    expect(finite.isPlaying, isTrue);
    clock.advanceTo(1.6);
    expect(finite.isPlaying, isFalse);
    expect(finite.value, 1);
  });
}
