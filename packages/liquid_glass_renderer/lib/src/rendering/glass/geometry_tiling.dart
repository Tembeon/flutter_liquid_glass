import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';

/// How far from a silhouette the final shader needs exact geometry, in
/// buffer pixels: deeper than [inward] it reads only "deep", farther out
/// than [outward] only "outside".
@internal
@immutable
final class GlassReach {
  /// Creates the reach.
  const GlassReach({required this.inward, required this.outward});

  /// Depth past which the shading no longer depends on the distance or the
  /// normal.
  final double inward;

  /// Distance outside past which nothing is drawn.
  final double outward;

  /// Whether geometry tiled for this reach serves [other]: a narrower reach
  /// finds every constant tile still constant.
  bool covers(GlassReach other) =>
      inward >= other.inward && outward >= other.outward;

  GlassReach get _shallower =>
      GlassReach(inward: inward > 2 ? inward / 2 : 1, outward: outward);

  @override
  bool operator ==(Object other) =>
      other is GlassReach && other.inward == inward && other.outward == outward;

  @override
  int get hashCode => Object.hash(inward, outward);
}

/// What one 16 x 16 tile of a geometry buffer holds.
@internal
enum TileKind {
  /// Farther outside every shape than [GlassReach.outward] at every pixel.
  outside,

  /// Deeper than [GlassReach.inward] at every pixel.
  deep,

  /// Within reach of a silhouette somewhere: its pixels are evaluated.
  ring,
}

/// Consecutive ring tiles of one table row that evaluate the same shapes.
@internal
@immutable
final class TileRun {
  /// Creates the run.
  const TileRun(this.row, this.column, this.length, this.shapes);

  /// The table row.
  final int row;

  /// The first tile's column.
  final int column;

  /// How many tiles, at most [Tiling.maxRunTiles].
  final int length;

  /// Index into [Tiling.shapeSets].
  final int shapes;
}

/// What the shapes of a buffer whose glass differs in tint or material look
/// like. The atlas pass writes each texel's look beside its geometry, blended
/// where shapes fuse by the smooth union's weight over its full radius
/// (looks.glsl), so the final shader reads it at the geometry's texel.
@internal
@immutable
final class ShapeLooks {
  /// The looks of shapes given by [entries], eight floats a shape: a tint
  /// (r, g, b, a) and a response (saturation, transmission gamma, vibrancy,
  /// visibility plus twice the color model's code). With [tintOnly] the
  /// atlas carries the tint alone. Shapes that look the same share a look;
  /// past [maxLooks] looks the rest take the last.
  factory ShapeLooks(List<double> entries, {required bool tintOnly}) {
    final compared = tintOnly ? 4 : _floats;
    final count = entries.length ~/ _floats;
    final lookOf = Uint8List(count);
    final looks = <double>[];
    for (var shape = 0; shape < count; shape++) {
      final at = shape * _floats;
      var look = 0;
      final known = looks.length ~/ _floats;
      while (look < known) {
        var same = true;
        for (var i = 0; i < compared && same; i++) {
          same = looks[look * _floats + i] == entries[at + i];
        }
        if (same) break;
        look++;
      }
      if (look == known) {
        if (known < maxLooks) {
          looks.addAll(entries.getRange(at, at + _floats));
        } else {
          look = maxLooks - 1;
        }
      }
      lookOf[shape] = look;
    }
    return ShapeLooks._(
      tintOnly: tintOnly,
      lookOf: lookOf,
      looks: List.unmodifiable(looks),
    );
  }

  const ShapeLooks._({
    required this.tintOnly,
    required this.lookOf,
    required this.looks,
  });

  static const int _floats = 8;

  /// The most looks one atlas holds: an atlas pass reads them from one
  /// uniform array.
  static const int maxLooks = geometryMaxShapesPerDraw;

  /// Whether the atlas carries the tint alone.
  final bool tintOnly;

  /// Each shape's look.
  final Uint8List lookOf;

  /// Eight floats a look, as the entries came.
  final List<double> looks;

  /// How many looks there are.
  int get count => looks.length ~/ _floats;
}

