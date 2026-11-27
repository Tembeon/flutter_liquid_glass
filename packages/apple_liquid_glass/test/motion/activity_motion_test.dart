import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('16 images a 0.8 s turn from the start, 20 a second', () {
    final spin = ActivityMotion(clock: ManualMotionClock(frameRate: 60));
    spin.start(2);
    spin.advance(2);
    expect(spin.image, 0);
    for (var i = 1; i <= 20; i++) {
      spin.advance(2 + i / 20 + 0.001);
      expect(spin.image, i % ActivityMotion.images);
    }
  });

  test('a restart turns on from the image a stop left', () {
    final spin = ActivityMotion(clock: ManualMotionClock(frameRate: 60));
    spin.start(0);
    spin.advance(0.501);
    expect(spin.image, 10);
    spin.stop();
    spin.advance(3);
    expect(spin.image, 10, reason: 'stopped, it keeps its image');
    spin.start(3);
    spin.advance(3.051);
    expect(spin.image, 11);
  });

  test('the head draws brightest, its four-spoke tail fades to the rest, '
      'and between two spokes each takes its share', () {
    double at(int spoke, int image) => ActivityMotion.brightness(spoke, image);
    expect(at(2, 4), ActivityMotion.head);
    expect(at(1, 4), greaterThan(at(0, 4)));
    expect(
      at(6, 4),
      moreOrLessEquals(ActivityMotion.head * ActivityMotion.tail),
    );
    expect(
      at(3, 4),
      moreOrLessEquals(ActivityMotion.head * ActivityMotion.tail),
    );
    expect(at(2, 5), lessThan(ActivityMotion.head));
    expect(at(2, 5), greaterThan(at(1, 5)));
  });
}
