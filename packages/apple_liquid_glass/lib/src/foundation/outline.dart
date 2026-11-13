import 'dart:typed_data';

import 'package:apple_liquid_glass/src/foundation/shape.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The outline of a glass body that no [GlassShape] describes, such as a
/// popover and its arrow as one shape.
///
/// [path] is the body's edge in the coordinates of the box its surface
/// was laid out in: the flat renderer fills it and clips the content to
/// it. [field] is the body's signed distance field in the same
/// coordinates, from which the liquid renderer shades the body as one
/// glass, edge light and refraction included, when the surface has a
/// layer of its own; without a field, on fake glass and in a shared group
/// the liquid renderer draws the body flat.
///
/// The field is computed the first time a renderer reads it, so a
/// renderer that only fills the body never pays for it.
final class GlassOutline {
  /// Creates the outline whose edge is [path] and whose field, if any,
  /// [field] computes when first read.
  GlassOutline(this.path, {GlassField? Function()? field}) : _fieldOf = field;

  /// The edge of the body.
  final Path path;

  final GlassField? Function()? _fieldOf;

  /// Whether the body has a [field] to shade it from.
  @internal
  bool get hasField => _fieldOf != null;

  /// The body's signed distance field, or null.
  late final GlassField? field = _fieldOf?.call();

  /// The box the body occupies.
  Rect get bounds => path.getBounds();
}

/// The signed distance field of a body's edge, sampled on a grid: four
/// values per node, row-major, the distance (negative inside), its
/// gradient along x and y, and the half thickness of the body there.
@immutable
final class GlassField {
  /// Creates a field from its samples.
  const GlassField({
    required this.samples,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.step,
  });

  /// Four values per node, row-major: at least `cols * rows * 4`.
  final Float32List samples;

  /// The number of nodes along x.
  final int cols;

  /// The number of nodes along y.
  final int rows;

  /// The position of node (0, 0) in the coordinates of the body's box.
  final Offset origin;

  /// The distance between neighbouring nodes, in logical pixels.
  final double step;
}