/// A fused body (`LiquidGlassLayer.field`) placed in a geometry buffer.
@internal
@immutable
final class BufferField {
  /// Places [field], whose frame is in its layer's logical pixels, by
  /// [layerToBuffer]: `(xx, xy, yx, yy, tx, ty)` with
  /// `buffer.x = xx * x + xy * y + tx`.
  factory BufferField(
    LiquidGlassField field, {
    required (double, double, double, double, double, double) layerToBuffer,
  }) {
    final (xx, xy, yx, yy, tx, ty) = layerToBuffer;
    final determinant = xx * yy - xy * yx;
    final step = field.step;
    final ix = yy / determinant / step;
    final ixy = -xy / determinant / step;
    final iyx = -yx / determinant / step;
    final iy = xx / determinant / step;
    final ox = field.origin.dx / step;
    final oy = field.origin.dy / step;
    final trace = xx * xx + xy * xy + yx * yx + yy * yy;
    final spread = sqrt(max(0, trace * trace - 4 * determinant * determinant));
    return BufferField._(
      field,
      bufferToGrid: (
        ix,
        ixy,
        iyx,
        iy,
        -(ix * tx + ixy * ty) - ox,
        -(iyx * tx + iy * ty) - oy,
      ),
      distanceScale: sqrt(max(0, (trace - spread) / 2)),
    );
  }

  const BufferField._(
    this.field, {
    required this.bufferToGrid,
    required this.distanceScale,
  });

  /// The field.
  final LiquidGlassField field;

  /// Buffer pixels to grid coordinates (node (i, j) at (i, j)):
  /// `(xx, xy, yx, yy, dx, dy)` with `grid.x = xx * x + xy * y + dx`.
  final (double, double, double, double, double, double) bufferToGrid;

  /// Buffer pixels per logical pixel of the field's distances: the
  /// placement's least stretch, as a shape's distance scale.
  final double distanceScale;
}

/// Which tiles of one geometry buffer need exact texels and which read a
/// constant, and which shapes each ring tile evaluates.
///
/// The buffer has one texel per buffer pixel, cut into [size] x [size]
/// tiles. Only ring tiles are drawn; outside and deep tiles point at shared
/// constant tiles. The classification uses conservative bounds of the
/// shapes, never their exact outlines: a tile is constant only when every
/// pixel in it provably is.
@internal
@immutable
final class Tiling {
  const Tiling._({
    required this.reach,
    required this.shapes,
    required this.field,
    required this.columns,
    required this.rows,
    required this.kinds,
    required this.runs,
    required this.shapeSets,
    required this.droppedShapes,
    required this.looks,
    required this.deepLooks,
  });

  /// Classifies a buffer of [width] x [height] pixels holding [shapes],
  /// encoded in buffer pixels, which wear [looks] where they differ.
  ///
  /// A ring that outgrows one atlas is tiled again with half the inward
  /// reach until it fits. Past the reach a read takes the deep value, so a
  /// layer with that much edge (several screens of glass outline) loses the
  /// inner part of its refraction falloff.
  factory Tiling.shapes(
    ShapeSet shapes, {
    required int width,
    required int height,
    required GlassReach reach,
    ShapeLooks? looks,
  }) {
    final columns = _tilesOver(width);
    final rows = _tilesOver(height);
    final kinds = _shapeKinds(shapes, columns, rows, reach);
    final deepLooks = looks == null
        ? null
        : _lookKinds(shapes, looks, columns, rows, kinds);
    final (sets, tileSets, dropped) = _shapeSets(
      shapes,
      columns,
      rows,
      reach,
      kinds,
      looks: looks != null,
    );
    final tiling = Tiling._(
      reach: reach,
      shapes: shapes,
      field: null,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: _runs(columns, rows, kinds, tileSets),
      shapeSets: List.unmodifiable(sets),
      droppedShapes: dropped,
      looks: looks,
      deepLooks: deepLooks,
    );
    if (tiling._fits || reach.inward <= 1) return tiling;
    return Tiling.shapes(
      shapes,
      width: width,
      height: height,
      reach: reach._shallower,
      looks: looks,
    );
  }

