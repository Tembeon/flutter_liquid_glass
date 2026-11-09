import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';

const _rectangle = 3.0;
const _ellipse = 2.0;

/// A shape as a test places it: a box of [width] x [height] in its own units,
/// turned by [angle] and stretched by [stretchX], [stretchY] into buffer
/// pixels around [centerX], [centerY].
final class _Shape {
  const _Shape({
    required this.type,
    required this.width,
    required this.height,
    required this.radius,
    required this.centerX,
    required this.centerY,
    this.angle = 0,
    this.stretchX = 1,
    this.stretchY = 1,
    this.blend = 0,
    this.startsGroup = true,
  });

  final double type;
  final double width;
  final double height;
  final double radius;
  final double centerX;
  final double centerY;
  final double angle;
  final double stretchX;
  final double stretchY;
  final double blend;
  final bool startsGroup;

  (double, double, double, double) get basis => (
    stretchX * cos(angle),
    -stretchY * sin(angle),
    stretchX * sin(angle),
    stretchY * cos(angle),
  );

  (double, double, double, double) get inverse {
    final (a, b, c, d) = basis;
    final determinant = a * d - b * c;
    return (
      d / determinant,
      -b / determinant,
      -c / determinant,
      a / determinant,
    );
  }

  double get distanceScale => min(stretchX, stretchY);

  List<double> get row {
    final (i00, i01, i10, i11) = inverse;
    return [
      type,
      width,
      height,
      radius,
      i00,
      i01,
      i10,
      i11,
      centerX,
      centerY,
      distanceScale,
      if (startsGroup) -(blend + 1) else blend,
    ];
  }

  List<double> get box {
    final (a, b, c, d) = basis;
    final hw = width / 2;
    final hh = height / 2;
    double extent(double x, double y) => type == _ellipse
        ? sqrt(pow(x * hw, 2) + pow(y * hh, 2))
        : x.abs() * (hw - radius) +
              y.abs() * (hh - radius) +
              radius * sqrt(x * x + y * y);
    final ex = extent(a, b);
    final ey = extent(c, d);
    return [centerX - ex, centerY - ey, centerX + ex, centerY + ey];
  }

  /// The geometry pass's signed distance at buffer point ([x], [y]).
  double distanceAt(double x, double y) {
    final (i00, i01, i10, i11) = inverse;
    final dx = x - centerX;
    final dy = y - centerY;
    final lx = i00 * dx + i01 * dy;
    final ly = i10 * dx + i11 * dy;
    final local = type == _ellipse
        ? _ellipseDistance(lx, ly, width / 2, height / 2)
        : _roundedBoxDistance(lx, ly, width / 2, height / 2, radius);
    return local * distanceScale;
  }
}

double _roundedBoxDistance(double x, double y, double bx, double by, double r) {
  final qx = x.abs() - bx + r;
  final qy = y.abs() - by + r;
  return min(max(qx, qy), 0) +
      sqrt(pow(max(qx, 0), 2) + pow(max(qy, 0), 2)) -
      r;
}

double _ellipseDistance(double x, double y, double rx, double ry) {
  final ax = max(rx, 1e-4);
  final ay = max(ry, 1e-4);
  final px = x.abs();
  final py = y.abs();
  var angle = ax * (px - ax) < ay * (py - ay) ? pi / 2 : 0.0;
  for (var i = 0; i < 5; i++) {
    final c = cos(angle);
    final s = sin(angle);
    final ux = ax * c;
    final uy = ay * s;
    final vx = -ax * s;
    final vy = ay * c;
    angle +=
        ((px - ux) * vx + (py - uy) * vy) /
        max((px - ux) * ux + (py - uy) * uy + vx * vx + vy * vy, 1e-6);
  }
  final distance = sqrt(
    pow(px - ax * cos(angle), 2) + pow(py - ay * sin(angle), 2),
  );
  return pow(px / ax, 2) + pow(py / ay, 2) > 1 ? distance : -distance;
}

