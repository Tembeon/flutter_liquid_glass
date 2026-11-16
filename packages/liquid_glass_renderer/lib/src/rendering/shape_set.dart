import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';

/// Half-extents along the matte axes of a shape with local half-size
/// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
/// shader culls with these boxes instead of mapping every pixel into each
/// shape's local space. Ellipses and rounded rectangles are exact;
/// continuous corners extend further into the corner than a circular arc of
/// the same radius, so they use their box.
Size _matteHalfExtents(
  RawShapeType type,
  Size halfSize,
  double cornerRadius,
  Offset axisX,
  Offset axisY,
) {
  double extent(double x, double y) {
    switch (type) {
      case RawShapeType.ellipse:
        return sqrt(pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2));
      case RawShapeType.roundedRectangle:
        final radius = min(cornerRadius, halfSize.shortestSide);
        return x.abs() * (halfSize.width - radius) +
            y.abs() * (halfSize.height - radius) +
            radius * sqrt(x * x + y * y);
      case RawShapeType.squircle:
      case RawShapeType.squirclePair:
        return x.abs() * halfSize.width + y.abs() * halfSize.height;
    }
  }

  return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
}

/// A layer's drawable shapes as the geometry shaders read them, in device
/// pixels of its matte.
///
/// Each encode makes a new set, so a set is the same object exactly while
/// its shapes are.
@internal
@immutable
final class ShapeSet {
  const ShapeSet._({
    required this.shapes,
    required this.superellipses,
    required this.superellipsesLower,
    required this.boxes,
    required this.turns,
    required this.appearances,
  });

  ShapeSet._unmodifiable({
    required List<double> shapes,
    required List<double> superellipses,
    required List<double> superellipsesLower,
    required List<double> boxes,
    required List<double> turns,
    required List<LiquidGlassAppearance> appearances,
  }) : this._(
         shapes: List.unmodifiable(shapes),
         superellipses: List.unmodifiable(superellipses),
         superellipsesLower: List.unmodifiable(superellipsesLower),
         boxes: List.unmodifiable(boxes),
         turns: List.unmodifiable(turns),
         appearances: List.unmodifiable(appearances),
       );

