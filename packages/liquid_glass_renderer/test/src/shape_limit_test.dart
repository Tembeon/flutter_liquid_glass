import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/appearance.dart';

int _define(String path, String name) {
  final source = File('lib/assets/shaders/$path').readAsStringSync();
  final match = RegExp(
    '^#define $name (\\d+)\$',
    multiLine: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$name in $path');
  return int.parse(match!.group(1)!);
}

void main() {
  test('every geometry draw holds as many shapes as its shaders', () {
    const most = geometryMaxShapesPerDraw;
    for (final path in [
      'gpu/sdf.glsl',
      'gpu/tile_geometry_fragment.glsl',
      'gpu/material_gradient_fragment.glsl',
    ]) {
      expect(_define(path, 'MAX_SHAPES'), most, reason: path);
    }
    expect(
      _define('liquid_glass_final_render_core.glsl', 'MATTE_MAX_SHAPES'),
      most,
    );
    expect(LiquidGlassBlendGroup.maxShapesPerCluster, most);
    expect(const Policy().maxShapes, most);
    expect(
      appearanceLookupData(
        const [],
        const LiquidGlassAppearance.ios27RegularLight(),
      ).length,
      most * 2 * 4,
    );
  });
}