  /// Classifies a buffer of [width] x [height] pixels holding the body of
  /// [field], fitted to one atlas as [Tiling.shapes] is. Where [looks]
  /// differ, the body takes its look from the [shapes] it grew from, at
  /// most [geometryMaxShapesPerDraw] of them.
  factory Tiling.field(
    BufferField field, {
    required int width,
    required int height,
    required GlassReach reach,
    ShapeSet shapes = ShapeSet.empty,
    ShapeLooks? looks,
  }) {
    assert(
      looks == null || shapes.count <= geometryMaxShapesPerDraw,
      'A field takes its looks from one draw of shapes.',
    );
    final columns = _tilesOver(width);
    final rows = _tilesOver(height);
    final kinds = _fieldKinds(field, columns, rows, reach);
    final deepLooks = looks == null
        ? null
        : _lookKinds(shapes, looks, columns, rows, kinds);
    final tiling = Tiling._(
      reach: reach,
      shapes: looks == null ? ShapeSet.empty : shapes,
      field: field,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: _runs(columns, rows, kinds, Int32List(columns * rows)),
      shapeSets: List.unmodifiable([
        if (looks == null)
          const <int>[]
        else
          List<int>.generate(shapes.count, (i) => i, growable: false),
      ]),
      droppedShapes: 0,
      looks: looks,
      deepLooks: deepLooks,
    );
    if (tiling._fits || reach.inward <= 1) return tiling;
    return Tiling.field(
      field,
      width: width,
      height: height,
      reach: reach._shallower,
      shapes: shapes,
      looks: looks,
    );
  }

  // The ring tiles as runs along each row, a run sharing one set of shapes.
  static List<TileRun> _runs(
    int columns,
    int rows,
    Uint8List kinds,
    Int32List tileSets,
  ) {
    final runs = <TileRun>[];
    for (var row = 0; row < rows; row++) {
      var column = 0;
      while (column < columns) {
        final tile = row * columns + column;
        if (kinds[tile] != TileKind.ring.index) {
          column++;
          continue;
        }
        final set = tileSets[tile];
        var end = column + 1;
        while (end < columns &&
            end - column < maxRunTiles &&
            kinds[row * columns + end] == TileKind.ring.index &&
            tileSets[row * columns + end] == set) {
          end++;
        }
        runs.add(TileRun(row, column, end - column, set));
        column = end;
      }
    }
    return List.unmodifiable(runs);
  }

  bool get _fits => AtlasLayout._pack(this).height <= AtlasLayout.maxSize;

  static int _tilesOver(int pixels) => max(1, (pixels + size - 1) ~/ size);

  /// How far from the silhouette texels are exact.
  final GlassReach reach;

  /// The shapes tiled, in buffer pixels; for a [field], the shapes its looks
  /// come from, else empty.
  final ShapeSet shapes;

  /// The fused body tiled, if any.
  final BufferField? field;

  /// Tile edge in buffer pixels.
  static const int size = 16;

  /// The longest run: short strips fill an atlas row with little left over.
  static const int maxRunTiles = 8;

  /// Tiles along x.
  final int columns;

  /// Tiles along y.
  final int rows;

  /// [TileKind.index] of every tile, row-major.
  final Uint8List kinds;

  /// The ring tiles, row by row.
  final List<TileRun> runs;

  /// The shapes each run evaluates, in chain order. A buffer of at most
  /// [geometryMaxShapesPerDraw] shapes has one set: all of them.
  final List<List<int>> shapeSets;

  /// Shapes left out of a set that had more than
  /// [geometryMaxShapesPerDraw] within reach of one tile.
  final int droppedShapes;

  /// The looks the atlas carries beside the geometry, where the shapes' looks
  /// differ.
  final ShapeLooks? looks;

  /// The look of every deep tile, row-major, with [looks].
  final Uint8List? deepLooks;

  /// The kind of the tile at [column], [row].
  TileKind kindAt(int column, int row) =>
      TileKind.values[kinds[row * columns + column]];

  /// The look of the deep tile at [column], [row].
  int deepLookAt(int column, int row) =>
      deepLooks?[row * columns + column] ?? 0;

