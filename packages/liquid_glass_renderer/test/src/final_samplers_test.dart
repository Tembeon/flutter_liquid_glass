import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';

void main() {
  test('the final shader declares its samplers in FinalSampler order, the '
      'looks in the atlas targets order', () {
    final core = File(
      '${shaderSources}liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final declared = [
      for (final match in RegExp(
        r'^uniform sampler2D (\w+);',
        multiLine: true,
      ).allMatches(core))
        match[1],
    ];
    expect(declared, [
      for (final sampler in FinalSampler.values) sampler.uniform,
    ]);
    expect(declared.skip(FinalSampler.lookTint.index), [
      for (final target in AtlasTarget.values.skip(1)) 'uLook${target.suffix}',
    ]);
  });
}
