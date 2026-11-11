// ignore_for_file: require_trailing_commas

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
import 'package:liquid_glass_renderer/src/glass_glow.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/glass_blur.dart';
import 'package:liquid_glass_renderer/src/internal/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/optimized_clip.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_visibility.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shape_frame.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';

/// A lower-cost approximation of [LiquidGlass] without refraction geometry.
///
/// It blurs and color-filters the backdrop and draws the tint, contour, bevel
/// and highlight analytically, and works on both Impeller and Skia. Where it
/// can, it filters a copy of what lies under it rather than reading the
/// backdrop (see [LiquidGlassBackdropFilterLayer]). NEAR: over a copy
/// filtered as the backdrop is, the antialiased rim of the shape differs
/// from reading the backdrop by up to 10 channel levels in the host test at
/// a device pixel ratio of 1, and inside the rim by at most 2; a copy the
/// shader frosts differs more (see
/// [LiquidGlassBackdropFrost.debugShaderFrost]). Fake shapes inside a
/// [LiquidGlassBlendGroup] remain visually independent; this fallback does
/// not compute smooth-union geometry.
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
       inheritVisibility = true,
       live = null,
       fakeKey = null,
       fadeKey = null;

  /// Creates the glass of a [LiquidGlass] in a fake layer, which reads the
  /// backdrop and paints the surface for it; [appearance] is resolved.
  @internal
  const FakeGlass.inLayerResolved({
    required this.shape,
    required this.child,
    required this.appearance,
    this.live,
    this.fakeKey,
    this.fadeKey,
    super.key,
  }) : settings = null,
       shadows = const [],
       _handledByLayer = true,
       inheritVisibility = false;

  static final List<String> _surfaceShaderAssets = [
    ShaderKeys.fakeGlassSurface,
  ];

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

  /// The list of shadows to paint around the glass shape.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  final bool _handledByLayer;

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
    final settings = this.settings ?? LiquidGlassSettings.of(context);
    final renderScope = this.settings == null
        ? LiquidGlassRenderScope.of(context)
        : null;
    final baseAppearance =
        this.appearance ??
        renderScope?.defaultAppearance ??
        const LiquidGlassAppearance();
    final appearance = inheritVisibility
        ? baseAppearance.copyWith(
            visibility:
                baseAppearance.visibility * LiquidGlassVisibility.of(context),
          )
        : baseAppearance;

    final glow = Opacity(
      key: fadeKey,
      opacity: appearance.visibility.clamp(0.0, 1.0),
      child: GlassGlowLayer(child: child),
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
      appearance: appearance,
      role: role,
      surfaceShader: surfaceShader,
      live: live,
      child: glow,
    );
    final fake = role != FakeGlassRole.layerPaints
        ? MultiShaderBuilder(
            (_, shaders, _) => buildRawFake(shaders.single),
            assetKeys: _surfaceShaderAssets,
            child: buildRawFake(null),
          )
        : buildRawFake(null);
    final clipped = OptimizedClip(
      shape: shape,
      outset: role == FakeGlassRole.layerPaints
          ? 0
          : fakeGlassSurfaceOutset(settings),
      live: live,
      child: fake,
    );
    if (shadows.isEmpty) return clipped;
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      appearanceVisibility: appearance.visibility,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      live: live,
      child: clipped,
    );
  }
}

/// Who reads the backdrop and paints the surface of a [RawFakeGlass].
@internal
enum FakeGlassRole {
  /// The consolidated fake layer reads the backdrop and paints the surface.
  layerPaints,

  /// The glass reads its backdrop and paints its surface inside a fake
  /// layer, unclipped where the surface reaches past the shape.
  inFakeLayer,

  /// The glass reads its backdrop clipped to the shape and draws its
  /// exterior border as a separate ring.
  standalone,
}

@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  const RawFakeGlass({
    required this.shape,
    required super.child,
    this.role = FakeGlassRole.standalone,
    this.surfaceShader,
    this.settings = const LiquidGlassSettings(),
    this.appearance = const LiquidGlassAppearance(),
    this.live,
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance appearance;

  final FakeGlassRole role;

  final ui.FragmentShader? surfaceShader;

  /// The live frame whose rect sizes the glass at paint.
  final ValueListenable<LiquidGlassShapeFrame>? live;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFakeGlass(
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      shape: shape,
      settings: settings,
      appearance: appearance,
      role: role,
      surfaceShader: surfaceShader,
    )..live = live;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    if (renderObject is RenderFakeGlass) {
      renderObject
        ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
        ..shape = shape
        ..settings = settings
        ..appearance = appearance
        ..role = role
        ..surfaceShader = surfaceShader
        ..live = live;
    }
  }
}

@internal
class RenderFakeGlass extends RenderProxyBox with LivePaintSize {
  RenderFakeGlass({
    required this._devicePixelRatio,
    required this._shape,
    required this._settings,
    required this._appearance,
    required this._role,
    required this._surfaceShader,
  });

