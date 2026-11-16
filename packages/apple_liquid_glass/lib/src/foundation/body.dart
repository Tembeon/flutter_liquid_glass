import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/outline.dart';
import 'package:apple_liquid_glass/src/foundation/shape.dart';
import 'package:flutter/widgets.dart';

/// Where a frame draws its body in the box its surface was laid out in: the
/// one rule every renderer and overlay of a surface follows.
///
/// The body is the frame's rect (the box where it names none, the outline's
/// bounds for an outline), scaled about its center. What is drawn on the
/// body (its fill, rim, ring, clip and glow) is drawn in the body's own
/// coordinates, its top left at zero and its size [size], under [toBox], so
/// it follows the liquid glass edge: corners scale with the body, as a
/// layer's transform scales a view in UIKit. The surface's content keeps the
/// box's size and is drawn centered on the body ([contentToBox]).
@immutable
final class GlassBody {
  /// The body [frame] draws in a box of [box].
  factory GlassBody.of(GlassFrame frame, Size box) {
    final outline = frame.outline;
    return GlassBody._(
      box: box,
      rect: frame.bodyRect ?? Offset.zero & box,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
      shape: frame.shape,
      outline: outline,
    );
  }

  const GlassBody._({
    required this.box,
    required this.rect,
    required this.scaleX,
    required this.scaleY,
    required this.shape,
    required this.outline,
  });

  /// The size of the box the surface was laid out in.
  final Size box;

  /// The body before its scale, in the box's coordinates.
  final Rect rect;

  /// The body's horizontal scale about its center.
  final double scaleX;

  /// The body's vertical scale about its center.
  final double scaleY;

  /// The body's shape.
  final GlassShape shape;

  /// The body's own edge, in the box's coordinates, or null to draw
  /// [shape].
  final GlassOutline? outline;

  /// The body's size in its own coordinates.
  Size get size => rect.size;

  /// The body in its own coordinates.
  Rect get bounds => Offset.zero & size;

  /// The radius of the body's corners in its own coordinates.
  double get radius => shape.radiusIn(bounds);

  /// The radius of the body's corners as seen in the box: [radius] scaled
  /// with the body, by the lesser of its scales where they differ.
  double get drawnRadius => radius * (scaleX < scaleY ? scaleX : scaleY).abs();

  /// The body's edge in its own coordinates.
  Path get edge => switch (outline) {
    final outline? => outline.path.shift(-rect.topLeft),
    null => shape.pathIn(bounds),
  };

  /// The body's edge as drawn in the box.
  Path get edgeInBox {
    if (outline case final outline?) return outline.path;
    final toBox = this.toBox;
    return toBox == null ? edge : edge.transform(toBox.storage);
  }

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

  // Where content laid out at the box's size lies in the body's
  // coordinates: centered on the body.
  Offset get _contentOffset => Offset(
    (rect.width - box.width) / 2,
    (rect.height - box.height) / 2,
  );

  /// From the coordinates the content was laid out in to the box's, or null
  /// where the content is drawn in place.
  Matrix4? get contentToBox {
    final toBox = this.toBox;
    final shift = _contentOffset;
    if (toBox == null) {
      return shift == Offset.zero
          ? null
          : Matrix4.translationValues(shift.dx, shift.dy, 0);
    }
    return toBox..translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  /// Runs [paint] with [canvas] in the body's coordinates, the box's top
  /// left at [offset].
  void paintIn(Canvas canvas, Offset offset, void Function(Canvas) paint) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (toBox case final toBox?) canvas.transform(toBox.storage);
    paint(canvas);
    canvas.restore();
  }
}
