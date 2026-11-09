import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';

import 'gpu_test_helpers.dart';

/// Every tile within reach, so every texel is evaluated.
const _everything = GlassReach(inward: 100000, outward: 100000);

/// An atlas read back: four floats a texel.
final class _Atlas {
  _Atlas(this.texels, this.width, this.layout);

  final Float32List texels;
  final int width;
  final AtlasLayout layout;

  /// The texel at atlas ([x], [y]). The engine reads a texel back as if w
  /// were alpha, dividing the rest by it; texels with w = 0 (the constants
  /// and far outside) come back as w = 0 only.
  (double, double, double, double) at(int x, int y) {
    final i = (y * width + x) * 4;
    final w = texels[i + 3];
    if (w <= 0) return (double.nan, 0, 0, 0);
    return (texels[i] * w, texels[i + 1] * w, texels[i + 2] * w, w);
  }

  /// The table entry of tile [column], [row].
  (int, int) entry(int column, int row) {
    final (tableX, tableY) = layout.tableOrigin;
    final (x, y, _, w) = at(tableX + column, tableY + row);
    expect(w, 1, reason: 'table texel of $column, $row');
    return (x.round(), y.round());
  }

  /// Buffer pixel ([x], [y]) through the table.
  (double, double, double, double) pixel(int x, int y) {
    final (ex, ey) = entry(x ~/ Tiling.size, y ~/ Tiling.size);
    return at(ex + x % Tiling.size, ey + y % Tiling.size);
  }
}

Future<_Atlas> _draw(FlutterGpuGeometryRenderer renderer, Tiling tiling) async {
  final result = renderer.renderAtlas(tiling);
  final data = await result.image.toByteData(
    format: ui.ImageByteFormat.rawExtendedRgba128,
  );
  return _Atlas(
    Float32List.fromList(
      data!.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4),
    ),
    result.textureWidth,
    result.layout,
  );
}

