import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/widgets/composer_install.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_visibility.dart';
import 'package:liquid_glass_renderer/src/widgets/optimized_clip.dart';

/// A lower-cost approximation of [LiquidGlass] without refraction geometry,
/// for one shape that stands alone: it needs no [LiquidGlassLayer].
///
/// It blurs and color-filters the backdrop and draws the tint, contour, bevel
/// and glint analytically, and works on both Impeller and Skia. Where it
/// can, it filters a copy of what lies under it rather than reading the
/// backdrop (see [LiquidGlassBackdropFilterLayer]). NEAR: over a copy
/// filtered as the backdrop is, the antialiased rim of the shape differs
/// from reading the backdrop by up to 10 channel levels in the host test at
/// a device pixel ratio of 1, and inside the rim by at most 2; a copy the
/// shader frosts differs more (see `PlanPolicy.shaderBlurs`).
///
/// Glass that should be full glass wherever the device draws it goes in a
/// [LiquidGlassLayer], which draws its [LiquidGlass] shapes as fake glass
/// by itself where full glass is unavailable, or always with
/// [LiquidGlassLayer.fake]. Fake shapes inside a [LiquidGlassBlendGroup]
/// remain visually independent; this fallback does not compute smooth-union
/// geometry.
///
/// One anti-aliased clip bounds the surface and the [child]: [shape], grown
/// by the contour the surface draws outside it. It is not a choice as
/// [LiquidGlass.clipBehavior] is, which clips the child alone.
class FakeGlass extends StatelessWidget {
  /// Creates a new [FakeGlass] widget with the given [child], [shape], and
  /// [settings].
  const FakeGlass({
    required this.shape,
    required this.child,
    this.settings = const LiquidGlassSettings(),
    this.appearance = const LiquidGlassAppearance(),
    this.shadows = const [],
    super.key,
  });

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// This path approximates lighting and blur without refraction: of the
  /// settings it draws [LiquidGlassSettings.blur] and
  /// [LiquidGlassSettings.sliderPosition] alone. Of a color model,
  /// [LiquidGlassDirectColorModel.vibrancy] is ignored and
  /// `transmissionGamma` only approximated.
  final LiquidGlassSettings settings;

  /// Color and materialization controls for this shape, multiplied by the
  /// nearest [LiquidGlassVisibility].
  final LiquidGlassAppearance appearance;

  /// The shadows the glass shape casts, as
  /// [LiquidGlassSilhouette.paintShadows] casts those of a lone body.
  final List<LiquidGlassShadow> shadows;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = fadedAppearance(
      appearance,
      LiquidGlassVisibility.of(context),
    );
    final content = Opacity(
      opacity: drawnVisibility(shown.visibility),
      child: child,
    );
    final clipped = OptimizedClip(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      outset: fakeGlassSurfaceOutset(
        FakeGlassLook.of(settings),
        shown.wornByNone.colorModel,
      ),
      child: RawFakeGlass(
        shape: shape,
        settings: settings,
        shownAppearance: shown,
        child: content,
      ),
    );
    if (shadows.isEmpty) return clipped;
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      appearanceVisibility: shown.visibility,
      devicePixelRatio: glassDevicePixelRatioOf(context),
      child: clipped,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('shape', shape))
      ..add(DiagnosticsProperty('settings', settings))
      ..add(DiagnosticsProperty('appearance', appearance))
      ..add(IterableProperty('shadows', shadows, ifEmpty: null));
  }
}

/// The render object widget of a [FakeGlass].
@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  /// Creates the fake glass of [shape] around [child].
  const RawFakeGlass({
    required this.shape,
    required this.settings,
    required this.shownAppearance,
    required super.child,
    super.key,
  });

  /// The shape of the glass.
  final LiquidShape shape;

  /// What the glass draws with.
  final LiquidGlassSettings settings;

  /// The appearance the glass shows: its own, faded.
  final LiquidGlassAppearance shownAppearance;

  @override
  RenderObject createRenderObject(BuildContext context) {
    installLiquidGlassComposer();
    return RenderFakeGlass(
      devicePixelRatio: glassDevicePixelRatioOf(context),
      shape: shape,
      settings: settings,
      shownAppearance: shownAppearance,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFakeGlass renderObject) {
    renderObject
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..shape = shape
      ..settings = settings
      ..shownAppearance = shownAppearance;
  }
}
