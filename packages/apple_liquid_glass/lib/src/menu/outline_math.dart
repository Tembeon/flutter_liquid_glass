import 'dart:math' as math;

import 'package:apple_liquid_glass/src/surface/outline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// How much larger a corner radius the glass's optical normals turn on
/// than the shape's own: the factor the renderer's analytic shapes use
/// (`kOpticalCornerRadiusScale` in its sdf.glsl, fitted to iOS 27 card
/// corners), so a fused body turns its light at a corner where the same
/// shape drawn alone does.
@internal
const double opticalCornerScale = 1.5;

/// The rounded boxes a fused outline is made of, laid out for the inner
/// loops: per box its center, half extents and clamped corner radius.
@internal
class OutlineBoxes {
  /// Lays out [shapes], whose corners must share one circular radius.
  OutlineBoxes(List<RRect> shapes)
    : length = shapes.length,
      _data = Float64List(shapes.length * 5) {
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      _requireUniform(shape);
      final hx = shape.width / 2;
      final hy = shape.height / 2;
      _data[i * 5] = shape.center.dx;
      _data[i * 5 + 1] = shape.center.dy;
      _data[i * 5 + 2] = hx;
      _data[i * 5 + 3] = hy;
      _data[i * 5 + 4] = math.min(shape.tlRadiusX, math.min(hx, hy));
    }
  }

  /// The number of boxes.
  final int length;

  /// Whether box [i]'s optical normals ever differ from its exact ones:
  /// false for a capsule or a circle, whose corners are already as round
  /// as its thickness allows.
  bool turns(int i) =>
      _data[i * 5 + 4] * opticalCornerScale > _data[i * 5 + 4] &&
      _data[i * 5 + 4] < halfMinor(i);

  final Float64List _data;

  /// The half thickness of box [i].
  double halfMinor(int i) => math.min(_data[i * 5 + 2], _data[i * 5 + 3]);

  /// The signed distance from (x, y) to box [i].
  double distance(int i, double x, double y) {
    final r = _data[i * 5 + 4];
    final qx = (x - _data[i * 5]).abs() - _data[i * 5 + 2] + r;
    final qy = (y - _data[i * 5 + 1]).abs() - _data[i * 5 + 3] + r;
    return boxDistance(qx, qy, r);
  }

  /// Whether (x, y) lies where box [i]'s optical normals can differ from
  /// its exact ones: in the square of a corner of the optical radius.
  bool inOpticalCorner(int i, double x, double y) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final optical = math.min(
      _data[i * 5 + 4] * opticalCornerScale,
      math.min(hx, hy),
    );
    return (x - _data[i * 5]).abs() > hx - optical &&
        (y - _data[i * 5 + 1]).abs() > hy - optical;
  }

  /// Whether [x] lies in the columns of box [i]'s optical corners: the
  /// horizontal half of [inOpticalCorner].
  bool inOpticalCornerColumns(int i, double x) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final optical = math.min(
      _data[i * 5 + 4] * opticalCornerScale,
      math.min(hx, hy),
    );
    return (x - _data[i * 5]).abs() > hx - optical;
  }

  /// Whether [y] lies in the rows of box [i]'s optical corners: the
  /// vertical half of [inOpticalCorner].
  bool inOpticalCornerRows(int i, double y) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final optical = math.min(
      _data[i * 5 + 4] * opticalCornerScale,
      math.min(hx, hy),
    );
    return (y - _data[i * 5 + 1]).abs() > hy - optical;
  }

  /// The rotation from box [i]'s exact normal at (x, y) to its optical
  /// normal, the one a corner [opticalCornerScale] times rounder
  /// gives, as (cos, sin) written into [out] at [at].
  void opticalTurn(int i, double x, double y, Float64List out, int at) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final half = math.min(hx, hy);
    final exact = _data[i * 5 + 4];
    final optical = math.min(exact * opticalCornerScale, half);
    out[at] = 1;
    out[at + 1] = 0;
    if (optical <= exact) return;
    final px = x - _data[i * 5];
    final py = y - _data[i * 5 + 1];
    final ax = px.abs() - hx;
    final ay = py.abs() - hy;
    final ox = ax + optical;
    final oy = ay + optical;
    if (ox <= 0 || oy <= 0) return;
    final ex = ax + exact;
    final ey = ay + exact;
    double enx;
    double eny;
    if (ex > 0 && ey > 0) {
      final length = math.sqrt(ex * ex + ey * ey);
      enx = ex / length;
      eny = ey / length;
    } else if (ex > ey) {
      enx = 1;
      eny = 0;
    } else {
      enx = 0;
      eny = 1;
    }
    final length = math.sqrt(ox * ox + oy * oy);
    final onx = ox / length;
    final ony = oy / length;
    final mirrored = (px < 0) != (py < 0);
    out[at] = enx * onx + eny * ony;
    out[at + 1] = (enx * ony - eny * onx) * (mirrored ? -1 : 1);
  }
}

