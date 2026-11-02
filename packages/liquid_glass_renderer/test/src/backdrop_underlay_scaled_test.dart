import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets('scaled frosted glass over its copy draws what reading the '
      'backdrop draws', (tester) async {
    RenderLiquidGlassLayer.debugMaxCopyDownscale = 1;
    addTearDown(() => RenderLiquidGlassLayer.debugMaxCopyDownscale = 2);
    expect(
      await underlayParity(tester, frost: 8, scale: 1.2),
      // Impeller blurs a scaled canvas with other taps: NEAR.
      lessThanOrEqualTo(5),
    );
  }, skip: skipProperGlassTests);
}
