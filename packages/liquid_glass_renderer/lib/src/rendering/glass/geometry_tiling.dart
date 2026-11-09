import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';

/// How far from a silhouette the final shader needs exact geometry, in
/// buffer pixels: deeper than [inward] it reads only "deep", farther out
/// than [outward] only "outside". Between them a texel spans [coarseTexel]
/// pixels a side wherever the geometry is smooth.
@internal
@immutable
final class GlassReach {
  /// Creates the reach.
  const GlassReach({
    required this.inward,
    required this.outward,
    this.coarseTexel = 1,
  });

  /// Depth past which the shading no longer depends on the distance or the
  /// normal.
  final double inward;

  /// Distance outside past which nothing is drawn.
  final double outward;

  /// The side in buffer pixels of a texel of a ring tile no ridge, seam or
  /// tight corner comes near, a power of two up to [Tiling.size]. The final
  /// shader reads such a tile linearly, which is exact on straight edges and
  /// elsewhere within a quarter pixel of distance and a tenth of the normal
  /// in the outer four pixels, a fifth deeper in, where a corner's inner
  /// contours tighten (NEAR, the low-res matte's density). Where the
  /// distance or the normal folds, the tile keeps one texel a pixel.
  final int coarseTexel;

  /// Whether geometry tiled for this reach serves [other]: a narrower reach
  /// finds every constant tile still constant, and finer texels serve
  /// coarser ones.
  bool covers(GlassReach other) =>
      inward >= other.inward &&
      outward >= other.outward &&
      coarseTexel <= other.coarseTexel;

