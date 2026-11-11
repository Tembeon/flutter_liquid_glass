import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/composer/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

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
/// the same density, or a block of such rows ([tall]).
@internal
@immutable
final class TileRun {
  /// Creates the run.
  const TileRun(
    this.row,
    this.column,
    this.length,
    this.shapes,
    this.texel, [
    this.members = 0,
    this.tall = 1,
  ]);

  /// The table row, the first of [tall].
  final int row;

  /// The first tile's column.
  final int column;

  /// How many tiles, at most [Tiling.maxRunTiles].
  final int length;

  /// Index into [Tiling.shapeSets].
  final int shapes;

  /// The side of a texel in buffer pixels: 1, or [GlassReach.coarseTexel].
  final int texel;

  /// The shapes of the set the run's texels evaluate, where every other
  /// shape provably leaves them as they are: up to [Tiling.maxListed] of
  /// them in chain order, a byte each from the lowest, holding the shape's
  /// place in the set plus one, and 0x80 where it is the first of its group
  /// among them. 0 when the texels evaluate the whole set.
  final int members;

  /// How many table rows the run spans: 1, or up to [Tiling.blockTiles]
  /// for a block of coarse tiles, whose strip is one piece.
  final int tall;

  /// [members] as the places in the set and whether each starts its group.
  List<(int, bool)> get listed => [
    for (var word = members; word != 0; word >>= 8)
      ((word & 0x7f) - 1, word & 0x80 != 0),
  ];
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
    required this.deeps,
    required this.shapeSets,
    required this.droppedShapes,
    required this.looks,
    required this.deepLooks,
    this.slack = 0,
    this._tiled,
  });

  /// Classifies a buffer of [width] x [height] pixels holding [shapes],
  /// encoded in buffer pixels, which wear [looks] where they differ. With
  /// [slack] every bound allows each shape that many pixels of movement,
  /// so the tiling still holds once they have moved ([held]).
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
    double slack = 0,
  }) {
    final columns = _tilesOver(width);
    final rows = _tilesOver(height);
    // A read blends texels up to a texel away; past two the field's
    // curvature is gentle enough for a linear read.
    List<_ShapeBounds> over(int cell) => [
      for (var i = 0; i < shapes.count; i++)
        _ShapeBounds.of(
          shapes,
          i,
          cell: cell,
          foldMargin: 2.0 * reach.coarseTexel + slack,
          apron: reach.coarseTexel / 2,
          slack: slack,
        )..prepare((width + cell - 1) ~/ cell, (height + cell - 1) ~/ cell),
    ];
    final bounds = over(size);
    final groups = _ShapeGroups.of(shapes);
    final classifier = _Classifier(
      columns: columns,
      rows: rows,
      reach: reach,
      listable: shapes.count <= geometryMaxShapesPerDraw,
    );
    final blocks = over(size * _Classifier.blockTiles);
    for (var group = 0; group < groups.members.length; group++) {
      classifier.add(
        group,
        groups.members[group],
        tiles: bounds,
        blocks: blocks,
        smoothing: groups.smoothingOf(group),
        sharp: groups.blendOf(group) < 8.0 * reach.coarseTexel,
      );
    }
    final (kinds, fine, lists, wholes) = classifier.finish();
    final deepLooks = looks == null
        ? null
        : _lookKinds(bounds, groups, looks, columns, rows, kinds, fine);
    // A deep tile of two looks turns ring, so with looks a deep block is
    // read tile by tile.
    if (looks != null) {
      for (var block = 0; block < wholes.length; block++) {
        if (wholes[block] == _deepBlock) wholes[block] = _byTile;
      }
    }
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
      runs: _runs(
        columns,
        rows,
        kinds,
        tileSets,
        fine,
        reach.coarseTexel,
        lists,
        wholes,
      ),
      deeps: _deeps(columns, rows, kinds, deepLooks, wholes),
      shapeSets: List.unmodifiable(sets),
      droppedShapes: dropped,
      looks: looks,
      deepLooks: deepLooks,
      slack: slack,
    );
    if (tiling._fits || reach.inward <= 1) return tiling;
    return Tiling.shapes(
      shapes,
      width: width,
      height: height,
      reach: reach._shallower,
      looks: looks,
      slack: slack,
    );
  }

  /// Classifies a buffer of [width] x [height] pixels holding the body of
  /// [field], fitted to one atlas as [Tiling.shapes] is. Its ring tiles
  /// take coarse texels where the field's nodes lie at least a texel apart
  /// and their gradients agree. Where [looks]
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
    final (kinds, fine) = _fieldKinds(field, columns, rows, reach);
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
      runs: _runs(
        columns,
        rows,
        kinds,
        Int32List(columns * rows),
        fine,
        reach.coarseTexel,
        Uint32List(columns * rows),
        null,
      ),
      deeps: _deeps(columns, rows, kinds, deepLooks, null),
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

  /// This tiling with [shapes] and [looks] in place of its own, where it
  /// still holds for them, else null: [shapes] are the shapes it was made
  /// for, none more than [slack] from where it was then, in a buffer of
  /// the same tiles, asked the same [reach], with looks shared out among
  /// the shapes as before. The atlas such a tiling draws holds the shapes
  /// where they are now; only which tiles are constant, which shapes a
  /// strip evaluates and how fine its texels are date from the first.
  Tiling? held(
    ShapeSet shapes, {
    required GlassReach reach,
    ShapeLooks? looks,
  }) {
    final tiled = _tiled ?? this;
    if (slack <= 0 || field != null || reach != this.reach) return null;
    final from = this.looks;
    if ((looks == null) != (from == null)) return null;
    if (looks != null &&
        from != null &&
        (looks.tintOnly != from.tintOnly ||
            !listEquals(looks.lookOf, from.lookOf))) {
      return null;
    }
    final moved = _moved(tiled.shapes, shapes);
    if (moved == null || moved > slack) return null;
    return Tiling._(
      reach: reach,
      shapes: shapes,
      field: null,
      columns: columns,
      rows: rows,
      kinds: kinds,
      runs: runs,
      deeps: deeps,
      shapeSets: shapeSets,
      droppedShapes: droppedShapes,
      looks: looks,
      deepLooks: deepLooks,
      slack: slack,
      tiled: tiled,
    );
  }

  /// How far the shape of [shapes] that moved most lies from where this
  /// tiling last drew it, in buffer pixels; null where [shapes] are not its
  /// shapes moved.
  double? motionTo(ShapeSet shapes) => _moved(this.shapes, shapes);

  // The greatest distance between the centers of [from]'s shapes and
  // [to]'s, or null unless they are the same shapes but for their centers.
  static double? _moved(ShapeSet from, ShapeSet to) {
    if (from.count != to.count) return null;
    final a = from.shapes;
    final b = to.shapes;
    var farthest = 0.0;
    for (var o = 0; o < a.length; o += 12) {
      for (var k = 0; k < 12; k++) {
        if (k == 8 || k == 9) continue;
        // A shape's transform is the difference of two transformed points,
        // which rounds differently wherever the shape lies.
        final value = a[o + k];
        if ((value - b[o + k]).abs() > 1e-6 * (1 + value.abs())) return null;
      }
      if (a[o] == RawShapeType.squirclePair.shaderIndex) {
        for (final k in const [8, 9]) {
          final value = from.superellipsesLower[o + k];
          if ((value - to.superellipsesLower[o + k]).abs() >
              1e-6 * (1 + value.abs())) {
            return null;
          }
        }
      }
      final dx = a[o + 8] - b[o + 8];
      final dy = a[o + 9] - b[o + 9];
      final distance = dx * dx + dy * dy;
      if (distance > farthest) farthest = distance;
    }
    return sqrt(farthest);
  }

  // The ring tiles as runs along each row, a run sharing one set of shapes,
  // one list of them and one density.
  static List<TileRun> _runs(
    int columns,
    int rows,
    Uint8List kinds,
    Int32List tileSets,
    Uint8List fine,
    int coarseTexel,
    Uint32List lists,
    Uint8List? wholes,
  ) {
    final runs = <TileRun>[];
    final blockColumns = (columns + blockTiles - 1) ~/ blockTiles;
    for (var row = 0; row < rows; row++) {
      var column = 0;
      while (column < columns) {
        if (wholes != null && column % blockTiles == 0) {
          final whole =
              wholes[row ~/ blockTiles * blockColumns + column ~/ blockTiles];
          if (whole == _outsideBlock || whole == _deepBlock) {
            column += blockTiles;
            continue;
          }
        }
        final tile = row * columns + column;
        if (kinds[tile] != TileKind.ring.index) {
          column++;
          continue;
        }
        final set = tileSets[tile];
        final members = lists[tile];
        final density = coarseTexel == 1 ? 1 : fine[tile];
        if (density == _inBlock) {
          // A block's tiles are one run, met at its first tile.
          if (row % blockTiles == 0 && column % blockTiles == 0) {
            runs.add(
              TileRun(
                row,
                column,
                min(blockTiles, columns - column),
                set,
                coarseTexel,
                members,
                min(blockTiles, rows - row),
              ),
            );
          }
          column += blockTiles - column % blockTiles;
          continue;
        }
        var end = column + 1;
        while (end < columns &&
            end - column < maxRunTiles &&
            kinds[tile + end - column] == TileKind.ring.index &&
            tileSets[tile + end - column] == set &&
            lists[tile + end - column] == members &&
            (coarseTexel == 1 || fine[tile + end - column] == density)) {
          end++;
        }
        final texel = density != 0 ? 1 : coarseTexel;
        runs.add(TileRun(row, column, end - column, set, texel, members));
        column = end;
      }
    }
    return List.unmodifiable(runs);
  }

  bool get _fits => layout.height <= AtlasLayout.maxSize;

  /// How far each shape may move from where it was tiled with the tiling
  /// still holding ([held]).
  final double slack;

  // The tiling this one holds for other shapes, if it is held.
  final Tiling? _tiled;

  /// Where the atlas holds this tiling's table and strips: about as wide as
  /// it is tall.
  late final AtlasLayout layout = _tiled?.layout ?? AtlasLayout._of(this);

  /// [layout] packed into an atlas [width] texels wide instead, or null
  /// where no strip or table fits that width or the atlas grows too tall.
  /// A page (FlutterGpuGeometryRenderer) asks the same width frame after
  /// frame, so the last answer is kept.
  AtlasLayout? layoutIn(int width) {
    final tiled = _tiled;
    if (tiled != null) return tiled.layoutIn(width);
    if (width == layout.width) return layout;
    if (_packed[this] case final packed? when packed.width == width) {
      return packed;
    }
    if (width < AtlasLayout._leastWidth(this)) return null;
    final packed = AtlasLayout._of(this, width: width);
    if (packed.height > AtlasLayout.maxSize) return null;
    return _packed[this] = packed;
  }

  static final Expando<AtlasLayout> _packed = Expando();

  static int _tilesOver(int pixels) => max(1, (pixels + size - 1) ~/ size);

  /// A rounded box that shape [i] of [shapes] holds, in the shape's own
  /// axes about its center: half its width, half its height and its corner
  /// radius; null where none is known to lie inside it. The bound a tile is
  /// called deep by, for a shader that works the shape out itself.
  static (double, double, double)? innerBoxOf(ShapeSet shapes, int i) {
    final bounds = _ShapeBounds.of(shapes, i);
    if (bounds._ellipse) {
      final minor = min(bounds.halfWidth, bounds.halfHeight);
      return minor > 0 ? (minor, minor, minor) : null;
    }
    if (bounds.innerRadius == double.infinity) return null;
    return (
      bounds.halfWidth - bounds.inset,
      bounds.halfHeight - bounds.inset,
      bounds.innerRadius,
    );
  }

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

  /// The side of a block in tiles: smooth coarse content is tiled in
  /// blocks, each one run ([TileRun.tall]).
  static const int blockTiles = 4;

  // What a tile's density says where the tile is part of a block.
  static const int _inBlock = 2;

  // What a block is as a whole ([_Classifier.finish]): told tile by tile,
  // outside throughout, one piece of coarse texels, or deep throughout.
  static const int _byTile = 0;
  static const int _outsideBlock = 1;
  static const int _ringBlock = 2;
  static const int _deepBlock = 3;

  // The deep tiles as rectangles ([deeps]): a deep block, with the deep
  // blocks beside it, is one; elsewhere a row's deep tiles of one look.
  static Int32List _deeps(
    int columns,
    int rows,
    Uint8List kinds,
    Uint8List? deepLooks,
    Uint8List? wholes,
  ) {
    final deeps = <int>[];
    final blockColumns = (columns + blockTiles - 1) ~/ blockTiles;
    for (var row = 0; row < rows; row++) {
      var column = 0;
      while (column < columns) {
        if (wholes != null && column % blockTiles == 0) {
          final block = row ~/ blockTiles * blockColumns + column ~/ blockTiles;
          final whole = wholes[block];
          if (whole == _deepBlock) {
            var end = block + 1;
            while (end % blockColumns != 0 && wholes[end] == _deepBlock) {
              end++;
            }
            if (row % blockTiles == 0) {
              deeps
                ..add(column)
                ..add(row)
                ..add(min(columns - column, (end - block) * blockTiles))
                ..add(min(rows - row, blockTiles))
                ..add(0);
            }
            column += (end - block) * blockTiles;
            continue;
          }
          if (whole != _byTile) {
            column += blockTiles;
            continue;
          }
        }
        final tile = row * columns + column;
        if (kinds[tile] != TileKind.deep.index) {
          column++;
          continue;
        }
        final look = deepLooks?[tile] ?? 0;
        var end = column + 1;
        while (end < columns &&
            (wholes == null || end % blockTiles != 0) &&
            kinds[tile + end - column] == TileKind.deep.index &&
            (deepLooks?[tile + end - column] ?? 0) == look) {
          end++;
        }
        deeps
          ..add(column)
          ..add(row)
          ..add(end - column)
          ..add(1)
          ..add(look);
        column = end;
      }
    }
    return Int32List.fromList(deeps);
  }

  /// The most shapes a run lists ([TileRun.members]): what one vertex
  /// carries to the geometry pass.
  static const int maxListed = 4;

  /// Tiles along x.
  final int columns;

  /// Tiles along y.
  final int rows;

  /// [TileKind.index] of every tile, row-major.
  final Uint8List kinds;

  /// The ring tiles, row by row.
  final List<TileRun> runs;

  /// The deep tiles as rectangles of one look, five numbers each: column,
  /// row, width and height in tiles, and the look.
  final Int32List deeps;

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
          if (shape.lowerOverTile(column, row) < reach) {
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

  // Each tile's kind, and whether it keeps one texel a pixel.
  //
  // A field's body is bilinear between its nodes, which a linear read of
  // coarse texels follows where the nodes lie at least a texel apart and
  // their gradients agree. Where the gradients over a tile turn against
  // one another, a ridge of the body or a corner the grid barely resolves,
  // the tile keeps one texel a pixel. NEAR, within what the grid resolves:
  // the body creases along the grid's lines, and a coarse texel across a
  // crease rounds it by up to the texel's side times the gradient's turn
  // there over four, the same order as the grid's own sag between nodes:
  // a sixth of a pixel on a corner six nodes in radius, half a pixel in
  // the tightest neck a grid holds.
  @pragma('vm:unsafe:no-bounds-checks')
  static (Uint8List, Uint8List) _fieldKinds(
    BufferField field,
    int columns,
    int rows,
    GlassReach reach,
  ) {
    final kinds = Uint8List(columns * rows);
    final fine = Uint8List(columns * rows);
    final (xx, xy, yx, yy, dx, dy) = field.bufferToGrid;
    final LiquidGlassField(:samples, :cols, rows: nodeRows, :step) =
        field.field;
    final scale = field.distanceScale;
    final coarse = reach.coarseTexel > 1 && step * scale >= reach.coarseTexel;
    // In the field's own units, so a node's distance is compared as read.
    final outward = reach.outward / scale;
    final inward = -reach.inward / scale;
    final agreement = _fieldAgreement * _fieldAgreement;
    // A tile's nodes are those over it and over its strip's apron.
    final apron = reach.coarseTexel / 2;
    final spanX = (xx.abs() + xy.abs()) * (size / 2 + apron);
    final spanY = (yx.abs() + yy.abs()) * (size / 2 + apron);
    final lastColumn = cols - 1;
    final lastRow = nodeRows - 1;
    final outside = TileKind.outside.index;
    final deep = TileKind.deep.index;
    final ring = TileKind.ring.index;
    var tile = 0;
    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * size;
      for (var column = 0; column < columns; column++, tile++) {
        final x = (column + 0.5) * size;
        final gx = xx * x + xy * y + dx;
        final gy = yx * x + yy * y + dy;
        // Bilinear values stay within their nodes, and the field pass
        // clamps to the grid, so the nodes over the tile bound it.
        var i0 = (gx - spanX).floor();
        var i1 = (gx + spanX).ceil();
        var j0 = (gy - spanY).floor();
        var j1 = (gy + spanY).ceil();
        if (i0 < 0) i0 = 0;
        if (i0 > lastColumn) i0 = lastColumn;
        if (i1 < 0) i1 = 0;
        if (i1 > lastColumn) i1 = lastColumn;
        if (j0 < 0) j0 = 0;
        if (j0 > lastRow) j0 = lastRow;
        if (j1 < 0) j1 = 0;
        if (j1 > lastRow) j1 = lastRow;
        var lowest = double.infinity;
        var highest = double.negativeInfinity;
        for (var j = j0; j <= j1; j++) {
          final from = (j * cols + i0) * 4;
          final to = (j * cols + i1) * 4;
          for (var at = from; at <= to; at += 4) {
            final d = samples[at];
            if (d < lowest) lowest = d;
            if (d > highest) highest = d;
          }
        }
        if (lowest >= outward) {
          kinds[tile] = outside;
          continue;
        }
        if (highest <= inward) {
          kinds[tile] = deep;
          continue;
        }
        kinds[tile] = ring;
        if (!coarse) {
          fine[tile] = 1;
          continue;
        }
        // Only a ring tile has texels to keep fine or coarse, and most of a
        // body's tiles are deep or outside: their gradients are not read.
        var sumX = 0.0;
        var sumY = 0.0;
        var lengths = 0.0;
        for (var j = j0; j <= j1; j++) {
          final from = (j * cols + i0) * 4;
          final to = (j * cols + i1) * 4;
          for (var at = from; at <= to; at += 4) {
            final nx = samples[at + 1];
            final ny = samples[at + 2];
            sumX += nx;
            sumY += ny;
            lengths += sqrt(nx * nx + ny * ny);
          }
        }
        if (sumX * sumX + sumY * sumY < agreement * lengths * lengths) {
          fine[tile] = 1;
        }
      }
    }
    return (kinds, fine);
  }

  // How much of their summed length the gradients of a tile's nodes keep
  // when added as vectors, at least, for the tile to take coarse texels:
  // 0.8 is a corner turning through about 130 degrees over the tile.
  static const double _fieldAgreement = 0.8;

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
          if (shape.lowerOverTile(column, row) < reachOut) {
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

/// Classifies the tiles of a buffer group by group.
///
/// A tile is outside or deep where the bounds of its groups' unions prove
/// every pixel is, and ring elsewhere. A ring tile keeps one texel a pixel
/// where two groups meet, where two members of a group with a narrow blend
/// meet, or where a shape's distance or normal folds. A wide blend folds
/// the union nowhere: the blend narrows as the members' normals agree, so
/// the turn of the normal across a seam stays within a texel's worth.
///
/// Each tile also gets its list of shapes ([TileRun.members]), for a
/// buffer whose shapes fit one draw: the members of each group that change
/// the group's union somewhere over the tile ([_chain]).
///
/// A group is bounded over blocks of [blockTiles] x [blockTiles] tiles
/// first: what holds over a block holds for each of its tiles, so a block
/// past every reach is skipped, a deep block is deep throughout, and the
/// tiles of any other bound only the members that change the block.
///
/// A block only one group reaches is not bounded tile by tile where it is
/// one thing as a whole: deep, past the ring, or crossed by the ring
/// without a fold. The last is one piece of coarse texels, which hold
/// what its outside and deep tiles would have held as constants. That is
/// most of a large smooth outline, for a few more coarse texels where the
/// ring only clips a block.
final class _Classifier {
  _Classifier({
    required this.columns,
    required this.rows,
    required GlassReach reach,
    required this.listable,
  }) : _kinds = Uint8List(columns * rows),
       _fine = Uint8List(columns * rows),
       _lists = Uint32List(columns * rows),
       _deep = Uint8List(columns * rows),
       _listed = Uint8List(columns * rows),
       _seamGroup = Int32List(columns * rows)..fillRange(0, columns * rows, -1),
       _claims = Int32List(
         _blocksOver(columns) * _blocksOver(rows),
       )..fillRange(0, _blocksOver(columns) * _blocksOver(rows), _free),
       _claimKinds = Uint8List(_blocksOver(columns) * _blocksOver(rows)),
       _claimLists = Uint32List(_blocksOver(columns) * _blocksOver(rows)),
       _coarse = reach.coarseTexel > 1,
       _outward = reach.outward,
       _inward = reach.inward,
       // A linear read blends texels up to a texel's diagonal away. Where
       // that footprint crosses a hard seam, both groups come within the
       // reach plus two diagonals of the pixel read.
       _seamReach =
           reach.outward +
           (reach.coarseTexel > 1 ? 3.0 * reach.coarseTexel : 0),
       // So the texels of every pixel a read shows are exact where a tile
       // lists every group that comes this near.
       _blended = reach.outward + 1.5 * reach.coarseTexel;

  static const int blockTiles = Tiling.blockTiles;

  static int _blocksOver(int tiles) => (tiles + blockTiles - 1) ~/ blockTiles;

  // A block no group has reached, and one bounded tile by tile.
  static const int _free = -1;
  static const int _byTile = -2;

  final int columns;
  final int rows;
  final bool listable;

  // Each block's claim: the one group that reaches it, or [_free] or
  // [_byTile]; what a claimed block is as a whole ([_whole]); and the list
  // of a smooth one.
  final Int32List _claims;
  final Uint8List _claimKinds;
  final Uint32List _claimLists;

  static const int _none = 0;
  static const int _smooth = 1;
  static const int _margin = 2;
  static const int _deepBlock = 3;

  // What each group was added with, for a block it claimed that another
  // group reaches after all.
  final List<List<int>> _members = [];
  final List<List<_ShapeBounds>> _blockBounds = [];
  final List<bool> _sharp = [];
  List<_ShapeBounds> _tileBounds = const [];
  final Uint8List _kinds;
  final Uint8List _fine;
  final Uint32List _lists;
  final Uint8List _deep;
  final Uint8List _listed;
  final Int32List _seamGroup;
  final bool _coarse;
  final double _outward;
  final double _inward;
  final double _seamReach;
  final double _blended;

  // What [_chain] found last: the places of the members it kept, and the
  // union's bounds.
  Int32List _kept = Int32List(0);
  double _lower = 0;
  double _upper = 0;

  final List<_ShapeBounds> _near = [];
  final List<int> _nearIndices = [];

  /// Each tile's kind, its density (whether it keeps one texel a pixel, or
  /// is part of a block), and its list; and what each block is as a whole
  /// ([Tiling._outsideBlock] and the constants beside it). Only the blocks
  /// bounded tile by tile are visited tile by tile.
  (Uint8List, Uint8List, Uint32List, Uint8List) finish() {
    final wholes = Uint8List(_claims.length);
    final blockColumns = _blocksOver(columns);
    for (var block = 0; block < _claims.length; block++) {
      final claim = _claims[block];
      if (claim == _free || (claim >= 0 && _claimKinds[block] == _margin)) {
        wholes[block] = Tiling._outsideBlock;
        continue;
      }
      final left = block % blockColumns * blockTiles;
      final top = block ~/ blockColumns * blockTiles;
      final right = min(columns, left + blockTiles);
      final bottom = min(rows, top + blockTiles);
      if (claim == _byTile) {
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final tile = y * columns + x;
            if (_deep[tile] != 0) _kinds[tile] = TileKind.deep.index;
            if (!listable || _listed[tile] > Tiling.maxListed) {
              _lists[tile] = 0;
            }
          }
        }
        continue;
      }
      final deep = _claimKinds[block] == _deepBlock;
      wholes[block] = deep ? Tiling._deepBlock : Tiling._ringBlock;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final tile = y * columns + x;
          if (deep) {
            _kinds[tile] = TileKind.deep.index;
          } else {
            _kinds[tile] = TileKind.ring.index;
            _fine[tile] = Tiling._inBlock;
            _lists[tile] = _claimLists[block];
          }
        }
      }
    }
    return (_kinds, _fine, _lists, wholes);
  }

  /// Classifies the tiles [group] reaches: its [members] in chain order,
  /// bounded over tiles by [tiles] and over blocks by [blocks]. Their union
  /// lies at most [smoothing] below its nearest member, and folds where two
  /// of them meet if their blend is [sharp].
  void add(
    int group,
    List<int> members, {
    required List<_ShapeBounds> tiles,
    required List<_ShapeBounds> blocks,
    required double smoothing,
    required bool sharp,
  }) {
    final count = members.length;
    if (_kept.length < count) _kept = Int32List(count);
    final reach = max(_blended, _seamReach);
    final blockColumns = _blocksOver(columns);
    final blockRows = _blocksOver(rows);
    var c0 = blockColumns;
    var r0 = blockRows;
    var c1 = -1;
    var r1 = -1;
    final shapes = <_ShapeBounds>[];
    for (final i in members) {
      final (left, top, right, bottom) = blocks[i].tileSpan(
        reach + smoothing,
        blockColumns,
        blockRows,
      );
      c0 = min(c0, left);
      r0 = min(r0, top);
      c1 = max(c1, right);
      r1 = max(r1, bottom);
      shapes.add(blocks[i]);
    }
    while (_members.length <= group) {
      _members.add(const []);
      _blockBounds.add(const []);
      _sharp.add(false);
    }
    _members[group] = members;
    _blockBounds[group] = shapes;
    _sharp[group] = sharp;
    _tileBounds = tiles;
    for (var row = r0; row <= r1; row++) {
      for (var column = c0; column <= c1; column++) {
        var kept = _chain(shapes, count, column, row);
        if (_lower >= reach) continue;
        final block = row * blockColumns + column;
        final claim = _claims[block];
        if (claim == _free) {
          final whole = _whole(shapes, kept, column, row, sharp);
          if (whole != _none) {
            _claims[block] = group;
            _claimKinds[block] = whole;
            var list = 0;
            if (whole == _smooth && kept <= Tiling.maxListed) {
              for (var k = 0; k < kept; k++) {
                list |=
                    ((members[_kept[k]] + 1) | (k == 0 ? 0x80 : 0)) << (8 * k);
              }
            }
            _claimLists[block] = list;
            continue;
          }
        }
        _claims[block] = _byTile;
        if (claim >= 0) {
          // Two groups meet here after all: the first is bounded tile by
          // tile like this one.
          _boundTiles(
            claim,
            _chain(_blockBounds[claim], _members[claim].length, column, row),
            column,
            row,
          );
          kept = _chain(shapes, count, column, row);
        }
        _boundTiles(group, kept, column, row);
      }
    }
  }

  // What block [column], [row] is as a whole for the group whose [kept]
  // members [_chain] just found over it, while no other group reaches it:
  // deep throughout; past the ring, where the group only counts beside
  // another's; or [_smooth], one piece of coarse texels, where its ring
  // crosses the block and neither a member nor a narrow blend folds there.
  // Else [_none].
  int _whole(
    List<_ShapeBounds> shapes,
    int kept,
    int column,
    int row,
    bool sharp,
  ) {
    if (_upper <= -_inward) return _deepBlock;
    if (_lower >= _outward) return _margin;
    if (!_coarse || !listable) return _none;
    if (kept > 1 && sharp) return _none;
    for (var k = 0; k < kept; k++) {
      if (shapes[_kept[k]].foldsOverTile(column, row)) return _none;
    }
    return _smooth;
  }

  // Bounds the tiles of block [column], [row] for [group], whose [kept]
  // members [_chain] just found over the block.
  void _boundTiles(int group, int kept, int column, int row) {
    final members = _members[group];
    final left = column * blockTiles;
    final top = row * blockTiles;
    final right = min(columns, left + blockTiles) - 1;
    final bottom = min(rows, top + blockTiles) - 1;
    if (_upper <= -_inward) {
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          final tile = y * columns + x;
          _meet(tile, group);
          for (var k = 0; k < kept; k++) {
            _list(tile, members[_kept[k]], starts: k == 0);
          }
          _deep[tile] = 1;
        }
      }
      return;
    }
    if (kept == 1) {
      final i = members[_kept[0]];
      _alone(group, _tileBounds[i], i, left, top, right, bottom);
      return;
    }
    _near.clear();
    _nearIndices.clear();
    for (var k = 0; k < kept; k++) {
      final i = members[_kept[k]];
      _near.add(_tileBounds[i]);
      _nearIndices.add(i);
    }
    _several(group, left, top, right, bottom, sharp: _sharp[group]);
  }

  void _meet(int tile, int group) {
    final other = _seamGroup[tile];
    if (other < 0) {
      _seamGroup[tile] = group;
    } else if (other != group) {
      _fine[tile] = 1;
    }
  }

  void _list(int tile, int shape, {required bool starts}) {
    final count = _listed[tile];
    if (count < Tiling.maxListed) {
      _lists[tile] |= ((shape + 1) | (starts ? 0x80 : 0)) << (8 * count);
    }
    if (count < 255) _listed[tile] = count + 1;
  }

  // The tiles [left], [top] to [right], [bottom] where [shape], shape
  // [index] of the buffer, is the one member of [group] that changes its
  // union.
  void _alone(
    int group,
    _ShapeBounds shape,
    int index,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        final lower = shape.lowerOverTile(column, row);
        if (lower >= _blended && lower >= _seamReach) continue;
        final tile = row * columns + column;
        if (lower < _seamReach) _meet(tile, group);
        if (lower >= _blended) continue;
        _list(tile, index, starts: true);
        if (lower >= _outward) continue;
        if (lower <= -_inward && shape.upperOverTile(column, row) <= -_inward) {
          _deep[tile] = 1;
          continue;
        }
        _kinds[tile] = TileKind.ring.index;
        if (_coarse && _fine[tile] == 0 && shape.foldsOverTile(column, row)) {
          _fine[tile] = 1;
        }
      }
    }
  }

  // The tiles [left], [top] to [right], [bottom] of [group] whose union
  // only the members in [_near] change.
  void _several(
    int group,
    int left,
    int top,
    int right,
    int bottom, {
    required bool sharp,
  }) {
    final shapes = _near;
    final indices = _nearIndices;
    final count = shapes.length;
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        final kept = _chain(shapes, count, column, row);
        final lower = _lower;
        if (lower >= _blended && lower >= _seamReach) continue;
        final tile = row * columns + column;
        if (lower < _seamReach) _meet(tile, group);
        if (lower >= _blended) continue;
        for (var k = 0; k < kept; k++) {
          _list(tile, indices[_kept[k]], starts: k == 0);
        }
        if (lower >= _outward) continue;
        if (_upper <= -_inward) {
          _deep[tile] = 1;
          continue;
        }
        _kinds[tile] = TileKind.ring.index;
        if (!_coarse || _fine[tile] != 0) continue;
        if (kept > 1 && sharp) {
          _fine[tile] = 1;
          continue;
        }
        for (var k = 0; k < kept; k++) {
          if (shapes[_kept[k]].foldsOverTile(column, row)) {
            _fine[tile] = 1;
            break;
          }
        }
      }
    }
  }

  // Folds the first [count] of [shapes], one group in chain order, over
  // cell [column], [row] as the geometry pass folds them at a pixel, on
  // bounds: [_lower] and [_upper] bound the union over the cell, and
  // [_kept] holds the places of the members that change it there; returns
  // how many.
  //
  // A smooth union of radius k is the nearer operand wherever the other
  // lies k or more past it, its distance, its normal and its look alike.
  // So a member that far past the union so far over the whole cell changes
  // nothing, and one that far inside it replaces everything before it.
  // Elsewhere the union is at most the nearer of the two, and below it by
  // at most what a blend takes at the narrowest gap between them.
  int _chain(List<_ShapeBounds> shapes, int count, int column, int row) {
    final first = shapes[0];
    var lower = first.lowerOverTile(column, row);
    var upper = first.upperOverTile(column, row);
    var kept = 1;
    _kept[0] = 0;
    for (var k = 1; k < count; k++) {
      final shape = shapes[k];
      final blend = shape.blend;
      final shapeLower = shape.lowerOverTile(column, row);
      if (shapeLower >= upper + blend) continue;
      final shapeUpper = shape.upperOverTile(column, row);
      if (lower >= shapeUpper + blend) {
        _kept[0] = k;
        kept = 1;
        lower = shapeLower;
        upper = shapeUpper;
        continue;
      }
      _kept[kept++] = k;
      if (blend > 0) {
        final gap = max(0, max(shapeLower - upper, lower - shapeUpper));
        final bite = blend - gap;
        lower = min(lower, shapeLower) - bite * bite * 0.25 / blend;
      } else {
        lower = min(lower, shapeLower);
      }
      upper = min(upper, shapeUpper);
    }
    _lower = lower;
    _upper = upper;
    return kept;
  }
}

