import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets(
    'scaled frosted glass over its blurred copy draws what reading the '
    'backdrop draws',
    (tester) async {
      RenderLiquidGlassLayer.debugMaxCopyShare = 1;
      RenderLiquidGlassLayer.debugShaderFrost = false;
      addTearDown(() {
        RenderLiquidGlassLayer.debugMaxCopyShare = 2;
        RenderLiquidGlassLayer.debugShaderFrost = true;
      });
      expect(
        await underlayParity(tester, frost: 8, scale: 1.2),
        // Impeller blurs a scaled canvas with other taps: NEAR.
        lessThanOrEqualTo(5),
      );
    },
    skip: skipProperGlassTests,
  );
}
