import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/warm_up.dart';

import 'shared.dart';

void main() {
  testWidgets('precache draws every glass pipeline once', (tester) async {
    debugWarmUpDraws = null;
    await tester.runAsync(precacheLiquidGlass);
    expect(debugWarmUpDraws, isNull, reason: 'warm-up is opt-in');
    await tester.runAsync(() => precacheLiquidGlass(warmUp: true));
    // Every program full glass loads, drawn as glass draws it.
    expect(debugWarmUpDraws?.programs, unorderedEquals(FullGlass.programs));
    // Every final shader alone and over each frost sigma, the band's frost,
    // the fake glass filters twice each; every final shader over a plain
    // copy, and one over copies drawn through each of their passes; two
    // shadows per glass shape.
    final finals = FinalShaderVariant.all.length;
    expect(debugWarmUpDraws?.filters, greaterThan(finals * 5));
    expect(debugWarmUpDraws?.copies, finals + 2);
    expect(debugWarmUpDraws?.shadows, 6);

    debugWarmUpDraws = null;
    await tester.runAsync(() => precacheLiquidGlass(warmUp: true));
    expect(debugWarmUpDraws, isNull, reason: 'the pipelines exist');
  }, skip: skipProperGlassTests);
}
