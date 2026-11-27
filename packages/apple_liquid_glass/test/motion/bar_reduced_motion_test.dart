import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('under Reduce Motion a bar change runs on a 0.15 s critically damped '
      'spring, its items appearing at full size, unblurred and unswollen '
      '(read from UIKit)', () {
    for (final spec in [
      GlassBarTransitionSpec.standard,
      GlassBarTransitionSpec.navigation,
    ]) {
      final reduced = spec.reduced;
      expect(reduced.appearScale, 1);
      expect(reduced.appearBlur, 0);
      expect(reduced.pulseScaleFor(44), 1);
      expect(reduced.pulseScaleFor(400), 1);
      expect(reduced.frameDelay, spec.frameDelay);
      expect(reduced.segmentDelay, spec.segmentDelay);
      expect(reduced.oversizedInPlace, spec.oversizedInPlace);
    }
  });
}