  /// The [drawn] shapes of a frame, in their order; the first shape of each
  /// geometry carries a negative blend marker, which starts a group, so
  /// shapes blend smoothly within their geometry and never with unrelated
  /// glass.
  ///
  /// With [turnsToCenter] the shapes of a group whose largest is more than
  /// [centerTurnShortSide] across turn their optical normals by
  /// [centerTurn], as iOS 27 regular glass does.
  factory ShapeSet.encode(
    List<FrameShape> drawn, {
    required double devicePixelRatio,
    bool turnsToCenter = false,
  }) {
    final dpr = devicePixelRatio;
    final shapes = <double>[];
    final superellipses = <double>[];
    final superellipsesLower = <double>[];
    final boxes = <double>[];
    final turns = <double>[];
    final appearances = <LiquidGlassAppearance>[];

    var groupStart = 0;
    var largestArea = 0.0;
    var largestShortSide = 0.0;
    void endGroup() {
      final turn = turnsToCenter && largestShortSide > centerTurnShortSide
          ? centerTurn
          : 0.0;
      for (var i = groupStart; i < appearances.length; i++) {
        turns.add(turn);
      }
      groupStart = appearances.length;
      largestArea = 0;
      largestShortSide = 0;
    }

    for (final (index, frameShape) in drawn.indexed) {
      final firstInGroup =
          index == 0 ||
          !identical(drawn[index - 1].geometry, frameShape.geometry);
      if (firstInGroup) endGroup();
      final FrameShape(:shape, :geometry, :basis) = frameShape;
      final (:axisX, :axisY, :determinant) = basis;

      // Inverse 2D affine basis maps matte-space physical pixels back to
      // the shape's own physical-pixel coordinate system.
      final inverse00 = axisY.dy / determinant;
      final inverse01 = -axisY.dx / determinant;
      final inverse10 = -axisX.dy / determinant;
      final inverse11 = axisX.dx / determinant;

      // The minimum singular value conservatively converts local SDF
      // distances back to screen pixels under non-uniform scaling.
      final distanceScale = leastSingularValue(
        axisX.dx,
        axisY.dx,
        axisX.dy,
        axisY.dy,
      );

      final size = shape.renderObject.paintSize;
      final centerInMatte = MatrixUtils.transformPoint(
        frameShape.toLayer,
        size.center(Offset.zero),
      );

      // The inverse affine basis above already maps matte coordinates back
      // into the shape's local coordinate system. Using the transformed
      // AABB here would apply scale a second time (and turn rotations into
      // oversized primitives), which is especially visible for stretched
      // shapes in a blend group.
      final pair = shape.encodedShapeType == RawShapeType.squirclePair;
      if (pair) {
        final halves = roundedSuperellipsePairParameters(
          size,
          shape.encodedCornerRadius,
          shape.encodedBottomRadius,
          scale: dpr,
        );
        superellipses.addAll(halves.top.floats);
        superellipsesLower.addAll(halves.geometryBottomFloats);
      } else {
        superellipses.addAll(
          roundedSuperellipseParameters(
            size,
            shape.encodedCornerRadius,
            scale: dpr,
          ).floats,
        );
        superellipsesLower.addAll(List<double>.filled(_squircleFloats, 0));
      }
      final center = centerInMatte * dpr;
      // Every shader clamps a corner to half the short side already;
      // a clamped radius also lets the tiler's depth bound hold for a
      // capsule written with an oversized radius. A pair is fitted on
      // its own.
      final cornerRadius = pair
          ? shape.encodedCornerRadius
          : min(shape.encodedCornerRadius, size.shortestSide / 2);
      final halfExtents = _matteHalfExtents(
        shape.encodedShapeType,
        size * dpr / 2,
        cornerRadius * dpr,
        axisX,
        axisY,
      );
      boxes.addAll([
        center.dx - halfExtents.width,
        center.dy - halfExtents.height,
        center.dx + halfExtents.width,
        center.dy + halfExtents.height,
      ]);
      final blendMarker = firstInGroup
          ? -(geometry.blend * dpr + 1)
          : geometry.blend * dpr;

      shapes.addAll(
        laneRow(ShapeLane.values, {
          ShapeLane.type: shape.encodedShapeType.shaderIndex,
          ShapeLane.width: size.width * dpr,
          ShapeLane.height: size.height * dpr,
          ShapeLane.radius: cornerRadius * dpr,
          ShapeLane.inverseXX: inverse00,
          ShapeLane.inverseXY: inverse01,
          ShapeLane.inverseYX: inverse10,
          ShapeLane.inverseYY: inverse11,
          ShapeLane.centerX: center.dx,
          ShapeLane.centerY: center.dy,
          ShapeLane.distanceScale: distanceScale,
          ShapeLane.blendMarker: blendMarker,
        }),
      );
      appearances.add(shape.appearance);
      final area = size.width * size.height * distanceScale * distanceScale;
      if (area > largestArea) {
        largestArea = area;
        largestShortSide = size.shortestSide * distanceScale;
      }
    }
    endGroup();
    return ShapeSet._unmodifiable(
      shapes: shapes,
      superellipses: superellipses,
      superellipsesLower: superellipsesLower,
      boxes: boxes,
      turns: turns,
      appearances: appearances,
    );
  }

  /// The shapes of [sets] in one, each moved by its offset in device pixels
  /// of the matte.
  factory ShapeSet.join(List<(ShapeSet, Offset)> sets) {
    final shapes = <double>[];
    final superellipses = <double>[];
    final superellipsesLower = <double>[];
    final boxes = <double>[];
    final turns = <double>[];
    final appearances = <LiquidGlassAppearance>[];
    for (final (set, by) in sets) {
      final from = shapes.length;
      shapes.addAll(set.shapes);
      for (var i = from; i < shapes.length; i += _shapeFloats) {
        shapes[i + ShapeLane.centerX.index] += by.dx;
        shapes[i + ShapeLane.centerY.index] += by.dy;
      }
      final box = boxes.length;
      boxes.addAll(set.boxes);
      for (var i = box; i < boxes.length; i += 2) {
        boxes[i] += by.dx;
        boxes[i + 1] += by.dy;
      }
      superellipses.addAll(set.superellipses);
      superellipsesLower.addAll(set.superellipsesLower);
      turns.addAll(set.turns);
      appearances.addAll(set.appearances);
    }
    return ShapeSet._unmodifiable(
      shapes: shapes,
      superellipses: superellipses,
      superellipsesLower: superellipsesLower,
      boxes: boxes,
      turns: turns,
      appearances: appearances,
    );
  }