/// Closed-form bounds of one encoded shape's distance over the tiles of a
/// buffer, in the units the geometry pass writes (local distance times the
/// shape's distance scale). A tile's preimage is a parallelogram, the same
/// size for every tile, grown by the apron of the tile's strip.
///
/// A box shape lies between two rounded rectangles: it holds one inset by a
/// fiftieth of its radius, and the rounded rectangle of its box and radius
/// holds it within a 500th of the radius; a pair holds the one of its
/// greater radius, where that fits its box, and lies in its box
/// (shape_bounds_test). A rounded rectangle's distance is convex and grows
/// with |x| and with |y|, so it is least over a box at the box's point
/// nearest the axes and greatest over a parallelogram at a corner.
final class _ShapeBounds {
  _ShapeBounds._({
    required this.type,
    required this.halfWidth,
    required this.halfHeight,
    required this.outerRadius,
    required this.outset,
    required this.inset,
    required this.innerRadius,
    required this.foldInset,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.blend,
    required this.foldMargin,
    required this.apron,
    required this.cell,
    required double slack,
  }) : _half = cell / 2 + apron,
       _extentX = (a.abs() + b.abs()) * (cell / 2 + apron),
       _extentY = (c.abs() + d.abs()) * (cell / 2 + apron),
       _ellipse = type == RawShapeType.ellipse.shaderIndex,
       // A shape that moves by some distance changes its own distance by
       // no more anywhere.
       _slack =
           slack +
           (type == RawShapeType.roundedRectangle.shaderIndex
               ? 0
               : _solveSlack);