/// The signed distance of a rounded box from its corner-relative offsets
/// [qx], [qy] (the distance past the box's inner rectangle along each
/// axis) and its corner radius [r].
@internal
double boxDistance(double qx, double qy, double r) {
  double outside;
  if (qx > 0) {
    outside = qy > 0 ? math.sqrt(qx * qx + qy * qy) : qx;
  } else {
    outside = qy > 0 ? qy : 0;
  }
  final inner = qx > qy ? qx : qy;
  return outside + (inner < 0 ? inner : 0.0) - r;
}

/// The outlines traced from sampled fields over the isolate's life; debug
/// builds only.
/// How many outlines have been traced, in debug builds.
@visibleForTesting
int debugOutlineTraces = 0;

/// A fused outline before it becomes a [GlassOutline]: its field
/// samples and its edge as closed loops of contour crossings, plain typed
/// data that any isolate can compute and send.
///
/// [outlineFromParts] turns the loops into the edge, the
/// quadratic B-spline through the crossings.
@internal
final class OutlineParts {
  /// Creates the parts of an outline.
  const OutlineParts({
    required this.samples,
    required this.cols,
    required this.rows,
    required this.left,
    required this.top,
    required this.step,
    required this.points,
    required this.loops,
  });

  /// Creates the parts of an outline that is its edge alone, without
  /// field samples, for a flat fill.
  OutlineParts.edge({required this.points, required this.loops})
    : samples = _noSamples,
      cols = 0,
      rows = 0,
      left = 0,
      top = 0,
      step = 0;

  static final Float32List _noSamples = Float32List(0);

  /// The field samples, four per node, row-major (`GlassField.samples`);
  /// empty for an edge alone.
  final Float32List samples;

  /// Whether the parts carry field samples; false for an edge alone.
  bool get hasField => samples.isNotEmpty;

  /// The field nodes along x.
  final int cols;

  /// The field nodes along y.
  final int rows;

  /// The x of field node (0, 0) in logical pixels.
  final double left;

  /// The y of field node (0, 0) in logical pixels.
  final double top;

  /// The distance between neighboring field nodes, in logical pixels.
  final double step;

  /// The contour crossings, (x, y) after (x, y), loop after loop.
  final Float64List points;

  /// The number of crossings of each loop, in the order of [points].
  final Int32List loops;
}

/// The parts of an outline traced from sampled fields.
@internal
@pragma('vm:unsafe:no-bounds-checks')
OutlineParts outlinePartsFromFields({
  required Float64List trace,
  required int cols,
  required int rows,
  required Uint8List near,
  required int blockCols,
  required int block,
  required Float64List distance,
  required Float64List halfMinor,
  required Float64List turn,
  required int stride,
  required double left,
  required double top,
  required double step,
}) {
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final fieldStep = step * stride;
  final samples = Float32List(fieldCols * fieldRows * 4);
  for (var j = 0; j < fieldRows; j++) {
    final up = j > 0 ? j - 1 : 0;
    final down = j < fieldRows - 1 ? j + 1 : fieldRows - 1;
    for (var i = 0; i < fieldCols; i++) {
      final back = i > 0 ? i - 1 : 0;
      final ahead = i < fieldCols - 1 ? i + 1 : fieldCols - 1;
      final at = j * fieldCols + i;
      final gx =
          (distance[j * fieldCols + ahead] - distance[j * fieldCols + back]) /
          ((ahead - back) * fieldStep);
      final gy =
          (distance[down * fieldCols + i] - distance[up * fieldCols + i]) /
          ((down - up) * fieldStep);
      final c = turn[at * 2];
      final s = turn[at * 2 + 1];
      final out = at * 4;
      samples[out] = distance[at];
      samples[out + 1] = gx * c - gy * s;
      samples[out + 2] = gx * s + gy * c;
      samples[out + 3] = halfMinor[at];
    }
  }
  final edge = outlineEdgeParts(
    trace: trace,
    cols: cols,
    rows: rows,
    near: near,
    blockCols: blockCols,
    block: block,
    left: left,
    top: top,
    step: step,
  );
  return OutlineParts(
    samples: samples,
    cols: fieldCols,
    rows: fieldRows,
    left: left,
    top: top,
    step: fieldStep,
    points: edge.points,
    loops: edge.loops,
  );
}