  /// Shapes already in the shaders' layout, each with the default
  /// appearance.
  factory ShapeSet.rows({
    required List<double> shapes,
    required List<double> boxes,
    List<double>? superellipses,
    List<double>? superellipsesLower,
  }) {
    final count = shapes.length ~/ _shapeFloats;
    return ShapeSet._(
      shapes: List.unmodifiable(shapes),
      superellipses: List.unmodifiable(
        superellipses ?? List<double>.filled(count * _squircleFloats, 0),
      ),
      superellipsesLower: List.unmodifiable(
        superellipsesLower ?? List<double>.filled(count * _squircleFloats, 0),
      ),
      boxes: List.unmodifiable(boxes),
      turns: List.filled(count, 0),
      appearances: List.filled(count, const LiquidGlassAppearance()),
    );
  }

  /// No shapes.
  static const empty = ShapeSet._(
    shapes: [],
    superellipses: [],
    superellipsesLower: [],
    boxes: [],
    turns: [],
    appearances: [],
  );

  /// How far iOS 27 turns the optical normal of large regular glass from
  /// its edge's to the line from its center, the two mixed and made a unit
  /// again. Read from UIKit on iOS 27.
  static const double centerTurn = 0.5;

  /// The short side, in logical pixels, past which iOS 27 regular glass
  /// turns its normals by [centerTurn]; glass no larger keeps its edge's.
  static const double centerTurnShortSide = 64;

  static final int _shapeFloats = ShapeLane.values.length;
  static final int _squircleFloats = SquircleLane.values.length;

  /// A row of [ShapeLane]s a shape.
  final List<double> shapes;

  /// A row of [SquircleLane]s a shape: its superellipse, or a pair's top
  /// half.
  final List<double> superellipses;

  /// A row of [SquircleLane]s a shape: a pair's bottom half, zeros for every
  /// other shape.
  final List<double> superellipsesLower;

  double _lane(int shape, ShapeLane lane) =>
      shapes[shape * _shapeFloats + lane.index];

  /// 4 floats a shape: its box in the matte.
  final List<double> boxes;

  /// A float a shape: how far its optical normal turns to the line from its
  /// center, [centerTurn] or 0. The shapes of a blend group turn alike, by
  /// the size of the largest of them, as the elements of an iOS 27
  /// container do.
  final List<double> turns;

  /// Each shape's appearance.
  final List<LiquidGlassAppearance> appearances;

  /// How many shapes the set has.
  int get count => appearances.length;

  /// Whether any shape turns its normal ([turns]).
  bool get leans => turns.any((turn) => turn > 0);

  /// Half the short side that sizes the lens of shape [index], in device
  /// pixels of the matte: the smallest of the shapes of its blend group.
  ///
  /// iOS 27 gives the glass of a container one lens, sized by its smallest
  /// element: a large shape that merges with a small one bends the backdrop
  /// no further than the small one does, all around its rim.
  double lensOf(int index) {
    var first = index;
    while (first > 0 && _lane(first, ShapeLane.blendMarker) >= 0) {
      first--;
    }
    var least = double.infinity;
    for (var i = first; i < count; i++) {
      if (i > first && _lane(i, ShapeLane.blendMarker) < 0) break;
      final half =
          min(_lane(i, ShapeLane.width), _lane(i, ShapeLane.height)) /
          2 *
          _lane(i, ShapeLane.distanceScale);
      if (half < least) least = half;
    }
    return least;
  }

  /// The first [most] shapes.
  ShapeSet take(int most) => count <= most
      ? this
      : ShapeSet._(
          shapes: shapes.sublist(0, most * _shapeFloats),
          superellipses: superellipses.sublist(0, most * _squircleFloats),
          superellipsesLower: superellipsesLower.sublist(
            0,
            most * _squircleFloats,
          ),
          boxes: boxes.sublist(0, most * 4),
          turns: turns.sublist(0, most),
          appearances: appearances.sublist(0, most),
        );
}

/// The smaller singular value of the 2 x 2 matrix `[[xx, xy], [yx, yy]]`:
/// the least a unit distance can shrink to under it.
double leastSingularValue(double xx, double xy, double yx, double yy) {
  final determinant = xx * yy - xy * yx;
  final trace = xx * xx + xy * xy + yx * yx + yy * yy;
  final spread = sqrt(max(0, trace * trace - 4 * determinant * determinant));
  return sqrt(max(0, (trace - spread) / 2));
}