/// The scene's distance folded like sdf.glsl's sceneSample over [members]
/// (whole groups, chain order): each smooth union at its full radius, the
/// lowest any blend angle gives, or hard unions, the highest.
double _sceneDistance(
  List<_Shape> shapes,
  Iterable<int> members,
  double x,
  double y, {
  required bool smooth,
}) {
  var result = double.infinity;
  var group = double.infinity;
  var blend = 0.0;
  for (final i in members) {
    final shape = shapes[i];
    final d = shape.distanceAt(x, y);
    if (shape.startsGroup) {
      result = min(result, group);
      group = d;
      blend = shape.blend;
    } else if (!smooth || blend <= 0) {
      group = min(group, d);
    } else {
      final e = max(blend - (group - d).abs(), 0);
      group = min(group, d) - e * e * 0.25 / blend;
    }
  }
  return min(result, group);
}

ShapeSet _encode(List<_Shape> shapes) => ShapeSet.rows(
  shapes: [for (final shape in shapes) ...shape.row],
  boxes: [for (final shape in shapes) ...shape.box],
);

List<_Shape> _randomScene(
  Random random, {
  required int count,
  required double width,
  required double height,
  double largest = 240,
}) {
  final shapes = <_Shape>[];
  var blend = 0.0;
  var groupX = 0.0;
  var groupY = 0.0;
  for (var i = 0; i < count; i++) {
    final startsGroup = i == 0 || random.nextDouble() < 0.45;
    if (startsGroup) {
      blend = random.nextDouble() < 0.3 ? 0 : random.nextDouble() * 40;
      groupX = -40 + random.nextDouble() * (width + 80);
      groupY = -40 + random.nextDouble() * (height + 80);
    }
    final type = random.nextBool() ? _rectangle : _ellipse;
    final w = 4 + random.nextDouble() * largest;
    final h = 4 + random.nextDouble() * largest;
    final tilted = random.nextDouble() < 0.4;
    final stretched = random.nextDouble() < 0.4;
    shapes.add(
      _Shape(
        type: type,
        width: w,
        height: h,
        radius: type == _rectangle ? random.nextDouble() * min(w, h) / 2 : 0,
        centerX: groupX + (random.nextDouble() - 0.5) * largest,
        centerY: groupY + (random.nextDouble() - 0.5) * largest,
        angle: tilted ? random.nextDouble() * pi : 0,
        stretchX: stretched ? 0.5 + random.nextDouble() * 1.2 : 1,
        stretchY: stretched ? 0.5 + random.nextDouble() * 1.2 : 1,
        blend: blend,
        startsGroup: startsGroup,
      ),
    );
  }
  return shapes;
}

/// Pixel centers of tile [column], [row] inside a [width] x [height] buffer.
Iterable<(double, double)> _pixels(
  int column,
  int row,
  int width,
  int height,
) sync* {
  for (
    var y = row * Tiling.size;
    y < min(height, (row + 1) * Tiling.size);
    y++
  ) {
    for (
      var x = column * Tiling.size;
      x < min(width, (column + 1) * Tiling.size);
      x++
    ) {
      yield (x + 0.5, y + 0.5);
    }
  }
}

void _expectRunsPartitionRing(Tiling tiling) {
  final covered = Uint8List(tiling.columns * tiling.rows);
  for (final run in tiling.runs) {
    expect(run.length, inInclusiveRange(1, Tiling.maxRunTiles));
    for (var i = 0; i < run.length; i++) {
      final tile = run.row * tiling.columns + run.column + i;
      expect(tiling.kindAt(run.column + i, run.row), TileKind.ring);
      covered[tile]++;
    }
  }
  for (var row = 0; row < tiling.rows; row++) {
    for (var column = 0; column < tiling.columns; column++) {
      expect(
        covered[row * tiling.columns + column],
        tiling.kindAt(column, row) == TileKind.ring ? 1 : 0,
        reason: 'tile $column, $row',
      );
    }
  }
}

