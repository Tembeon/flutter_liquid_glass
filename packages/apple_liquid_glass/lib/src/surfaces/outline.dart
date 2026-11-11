import 'package:apple_liquid_glass/src/surfaces/shape.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
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
  GlassOutline(this.path, {@internal LiquidGlassField? Function()? field})
    : _fieldOf = field;

  /// The edge of the body.
  final Path path;

  final LiquidGlassField? Function()? _fieldOf;

  /// Whether the body has a [field] to shade it from.
  @internal
  bool get hasField => _fieldOf != null;

  /// The body's signed distance field, or null.
  @internal
  late final LiquidGlassField? field = _fieldOf?.call();

  /// The box the body occupies.
  Rect get bounds => path.getBounds();
}

/// What lies in [box] and outside [body], to clip a shadow to.
///
/// An outline traced from a field is one even-odd path, so adding its loops
/// to the box under the same rule leaves the box less the body with nothing
/// worked out: a menu's outline changes every frame it opens, and
/// subtracting it took a Pixel 6a's UI thread 0.28 ms each. Any other path
/// is subtracted.
@internal
Path pathOutside(Path body, Rect box) {
  final whole = Path();
  whole.addRect(box);
  if (body.fillType != PathFillType.evenOdd) {
    return Path.combine(PathOperation.difference, whole, body);
  }
  whole.fillType = PathFillType.evenOdd;
  whole.addPath(body, Offset.zero);
  return whole;
}