  /// Shape [i] of [shapes] over tiles of [cell] buffer pixels a side;
  /// [foldsOverTile] looks [foldMargin] pixels around a tile, and every
  /// bound [apron] pixels around it, for the shape anywhere within [slack]
  /// pixels of where it is.
  factory _ShapeBounds.of(
    ShapeSet shapes,
    int i, {
    int cell = Tiling.size,
    double foldMargin = 0,
    double apron = 0.5,
    double slack = 0,
  }) {
    final row = shapes.shapes;
    final o = i * 12;
    final type = row[o];
    final halfWidth = row[o + 1] / 2;
    final halfHeight = row[o + 2] / 2;
    final shorter = min(halfWidth, halfHeight);
    var radius = row[o + 3];
    var least = radius;
    // A pair's corner can be as tall as its box, which no rounded rectangle
    // inside it follows.
    var hollow = false;
    if (type == RawShapeType.squirclePair.shaderIndex) {
      // The row holds the top radius as it was asked for, which a pair that
      // does not fit scales down: only the pair's box is known to hold it.
      least = 0;
      radius = max(radius, shapes.superellipsesLower[i * 12 + 8]);
      hollow = radius > shorter;
    }
    final corner = min(radius, shorter);
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
    final exact = type == RawShapeType.roundedRectangle.shaderIndex;
    final inset = exact ? 0.0 : min(0.02 * corner + 0.01, shorter / 2);
    final around = min(least, shorter);
    return _ShapeBounds._(
      type: type,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      outerRadius: around,
      outset: exact ? 0.0 : 0.002 * around,
      inset: inset,
      innerRadius: hollow ? double.infinity : min(corner, shorter - inset),
      foldInset: foldInset,
      a: row[o + 4],
      b: row[o + 5],
      c: row[o + 6],
      d: row[o + 7],
      centerX: row[o + 8],
      centerY: row[o + 9],
      scale: row[o + 10],
      blend: max(0, row[o + 11]),
      foldMargin: foldMargin,
      apron: apron,
      cell: cell,
      slack: slack,
    );
  }

