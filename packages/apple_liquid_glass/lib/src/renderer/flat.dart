import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The flat renderer: a fill per role and glass, a hairline rim on all but
/// an untinted track, a soft shadow under floating roles; no backdrop
/// reads, no glow.
///
/// The fills, rims and shadow are Morph's flat glass button and the track
/// fill iOS systemFill: an approximation of the glass's average look, not
/// a measurement.
@internal
final class FlatGlassRenderer extends GlassRenderer {
  /// Creates the flat renderer.
  const FlatGlassRenderer();

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      _FlatSurface(
        frame: details.frame,
        look: FlatGlassLook.of(
          details.role,
          details.glass,
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
        ),
        child: details.child,
      );

  @override
  bool operator ==(Object other) => other is FlatGlassRenderer;

  @override
  int get hashCode => (FlatGlassRenderer).hashCode;
}

/// How the flat renderer paints one surface.
@internal
@immutable
final class FlatGlassLook {
  /// Creates a look.
  const FlatGlassLook({required this.fill, this.rim, this.shadow});

  /// The look of a surface of [role] made of [glass] in [brightness].
  factory FlatGlassLook.of(GlassRole role, Glass glass, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tint = glass.tint;
    final floating = switch (role) {
      GlassRole.control ||
      GlassRole.lens ||
      GlassRole.knob ||
      GlassRole.menu ||
      GlassRole.sheet => true,
      GlassRole.bar || GlassRole.track => false,
    };
    if (role == GlassRole.track && tint == null) {
      return FlatGlassLook(fill: dark ? _darkTrack : _lightTrack);
    }
    return FlatGlassLook(
      fill:
          tint ??
          (glass.isClear
              ? (dark ? _darkClear : _lightClear)
              : (dark ? _darkFill : _lightFill)),
      rim: tint != null ? _tintedRim : (dark ? _darkRim : _lightRim),
      shadow: floating ? (dark ? _darkShadow : _lightShadow) : null,
    );
  }

  static const _lightFill = Color(0xD9FFFFFF);
  static const _darkFill = Color(0xB82C2C2E);
  static const _lightClear = Color(0x40FFFFFF);
  static const _darkClear = Color(0x402C2C2E);
  static const _lightRim = Color(0x1F000000);
  static const _darkRim = Color(0x33FFFFFF);
  static const _tintedRim = Color(0x33FFFFFF);

  // iOS systemFill, light and dark.
  static const _lightTrack = Color(0x33787880);
  static const _darkTrack = Color(0x5C787880);
  static const _lightShadow = Color(0x1A000000);
  static const _darkShadow = Color(0x40000000);

  /// The fill of the body.
  final Color fill;

  /// The hairline along the outline, or null for none.
  final Color? rim;

  /// The color of the shadow under the body, or null for none.
  final Color? shadow;

  @override
  bool operator ==(Object other) =>
      other is FlatGlassLook &&
      other.fill == fill &&
      other.rim == rim &&
      other.shadow == shadow;

  @override
  int get hashCode => Object.hash(fill, rim, shadow);
}

class _FlatSurface extends SingleChildRenderObjectWidget {
  const _FlatSurface({
    required this.frame,
    required this.look,
    required super.child,
  });

  final ValueListenable<GlassFrame> frame;
  final FlatGlassLook look;

  @override
  RenderFlatGlass createRenderObject(BuildContext context) =>
      RenderFlatGlass(frame: frame, look: look);

  @override
  void updateRenderObject(BuildContext context, RenderFlatGlass renderObject) {
    renderObject.frame = frame;
    renderObject.look = look;
  }
}

/// Paints a flat glass body under its child where the frame draws it.
@internal
class RenderFlatGlass extends RenderProxyBox {
  /// Creates a body that follows [frame].
  RenderFlatGlass({
    required this._frame,
    required this._look,
  });

  /// The shadow's offset and blur sigma, Morph's flat glass button.
  static const Offset shadowOffset = Offset(0, 2);

  /// See [shadowOffset].
  static const double shadowSigma = 6;

  /// The width of the rim, stroked just inside the outline.
  static const double rimWidth = 0.5;

  ValueListenable<GlassFrame> _frame;

  /// The frames the body follows.
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (value == _frame) return;
    if (attached) _frame.removeListener(markNeedsPaint);
    _frame = value;
    if (attached) _frame.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  FlatGlassLook _look;

  /// How the body is painted.
  FlatGlassLook get look => _look;
  set look(FlatGlassLook value) {
    if (value == _look) return;
    _look = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipPathLayer>();
  final _transform = LayerHandle<TransformLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frame.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _transform.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final content = _frame.value.contentTransformIn(size);
    if (content != null) transform.multiply(content);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _frame.value;
    final body = frame.drawnIn(size);
    final outline = frame.shape.getOuterPath(body);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (_look.shadow case final shadow?) {
      final paint = Paint();
      paint.color = shadow;
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, shadowSigma);
      canvas.drawPath(outline.shift(shadowOffset), paint);
    }
    final fill = Paint();
    fill.color = _look.fill;
    canvas.drawPath(outline, fill);
    if (_look.rim case final rim?) {
      final stroke = Paint();
      stroke.style = PaintingStyle.stroke;
      stroke.strokeWidth = rimWidth;
      stroke.color = rim;
      canvas.drawPath(
        frame.shape.getOuterPath(body.deflate(rimWidth / 2)),
        stroke,
      );
    }
    canvas.restore();
    final child = this.child;
    if (child == null) return;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      outline,
      (context, offset) => _paintContent(context, offset, frame),
      oldLayer: _clip.layer,
    );
  }

  void _paintContent(PaintingContext context, Offset offset, GlassFrame frame) {
    final transform = frame.contentTransformIn(size);
    if (transform == null) {
      _transform.layer = null;
      context.paintChild(child!, offset);
      return;
    }
    _transform.layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => context.paintChild(child!, offset),
      oldLayer: _transform.layer,
    );
  }
}
