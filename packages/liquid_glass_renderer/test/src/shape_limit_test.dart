import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

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
    expect(_define('gpu/geometry_uniforms.glsl', 'MAX_SHAPES'), most);
    expect(const PlanPolicy().maxShapes, most);
    expect(ShapeLooks.maxLooks, most);
  });

  test('the geometry shaders mark a texel far inside as the renderer does', () {
    final source = File(
      'lib/assets/shaders/gpu/matte_encoding.glsl',
    ).readAsStringSync();
    final match = RegExp(
      r'^const float kFarInward = (-?[\d.]+);$',
      multiLine: true,
    ).firstMatch(source);
    expect(double.parse(match!.group(1)!), kFarInward);
  });
}
