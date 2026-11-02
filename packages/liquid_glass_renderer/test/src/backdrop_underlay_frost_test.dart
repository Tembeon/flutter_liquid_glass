import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  tearDown(() => RenderLiquidGlassLayer.debugMaxCopyDownscale = 2);

  testWidgets('frosted glass over its copy draws what reading the backdrop '
      'draws', (tester) async {
    RenderLiquidGlassLayer.debugMaxCopyDownscale = 1;
    expect(await underlayParity(tester, frost: 8), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass over a copy at half size draws near what '
      'reading the backdrop draws', (tester) async {
    final difference = await underlayParity(tester, frost: 8);
    final copy = underlayGlass(tester).debugUnderlay.debugImage!;
    // The whole 260 x 200 view, at half size.
    expect((copy.width, copy.height), (130, 100));
    // White text drawn at half size is bolder under the frost: NEAR.
    expect(difference, lessThanOrEqualTo(16));
  }, skip: skipProperGlassTests);
}