  static Uint8List _shapeKinds(
    ShapeSet shapes,
    int columns,
    int rows,
    GlassReach reach,
  ) {
    final kinds = Uint8List(columns * rows);
    final count = shapes.count;
    if (count == 0) return kinds;
    final groups = _ShapeGroups.of(shapes);
    final deep = Uint8List(columns * rows);
    for (var i = 0; i < count; i++) {
      final bounds = _ShapeBounds.of(shapes, i);
      final reachOut = reach.outward + groups.smoothing(i);
      final (c0, r0, c1, r1) = bounds.tileSpan(reachOut, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          final x0 = (column * size).toDouble();
          final y0 = (row * size).toDouble();
          final x1 = x0 + size;
          final y1 = y0 + size;
          if (bounds.distanceLowerBound(x0, y0, x1, y1) < reachOut) {
            kinds[tile] = TileKind.ring.index;
          }
          if (deep[tile] == 0 &&
              bounds.depthLowerBound(x0, y0, x1, y1) >= reach.inward) {
            deep[tile] = 1;
          }
        }
      }
    }
    // A smooth or hard union is at least as deep as its deepest member.
    for (var tile = 0; tile < kinds.length; tile++) {
      if (deep[tile] != 0) kinds[tile] = TileKind.deep.index;
    }
    return kinds;
  }

  // A deep tile reads one look only where one look's shapes alone weigh in:
  // a shape's weight in a smooth union is gone once its distance exceeds the
  // deepest member's by the blend, and a group's own fold lowers it by at
  // most its smoothing, so a shape weighs in only within 1.25 times its
  // group's blends. Other deep tiles turn ring and are evaluated; so does a
  // deep tile of a field no shape reaches. Returns each deep tile's look.
  static Uint8List _lookKinds(
    ShapeSet shapes,
    ShapeLooks looks,
    int columns,
    int rows,
    Uint8List kinds,
  ) {
    const none = -1;
    const mixed = -2;
    final owners = Int8List(columns * rows)..fillRange(0, columns * rows, none);
    final groups = _ShapeGroups.of(shapes);
    for (var i = 0; i < shapes.count; i++) {
      final bounds = _ShapeBounds.of(shapes, i);
      final reach = groups.lookReach(i);
      final look = looks.lookOf[i];
      final (c0, r0, c1, r1) = bounds.tileSpan(reach, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          final owner = owners[tile];
          if (kinds[tile] != TileKind.deep.index ||
              owner == mixed ||
              owner == look) {
            continue;
          }
          final x0 = (column * size).toDouble();
          final y0 = (row * size).toDouble();
          if (bounds.distanceLowerBound(x0, y0, x0 + size, y0 + size) < reach) {
            owners[tile] = owner == none ? look : mixed;
          }
        }
      }
    }
    final deepLooks = Uint8List(columns * rows);
    for (var tile = 0; tile < kinds.length; tile++) {
      if (kinds[tile] != TileKind.deep.index) continue;
      final owner = owners[tile];
      if (owner < 0) {
        kinds[tile] = TileKind.ring.index;
      } else {
        deepLooks[tile] = owner;
      }
    }
    return deepLooks;
  }

  static Uint8List _fieldKinds(
    BufferField field,
    int columns,
    int rows,
    GlassReach reach,
  ) {
    final kinds = Uint8List(columns * rows);
    final (xx, xy, yx, yy, dx, dy) = field.bufferToGrid;
    final LiquidGlassField(:samples, :cols, rows: nodeRows) = field.field;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        var gx0 = double.infinity;
        var gy0 = double.infinity;
        var gx1 = double.negativeInfinity;
        var gy1 = double.negativeInfinity;
        for (final (cx, cy) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
          final x = ((column + cx) * size).toDouble();
          final y = ((row + cy) * size).toDouble();
          final gx = xx * x + xy * y + dx;
          final gy = yx * x + yy * y + dy;
          gx0 = min(gx0, gx);
          gy0 = min(gy0, gy);
          gx1 = max(gx1, gx);
          gy1 = max(gy1, gy);
        }
        // Bilinear values stay within their nodes, and the field pass
        // clamps to the grid, so the nodes over the tile bound it.
        final i0 = gx0.floor().clamp(0, cols - 1);
        final i1 = gx1.ceil().clamp(0, cols - 1);
        final j0 = gy0.floor().clamp(0, nodeRows - 1);
        final j1 = gy1.ceil().clamp(0, nodeRows - 1);
        var lowest = double.infinity;
        var highest = double.negativeInfinity;
        for (var j = j0; j <= j1; j++) {
          for (var i = i0; i <= i1; i++) {
            final d = samples[(j * cols + i) * 4];
            lowest = min(lowest, d);
            highest = max(highest, d);
          }
        }
        lowest *= field.distanceScale;
        highest *= field.distanceScale;
        kinds[row * columns + column] = lowest >= reach.outward
            ? TileKind.outside.index
            : highest <= -reach.inward
            ? TileKind.deep.index
            : TileKind.ring.index;
      }
    }
    return kinds;
  }

  static (List<List<int>>, Int32List, int) _shapeSets(
    ShapeSet shapes,
    int columns,
    int rows,
    GlassReach reach,
    Uint8List kinds, {
    required bool looks,
  }) {
    final count = shapes.count;
    final tileSets = Int32List(columns * rows);
    if (count <= geometryMaxShapesPerDraw) {
      return (
        [List<int>.generate(count, (i) => i, growable: false)],
        tileSets,
        0,
      );
    }
    // A group reaches a pixel only where its smoothed union can come within
    // the outward reach, or its look can weigh in, so a ring tile evaluates
    // every group that can; whole groups keep the chain's order exact.
    final groups = _ShapeGroups.of(shapes);
    final reached = List<Set<int>>.generate(
      columns * rows,
      (_) => <int>{},
      growable: false,
    );
    for (var i = 0; i < count; i++) {
      final bounds = _ShapeBounds.of(shapes, i);
      final group = groups.groupOf[i];
      final reachOut = max(
        reach.outward + groups.smoothing(i),
        looks ? groups.lookReach(i) : 0.0,
      );
      final (c0, r0, c1, r1) = bounds.tileSpan(reachOut, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          if (kinds[tile] != TileKind.ring.index) continue;
          final x0 = (column * size).toDouble();
          final y0 = (row * size).toDouble();
          if (bounds.distanceLowerBound(x0, y0, x0 + size, y0 + size) <
              reachOut) {
            reached[tile].add(group);
          }
        }
      }
    }
    final sets = <List<int>>[];
    final index = <String, int>{};
    var dropped = 0;
    for (var tile = 0; tile < tileSets.length; tile++) {
      if (kinds[tile] != TileKind.ring.index) continue;
      final members = [
        for (final group in reached[tile].toList()..sort())
          ...groups.members[group],
      ];
      if (members.length > geometryMaxShapesPerDraw) {
        dropped = max(dropped, members.length - geometryMaxShapesPerDraw);
        members.length = geometryMaxShapesPerDraw;
      }
      final key = members.join(',');
      tileSets[tile] = index.putIfAbsent(key, () {
        sets.add(List.unmodifiable(members));
        return sets.length - 1;
      });
    }
    return (sets, tileSets, dropped);
  }
}

