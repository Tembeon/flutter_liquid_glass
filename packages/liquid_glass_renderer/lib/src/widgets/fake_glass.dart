import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_visibility.dart';
import 'package:liquid_glass_renderer/src/widgets/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/widgets/optimized_clip.dart';

/// A lower-cost approximation of [LiquidGlass] without refraction geometry.
///
/// It blurs and color-filters the backdrop and draws the tint, contour, bevel
/// and highlight analytically, and works on both Impeller and Skia. Where it
/// can, it filters a copy of what lies under it rather than reading the
/// backdrop (see [LiquidGlassBackdropFilterLayer]). NEAR: over a copy
/// filtered as the backdrop is, the antialiased rim of the shape differs
/// from reading the backdrop by up to 10 channel levels in the host test at
/// a device pixel ratio of 1, and inside the rim by at most 2; a copy the
/// shader frosts differs more (see [PlanPolicy.shaderFrost]). Fake
/// shapes inside a [LiquidGlassBlendGroup] remain visually independent; this
/// fallback does not compute smooth-union geometry.
class FakeGlass extends StatelessWidget {
  /// Creates a new [FakeGlass] widget with the given [child], [shape], and
  /// [settings].
  const FakeGlass({
    required this.shape,
    required this.child,
    LiquidGlassSettings this.settings = const LiquidGlassSettings(),
    this.appearance,
    this.shadows = const [],
    super.key,
  }) : _handledByLayer = false,
       _clipBehavior = Clip.antiAlias,
       inheritVisibility = true,
       live = null,
       fakeKey = null,
       fadeKey = null;

  /// Creates a new [FakeGlass] widget that takes settings from the nearest
  /// ancestor [LiquidGlassLayer].
  const FakeGlass.inLayer({
    required this.shape,
    required this.child,
    this.appearance,
    this.shadows = const [],
    super.key,
  }) : settings = null,
       _handledByLayer = false,
       _clipBehavior = Clip.antiAlias,
       inheritVisibility = true,
       live = null,
       fakeKey = null,
       fadeKey = null;

  /// Creates the glass of a [LiquidGlass] in a fake layer, which reads the
  /// backdrop and paints the surface for it; [appearance] is resolved and
  /// the clip of the child is [LiquidGlass.clipBehavior].
  @internal
  const FakeGlass.inLayerResolved({
    required this.shape,
    required this.child,
    required this.appearance,
    required this._clipBehavior,
    this.live,
    this.fakeKey,
    this.fadeKey,
    super.key,
  }) : settings = null,
       shadows = const [],
       _handledByLayer = true,
       inheritVisibility = false;

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// This path approximates lighting and blur without refraction.
  /// [LiquidGlassSettings.refractionAmount],
  /// [LiquidGlassSettings.backdropShrink] and
  /// [LiquidGlassSettings.dispersion] therefore have no effect, and
  /// [LiquidGlassColorModel.vibrancy] is likewise ignored.
  /// [LiquidGlassColorModel.transmissionGamma] is only approximated.
  /// [LiquidGlassSettings.refractionHeight] only controls the width of the
  /// approximate inner light bleed.
  final LiquidGlassSettings? settings;

  /// Color and materialization controls for this shape.
  ///
  /// [FakeGlass.inLayer] inherits the containing layer's default appearance.
  final LiquidGlassAppearance? appearance;

  /// The shadows the glass shape casts, as [LiquidGlassShadow.paint] casts
  /// those of a lone body.
  final List<BoxShadow> shadows;

  final bool _handledByLayer;

  final Clip _clipBehavior;

  /// Whether to apply the nearest [LiquidGlassVisibility] multiplier.
  @internal
  final bool inheritVisibility;

  /// The live frame whose rect sizes the glass at paint.
  @internal
  final ValueListenable<LiquidGlassShapeFrame>? live;

  /// The keys of the render objects a live frame writes its shape,
  /// appearance and shadows into: the glass, its shadow and the fade of
  /// its child.
  @internal
  final Key? fakeKey;

  /// See [fakeKey].
  @internal
  final Key? fadeKey;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final renderScope = this.settings == null
        ? LiquidGlassRenderScope.of(context)
        : null;
    final settings = this.settings ?? renderScope!.settings;
    final appearance = shownAppearance(
      this.appearance,
      layerDefault:
          renderScope?.defaultAppearance ?? const LiquidGlassAppearance(),
      visibility: inheritVisibility ? LiquidGlassVisibility.of(context) : 1,
    );

    final content = Opacity(
      key: fadeKey,
      opacity: drawnVisibility(appearance.visibility),
      child: child,
    );
    final role = switch ((_handledByLayer, renderScope?.fake ?? false)) {
      (true, _) => FakeGlassRole.layerPaints,
      (false, true) => FakeGlassRole.inFakeLayer,
      (false, false) => FakeGlassRole.standalone,
    };
    RawFakeGlass buildRawFake(ui.FragmentShader? surfaceShader) => RawFakeGlass(
      key: fakeKey,
      shape: shape,
      settings: settings,
      shownAppearance: appearance,
      role: role,
      surfaceShader: surfaceShader,
      live: live,
      child: content,
    );
    final fake = role != FakeGlassRole.layerPaints
        ? MultiShaderBuilder(
            (_, shaders, _) => buildRawFake(shaders.single),
            assetKeys: ShaderKeys.fakeSurfaceAssets,
            child: buildRawFake(null),
          )
        : buildRawFake(null);
    final clipped = OptimizedClip(
      shape: shape,
      clipBehavior: _clipBehavior,
      outset: role == FakeGlassRole.layerPaints
          ? 0
          : fakeGlassSurfaceOutset(FakeGlassLook.of(settings)),
      live: live,
      child: fake,
    );
    if (shadows.isEmpty) return clipped;
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      appearanceVisibility: appearance.visibility,
      devicePixelRatio: glassDevicePixelRatioOf(context),
      live: live,
      child: clipped,
    );
  }
}

@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  const RawFakeGlass({
    required this.shape,
    required super.child,
    this.role = FakeGlassRole.standalone,
    this.surfaceShader,
    this.settings = const LiquidGlassSettings(),
    this.shownAppearance = const LiquidGlassAppearance(),
    this.live,
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance shownAppearance;

  final FakeGlassRole role;

  final ui.FragmentShader? surfaceShader;

  /// The live frame whose rect sizes the glass at paint.
  final ValueListenable<LiquidGlassShapeFrame>? live;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFakeGlass(
      devicePixelRatio: glassDevicePixelRatioOf(context),
      shape: shape,
      settings: settings,
      shownAppearance: shownAppearance,
      role: role,
      surfaceShader: surfaceShader,
    )..live = live;
  }

  @override
  void updateRenderObject(BuildContext context, RenderFakeGlass renderObject) {
    renderObject
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..shape = shape
      ..settings = settings
      ..shownAppearance = shownAppearance
      ..role = role
      ..surfaceShader = surfaceShader
      ..live = live;
  }
}