/// The edge of a trace grid alone, without field samples: the contour
/// crossings [outlinePartsFromFields] traces from the same
/// [trace] grid and [near] blocks, for a body that is only filled.
@internal
OutlineParts outlineEdgeParts({
  required Float64List trace,
  required int cols,
  required int rows,
  required Uint8List near,
  required int blockCols,
  required int block,
  required double left,
  required double top,
  required double step,
}) {
  assert(() {
    debugOutlineTraces++;
    return true;
  }(), 'Count traces in debug builds.');
  final (points, loops) = _OutlineTracer.trace(
    trace,
    cols,
    rows,
    near: near,
    blockCols: blockCols,
    block: block,
    left: left,
    top: top,
    step: step,
  );
  return OutlineParts.edge(points: points, loops: loops);
}

/// The outline [parts] describe: the quadratic B-spline through each loop
/// of crossings as one even-odd path, shaded from the field samples, or
/// its edge alone when the parts carry no samples.
///
/// A run of crossings along one grid row or column, where the spline is
/// straight, becomes one line.
@internal
@pragma('vm:unsafe:no-bounds-checks')
GlassOutline outlineFromParts(OutlineParts parts) {
  final path = _outlinePath(parts.points, parts.loops);
  if (!parts.hasField) return GlassOutline(path);
  return GlassOutline(
    path,
    field: LiquidGlassField(
      samples: parts.samples,
      cols: parts.cols,
      rows: parts.rows,
      origin: Offset(parts.left, parts.top),
      step: parts.step,
    ),
  );
}

@pragma('vm:unsafe:no-bounds-checks')
Path _outlinePath(Float64List xy, Int32List loops) {
  final path = Path();
  path.fillType = PathFillType.evenOdd;
  var base = 0;
  for (var l = 0; l < loops.length; l++) {
    final n = loops[l];
    final first = base;
    final last = base + n - 1;
    var fromX = (xy[last * 2] + xy[first * 2]) / 2;
    var fromY = (xy[last * 2 + 1] + xy[first * 2 + 1]) / 2;
    path.moveTo(fromX, fromY);
    var startX = 0.0;
    var startY = 0.0;
    var lined = false;
    for (var k = 0; k < n; k++) {
      final p = base + k;
      final q = k + 1 < n ? p + 1 : first;
      final px = xy[p * 2];
      final py = xy[p * 2 + 1];
      final toX = (px + xy[q * 2]) / 2;
      final toY = (py + xy[q * 2 + 1]) / 2;
      final across =
          fromY == py && py == toY && (fromX <= px ? px <= toX : px >= toX);
      final down =
          fromX == px && px == toX && (fromY <= py ? py <= toY : py >= toY);
      if (across || down) {
        final continues =
            lined &&
            (across
                ? startY == fromY && (startX <= fromX) == (fromX <= toX)
                : startX == fromX && (startY <= fromY) == (fromY <= toY));
        if (!continues) {
          if (lined) path.lineTo(fromX, fromY);
          startX = fromX;
          startY = fromY;
          lined = true;
        }
      } else {
        if (lined) {
          path.lineTo(fromX, fromY);
          lined = false;
        }
        path.quadraticBezierTo(px, py, toX, toY);
      }
      fromX = toX;
      fromY = toY;
    }
    if (lined) path.lineTo(fromX, fromY);
    path.close();
    base += n;
  }
  return path;
}