/// The blend groups of a [ShapeSet]: shapes in chain order, a negative blend
/// marker starting each group.
final class _ShapeGroups {
  _ShapeGroups._(this.groupOf, this.members, this._smoothing);

  factory _ShapeGroups.of(ShapeSet shapes) {
    final groupOf = Int32List(shapes.count);
    final members = <List<int>>[];
    final blends = <double>[];
    for (var i = 0; i < shapes.count; i++) {
      final marker = shapes.shapes[i * 12 + 11];
      if (marker < 0 || members.isEmpty) {
        members.add(<int>[]);
        blends.add(0);
      } else {
        blends[blends.length - 1] += marker;
      }
      members.last.add(i);
      groupOf[i] = members.length - 1;
    }
    // A smooth fold lowers the union by at most a quarter of its radius.
    return _ShapeGroups._(
      groupOf,
      members,
      [for (final blend in blends) blend * 0.25],
    );
  }

  final Int32List groupOf;
  final List<List<int>> members;
  final List<double> _smoothing;

  /// How far below its nearest member a shape's group can reach.
  double smoothing(int shape) => _smoothing[groupOf[shape]];

  /// How far outside a shape its look can weigh in: 1.25 times its group's
  /// blends, and a pixel.
  double lookReach(int shape) => smoothing(shape) * 5 + 1;
}

/// Closed-form bounds of one encoded shape's distance over a buffer rect,
/// in the units the geometry pass writes (local distance times the
/// shape's distance scale).
final class _ShapeBounds {
  _ShapeBounds._({
    required this.type,
    required this.halfWidth,
    required this.halfHeight,
    required this.radius,
    required this.inverse,
    required this.centerX,
    required this.centerY,
    required this.scale,
  });

  factory _ShapeBounds.of(ShapeSet shapes, int i) {
    final row = shapes.shapes;
    final o = i * 12;
    final type = row[o];
    final halfWidth = row[o + 1] / 2;
    final halfHeight = row[o + 2] / 2;
    var radius = row[o + 3];
    if (type == RawShapeType.squirclePair.shaderIndex) {
      radius = max(radius, shapes.superellipsesLower[i * 12 + 8]);
    }
    return _ShapeBounds._(
      type: type,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      radius: radius,
      inverse: (row[o + 4], row[o + 5], row[o + 6], row[o + 7]),
      centerX: row[o + 8],
      centerY: row[o + 9],
      scale: row[o + 10],
    );
  }

