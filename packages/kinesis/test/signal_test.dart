import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

class _Bar extends Motion {
  _Bar({super.clock});

  late final pixels = own(MotionSignal<double>(0));
}

void main() {
  test('answers the latest write at or before a time', () {
    final bar = _Bar();
    bar.pixels.write(0.1, 10);
    bar.pixels.write(0.2, 30);
    expect(bar.pixels.valueAt(0.05), 0);
    expect(bar.pixels.valueAt(0.15), 10);
    expect(bar.pixels.valueAt(0.2), 30);
    expect(bar.pixels.value, 30);
  });

  test('a write stamped before the latest replaces what came after', () {
    final bar = _Bar();
    bar.pixels.write(0.2, 30);
    bar.pixels.write(0.1, 10);
    expect(bar.pixels.valueAt(0.3), 10);
  });

  test('a write recomputes the selections and never keeps the motion '
      'awake', () {
    final clock = ManualMotionClock();
    final bar = _Bar(clock: clock);
    final minimized = bar.select((m) => m.pixels.valueAt(m.now) > 50);
    final heard = <bool>[];
    minimized.addListener(() => heard.add(minimized.value));
    clock.advanceBy(1 / 60);
    clock.input(clock.now, () => bar.pixels.write(clock.now, 80));
    clock.advanceBy(1 / 60);
    expect(heard, [true]);
    expect(bar.isSettled, isTrue);
  });
}