/// Marching squares over the near blocks of a trace grid, stitched by the
/// grid edges the contour crosses and smoothed into the quadratic B-spline
/// through the crossings (the limit of Chaikin's corner cutting).
///
/// A saddle cell is resolved by the mean of its corners. The buffers live
/// across calls in [_TracerBuffers]: an outline is traced on the UI
/// thread, one at a time. They retain the largest traced grid until the
/// isolate exits. This tracer follows the sampled optical field's zero
/// contour; LiquidField's tracer evaluates an analytic mass field instead.
/// The B-spline uses the same Chaikin limit without repeated point lists.
class _OutlineTracer {
  factory _OutlineTracer(int edges) {
    final buffers = _TracerBuffers.claim(edges);
    return _OutlineTracer._(
      buffers.stamp,
      buffers.slot,
      buffers.generation,
      buffers.xs,
      buffers.ys,
      buffers.links,
      buffers.seen,
    );
  }

  _OutlineTracer._(
    this._stamp,
    this._slot,
    this._generation,
    this._xs,
    this._ys,
    this._links,
    this._seen,
  );

  final Int32List _stamp;
  final Int32List _slot;
  final int _generation;
  Float64List _xs;
  Float64List _ys;
  Int32List _links;
  Uint8List _seen;
  int _count = 0;

