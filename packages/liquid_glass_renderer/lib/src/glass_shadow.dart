import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/internal/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';

/// Conservative pixel support of Flutter's Gaussian shadow mask.
///
/// [BoxShadow.blurRadius] is converted to sigma before rasterization. Reserving
/// only the radius clips the low-energy tail, especially when the shadow is
/// painted into a bounded saveLayer before translucent glass.
@internal
double glassShadowBlurSupport(double blurRadius) =>
    Shadow.convertRadiusToSigma(blurRadius) * 3;

/// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
/// (drawRRect, drawCircle, drawRSuperellipse, etc.) instead of drawPath.
///
/// This avoids the cost of rasterizing an arbitrary [Path] with a blur
/// [MaskFilter], which is significantly slower than the dedicated GPU-
/// accelerated primitives that Impeller/Skia provide for simple shapes.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows], and
  /// optional [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    this.appearanceVisibility = 1,
    this.devicePixelRatio = 1,
    this.live,
    super.child,
    super.key,
  });

  /// The shape to paint shadows for.
  final LiquidShape shape;

  /// Per-shape materialization progress.
  final double appearanceVisibility;

  /// Pixel ratio the shadow layer's bounds are kept on stable buckets for.
  final double devicePixelRatio;

  /// The live frame whose rect sizes the shape at paint.
  final ValueListenable<LiquidGlassShapeFrame>? live;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderGlassShadow(
      shape: shape,
      shadows: shadows,
      visibility: appearanceVisibility,
      devicePixelRatio: devicePixelRatio,
    )..live = live;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassShadow renderObject,
  ) {
    renderObject
      ..shape = shape
      ..shadows = shadows
      ..visibility = appearanceVisibility
      ..devicePixelRatio = devicePixelRatio
      ..live = live;
  }
}

/// Paints a [GlassShadow].
@internal
class RenderGlassShadow extends RenderProxyBox with LivePaintSize {
  /// Creates the render object of a [GlassShadow].
  RenderGlassShadow({
    required this._shape,
    required this._shadows,
    required double visibility,
    required this._devicePixelRatio,
  }) : _visibility = visibility.clamp(0, 1);

  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  double get visibility => _visibility;
  double _visibility = 1;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  Rect get paintBounds {
    var bounds = super.paintBounds;
    if (visibility <= 0 || shadows.isEmpty) return bounds;

    final shapeBounds = Offset.zero & paintSize;
    for (final shadow in shadows) {
      // Report the same conservative Gaussian support used by paint()'s
      // saveLayer. Without this, Flutter culls the blurred pixels outside the
      // render box and different blur radii collapse to the same hard ring.
      final extent = math
          .max(
            shadow.spreadRadius +
                glassShadowBlurSupport(
                  shadow.blurRadius * visibility,
                ),
            0,
          )
          .toDouble();
      bounds = bounds.expandToInclude(
        shapeBounds.shift(shadow.offset).inflate(extent),
      );
    }
    return bounds;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (shadows.isNotEmpty) {
      final rect = offset & paintSize;
      final canvas = context.canvas;

      final needsCutout = shadows.any((s) => s.offset != Offset.zero);

      if (needsCutout) {
        var layerBounds = rect;
        for (final shadow in shadows) {
          layerBounds = layerBounds.expandToInclude(
            rect
                .shift(shadow.offset)
                .inflate(
                  shadow.spreadRadius +
                      glassShadowBlurSupport(
                        shadow.blurRadius * visibility,
                      ),
                ),
          );
        }
        // Bounds only, so growing them to pixel buckets changes no pixel, but
        // an animated shape no longer gets a new render target size per frame.
        canvas.saveLayer(
          layerBounds.expandToPixelBuckets(devicePixelRatio),
          Paint(),
        );
      }

      for (final shadow in shadows) {
        final shadowRect = rect
            .shift(shadow.offset)
            .inflate(shadow.spreadRadius);
        final paint = shadow
            .copyWith(
              blurRadius: shadow.blurRadius * visibility,
              blurStyle: needsCutout ? BlurStyle.normal : BlurStyle.outer,
              color: shadow.color.withValues(
                alpha: shadow.color.a * visibility,
              ),
            )
            .toPaint();

        drawGlassShape(canvas, shape, shadowRect, paint);
      }

      if (needsCutout) {
        drawGlassShape(
          canvas,
          shape,
          rect.deflate(.5),
          Paint()..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
      }
    }

    super.paint(context, offset);
  }
}

@internal
void drawGlassShape(Canvas canvas, LiquidShape shape, Rect rect, Paint paint) {
  final radius = Radius.circular(shape.cornerRadius);
  switch (shape) {
    case LiquidRoundedSuperellipse(:final radii):
      canvas.drawRSuperellipse(radii.toRSuperellipse(rect), paint);
    case LiquidOval():
      canvas.drawOval(rect, paint);
    case LiquidRoundedRectangle():
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
  }
}
