import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';

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
  test('every matte draw holds as many shapes as its shaders', () {
    const most = geometryMaxShapesPerDraw;
    for (final path in [
      'gpu/sdf.glsl',
      'gpu/geometry_fragment.glsl',
      'gpu/material_gradient_fragment.glsl',
    ]) {
      expect(_define(path, 'MAX_SHAPES'), most, reason: path);
    }
    expect(
      _define('liquid_glass_final_render_core.glsl', 'MATTE_MAX_SHAPES'),
      most,
    );
    expect(FlutterGpuGeometryRenderer.maxShapesPerDraw, most);
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

  test('an analytic frame holds as many shapes as its shader', () {
    const most = AnalyticShapes.maxShapes;
    expect(_define('analytic_geometry.glsl', 'ANALYTIC_MAX_SHAPES'), most);
    // The header, then uShapeData, uRseData's two halves and uShapeBounds,
    // its boxes followed by a cull ratio a shape.
    expect(
      AnalyticShapes.of(ShapeSet.empty, contourExtent: 1).floats.length,
      4 + most * (12 + 12 + 12 + 4 + 1),
    );
  });
}
