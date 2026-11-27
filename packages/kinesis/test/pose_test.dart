import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  test('a lerp keeps a field equal at both ends exactly', () {
    const offset = Offset(0.1, 3.3);
    const a = MotionPose(offset: offset, offsetFraction: offset, opacity: 0);
    const b = MotionPose(offset: offset, offsetFraction: offset);
    final between = MotionPose.lerp(a, b, 0.3);
    expect(between.offset, offset);
    expect(between.offsetFraction, offset);
    expect(between.opacity, moreOrLessEquals(0.3));
  });

  test('two poses on one piece of content add up', () {
    const a = MotionPose(
      offset: Offset(4, 0),
      offsetFraction: Offset(0, 0.5),
      scale: 2,
      rotation: 0.1,
      opacity: 0.5,
      blur: 3,
    );
    const b = MotionPose(
      offset: Offset(1, 2),
      scale: 0.5,
      rotation: 0.2,
      opacity: 0.5,
      blur: 4,
    );
    final both = a.compose(b);
    expect(both.offset, const Offset(5, 2));
    expect(both.offsetFraction, const Offset(0, 0.5));
    expect(both.scale, 1);
    expect(both.rotation, closeTo(0.3, 1e-12));
    expect(both.opacity, 0.25);
    expect(both.blur, 5);
    expect(MotionPose.identity.compose(a), a);
  });

  test('a pose moves content by its offset and a fraction of its size', () {
    const pose = MotionPose(
      offset: Offset(1, 1),
      offsetFraction: Offset(0.5, -1),
    );
    expect(pose.offsetFor(const Size(40, 20)), const Offset(21, -19));
  });

  test('lerp runs from one pose to the other', () {
    const to = MotionPose(scale: 0, opacity: 0, blur: 8, rotation: math.pi);
    final half = MotionPose.lerp(MotionPose.identity, to, 0.5);
    expect(half.scale, 0.5);
    expect(half.opacity, 0.5);
    expect(half.blur, 4);
    expect(half.rotation, math.pi / 2);
  });
}
