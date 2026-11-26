@Tags(['composer'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets(
    'scaled frosted glass over its blurred copy draws what reading the '
    'backdrop draws',
    (tester) async {
      debugGlassPolicy = const PlanPolicy(shaderFrost: false, maxCopyShare: 1);
      expect(
        await underlayParity(tester, frost: 8, scale: 1.2),
        // NEAR: Impeller blurs a scaled canvas with other taps, 7 levels
        // apart on the face, 21 where the rim highlight brightens a corner.
        lessThanOrEqualTo(21),
      );
    },
    skip: skipProperGlassTests,
  );
}
