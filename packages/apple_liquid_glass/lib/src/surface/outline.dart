import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// The outline of a glass body that no [LiquidShape] describes, such as a
/// popover and its arrow as one shape.
///
/// [path] is the body's edge in the coordinates of the box its surface
/// was laid out in: the flat renderer fills it and clips the content to
/// it. [field] is the body's signed distance field in the same
/// coordinates, from which the liquid renderer shades the body as one
/// glass, edge light and refraction included, when the surface has a
/// layer of its own; without a field, on fake glass and in a shared group
/// the liquid renderer draws the body flat.
@immutable
final class GlassOutline {
  /// Creates the outline whose edge is [path].
  const GlassOutline(this.path, {this.field});

  /// The edge of the body.
  final Path path;

  /// The body's signed distance field, or null.
  final LiquidGlassField? field;

  /// The box the body occupies.
  Rect get bounds => path.getBounds();

  /// Outlines are equal when they share one path and an equal field.
  @override
  bool operator ==(Object other) =>
      other is GlassOutline &&
      identical(other.path, path) &&
      other.field == field;

  @override
  int get hashCode => Object.hash(identityHashCode(path), field);
}