  static (Float64List, Int32List) trace(
    Float64List values,
    int cols,
    int rows, {
    required Uint8List near,
    required int blockCols,
    required int block,
    required double left,
    required double top,
    required double step,
  }) {
    final horizontal = rows * (cols - 1);
    final tracer = _OutlineTracer(horizontal + (rows - 1) * cols);
    final blockRows = near.length ~/ blockCols;
    for (var bj = 0; bj < blockRows; bj++) {
      for (var bi = 0; bi < blockCols; bi++) {
        if (near[bj * blockCols + bi] == 0) continue;
        final jEnd = math.min(bj * block + block, rows - 1);
        final iEnd = math.min(bi * block + block, cols - 1);
        for (var j = bj * block; j < jEnd; j++) {
          final upper = j * cols;
          final lower = upper + cols;
          final y0 = top + j.toDouble() * step;
          for (var i = bi * block; i < iEnd; i++) {
            final tl = values[upper + i];
            final tr = values[upper + i + 1];
            final br = values[lower + i + 1];
            final bl = values[lower + i];
            final mask =
                (tl < 0 ? 8 : 0) |
                (tr < 0 ? 4 : 0) |
                (br < 0 ? 2 : 0) |
                (bl < 0 ? 1 : 0);
            if (mask == 0 || mask == 15) continue;
            final x0 = left + i.toDouble() * step;
            final eTop = j * (cols - 1) + i;
            final eLeft = horizontal + j * cols + i;
            final saddle = mask == 5 || mask == 10;
            final first = saddle && (tl + tr + br + bl < 0) == (mask == 5)
                ? 2
                : 0;
            final last = saddle ? first + 2 : 1;
            for (var k = first; k < last; k++) {
              final pair = saddle ? _saddlePairs[k] : _pairs[mask];
              tracer._link(
                tracer._edge(
                  pair >> 2,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
                tracer._edge(
                  pair & 3,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
              );
            }
          }
        }
      }
    }
    return tracer._stitch();
  }

  /// Per corner mask, the two crossed sides of a one-segment cell packed
  /// as `a << 2 | b` (sides: 0 top, 1 right, 2 bottom, 3 left).
  static const List<int> _pairs = [
    0,
    3 << 2 | 2,
    2 << 2 | 1,
    3 << 2 | 1,
    0 << 2 | 1,
    0,
    0 << 2 | 2,
    3 << 2 | 0,
    3 << 2 | 0,
    0 << 2 | 2,
    0,
    0 << 2 | 1,
    3 << 2 | 1,
    2 << 2 | 1,
    3 << 2 | 2,
    0,
  ];

  /// The two ways through a saddle cell: the first two pairs keep the
  /// inside corners apart, the last two join them through the center.
  static const List<int> _saddlePairs = [
    3 << 2 | 2,
    0 << 2 | 1,
    3 << 2 | 0,
    2 << 2 | 1,
  ];

  int _edge(
    int side,
    int eTop,
    int eLeft,
    int cols,
    double x0,
    double y0,
    double step,
    double tl,
    double tr,
    double br,
    double bl,
  ) => switch (side) {
    0 => _crossing(eTop, x0, y0, tl, x0 + step, y0, tr),
    1 => _crossing(eLeft + 1, x0 + step, y0, tr, x0 + step, y0 + step, br),
    2 => _crossing(
      eTop + cols - 1,
      x0,
      y0 + step,
      bl,
      x0 + step,
      y0 + step,
      br,
    ),
    _ => _crossing(eLeft, x0, y0, tl, x0, y0 + step, bl),
  };

  int _crossing(
    int edge,
    double x0,
    double y0,
    double v0,
    double x1,
    double y1,
    double v1,
  ) {
    if (_stamp[edge] == _generation) return _slot[edge];
    final slot = _count++;
    if (slot >= _xs.length) _grow();
    _stamp[edge] = _generation;
    _slot[edge] = slot;
    final denom = v0 - v1;
    var t = denom.abs() < 1e-6 ? 0.5 : v0 / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    _xs[slot] = x0 + (x1 - x0) * t;
    _ys[slot] = y0 + (y1 - y0) * t;
    _links[slot * 2] = -1;
    _links[slot * 2 + 1] = -1;
    _seen[slot] = 0;
    return slot;
  }

  void _grow() {
    _TracerBuffers.grow();
    _xs = _TracerBuffers.xs;
    _ys = _TracerBuffers.ys;
    _links = _TracerBuffers.links;
    _seen = _TracerBuffers.seen;
  }

  void _link(int a, int b) {
    if (_links[a * 2] < 0) {
      _links[a * 2] = b;
    } else {
      _links[a * 2 + 1] = b;
    }
    if (_links[b * 2] < 0) {
      _links[b * 2] = a;
    } else {
      _links[b * 2 + 1] = a;
    }
  }

  (Float64List, Int32List) _stitch() {
    final points = Float64List(_count * 2);
    final loops = <int>[];
    var written = 0;
    for (var start = 0; start < _count; start++) {
      if (_seen[start] != 0) continue;
      final from = written;
      var current = start;
      while (current >= 0 && _seen[current] == 0) {
        _seen[current] = 1;
        points[written * 2] = _xs[current];
        points[written * 2 + 1] = _ys[current];
        written++;
        final a = _links[current * 2];
        final b = _links[current * 2 + 1];
        current = a >= 0 && _seen[a] == 0
            ? a
            : b >= 0 && _seen[b] == 0
            ? b
            : -1;
      }
      if (written - from < 3) {
        written = from;
      } else {
        loops.add(written - from);
      }
    }
    return (
      Float64List.sublistView(points, 0, written * 2),
      Int32List.fromList(loops),
    );
  }
}

/// The buffers of [_OutlineTracer], kept across calls: per grid edge the
/// generation it was last crossed in and its crossing's slot, per slot
/// the crossing and its two neighbours along the contour.
abstract final class _TracerBuffers {
  static Int32List stamp = Int32List(0);
  static Int32List slot = Int32List(0);
  static int generation = 0;
  static Float64List xs = Float64List(256);
  static Float64List ys = Float64List(256);
  static Int32List links = Int32List(512);
  static Uint8List seen = Uint8List(256);

  /// Readies the buffers for a grid of [edges] edges and starts a new
  /// generation.
  static ({
    Int32List stamp,
    Int32List slot,
    int generation,
    Float64List xs,
    Float64List ys,
    Int32List links,
    Uint8List seen,
  })
  claim(int edges) {
    if (stamp.length < edges) {
      stamp = Int32List(edges + edges ~/ 2);
      slot = Int32List(stamp.length);
      generation = 0;
    }
    generation++;
    if (generation == 0x3FFFFFFF) {
      stamp.fillRange(0, stamp.length, 0);
      generation = 1;
    }
    return (
      stamp: stamp,
      slot: slot,
      generation: generation,
      xs: xs,
      ys: ys,
      links: links,
      seen: seen,
    );
  }

  /// Doubles the per-slot buffers, keeping their contents.
  static void grow() {
    final size = xs.length * 2;
    final nextXs = Float64List(size);
    nextXs.setAll(0, xs);
    xs = nextXs;
    final nextYs = Float64List(size);
    nextYs.setAll(0, ys);
    ys = nextYs;
    final nextLinks = Int32List(size * 2);
    nextLinks.setAll(0, links);
    links = nextLinks;
    final nextSeen = Uint8List(size);
    nextSeen.setAll(0, seen);
    seen = nextSeen;
  }
}

/// Within this much of the spacing the merge moves an outline by less than
/// a hundredth of a point, so surfaces whose layout lands a rounding error
/// under the spacing keep their own shapes.
final List<(List<RRect>, GlassOutline)> _recentUnions = [];

/// The merged-box outlines retained by the isolate.
const int _recentLimit = 4;

/// Moves entry [k] of [recent] to the end, as the one used last.
void _used<T>(List<T> recent, int k) {
  if (k == recent.length - 1) return;
  recent.add(recent.removeAt(k));
}

/// Adds [entry] to [recent] as the one used last, dropping the one used
/// longest ago past [_recentLimit].
void _remember<T>(List<T> recent, T entry) {
  recent.add(entry);
  if (recent.length > _recentLimit) recent.removeAt(0);
}

/// The plain union of [shapes], whose corners must share one circular
/// radius each: one closed contour per connected part, a box inside
/// another adding nothing. The latest unions are kept.
@internal
GlassOutline plainUnionOutline(List<RRect> shapes) => _plainUnion(shapes);

GlassOutline _plainUnion(List<RRect> shapes) {
  for (var k = 0; k < _recentUnions.length; k++) {
    final (recent, outline) = _recentUnions[k];
    if (listEquals(recent, shapes)) {
      _used(_recentUnions, k);
      return outline;
    }
  }
  final kept = List<RRect>.unmodifiable(shapes);
  final outline = GlassOutline(_unionPath(kept));
  _remember(_recentUnions, (kept, outline));
  return outline;
}

/// The edge of the plain union of [shapes]: one closed contour per
/// connected part, a box inside another adding nothing.
Path _unionPath(List<RRect> shapes) {
  for (final shape in shapes) {
    _requireUniform(shape);
  }
  final kept = [
    for (var i = 0; i < shapes.length; i++)
      if (!_covered(shapes, i)) shapes[i],
  ];
  var union = _rrectPath(kept.first);
  for (final shape in kept.skip(1)) {
    union = Path.combine(PathOperation.union, union, _rrectPath(shape));
  }
  return union;
}

Path _rrectPath(RRect shape) {
  final path = Path();
  path.addRRect(shape);
  return path;
}

/// Whether shape [i] of [shapes] adds nothing to their union: another
/// shape encloses it, and of two that enclose each other the first stays.
bool _covered(List<RRect> shapes, int i) {
  final shape = shapes[i];
  for (var j = 0; j < shapes.length; j++) {
    if (j == i) continue;
    final other = shapes[j];
    if (_encloses(other, shape) && (j < i || !_encloses(shape, other))) {
      return true;
    }
  }
  return false;
}

/// Whether rounded box [outer] covers rounded box [inner]: every corner
/// circle of [inner] lies inside it, and with them, [outer] being convex,
/// all of [inner].
bool _encloses(RRect outer, RRect inner) {
  final r = _radius(inner);
  final hx = inner.width / 2 - r;
  final hy = inner.height / 2 - r;
  final center = inner.center;
  _requireUniform(outer);
  final ohx = outer.width / 2;
  final ohy = outer.height / 2;
  final outerRadius = math.min(outer.tlRadiusX, math.min(ohx, ohy));
  final ocx = outer.center.dx;
  final ocy = outer.center.dy;
  for (final (sx, sy) in const [
    (-1.0, -1.0),
    (1.0, -1.0),
    (-1.0, 1.0),
    (1.0, 1.0),
  ]) {
    final qx = (center.dx + sx * hx - ocx).abs() - ohx + outerRadius;
    final qy = (center.dy + sy * hy - ocy).abs() - ohy + outerRadius;
    if (boxDistance(qx, qy, outerRadius) > -r) return false;
  }
  return true;
}

/// Normalizes the (cos, sin) pair at [at], blended from several turns.
@internal
void normalizeTurn(Float64List turn, int at) {
  final c = turn[at];
  final s = turn[at + 1];
  final length = math.sqrt(c * c + s * s);
  if (length < 1e-9) {
    turn[at] = 1;
    turn[at + 1] = 0;
  } else {
    turn[at] = c / length;
    turn[at + 1] = s / length;
  }
}

double _radius(RRect shape) {
  _requireUniform(shape);
  return math.min(shape.tlRadiusX, shape.outerRect.shortestSide / 2);
}

void _requireUniform(RRect shape) {
  assert(
    shape.tlRadiusX == shape.tlRadiusY &&
        shape.tlRadius == shape.trRadius &&
        shape.tlRadius == shape.blRadius &&
        shape.tlRadius == shape.brRadius,
    'Glass distance fields require uniform circular corner radii.',
  );
}

final List<(List<RRect>, GlassOutline)> _recentFields = [];

/// The plain union of [shapes] with its signed distance field sampled every
/// [step] points over it and a margin, for a renderer that shades the body
/// from the field: each node holds the distance to the nearest shape, its
/// gradient by central differences, turned as the renderer turns a rounded
/// box's normals near its corners ([opticalCornerScale]), and that shape's
/// half thickness. The latest fields are kept.
@internal
GlassOutline unionFieldOutline(List<RRect> shapes, {double step = 4}) {
  for (var k = 0; k < _recentFields.length; k++) {
    final (recent, outline) = _recentFields[k];
    if (listEquals(recent, shapes)) {
      _used(_recentFields, k);
      return outline;
    }
  }
  final kept = List<RRect>.unmodifiable(shapes);
  final path = _plainUnion(kept).path;
  final boxes = OutlineBoxes(kept);
  final area = path.getBounds().inflate(2 * step + 4);
  final cols = (area.width / step).ceil() + 1;
  final rows = (area.height / step).ceil() + 1;
  final distance = Float64List(cols * rows);
  final nearest = Int32List(cols * rows);
  for (var j = 0; j < rows; j++) {
    final y = area.top + j * step;
    for (var i = 0; i < cols; i++) {
      final x = area.left + i * step;
      var best = double.infinity;
      var which = 0;
      for (var b = 0; b < boxes.length; b++) {
        final d = boxes.distance(b, x, y);
        if (d < best) {
          best = d;
          which = b;
        }
      }
      distance[j * cols + i] = best;
      nearest[j * cols + i] = which;
    }
  }
  final samples = Float32List(cols * rows * 4);
  final turn = Float64List(2);
  for (var j = 0; j < rows; j++) {
    final up = j > 0 ? j - 1 : 0;
    final down = j < rows - 1 ? j + 1 : rows - 1;
    for (var i = 0; i < cols; i++) {
      final back = i > 0 ? i - 1 : 0;
      final ahead = i < cols - 1 ? i + 1 : cols - 1;
      final at = j * cols + i;
      var gx =
          (distance[j * cols + ahead] - distance[j * cols + back]) /
          ((ahead - back) * step);
      var gy =
          (distance[down * cols + i] - distance[up * cols + i]) /
          ((down - up) * step);
      final which = nearest[at];
      final x = area.left + i * step;
      final y = area.top + j * step;
      if (boxes.inOpticalCorner(which, x, y)) {
        boxes.opticalTurn(which, x, y, turn, 0);
        final tx = gx * turn[0] - gy * turn[1];
        gy = gx * turn[1] + gy * turn[0];
        gx = tx;
      }
      final out = at * 4;
      samples[out] = distance[at];
      samples[out + 1] = gx;
      samples[out + 2] = gy;
      samples[out + 3] = boxes.halfMinor(which);
    }
  }
  final outline = GlassOutline(
    path,
    field: LiquidGlassField(
      samples: samples,
      cols: cols,
      rows: rows,
      origin: area.topLeft,
      step: step,
    ),
  );
  _remember(_recentFields, (kept, outline));
  return outline;
}
