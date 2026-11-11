import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/path_outside.dart';
import 'package:apple_liquid_glass/src/liquid/scroll_edge.dart';
import 'package:apple_liquid_glass/src/liquid/shapes.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/widgets.dart';

part 'package:apple_liquid_glass/src/liquid/liquid_group.dart';
part 'package:apple_liquid_glass/src/liquid/liquid_render.dart';

/// The liquid renderer: every surface is liquid glass, and the members of
/// a group share one glass layer.
///
/// A lone body whose [GlassFrame.outline] has a field is shaded from that
/// field in a layer of its own, its shadow cast by the outline's path; an
/// outlined body in a group, on fake glass or without a field draws flat.
/// The renderer chooses from the frame the surface builds with, not per
/// frame.
///
/// A surface outside a group draws as a group of one, and a track as a
/// plain fill, as iOS draws one. A lens or knob is an opaque platter at
/// rest and gets a glass layer of its own over the platter only while it
/// is lifted; on fake glass the layer keeps the lifted optics for the whole
/// lift and the glass's fade carries the change, a NEAR trade that keeps
/// the fake layer from rebuilding every frame.
///
/// Layers use the fitted iOS 27 settings: clear for clear glass (a group
/// only when all its members are clear), regular in the ambient brightness
/// ([GlassTraits.brightness]) otherwise, both at the Liquid Glass slider's
/// position ([GlassTraits.glassTintAmount]).
///
/// Under Reduce Transparency the surfaces draw flat, an unmeasured
/// stand-in for iOS's frosted glass.
///
/// A body whose control is focused from the keyboard draws Flutter's
/// Cupertino focus ring outside its shape, and a hovered one a pressed
/// body's wash at half strength over it ([GlassSurfaceDetails.states]),
/// both plain painting over the glass that costs it no pass.
///
/// On a device without shader filters the layers draw fake glass, as
/// [FakeGlassRenderer] does.
base class LiquidGlassRenderer extends GlassRenderer {
  /// Creates the liquid renderer.
  const LiquidGlassRenderer();

  /// Whether every layer draws fake glass, which shows no touch glow.
  @internal
  bool get fake => false;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      buildHighlights(context, details, _body(context, details));

  Widget _body(BuildContext context, GlassSurfaceDetails details) {
    if (GlassTraits.of(context).reduceTransparency ||
        details.role == GlassRole.track) {
      return FlatGlassRenderer.flatSurface(context, details);
    }
    if (details.role == GlassRole.lens) {
      return _LiquidLens(details: details, fake: fake);
    }
    final grouped = _LiquidGroupScope.maybeOf(context) != null;
    if (details.frame.value.outline case final outline?
        when fake || grouped || !outline.hasField) {
      return FlatGlassRenderer.flatSurface(context, details);
    }
    if (grouped) return _LiquidSurface(details: details, glows: !fake);
    return _LiquidGroup(
      fake: fake,
      glass: details.glass,
      body: details.frame,
      child: _LiquidSurface(details: details, glows: !fake, outlined: true),
    );
  }

  @override
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => GlassTraits.of(context).reduceTransparency
      ? super.buildScrollEdge(context, details)
      : ScrollEdge(details: details);

  @override
  Widget buildGroup(BuildContext context, GlassGroupDetails details) {
    if (GlassTraits.of(context).reduceTransparency) return details.child;
    return _LiquidGroup(
      fake: fake,
      blend: details.merge.spacing,
      child: details.child,
    );
  }

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  /// The appearance of [glass] in [brightness].
  @internal
  static LiquidGlassAppearance appearanceOf(
    Glass glass,
    Brightness brightness,
  ) {
    final tint = glass.tint;
    return switch ((glass.isClear, tint)) {
      (true, null) => const LiquidGlassAppearance.ios27Clear(),
      (true, final Color tint) => LiquidGlassAppearance.ios27Clear(tint: tint),
      (false, null) => LiquidGlassAppearance.ios27Regular(
        brightness: brightness,
      ),
      (false, final Color tint) => LiquidGlassAppearance.ios27Regular(
        brightness: brightness,
        tint: tint,
      ),
    };
  }

  /// The shadows of a body of [role] lifted by [lift].
  ///
  /// Engineering defaults, not measured: one soft body shadow for controls
  /// and panels; a lens's drops from 1.5 to 3.5 and blurs from 3 to 9 as it
  /// lifts.
  @internal
  static List<BoxShadow> shadowsOf(GlassRole role, {double lift = 0}) {
    final l = lift.clamp(0.0, 1.0);
    return switch (role) {
      GlassRole.control || GlassRole.panel => const [
        BoxShadow(
          color: Color(0x14000000),
          offset: Offset(0, 4),
          blurRadius: 16,
        ),
      ],
      GlassRole.lens => [
        BoxShadow(
          color: const Color(0x1A000000),
          offset: Offset(0, 1.5 + 2 * l),
          blurRadius: 3 + 6 * l,
        ),
      ],
      GlassRole.bar || GlassRole.track => const [],
    };
  }
}