/// One shape of each kind the geometry pass draws, placed at random.
ShapeSet _scene(Random random, int count, int width, int height) {
  final shapes = <double>[];
  final superellipses = <double>[];
  final lower = <double>[];
  final boxes = <double>[];
  var blend = 0.0;
  var groupX = 0.0;
  var groupY = 0.0;
  for (var i = 0; i < count; i++) {
    final starts = i == 0 || random.nextDouble() < 0.5;
    if (starts) {
      blend = random.nextDouble() < 0.3 ? 0 : random.nextDouble() * 30;
      groupX = random.nextDouble() * width;
      groupY = random.nextDouble() * height;
    }
    final type = 1 + random.nextInt(4);
    final w = 8 + random.nextDouble() * 120;
    final h = 8 + random.nextDouble() * 120;
    final shorter = min(w, h) / 2;
    final top = random.nextDouble() * shorter;
    final bottom = random.nextDouble() * shorter * 0.5;
    final radius = type == 2 ? 0.0 : top;
    final angle = random.nextDouble() < 0.4 ? random.nextDouble() * pi : 0.0;
    final stretch = random.nextDouble() < 0.4;
    final sx = stretch ? 0.6 + random.nextDouble() : 1.0;
    final sy = stretch ? 0.6 + random.nextDouble() : 1.0;
    final a = sx * cos(angle);
    final b = -sy * sin(angle);
    final c = sx * sin(angle);
    final d = sy * cos(angle);
    final determinant = a * d - b * c;
    final cx = groupX + (random.nextDouble() - 0.5) * 80;
    final cy = groupY + (random.nextDouble() - 0.5) * 80;
    shapes.addAll([
      type.toDouble(),
      w,
      h,
      radius,
      d / determinant,
      -b / determinant,
      -c / determinant,
      a / determinant,
      cx,
      cy,
      min(sx, sy),
      if (starts) -(blend + 1) else blend,
    ]);
    final rse = type == 4
        ? roundedSuperellipsePairParameters(ui.Size(w, h), top, bottom)
        : roundedSuperellipseParameters(ui.Size(w, h), radius);
    for (var half = 0; half < rse.length; half += 12) {
      rse[half + 2] = 1 - cos(rse[half + 2]);
      rse[half + 3] = 1 - cos(rse[half + 3]);
    }
    superellipses.addAll(rse.take(12));
    lower.addAll(type == 4 ? rse.skip(12) : List.filled(12, 0));
    double extent(double x, double y) => type == 2
        ? sqrt(pow(x * w / 2, 2) + pow(y * h / 2, 2))
        : x.abs() * w / 2 + y.abs() * h / 2;
    final ex = extent(a, b);
    final ey = extent(c, d);
    boxes.addAll([cx - ex, cy - ey, cx + ex, cy + ey]);
  }
  return ShapeSet.rows(
    shapes: shapes,
    boxes: boxes,
    superellipses: superellipses,
    superellipsesLower: lower,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 256;
  const height = 192;

  test('the table points every tile at its constant or its strip', () async {
    final renderer = await createGeometryRenderer();
    final shapes = _scene(Random(5), 6, width, height);
    final tiling = Tiling.shapes(
      shapes,
      width: width,
      height: height,
      reach: const GlassReach(inward: 12, outward: 2),
    );
    expect(tiling.runs, isNotEmpty);
    final atlas = await _draw(renderer, tiling);
    final expected = <(int, int), (int, int)>{};
    for (var i = 0; i < tiling.runs.length; i++) {
      final run = tiling.runs[i];
      for (var t = 0; t < run.length; t++) {
        expected[(run.column + t, run.row)] = atlas.layout.entryOf(i, t);
      }
    }
    for (var row = 0; row < tiling.rows; row++) {
      for (var column = 0; column < tiling.columns; column++) {
        expect(
          atlas.entry(column, row),
          switch (tiling.kindAt(column, row)) {
            TileKind.outside => AtlasLayout.outsideEntry,
            TileKind.deep => AtlasLayout.deepEntry,
            TileKind.ring => expected[(column, row)],
          },
          reason: 'tile $column, $row',
        );
      }
    }
  });

  test('a rounded rectangle reads its distance through the table', () async {
    final renderer = await createGeometryRenderer();
    final shapes = ShapeSet.rows(
      shapes: const [3, 100, 60, 12, 1, 0, 0, 1, 128, 96, 1, -1],
      boxes: const [78, 66, 178, 126],
    );
    final atlas = await _draw(
      renderer,
      Tiling.shapes(
        shapes,
        width: width,
        height: height,
        reach: const GlassReach(inward: 16, outward: 3),
      ),
    );
    // R is the distance inside, the left edge at x = 78.
    expect(atlas.pixel(82, 96).$1, closeTo(4.5, 0.01));
    expect(atlas.pixel(76, 96).$1, closeTo(-1.5, 0.01));
    expect(atlas.pixel(128, 70).$1, closeTo(4.5, 0.01));
  });

  test('ring strips hold what a pass over every texel writes', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    final random = Random(9);
    for (var scene = 0; scene < 6; scene++) {
      final shapes = _scene(random, 2 + random.nextInt(10), width, height);
      for (final reach in const [
        GlassReach(inward: 16, outward: 2),
        GlassReach(inward: 4, outward: 0.5),
      ]) {
        final tiling = Tiling.shapes(
          shapes,
          width: width,
          height: height,
          reach: reach,
        );
        final sparse = await _draw(renderer, tiling);
        final every = await _draw(
          dense,
          Tiling.shapes(
            shapes,
            width: width,
            height: height,
            reach: _everything,
          ),
        );
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final kind = tiling.kindAt(x ~/ Tiling.size, y ~/ Tiling.size);
            final exact = every.pixel(x, y);
            final reason = 'scene $scene, $reach, pixel $x, $y: $exact';
            switch (kind) {
              case TileKind.ring:
                // A strip skips texels past the reach, which a pass over
                // every texel evaluates.
                final read = sparse.pixel(x, y);
                if (read.$4 > 0) {
                  expect(read, exact, reason: reason);
                } else if (exact.$4 > 0) {
                  expect(
                    exact.$1,
                    lessThanOrEqualTo(-reach.outward),
                    reason: reason,
                  );
                }
              case TileKind.outside:
                if (exact.$4 > 0) {
                  expect(
                    exact.$1,
                    lessThanOrEqualTo(-reach.outward),
                    reason: reason,
                  );
                }
              case TileKind.deep:
                expect(exact.$4, greaterThan(0), reason: reason);
                expect(
                  exact.$1,
                  greaterThanOrEqualTo(reach.inward),
                  reason: reason,
                );
            }
          }
        }
      }
    }
  });

  test('a field atlas holds what a pass over every texel writes', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    const cols = 40;
    const rows = 30;
    const step = 4.0;
    final samples = Float32List(cols * rows * 4);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final x = i * step - 80;
        final y = j * step - 60;
        final r = sqrt(x * x + y * y);
        final o = (j * cols + i) * 4;
        samples[o] = r - 40;
        samples[o + 1] = r > 0 ? x / r : 0;
        samples[o + 2] = r > 0 ? y / r : 0;
        samples[o + 3] = 40;
      }
    }
    final field = BufferField(
      LiquidGlassField(
        samples: samples,
        cols: cols,
        rows: rows,
        origin: const ui.Offset(-10, -5),
        step: step,
      ),
      layerToBuffer: (2, 0, 0, 2, 20, 10),
    );
    const reach = GlassReach(inward: 20, outward: 2);
    final tiling = Tiling.field(
      field,
      width: width,
      height: height,
      reach: reach,
    );
    expect(
      {for (var t = 0; t < tiling.kinds.length; t++) tiling.kinds[t]},
      {for (final kind in TileKind.values) kind.index},
    );
    final sparse = await _draw(renderer, tiling);
    final every = await _draw(
      dense,
      Tiling.field(field, width: width, height: height, reach: _everything),
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final exact = every.pixel(x, y);
        final reason = 'pixel $x, $y: $exact';
        switch (tiling.kindAt(x ~/ Tiling.size, y ~/ Tiling.size)) {
          case TileKind.ring:
            expect(sparse.pixel(x, y), exact, reason: reason);
          case TileKind.outside:
            expect(exact.$1, lessThanOrEqualTo(-reach.outward), reason: reason);
          case TileKind.deep:
            expect(
              exact.$1,
              greaterThanOrEqualTo(reach.inward),
              reason: reason,
            );
        }
      }
    }
    // The circle of radius 40 logical pixels sits at buffer (20, 10) +
    // 2 * ((-10, -5) + (80, 60)) = (160, 120), 80 pixels in radius; the
    // grid's bilinear cone rounds its tip.
    expect(every.pixel(160, 120).$1, closeTo(80, 2));
    expect(every.pixel(160 + 70, 120).$1, closeTo(10, 1));
  });
}
