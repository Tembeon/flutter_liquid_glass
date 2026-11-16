import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/composer/band_look.dart';
import 'package:liquid_glass_renderer/src/composer/copy_tuning.dart';
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';
import 'package:liquid_glass_renderer/src/composer/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:liquid_glass_renderer/src/composer/read_geometry.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/rendering/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/debug.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/group_matte.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/tiling_drift.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

/// The real glass layer: renders the shapes into a GPU matte and paints the
/// final shader filter over it.
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  /// Creates a glass layer that draws with [finalShaders] and builds its
  /// geometry with [gpuGeometryRenderer].
  RenderLiquidGlassLayer({
    required this.finalShaders,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
  });

  /// The final shaders, one per [FinalShaderVariant.all]; each draw takes
  /// the cheapest that shades it ([debugLiveShader]).
  final List<FragmentShader> finalShaders;

  late final GlassShading _shading = GlassShading(finalShaders);

  /// Whether a layer draws with the variant of its color model family;
  /// false always draws with the general one.
  @visibleForTesting
  static bool debugShaderVariants = true;

  bool _debugWarnedShapeLimit = false;

  void _debugWarnShapeLimitExceeded() {
    if (!kDebugMode || _debugWarnedShapeLimit) return;
    _debugWarnedShapeLimit = true;
    const message =
        'a LiquidGlassLayer has more than '
        '$geometryMaxShapesPerDraw glass shapes that '
        'blend, lie within reach of each other, or carry their own '
        'appearances; the extra shapes are not drawn. Split the glass across '
        'several layers.';
    debugPrint('liquid_glass_renderer: $message');
  }

  // The index of the cheapest final shader that draws the glass: by where it
  // reads its geometry and appearance, and the color model family of its
  // appearances, in a group whose matte holds its tints when [groupTints],
  // beside the band that leads its read when [band]. A look that changed
  // since the read began has no band variant. [geometry] is the one drawn.
  int _variant(
    GlassGeometry geometry, {
    bool band = false,
    bool groupTints = false,
  }) {
    final kind = switch ((
      _usesShapeAppearances || groupTints,
      _usesTintOnlyAppearance || groupTints,
    )) {
      (false, _) => FinalShaderKind.single,
      (true, true) => FinalShaderKind.tint,
      (true, false) => FinalShaderKind.material,
    };
    final models = _colorModelFamily;
    return FinalShaderVariant.indexOf(
      kind,
      models,
      frost: _frostsCopies,
      band:
          band &&
          kind == FinalShaderKind.single &&
          _frostsCopies &&
          models == FinalShaderModels.ios27,
      shape: geometry is ComputedGeometry,
    );
  }

  /// The shader the live filter draws with.
  @visibleForTesting
  FragmentShader get debugLiveShader => finalShaders[_liveDraw.variant];

  /// The color models the layer shades: the direct model alone, one iOS
  /// 27 model in the first slot, or any.
  FinalShaderModels get _colorModelFamily {
    // Only the variants that shade every model part colors.
    if (!debugShaderVariants || settings.effectiveAberration != 0) {
      return FinalShaderModels.all;
    }
    return colorModelFamily(
      _usesShapeAppearances
          ? _shapeAppearances
          : [_uniformAppearance ?? defaultAppearance],
    );
  }

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;

  /// The renderer that draws the layer's geometry, or null before it has
  /// loaded.
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  // MARK: Shader inputs

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// Whether the shapes' appearances differ, so the atlas carries their
  /// looks.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only the shapes' tints differ, so the atlas carries the tint
  /// alone.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The looks beside the atlas, where the shapes' appearances differ.
  @visibleForTesting
  List<ui.Image> get debugLookImages => switch (_drawnGeometry()) {
    AtlasGeometry(:final looks) => looks,
    _ => const [],
  };

  // The material and glow the glass draws with, made again after their
  // inputs change.
  GlassFace? _face;
  List<double>? _glowUniforms;

  void _shadingChanged() {
    _face = null;
    _glowUniforms = null;
  }

  GlassFace get _glassFace {
    if (_face case final face?) return face;
    final appearance = _uniformAppearance ?? defaultAppearance;
    final slots = colorModelSlots(_shapeAppearances, defaultAppearance);
    return _face = GlassFace.of(
      settings: settings,
      appearance: appearance,
      colorModels: slots,
      devicePixelRatio: devicePixelRatio,
      blurs: blurPassSigma > 0,
    );
  }

  List<double> get _glowNow =>
      _glowUniforms ??= glowUniforms(_glow, devicePixelRatio);

  /// [smallestVisibleShortSide], measured when geometry is bound. Starts at
  /// [LiquidGlassRenderObject.largestFittedShortSide] so a bounds query
  /// before the first paint over-allocates rather than clips the blur.
  double _shapeShortSide = LiquidGlassRenderObject.largestFittedShortSide;

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  ///
  /// It is the sigma at a toolbar's size; painting scales it by the size of
  /// the shapes.
  double get blurPassSigma => settings.frostSigmaAt(devicePixelRatio);

  double _frostSigmaForCurrentShapes() {
    final inputs = (settings, devicePixelRatio, _shapeShortSide);
    if (inputs == _frostInputs) return _frostSigma;
    _frostInputs = inputs;
    return _frostSigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: _shapeShortSide,
    );
  }

  (LiquidGlassSettings, double, double)? _frostInputs;
  double _frostSigma = 0;

  /// The color of a [LiquidGlassBackdrop.solid], or null to read the
  /// backdrop; only an opaque color is painted over.
  Color? get solidBackdrop => _solidBackdrop;
  Color? _solidBackdrop;
  set solidBackdrop(Color? value) {
    if (_solidBackdrop == value) return;
    _solidBackdrop = value;
    markNeedsPaint();
  }

  bool get _drawsOverSolid => (_solidBackdrop?.a ?? 0) == 1;

  /// See `LiquidGlassLayer.glow`.
  LiquidGlassGlow? get glow => _glow;
  LiquidGlassGlow? _glow;
  set glow(LiquidGlassGlow? value) {
    if (_glow == value) return;
    _glow = value;
    // Only the glow changes. A retained pass takes it in a new filter,
    // without painting the layer and its shapes.
    _glowUniforms = null;
    if (!_refreshRetainedFilter()) markNeedsPaint();
  }

  /// Hands the final pass's current uniforms to the retained filter layer
  /// and schedules a frame to composite it; false when there is no
  /// retained pass to update, so the layer has to paint.
  bool _refreshRetainedFilter() {
    if (!attached || drawableEmpty || !hasReusableGeometry) return false;
    if (_readsLive) {
      if (!_canRebindFilter) return false;
      _bindFilter();
    } else if (!_rig.hasSlot) {
      return false;
    }
    SchedulerBinding.instance.ensureVisualUpdate();
    return true;
  }

  /// See `LiquidGlassLayer.field`.
  LiquidGlassField? get field => _field;
  LiquidGlassField? _field;
  set field(LiquidGlassField? value) {
    if (_field == value) return;
    _field = value;
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (:mixed, :tintOnly, :uniform) = classifyAppearances(
      appearances,
      defaultAppearance,
    );
    if (_usesShapeAppearances == mixed &&
        _usesTintOnlyAppearance == tintOnly &&
        _uniformAppearance == uniform &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = mixed;
    _usesTintOnlyAppearance = tintOnly;
    _uniformAppearance = uniform;
    _shapeAppearances = List.unmodifiable(appearances);
    _shadingChanged();
  }

  // MARK: Retained frame hooks

  /// Whether the committed shapes exist but none can be drawn by this effect.
  /// It reads the committed geometry, so it stays right when a retained
  /// refresh commits new shapes between paints.
  bool get drawableEmpty => _drawableEmpty ??=
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  bool? _drawableEmpty;

  @override
  void onFrameGeometryCommitted() => _drawableEmpty = null;

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometry != null;

  // Whether the retained filter layer can take new uniforms without a paint.
  bool get _canRebindFilter =>
      _rig.filterLayer != null && !drawableEmpty && hasReusableGeometry;

  @override
  bool get encodesMatte => true;

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    GlassReach reachOf(LiquidGlassSettings settings) => glassReach(
      settings,
      devicePixelRatio: devicePixelRatio,
      contourExtent: 0,
    );
    _shadingChanged();
    if (old.contourWidth != settings.contourWidth ||
        !reachOf(old).covers(reachOf(settings))) {
      needsGeometryUpdate = true;
    }
  }

  @override
  void onAppearanceChanged() => _shadingChanged();

  @override
  void onDevicePixelRatioChanged() {
    _shadingChanged();
    needsGeometryUpdate = true;
  }

  // MARK: Retained matte

  // The glass's geometry, once encoded. An atlas's images are its page's
  // (FlutterGpuGeometryRenderer.renderAtlas), good until the renderer draws
  // another atlas or releases this one. An atlas not drawn yet stands as
  // [AtlasGeometry.none] beside [_atlasToDraw].
  GlassGeometry? _geometry;

  // The tiling of an encoded atlas no draw has read yet. Glass whose reads
  // draw over a group's matte never reads its own, so the atlas is drawn
  // only when a draw of this glass's own matte asks for it.
  Tiling? _atlasToDraw;
  int _encodes = 0;

  // [_geometry], its atlas drawn now if it waits for a draw.
  GlassGeometry? _drawnGeometry() {
    if (_atlasToDraw case final tiling?) {
      _atlasToDraw = null;
      final atlas = _gpuGeometryRenderer!.renderAtlas(tiling);
      _geometry = AtlasGeometry(
        image: atlas.image,
        place: atlas.place,
        looks: atlas.looks,
      );
    }
    return _geometry;
  }

  /// How many times the glass's geometry was encoded, as an atlas or as one
  /// shape for the shader.
  @visibleForTesting
  int debugEncodeCount = 0;

  /// Layer-local bounds of the matte, in logical pixels. Ancestor transforms
  /// do not change them: the compositor applies those, not the shader.
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSize = Size.zero;

  /// The page holding the glass's atlas, where its geometry is one.
  @visibleForTesting
  ui.Image? get debugGeometryImage => switch (_drawnGeometry()) {
    AtlasGeometry(:final image) => image,
    _ => null,
  };

  /// The bounds of the last geometry matte it drew.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  // Whether [_refreshRetainedGeometry] can take the shapes as they are now
  // in place of a paint: the retained frame has a filter and a clip to
  // re-sync, or draws nothing, and the same structure. Topology changes need
  // normal painting to rebuild clip ancestry. It records nothing.
  bool get _refreshTakesFrame =>
      (_rig.filterLayer != null || drawableEmpty) &&
      _rig.hasClip &&
      (_geometry != null || drawableEmpty) &&
      frameState != GlassFrameState.idle &&
      !debugPaintLiquidGlassGeometry &&
      retainedStructureHolds();

  /// Re-encodes the committed shapes before the layer tree is built, without
  /// painting children; false when the frame needs a normal paint.
  bool _refreshRetainedGeometry() {
    if (!_refreshTakesFrame) return false;
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    // Collecting sorts the shapes into paint order, which the question above
    // read as the link held it.
    if (bounds == null || !retainedStructureHolds()) return false;
    commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    // A drawable-empty refresh encodes nothing; the committed list alone
    // is the compositor-translation poll's baseline.
    if (hasDrawableGlass(shapesWithGeometry)) {
      if (!_reusesMatte(bounds, marked: needsGeometryUpdate)) {
        _encodeGeometry(bounds);
      }
    }
    _markGeometryCurrent();
    recordGlassShadows(retainedPaintOffset);
    _syncMaterialFilter(materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  // Whether the shapes or what is encoded beside them changed since the
  // geometry was last encoded.
  bool get _geometryStale =>
      needsGeometryUpdate || link.isDirty || _encodedLean != _leans;

  // Whether the glass's shapes may lean, now and as they were last encoded.
  bool get _leans => settings.refractionFitsShape;
  bool _encodedLean = false;

  // The one place both marks clear once the encoded geometry holds the
  // committed shapes; the shapes rebuild their caches before the link's mark
  // clears, as a rebuild marks it again.
  void _markGeometryCurrent() {
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
  }

  // [marked] is [needsGeometryUpdate] as it stood before the frame cleared it.
  bool _reusesMatte(Rect bounds, {required bool marked}) =>
      !marked && _geometry != null && _reuseUniformlyTranslatedGeometry(bounds);

  void _encodeGeometry(Rect bounds) {
    final result = _buildGeometry(shapesWithGeometry, bounds);
    _encodes++;
    debugEncodeCount++;
    _geometry = result.geometry;
    _geometryMatteBounds = result.matteBounds;
    _materialCenterInMatte = bounds.center;
    _materialSize = bounds.size;
    _rememberEncodedGeometry(bounds);
  }

  void _clearGeometryImage() {
    clearGlassShadows();
    // A page is drawn over only once nothing holds an atlas in it.
    _gpuGeometryRenderer?.releaseAtlas();
    _geometry = null;
    _atlasToDraw = null;
    clearFrameInputs();
  }

  void _rememberEncodedGeometry(Rect bounds) {
    encodedGeometryBounds = bounds;
    rememberFrameInputs();
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final delta = encodedMatteDelta(bounds);
    if (delta == null) return false;
    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
    _materialCenterInMatte += delta;
    _encodedShift += delta;
    _rememberEncodedGeometry(bounds);
    return true;
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    // Set again where the frame paints its material.
    _rig.releaseSlot();
    if (geometryBounds == null) {
      _clearGeometryImage();
      _releaseCompositorFilter();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    switch (frameState) {
      case GlassFrameState.empty:
        _clearGeometryImage();
        _releaseCompositorFilter();
        needsGeometryUpdate = false;
        link.markClean();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          _paintMaterialFilter(
            effectContext,
            effectOffset,
            materialPaintBounds,
          );
          if (recordGlassShadows(effectOffset) case final shadows?) {
            effectContext.addLayer(shadows);
          }
        });
      case GlassFrameState.idle:
        // Keep the last matte and its encode snapshot; ancestor motion
        // stays compositor-only while hidden because the translation poll
        // rebaselines on the committed frame, not on that snapshot. Skip
        // the backdrop filter so idle glass does not sample.
        updateIdleAncestorClips();
        _releaseCompositorFilter();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {});
      case GlassFrameState.active:
        if (_geometryStale || _geometry == null) {
          final marked = needsGeometryUpdate;
          _markGeometryCurrent();
          if (!_reusesMatte(geometryBounds, marked: marked)) {
            _clearGeometryImage();
            _encodeGeometry(geometryBounds);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (debugPaintLiquidGlassGeometry) {
            _debugPaintGeometry(effectContext, effectOffset);
          } else if (_geometry != null) {
            _paintMaterialFilter(
              effectContext,
              effectOffset,
              materialPaintBounds,
            );
            if (recordGlassShadows(effectOffset) case final shadows?) {
              effectContext.addLayer(shadows);
            }
          }
        });
    }
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    _shapeShortSide = switch (smallestVisibleShortSide()) {
      final side? => max(1, side),
      null => LiquidGlassRenderObject.largestFittedShortSide,
    };
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearances = [
      for (final (_, geometry, geometryToLayer) in shapesWithGeometry)
        for (final shape in geometry.shapes)
          if (matteShapeBasis(shape, geometryToLayer) != null) shape.appearance,
    ];
    final appearanceValuesChanged = !listEquals(
      _shapeAppearances,
      appearances,
    );
    _setShapeAppearances(appearances);
    if (_usesShapeAppearances &&
        (!usedShapeAppearances ||
            usedTintOnlyAppearance != _usesTintOnlyAppearance ||
            appearanceValuesChanged)) {
      // The atlas pass writes the looks beside the geometry.
      needsGeometryUpdate = true;
    }
    effectPaintBounds = expandEffectBounds(boundingBox);
    return boundingBox.inflate(materialOutset);
  }

  MatteBinding get _ownMatte => _matteBinding(
    switch (_drawnGeometry()) {
      null => AtlasGeometry.none,
      // Glass that came to look alike keeps its atlas and reads none of the
      // looks beside it.
      AtlasGeometry(:final image, :final place, looks: [_, ...])
          when !_usesShapeAppearances =>
        AtlasGeometry(image: image, place: place),
      final geometry => geometry,
    },
    bounds: _geometryMatteBounds,
  );

  // A matte this glass's draws read, its own or its group's: the bevel and
  // the material's center stay the glass's own.
  MatteBinding _matteBinding(GlassGeometry geometry, {required Rect bounds}) {
    final dpr = devicePixelRatio;
    final alongX = _materialSize.width >= _materialSize.height;
    final pull = settings.effectiveBackdropPull;
    final aberration = settings.effectiveAberration;
    final line =
        (_materialSize.longestSide - _materialSize.shortestSide) / 2 * dpr;
    return MatteBinding(
      geometry: geometry,
      origin: bounds.topLeft * dpr,
      size: bounds.size * dpr,
      halfMinor: _halfMinor,
      refractionHeight: settings.effectiveRefractionHeight * dpr,
      fitsShape: settings.refractionFitsShape,
      materialCenter: _materialCenterInMatte * dpr,
      edge: pull == 0 && aberration == 0
          ? MatteBinding.plainEdge
          : (
              pull: pull * dpr,
              pullHeight: settings.backdropPullHeight * dpr,
              // A square's line is a point, and either sign keeps it one.
              line: alongX ? line : -line,
              halfMinor: _materialSize.shortestSide / 2 * dpr,
              aberration: aberration * dpr,
              aberrationDepth: settings.aberrationDepth * dpr,
            ),
    );
  }

  // MARK: Coordinate mapping

  /// The transform from the layer's coordinates to those its final shader draws
  /// in.
  Matrix4 get shaderCoordinateTransform => filterPassTransform(
    this,
    seeding: compositionProbeSeeding,
    devicePixelRatio: devicePixelRatio,
    translation: compositorTranslation,
  );

  MatteMapping _liveMapping = MatteMapping.none;
  Rect? _backdropBounds;
  bool _mappingMoved = true;
  Object? _mappingInputs;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null) return null;
    final translation = compositorTranslation;
    // Unblurred, the filter input is the backdrop inside the filter's own
    // clip. With a blur pass, Impeller re-rasterizes the blurred input into
    // the filter's coverage, which every clip around the filter narrows: the
    // retained clips between this layer and its shapes, and the clips above
    // this layer up to its pass. The texture is transparent outside it.
    if (blurPassSigma <= 0) return clip;
    var captured = clip.shift(translation);
    final ancestorClips = [
      retainedClipBounds,
      localPaintClipAbove(this),
    ];
    for (final ancestorClip in ancestorClips) {
      if (ancestorClip != null) captured = captured.intersect(ancestorClip);
    }
    return captured.shift(-translation);
  }

  /// The [backdropSampleBounds] the live filter last mapped.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  // Maps the live filter's fragments into the matte; false where the
  // mapping holds.
  bool _syncMapping() {
    // Scaled to nothing, it draws nothing: the last mapping holds.
    final toMatte = Matrix4.tryInvert(shaderCoordinateTransform);
    if (toMatte == null) return false;
    final backdropBounds = backdropSampleBounds;
    final mapping = MatteMapping.of(
      toMatte,
      devicePixelRatio: devicePixelRatio,
      backdropBounds: backdropBounds,
    );
    final changed = mapping != _liveMapping;
    _liveMapping = mapping;
    _backdropBounds = backdropBounds;
    return changed;
  }

  // MARK: Native filter

  // The live read: a filter in a clip.
  final _rig = BackdropRig();

  /// The backdrop filter layer it last drew through.
  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _rig.filterLayer;

  /// The layer-local clip of the native glass filter, without the exterior
  /// shadows.
  @visibleForTesting
  Rect? debugFilterBounds;
  Rect? _filterMaterialBounds;
  Offset _filterPaintOffset = Offset.zero;

  // The native filter clip, kept on stable pixel buckets in the translated
  // frame so retained compositor motion does not resize its render target.
  Rect? get _filterClip {
    final bounds = _filterMaterialBounds;
    if (bounds == null) return null;
    final translation = compositorTranslation;
    return bounds
        .shift(translation)
        .expandToPixelBuckets(devicePixelRatio)
        .shift(-translation);
  }

  GlassDraw get _liveDraw => _liveDrawOver(_ownMatte);

  GlassDraw _liveDrawOver(MatteBinding matte) => GlassDraw(
    variant: _variant(_geometry ?? AtlasGeometry.none),
    face: _glassFace,
    glow: _glowNow,
    matte: matte,
    mapping: _liveMapping,
  );

  void _bindFilter() => _rig.bindFilter(_liveFilterNow());

  ImageFilter _liveFilterNow() {
    final draw = _liveDraw;
    final sigma = _frostSigmaForCurrentShapes();
    if (_liveFilter case (final held, final heldSigma, final filter)
        when heldSigma == sigma && held == draw) {
      return filter;
    }
    final filter = _frosted(_shading.filter(draw), sigma);
    _liveFilter = (draw, sigma, filter);
    return filter;
  }

  static ImageFilter _frosted(ImageFilter shader, double sigma) => sigma > 0
      ? ImageFilter.compose(
          inner: ImageFilter.blur(
            tileMode: glassBlurTileMode,
            sigmaX: sigma,
            sigmaY: sigma,
          ),
          outer: shader,
        )
      : shader;

  void _dropFilterCache() => _liveFilter = null;

  // Shared by paint and the retained geometry refresh; it never paints
  // children.
  Rect _syncMaterialFilter(Rect materialBounds, Offset offset) {
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    _rig.clipTo(filterBounds.shift(offset));
    if (drawableEmpty) {
      _rig.releaseFilter();
      _dropFilterCache();
    } else {
      _syncMapping();
      if (_readsLive) _bindFilter();
    }
    return filterBounds;
  }

  void _paintMaterialFilter(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    if (!attached) return;
    if (_drawsOverSolid) {
      shadowsUnderGlass = false;
      _paintOverSolid(context, offset, materialBounds);
      return;
    }
    final filterBounds = _syncMaterialFilter(materialBounds, offset);
    final copies = GlassCopies.enabled && !drawableEmpty;
    // Only glass over its copy can cover the shadows (see _placeShadows).
    if (!copies) shadowsUnderGlass = false;

    void paintLive(PaintingContext context, Offset offset) {
      _rig.paintLive(
        context,
        offset,
        bounds: filterBounds,
        drawsFilter: !drawableEmpty,
      );
    }

    // The live filter, or the glass painted over a copy of what lies under
    // it: compositing picks one per frame.
    _rig.paintSite(
      context,
      offset,
      site: copies ? layer : null,
      live: paintLive,
    );
  }

  // Over a solid backdrop the glass is a rect painted with the final shader.
  // A paint's fragment coordinates are the logical canvas coordinates it is
  // recorded in: the layer's own shifted by [offset]. The matte is the
  // layer's own coordinates in device pixels, so neither the pass nor any
  // ancestor transform enters the mapping.
  void _paintOverSolid(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    _releaseCompositorFilter();
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    if (drawableEmpty) return;
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    debugFilterBounds = filterBounds;
    final dpr = devicePixelRatio;
    final color = _solidBackdrop!.withValues(
      colorSpace: ColorSpace.extendedSRGB,
    );
    final live = _liveDraw;
    _shading.paintRect(
      context.canvas,
      filterBounds.shift(offset),
      live.copyWith(
        mapping: MatteMapping((
          dpr,
          0,
          0,
          dpr,
          -offset.dx * dpr,
          -offset.dy * dpr,
        ), live.mapping.backdropBounds),
        reading: SolidReading(
          color,
          Size(
            max(filterBounds.width * dpr, 1),
            max(filterBounds.height * dpr, 1),
          ),
        ),
      ),
    );
  }

  /// Drops the native backdrop filter and its clip.
  void _releaseCompositorFilter() {
    _rig.clear();
    _dropFilterCache();
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    _mappingMoved = true;
    // Retained geometry follows the move in onPreparing.
    if (repaintsOnMove) GlassComposer.repaint(this);
  }

  // Glass with nothing to reuse repaints.
  @override
  bool get repaintsOnMove => !hasReusableGeometry && !hasReusableIdleContents;

  @override
  void onPreparing() => runCompositorPoll();

  // Nothing around it changed: what it read of its place holds.
  @override
  void onResting() {}

  // A pass that changes size counts the frames it holds still in the poll. A
  // shape under the glass's own repaint boundary changes nothing around it.
  // Hidden glass paints nothing that clears either mark, and has nothing a
  // poll could move.
  @override
  bool get mayRest => frameState == GlassFrameState.idle || !_geometryStale;

  double get _halfMinor =>
      _geometryMatteBounds.shortestSide * devicePixelRatio / 2;

  // The atlas texel for texel at the geometry buffer's corner.
  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (debugGeometryImage case final atlas?) {
      context.canvas
        ..save()
        ..translate(
          offset.dx + _geometryMatteBounds.left,
          offset.dy + _geometryMatteBounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(atlas, Offset.zero, Paint()..blendMode = BlendMode.src)
        ..restore();
    }
  }

  @override
  void dispose() {
    _rig.dispose();
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _groupMatte?.dispose();
    _groupMatte = null;
    super.dispose();
  }

  // MARK: Geometry

  /// Whether its geometry changed since it last drew it.
  @protected
  bool needsGeometryUpdate = true;

  // The shapes of the latest encode.
  ShapeSet _shapes = ShapeSet.empty;

  final _drift = TilingDrift();

  @override
  double get materialOutset => _contourOutset;

  double get _contourOutset {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// How far outside the material the composed filter reads the backdrop:
  /// the blur kernel (3 sigma), the peak edge displacement of shapes that
  /// fit in [material] including its dispersion, and, with
  /// [LiquidGlassSettings.backdropShrink] or
  /// [LiquidGlassSettings.backdropPull], the extra content revealed on the
  /// face. A copy of the backdrop must contain this reach or the filter
  /// samples its own edge.
  double backdropSamplingReach(Rect material) {
    // The final shader's edge shift (displacementMagnitude): no wider
    // than half a shape's shorter side when refraction fits the shape, and
    // than 0.65 of it otherwise. No shape inside the material has a shorter
    // side longer than the material's.
    final amount = settings.effectiveDisplacementScale;
    final halfMinor = min(material.width, material.height) / 2;
    final shift = min(
      amount,
      settings.refractionFitsShape ? halfMinor : 1.3 * halfMinor,
    );
    final frostSigma = _frostSigmaForCurrentShapes();
    final blur = frostSigma > 0 ? frostSigma * 3 + 1 / devicePixelRatio : 0.0;
    final displacement = shift * (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur +
        displacement +
        revealed +
        settings.effectiveBackdropPull +
        settings.effectiveAberration;
  }

  // The geometry of [geometries]: worked out by the shader where they are
  // one shape of one look, else drawn into the frame's page.
  ({GlassGeometry geometry, Rect matteBounds}) _buildGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    final dpr = devicePixelRatio;
    final aaPadding = matteRoom(dpr, _contourOutset);
    // The geometry buffer is in this layer's local coordinates. Ancestor
    // transforms are applied once by the compositor; baking them in would
    // apply scale and rotation twice.
    final boundsInMatteSpace = bounds.inflate(aaPadding).snapToPixels(dpr);
    if (boundsInMatteSpace.isEmpty) {
      throw StateError('Cannot render empty liquid-glass geometry.');
    }

    _encodedShift = Offset.zero;
    var shapes = ShapeSet.encode(
      geometries,
      devicePixelRatio: dpr,
      turnsToCenter: _encodedLean = _leans,
    );
    if (shapes.count == 0) {
      throw StateError('No invertible liquid-glass shapes to render.');
    }
    // A field takes its looks from one draw of shapes.
    if (_usesShapeAppearances &&
        _field != null &&
        shapes.count > geometryMaxShapesPerDraw) {
      _debugWarnShapeLimitExceeded();
      shapes = shapes.take(geometryMaxShapesPerDraw);
    }
    _shapes = shapes;
    final looks = _usesShapeAppearances
        ? shapeLooks(
            shapes.appearances,
            colorModels: colorModelSlots(_shapeAppearances, defaultAppearance),
            tintOnly: _usesTintOnlyAppearance,
          )
        : null;
    final body = GlassBody(
      shapes: shapes.count,
      field: _field != null,
      looks: looks != null,
      leans: shapes.leans,
    );
    renderer.releaseAtlas();
    if (geometryKindOf([body]) is ComputedShape) {
      _atlasToDraw = null;
      _drift.reset();
      return (
        geometry: ComputedGeometry(
          ShapeSet.join([(shapes, -boundsInMatteSpace.topLeft * dpr)]),
        ),
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          (boundsInMatteSpace.width * dpr).ceil() / dpr,
          (boundsInMatteSpace.height * dpr).ceil() / dpr,
        ),
      );
    }
    final reach = glassReach(
      settings,
      devicePixelRatio: dpr,
      contourExtent: aaPadding * dpr,
    );

    // Shapes that drift keep the tiling of an earlier frame while each stays
    // within its slack, in that frame's buffer: only the pass runs again.
    final tiling = _drift.advance(
      shapes,
      bounds: bounds,
      padded: boundsInMatteSpace,
      padding: aaPadding,
      devicePixelRatio: dpr,
      field: _field,
      reach: reach,
      looks: looks,
    );
    _atlasToDraw = tiling;
    if (tiling.droppedShapes > 0) _debugWarnShapeLimitExceeded();
    return (
      geometry: AtlasGeometry.none,
      matteBounds: Rect.fromLTWH(
        _drift.bounds.left,
        _drift.bounds.top,
        _drift.width / dpr,
        _drift.height / dpr,
      ),
    );
  }
}

/// What a [RenderLiquidGlassLayer] drew, for the package's tests.
extension RenderLiquidGlassLayerDebug on RenderLiquidGlassLayer {
  /// What the glass last drew over a copy of a read.
  GlassDraw? get debugReadDraw => _debugReadDraw;

  /// The page this glass reads in the last composited frame, if it reads one.
  PageCopy? get debugPage => _debugPage;

  /// What the live filter draws.
  GlassDraw get debugLiveDraw => _liveDraw;

  /// Where the shader takes the glass's geometry from.
  GlassGeometry? get debugGeometry => _drawnGeometry();

  /// Where the atlas lies in [debugGeometryImage].
  AtlasPlace get debugGeometryPlace => switch (_drawnGeometry()) {
    AtlasGeometry(:final place) => place,
    _ => AtlasLayout.unplaced,
  };

  /// The tiling of the latest atlas.
  Tiling? get debugTiling => _drift.tiling;
}
