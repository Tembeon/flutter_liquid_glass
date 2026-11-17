import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';

/// Paints a `GlassShadow`.
class RenderGlassShadow extends RenderProxyBox with LivePaintSize {
  /// Creates the render object of a `GlassShadow`.
  RenderGlassShadow({
    required this._shape,
    required this._shadows,
    required double visibility,
    required this._devicePixelRatio,
  }) : _visibility = visibility.clamp(0, 1);

  /// The shape whose shadows it paints.
  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  /// The shadows it paints around [shape].
  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  /// The pixel ratio its shadow layer's bounds are kept on stable buckets for.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How far the shape has materialized, which fades the shadows.
  double get visibility => _visibility;
  double _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  Rect get paintBounds {
    final bounds = super.paintBounds;
    if (visibility <= 0 || shadows.isEmpty) return bounds;
    return bounds.expandToInclude(
      glassShadowBounds(
        Offset.zero & paintSize,
        LiquidGlassShadow.resolve(shadows, paintSize),
        visibility,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintLoneGlassShadows(
      context.canvas,
      LiquidGlassSilhouette.shape(shape, offset & paintSize),
      LiquidGlassShadow.resolve(shadows, paintSize),
      visibility: visibility,
      layerBounds: ViewPixels(devicePixelRatio).bucket,
    );
    super.paint(context, offset);
  }
}
