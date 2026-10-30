import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The flat renderer: a fill per role and glass, a hairline rim on all but
/// a track and a resting lens or knob, a soft shadow under floating roles;
/// no backdrop reads, no glow. A lens or knob is an opaque platter that
/// fades and gains a rim as it lifts.
///
/// The fills, rims and shadows are Morph's flat glass button and flat small
/// lens: an approximation of the glass's average look, not a measurement. A
/// track is a plain fill on every renderer; untinted, it takes iOS
/// systemFill, a default no control measured. A color scheme's surfaces
/// replace the fills per role.
@internal
final class FlatGlassRenderer extends GlassRenderer {
  /// Creates the flat renderer.
  const FlatGlassRenderer();

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      flatSurface(context, details);

  /// The flat body of [details]; [underGlass] for a lens or knob whose
  /// liquid glass covers it while it is lifted.
  static Widget flatSurface(
    BuildContext context,
    GlassSurfaceDetails details, {
    bool underGlass = false,
  }) => _FlatSurface(
    frame: details.frame,
    look: FlatGlassLook.of(
      details.role,
      details.glass,
      GlassTraits.of(context),
      scheme: GlassTheme.colorSchemeOf(context),
      underGlass: underGlass,
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
  const FlatGlassLook({
    required this.fill,
    this.rim,
    this.shadow,
    this.liftRim,
    this.underGlass = false,
  });

  /// The look of a surface of [role] made of [glass] under [traits]: the
  /// glass's tint, else the [scheme]'s surface for the role, else the
  /// renderer's own fill.
  factory FlatGlassLook.of(
    GlassRole role,
    Glass glass,
    GlassTraits traits, {
    GlassColorScheme? scheme,
    bool underGlass = false,
  }) {
    Color resolve(Color color) =>
        color is GlassDynamicColor ? color.resolvedWith(traits) : color;
    final tint = glass.tint;
    final surface = scheme?.surfaces[role];
    switch (role) {
      case GlassRole.knob ||
          GlassRole.thumb ||
          GlassRole.lens ||
          GlassRole.tabBarLens:
        return FlatGlassLook(
          fill: resolve(tint ?? surface ?? _platter),
          shadow: _liftShadow,
          liftRim: resolve(_liftRim),
          underGlass: underGlass,
        );
      case GlassRole.track:
        return FlatGlassLook(
          fill: resolve(tint ?? surface ?? GlassColors.systemFill),
        );
      case GlassRole.control ||
          GlassRole.menu ||
          GlassRole.sheet ||
          GlassRole.bar:
        final floating = role != GlassRole.bar;
        return FlatGlassLook(
          fill: resolve(tint ?? surface ?? (glass.isClear ? _clear : _fill)),
          rim: tint != null ? _tintedRim : resolve(_rim),
          shadow: floating ? resolve(_shadow) : null,
        );
    }
  }

  static const _fill = GlassDynamicColor.withBrightness(
    color: Color(0xD9FFFFFF),
    darkColor: Color(0xB82C2C2E),
  );
  static const _clear = GlassDynamicColor.withBrightness(
    color: Color(0x40FFFFFF),
    darkColor: Color(0x402C2C2E),
  );
  static const _rim = GlassDynamicColor.withBrightness(
    color: Color(0x1F000000),
    darkColor: Color(0x33FFFFFF),
  );
  static const _tintedRim = Color(0x33FFFFFF);
  static const _platter = Color(0xFFFFFFFF);
  static const _liftShadow = Color(0x26000000);
  static const _liftRim = GlassDynamicColor.withBrightness(
    color: Color(0x2E000000),
    darkColor: Color(0x47FFFFFF),
  );
  static const _shadow = GlassDynamicColor.withBrightness(
    color: Color(0x1A000000),
    darkColor: Color(0x40000000),
  );

  /// The fill of the body.
  final Color fill;

  /// The hairline along the outline, or null for none.
  final Color? rim;

  /// The color of the shadow under the body at rest, or null for none; a
  /// lifting body's darkens by a tenth and spreads as it lifts.
  final Color? shadow;

  /// The rim of a fully lifted lens or knob, or null for a surface that
  /// does not lift.
  ///
  /// A lifting look is Morph's flat small lens: the fill fades to a fifth
  /// of its opacity as the frame lifts ([liftedOpacity]), this rim fades in,
  /// and the shadow darkens and spreads. Not measured.
  final Color? liftRim;

  /// Whether liquid glass covers this lifting body while it is lifted: its
  /// fill and shadow then fade as the glass appears ([glassness]), and the
  /// glass draws the rim.
  final bool underGlass;

  /// The share of its opacity a lens's fill keeps at [lift]: all at rest, a
  /// fifth fully lifted (Morph's flat small lens, not measured).
  static double liftedOpacity(double lift) => 1 - 0.8 * lift.clamp(0.0, 1.0);

  /// Below this lift a lens or knob draws no glass.
  ///
  /// Above it the glass appears over the first [glassLiftSpan] of the
  /// lift. Engineering defaults from Morph, not measured; a lens crossing
  /// it changes by at most 2% of its blend: invisible, NEAR.
  static const double restingLift = 0.005;

  /// See [restingLift].
  static const double glassLiftSpan = 0.25;

  /// How far a lens or knob lifted by [lift] has turned into glass.
  static double glassness(double lift) =>
      lift <= restingLift ? 0 : (lift / glassLiftSpan).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is FlatGlassLook &&
      other.fill == fill &&
      other.rim == rim &&
      other.shadow == shadow &&
      other.liftRim == liftRim &&
      other.underGlass == underGlass;

  @override
  int get hashCode => Object.hash(fill, rim, shadow, liftRim, underGlass);
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

  /// The offset and blur sigma of the shadow under a body that does not
  /// lift: Morph's flat glass button.
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
    if (attached) _frame.removeListener(_framed);
    _frame = value;
    if (attached) _frame.addListener(_framed);
    _framed();
  }

  bool _fading = false;

  // A partly present body draws through an opacity layer of its own.
  void _framed() {
    final fading = _frame.value.opacity < 1;
    if (fading != _fading) {
      _fading = fading;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _fading;

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
  final _opacity = LayerHandle<OpacityLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_framed);
    _fading = _frame.value.opacity < 1;
  }

  @override
  void detach() {
    _frame.removeListener(_framed);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final content = _frame.value.contentTransformIn(size);
    if (content != null) transform.multiply(content);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final opacity = _frame.value.opacity;
    if (opacity >= 1) {
      _opacity.layer = null;
      _paintSurface(context, offset);
      return;
    }
    if (opacity <= 0) {
      _opacity.layer = null;
      return;
    }
    _opacity.layer = context.pushOpacity(
      offset,
      (opacity * 255).round(),
      _paintSurface,
      oldLayer: _opacity.layer,
    );
  }

  void _paintSurface(PaintingContext context, Offset offset) {
    final frame = _frame.value;
    final body = frame.drawnIn(size);
    final outline = frame.outline?.path ?? frame.shape.getOuterPath(body);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final color = frame.tint ?? _look.fill;
    final liftRim = _look.liftRim;
    if (liftRim != null) {
      _paintLifting(canvas, frame, body, outline, color, liftRim);
    } else {
      _paintBody(canvas, frame, body, outline, color);
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

  void _paintLifting(
    Canvas canvas,
    GlassFrame frame,
    Rect body,
    Path outline,
    Color color,
    Color liftRim,
  ) {
    final lift = frame.lift.clamp(0.0, 1.0);
    final shown = _look.underGlass ? 1 - FlatGlassLook.glassness(lift) : 1.0;
    if (shown <= 0) return;
    if (_look.shadow case final resting?) {
      final shadow = Paint();
      shadow.color = resting.withValues(
        alpha: (resting.a + 0.1 * lift) * shown,
      );
      shadow.maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 4 * lift);
      canvas.drawPath(outline.shift(const Offset(0, 1.5)), shadow);
    }
    final fill = Paint();
    fill.color = color.withValues(
      alpha: color.a * FlatGlassLook.liftedOpacity(lift) * shown,
    );
    canvas.drawPath(outline, fill);
    if (_look.underGlass || lift <= 0.01) return;
    final rim = Paint();
    rim.style = PaintingStyle.stroke;
    rim.strokeWidth = 0.75;
    rim.color = liftRim.withValues(alpha: liftRim.a * lift);
    canvas.drawPath(_rimPath(frame, body, 0.4), rim);
  }

  void _paintBody(
    Canvas canvas,
    GlassFrame frame,
    Rect body,
    Path outline,
    Color color,
  ) {
    if (_look.shadow case final shadow?) {
      final paint = Paint();
      paint.color = shadow;
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, shadowSigma);
      canvas.drawPath(outline.shift(shadowOffset), paint);
    }
    final fill = Paint();
    fill.color = color;
    canvas.drawPath(outline, fill);
    if (_look.rim case final rim?) {
      final stroke = Paint();
      stroke.style = PaintingStyle.stroke;
      stroke.strokeWidth = rimWidth;
      stroke.color = rim;
      canvas.drawPath(_rimPath(frame, body, rimWidth / 2), stroke);
    }
  }

  // An outline body strokes its own edge: the rim is too thin for the
  // stroke's straddle of the edge to show.
  static Path _rimPath(GlassFrame frame, Rect body, double inset) =>
      frame.outline?.path ?? frame.shape.getOuterPath(body.deflate(inset));

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
