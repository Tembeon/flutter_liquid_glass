import 'package:flutter_test/flutter_test.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets('scaled frosted glass over its copy draws what reading the '
      'backdrop draws', (tester) async {
    expect(
      await underlayParity(tester, frost: 8, scale: 1.2),
      // Impeller blurs a scaled canvas with other taps: NEAR.
      lessThanOrEqualTo(5),
    );
  }, skip: skipProperGlassTests);
}
