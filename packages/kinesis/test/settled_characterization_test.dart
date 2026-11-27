import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

final class _Parts extends Motion {
  late final spring = own(MotionValue<double>(0, spring: Spring.snappy));
  late final curve = own(MotionValue<double>(0));
  late final frames = own(
    KeyframeValue<double>(
      const MotionKeyframes(
        duration: 0.4,
        mode: KeyframeMode.discrete,
        stops: [KeyframeStop(0, 0), KeyframeStop(0.5, 1), KeyframeStop(1, 2)],
      ),
    ),
  );
  late final loop = own(_Settling(spring));
}

final class _Settling extends MotionLoop {
  _Settling(this.input) : super(rate: 60);

  final MotionValue<double> input;
  double value = 0;

  @override
  bool step(double t) {
    value += (input.valueAt(t) - value) * 0.5;
    return (input.valueAt(t) - value).abs() > 1e-3 || !input.restsAt(t);
  }
}

void main() {
  test('a motion is settled exactly when it rests now with nothing due, and '
      'then its rest time has come', () {
    final m = _Parts();
    m.spring.retarget(0, 10);
    m.loop.wake(0);
    m.curve.animate(
      0,
      1,
      animation: const TimingCurve.linear(duration: 0.1),
    );
    m.curve.animate(
      0,
      2,
      animation: const TimingCurve.linear(duration: 0.1),
      delay: 0.3,
    );
    m.frames.play(0, delay: 0.2);
    final seen = <bool>{};
    for (var t = 0.0; t <= 3; t += 1 / 120) {
      m.advance(t);
      final rest = m.restTime();
      final settled = m.isSettled;
      seen.add(settled);
      expect(settled, rest != null && rest <= m.now, reason: 'at $t');
      final due = m.dueAfter(m.now);
      expect(settled, m.restsAt(m.now) && due == null, reason: 'at $t');
    }
    expect(seen, {false, true});
  });
}