/// The liquid renderer on fake glass: every surface blurred and lit, with
/// no refraction and no touch glow. Cheaper than real glass, and the glass
/// a platform without shader filters, such as the web, can draw.
final class FakeGlassRenderer extends LiquidGlassRenderer {
  /// Creates the fake glass renderer.
  const FakeGlassRenderer();

  @override
  bool get fake => true;
}

// The tint [frame] gives a body whose glass has [own], crossing from it
// (or from none: an untinted iOS material is one with a transparent tint)
// by the frame's amount, or null where the frame keeps the glass's look.
Color? _tintOf(GlassFrame frame, Color? own) {
  final tint = frame.tint;
  final amount = frame.tintAmount.clamp(0.0, 1.0);
  if (tint == null || amount == 0) return null;
  if (amount == 1) return tint;
  return Color.lerp(own ?? tint.withValues(alpha: 0), tint, amount);
}

/// The settings of [lens] lifted by [lift].
///
/// UIKit's lens configuration (read from UIKit, notes private) bends what
/// is behind a resting small lens (a knob or thumb) by 50 and blurs it by
/// 6, a lifted one bends it by 9 without blur, and a large lens rests
/// clear. A lifted lens parts the colors along its rim by a factor fitted
/// to one screenshot of the iOS 27 tab bar (iPhone 16 Pro, lens lifted
/// between two items): red and blue stand 0.38 px apart at its bottom edge
/// and 0.78 px at its top, and 0.10 gives 0.57 px at both, one factor
/// having no way to tell the edges apart. An engineering factor, not
/// measured, brightens the highlight by half as the lens lifts. The lens's
/// shrink grows with the lift; the bevel bends the other way, toward the
/// middle, so a bend above UIKit's 9 hides the edges the shrink shows
/// behind the rim.
LiquidGlassSettings _lensSettings(
  LiquidGlassSettings base,
  double lift, {
  required GlassLens lens,
}) {
  final l = lift.clamp(0.0, 1.0);
  final small = lens.small;
  final displacement = small ? 50 + (9 - 50) * l : 9 * l;
  return base.copyWith(
    frost: small ? 6 * (1 - l) : 0,
    refractionAmount: displacement,
    dispersion: -0.10 * l,
    highlight: base.highlight * (1 + 0.5 * l),
    backdropShrink: lens.shrink * l,
    backdropShrinkRim: lens.shrinkRim,
  );
}

bool _drawsFake(bool fake) => fake || !ImageFilter.isShaderFilterSupported;

class _LiquidSurface extends StatefulWidget {
  const _LiquidSurface({
    required this.details,
    required this.glows,
    this.outlined = false,
  });

  final GlassSurfaceDetails details;
  final bool glows;

  /// Whether the body may take an outline, whose shadow it then casts by
  /// the outline's path; a lone surface can.
  final bool outlined;

  @override
  State<_LiquidSurface> createState() => _LiquidSurfaceState();
}