  final double type;
  final double halfWidth;
  final double halfHeight;
  final double radius;
  final (double, double, double, double) inverse;
  final double centerX;
  final double centerY;
  final double scale;

  /// The tiles that can hold a pixel closer than [reach]: the shape's box
  /// grown by the reach in its own units, mapped into the buffer. The
  /// geometry pass measures distance in the shape's units times [scale], the
  /// basis's least stretch, so a box in buffer pixels grown by [reach] can
  /// miss pixels beside a stretched shape.
  (int, int, int, int) tileSpan(double reach, int columns, int rows) {
    final (a, b, c, d) = inverse;
    final determinant = a * d - b * c;
    final grownX = halfWidth + reach / scale;
    final grownY = halfHeight + reach / scale;
    final extentX = (d.abs() * grownX + b.abs() * grownY) / determinant.abs();
    final extentY = (c.abs() * grownX + a.abs() * grownY) / determinant.abs();
    int tile(double at, int tiles) =>
        (at / Tiling.size).floor().clamp(0, tiles - 1);
    return (
      tile(centerX - extentX, columns),
      tile(centerY - extentY, rows),
      tile(centerX + extentX, columns),
      tile(centerY + extentY, rows),
    );
  }

  (double, double) _local(double x, double y) {
    final (a, b, c, d) = inverse;
    final dx = x - centerX;
    final dy = y - centerY;
    return (a * dx + b * dy, c * dx + d * dy);
  }

  /// A lower bound of the distance (negative inside) over the rect: the
  /// distance from the shape's box to the box around the rect's preimage.
  double distanceLowerBound(double x0, double y0, double x1, double y1) {
    var lx0 = double.infinity;
    var ly0 = double.infinity;
    var lx1 = double.negativeInfinity;
    var ly1 = double.negativeInfinity;
    for (final (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]) {
      final (lx, ly) = _local(x, y);
      lx0 = min(lx0, lx);
      ly0 = min(ly0, ly);
      lx1 = max(lx1, lx);
      ly1 = max(ly1, ly);
    }
    // The shapes are convex and mirror-symmetric in both local axes, so
    // their distance grows with |x| and with |y| outside: the box's point
    // nearest the axes is its nearest point.
    final double qx = max(0, max(lx0, -lx1));
    final double qy = max(0, max(ly0, -ly1));
    final double gx = max(0, qx - halfWidth);
    final double gy = max(0, qy - halfHeight);
    final boxDistance = sqrt(gx * gx + gy * gy);
    if (type != RawShapeType.ellipse.shaderIndex ||
        halfWidth <= 0 ||
        halfHeight <= 0) {
      return boxDistance == 0 ? double.negativeInfinity : boxDistance * scale;
    }
    final a2 = halfWidth * halfWidth;
    final b2 = halfHeight * halfHeight;
    final nx = qx / a2;
    final ny = qy / b2;
    if (nx * qx + ny * qy <= 1) return double.negativeInfinity;
    // Any support line bounds the distance to a convex shape from below;
    // the one whose normal is the ellipse's at q's radial projection is
    // close to the nearest.
    final length = sqrt(nx * nx + ny * ny);
    final ux = nx / length;
    final uy = ny / length;
    final support = ux * qx + uy * qy - sqrt(a2 * ux * ux + b2 * uy * uy);
    return max(boxDistance, support) * scale;
  }

  /// A lower bound of the depth inside the shape over the rect, or 0.
  ///
  /// The depth in a convex polygon the shape contains bounds the shape's
  /// depth; it is a minimum of affine functions, so over the rect's preimage
  /// (a parallelogram) it is least at a corner. Rounded boxes hold the
  /// octagon cut at twice the radius from each corner, shrunk by a
  /// hundredth of the radius (shape_depth_bound_test). An ellipse holds its
  /// copy scaled by rho about the center (the copy through the point) grown
  /// by (1 - rho) times its minor semi-axis; rho is convex, so that bound
  /// too is least at a corner.
  double depthLowerBound(double x0, double y0, double x1, double y1) {
    var depth = double.infinity;
    for (final (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]) {
      depth = min(depth, _depthAt(x, y));
      if (depth <= 0) return 0;
    }
    return depth * scale;
  }