  final double type;
  final double halfWidth;
  final double halfHeight;

  // The rounded rectangle around a box shape: of its box, with corners of
  // [outerRadius], which the shape passes by at most [outset].
  final double outerRadius;
  final double outset;

  // The rounded rectangle inside a box shape: its box [inset] from the
  // shape's, with corners of [innerRadius], infinite where the shape is
  // known to hold none.
  final double inset;
  final double innerRadius;

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

  // The radius of the shape's smooth union with those before it in its
  // group; 0 for the first.
  final double blend;
  final double foldMargin;
  final double apron;
  final int cell;

  // What the geometry pass's continuous corners, a bisection and a chord,
  // can lie off the shape dart:ui draws.
  static const double _solveSlack = 0.25;

  final double _half;
  final double _extentX;
  final double _extentY;
  late final double _foldExtentX =
      (a.abs() + b.abs()) * (cell / 2 + foldMargin);
  late final double _foldExtentY =
      (c.abs() + d.abs()) * (cell / 2 + foldMargin);
  final bool _ellipse;
  final double _slack;

  /// The tiles [lowerOverTile] can bound below [reach]: the shape's box
  /// grown by the reach in its own units, mapped into the buffer. The
  /// geometry pass measures distance in the shape's units times [scale], the
  /// basis's least stretch, so a box in buffer pixels grown by [reach] can
  /// miss pixels beside a stretched shape.
  (int, int, int, int) tileSpan(double reach, int columns, int rows) {
    final determinant = a * d - b * c;
    final room = (reach + 2 * apron + _slack) / scale;
    final grownX = halfWidth + room;
    final grownY = halfHeight + room;
    final extentX = (d.abs() * grownX + b.abs() * grownY) / determinant.abs();
    final extentY = (c.abs() * grownX + a.abs() * grownY) / determinant.abs();
    int tile(double at, int tiles) => (at / cell).floor().clamp(0, tiles - 1);
    return (
      tile(centerX - extentX, columns),
      tile(centerY - extentY, rows),
      tile(centerX + extentX, columns),
      tile(centerY + extentY, rows),
    );
  }

