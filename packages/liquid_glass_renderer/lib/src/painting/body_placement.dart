import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shape_frame.dart';
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Where a live glass draws its body in the box it was laid out in: the one
/// rule its paint size, its move and scale and its child's place follow.
///
/// The body is the frame's rect, or the box where it names none, scaled by
/// [scaleX] and [scaleY] about its center. The glass and what is drawn with
/// it are drawn in the body's own coordinates, its top left at zero and its
/// size [size], under [toBox]: corners and glow scale with the body, as a
/// layer's transform scales a view in UIKit. The child keeps the box's size
/// and is drawn centered on the body.
@internal
@immutable
final class BodyPlacement {
  /// The body [frame] draws in a box of [box], or the box itself without a
  /// frame.
  BodyPlacement(LiquidGlassShapeFrame? frame, this.box)
    : rect = frame?.rect ?? Offset.zero & box,
      scaleX = frame?.scaleX ?? 1,
      scaleY = frame?.scaleY ?? 1;

  /// The size of the box the glass was laid out in.
  final Size box;

  /// The body before its scale, in the box's coordinates.
  final Rect rect;

  /// The body's horizontal scale about its center.
  final double scaleX;

  /// The body's vertical scale about its center.
  final double scaleY;

  /// The size the glass paints at, in the body's own coordinates.
  Size get size => rect.size;

  /// Where the body is seen in the box: [rect] scaled about its center.
  Rect get drawn => scaleX == 1 && scaleY == 1
      ? rect
      : Rect.fromCenter(
          center: rect.center,
          width: rect.width * scaleX,
          height: rect.height * scaleY,
        );

  /// From the body's coordinates to the box's, or null where they are the
  /// same.
  Matrix4? get toBox {
    if (rect.topLeft == Offset.zero && scaleX == 1 && scaleY == 1) {
      return null;
    }
    final center = rect.center;
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scaleX, scaleY, 1, 1)
      ..translateByDouble(
        rect.left - center.dx,
        rect.top - center.dy,
        0,
        1,
      );
  }

  /// Where the child, laid out at the box's size, lies in the body's
  /// coordinates: centered on the body.
  Offset get childOffset => Offset(
    (rect.width - box.width) / 2,
    (rect.height - box.height) / 2,
  );
}
