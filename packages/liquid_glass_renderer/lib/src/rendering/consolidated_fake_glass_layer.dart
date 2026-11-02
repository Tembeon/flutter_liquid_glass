import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

enum _FakeGlassPaintStage {
  shadows,
  backdrop,
  surfaces,
  contents,
}

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settings,
    required this.defaultAppearance,
    required this.surfaceShader,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final FragmentShader? surfaceShader;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        link: link,
        settings: settings,
        defaultAppearance: defaultAppearance,
        surfaceShader: surfaceShader,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
      ..link = link
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..surfaceShader = surfaceShader;
  }
}

/// The fake glass layer: paints a clipped backdrop blur plus the surface
/// shader for the shared shape geometry. Where it can, the shared blur is
/// drawn over a copy of what lies under the glass instead of reading the
/// backdrop (see [BackdropRig]). NEAR: over a copy, a blur that Impeller
/// downsamples takes other taps than over the whole backdrop, at most 19
/// channel levels apart in the host test of white text under 6 px of frost;
/// at 2 px the two do not differ. All shared machinery (shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state) lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderConsolidatedFakeGlassLayer({
    required super.devicePixelRatio,
    required super.link,
    required super.settings,
    required super.defaultAppearance,
    required this._surfaceShader,
  });

  FragmentShader? _surfaceShader;
  FragmentShader? get surfaceShader => _surfaceShader;

  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  /// Capture shared by this layer's own backdrop reads. Without it, a
  /// separately served shape would sample the shared filter's output in
  /// overlapping pixels and compound both transfers; sharing one capture
  /// also collapses their backdrop readbacks into one.
  final _share = BackdropShare();

  /// The read under the shared union clip.
  late final _sharedRig = _rig();

  BackdropRig _rig() => BackdropRig(
    plan: planBackdropPass,
    share: _share,
    seedWhileResizing: true,
  );

  final _retainedFrameSlot = LayerHandle<ContainerLayer>();

  /// Per-shape backdrop reads for shapes the shared union clip cannot
  /// serve: shapes that are fading (0 < visibility < 1) or whose appearance
  /// needs a different backdrop transfer than the layer's. They sit between
  /// the shared opaque-shape filter and the surfaces so a fading shape keeps
  /// its own clipped backdrop filter instead of swapping its widget subtree.
  final Map<LiquidGlassShapeRenderObject, BackdropRig> _separateRigs = {};
  FakeGlassFilterParts? _cachedFilter;
  double? _cachedFilterSigma;

  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  List<int> _cachedClipClasses = const [];

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.colorModel.saturation != 1 ||
      defaultAppearance.colorModel.transmissionGamma != 1 ||
      defaultAppearance.colorModel.faceTransfer() != null;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  /// Whether [appearance] can be served by the layer's shared backdrop
  /// filter — that is, it differs from [defaultAppearance] only in fields
  /// the surface pass and opacity handle (tint and visibility).
  bool _sharesLayerBackdrop(LiquidGlassAppearance appearance) =>
      appearance.colorModel == defaultAppearance.colorModel;

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _sharedRig.filterLayer;

  /// The retained per-shape clipped backdrop filters.
  @visibleForTesting
  Iterable<BackdropFilterLayer> get debugSeparateBackdropLayers =>
      _separateRigs.values.map((rig) => rig.filterLayer).nonNulls;

  @visibleForTesting
  Rect? debugClipBounds;

  /// Whether the last composited frame drew the shared filter over a copy
  /// rather than reading the backdrop.
  @visibleForTesting
  bool debugDrewOverCopy = false;

  @visibleForTesting
  Path? get debugClipPath => _cachedClipPath;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // MARK: Retained frame hooks

  // The fake effect encodes no matte, so a fully-hidden frame retains
  // nothing that must stay compositor-only.
  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.empty;

  // Without a matte, every shape is drawable.
  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => true;

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentGeometryCache(snapshot);

  @override
  double get materialOutset => fakeGlassSurfaceOutset(settings);

  // How far outside its bounds the blur reads; one extra logical pixel
  // covers the kernel's rounding at any DPR.
  double get _samplingReach {
    if (!_hasBlur) return 0;
    final sigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: _layerShapeShortSide,
    );
    return sigma * 3 + 1;
  }

  /// Short side of the smallest visible shape, fading ones included. The
  /// blur is layer-wide, like RealGlass's: the shared filter and every
  /// separate one use it, so a shape that starts to fade (and leaves the
  /// shared filter for one of its own) keeps the blur it had.
  double get _layerShapeShortSide {
    double? shortest;
    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) == 0) continue;
        // shapeBounds is already in the geometry's local space.
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        shortest = shortest == null ? side : math.min(shortest, side);
      }
    }
    return shortest ?? 150;
  }

  FakeGlassFilterParts _sharedBackdropFilter() {
    // Keyed on the blur sigma the short side turns into, not on the short
    // side: an animated scale changes it every frame, but the filter only
    // when the sigma does, and a new filter object is a new backdrop saveLayer
    // paint.
    final sigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: _layerShapeShortSide,
    );
    final cached = _cachedFilter;
    if (cached != null && _cachedFilterSigma == sigma) return cached;
    final filter = _buildBackdropFilter();
    _cachedFilter = filter;
    _cachedFilterSigma = sigma;
    return filter;
  }

  @override
  void onDevicePixelRatioChanged() {
    _cachedFilter = null;
    _cachedFilterSigma = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _cachedFilter = null;
    _cachedFilterSigma = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onAppearanceChanged() {
    _cachedFilter = null;
    _cachedFilterSigma = null;
    markNeedsCompositingBitsUpdate();
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    context.pushLayer(
      _retainedFrameSlot.layer ??= ContainerLayer(),
      (slotContext, slotOffset) =>
          _paintFrame(slotContext, slotOffset, geometryBounds),
      offset,
    );
  }

  void _paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    if (frameState == GlassFrameState.empty && shapesWithGeometry.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    if (!_clipInputsMatch()) {
      Rect? rebuiltBounds;
      final rebuiltPath = Path();
      final rebuiltClasses = <int>[];
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          final backdropClass = _backdropClass(shape.appearance);
          rebuiltClasses.add(backdropClass);
          if (backdropClass == 0) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final shapeBounds = Offset.zero & shape.renderObject.paintSize;
          final transformedBounds = MatrixUtils.transformRect(
            shapeToLayer,
            shapeBounds,
          );
          rebuiltBounds =
              rebuiltBounds?.expandToInclude(transformedBounds) ??
              transformedBounds;
          // The shared union clip covers only fully visible shapes whose
          // backdrop transfer matches the layer's; every other visible shape
          // gets its own clipped pass below.
          if (backdropClass == 2) {
            rebuiltPath.addPath(
              shape.shape.getOuterPath(shapeBounds),
              Offset.zero,
              matrix4: shapeToLayer.storage,
            );
          }
        }
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipClasses = rebuiltClasses;
      rememberFrameInputs();
    }
    final bounds = _cachedClipBounds;
    if (bounds == null) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _releaseLayers();
      return;
    }
    final clipPath = _cachedClipPath!;

    debugClipBounds = bounds;
    effectPaintBounds = expandEffectBounds(bounds);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    paintRetainedEffect(context, offset, (effectContext, effectOffset) {
      if (recordGlassShadows(effectOffset) case final shadows?) {
        effectContext.addLayer(shadows);
      }

      // The shared filter only exists while a fully visible shape shares
      // the layer's backdrop transfer.
      final sharedBackdropActive =
          _hasBackdropEffect && _cachedClipClasses.contains(2);
      var paintedBackdrop = sharedBackdropActive;
      if (sharedBackdropActive) {
        final sharedFilter = _sharedBackdropFilter();
        _sharedRig.paint(
          effectContext,
          effectOffset,
          filter: sharedFilter.full,
          blur: _passBlur(sharedFilter),
          bounds: bounds,
          outline: clipPath,
          reach: _samplingReach,
          devicePixelRatio: devicePixelRatio,
          // Separate shapes read live under the shared key. A shared filter
          // drawn from a copy would leave them no shared read, so they would
          // filter its output where they overlap: while one paints, the
          // shared filter reads live too.
          copies: BackdropUnderlay.enabled && !_cachedClipClasses.contains(1),
        );
      } else {
        _sharedRig.clear();
      }
      paintedBackdrop =
          _paintSeparateBackdrops(
            effectContext,
            effectOffset,
            shapesWithGeometry,
          ) ||
          paintedBackdrop;
      assert(() {
        if (paintedBackdrop) {
          _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
        }
        return true;
      }(), 'Record backdrop composition order.');

      assert(() {
        _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
        return true;
      }(), 'Record layer-owned surface composition order.');
      _paintSurfaces(effectContext.canvas, effectOffset, shapesWithGeometry);
    });
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
  }

  void _paintSurfaces(
    Canvas canvas,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final shader = surfaceShader;
    if (shader == null) return;
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        paintFakeGlassSurface(
          canvas,
          shader: shader,
          size: shape.renderObject.paintSize,
          shape: shape.shape,
          settings: settings,
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        if (settings.highlight * shape.appearance.visibility > 0) {
          paintFakeGlassSurface(
            canvas,
            shader: shader,
            size: shape.renderObject.paintSize,
            shape: shape.shape,
            settings: settings,
            appearance: shape.appearance,
            devicePixelRatio: devicePixelRatio,
            highlightOnly: true,
          );
        }
        canvas.restore();
      }
    }
  }

  /// Paints each separately served shape's own clipped backdrop filter so
  /// its transfer applies independently while the shape stays registered
  /// with this layer. Layers are retained across frames keyed by the
  /// shape's render object; entries for shapes that rejoined the shared
  /// clip or hid are released. Returns whether any pass was painted.
  bool _paintSeparateBackdrops(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    final shortSide = _layerShapeShortSide;
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) != 1) continue;
        // The shape's own appearance carries its visibility and any
        // backdrop-transfer override, so fading keeps the same transfer the
        // shared filter applied while it was fully visible.
        final filter = fakeGlassBackdropFilterParts(
          settings,
          shape.appearance,
          deviceScale: devicePixelRatio,
          shapeShortSide: shortSide,
        );
        if (filter == null) continue;
        final renderObject = shape.renderObject;
        active.add(renderObject);
        final rig = _separateRigs.putIfAbsent(renderObject, _rig);
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        final shapeBounds = Offset.zero & renderObject.paintSize;
        final clipBounds = MatrixUtils.transformRect(shapeToLayer, shapeBounds);
        final sigma = settings.frostSigmaAt(
          devicePixelRatio,
          shapeShortSide: shortSide,
        );
        rig.paint(
          context,
          offset,
          filter: filter.full,
          blur: _passBlur(filter),
          bounds: clipBounds,
          outline: shape.shape
              .getOuterPath(shapeBounds)
              .transform(shapeToLayer.storage),
          reach: sigma != 0 ? sigma * 3 + 1 : 0,
          devicePixelRatio: devicePixelRatio,
        );
      }
    }
    for (final renderObject in _separateRigs.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _separateRigs.remove(renderObject)!.dispose();
    }
    return active.isNotEmpty;
  }

  bool _clipInputsMatch() {
    if (!encodedInputsMatch(shapesWithGeometry)) return false;
    var shapeIndex = 0;
    for (final (_, geometry, _) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shapeIndex >= _cachedClipClasses.length ||
            _cachedClipClasses[shapeIndex] !=
                _backdropClass(shape.appearance)) {
          return false;
        }
        shapeIndex++;
      }
    }
    return shapeIndex == _cachedClipClasses.length;
  }

  /// 0: hidden, 1: needs its own clipped backdrop pass — fading visibility,
  /// or a backdrop transfer that differs from the layer's shared one,
  /// 2: fully visible and covered by the shared union clip.
  int _backdropClass(LiquidGlassAppearance appearance) {
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    if (visibility <= 0) return 0;
    if (visibility >= 1 && _sharesLayerBackdrop(appearance)) return 2;
    return 1;
  }

  void _clearClipCache() {
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipClasses = const [];
  }

  FakeGlassFilterParts _buildBackdropFilter() {
    // Every shape the shared clip covers is fully visible, so the shared
    // transfer always applies at full strength.
    return fakeGlassBackdropFilterParts(
      settings,
      defaultAppearance.copyWith(visibility: 1),
      deviceScale: devicePixelRatio,
      shapeShortSide: _layerShapeShortSide,
    )!;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onCompositing() {
    if (!attached) return;
    runCompositorPoll();
    // Where the glass is on screen decides how its passes are cut, and
    // retained motion moves it without repainting.
    _sharedRig.sync();
    for (final rig in _separateRigs.values) {
      rig.sync();
    }
    // Glass over its copy reads no backdrop: an opacity pass around it needs
    // no seed, and a seeded one would stand in the copy's way.
    compositionSeedSuppressed = true;
    final served = _sharedRig.compose();
    if (!served) compositionSeedSuppressed = false;
    debugDrewOverCopy = served;
  }

  // A glass without a blur, or that is nothing but a blur, needs no seed.
  PassBlur? _passBlur(FakeGlassFilterParts parts) =>
      parts.sigma > 0 && !identical(parts.withoutBlur, fakeGlassIdentityFilter)
      ? PassBlur(
          sigma: parts.sigma,
          tileMode: parts.tileMode,
          withoutBlur: parts.withoutBlur,
        )
      : null;

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (motion.needsRepaint) _refreshRetainedFrame();
  }

  // Paint is over for this frame: draws the retained slot again in place.
  void _refreshRetainedFrame() {
    final slot = _retainedFrameSlot.layer;
    if (slot == null) {
      GlassComposer.repaint(this);
      return;
    }
    final bounds = prepareFrameGeometry();
    slot.removeAllChildren();
    final context = PaintingContext(
      slot,
      paintBounds.shift(retainedPaintOffset),
    );
    _paintFrame(context, retainedPaintOffset, bounds);
  }

  void _releaseGlassLayers() {
    _sharedRig.clear();
    for (final rig in _separateRigs.values) {
      rig.dispose();
    }
    _separateRigs.clear();
  }

  void _releaseLayers() {
    _releaseGlassLayers();
    releaseRetainedEffectLayer();
  }

  @override
  void dispose() {
    _retainedFrameSlot.layer = null;
    _releaseLayers();
    _sharedRig.dispose();
    super.dispose();
  }
}