  FakeGlassRole _role;
  FakeGlassRole get role => _role;
  set role(FakeGlassRole value) {
    if (_role == value) return;
    _role = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _handledByLayer => _role == FakeGlassRole.layerPaints;

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  LiquidGlassAppearance _appearance;
  LiquidGlassAppearance get appearance => _appearance;
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _hasBlur =>
      settings.effectiveFrost != 0 && appearance.visibility > 0;

  bool get _hasColorTransfer =>
      appearance.visibility > 0 &&
      (appearance.colorModel.saturation != 1 ||
          appearance.colorModel.transmissionGamma != 1 ||
          appearance.colorModel.faceTransfer() != null);

  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  ui.FragmentShader? _surfaceShader;
  ui.FragmentShader? get surfaceShader => _surfaceShader;
  set surfaceShader(ui.FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  @visibleForTesting
  int debugPaintCount = 0;

  @override
  bool get alwaysNeedsCompositing => _hasBackdropEffect && !_handledByLayer;

  @override
  LiquidGlassBackdropFilterLayer? get layer =>
      super.layer as LiquidGlassBackdropFilterLayer?;

  @visibleForTesting
  LiquidGlassBackdropFilterLayer? get debugBackdropFilterLayer => layer;

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track fake surface paints in debug builds.');
    if (!_hasBackdropEffect || _handledByLayer) {
      // The consolidated layer reads the backdrop for this glass, or there is
      // nothing to read: no backdrop layer.
      this.layer = null;
      _paintRecordedSurface(context.canvas, offset);
      if (_paintsBorderRing) {
        _paintBorderRing(context.canvas, offset);
        final localBounds = Offset.zero & paintSize;
        context.pushClipPath(
          needsCompositing,
          offset,
          localBounds,
          shape.getOuterPath(localBounds),
          (context, offset) => super.paint(context, offset),
        );
        return;
      }
      super.paint(context, offset);
      return;
    }

    final parts = fakeGlassBackdropFilterParts(
      settings,
      appearance,
      deviceScale: devicePixelRatio,
      shapeShortSide: paintSize.shortestSide,
    )!;
    final clip = offset & paintSize;
    final reach = glassBlurReach(parts.sigma);
    final layer = this.layer ??= LiquidGlassBackdropFilterLayer(
      filter: parts.full,
      clip: clip,
      reach: reach,
      devicePixelRatio: devicePixelRatio,
      blendMode: BlendMode.srcATop,
    );
    if (parts.frost case final frost?) {
      layer.frost = frost;
    } else {
      layer.filter = parts.full;
    }
    layer
      ..clip = clip
      ..reach = reach
      ..devicePixelRatio = devicePixelRatio;

    if (_role == FakeGlassRole.inFakeLayer) {
      final localBounds = Offset.zero & paintSize;
      final clipPath = shape.getOuterPath(localBounds);
      context.pushClipPath(
        true,
        offset,
        localBounds,
        clipPath,
        (context, offset) {
          if (!ui.ImageFilter.isShaderFilterSupported) {
            context.setWillChangeHint();
          }
          context.pushLayer(layer, (_, _) {}, offset);
        },
      );
      _paintRecordedSurface(context.canvas, offset);
      context.pushClipPath(
        true,
        offset,
        localBounds,
        clipPath,
        (context, offset) => super.paint(context, offset),
      );
      return;
    }

    void paintBackdropLayer(PaintingContext context, Offset offset) {
      context.pushLayer(layer, (context, offset) {
        // If we are on Skia, we need to avoid the raster cache.
        if (!ui.ImageFilter.isShaderFilterSupported) {
          context.setWillChangeHint();
        }

        _paintInnerContent(context, offset);
      }, offset);
    }

    if (_paintsBorderRing) {
      final localBounds = Offset.zero & paintSize;
      context.pushClipPath(
        true,
        offset,
        localBounds,
        shape.getOuterPath(localBounds),
        paintBackdropLayer,
      );
      _paintBorderRing(context.canvas, offset);
      return;
    }
    paintBackdropLayer(context, offset);
  }

  bool get _paintsBorderRing =>
      _role == FakeGlassRole.standalone &&
      _surfaceShader != null &&
      settings.contourWidth > 0;

  /// Draws the analytic surface only outside the silhouette, where the
  /// exterior border lives, without widening the backdrop clip.
  void _paintBorderRing(Canvas canvas, Offset offset) {
    final localBounds = Offset.zero & paintSize;
    final ring = Path.from(shape.getOuterPath(localBounds))
      ..addRect(localBounds.inflate(fakeGlassSurfaceOutset(settings)))
      ..fillType = PathFillType.evenOdd;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(ring);
    paintFakeGlassSurface(
      canvas,
      shader: _surfaceShader!,
      size: paintSize,
      shape: shape,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: true,
    );
    canvas.restore();
  }

  /// Paints content inside the single composed backdrop-filter pass.
  void _paintInnerContent(PaintingContext context, Offset offset) {
    _paintRecordedSurface(context.canvas, offset);
    super.paint(context, offset);
  }

  void _paintRecordedSurface(Canvas canvas, Offset offset) {
    if (_handledByLayer) return;
    if (_surfaceShader case final shader?) {
      _paintShaderSurface(canvas, offset, shader);
      return;
    }
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    final surfaceTint = appearance.colorModel.approximateSurfaceTint(
      appearance.tint,
    );
    final tint = surfaceTint.withValues(
      alpha: surfaceTint.a * visibility,
    );
    if (tint.a == 0) return;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(shape.getOuterPath(Offset.zero & paintSize))
      ..drawPaint(Paint()..color = tint)
      ..restore();
  }

  void _paintShaderSurface(
    Canvas canvas,
    Offset offset,
    ui.FragmentShader shader,
  ) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (_role != FakeGlassRole.inFakeLayer) {
      canvas.clipPath(shape.getOuterPath(Offset.zero & paintSize));
    }
    paintFakeGlassSurface(
      canvas,
      shader: shader,
      size: paintSize,
      shape: shape,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
    );
    if (settings.highlight * appearance.visibility > 0) {
      paintFakeGlassSurface(
        canvas,
        shader: shader,
        size: paintSize,
        shape: shape,
        settings: settings,
        appearance: appearance,
        devicePixelRatio: devicePixelRatio,
        highlightOnly: true,
      );
    }
    canvas.restore();
  }
}
