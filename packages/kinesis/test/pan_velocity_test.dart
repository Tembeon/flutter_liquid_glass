import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/input.dart';

void main() {
  const lift = 0.06;

  Offset at(int ms) => Offset(0.5 * ms * ms / 10, 3.0 * ms);

  testWidgets("a release in motion reads what Flutter's tracker reads", (
    tester,
  ) async {
    final pan = PanVelocityTracker();
    final flutter = VelocityTracker.withKind(PointerDeviceKind.touch);
    for (var ms = 0; ms < 60; ms += 7) {
      pan.addPosition(ms / 1000, at(ms));
      flutter.addPosition(Duration(milliseconds: ms), at(ms));
    }
    flutter.addPosition(const Duration(milliseconds: 60), at(60));
    final expected = flutter.getVelocity().pixelsPerSecond;
    final got = pan.velocityAtLift(lift, at(60));
    expect(got.dx, closeTo(expected.dx, 1e-6));
    expect(got.dy, closeTo(expected.dy, 1e-6));
  });

  test('a lift after a stop reads the speed of the moves before it', () {
    final pan = PanVelocityTracker();
    for (var ms = 0; ms <= 40; ms += 8) {
      pan.addPosition(ms / 1000, Offset(2.0 * ms, 0));
    }
    final still = pan.velocityAtLift(0.4, const Offset(80, 0));
    expect(still.dx, closeTo(2000, 1e-6));
    expect(pan.heldStillAt(0.4), isTrue);
    expect(pan.heldStillAt(0.072), isFalse);
  });

  test('fewer than three positions moving together read zero', () {
    final pan = PanVelocityTracker()
      ..addPosition(0, Offset.zero)
      ..addPosition(0.1, const Offset(50, 0));
    expect(pan.velocityAtLift(0.108, const Offset(54, 0)), Offset.zero);
  });
}
