import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/outline.dart';
import 'package:apple_liquid_glass/src/foundation/shape.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Where a frame draws its body in the box its surface was laid out in, as
/// live glass draws it ([LiquidGlassBody]), and the shape it draws there.
///
/// What is drawn on the body (its fill, rim, ring, clip and glow) is drawn
/// in the body's own coordinates under [toBox] ([paintIn]).
@immutable
final class GlassBody extends LiquidGlassBody {
  /// The body [frame] draws in a box of [box].
  factory GlassBody.of(GlassFrame frame, Size box) => GlassBody._(
    box,
    rect: frame.bodyRect,
    scaleX: frame.scaleX,
    scaleY: frame.scaleY,
    shape: frame.shape,
    outline: frame.outline,
  );

  const GlassBody._(
    super.box, {
    required super.rect,
    required super.scaleX,
    required super.scaleY,
    required this.shape,
    required this.outline,
  });

  /// The body's shape.
  final GlassShape shape;

  /// The body's own edge, in the box's coordinates, or null to draw
  /// [shape].
  final GlassOutline? outline;

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
