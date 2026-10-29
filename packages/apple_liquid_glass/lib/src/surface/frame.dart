import 'package:apple_liquid_glass/src/motion/touch_glow.dart';
import 'package:apple_liquid_glass/src/surface/outline.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// One frame of one glass surface: where its body is drawn, how far it is
/// lifted, the tint it turns to and how a touch lights it.
///
/// A frame is what a control's motion produces; how the body looks at that
/// lift and tint (its optics, frost, fill and shadows) is the renderer's.
/// Renderers apply [rect], [scaleX] and [scaleY] at paint, so a frame never
/// lays anything out, and the surface's content moves and scales with the
/// body.
@immutable
final class GlassFrame {
  /// Creates a frame of a body of [shape].
  const GlassFrame({
    this.shape = capsule,
    this.rect,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tint,
    this.lift = 0,
    this.glow,
    this.opacity = 1,
    this.outline,
  }) : assert(
         outline == null || (rect == null && scaleX == 1 && scaleY == 1),
         'An outline body is drawn where its path is.',
       );

  /// A capsule in any box: renderers clamp a corner radius to half the
  /// short side of the box they draw in, as Flutter's rounded borders do.
  static const LiquidShape capsule = LiquidRoundedSuperellipse(
    borderRadius: 10000,
  );

  /// The outline of the body.
  final LiquidShape shape;

  /// Where the body is drawn in the box the surface was laid out in, or
  /// null to fill that box. Hit testing keeps that box, as UIKit hit-tests
  /// a view's model rather than its presentation.
  final Rect? rect;

  /// The horizontal scale of the body and its content about the center of
  /// [rect].
  final double scaleX;

  /// The vertical scale of the body and its content about the center of
  /// [rect].
  final double scaleY;

  /// A color, already resolved for the context, that the body draws in
  /// place of its glass's tint in this frame, or null to keep it: a
  /// switch's track turning on.
  final Color? tint;

  /// How far a lens or knob is lifted, 0 resting and 1 lifted: a resting
  /// one is an opaque platter, a lifted one clear glass. Other roles ignore
  /// it.
  final double lift;

  /// The glow a finger raises on the body, in the surface's coordinates,
  /// or null for none.
  final GlassTouchGlow? glow;

  /// How present the body and its content are, 0 gone to 1 fully there:
  /// a body appearing or leaving in place fades its glass, refraction and
  /// lighting included, with its content.
  final double opacity;

  /// The body's own edge when [shape] does not describe it, or null to
  /// draw [shape]. With an outline, [shape] still rounds the corners of
  /// the box the outline spans for what a renderer cannot draw from the
  /// outline, and [rect], [scaleX] and [scaleY] keep their defaults.
  final GlassOutline? outline;

  /// Where the body is drawn in a box of [size]: [rect], scaled about its
  /// center.
  Rect drawnIn(Size size) {
    final rect = this.rect ?? Offset.zero & size;
    if (scaleX == 1 && scaleY == 1) return rect;
    return Rect.fromCenter(
      center: rect.center,
      width: rect.width * scaleX,
      height: rect.height * scaleY,
    );
  }

  /// The transform that draws content laid out in a box of [size] where
  /// this frame draws the body, or null when it draws it in place.
  Matrix4? contentTransformIn(Size size) {
    final rect = this.rect;
    if ((rect == null || rect == Offset.zero & size) &&
        scaleX == 1 &&
        scaleY == 1) {
      return null;
    }
    final to = (rect ?? Offset.zero & size).center;
    final from = size.center(Offset.zero);
    final transform = Matrix4.translationValues(to.dx, to.dy, 0);
    transform.scaleByDouble(scaleX, scaleY, 1, 1);
    transform.translateByDouble(-from.dx, -from.dy, 0, 1);
    return transform;
  }

  @override
  bool operator ==(Object other) =>
      other is GlassFrame &&
      other.shape == shape &&
      other.rect == rect &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.tint == tint &&
      other.lift == lift &&
      other.glow == glow &&
      other.opacity == opacity &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(
    shape,
    rect,
    scaleX,
    scaleY,
    tint,
    lift,
    glow,
    opacity,
    outline,
  );
}
