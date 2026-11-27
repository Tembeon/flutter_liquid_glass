import 'package:apple_liquid_glass/src/motions/slider_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

// A slider 300 wide whose thumb a finger takes at its center and moves to
// [to], a share of the width away from where it started.
double _dragged(SliderMotion motion, double from, double to) {
  final x = motion.thumbCenter;
  motion.pointerDown(0, x);
  motion.pointerMove(0.016, x + 20);
  motion.pointerMove(0.032, x + 10 + (to - from) * motion.width);
  return motion.value;
}

void main() {
  SliderMotion slider({double value = 0.3}) => SliderMotion(
    width: 300,
    value: value,
    ticks: 5,
    clock: ManualMotionClock(frameRate: 60),
  );

  test('with snapsToTicks off the value tracks the finger and a tick '
      'takes it only within 0.05 of the track (read from UIKit)', () {
    final free = slider()..snapsToTicks = false;
    expect(_dragged(free, 0.25, 0.38), moreOrLessEquals(0.38, epsilon: 1e-9));
    final caught = slider()..snapsToTicks = false;
    expect(_dragged(caught, 0.25, 0.46), 0.5);
    final snapping = slider();
    expect(_dragged(snapping, 0.25, 0.38), 0.5);
  });

  test('enabled bounds stop a drag short of the track ends', () {
    final bounded = slider()
      ..snapsToTicks = false
      ..enabledMin = 0.2
      ..enabledMax = 0.6;
    expect(_dragged(bounded, 0.25, 0.9), moreOrLessEquals(0.6));
    final low = slider()
      ..snapsToTicks = false
      ..enabledMin = 0.15
      ..enabledMax = 0.6;
    expect(_dragged(low, 0.25, 0.05), moreOrLessEquals(0.15));
  });
}
