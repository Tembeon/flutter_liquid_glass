@Tags(['macos_pixels', 'composer'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  testWidgets('frosted glass over its blurred copy draws what reading the '
      'backdrop draws', (tester) async {
    debugGlassPolicy = const PlanPolicy(shaderBlurs: false, maxCopyShare: 1);
    expect(await underlayParity(tester, frost: 8), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass over a blurred copy at half size draws near '
      'what reading the backdrop draws', (tester) async {
    debugGlassPolicy = const PlanPolicy(shaderBlurs: false);
    final difference = await underlayParity(tester, frost: 8);
    final copy = underlayGlass(tester).debugImageCopy!.image;
    // The whole 260 x 200 view, at half size.
    expect((copy.width, copy.height), (130, 100));
    expect(difference, lessThanOrEqualTo(4));
  }, skip: skipProperGlassTests);

  // NEAR: glass blurs a copy from levels, not by Impeller's blur. Over the
  // scene's white bars, the hardest edges a blur meets, it lies 0.3 to 0.9
  // channel levels from what reading the backdrop draws on average, 8 to 12
  // at the 99th percentile and up to 30 at the bars' corners. The levels
  // average the copy on cells of the screen, so a coarse copy blurs alike.
  for (final (frost, share, near) in [
    (3.0, 1, 20),
    (8.0, 2, 27),
    (12.0, 4, 30),
    (20.0, 4, 24),
  ]) {
    testWidgets('glass frosted by $frost over an unblurred copy draws near '
        'what reading the backdrop draws', (tester) async {
      copyIntoImages();
      final difference = await underlayParity(tester, frost: frost);
      final held = underlayGlass(tester).debugImageCopy!;
      expect(held.place.share, share);
      expect(held.place.levels, isNotNull);
      expect(difference, lessThanOrEqualTo(near));
    }, skip: skipProperGlassTests);
  }

  testWidgets('scaled glass frosted over an unblurred copy draws near what '
      'reading the backdrop draws', (tester) async {
    expect(
      await underlayParity(tester, frost: 8, scale: 1.2),
      lessThanOrEqualTo(32),
    );
  }, skip: skipProperGlassTests);
}