class _LiquidSurfaceState extends State<_LiquidSurface> {
  late final _shape = ValueNotifier(_shapeFrame);
  late LiquidGlassAppearance _appearance;
  late Brightness _brightness;
  _LiquidGroupState? _group;
  LiquidGlassGlow? _glow;
  final _glowRequest = _GlowRequest();

  ValueListenable<GlassFrame> get _source => widget.details.frame;

  LiquidGlassShapeFrame get _shapeFrame {
    final frame = _source.value;
    final role = widget.details.role;
    final tint = _tintOf(frame, widget.details.glass.tint);
    final appearance = role == GlassRole.lens
        ? LiquidGlassAppearance(
            visibility: GlassFrame.glassnessAt(frame.lift),
          )
        : tint == null
        ? _appearance
        : LiquidGlassRenderer.appearanceOf(
            widget.details.glass.isClear
                ? Glass.clear(tint: tint)
                : Glass.regular(tint: tint),
            _brightness,
          );
    final outline = frame.outline;
    return LiquidGlassShapeFrame(
      shape: liquidShapeOf(frame.shape),
      appearance: frame.opacity >= 1
          ? appearance
          : appearance.copyWith(
              visibility: appearance.visibility * frame.opacity.clamp(0.0, 1.0),
            ),
      shadows: outline == null
          ? LiquidGlassRenderer.shadowsOf(role, lift: frame.lift)
          : const [],
      rect: outline?.bounds ?? frame.rect,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
    );
  }

  @override
  void initState() {
    super.initState();
    _source.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(_LiquidSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.frame != _source) {
      oldWidget.details.frame.removeListener(_onFrame);
      _source.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onFrame);
    _leave(_group);
    _shape.dispose();
    super.dispose();
  }

  void _leave(_LiquidGroupState? group) {
    if (group == null) return;
    group.reportGlass(this, null);
    if (_glow == null) return;
    _glow = null;
    group.reportGlow(this, null);
  }

  void _onFrame() {
    _shape.value = _shapeFrame;
    _askGlow();
  }

  // The glow reads the body's laid out box: it is written in the frame's
  // resolve phase, after layout, so it moves in the frame its body does.
  void _askGlow() {
    if (!widget.glows || (_source.value.glow == null && _glow == null)) {
      return;
    }
    _glowRequest.ask();
  }

  void _writeGlow(RenderBox box) {
    final glow = _glowOf(_source.value, box);
    if (glow == _glow) return;
    _glow = glow;
    _group!.reportGlow(this, glow);
  }

  LiquidGlassGlow? _glowOf(GlassFrame frame, RenderBox box) {
    final glow = frame.glow;
    if (glow == null) return null;
    final size = box.size;
    final body = frame.drawnIn(size);
    final transform = frame.contentTransformIn(size);
    return _group!.toLayer(
      box,
      LiquidGlassGlow(
        bounds: body,
        cornerRadius: frame.shape.radiusIn(body),
        center: transform == null
            ? glow.center
            : MatrixUtils.transformPoint(transform, glow.center),
        radius: glow.radius * (frame.scaleX + frame.scaleY) / 2,
        gain: glow.gainOn(widget.details.glass, _brightness),
        wash: glow.wash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _LiquidGroupScope.maybeOf(context)!;
    if (!identical(group, _group)) {
      _leave(_group);
      _group = group;
    }
    group.reportGlass(this, widget.details.glass);
    _brightness = GlassTraits.of(context).brightness;
    _appearance = LiquidGlassRenderer.appearanceOf(
      widget.details.glass,
      _brightness,
    );
    _shape.value = _shapeFrame;
    _askGlow();
    final glass = LiquidGlass.live(
      frame: _shape,
      grouped: group.blends,
      child: _CenteredOnBody(frame: _shape, child: widget.details.child),
    );
    final body = widget.outlined
        ? _OutlineShadow(
            frame: _source,
            shadows: LiquidGlassRenderer.shadowsOf(widget.details.role),
            child: glass,
          )
        : glass;
    if (!widget.glows) return body;
    return _GlowResolve(
      request: _glowRequest,
      onResolve: _writeGlow,
      child: body,
    );
  }
}