void main() {
  const width = 480;
  const height = 360;
  const reaches = [
    GlassReach(inward: 24, outward: 2),
    GlassReach(inward: 6, outward: 0.5),
    GlassReach(inward: 60, outward: 12),
  ];

  test('constant tiles hold only pixels past the reach', () {
    final random = Random(7);
    final seen = {for (final kind in TileKind.values) kind: 0};
    for (var scene = 0; scene < 12; scene++) {
      final shapes = _randomScene(
        random,
        count: 1 + random.nextInt(geometryMaxShapesPerDraw),
        width: width.toDouble(),
        height: height.toDouble(),
      );
      final all = List<int>.generate(shapes.length, (i) => i);
      for (final reach in reaches) {
        final tiling = Tiling.shapes(
          _encode(shapes),
          width: width,
          height: height,
          reach: reach,
        );
        expect(tiling.shapeSets, [all]);
        expect(tiling.droppedShapes, 0);
        _expectRunsPartitionRing(tiling);
        for (var row = 0; row < tiling.rows; row++) {
          for (var column = 0; column < tiling.columns; column++) {
            final kind = tiling.kindAt(column, row);
            seen[kind] = seen[kind]! + 1;
            if (kind == TileKind.ring) continue;
            for (final (x, y) in _pixels(column, row, width, height)) {
              if (kind == TileKind.outside) {
                final d = _sceneDistance(shapes, all, x, y, smooth: true);
                expect(
                  d,
                  greaterThanOrEqualTo(reach.outward),
                  reason: 'scene $scene, outside tile $column, $row at $x, $y',
                );
              } else {
                final d = _sceneDistance(shapes, all, x, y, smooth: false);
                expect(
                  d,
                  lessThanOrEqualTo(-reach.inward),
                  reason: 'scene $scene, deep tile $column, $row at $x, $y',
                );
              }
            }
          }
        }
      }
    }
    for (final kind in TileKind.values) {
      expect(seen[kind], greaterThan(100), reason: '$kind');
    }
  });

  test('a ring tile of a large scene evaluates every group that reaches it, '
      'in chain order', () {
    final random = Random(11);
    for (var scene = 0; scene < 4; scene++) {
      final shapes = _randomScene(
        random,
        count: 40,
        width: width.toDouble(),
        height: height.toDouble(),
        largest: 60,
      );
      final all = List<int>.generate(shapes.length, (i) => i);
      const reach = GlassReach(inward: 24, outward: 2);
      final tiling = Tiling.shapes(
        _encode(shapes),
        width: width,
        height: height,
        reach: reach,
      );
      expect(tiling.droppedShapes, 0);
      expect(tiling.shapeSets.length, greaterThan(1));
      _expectRunsPartitionRing(tiling);
      for (final run in tiling.runs) {
        final members = tiling.shapeSets[run.shapes];
        expect(members.length, lessThanOrEqualTo(geometryMaxShapesPerDraw));
        expect(members, orderedEquals([...members]..sort()));
        expect(shapes[members.first].startsGroup, isTrue);
        for (var i = 0; i < run.length; i++) {
          for (final (x, y) in _pixels(
            run.column + i,
            run.row,
            width,
            height,
          )) {
            final full = _sceneDistance(shapes, all, x, y, smooth: true);
            final set = _sceneDistance(shapes, members, x, y, smooth: true);
            if (full < reach.outward) {
              expect(set, full, reason: 'scene $scene at $x, $y');
            } else {
              expect(set, greaterThanOrEqualTo(reach.outward));
            }
          }
        }
      }
    }
  });

  test('a field tiles by the nodes over each tile', () {
    const step = 6.0;
    const pixelsPerUnit = 2.0;
    const cols = 70;
    const rows = 50;
    const originX = -12.0;
    const originY = -9.0;
    final samples = Float32List(cols * rows * 4);
    const shape = _Shape(
      type: _rectangle,
      width: 300,
      height: 200,
      radius: 40,
      centerX: 200,
      centerY: 150,
    );
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        samples[(j * cols + i) * 4] =
            shape.distanceAt(originX + i * step, originY + j * step) /
            pixelsPerUnit;
      }
    }
    final field = BufferField(
      LiquidGlassField(
        samples: samples,
        cols: cols,
        rows: rows,
        origin: const Offset(originX / pixelsPerUnit, originY / pixelsPerUnit),
        step: step / pixelsPerUnit,
      ),
      layerToBuffer: (pixelsPerUnit, 0, 0, pixelsPerUnit, 0, 0),
    );
    expect(field.distanceScale, closeTo(pixelsPerUnit, 1e-9));
    double fieldAt(double x, double y) {
      final gx = ((x - originX) / step).clamp(0, cols - 1);
      final gy = ((y - originY) / step).clamp(0, rows - 1);
      final cx = min(gx.floor(), cols - 2);
      final cy = min(gy.floor(), rows - 2);
      final fx = gx - cx;
      final fy = gy - cy;
      double node(int i, int j) => samples[(j * cols + i) * 4];
      final top = node(cx, cy) * (1 - fx) + node(cx + 1, cy) * fx;
      final bottom = node(cx, cy + 1) * (1 - fx) + node(cx + 1, cy + 1) * fx;
      return (top * (1 - fy) + bottom * fy) * pixelsPerUnit;
    }

    for (final reach in reaches) {
      final tiling = Tiling.field(
        field,
        width: width,
        height: height,
        reach: reach,
      );
      _expectRunsPartitionRing(tiling);
      final kinds = {for (final kind in TileKind.values) kind: 0};
      for (var row = 0; row < tiling.rows; row++) {
        for (var column = 0; column < tiling.columns; column++) {
          final kind = tiling.kindAt(column, row);
          kinds[kind] = kinds[kind]! + 1;
          if (kind == TileKind.ring) continue;
          for (final (x, y) in _pixels(column, row, width, height)) {
            final d = fieldAt(x, y);
            if (kind == TileKind.outside) {
              expect(d, greaterThanOrEqualTo(reach.outward));
            } else {
              expect(d, lessThanOrEqualTo(-reach.inward));
            }
          }
        }
      }
      for (final kind in TileKind.values) {
        expect(kinds[kind], greaterThan(0), reason: '$reach $kind');
      }
    }
  });

  test(
    'the atlas keeps the constant tiles, the table and the strips apart',
    () {
      final random = Random(3);
      for (var scene = 0; scene < 6; scene++) {
        final shapes = _randomScene(
          random,
          count: 12,
          width: 1200,
          height: 900,
          largest: 500,
        );
        final tiling = Tiling.shapes(
          _encode(shapes),
          width: 1200,
          height: 900,
          reach: const GlassReach(inward: 40, outward: 4),
        );
        final atlas = AtlasLayout.of(tiling);
        expect(atlas.width, lessThanOrEqualTo(AtlasLayout.maxSize));
        expect(atlas.height, lessThanOrEqualTo(AtlasLayout.maxSize));
        final (tableX, tableY) = atlas.tableOrigin;
        final rects = <(int, int, int, int)>[
          (0, 0, 18, 18),
          (18, 0, 18, 18),
          (tableX, tableY, tiling.columns, tiling.rows),
          for (var i = 0; i < tiling.runs.length; i++)
            (
              atlas.strips[i * 2],
              atlas.strips[i * 2 + 1],
              tiling.runs[i].length * Tiling.size + 2,
              Tiling.size + 2,
            ),
        ];
        for (final (x, y, w, h) in rects) {
          expect(x, greaterThanOrEqualTo(0));
          expect(y, greaterThanOrEqualTo(0));
          expect(x + w, lessThanOrEqualTo(atlas.width));
          expect(y + h, lessThanOrEqualTo(atlas.height));
        }
        for (var a = 0; a < rects.length; a++) {
          for (var b = a + 1; b < rects.length; b++) {
            final (ax, ay, aw, ah) = rects[a];
            final (bx, by, bw, bh) = rects[b];
            final apart =
                ax + aw <= bx ||
                bx + bw <= ax ||
                ay + ah <= by ||
                by + bh <= ay;
            expect(
              apart,
              isTrue,
              reason: 'scene $scene: ${rects[a]} ${rects[b]}',
            );
          }
        }
        for (var i = 0; i < tiling.runs.length; i++) {
          expect(atlas.entryOf(i, 2), (
            atlas.strips[i * 2] + 1 + 2 * Tiling.size,
            atlas.strips[i * 2 + 1] + 1,
          ));
        }
      }
    },
  );

  test('a wider reach covers a narrower one', () {
    const wide = GlassReach(inward: 30, outward: 4);
    expect(wide.covers(const GlassReach(inward: 20, outward: 4)), isTrue);
    expect(wide.covers(const GlassReach(inward: 31, outward: 1)), isFalse);
    expect(wide.covers(const GlassReach(inward: 10, outward: 5)), isFalse);
  });
}
