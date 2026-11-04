import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  tearDown(() {
    RenderLiquidGlassLayer.debugMaxCopyDownscale = 2;
    RenderLiquidGlassLayer.debugShaderFrost = true;
  });

  testWidgets('frosted glass over its blurred copy draws what reading the '
      'backdrop draws', (tester) async {
    RenderLiquidGlassLayer.debugShaderFrost = false;
    RenderLiquidGlassLayer.debugMaxCopyDownscale = 1;
    expect(await underlayParity(tester, frost: 8), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass over a blurred copy at half size draws near '
      'what reading the backdrop draws', (tester) async {
    RenderLiquidGlassLayer.debugShaderFrost = false;
    final difference = await underlayParity(tester, frost: 8);
    final copy = underlayGlass(tester).debugUnderlay.debugImage!;
    // The whole 260 x 200 view, at half size.
    expect((copy.width, copy.height), (130, 100));
    expect(difference, lessThanOrEqualTo(4));
  }, skip: skipProperGlassTests);

  // The scene's text is white bars under the glass, the hardest edges a
  // frost meets: the shader's 24 taps differ from Impeller's blur most
  // there, and the copy's size adds to it as it does for a blurred copy.
  for (final (frost, size, near) in [
    (3.0, (260, 200), 14),
    (8.0, (130, 100), 14),
    (12.0, (65, 50), 22),
  ]) {
    testWidgets('glass frosted by $frost over an unblurred copy draws near '
        'what reading the backdrop draws', (tester) async {
      copyIntoImages();
      final difference = await underlayParity(tester, frost: frost);
      final copy = underlayGlass(tester).debugUnderlay.debugImage!;
      expect((copy.width, copy.height), size);
      // NEAR, see RenderLiquidGlassLayer.debugShaderFrost.
      expect(difference, lessThanOrEqualTo(near));
    }, skip: skipProperGlassTests);
  }

  testWidgets('a frost wider than the shader draws keeps a blurred copy', (
    tester,
  ) async {
    final difference = await underlayParity(tester, frost: 20);
    final copy = underlayGlass(tester).debugUnderlay.debugImage!;
    expect((copy.width, copy.height), (130, 100));
    expect(difference, lessThanOrEqualTo(6));
  }, skip: skipProperGlassTests);

  testWidgets('scaled glass frosted over an unblurred copy draws near what '
      'reading the backdrop draws', (tester) async {
    expect(
      await underlayParity(tester, frost: 8, scale: 1.2),
      lessThanOrEqualTo(26),
    );
  }, skip: skipProperGlassTests);
}