  double _localX(int column, int row) =>
      a * ((column + 0.5) * cell - centerX) +
      b * ((row + 0.5) * cell - centerY);

  double _localY(int column, int row) =>
      c * ((column + 0.5) * cell - centerX) +
      d * ((row + 0.5) * cell - centerY);

  // A box shape whose axes are the buffer's bounds a tile from its column
  // and its row alone: per column the |x| of the preimage's point nearest
  // the center, then of its farthest, and per row the same of |y|.
  bool _separable = false;
  Float64List _columnsX = _none;
  Float64List _rowsY = _none;
  static final Float64List _none = Float64List(0);

  /// Readies the bounds for a buffer of [columns] x [rows] tiles.
  void prepare(int columns, int rows) {
    if (_ellipse || b != 0 || c != 0) return;
    Float64List table(int count, double inverse, double center, double extent) {
      final table = Float64List(count * 2);
      for (var i = 0; i < count; i++) {
        final at = (inverse * ((i + 0.5) * cell - center)).abs();
        table[i * 2] = _positive(at - extent);
        table[i * 2 + 1] = at + extent;
      }
      return table;
    }

    _separable = true;
    _columnsX = table(columns, a, centerX, _extentX);
    _rowsY = table(rows, d, centerY, _extentY);
  }

  /// A lower bound of the distance (negative inside) over tile [column],
  /// [row]: the least distance of the shape around this one over the box
  /// around the tile's preimage.
  double lowerOverTile(int column, int row) {
    // The shapes are convex and mirror-symmetric in both local axes, so
    // their distance grows with |x| and with |y|: the box's point nearest
    // the axes is its nearest point.
    final double qx;
    final double qy;
    if (_separable) {
      qx = _columnsX[column * 2];
      qy = _rowsY[row * 2];
    } else {
      qx = _positive(_localX(column, row).abs() - _extentX);
      qy = _positive(_localY(column, row).abs() - _extentY);
    }
    if (!_ellipse) {
      // The geometry pass measures a sharp box by its farther side.
      if (outerRadius <= 1e-4) {
        return max(qx - halfWidth, qy - halfHeight) * scale - _slack;
      }
      return (_roundedBox(qx, qy, halfWidth, halfHeight, outerRadius) -
                  outset) *
              scale -
          _slack;
    }
    if (halfWidth <= 0 || halfHeight <= 0) {
      final gx = _positive(qx - halfWidth);
      final gy = _positive(qy - halfHeight);
      return sqrt(gx * gx + gy * gy) * scale - _slack;
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
    final gx = _positive(qx - halfWidth);
    final gy = _positive(qy - halfHeight);
    return max(sqrt(gx * gx + gy * gy), support) * scale - _slack;
  }

  /// An upper bound of the distance over tile [column], [row]: the greatest
  /// distance of the shape inside this one over the tile's preimage, which
  /// a convex distance takes at a corner.
  double upperOverTile(int column, int row) {
    if (innerRadius == double.infinity) return double.infinity;
    if (_separable) {
      return _roundedBox(
                _columnsX[column * 2 + 1],
                _rowsY[row * 2 + 1],
                halfWidth - inset,
                halfHeight - inset,
                innerRadius,
              ) *
              scale +
          _slack;
    }
    final x = _localX(column, row);
    final y = _localY(column, row);
    final ux = (a + b) * _half;
    final uy = (c + d) * _half;
    final vx = (a - b) * _half;
    final vy = (c - d) * _half;
    if (!_ellipse) {
      final hw = halfWidth - inset;
      final hh = halfHeight - inset;
      final r = innerRadius;
      final distance = max(
        max(
          _roundedBox((x + ux).abs(), (y + uy).abs(), hw, hh, r),
          _roundedBox((x - ux).abs(), (y - uy).abs(), hw, hh, r),
        ),
        max(
          _roundedBox((x + vx).abs(), (y + vy).abs(), hw, hh, r),
          _roundedBox((x - vx).abs(), (y - vy).abs(), hw, hh, r),
        ),
      );
      return distance * scale + _slack;
    }
    if (halfWidth <= 0 || halfHeight <= 0) return double.infinity;
    // An ellipse holds its copy scaled by rho about the center (the copy
    // through the point) grown by (1 - rho) times its minor semi-axis, and
    // the circle of its minor semi-axis. Both bounds are convex.
    final minor = min(halfWidth, halfHeight);
    var rho = 0.0;
    var radius = 0.0;
    for (final (px, py) in [
      (x + ux, y + uy),
      (x - ux, y - uy),
      (x + vx, y + vy),
      (x - vx, y - vy),
    ]) {
      final rx = px / halfWidth;
      final ry = py / halfHeight;
      rho = max(rho, sqrt(rx * rx + ry * ry));
      radius = max(radius, sqrt(px * px + py * py));
    }
    return (rho <= 1 ? (rho - 1) * minor : radius - minor) * scale + _slack;
  }

  // The signed distance from (x, y), both positive, to the box of half size
  // (hw, hh) with corners of radius r.
  static double _roundedBox(
    double x,
    double y,
    double hw,
    double hh,
    double r,
  ) {
    final gx = x - hw + r;
    final gy = y - hh + r;
    if (gx <= 0 || gy <= 0) return max(gx, gy) - r;
    return sqrt(gx * gx + gy * gy) - r;
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
    if (_ellipse) {
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
}

/// Where a drawn atlas lies in the texture it shares with the other
/// atlases of its frame: the texel of its table's first entry and the
/// texture's size, as the final shader's uGeometryAtlas takes them.
typedef AtlasPlace = ({int tableX, int tableY, int width, int height});

/// Where one buffer's table, constant tiles and ring strips sit in its atlas
/// texture.
///
/// The 18 x 18 block at texel (0, 0) holds the outside value and the next
/// blocks the deep value, one block a look ([Tiling.looks]). The atlas is
/// cleared to the outside tile's table entry, so only deep and ring tiles
/// write theirs. The table lies below them, one texel per tile, and the
/// strips beside and below both: a run of n tiles of texels t pixels a
/// side ([TileRun.texel]), m rows tall ([TileRun.tall]), is `16 n / t + 2`
/// x `16 m / t + 2` texels, with a one-texel apron evaluated like the
/// rest, so a linear read between texels stays on exact values.
@internal
@immutable
final class AtlasLayout {
  const AtlasLayout._({
    required this.width,
    required this.height,
    required this.strips,
    required this._runs,
  });

  // Shelves of strips, the tallest strips first (the full-density strips
  // and the blocks, then the coarse runs), each height on shelves of its
  // own, the shelves beside the constants and the table starting past
  // them. A layout taller than [maxSize] does not fit; Tiling tiles such a
  // ring again.
  factory AtlasLayout._of(Tiling tiling, {int? width}) {
    final runs = tiling.runs;
    final headWidth = _headWidth(tiling);
    final headHeight = tableOrigin.$2 + tiling.rows;
    var atlasWidth = width ?? 0;
    final heights = <int>[];
    var area = headWidth * headHeight;
    for (final run in runs) {
      final height = _stripHeight(run);
      area += _stripWidth(run) * height;
      if (!heights.contains(height)) heights.add(height);
    }
    heights.sort((a, b) => b - a);
    if (width == null) {
      // An eighth over the area for what the shelves leave empty.
      atlasWidth = max(_leastWidth(tiling), sqrt(area * 1.125).ceil());
      atlasWidth = min(
        maxSize,
        (atlasWidth + _alignWidth - 1) ~/ _alignWidth * _alignWidth,
      );
    }
    final strips = Int32List(runs.length * 2);
    var x = headWidth;
    var y = 0;
    var shelf = 0;
    for (final height in heights) {
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if (_stripHeight(run) != height) continue;
        final stripWidth = _stripWidth(run);
        if (x + stripWidth > atlasWidth || height != shelf) {
          y += shelf;
          shelf = height;
          x = y < headHeight ? headWidth : 0;
          if (x + stripWidth > atlasWidth) {
            y = headHeight;
            x = 0;
          }
        }
        strips[i * 2] = x;
        strips[i * 2 + 1] = y;
        x += stripWidth;
      }
    }
    final used = max(headHeight, y + shelf);
    return AtlasLayout._(
      width: atlasWidth,
      height: (used + _alignHeight - 1) ~/ _alignHeight * _alignHeight,
      strips: strips,
      runs: runs,
    );
  }

  // The width of the constant tiles above the table, and of the table.
  static int _headWidth(Tiling tiling) => max(
    (1 + max<int>(1, tiling.looks?.count ?? 0)) * _strip,
    tiling.columns,
  );

  // The narrowest atlas that holds the constants, the table and every
  // strip of [tiling].
  static int _leastWidth(Tiling tiling) {
    var widest = _headWidth(tiling);
    for (final run in tiling.runs) {
      widest = max(widest, _stripWidth(run));
    }
    return widest;
  }

  static int _stripWidth(TileRun run) =>
      run.length * Tiling.size ~/ run.texel + 2;

  static int _stripHeight(TileRun run) =>
      run.tall * Tiling.size ~/ run.texel + 2;

  static const int _strip = Tiling.size + 2;

  // A tiled GPU stores a target in tiles of 16 texels. Widths step by two,
  // so an atlas that grows a little keeps its width and its texture.
  static const int _alignWidth = 32;
  static const int _alignHeight = 16;

  /// The largest atlas side: table entries are atlas texel coordinates in a
  /// 16-bit float, exact up to 2048.
  static const int maxSize = 2048;

  /// The atlas size in texels.
  final int width;

  /// The atlas size in texels.
  final int height;

  /// Texel of table entry (0, 0), below the constant tiles.
  static const (int, int) tableOrigin = (0, _strip);

  /// The place of an atlas that is not drawn.
  static const AtlasPlace unplaced = (
    tableX: 0,
    tableY: _strip,
    width: 0,
    height: 0,
  );

  /// Each run's strip corner (its apron's top-left texel), x then y.
  final Int32List strips;

  final List<TileRun> _runs;

  /// The table entry of the outside tile: the texel of its pixel (0, 0).
  static const (int, int) outsideEntry = (1, 1);

  /// The table entry of the deep tiles of [look].
  static (int, int) deepEntryOf(int look) => ((look + 1) * _strip + 1, 1);

  /// The table entry of tile [index] of [run], [down] rows below its
  /// first: the corner of the texel of that tile's pixel (0, 0) in the
  /// run's strip.
  (int, int) entryOf(int run, int index, [int down = 0]) => (
    strips[run * 2] + 1 + index * Tiling.size ~/ _runs[run].texel,
    strips[run * 2 + 1] + 1 + down * Tiling.size ~/ _runs[run].texel,
  );
}