  GlassReach get _shallower => GlassReach(
    inward: inward > 2 ? inward / 2 : 1,
    outward: outward,
    coarseTexel: coarseTexel,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassReach &&
      other.inward == inward &&
      other.outward == outward &&
      other.coarseTexel == coarseTexel;

  @override
  int get hashCode => Object.hash(inward, outward, coarseTexel);
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

/// Consecutive ring tiles of one table row that evaluate the same shapes at
/// the same density.
@internal
@immutable
final class TileRun {
  /// Creates the run.
  const TileRun(this.row, this.column, this.length, this.shapes, this.texel);

  /// The table row.
  final int row;

  /// The first tile's column.
  final int column;

  /// How many tiles, at most [Tiling.maxRunTiles].
  final int length;

  /// Index into [Tiling.shapeSets].
  final int shapes;

  /// The side of a texel in buffer pixels: 1, or [GlassReach.coarseTexel].
  final int texel;
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
  Tiling._({
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
    // A read blends texels up to a texel away; past two the field's
    // curvature is gentle enough for a linear read.
    final bounds = [
      for (var i = 0; i < shapes.count; i++)
        _ShapeBounds.of(shapes, i, foldMargin: 2.0 * reach.coarseTexel),
    ];
    final groups = _ShapeGroups.of(shapes);
    final (kinds, fine) = _shapeKinds(bounds, groups, columns, rows, reach);
    final deepLooks = looks == null
        ? null
        : _lookKinds(bounds, groups, looks, columns, rows, kinds, fine);
    final (sets, tileSets, dropped) = _shapeSets(
      bounds,
      groups,
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
      runs: _runs(columns, rows, kinds, tileSets, fine, reach.coarseTexel),
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
    // A field's body is bilinear between its nodes, so its folds sit
    // anywhere: every ring tile keeps one texel a pixel.
    final fine = Uint8List(columns * rows)..fillRange(0, columns * rows, 1);
    final deepLooks = looks == null
        ? null
        : _lookKinds(
            [for (var i = 0; i < shapes.count; i++) _ShapeBounds.of(shapes, i)],
            _ShapeGroups.of(shapes),
            looks,
            columns,
            rows,
            kinds,
            fine,
          );
    final tiling = Tiling._(
      reach: reach,
      shapes: looks == null ? ShapeSet.empty : shapes,
      field: field,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: _runs(columns, rows, kinds, Int32List(columns * rows), fine, 1),
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

  // The ring tiles as runs along each row, a run sharing one set of shapes
  // and one density.
  static List<TileRun> _runs(
    int columns,
    int rows,
    Uint8List kinds,
    Int32List tileSets,
    Uint8List fine,
    int coarseTexel,
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
        final density = coarseTexel == 1 ? 1 : fine[tile];
        var end = column + 1;
        while (end < columns &&
            end - column < maxRunTiles &&
            kinds[tile + end - column] == TileKind.ring.index &&
            tileSets[tile + end - column] == set &&
            (coarseTexel == 1 || fine[tile + end - column] == density)) {
          end++;
        }
        final texel = density != 0 ? 1 : coarseTexel;
        runs.add(TileRun(row, column, end - column, set, texel));
        column = end;
      }
    }
    return List.unmodifiable(runs);
  }

  bool get _fits => layout.height <= AtlasLayout.maxSize;

  /// Where the atlas holds this tiling's table and strips.
  late final AtlasLayout layout = AtlasLayout._of(this);

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

  // A shape's tiles are ring within the outward reach of it, and within its
  // group's smoothing past that only where another member comes near
  // enough for the smooth union to bite: within the reach, the smoothing
  // and the blend. A smooth or hard union is at least as deep as its
  // deepest member. A ring tile keeps one texel a pixel where two groups
  // meet, where two members of a group with a narrow blend meet, or where a
  // shape's distance or normal folds. A wide blend folds the union nowhere:
  // the blend narrows as the members' normals agree, so the turn of the
  // normal across a seam stays within a texel's worth.
  static (Uint8List, Uint8List) _shapeKinds(
    List<_ShapeBounds> bounds,
    _ShapeGroups groups,
    int columns,
    int rows,
    GlassReach reach,
  ) {
    final tiles = columns * rows;
    final kinds = Uint8List(tiles);
    final fine = Uint8List(tiles);
    if (bounds.isEmpty) return (kinds, fine);
    final deep = Uint8List(tiles);
    final seamGroup = Int32List(tiles)..fillRange(0, tiles, -1);
    final near = Uint8List(tiles);
    final nearest = Float64List(tiles);
    final coarse = reach.coarseTexel > 1;
    // A linear read blends texels up to a texel's diagonal away. Where that
    // footprint crosses a hard seam, both groups come within the reach plus
    // two diagonals of the pixel read.
    final seamReach = reach.outward + (coarse ? 3.0 * reach.coarseTexel : 0);
    for (var group = 0; group < groups.members.length; group++) {
      final smoothing = groups.smoothingOf(group);
      final blend = groups.blendOf(group);
      final union = max(reach.outward + smoothing + blend, seamReach);
      final sharpSeams = blend < 8.0 * reach.coarseTexel;
      var groupC0 = columns;
      var groupR0 = rows;
      var groupC1 = -1;
      var groupR1 = -1;
      for (final i in groups.members[group]) {
        final shape = bounds[i];
        final (c0, r0, c1, r1) = shape.tileSpan(union, columns, rows);
        groupC0 = min(groupC0, c0);
        groupR0 = min(groupR0, r0);
        groupC1 = max(groupC1, c1);
        groupR1 = max(groupR1, r1);
        for (var row = r0; row <= r1; row++) {
          for (var column = c0; column <= c1; column++) {
            final tile = row * columns + column;
            final distance = shape.distanceOverTile(column, row);
            if (distance >= union) continue;
            if (near[tile] == 0 || distance < nearest[tile]) {
              nearest[tile] = distance;
            }
            if (near[tile] < 2) near[tile]++;
            if (distance == double.negativeInfinity &&
                deep[tile] == 0 &&
                shape.depthOverTile(column, row) >= reach.inward) {
              deep[tile] = 1;
            }
            if (coarse && fine[tile] == 0 && shape.foldsOverTile(column, row)) {
              fine[tile] = 1;
            }
          }
        }
      }
      for (var row = groupR0; row <= groupR1; row++) {
        for (var column = groupC0; column <= groupC1; column++) {
          final tile = row * columns + column;
          final count = near[tile];
          if (count == 0) continue;
          near[tile] = 0;
          final distance = nearest[tile];
          if (distance < seamReach) {
            final other = seamGroup[tile];
            if (other < 0) {
              seamGroup[tile] = group;
            } else if (other != group) {
              fine[tile] = 1;
            }
          }
          if (distance >= reach.outward &&
              (count < 2 || distance >= reach.outward + smoothing)) {
            continue;
          }
          kinds[tile] = TileKind.ring.index;
          if (count > 1 && sharpSeams) fine[tile] = 1;
        }
      }
    }
    for (var tile = 0; tile < tiles; tile++) {
      if (deep[tile] != 0) kinds[tile] = TileKind.deep.index;
    }
    return (kinds, fine);
  }

  // A deep tile reads one look only where one look's shapes alone weigh in:
  // a shape's weight in a smooth union is gone once its distance exceeds the
  // deepest member's by the blend, and a group's own fold lowers it by at
  // most its smoothing, so a shape weighs in only within 1.25 times its
  // group's blends. Other deep tiles turn ring and are evaluated; so does a
  // deep tile of a field no shape reaches. Returns each deep tile's look.
  static Uint8List _lookKinds(
    List<_ShapeBounds> bounds,
    _ShapeGroups groups,
    ShapeLooks looks,
    int columns,
    int rows,
    Uint8List kinds,
    Uint8List fine,
  ) {
    const none = -1;
    const mixed = -2;
    final owners = Int8List(columns * rows)..fillRange(0, columns * rows, none);
    for (var i = 0; i < bounds.length; i++) {
      final shape = bounds[i];
      final reach = groups.lookReach(i);
      final look = looks.lookOf[i];
      final (c0, r0, c1, r1) = shape.tileSpan(reach, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          final owner = owners[tile];
          if (kinds[tile] != TileKind.deep.index ||
              owner == mixed ||
              owner == look) {
            continue;
          }
          if (shape.distanceOverTile(column, row) < reach) {
            owners[tile] = owner == none ? look : mixed;
          }
        }
      }
    }
    // Such a tile keeps one texel a pixel: looks of different groups meet at
    // a hard seam.
    final deepLooks = Uint8List(columns * rows);
    for (var tile = 0; tile < kinds.length; tile++) {
      if (kinds[tile] != TileKind.deep.index) continue;
      final owner = owners[tile];
      if (owner < 0) {
        kinds[tile] = TileKind.ring.index;
        fine[tile] = 1;
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
    List<_ShapeBounds> bounds,
    _ShapeGroups groups,
    int columns,
    int rows,
    GlassReach reach,
    Uint8List kinds, {
    required bool looks,
  }) {
    final count = bounds.length;
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
    // every group that can, over the tiles _shapeKinds visits; whole groups
    // keep the chain's order exact.
    final reached = List<Set<int>>.generate(
      columns * rows,
      (_) => <int>{},
      growable: false,
    );
    for (var i = 0; i < count; i++) {
      final shape = bounds[i];
      final group = groups.groupOf[i];
      final reachOut = max(
        reach.outward + groups.smoothing(i) + groups.blendOf(group),
        looks ? groups.lookReach(i) : 0.0,
      );
      final (c0, r0, c1, r1) = shape.tileSpan(reachOut, columns, rows);
      for (var row = r0; row <= r1; row++) {
        for (var column = c0; column <= c1; column++) {
          final tile = row * columns + column;
          if (kinds[tile] != TileKind.ring.index) continue;
          if (shape.distanceOverTile(column, row) < reachOut) {
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
  _ShapeGroups._(this.groupOf, this.members, this._blends, this._smoothing);

  factory _ShapeGroups.of(ShapeSet shapes) {
    final groupOf = Int32List(shapes.count);
    final members = <List<int>>[];
    final blends = <double>[];
    final sums = <double>[];
    for (var i = 0; i < shapes.count; i++) {
      final marker = shapes.shapes[i * 12 + 11];
      if (marker < 0 || members.isEmpty) {
        members.add(<int>[]);
        blends.add(0);
        sums.add(0);
      } else {
        blends.last = max(blends.last, marker);
        sums.last += marker;
      }
      members.last.add(i);
      groupOf[i] = members.length - 1;
    }
    // A smooth fold lowers the union by at most a quarter of its radius.
    return _ShapeGroups._(
      groupOf,
      members,
      blends,
      [for (final sum in sums) sum * 0.25],
    );
  }

  final Int32List groupOf;
  final List<List<int>> members;
  final List<double> _blends;
  final List<double> _smoothing;

  /// How far below its nearest member [group]'s union can reach.
  double smoothingOf(int group) => _smoothing[group];

  /// The largest smooth-union radius in [group]: a member changes the union
  /// only where its distance comes within this of the rest's.
  double blendOf(int group) => _blends[group];

  /// How far below its nearest member a shape's group can reach.
  double smoothing(int shape) => _smoothing[groupOf[shape]];

  /// How far outside a shape its look can weigh in: 1.25 times its group's
  /// blends, and a pixel.
  double lookReach(int shape) => smoothing(shape) * 5 + 1;
}

/// Closed-form bounds of one encoded shape's distance over the tiles of a
/// buffer, in the units the geometry pass writes (local distance times the
/// shape's distance scale). A tile's preimage is a parallelogram; the
/// bounds read the box around it, which is the same size for every tile.
final class _ShapeBounds {
  _ShapeBounds._({
    required this.type,
    required this.halfWidth,
    required this.halfHeight,
    required this.radius,
    required this.foldInset,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.foldMargin,
  });

  /// Shape [i] of [shapes]; [foldsOverTile] looks [foldMargin] buffer pixels
  /// around a tile.
  factory _ShapeBounds.of(ShapeSet shapes, int i, {double foldMargin = 0}) {
    final row = shapes.shapes;
    final o = i * 12;
    final type = row[o];
    final halfWidth = row[o + 1] / 2;
    final halfHeight = row[o + 2] / 2;
    var radius = row[o + 3];
    if (type == RawShapeType.squirclePair.shaderIndex) {
      radius = max(radius, shapes.superellipsesLower[i * 12 + 8]);
    }
    final corner = min(radius, min(halfWidth, halfHeight));
    var foldInset = corner;
    if (type == RawShapeType.squircle.shaderIndex) {
      // The corner's two octants are arcs of circles centered on the
      // diagonal that touch at the corner's 45-degree point, a gap in from
      // the box: they fold the distance deeper than the nearer center.
      final cap = min(
        shapes.superellipses[i * 12 + 10],
        shapes.superellipses[i * 12 + 11],
      );
      foldInset = cap > 0
          ? min(corner, (1 - sqrt1_2) * corner + cap * sqrt1_2)
          : double.negativeInfinity;
    }
    return _ShapeBounds._(
      type: type,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      radius: radius,
      foldInset: foldInset,
      a: row[o + 4],
      b: row[o + 5],
      c: row[o + 6],
      d: row[o + 7],
      centerX: row[o + 8],
      centerY: row[o + 9],
      scale: row[o + 10],
      foldMargin: foldMargin,
    );
  }

  final double type;
  final double halfWidth;
  final double halfHeight;
  final double radius;

  // Where a box shape's corner diagonal stops folding, in from the box's
  // corner along both axes: the center of the arc of a rounded rectangle
  // (the optical normal's wider arc lies deeper), the nearer center of a
  // continuous corner's arcs; a box with sharp corners folds out past it.
  final double foldInset;

  // The inverse basis: local = (a x + b y, c x + d y) from the center.
  final double a;
  final double b;
  final double c;
  final double d;
  final double centerX;
  final double centerY;
  final double scale;
  final double foldMargin;

  static const double _half = Tiling.size / 2;

  late final double _extentX = (a.abs() + b.abs()) * _half;
  late final double _extentY = (c.abs() + d.abs()) * _half;
  late final double _foldExtentX = (a.abs() + b.abs()) * (_half + foldMargin);
  late final double _foldExtentY = (c.abs() + d.abs()) * (_half + foldMargin);

  /// The tiles that can hold a pixel closer than [reach]: the shape's box
  /// grown by the reach in its own units, mapped into the buffer. The
  /// geometry pass measures distance in the shape's units times [scale], the
  /// basis's least stretch, so a box in buffer pixels grown by [reach] can
  /// miss pixels beside a stretched shape.
  (int, int, int, int) tileSpan(double reach, int columns, int rows) {
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

  double _localX(int column, int row) =>
      a * ((column + 0.5) * Tiling.size - centerX) +
      b * ((row + 0.5) * Tiling.size - centerY);

  double _localY(int column, int row) =>
      c * ((column + 0.5) * Tiling.size - centerX) +
      d * ((row + 0.5) * Tiling.size - centerY);

  /// A lower bound of the distance (negative inside) over tile [column],
  /// [row]: the distance from the shape's box to the box around the tile's
  /// preimage.
  double distanceOverTile(int column, int row) {
    // The shapes are convex and mirror-symmetric in both local axes, so
    // their distance grows with |x| and with |y| outside: the box's point
    // nearest the axes is its nearest point.
    final qx = _positive(_localX(column, row).abs() - _extentX);
    final qy = _positive(_localY(column, row).abs() - _extentY);
    final gx = _positive(qx - halfWidth);
    final gy = _positive(qy - halfHeight);
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

  /// A lower bound of the depth inside the shape over tile [column], [row],
  /// or 0.
  ///
  /// The depth in a convex polygon the shape contains bounds the shape's
  /// depth; it is a minimum of affine functions, so over the tile's preimage
  /// (a parallelogram) it is least at a corner. Rounded boxes hold the
  /// octagon cut at twice the radius from each corner, shrunk by a
  /// hundredth of the radius (shape_depth_bound_test). An ellipse holds its
  /// copy scaled by rho about the center (the copy through the point) grown
  /// by (1 - rho) times its minor semi-axis; rho is convex, so that bound
  /// too is least at a corner.
  double depthOverTile(int column, int row) {
    final x = _localX(column, row);
    final y = _localY(column, row);
    final ux = (a + b) * _half;
    final uy = (c + d) * _half;
    final vx = (a - b) * _half;
    final vy = (c - d) * _half;
    final depth = min(
      min(_depthAt(x + ux, y + uy), _depthAt(x - ux, y - uy)),
      min(_depthAt(x + vx, y + vy), _depthAt(x - vx, y - vy)),
    );
    return depth <= 0 ? 0 : depth * scale;
  }

  /// Whether the shape's distance or its normal can fold within
  /// [foldMargin] of tile [column], [row]: its medial axis (the center line
  /// and each corner's diagonal, where the nearest edge changes) or a
  /// corner's center of curvature can lie there. A pair's halves meet on a
  /// line of their own, so a pair folds anywhere.
  bool foldsOverTile(int column, int row) {
    if (type == RawShapeType.squirclePair.shaderIndex) return true;
    final x = _localX(column, row).abs();
    final y = _localY(column, row).abs();
    // The box folded into the first quadrant, which the medial axis of a
    // mirror-symmetric shape is in.
    var nearX = _positive(x - _foldExtentX);
    var nearY = _positive(y - _foldExtentY);
    var farX = x + _foldExtentX;
    var farY = y + _foldExtentY;
    var long = halfWidth;
    var short = halfHeight;
    if (short > long) {
      (long, short) = (short, long);
      (nearX, nearY) = (nearY, nearX);
      (farX, farY) = (farY, farX);
    }
    if (type == RawShapeType.ellipse.shaderIndex) {
      // The medial axis runs along the major axis to the center of
      // curvature of its vertex.
      return nearY <= 0 && nearX <= long - short * short / max(long, 1e-9);
    }
    final spine = long - short;
    if (nearY <= 0 && nearX <= spine) return true;
    // Each corner's diagonal, from the spine's end to [foldInset].
    final from = max(spine, max(nearX, nearY + spine));
    final to = min(long - foldInset, min(farX, farY + spine));
    return from <= to;
  }

  static double _positive(double value) => value > 0 ? value : 0.0;

  double _depthAt(double localX, double localY) {
    final ax = localX.abs();
    final ay = localY.abs();
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
/// write theirs. The table follows, one texel per tile, then the strips: a
/// run of n tiles of texels t pixels a side ([TileRun.texel]) is
/// `16 n / t + 2` x `16 / t + 2` texels, with a one-texel apron evaluated
/// like the rest, so a linear read between texels stays on exact values.
@internal
@immutable
final class AtlasLayout {
  const AtlasLayout._({
    required this.width,
    required this.height,
    required this.strips,
    required this._runs,
  });

  // Shelves of strips: the full-density strips first, then the coarse ones,
  // each density on shelves of its own height. A layout taller than
  // [maxSize] does not fit; Tiling tiles such a ring again.
  factory AtlasLayout._of(Tiling tiling) {
    final runs = tiling.runs;
    final blocks = 1 + max<int>(1, tiling.looks?.count ?? 0);
    var area = blocks * _strip * _strip;
    var widest = 0;
    for (final run in runs) {
      final width = _stripWidth(run);
      area += width * (Tiling.size ~/ run.texel + 2);
      widest = max(widest, width);
    }
    var width = max(max(blocks * _strip, tiling.columns), widest);
    width = max(width, sqrt(area).ceil());
    width = min(maxSize, (width + _align - 1) ~/ _align * _align);
    final strips = Int32List(runs.length * 2);
    var x = 0;
    var y = tableOrigin.$2 + tiling.rows;
    var shelf = 0;
    for (final fine in [true, false]) {
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if ((run.texel == 1) != fine) continue;
        final stripWidth = _stripWidth(run);
        final stripHeight = Tiling.size ~/ run.texel + 2;
        if (x + stripWidth > width || stripHeight != shelf) {
          y += shelf;
          x = 0;
          shelf = stripHeight;
        }
        strips[i * 2] = x;
        strips[i * 2 + 1] = y;
        x += stripWidth;
      }
    }
    return AtlasLayout._(
      width: width,
      height: (y + shelf + _align - 1) ~/ _align * _align,
      strips: strips,
      runs: runs,
    );
  }

  static int _stripWidth(TileRun run) =>
      run.length * Tiling.size ~/ run.texel + 2;

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

  final List<TileRun> _runs;

  /// The table entry of the outside tile: the texel of its pixel (0, 0).
  static const (int, int) outsideEntry = (1, 1);

  /// The table entry of the deep tiles of [look].
  static (int, int) deepEntryOf(int look) => ((look + 1) * _strip + 1, 1);

  /// The table entry of tile [index] of [run]: the corner of the texel of
  /// that tile's pixel (0, 0) in the run's strip.
  (int, int) entryOf(int run, int index) => (
    strips[run * 2] + 1 + index * Tiling.size ~/ _runs[run].texel,
    strips[run * 2 + 1] + 1,
  );
}