  double _depthAt(double x, double y) {
    final (lx, ly) = _local(x, y);
    final ax = lx.abs();
    final ay = ly.abs();
    if (type == RawShapeType.ellipse.shaderIndex) {
      if (halfWidth <= 0 || halfHeight <= 0) return 0;
      final rx = ax / halfWidth;
      final ry = ay / halfHeight;
      return (1 - sqrt(rx * rx + ry * ry)) * min(halfWidth, halfHeight);
    }
    final shorter = min(halfWidth, halfHeight);
    final pair = type == RawShapeType.squirclePair.shaderIndex;
    if ((pair ? 2 * radius : radius) > shorter) return 0;
    final insideX = halfWidth - ax;
    final insideY = halfHeight - ay;
    var depth = min(insideX, insideY);
    if (radius > 0) {
      final cutX = min(2 * radius, halfWidth);
      final cutY = min(2 * radius, halfHeight);
      depth = min(
        depth,
        (insideX * cutY + insideY * cutX - cutX * cutY) /
            sqrt(cutX * cutX + cutY * cutY),
      );
    }
    return depth - 0.01 * radius;
  }
}

/// Where one buffer's table, constant tiles and ring strips sit in its atlas
/// texture.
///
/// The 18 x 18 block at texel (0, 0) holds the outside value and the next
/// blocks the deep value, one block a look ([Tiling.looks]). The atlas is
/// cleared to the outside tile's table entry, so only deep and ring tiles
/// write theirs. The table follows, one texel per tile, then the strips,
/// each `16 n + 2` x 18 texels: a run of n tiles with a one-texel apron
/// evaluated like the rest, so a linear read between texels stays on exact
/// values.
@internal
@immutable
final class AtlasLayout {
  const AtlasLayout._({
    required this.width,
    required this.height,
    required this.strips,
  });

  /// Lays out [tiling]'s table and strips.
  factory AtlasLayout.of(Tiling tiling) {
    final packed = AtlasLayout._pack(tiling);
    assert(
      packed.height <= maxSize,
      'A geometry atlas outgrew $maxSize rows at an inward reach of 1.',
    );
    return AtlasLayout._(
      width: packed.width,
      height: (packed.height + _align - 1) ~/ _align * _align,
      strips: packed.strips,
    );
  }

  factory AtlasLayout._pack(Tiling tiling) {
    final widths = [
      for (final run in tiling.runs) run.length * Tiling.size + 2,
    ];
    final blocks = 1 + max<int>(1, tiling.looks?.count ?? 0);
    final area =
        widths.fold(0, (sum, w) => sum + w * _strip) + blocks * _strip * _strip;
    var width = max(
      max(blocks * _strip, tiling.columns),
      widths.fold(0, max),
    );
    width = max(width, sqrt(area).ceil());
    width = min(maxSize, (width + _align - 1) ~/ _align * _align);
    var x = 0;
    var y = tableOrigin.$2 + tiling.rows;
    final strips = Int32List(widths.length * 2);
    for (var i = 0; i < widths.length; i++) {
      if (x + widths[i] > width) {
        x = 0;
        y += _strip;
      }
      strips[i * 2] = x;
      strips[i * 2 + 1] = y;
      x += widths[i];
    }
    return AtlasLayout._(
      width: width,
      height: y + (widths.isEmpty ? 0 : _strip),
      strips: strips,
    );
  }

  static const int _strip = Tiling.size + 2;
  static const int _align = 64;

  /// The largest atlas side: table entries are atlas texel coordinates in a
  /// 16-bit float, exact up to 2048.
  static const int maxSize = 2048;

  /// The atlas size in texels.
  final int width;

  /// The atlas size in texels.
  final int height;

  /// Texel of table entry (0, 0), below the constant tiles.
  static const (int, int) tableOrigin = (0, _strip);

  /// Each run's strip corner (its apron's top-left texel), x then y.
  final Int32List strips;

  /// The table entry of the outside tile: the texel of its pixel (0, 0).
  static const (int, int) outsideEntry = (1, 1);

  /// The table entry of the deep tiles of [look].
  static (int, int) deepEntryOf(int look) => ((look + 1) * _strip + 1, 1);

  /// The table entry of tile [index] of [run]: the texel of that tile's
  /// pixel (0, 0) in the run's strip.
  (int, int) entryOf(int run, int index) =>
      (strips[run * 2] + 1 + index * Tiling.size, strips[run * 2 + 1] + 1);
}
