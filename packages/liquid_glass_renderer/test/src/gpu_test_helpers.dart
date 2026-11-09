import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Creates a renderer and registers cleanup for the end of the test.
Future<FlutterGpuGeometryRenderer> createGeometryRenderer() async {
  final renderer = await FlutterGpuGeometryRenderer.fromAsset(
    ShaderKeys.gpuGeometryShaderBundle,
  );
  addTearDown(renderer.dispose);
  return renderer;
}

/// The reach the renderer tests draw atlases with.
const testReach = GlassReach(inward: 12, outward: 2);

/// A 20 x 30 rounded rectangle with corners of 4, centered at ([centerX],
/// 32).
ShapeSet testRectangle({double centerX = 16}) => ShapeSet.rows(
  shapes: [
    3, 20, 30, 4, // Rounded rectangle.
    1, 0, 0, 1, // Identity inverse affine basis.
    centerX, 32, 1, -1, // Center, scale, new group marker.
  ],
  boxes: [centerX - 10, 17, centerX + 10, 47],
);

/// Draws [testRectangle] into the atlas of a 64 x 64 geometry buffer and
/// returns the atlas.
ui.Image renderTestRectangle(
  FlutterGpuGeometryRenderer renderer, {
  double centerX = 16,
}) => renderer
    .renderAtlas(
      Tiling.shapes(
        testRectangle(centerX: centerX),
        width: 64,
        height: 64,
        reach: testReach,
      ),
    )
    .image;

/// A geometry atlas read back: four floats a texel, read through its table
/// as the final shader reads it.
final class AtlasTexels {
  AtlasTexels._(this.texels, this.width);

  /// Reads [image], an atlas.
  static Future<AtlasTexels> read(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    );
    return AtlasTexels._(
      Float32List.fromList(
        data!.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4),
      ),
      image.width,
    );
  }

  /// The texels, four floats each.
  final Float32List texels;

  /// The atlas's width in texels.
  final int width;

  /// The texel at atlas ([x], [y]). The engine reads a texel back as if w
  /// were alpha, dividing the rest by it; texels with w = 0 (the constants
  /// and those far outside) come back as NaN.
  (double, double, double, double) at(int x, int y) {
    final i = (y * width + x) * 4;
    final w = texels[i + 3];
    if (w <= 0) return (double.nan, 0, 0, 0);
    return (texels[i] * w, texels[i + 1] * w, texels[i + 2] * w, w);
  }

  /// The table entry of tile [column], [row].
  (int, int) entry(int column, int row) {
    final (tableX, tableY) = AtlasLayout.tableOrigin;
    final (x, y, _, w) = at(tableX + column, tableY + row);
    expect(w, 1, reason: 'table texel of $column, $row');
    return (x.round(), y.round());
  }

  /// Buffer pixel ([x], [y]) through the table. The constant tiles and the
  /// texels a strip skips come back as the constants they hold.
  (double, double, double, double) pixel(int x, int y) {
    final entry = this.entry(x ~/ Tiling.size, y ~/ Tiling.size);
    if (entry == AtlasLayout.deepEntry) return (kDeepInward, 0, 0, 0);
    if (entry == AtlasLayout.outsideEntry) return (kFarInward, 0, 0, 0);
    final texel = at(entry.$1 + x % Tiling.size, entry.$2 + y % Tiling.size);
    return texel.$1.isNaN ? (kFarInward, 0, 0, 0) : texel;
  }

  /// The distance to the edge at buffer pixel ([x], [y]), positive inside.
  double inwardAt(int x, int y) => pixel(x, y).$1;
}
