// ignore_for_file: cascade_invocations

import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/internal/glass_blur.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/composer/scene_out.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/internal/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/internal/shader_filter.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_render_object_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_backdrop.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/matte_scale_flag.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Represents a layer of multiple [LiquidGlass] shapes or
/// [LiquidGlassBlendGroup]s that have shared [LiquidGlassSettings] and will be
/// rendered together.
///
/// If you create a [LiquidGlassLayer] with one or more [LiquidGlass] or
/// [LiquidGlassBlendGroup] widgets, the liquid glass effect will be rendered
/// where this layer is.
///
/// Widgets between the layer and its [LiquidGlass] widgets that paint, such
/// as a colored background, paint over the glass: the layer draws all of its
/// glass before its child.
///
/// ## Example
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlassLayer(
///     child: Column(
///       children: [
///         LiquidGlass(
///           shape: LiquidRoundedSuperellipse(
///             borderRadius: 10,
///           ),
///           child: const SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///         const SizedBox(height: 100),
///         LiquidGlassBlendGroup(
///           blend: 20,
///           child: Row(
///             children: [
///               LiquidGlass.grouped(
///                 shape: const LiquidOval(),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///               LiquidGlass.grouped(
///                 shape: const LiquidRoundedSuperellipse(
///                   borderRadius: 20,
///                 ),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///             ],
///           ),
///         ),
///       ],
///     ),
///   );
/// }
/// ```
class LiquidGlassLayer extends StatefulWidget {
  /// Creates a new [LiquidGlassLayer] with the given [child] and [settings].
  const LiquidGlassLayer({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    this.defaultAppearance,
    this.fake = false,
    this.field,
    this.backdrop = const LiquidGlassBackdrop.read(),
    this.glow,
    this.analyticGeometry = false,
    super.key,
  }) : live = null;

  /// Creates a [LiquidGlassLayer] whose settings, field and glow follow
  /// [frame].
  ///
  /// Every notification writes the new frame straight into the layer's
  /// render object; nothing rebuilds. Widgets below that read the settings
  /// from the tree (`LiquidGlassSettings.of`, a nested [LiquidGlass] that
  /// opens its own layer) see those of the frame the layer last built with.
  /// A layer that draws fake glass, or whose shaders are still loading,
  /// draws neither the field nor the glow and rebuilds only when the
  /// frame's settings change.
  const LiquidGlassLayer.live({
    required ValueListenable<LiquidGlassLayerFrame> frame,
    required this.child,
    this.defaultAppearance,
    this.fake = false,
    this.backdrop = const LiquidGlassBackdrop.read(),
    this.analyticGeometry = false,
    super.key,
  }) : live = frame,
       settings = const LiquidGlassSettings(),
       field = null,
       glow = null;

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// Appearance inherited by shapes that do not provide an override.
  ///
  /// When omitted, the fitted iOS 27 regular appearance follows the ambient
  /// platform brightness.
  final LiquidGlassAppearance? defaultAppearance;

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  ///
  /// The layer also uses [FakeGlass] when Impeller shader filters or Flutter
  /// GPU are unavailable, for example on Skia.
  final bool fake;

  /// The distance field of the one body this layer's shapes form, when the
  /// caller has fused them already.
  ///
  /// The layer then shades the body the field describes instead of its
  /// shapes' outlines and blend groups. See [LiquidGlassField].
  final LiquidGlassField? field;

  /// Where the glass takes what it shows through: read behind the layer by
  /// default, or a backdrop the caller knows. See [LiquidGlassBackdrop].
  final LiquidGlassBackdrop backdrop;

  /// The glow a finger raises on one of this layer's shapes, or null for
  /// none.
  ///
  /// The widget that owns the glass computes it each frame. A new glow
  /// changes only the final pass's uniforms: no geometry pass runs, and a
  /// layer whose retained filter reads the backdrop does not repaint.
  final LiquidGlassGlow? glow;

  /// Whether the final pass works out this layer's shapes itself while they
  /// change, instead of drawing them into the matte first.
  ///
  /// A frame shaded this way records and submits no geometry pass, which
  /// cuts UI-thread time while a shape moves or resizes. The GPU pays
  /// instead: the final shader works out the shapes at every pixel rather
  /// than once per matte texel. For one small shape that costs next to
  /// nothing; for several blended shapes or large glass it costs much more
  /// GPU time and energy than the matte. Turn it on for small glass that
  /// moves often on a busy UI thread, such as a slider thumb or a segmented
  /// control's lens; leave it off for sheets and blend groups. Once the
  /// shapes stop, the layer draws the matte and shades from it again.
  ///
  /// A layer with shapes that differ in appearance, a field (its own or a
  /// live frame's), more than eight shapes or mostly empty space keeps the
  /// matte either way.
  ///
  /// Defaults to false.
  final bool analyticGeometry;

  /// The frames of a layer made with [LiquidGlassLayer.live], or null for
  /// one that uses [settings], [field] and [glow].
  final ValueListenable<LiquidGlassLayerFrame>? live;

  /// Whether there is a [LiquidGlassLayer] in the widget tree above the given
  /// [context].
  static bool existsIn(BuildContext context, {bool watch = true}) {
    return LiquidGlassRenderScope.maybeOf(context, watch: watch) != null;
  }

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer>
    with SingleTickerProviderStateMixin {
  static final List<String> _fakeSurfaceShaderAssets = [
    ShaderKeys.fakeGlassSurface,
  ];

  late final GeometryRenderLink _link = GeometryRenderLink();

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  final List<FlutterGpuGeometryRenderer> _retiredGpuGeometryRenderers = [];
  bool _triedGpuGeometryRenderer = false;
  bool _gpuInitializationScheduled = false;
  bool _loggedFallback = false;

  // Fake and real subtrees never coexist, so one key keeps the user's subtree
  // alive across a renderer swap without ever being mounted twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  // The real layer's render object, which a live frame is written into.
  final _shapesKey = GlobalKey(debugLabel: 'LiquidGlassLayer.shapes');

  LiquidGlassSettings get _settings =>
      widget.live?.value.settings ?? widget.settings;

  // The settings the fake or loading subtree was built with.
  LiquidGlassSettings? _builtSettings;
  LiquidGlassField? get _field => widget.live?.value.field ?? widget.field;
  LiquidGlassGlow? get _glow => widget.live?.value.glow ?? widget.glow;

  bool _rebuildPending = false;

  void _onLiveFrame() {
    final frame = widget.live!.value;
    final layer = _shapesKey.currentContext?.findRenderObject();
    if (layer is! RenderLiquidGlassLayer) {
      if (frame.settings != _builtSettings) _rebuild();
      return;
    }
    layer
      ..settings = frame.settings
      ..field = frame.field
      ..glow = frame.glow;
  }

  // A frame may come from a descendant while the framework builds, lays out
  // or paints, when this layer can no longer be marked to build.
  void _rebuild() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_rebuildPending) return;
    _rebuildPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildPending = false;
      if (mounted) setState(() {});
    });
  }

  void _logDebugFallback(String message) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint('liquid_glass_renderer: $message');
  }

  void _tryCreateCachedGpuGeometryRenderer() {
    if (widget.fake ||
        !ImageFilter.isShaderFilterSupported ||
        _triedGpuGeometryRenderer) {
      return;
    }
    final renderer = FlutterGpuGeometryRenderer.tryCreateCached(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    if (renderer == null) return;
    _gpuGeometryRenderer = renderer;
    _triedGpuGeometryRenderer = true;
  }

  void _scheduleGpuGeometryRendererInitialization() {
    if (_triedGpuGeometryRenderer || _gpuInitializationScheduled) return;
    _gpuInitializationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _gpuInitializationScheduled = false;
      if (!mounted || widget.fake || _triedGpuGeometryRenderer) return;

      _triedGpuGeometryRenderer = true;
      try {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        if (!mounted || widget.fake) {
          renderer.dispose();
          return;
        }
        _gpuGeometryRenderer = renderer;
      } on Object catch (error) {
        if (!mounted) return;
        _logDebugFallback(
          'Flutter GPU is unavailable; LiquidGlassLayer is using FakeGlass. '
          'Enable Impeller and Flutter GPU for the full glass effect. $error',
        );
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _tryCreateCachedGpuGeometryRenderer();
    widget.live?.addListener(_onLiveFrame);
  }

  @override
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.live, widget.live)) {
      oldWidget.live?.removeListener(_onLiveFrame);
      widget.live?.addListener(_onLiveFrame);
    }
    if (oldWidget.fake && !widget.fake) {
      _tryCreateCachedGpuGeometryRenderer();
    }
    if (!oldWidget.fake && widget.fake) {
      final renderer = _gpuGeometryRenderer;
      _gpuGeometryRenderer = null;
      _triedGpuGeometryRenderer = false;
      if (renderer != null) {
        // The outgoing real subtree still samples these textures this frame;
        // dispose them after it.
        _retiredGpuGeometryRenderers.add(renderer);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_retiredGpuGeometryRenderers.remove(renderer)) return;
          renderer.dispose();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.live?.removeListener(_onLiveFrame);
    _gpuGeometryRenderer?.dispose();
    for (final renderer in _retiredGpuGeometryRenderers) {
      renderer.dispose();
    }
    _retiredGpuGeometryRenderers.clear();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultAppearance =
        widget.defaultAppearance ??
        LiquidGlassAppearance.ios27Regular(
          brightness: MediaQuery.platformBrightnessOf(context),
        );
    final shaderFiltersSupported = ImageFilter.isShaderFilterSupported;
    if (!widget.fake && shaderFiltersSupported) {
      // Keep uncached GPU setup out of build: acquiring the engine's context
      // may take startup time. Explicit precaching can load these resources
      // before any frame; rendering a frame is not a prerequisite.
      _scheduleGpuGeometryRendererInitialization();
    }
    _builtSettings = _settings;
    final gpuRenderer = _gpuGeometryRenderer;
    final useFake =
        widget.fake || !shaderFiltersSupported || gpuRenderer == null;
    final matteScale = resolveMatteScale(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    if (useFake) {
      if (!widget.fake && !shaderFiltersSupported && kDebugMode) {
        _logDebugFallback(
          'Impeller shader filters are unavailable; LiquidGlassLayer is using '
          'FakeGlass. Enable Impeller and Flutter GPU for the full effect.',
        );
      }

      return _buildFakeLayer(
        defaultAppearance: defaultAppearance,
        settings: _settings,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: _settings,
        defaultAppearance: defaultAppearance,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: MultiShaderBuilder(
            assetKeys: FinalShaderVariant.assetKeys,
            (context, shaders, child) {
              return _RawShapes(
                key: _shapesKey,
                finalShaders: shaders,
                field: _field,
                solidBackdrop: solidColorOf(widget.backdrop),
                glow: _glow,
                analyticGeometry: widget.analyticGeometry,
                settings: _settings,
                defaultAppearance: defaultAppearance,
                link: _link,
                gpuGeometryRenderer: gpuRenderer,
                matteScale: matteScale,
                child: child!,
              );
            },
            child: KeyedSubtree(key: _childKey, child: widget.child),
          ),
        ),
      ),
    );
  }

  Widget _buildFakeLayer({
    required LiquidGlassAppearance defaultAppearance,
    required LiquidGlassSettings settings,
    required Widget child,
  }) {
    // A boundary of its own, as the real layer has: ancestor motion moves
    // the retained surfaces without recording them again.
    Widget buildFakeSurfaceLayer(
      FragmentShader? surfaceShader,
    ) {
      return RepaintBoundary(
        child: LiquidGlassRenderScope(
          settings: settings,
          defaultAppearance: defaultAppearance,
          fake: true,
          child: InheritedGeometryRenderLink(
            link: _link,
            child: ConsolidatedFakeGlassLayer(
              link: _link,
              settings: settings,
              defaultAppearance: defaultAppearance,
              surfaceShader: surfaceShader,
              child: child,
            ),
          ),
        ),
      );
    }

    return MultiShaderBuilder(
      assetKeys: _fakeSurfaceShaderAssets,
      (_, shaders, _) => buildFakeSurfaceLayer(shaders.firstOrNull),
      child: buildFakeSurfaceLayer(null),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.finalShaders,
    required this.field,
    required this.solidBackdrop,
    required this.glow,
    required this.analyticGeometry,
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    required this.matteScale,
    this.gpuGeometryRenderer,
    super.key,
  });

  final List<FragmentShader> finalShaders;
  final LiquidGlassField? field;

  final Color? solidBackdrop;
  final LiquidGlassGlow? glow;
  final bool analyticGeometry;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;

  /// How many matte pixels one low-res matte texel covers in each direction
  /// (see `liquidGlassMatteScale`).
  final int matteScale;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        finalShaders: finalShaders,
        settings: settings,
        defaultAppearance: defaultAppearance,
        link: link,
        gpuGeometryRenderer: gpuGeometryRenderer,
        matteScale: matteScale,
      )
      ..field = field
      ..solidBackdrop = solidBackdrop
      ..glow = glow
      ..analyticGeometry = analyticGeometry;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..gpuGeometryRenderer = gpuGeometryRenderer
      ..matteScale = matteScale
      ..field = field
      ..solidBackdrop = solidBackdrop
      ..glow = glow
      ..analyticGeometry = analyticGeometry;
  }
}

/// One frame of a live [LiquidGlassLayer]: what it shades with.
@immutable
class LiquidGlassLayerFrame {
  /// Describes one frame of a layer.
  const LiquidGlassLayerFrame({
    this.settings = const LiquidGlassSettings(),
    this.field,
    this.glow,
  });

  /// See [LiquidGlassLayer.settings].
  final LiquidGlassSettings settings;

  /// See [LiquidGlassLayer.field].
  final LiquidGlassField? field;

  /// See [LiquidGlassLayer.glow].
  final LiquidGlassGlow? glow;
}

/// The real glass layer: renders the shapes into a GPU matte and paints the
/// final shader filter over it.
@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin
    implements ReadPainter {
  RenderLiquidGlassLayer({
    required this.finalShaders,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    required int matteScale,
    this._gpuGeometryRenderer,
  }) : _matteScale = matteScale {
    _updateShaderSettings();
  }

  /// The final shaders, one per [FinalShaderVariant.all]; the layer draws
  /// with the cheapest that shades its frame ([renderShader]).
  final List<FragmentShader> finalShaders;

  /// Whether a layer draws with the variant of its color model family;
  /// false always draws with the general one.
  @visibleForTesting
  static bool debugShaderVariants = true;

  // Shaders whose common uniforms predate the layer's latest settings, and
  // the last shader picked: a different pick changes the shader inputs.
  final Set<FragmentShader> _staleShaders = Set.identity();
  FragmentShader? _lastShader;

  /// Whether a frame whose geometry changes may shade the shapes
  /// analytically (see [LiquidGlassLayer.analyticGeometry]): the final
  /// shader evaluates them where each fragment is, so the frame encodes no
  /// matte and submits no Flutter GPU pass. [debugAnalyticIneligibility]
  /// names why a frame encoded a matte anyway. [analyticRestFrames] frames
  /// after the geometry last changed, the layer encodes one matte and rests
  /// on it, which is cheaper to shade.
  bool analyticGeometry = false;

  /// The most shapes an analytic frame evaluates (ANALYTIC_MAX_SHAPES).
  static const int analyticMaxShapes = 8;

  /// How many frames after its latest analytic frame the layer encodes a
  /// matte to rest on.
  static const int analyticRestFrames = 2;

  /// The most shape tests an analytic frame spends where no shape is: the
  /// matte's device pixels outside the shapes' boxes, times the shapes.
  /// Each such pixel tests every shape's box before it finds itself empty,
  /// so a sparse layer (a page of buttons in one layer) costs the GPU more
  /// than encoding its low-res matte, a quarter or a sixteenth of the pixels.
  /// Glass that fills its rect, however large, stays analytic, and so do
  /// rows that fill most of theirs. The bound sits between the two on a
  /// Mali-G78 phone: a column of eight round buttons over a page is sparse,
  /// eight full-width rows and a sheet are not.
  @visibleForTesting
  static int analyticMaxEmptyTests = 6000000;

  bool _analytic = false;

  /// Whether the latest geometry frame is shaded analytically.
  @visibleForTesting
  bool get debugAnalytic => _analytic;

  /// Why the latest geometry frame encoded a matte, or null when it was
  /// analytic.
  @visibleForTesting
  String? get debugAnalyticIneligibility => _analyticIneligibility;
  String? _analyticIneligibility;

  // Whether the layer asked for a matte frame to rest on, and which analytic
  // frame's quiet frames are being counted.
  bool _restRequested = false;
  int _analyticGeneration = 0;

  // Sampler 0 takes its filtering from the image bound to it; an analytic
  // frame has no matte to bind, so it binds this.
  static final ui.Image _placeholder = () {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    return recorder.endRecording().toImageSync(1, 1);
  }();

  /// How many matte pixels one low-res matte texel covers in each direction:
  /// 2 or 4 (see `liquidGlassMatteScale`). The final shaders work for both,
  /// because the scale is passed in as a uniform.
  int _matteScale;
  int get matteScale => _matteScale;
  set matteScale(int value) {
    if (_matteScale == value) return;
    _matteScale = value;
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  bool _debugWarnedShapeLimit = false;

  void _debugWarnShapeLimitExceeded() {
    if (!kDebugMode || _debugWarnedShapeLimit) return;
    _debugWarnedShapeLimit = true;
    const message =
        'a LiquidGlassLayer has more than '
        '${LiquidGlassBlendGroup.maxShapesPerCluster} glass shapes that '
        'blend, lie within reach of each other, or carry their own '
        'appearances; the extra shapes are not drawn. Split the glass across '
        'several layers.';
    LiquidGlassRenderObject.logger.warning(message);
    debugPrint('liquid_glass_renderer: $message');
  }

  /// The cheapest final shader that shades the layer's frame: by where it
  /// reads its geometry and appearance, and the color model family of its
  /// appearances. Its common uniforms are brought up to date when it is
  /// picked.
  FragmentShader get renderShader {
    final kind = switch ((
      _analytic,
      _usesShapeAppearances || _groupTints,
      _usesTintOnlyAppearance || _groupTints,
    )) {
      (true, _, _) => FinalShaderKind.analytic,
      (false, false, _) => FinalShaderKind.single,
      (false, true, true) => FinalShaderKind.tint,
      (false, true, false) => FinalShaderKind.material,
    };
    final shader =
        finalShaders[FinalShaderVariant.indexOf(
          kind,
          _colorModelFamily,
          frost: _frostsCopies,
          band: _drawsBand && kind == FinalShaderKind.single,
        )];
    if (_staleShaders.remove(shader)) {
      _writeCommonShaderUniforms(
        shader,
        _uniformAppearance ?? defaultAppearance,
        _materialCenterInMatte,
        _colorModelSlots(_shapeAppearances),
      );
    }
    if (!identical(shader, _lastShader)) {
      _lastShader = shader;
      _noteShaderInputs();
    }
    return shader;
  }

  // Whether the shader may frost the copy it draws over, which picks a
  // variant that can. Settings pick it, as they pick the color models, so
  // a change rewrites the uniforms.
  bool get _frostsCopies =>
      debugShaderFrost && settings.frost > 0 && settings.dispersion == 0;

  /// The color models the layer shades: the direct model alone, one iOS
  /// 27 model in the first slot, or any.
  FinalShaderModels get _colorModelFamily {
    if (!debugShaderVariants) return FinalShaderModels.all;
    final shaded = _usesShapeAppearances
        ? _shapeAppearances
        : [_uniformAppearance ?? defaultAppearance];
    final first = shaded.first.colorModel.parameters;
    for (final appearance in shaded) {
      if (appearance.colorModel.parameters != first) {
        return FinalShaderModels.all;
      }
    }
    return first == null ? FinalShaderModels.direct : FinalShaderModels.ios27;
  }

  /// The analytic variants, which an analytic frame writes its shapes into.
  Iterable<FragmentShader> get _analyticShaders => [
    for (final models in FinalShaderModels.values)
      finalShaders[FinalShaderVariant.indexOf(
        FinalShaderKind.analytic,
        models,
      )],
  ];

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
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
  bool _needsMaterialUpdate = false;

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only tint differs, allowing one filtered appearance lookup.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  bool _shaderInputsChanged = true;

  // Counts the changes of a uniform or sampler of [renderShader], for what
  // holds a filter apart from [takeShaderInputsChanged].
  int _shaderInputsRevision = 0;

  void _noteShaderInputs() {
    _shaderInputsChanged = true;
    _shaderInputsRevision++;
  }

  /// Whether a uniform or sampler of [renderShader] changed since the last
  /// call, which also resets it.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused while this stays false.
  @protected
  bool takeShaderInputsChanged() {
    final changed = _shaderInputsChanged;
    _shaderInputsChanged = false;
    return changed;
  }

  void _updateShaderSettings() {
    _noteShaderInputs();
    _staleShaders.addAll(finalShaders);
    // Reading renderShader writes the picked shader's uniforms; the others
    // are written when a frame picks them.
    renderShader;
  }

  /// The layer's adaptive color models in shader slot order.
  ///
  /// `uColorModelParams` holds at most three distinct models; extra models
  /// fold onto the first slot. The direct model needs no slot: it always
  /// takes code 0.
  List<GlassColorParameters> _colorModelSlots(
    List<LiquidGlassAppearance> appearances,
  ) {
    final slots = <GlassColorParameters>[];
    void add(LiquidGlassAppearance appearance) {
      final parameters = appearance.colorModel.parameters;
      if (parameters != null &&
          !slots.contains(parameters) &&
          slots.length < 3) {
        slots.add(parameters);
      }
    }

    // The shaded models first, so a layer of one iOS 27 model has it in the
    // first slot, which its one-model variant reads.
    appearances.forEach(add);
    add(defaultAppearance);
    return List.unmodifiable(slots);
  }

  /// The shader's model code for [model]: 0 direct, 1..3 slot index.
  double _colorModelCode(
    LiquidGlassColorModel model,
    List<GlassColorParameters> slots,
  ) {
    final parameters = model.parameters;
    if (parameters == null) return 0;
    // The slots hold the appearances' own parameter objects, so a model
    // finds its slot by identity before a field-by-field comparison.
    var index = slots.indexWhere((slot) => identical(slot, parameters));
    if (index < 0) index = slots.indexOf(parameters);
    // Models beyond the third fold onto the first slot.
    return (index.clamp(0, 2) + 1).toDouble();
  }

  void _writeCommonShaderUniforms(
    FragmentShader shader,
    LiquidGlassAppearance appearance,
    Offset materialCenter,
    List<GlassColorParameters> colorModels,
  ) {
    // The final shader fades the whole material with visibility, so the
    // color factors are written at full strength.
    shader.setFloatUniforms(initialIndex: _FinalUniforms.tint, (value) {
      value
        ..setColor(appearance.tint)
        ..setFloats([
          settings.effectiveDisplacementScale * devicePixelRatio,
          settings.dispersion,
          settings.effectiveEdgeDistanceRange * devicePixelRatio,
          settings.highlight,
          1 - settings.effectiveBackdropShrink,
          appearance.colorModel.saturation,
        ])
        ..setOffset(
          const Offset(0, 1),
        )
        ..setColor(const Color.fromARGB(255, 255, 255, 255))
        ..setColor(
          Color.fromARGB(
            (settings.contourStrength.clamp(0.0, 1.0) * 255).round(),
            0,
            0,
            0,
          ),
        )
        // Rim geometry the presets share; see [GlassRim].
        ..setFloats([
          GlassRim.bevelShadowDirectionality,
          0, // bevel shadow size response
          GlassRim.highlightWidth * devicePixelRatio,
          GlassRim.highlightOppositeStrength,
        ])
        ..setFloats([
          settings.contourWidth * devicePixelRatio,
          0, // contour transmittance
          settings.contourDirectionality,
        ])
        ..setFloats([
          0, // contour offset
          materialCenter.dx * devicePixelRatio,
          materialCenter.dy * devicePixelRatio,
          GlassRim.highlightWrap,
        ])
        ..setFloats([
          appearance.colorModel.transmissionGamma,
          appearance.colorModel.vibrancy,
          settings.effectiveTintAmount,
        ])
        ..setFloats([
          settings.bevelShadowStrength,
          GlassRim.bevelShadowDepth * devicePixelRatio,
          GlassRim.bevelShadowOffset * devicePixelRatio,
        ])
        ..setFloats([
          _colorModelCode(appearance.colorModel, colorModels),
          appearance.visibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
        ]);
    });
    // Frosted glass cross-fades its blur away, while unfrosted glass stays
    // alpha-1 and cross-fades its material in the shader, so both match the
    // backdrop exactly at visibility 0.
    shader.setFloat(_FinalUniforms.blurFade, blurPassSigma > 0 ? 1 : 0);
    // uSolidBackdrop's alpha; 0 reads the backdrop. A paint over a solid
    // sets it only while it records.
    shader.setFloat(_FinalUniforms.solidBackdrop + 3, 0);
    _writeGlow(shader);
    // uBackdropOverlay's alpha; 0 lays no color over the backdrop. A paint
    // over a cached copy sets it only while it records.
    shader.setFloat(_FinalUniforms.overlay + 3, 0);
    // The three adaptive color-model slots, filled with the default model
    // when fewer than three distinct models are in use.
    shader.setFloatUniforms(initialIndex: _FinalUniforms.colorModels, (value) {
      value.setFloats([
        for (var i = 0; i < 3; i++)
          ...i < colorModels.length
              ? colorModels[i].toShaderParameters()
              : GlassColorParameters.ios27Light.toShaderParameters(),
      ]);
    });
  }

  /// [smallestVisibleShortSide], measured when geometry is bound. Starts at
  /// [largestFittedShortSide] so a bounds query before the first paint
  /// over-allocates rather than clips the blur.
  double _shapeShortSide = LiquidGlassRenderObject.largestFittedShortSide;

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  ///
  /// This is the unscaled toolbar-size value; painting uses
  /// [_frostSigmaForCurrentShapes], which applies the shape-size response.
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

  /// Whether the last composited frame drew the glass over the underlay's
  /// copy rather than reading the backdrop.
  @visibleForTesting
  bool debugDrewOverUnderlay = false;

  /// The page this glass reads in the last composited frame, if it reads one.
  @visibleForTesting
  PageCopy? debugPage;

  /// What the last plan has this glass do.
  @visibleForTesting
  Fate? get debugFate => _fate;

  /// See [LiquidGlassLayer.glow].
  LiquidGlassGlow? get glow => _glow;
  LiquidGlassGlow? _glow;
  set glow(LiquidGlassGlow? value) {
    if (_glow == value) return;
    _glow = value;
    // Only the glow's uniforms change. A retained pass takes them in a new
    // filter, without painting the layer and its shapes. Every final shader
    // takes them: the layer switches between them without rewriting them.
    finalShaders.forEach(_writeGlow);
    _noteShaderInputs();
    if (!_refreshRetainedFilter()) markNeedsPaint();
  }

  void _writeGlow(FragmentShader shader) {
    final glow = LiquidGlassGlow.uniformsOf(_glow, devicePixelRatio);
    for (var i = 0; i < glow.length; i++) {
      shader.setFloat(_FinalUniforms.glow + i, glow[i]);
    }
  }

  /// Hands the final pass's current uniforms to the retained filter layer
  /// and schedules a frame to composite it; false when there is no
  /// retained pass to update, so the layer has to paint.
  bool _refreshRetainedFilter() {
    if (!attached || !_canRebindFilter) return false;
    _bindFilter();
    SchedulerBinding.instance.ensureVisualUpdate();
    return true;
  }

  /// See [LiquidGlassLayer.field].
  LiquidGlassField? get field => _field;
  LiquidGlassField? _field;
  set field(LiquidGlassField? value) {
    if (_field == value) return;
    _field = value;
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  List<double> _appearanceLookupData(
    List<LiquidGlassAppearance> appearances,
  ) {
    // This is used only for mixed frames; unused lookup rows must not depend
    // on the owner's active (possibly different) uniform frame.
    final fallback = defaultAppearance;
    final colorModels = _colorModelSlots(appearances);
    LiquidGlassAppearance at(int index) =>
        index < appearances.length ? appearances[index] : fallback;
    return <double>[
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).tint.r,
        at(i).tint.g,
        at(i).tint.b,
        at(i).tint.a,
      ],
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).colorModel.saturation / 4,
        at(i).colorModel.transmissionGamma / 4,
        at(i).colorModel.vibrancy / 4,
        (at(i).visibility +
                _colorModelCode(at(i).colorModel, colorModels) * 2) /
            7,
      ],
    ];
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (usesShapeAppearances, usesTintOnlyAppearance, uniformAppearance) =
        _classifyShapeAppearances(appearances, defaultAppearance);
    if (_usesShapeAppearances == usesShapeAppearances &&
        _usesTintOnlyAppearance == usesTintOnlyAppearance &&
        _uniformAppearance == uniformAppearance &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = usesShapeAppearances;
    _usesTintOnlyAppearance = usesTintOnlyAppearance;
    _uniformAppearance = uniformAppearance;
    _shapeAppearances = List.unmodifiable(appearances);
    _updateShaderSettings();
  }

  // MARK: Retained frame hooks

  /// Whether the committed shapes exist but none can be drawn by this effect.
  /// It reads the committed geometry, so it stays right when a retained
  /// refresh commits new shapes between paints.
  bool get drawableEmpty => _drawableEmpty ??=
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  bool? _drawableEmpty;

  @override
  void commitFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    super.commitFrameGeometry(candidate);
    _drawableEmpty = null;
  }

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometryImage != null;

  // Whether the retained filter layer can take new uniforms without a paint.
  bool get _canRebindFilter =>
      _rig.filterLayer != null && !drawableEmpty && hasReusableGeometry;

  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.idle;

  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
          shape.appearance.visibility > 0 &&
          _matteShapeBasis(entry.$3, shape.shapeToGeometry ?? _identity) !=
              null,
    ),
  );

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentMatteRevision(snapshot.matteRevision);

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    final geometryInputsChanged =
        old.effectiveRefractionHeight != settings.effectiveRefractionHeight ||
        old.effectiveRefractionAmount != settings.effectiveRefractionAmount ||
        old.refractionFitsShape != settings.refractionFitsShape ||
        old.contourWidth != settings.contourWidth;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
  }

  @override
  void onAppearanceChanged() => _updateShaderSettings();

  @override
  void onDevicePixelRatioChanged() {
    _updateShaderSettings();
    needsGeometryUpdate = true;
  }

  // MARK: Retained matte

  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// Layer-local bounds of the matte, in logical pixels. Ancestor transforms
  /// do not change them: the compositor applies those, not the shader.
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSize = Size.zero;
  // The matte and material map fill the top-left of textures that only grow.
  Size _geometryTextureSize = Size.zero;
  Size _materialTextureSize = const Size(1, 1);

  @visibleForTesting
  ui.Image? get debugGeometryImage => _geometryImage;

  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  /// Re-encodes the committed shapes before the layer tree is built, without
  /// painting children; false when the frame needs a normal paint.
  bool _refreshRetainedGeometry() {
    if ((_geometryImage == null && !drawableEmpty) ||
        frameState == GlassFrameState.idle ||
        debugPaintLiquidGlassGeometry) {
      return false;
    }
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    // Topology changes need normal painting to rebuild clip ancestry.
    if (bounds == null ||
        !listEquals(retainedStructure, geometryStructure(candidate))) {
      return false;
    }
    commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    // A drawable-empty refresh encodes nothing; the committed list alone
    // is the compositor-translation poll's baseline.
    if (hasDrawableGlass(shapesWithGeometry)) {
      final reuseMatte = _reusesMatte(bounds);
      if (!reuseMatte || _needsMaterialUpdate) {
        // Keep old borrowed handles valid until the replacement is installed.
        if (!_ownsGeometryImages && _geometryImage != null) {
          final geometry = _geometryImage!.clone();
          ui.Image? material;
          try {
            material = _materialImage?.clone();
          } catch (_) {
            geometry.dispose();
            rethrow;
          }
          _geometryImage = geometry;
          _materialImage = material;
          _ownsGeometryImages = true;
        }
        _encodeGeometry(bounds, writeMatte: !reuseMatte);
      }
      _bindGeometryShader(_geometryImage!);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
    recordGlassShadows(retainedPaintOffset);
    _syncMaterialFilter(materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  bool _reusesMatte(Rect bounds) =>
      !needsGeometryUpdate &&
      !_analytic &&
      _geometryImage != null &&
      _reuseUniformlyTranslatedGeometry(bounds);

  void _encodeGeometry(Rect bounds, {required bool writeMatte}) {
    final result = _buildGpuGeometryImage(
      shapesWithGeometry,
      bounds,
      writeMatte: writeMatte,
    );
    _releaseGeometryImageHandles();
    _geometryImage = result.image;
    _materialImage = result.materialImage;
    _geometryMatteBounds = result.matteBounds;
    _geometryTextureSize = result.textureSize;
    _materialTextureSize = result.materialTextureSize;
    _materialCenterInMatte = result.materialCenter;
    _materialSize = bounds.size;
    _setShapeAppearances(result.appearances);
    _rememberEncodedGeometry(bounds);
  }

  void _clearGeometryImage() {
    clearGlassShadows();
    _releaseGeometryImageHandles();
    clearFrameInputs();
  }

  void _releaseGeometryImageHandles() {
    if (_ownsGeometryImages) {
      _geometryImage?.dispose();
      _materialImage?.dispose();
      _ownsGeometryImages = false;
    }
    _geometryImage = null;
    _materialImage = null;
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
        if (needsGeometryUpdate ||
            _geometryImage == null ||
            link.isDirty ||
            _needsMaterialUpdate) {
          link
            ..updateAllGeometries()
            ..markClean();

          final reuseMatte = _reusesMatte(geometryBounds);
          needsGeometryUpdate = false;
          if (!reuseMatte || _needsMaterialUpdate) {
            if (!reuseMatte) _clearGeometryImage();
            _encodeGeometry(geometryBounds, writeMatte: !reuseMatte);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (debugPaintLiquidGlassGeometry) {
            _debugPaintGeometry(effectContext, effectOffset);
          } else if (_geometryImage != null) {
            _bindGeometryShader(_geometryImage!);
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
      for (final (_, geometry, _) in shapesWithGeometry)
        for (final shape in geometry.shapes) shape.appearance,
    ];
    final appearanceValuesChanged = !listEquals(
      _shapeAppearances,
      appearances,
    );
    _setShapeAppearances(appearances);
    if (usedShapeAppearances != _usesShapeAppearances ||
        usedTintOnlyAppearance != _usesTintOnlyAppearance ||
        (_usesShapeAppearances && appearanceValuesChanged)) {
      // Appearance maps have their own output. Matte validity is decided by
      // the encoded geometry snapshot, including visibility zero crossings.
      _needsMaterialUpdate = true;
    }
    effectPaintBounds = expandEffectBounds(boundingBox);
    return boundingBox.inflate(materialOutset);
  }

  // Resource binding is separate from recording/painting children so a
  // changed geometry frame can be prepared without invoking child paint.
  // The coordinate mapping is written by the material paint
  // (_syncMaterialFilter, or _paintOverSolid over a solid color) once this
  // frame's material bounds are set; written here it would use the previous
  // frame's.
  void _bindGeometryShader(ui.Image geometryImage, {double? halfMinor}) {
    final activeRenderShader = renderShader;
    activeRenderShader
      ..setFloatUniforms(initialIndex: _FinalUniforms.lowResMatte, (value) {
        value.setFloats([
          _matteScale.toDouble(),
          _geometryTextureSize.width,
          _geometryTextureSize.height,
          halfMinor ?? _halfMinor,
          settings.effectiveRefractionHeight * devicePixelRatio,
          settings.refractionFitsShape ? 1 : 0,
        ]);
      })
      ..setFloatUniforms(initialIndex: _FinalUniforms.geometryBounds, (value) {
        value
          ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
          ..setSize(_geometryMatteBounds.size * devicePixelRatio);
      })
      ..setFloatUniforms(initialIndex: _FinalUniforms.materialCenter, (value) {
        value.setOffset(_materialCenterInMatte * devicePixelRatio);
      })
      // uBackdropShrinkAxis, along the glass's long side.
      ..setFloatUniforms(initialIndex: _FinalUniforms.shrinkAxis, (value) {
        final half =
            settings.effectiveBackdropShrinkRim *
            (_materialSize.longestSide - _materialSize.shortestSide) /
            2 *
            devicePixelRatio;
        final alongX = _materialSize.width >= _materialSize.height;
        value.setOffset(alongX ? Offset(half, 0) : Offset(0, half));
      })
      // uBackdropOrigin, zero for a filter, whose fragment coordinates are
      // its input's, then uMaterialTextureSize.
      ..setFloatUniforms(initialIndex: _FinalUniforms.backdropOrigin, (value) {
        value.setFloats([
          0,
          0,
          _materialTextureSize.width,
          _materialTextureSize.height,
        ]);
      })
      // Sampler 0 is the image-filter input. The engine replaces its texture
      // with the backdrop but keeps the sampling set here, so any bound image
      // selects bilinear or nearest backdrop sampling at no cost.
      ..setImageSampler(
        0,
        geometryImage,
        filterQuality: FilterQuality.low,
      );
    if (!_analytic) {
      // Linear filtering: the shader relies on each read blending the four
      // nearest texels of the low-res matte.
      activeRenderShader.setImageSampler(
        1,
        geometryImage,
        filterQuality: FilterQuality.low,
      );
    }
    final material = _groupTints
        ? _groupMatte?.tints
        : _usesShapeAppearances
        ? _materialImage
        : null;
    if (material case final materialImage?) {
      if (_usesTintOnlyAppearance || _groupTints) {
        activeRenderShader.setImageSampler(
          2,
          materialImage,
          filterQuality: FilterQuality.low,
        );
      } else {
        activeRenderShader
          ..setImageSampler(2, materialImage)
          ..setImageSampler(3, materialImage, filterQuality: FilterQuality.low);
      }
    }
    if (!identical(activeRenderShader, _boundRenderShader) ||
        !identical(geometryImage, _boundGeometryImage) ||
        !identical(material ?? _materialImage, _boundMaterialImage) ||
        _geometryMatteBounds != _boundMatteBounds) {
      _boundRenderShader = activeRenderShader;
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = material ?? _materialImage;
      _boundMatteBounds = _geometryMatteBounds;
      _noteShaderInputs();
    }
  }

  FragmentShader? _boundRenderShader;
  ui.Image? _boundGeometryImage;
  ui.Image? _boundMaterialImage;
  Rect? _boundMatteBounds;

  // MARK: Coordinate mapping

  Matrix4 get shaderCoordinateTransform => filterPassTransform(
    this,
    seeding: compositionProbeSeeding,
    devicePixelRatio: devicePixelRatio,
    translation: compositorTranslation,
  );

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;
  FragmentShader? _mappedShader;
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

  /// The [backdropSampleBounds] last written to the shader.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  @protected
  bool syncCoordinateMapping() {
    final mapping = _currentCoordinateMapping();
    final backdropBounds = backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _noteShaderInputs();
    final shader = renderShader;
    if (changed || !identical(shader, _mappedShader)) {
      _mappedShader = shader;
      _writeCoordinateMapping(shader, mapping, backdropBounds);
    }
    return changed;
  }

  (double, double, double, double, double, double)
  _currentCoordinateMapping() => _matteMapping(
    Matrix4.inverted(shaderCoordinateTransform),
    devicePixelRatio,
  );

  // From fragment coordinates that begin at [origin] in the screen's device
  // pixels to the matte.
  static (double, double, double, double, double, double) _matteMapping(
    Matrix4 globalToMatte,
    double dpr, [
    Offset origin = Offset.zero,
  ]) {
    final o = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
    final ax = MatrixUtils.transformPoint(globalToMatte, const Offset(1, 0));
    final ay = MatrixUtils.transformPoint(globalToMatte, const Offset(0, 1));
    return (
      ax.dx - o.dx,
      ay.dx - o.dx,
      ax.dy - o.dy,
      ay.dy - o.dy,
      o.dx * dpr + (ax.dx - o.dx) * origin.dx + (ay.dx - o.dx) * origin.dy,
      o.dy * dpr + (ax.dy - o.dy) * origin.dx + (ay.dy - o.dy) * origin.dy,
    );
  }

  static void _writeMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
  ) {
    shader.setFloatUniforms(initialIndex: _FinalUniforms.filterToMatte, (
      value,
    ) {
      value.setFloats([
        mapping.$1,
        mapping.$2,
        mapping.$3,
        mapping.$4,
        mapping.$5,
        mapping.$6,
      ]);
    });
  }

  void _writeCoordinateMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    _writeMapping(shader, mapping);
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloatUniforms(initialIndex: _FinalUniforms.backdropBounds, (
      value,
    ) {
      value.setFloats([
        matteBounds.left * devicePixelRatio,
        matteBounds.top * devicePixelRatio,
        matteBounds.right * devicePixelRatio,
        matteBounds.bottom * devicePixelRatio,
      ]);
    });
  }

  // MARK: Native filter

  // The live read: a filter in a clip.
  final _rig = BackdropRig();

  // The clip around the filter in the coordinates of the layer painting it.
  Rect? _innerClipLayerRect;

  // Re-syncs the coordinate mapping into the retained filter, or repaints
  // when its inputs cannot be reused.
  void _resyncMappingIntoFilter() {
    if (!syncCoordinateMapping()) return;
    if (_canRebindFilter) {
      _bindFilter();
    } else {
      GlassComposer.repaint(this);
    }
  }

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

  ImageFilter? _cachedFilter;
  double? _filterFrostSigma;

  void _bindFilter() => _rig.bindFilter(_updateShaderFilter());

  ImageFilter _updateShaderFilter() {
    final inputsChanged = takeShaderInputsChanged();
    final frostSigma = _frostSigmaForCurrentShapes();
    if (_cachedFilter != null &&
        !inputsChanged &&
        frostSigma == _filterFrostSigma) {
      return _cachedFilter!;
    }
    final shader = bilinearShaderFilter(renderShader);
    final filter = _frosted(shader, frostSigma);
    _cachedFilter = filter;
    _filterFrostSigma = frostSigma;
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

  void _dropFilterCache() => _cachedFilter = null;

  void _restoreLiveMapping(FragmentShader shader) {
    if (_coordinateMapping case final live?) {
      _writeCoordinateMapping(shader, live, _backdropBounds);
    }
  }

  // Shared by paint and the retained geometry refresh; it never paints
  // children.
  Rect _syncMaterialFilter(Rect materialBounds, Offset offset) {
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    _innerClipLayerRect = filterBounds.shift(offset);
    _rig.clipTo(_innerClipLayerRect!);
    if (drawableEmpty) {
      _rig.releaseFilter();
      _dropFilterCache();
    } else {
      syncCoordinateMapping();
      _bindFilter();
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
        needsCompositing: needsCompositing,
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
  // ancestor transform enters the mapping. The shader snapshots its uniforms
  // when the rect is recorded, as the filter does when it is created.
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
    final shader = renderShader;
    _writeMapping(shader, (dpr, 0, 0, dpr, -offset.dx * dpr, -offset.dy * dpr));
    shader
      // uSize, which the engine fills in only for a filter. Only backdrop
      // reads divide by it, so any nonzero size works.
      ..setFloat(0, max(filterBounds.width * dpr, 1))
      ..setFloat(1, max(filterBounds.height * dpr, 1))
      ..setFloat(_FinalUniforms.solidBackdrop, color.r)
      ..setFloat(_FinalUniforms.solidBackdrop + 1, color.g)
      ..setFloat(_FinalUniforms.solidBackdrop + 2, color.b)
      ..setFloat(_FinalUniforms.solidBackdrop + 3, 1);
    context.canvas.drawRect(
      filterBounds.shift(offset),
      Paint()
        ..shader = shader
        // The filter path clips its output to this rect with a hard edge.
        ..isAntiAlias = false,
    );
    shader.setFloat(_FinalUniforms.solidBackdrop + 3, 0);
  }

  /// Drops the native backdrop filter and its clip.
  void _releaseCompositorFilter() {
    _rig.clear();
    _innerClipLayerRect = null;
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

  // A pass that changes size counts the frames it holds still in the poll, and
  // glass drawn analytically counts its way back to a matte there.
  @override
  bool get mayRest => !_analytic;

  // This frame's place on the screen: the glass's transform to the screen, the
  // logical rect the shader draws, the material it paints there and the sigma
  // of the blur, in the screen's logical pixels, the shader frosts the copy
  // for, 0 where the copy is blurred or the glass unfrosted.
  ({Matrix4 screen, Rect logical, Rect drawn, double frost})? _frame;

  @override
  void fillPlanFacts(SiteFacts facts) {
    _frame = null;
    facts.hidden = false;
    facts.turned = false;
    facts.look = Look.none;
    facts.noJoin = _analytic
        ? NoJoin.analytic
        : _field != null || _usesShapeAppearances
        ? NoJoin.field
        : _glow != null
        ? NoJoin.glow
        : settings.effectiveBackdropShrink != 0
        ? NoJoin.shrink
        : glassShadowsFade
        ? NoJoin.fadingShadows
        : _shapeData.isEmpty || _geometryImage == null
        ? NoJoin.noMatte
        : null;
    final bounds = _filterMaterialBounds;
    if (!_rig.hasSlot || bounds == null || drawableEmpty) {
      facts.hidden = true;
      return;
    }
    final dpr = devicePixelRatio;
    final screen = filterPassTransform(
      this,
      seeding: false,
      devicePixelRatio: dpr,
      translation: compositorTranslation,
    );
    // The copy is taken in screen space: glass that is turned reads the
    // backdrop. A scale along the axes scales the filter's blur and reach on
    // the screen, along each axis on its own, as Impeller scales the live
    // filter's blur. Impeller blurs a scaled canvas with other taps than the
    // same blur unscaled: NEAR, at most 5 channel levels apart in the host
    // test of glass scaled 1.2 under 8 px of frost, and only while the glass
    // is scaled.
    final storage = screen.storage;
    final scaleX = storage[0];
    final scaleY = storage[5];
    // What the shader paints: the material, not the rect it is drawn in.
    final drawn = MatrixUtils.transformRect(screen, bounds);
    facts.drawn = drawn;
    facts.reads = drawn.inflate(
      (backdropSamplingReach(bounds) + 1) * max(scaleX.abs(), scaleY.abs()),
    );
    if (scaleX <= 0 ||
        scaleY <= 0 ||
        storage[1].abs() > 1e-6 ||
        storage[4].abs() > 1e-6) {
      facts.turned = true;
      return;
    }
    if ((scaleX - 1).abs() > 1e-6 || (scaleY - 1).abs() > 1e-6) {
      facts.noJoin ??= NoJoin.scaled;
    }
    final logical = MatrixUtils.transformRect(
      screen,
      bounds.expandToPixelBuckets(dpr),
    );
    final sigma = _frostSigmaForCurrentShapes();
    final frostX = sigma * scaleX;
    final frostY = sigma * scaleY;
    // Frost the final shader can draw is drawn there, over an unblurred
    // copy: the copy's blur passes become its taps. The shader frosts round,
    // so glass stretched past 5 % keeps the copy's blur, which follows each
    // axis.
    final round = sigma * sqrt(scaleX * scaleY);
    final frosted =
        sigma > 0 && _frostsCopies && (scaleX / scaleY - 1).abs() <= 0.05
        ? shaderFrostDownscale(round * dpr, minTexels: debugFrostMinTexels)
        : null;
    var downscale = frosted ?? 1;
    final frost = frosted == null ? 0.0 : round;
    if (frosted == null) {
      // A copy blurred by at least [_copySigma] of its own pixels is drawn
      // as the blur leaves it at a fraction of the screen's pixels: sampled
      // back up, it adds a tent of its pixel's width to a blur many times
      // wider.
      while (downscale * 2 <= debugMaxCopyDownscale &&
          min(frostX, frostY) * dpr / (downscale * 2) >= _copySigma) {
        downscale *= 2;
      }
    }
    final appearance = _uniformAppearance ?? defaultAppearance;
    _frame = (screen: screen, logical: logical, drawn: drawn, frost: frost);
    facts.stamp = _shaderInputsRevision;
    facts.look = Look(
      key: (
        settings,
        appearance.colorModel,
        appearance.visibility,
        dpr,
        _matteScale,
        frost,
        downscale,
        _colorModelFamily,
        // The shader's bevel asks how large a surface is only between these
        // sizes.
        (_halfMinor.clamp(
                  GlassRim.bevelShadowDepth * dpr * 3.5,
                  GlassRim.bevelShadowDepth * dpr * 5,
                ) *
                64)
            .round(),
      ),
      frost: frost,
      downscale: downscale,
      drawsBand:
          frost > 0 && _frostsCopies && _colorModelFamily == FinalShaderModels.ios27,
      tint: appearance.tint,
      shapes: _shapeData.length ~/ 12,
      devicePixelRatio: dpr,
      page: sigma > 0 && frosted == null
          ? PageFilter(blur: (frostX, frostY))
          : null,
    );
  }

  // Whether the shader draws a group whose matte holds its tints.
  bool _groupTints = false;

  // This frame's fate.
  Fate _fate = const Hidden();

  // Whether the shader is set up to draw a group.
  bool _inGroup = false;
  bool _drawsBand = false;
  _GroupMatte? _groupMatte;
  int _encoded = 0;

  /// How many times the matte of a group was drawn.
  @visibleForTesting
  static int debugGroupMatteRenders = 0;

  // Moves [_shapeData] and the bounds took since they were encoded.
  Offset _encodedShift = Offset.zero;

  double get _halfMinor =>
      _geometryMatteBounds.shortestSide * devicePixelRatio / 2;

  // Where the origin of the canvas the glass paints in lies on the screen.
  Offset get _canvasOnScreen {
    final storage = _frame!.screen.storage;
    return Offset(storage[12], storage[13]) - _filterPaintOffset;
  }

  // Where the origin of the encoded shapes lies on the screen, in device
  // pixels.
  Offset get _shapesOnScreen {
    final storage = _frame!.screen.storage;
    return (Offset(storage[12], storage[13]) + _encodedShift) *
        devicePixelRatio;
  }

  static RenderLiquidGlassLayer _glassOf(SiteFacts facts) =>
      (facts.id as GeometryTransformTrackingLayer).trackedSite!
          as RenderLiquidGlassLayer;

  // The glass of [read], its band left out.
  static List<RenderLiquidGlassLayer> _glassIn(Read read) => [
    for (final member in read.members)
      if (!member.look.isBand) _glassOf(member),
  ];

  static LiquidGlassBackdropFilterLayer? _bandOf(Read read) =>
      read.lead.look.isBand
      ? read.lead.id as LiquidGlassBackdropFilterLayer
      : null;

  // Sets the shader up to draw [read], over a matte of all its glass unless it
  // has only this.
  void _beginRead(Read read) {
    final glass = _glassIn(read);
    final band = _bandOf(read) != null;
    if (glass.length == 1 && !band) {
      _endGroup();
      return;
    }
    if (glass.length > 1) {
      final matte = _groupMatte ??= _GroupMatte.tryCreate()!;
      matte.gather(glass);
    }
    _inGroup = true;
    final tints = glass.length > 1 && _groupMatte!.tints != null;
    final rebind = band != _drawsBand || tints != _groupTints;
    _drawsBand = band;
    _groupTints = tints;
    if (glass.length > 1) {
      final matte = _groupMatte!;
      if (rebind ||
          !identical(_boundGeometryImage, matte.image) ||
          !identical(_boundMaterialImage, matte.tints) ||
          _boundMatteBounds != matte.bounds) {
        final bounds = _geometryMatteBounds;
        final textureSize = _geometryTextureSize;
        final tintsSize = _materialTextureSize;
        final halfMinor = _halfMinor;
        _geometryMatteBounds = matte.bounds;
        _geometryTextureSize = matte.textureSize;
        if (tints) _materialTextureSize = matte.tintsSize;
        _bindGeometryShader(matte.image!, halfMinor: halfMinor);
        _geometryMatteBounds = bounds;
        _geometryTextureSize = textureSize;
        _materialTextureSize = tintsSize;
      }
    } else if (_geometryImage case final image?
        when rebind || !identical(_boundGeometryImage, image)) {
      _bindGeometryShader(image);
    }
  }

  void _endGroup() {
    if (!_inGroup) return;
    _inGroup = false;
    _drawsBand = false;
    _groupTints = false;
    if (_geometryImage case final image?) _bindGeometryShader(image);
    if (!drawableEmpty) {
      syncCoordinateMapping();
      _bindFilter();
    }
  }

  // A band adds to the frost what it still lacks, so it can't take less of it.
  @override
  ImageFilter? readInPlace(Read read, CornerRead corner) {
    final frost = _frame!.frost;
    final band = _bandOf(read);
    if (band != null && band.frost!.sigma < frost) return null;
    return inPlaceFrostFilter(corner, frost);
  }

  // From the screen's device pixels into the matte [read] is drawn over, and
  // what its shader samples of the backdrop there.
  (Matrix4, Rect?) _readMapping(Read read) {
    final matte = _glassIn(read).length > 1 ? _groupMatte : null;
    final origin = matte?.origin;
    return origin == null
        ? (Matrix4.inverted(_frame!.screen), _backdropBounds)
        : (
            Matrix4.translationValues(-origin.dx, -origin.dy, 0),
            read.band.shift(-origin),
          );
  }

  @override
  ImageFilter readFilter(Read read, CornerRead corner, ImageFilter? inPlace) {
    final frost = _frame!.frost;
    final sampling = corner.glassSampling(inPlace == null ? frost : 0);
    final (globalToMatte, backdropBounds) = _readMapping(read);
    final band = _bandOf(read);
    final shown = band == null
        ? null
        : corner.frostSampling(band.shown, band.frost!.sigma)?.shown ??
              Rect.zero;
    final shader = renderShader;
    final key = (
      shader,
      _shaderInputsRevision,
      sampling.origin,
      sampling.reduced,
      sampling.frost,
      sampling.holds,
      globalToMatte,
      backdropBounds,
      shown,
      band?.bandPaint,
      band?.screenOrigin,
    );
    if (key == _inSceneFilterKey) return _inSceneFilter!;
    _inSceneFilterKey = key;
    if (band != null) {
      _writeBand(
        shader,
        band,
        sampling.origin.dy,
        shown!,
        corner.glassSampling(band.frost!.sigma).frost,
        inPlace == null ? 0 : corner.glassSampling(frost).frost,
      );
    }
    try {
      return _inSceneFilter = _readingCopy<ImageFilter>(
        sampling,
        globalToMatte: globalToMatte,
        backdropBounds: backdropBounds,
        draw: shaderFilterNow,
      );
    } finally {
      if (band != null) shader.setFloat(_FinalUniforms.overlay + 3, 0);
    }
  }

  @override
  Object readRevision(Read read) => (
    _shaderInputsRevision,
    _bandOf(read)?.bandPaint,
    _bandOf(read)?.screenOrigin,
    _frame!.frost,
    read.quad,
    read.band,
    _groupMatte?.origin,
  );

  @override
  ui.Picture recordPage(Read read, PageCopy page, Matrix4 screenToCanvas) {
    final frost = _frame!.frost;
    final sampling = page.glassSampling(frost);
    final (globalToMatte, backdropBounds) = _readMapping(read);
    final band = _bandOf(read);
    final shader = renderShader;
    if (band != null) {
      _writeBand(
        shader,
        band,
        sampling.origin.dy,
        page.fragmentsOf(band.shown),
        page.frostOf(band.frost!.sigma),
        0,
      );
    }
    final dpr = devicePixelRatio;
    final glass = _glassIn(read);
    final logical = glass.length == 1
        ? _frame!.logical
        : read.quad.expandToPixelBuckets(dpr);
    final device = Rect.fromLTRB(
      logical.left * dpr,
      logical.top * dpr,
      logical.right * dpr,
      logical.bottom * dpr,
    );
    try {
      return _readingCopy<ui.Picture>(
        sampling,
        globalToMatte: globalToMatte,
        backdropBounds: backdropBounds,
        draw: (shader) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.transform(screenToCanvas.storage);
          final paint = Paint();
          paint.shader = shader;
          // The filter's clip cuts its output with a hard edge.
          paint.isAntiAlias = false;
          canvas.drawRect(device, paint);
          return recorder.endRecording();
        },
      );
    } finally {
      if (band != null) shader.setFloat(_FinalUniforms.overlay + 3, 0);
    }
  }

  // uBand, with the rows of the band's fade and hairline in fragment
  // coordinates that start at the screen's device row [top], the frost
  // [whole] of the band, of which [frosted] is there already, and what lies
  // under the glass over the band: its fade, laid over what it reads.
  void _writeBand(
    FragmentShader shader,
    LiquidGlassBackdropFilterLayer band,
    double top,
    Rect shown,
    double whole,
    double frosted,
  ) {
    final paint = band.bandPaint!;
    final dpr = band.devicePixelRatio;
    final origin = band.screenOrigin;
    double row(double y) => (y + origin.dy) * dpr - top;
    var i = _FinalUniforms.band;
    void put(double value) => shader.setFloat(i++, value);
    put(shown.left);
    put(shown.top);
    put(shown.right);
    put(shown.bottom);
    put(sqrt(max(whole * whole - frosted * frosted, 0)));
    put(row(paint.whole));
    put(row(paint.gone));
    put(paint.brightness);
    final fade = paint.fade;
    final alpha = fade.a * paint.presence;
    put(fade.r * alpha);
    put(fade.g * alpha);
    put(fade.b * alpha);
    put(alpha);
    put(row(paint.lineStart));
    put(row(paint.lineEnd));
    put(paint.lineGray);
    put(paint.presence);
    put(paint.saturation);
    put(0);
    put(0);
    put(0);
    shader.setFloat(_FinalUniforms.overlay, fade.r);
    shader.setFloat(_FinalUniforms.overlay + 1, fade.g);
    shader.setFloat(_FinalUniforms.overlay + 2, fade.b);
    shader.setFloat(_FinalUniforms.overlay + 3, alpha);
  }

  // From the screen's device pixels to the canvas the glass paints in.
  Matrix4 _screenToCanvas() {
    final canvasToScreen = _frame!.screen.clone();
    canvasToScreen.multiply(
      Matrix4.translationValues(
        -_filterPaintOffset.dx,
        -_filterPaintOffset.dy,
        0,
      ),
    );
    final screenToCanvas = Matrix4.tryInvert(canvasToScreen)!;
    screenToCanvas.multiply(
      Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
    );
    return screenToCanvas;
  }

  // The shadows of the other glass [read] draws, where they lie in this glass's
  // canvas: under its filter, which covers them inside their silhouettes.
  List<(ui.Picture, Offset)> _shadowsOfOthers(Read read) {
    if (_bandOf(read) != null) return const [];
    return [
      for (final glass in _glassIn(read))
        if (!identical(glass, this))
          if (glass._shadowUnderRead() case final picture?)
            (picture, glass._canvasOnScreen - _canvasOnScreen),
    ];
  }

  ui.Picture? _shadowUnderRead() {
    _placeShadows(under: true);
    return glassShadowPicture?.picture;
  }

  // The hard edge around glass far apart, in the screen's device pixels, or
  // null where it fills most of [layer], the filter's layer on the screen: it
  // rejects the pixels of the layer no glass paints, which saved 0.6 ms of GPU
  // time over twelve buttons on the Pixel 6a.
  //
  // A pixel at two corners keeps the edge's bounds at the layer's: Impeller
  // cuts a layer a clip cuts by 30 % or more, and the fragment coordinates the
  // glass reads start at the cut (see [GlassCopies.keepsWhole]).
  ui.Path? _clipIn(Read read, Rect layer) {
    if (read.members.length < 2 || _bandOf(read) != null) return null;
    double area(Rect rect) => rect.width * rect.height;
    var sum = 0.0;
    for (final member in read.members) {
      sum += area(member.drawn);
    }
    if (area(read.quad) <= sum * 1.3) return null;
    final dpr = devicePixelRatio;
    final path = ui.Path();
    void add(Rect rect) => path.addRect(
      Rect.fromLTRB(
        rect.left * dpr,
        rect.top * dpr,
        rect.right * dpr,
        rect.bottom * dpr,
      ),
    );
    for (final member in read.members) {
      add(member.drawn.inflate(2 / dpr));
    }
    add(layer.topLeft & Size.square(1 / dpr));
    add(
      Rect.fromPoints(
        layer.bottomRight - Offset(1 / dpr, 1 / dpr),
        layer.bottomRight,
      ),
    );
    return path;
  }

  @override
  void beginFate(Fate fate) {
    _fate = fate;
    debugPage = null;
    if (!_rig.hasSlot) {
      _endGroup();
      _placeShadows(under: false);
      return;
    }
    switch (fate) {
      case Hidden():
        _endGroup();
        compositionSeedSuppressed = true;
        debugDrewOverUnderlay = false;
        _rig.hide();
        _placeShadows(under: false);
      case Leads(:final read) when read.source is LiveRead:
        // Set up here too: a read drawn over a copy above this one holds what
        // this frame's fates decided.
        _endGroup();
      case Leads(:final read):
        // Glass over its copy reads no backdrop: an opacity pass around it
        // needs no seed.
        compositionSeedSuppressed = true;
        debugDrewOverUnderlay = true;
        _beginRead(read);
        _placeShadows(under: !glassShadowsFade);
      case Follows(:final read):
        compositionSeedSuppressed = true;
        debugDrewOverUnderlay = true;
        // The glass over a band draws it, in the band's place.
        if (_bandOf(read) != null && identical(_glassIn(read).first, this)) {
          _beginRead(read);
        } else {
          _endGroup();
        }
        _rig.hide();
        // Another layer draws this glass. Its shadows lie under that layer's
        // filter, or, over a band, stay cut outside the glass: a band's bar
        // spends next to nothing on them
        // (tool/audit/2026-11-05-one-pass/results.md).
        if (_bandOf(read) == null) {
          _placeShadows(under: true);
          glassShadowPicture?.remove();
        } else {
          _placeShadows(under: false);
        }
    }
  }

  // Where this glass's read shows in the scene.
  CornerRead? _shownCorner;
  ImageFilter? _shownFilter;
  ImageFilter? _shownInPlace;
  ui.Path? _shownClip;
  Matrix4? _shownToCanvas;
  List<(ui.Picture, Offset)> _shownUnder = const [];
  Object? _shownKey;

  @override
  void showScene(Read read, ReadCopy copy) {
    final corner = copy.readIn(copy.layer);
    if (corner == null) {
      _rig.hide();
      _placeShadows(under: false);
      debugDrewOverUnderlay = false;
      return;
    }
    final inPlace = readInPlace(read, corner);
    final filter = readFilter(read, corner, inPlace);
    final toCanvas = _screenToCanvas();
    final under = _shadowsOfOthers(read);
    final clip = _clipIn(read, copy.layer);
    final key = [
      filter,
      inPlace,
      toCanvas,
      copy.layer,
      if (clip != null) ...[for (final member in read.members) member.drawn],
      for (final (picture, offset) in under) ...[picture, offset],
    ];
    final layer = _rig.readLayer;
    final held = _shownKey;
    final changed =
        read.changed ||
        layer.parent == null ||
        held is! List<Object?> ||
        !listEquals(held, key);
    _shownCorner = corner;
    _shownFilter = filter;
    _shownInPlace = inPlace;
    _shownClip = clip;
    _shownToCanvas = toCanvas;
    _shownUnder = under;
    _shownKey = key;
    layer.show(_addRead, changed: changed);
    _rig.show(layer, under: glassShadowsFade ? null : glassShadowPicture);
  }

  ui.TransformEngineLayer? _addRead(ui.SceneBuilder builder) {
    for (final (picture, offset) in _shownUnder) {
      builder.addPicture(offset, picture);
    }
    return _shownCorner!.addToScene(
      builder,
      _shownFilter!,
      _shownToCanvas!,
      clip: _shownClip,
      inPlace: _shownInPlace,
    );
  }

  @override
  void showPage(Read read, PageCopy page) {
    debugPage = page;
    final toCanvas = _screenToCanvas();
    final under = _shadowsOfOthers(read);
    final dpr = devicePixelRatio;
    final quad = read.quad;
    final bounds = MatrixUtils.transformRect(
      toCanvas,
      Rect.fromLTRB(
        quad.left * dpr,
        quad.top * dpr,
        quad.right * dpr,
        quad.bottom * dpr,
      ),
    ).inflate(1);
    final key = (
      page.image,
      page.placement,
      page.rect,
      readRevision(read),
      toCanvas,
      Object.hashAll([
        for (final (picture, offset) in under) ...[picture, offset],
      ]),
    );
    _rig.show(
      _rig.pagePicture(key, bounds, () {
        final body = recordPage(read, page, toCanvas);
        if (under.isEmpty) return body;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final (shadow, offset) in under) {
          canvas.save();
          canvas.translate(offset.dx, offset.dy);
          canvas.drawPicture(shadow);
          canvas.restore();
        }
        canvas.drawPicture(body);
        body.dispose();
        return recorder.endRecording();
      }),
      under: glassShadowsFade ? null : glassShadowPicture,
    );
  }

  @override
  void showLive(BackdropKey? group) {
    compositionSeedSuppressed = false;
    debugDrewOverUnderlay = false;
    _placeShadows(under: false);
    _rig.showLive(group);
  }

  @override
  ReadPainter get readPainter => this;

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    final fate = _fate;
    if (fate is! Leads) return;
    final read = fate.read;
    if (glassShadowPicture?.picture case final shadow?
        when !glassShadowsFade) {
      out.picture(shadow);
    }
    if (read.source is ImageRead) {
      if (_rig.pageShown case final page?) out.picture(page);
      return;
    }
    final copy = read.output! as ReadCopy;
    final corner = copy.readIn(copy.regionIn(outer, read.lead.clip));
    if (corner == null) return;
    for (final (picture, offset) in _shadowsOfOthers(read)) {
      out.mark();
      out.at += offset;
      out.picture(picture);
      out.leave();
    }
    final inPlace = readInPlace(read, corner);
    final filter = readFilter(read, corner, inPlace);
    out.settle();
    corner.addToScene(
      out.builder,
      filter,
      _screenToCanvas(),
      inPlace: inPlace,
    );
  }

  // Glass over its copy paints its silhouettes opaquely over the slot, so
  // its shadows lie under it in the slot, whole, rather than over it cut
  // outside the silhouettes: the cut is a stencil clip of the shadow
  // groups' bounds, the dearest part of drawing them. The copy is taken
  // under the glass's own layer, so it never holds them.
  void _placeShadows({required bool under}) {
    if (under == shadowsUnderGlass) return;
    shadowsUnderGlass = under;
    if (glassShadowPicture != null) recordGlassShadows(retainedPaintOffset);
  }

  /// How many device pixels along each side one pixel of a copy that
  /// Impeller blurs stands for at most; a copy the shader frosts takes its
  /// size from the frost.
  ///
  /// NEAR: a copy drawn at half size differs from the full one by at most 10
  /// channel levels on the Pixel 6a (5 in the scroll scene, 10 under the
  /// crowd of buttons), and by 4 in the host test of white text under 8 px
  /// of frost at dpr 1. In return the
  /// Pixel's rails spend 7 % less on a dot or the Liquid tab and 32 % less
  /// under the crowd. A quarter size differs by 15 on the Liquid tab and
  /// saves no more.
  @visibleForTesting
  static int debugMaxCopyDownscale = 2;

  // The blur, in the copy's own pixels, that hides its size.
  static const double _copySigma = 2.5;

  /// Whether the final shader frosts an unblurred copy instead of the copy
  /// being blurred.
  ///
  /// NEAR: the shader's 12 taps, turned over a 2 x 2 cell of pixels except in
  /// the tinted variants, are not Impeller's blur, and a thin hard edge under
  /// the frost shows a faint dither. Over the white bars of the host test they
  /// differ from the live filter by at most 22 channel levels over a half-size
  /// copy and 36 over a quarter-size one, where the blurred half-size copy
  /// differs by 4, and by 30 for glass scaled 1.2 over a quarter-size copy.
  /// In return a frosted copy takes no blur passes.
  ///
  /// A layer picks its shaders by it: after a change, call
  /// [debugUpdateShaders].
  @visibleForTesting
  static bool debugShaderFrost = true;

  /// A copy is halved while the frost still spans this many of its pixels:
  /// the fewer the pixels, the less it costs to draw and to frost.
  static double debugFrostMinTexels = 1;

  /// Encodes the geometry again, after a bench changed what it draws.
  void debugUpdateGeometry() {
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  /// Picks this layer's shaders again, after [debugShaderFrost] changed.
  @visibleForTesting
  void debugUpdateShaders() {
    _updateShaderSettings();
    markNeedsPaint();
  }

  ImageFilter? _inSceneFilter;
  Object? _inSceneFilterKey;

  // Draws the glass with [draw] over a copy read as [sampling], with the
  // shader's uniforms set for it, and sets
  // them back to the live filter's after: a shader filter takes the
  // uniforms when it is created, a paint when it draws. The shader's
  // fragment coordinates start at the sampling's origin, so the mapping
  // into the matte is the screen's shifted by it. A paint over an image
  // draws in the screen's device pixels, from which the shader takes the
  // origin (uBackdropOrigin); a filter's fragments start there already.
  T _readingCopy<T>(
    GlassSampling sampling, {
    required Matrix4 globalToMatte,
    required Rect? backdropBounds,
    required T Function(FragmentShader shader) draw,
  }) {
    final shader = renderShader;
    final holds = sampling.holds;
    final within = holds == null
        ? null
        : MatrixUtils.transformRect(globalToMatte, holds);
    _writeCoordinateMapping(
      shader,
      _matteMapping(globalToMatte, devicePixelRatio, sampling.origin),
      within == null
          ? backdropBounds
          : backdropBounds?.intersect(within) ?? within,
    );
    if (sampling.size case final size?) {
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
    }
    final paints = sampling.image != null;
    if (paints) {
      shader.setFloat(_FinalUniforms.backdropOrigin, sampling.origin.dx);
      shader.setFloat(_FinalUniforms.backdropOrigin + 1, sampling.origin.dy);
    }
    shader.setFloat(_FinalUniforms.reducedBackdrop, sampling.reduced);
    shader.setFloat(_FinalUniforms.backdropFrost, sampling.frost);
    if (sampling.image case final image?) {
      shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
    }
    try {
      return draw(shader);
    } finally {
      shader.setFloat(_FinalUniforms.reducedBackdrop, 0);
      shader.setFloat(_FinalUniforms.backdropFrost, 0);
      _restoreLiveMapping(shader);
      if (paints) {
        shader.setFloat(_FinalUniforms.backdropOrigin, 0);
        shader.setFloat(_FinalUniforms.backdropOrigin + 1, 0);
        if (_geometryImage case final matte?) {
          shader.setImageSampler(0, matte, filterQuality: FilterQuality.low);
        }
      }
    }
  }

  @override
  void onCompositorTranslated(Offset translation) {
    // Nothing to map: a shape that appears repaints.
    if (shapesWithGeometry.isEmpty) return;
    // Chrome over a scroll keeps all of it, frame after frame.
    final inputs = (
      translation,
      _filterMaterialBounds,
      _filterPaintOffset,
      compositionProbeSeeding,
      _frostSigmaForCurrentShapes(),
      devicePixelRatio,
      retainedClipBounds,
      localPaintClipAbove(this),
    );
    if (!_mappingMoved && inputs == _mappingInputs) return;
    _mappingMoved = false;
    _mappingInputs = inputs;
    final clip = _filterClip;
    if (clip != null && _rig.hasClip) {
      _innerClipLayerRect = clip.shift(_filterPaintOffset);
      _rig.clipTo(_innerClipLayerRect!);
    }
    final remapped = syncCoordinateMapping();
    if (remapped && _canRebindFilter) _bindFilter();
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    // A pass-origin change (the opacity seed turning on, or an ancestor clip
    // moving with paint-only changes inside it) moves no tracked transform,
    // so the translation poll misses it.
    _resyncMappingIntoFilter();
    if (motion.needsRepaint &&
        (_rig.filterLayer != null || drawableEmpty) &&
        _rig.hasClip &&
        _refreshRetainedGeometry()) {
      return;
    }
    if (motion.needsRepaint) GlassComposer.repaint(this);
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final bounds = _geometryMatteBounds;
      context.canvas
        ..save()
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImageRect(
          geometryImage,
          Offset.zero & bounds.size * devicePixelRatio / _matteScale.toDouble(),
          (offset * devicePixelRatio) & bounds.size * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
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

  @protected
  bool needsGeometryUpdate = true;

  final List<double> _shapeData = [];
  final List<double> _rseData = [];
  // A pair's bottom half, 12 floats per shape, zeros for every other shape.
  final List<double> _rseLowerData = [];
  final List<double> _boundsData = [];
  // Each shape's smallest stretch over its largest, for analytic frames.
  final List<double> _cullData = [];
  static final Matrix4 _identity = Matrix4.identity();

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
  /// [LiquidGlassSettings.backdropShrink], the extra content revealed on the
  /// face. A copy of the backdrop must contain this reach or the filter
  /// samples its own edge.
  double backdropSamplingReach(Rect material) {
    // The final shader's edge shift (lowResDisplacementMagnitude): no wider
    // than half a shape's shorter side when refraction fits the shape, and
    // shrunk with the bevel otherwise. No shape inside the material has a
    // shorter side longer than the material's.
    final amount = settings.effectiveDisplacementScale;
    final halfMinor = min(material.width, material.height) / 2;
    final shift = settings.refractionFitsShape
        ? min(amount, halfMinor)
        : amount *
              min(1, halfMinor / max(settings.effectiveRefractionHeight, 1e-3));
    final frostSigma = _frostSigmaForCurrentShapes();
    final blur = frostSigma > 0 ? frostSigma * 3 + 1 / devicePixelRatio : 0.0;
    final displacement = shift * (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur + displacement + revealed;
  }

  /// Half-extents along the matte axes of a shape with local half-size
  /// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
  /// shader culls with these boxes instead of mapping every pixel into each
  /// shape's local space. Ellipses and rounded rectangles are exact;
  /// continuous corners extend further into the corner than a circular arc of
  /// the same radius, so they use their box.
  static Size _matteHalfExtents(
    RawShapeType type,
    Size halfSize,
    double cornerRadius,
    Offset axisX,
    Offset axisY,
  ) {
    double extent(double x, double y) {
      switch (type) {
        case RawShapeType.ellipse:
          return sqrt(
            pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2),
          );
        case RawShapeType.roundedRectangle:
          final radius = min(cornerRadius, halfSize.shortestSide);
          return x.abs() * (halfSize.width - radius) +
              y.abs() * (halfSize.height - radius) +
              radius * sqrt(x * x + y * y);
        case RawShapeType.squircle:
        case RawShapeType.squirclePair:
          return x.abs() * halfSize.width + y.abs() * halfSize.height;
      }
    }

    return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
  }

  // Null when the shape's transform into the matte is singular.
  ({Offset axisX, Offset axisY, double determinant})? _matteShapeBasis(
    Matrix4 geometryToLayer,
    Matrix4 shapeToGeometry,
  ) {
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toMatte(Offset.zero);
    final axisX = toMatte(const Offset(1, 0)) - origin;
    final axisY = toMatte(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }

  /// Writes an analytic frame's shapes into the analytic final shaders, in
  /// the layout of analytic_geometry.glsl from uAnalyticHeader.
  void _writeAnalyticUniforms({
    required int numShapes,
    required double contourExtent,
    required bool blended,
  }) {
    const header = _FinalUniforms.analytic;
    const shapeData = header + 4;
    const rseData = shapeData + analyticMaxShapes * 12;
    const rseLower = rseData + analyticMaxShapes * 12;
    const bounds = rseLower + analyticMaxShapes * 12;
    const cull = bounds + analyticMaxShapes * 4;
    // One setFloatUniforms call for all of them: each array is padded with
    // zeros to its declared length, so the next starts where the shader
    // declares it.
    void write(FragmentShader shader) =>
        shader.setFloatUniforms(initialIndex: header, (value) {
          void fill(List<double> values, int length) {
            value
              ..setFloats(values)
              ..setFloats(List<double>.filled(length - values.length, 0));
          }

          fill([
            numShapes.toDouble(),
            max(0.5, contourExtent),
            if (blended) 1 else 0,
          ], shapeData - header);
          fill(_shapeData, rseData - shapeData);
          fill(_rseData, rseLower - rseData);
          fill(_rseLowerData, bounds - rseLower);
          fill(_boundsData, cull - bounds);
          fill(_cullData, analyticMaxShapes);
        });

    // Every analytic variant, so the one a frame picks by its color models
    // has them.
    _analyticShaders.forEach(write);
    _noteShaderInputs();
  }

  /// [area] less the shapes' box areas, times [numShapes]; overlapping boxes
  /// count twice, which errs toward analytic.
  int _emptyTests(int area, int numShapes) {
    var covered = 0.0;
    for (var i = 0; i + 3 < _boundsData.length; i += 4) {
      covered +=
          (_boundsData[i + 2] - _boundsData[i]) *
          (_boundsData[i + 3] - _boundsData[i + 1]);
    }
    return max(0, area - covered.round()) * numShapes;
  }

  /// Asks for one matte frame [analyticRestFrames] frames after the latest
  /// analytic frame, unless another one comes first.
  void _scheduleAnalyticRest() {
    final generation = ++_analyticGeneration;
    var frames = 0;
    void check(Duration _) {
      if (!attached || !_analytic || generation != _analyticGeneration) return;
      if (++frames < analyticRestFrames) {
        SchedulerBinding.instance
          ..addPostFrameCallback(check)
          ..scheduleFrame();
        return;
      }
      _restRequested = true;
      needsGeometryUpdate = true;
      markNeedsPaint();
    }

    SchedulerBinding.instance.addPostFrameCallback(check);
  }

  _GpuGeometryFrame _buildGpuGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds, {
    required bool writeMatte,
  }) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    // Centered SDF antialiasing needs half a physical pixel outside the
    // mathematical shape. Keep that margin in the persistent geometry
    // texture so the positive side of the fade is not clipped at the matte
    // edge.
    final aaPadding = max(0.5 / devicePixelRatio, _contourOutset);
    // The matte is in this layer's local coordinates. Ancestor transforms
    // are applied once by the compositor; baking them in would apply scale
    // and rotation twice.
    // Reused mattes may have moved by a fractional physical pixel. Keep
    // their raster phase and bucket-sized extent: snapping again would
    // register the new material map against an origin its matte never used.
    final boundsInMatteSpace = writeMatte
        ? bounds.inflate(aaPadding).snapToPixels(devicePixelRatio)
        : _geometryMatteBounds;
    final materialCenter = writeMatte ? bounds.center : _materialCenterInMatte;

    final physicalSize = boundsInMatteSpace.size * devicePixelRatio;
    final textureWidth = writeMatte
        ? physicalSize.width.ceil()
        : physicalSize.width.round();
    final textureHeight = writeMatte
        ? physicalSize.height.ceil()
        : physicalSize.height.round();

    if (textureWidth <= 0 || textureHeight <= 0) {
      throw StateError('Cannot render empty liquid-glass geometry.');
    }

    // Gather shapes in cache order. A negative blend marker starts a new
    // group; this preserves smooth unions within a group without blending
    // unrelated standalone glass widgets together.
    _encodedShift = Offset.zero;
    _encoded++;
    _shapeData.clear();
    _rseData.clear();
    _rseLowerData.clear();
    _boundsData.clear();
    _cullData.clear();
    var blended = false;
    final appearances = <LiquidGlassAppearance>[];
    var numShapes = 0;

    for (final (_, geometry, geometryToLayer) in geometries) {
      var firstInGroup = true;
      for (final shape in geometry.shapes) {
        // A shape at visibility 0 draws nothing. Left in, it would count as
        // an appearance of its own and take the layer to the material map.
        if (shape.appearance.visibility <= 0) continue;
        final shapeToGeometry = shape.shapeToGeometry ?? _identity;
        final basis = _matteShapeBasis(geometryToLayer, shapeToGeometry);
        if (basis == null) continue;
        final (:axisX, :axisY, :determinant) = basis;

        // Inverse 2D affine basis maps matte-space physical pixels back to
        // the shape's own physical-pixel coordinate system.
        final inverse00 = axisY.dy / determinant;
        final inverse01 = -axisY.dx / determinant;
        final inverse10 = -axisX.dy / determinant;
        final inverse11 = axisX.dx / determinant;

        // The minimum singular value conservatively converts local SDF
        // distances back to screen pixels under non-uniform scaling.
        final trace =
            axisX.dx * axisX.dx +
            axisX.dy * axisX.dy +
            axisY.dx * axisY.dx +
            axisY.dy * axisY.dy;
        final discriminant = max(
          0,
          trace * trace - 4 * determinant * determinant,
        );
        final distanceScale = sqrt(
          max(0.0, (trace - sqrt(discriminant)) * 0.5),
        );
        // trace + sqrt(discriminant) > 0: the basis is invertible.
        _cullData.add(
          distanceScale / sqrt((trace + sqrt(discriminant)) * 0.5),
        );
        if (!firstInGroup) blended = true;

        final centerInGeometry = MatrixUtils.transformPoint(
          shapeToGeometry,
          Offset(
            shape.renderObject.paintSize.width / 2,
            shape.renderObject.paintSize.height / 2,
          ),
        );
        final centerInLayer = MatrixUtils.transformPoint(
          geometryToLayer,
          centerInGeometry,
        );
        final centerInMatte = centerInLayer;

        // The inverse affine basis above already maps matte coordinates back
        // into the shape's local coordinate system. Using the transformed
        // AABB here would apply scale a second time (and turn rotations into
        // oversized primitives), which is especially visible for stretched
        // shapes in a blend group.
        final size = shape.renderObject.paintSize;
        final pair = shape.rawShapeType == RawShapeType.squirclePair;
        final rseParameters = pair
            ? roundedSuperellipsePairParameters(
                size,
                shape.rawCornerRadius,
                shape.rawBottomRadius,
                scale: devicePixelRatio,
              )
            : roundedSuperellipseParameters(
                size,
                shape.rawCornerRadius,
                scale: devicePixelRatio,
              );
        // The geometry shader tests each cap's angular span as
        // 1 - cos(span); FakeGlass reads the spans themselves.
        for (var half = 0; half < rseParameters.length; half += 12) {
          rseParameters[half + 2] = 1.0 - cos(rseParameters[half + 2]);
          rseParameters[half + 3] = 1.0 - cos(rseParameters[half + 3]);
        }
        _rseData.addAll(rseParameters.take(12));
        _rseLowerData.addAll(
          pair ? rseParameters.skip(12) : List<double>.filled(12, 0),
        );
        final center = centerInMatte * devicePixelRatio;
        // Every shader clamps a corner to half the short side already;
        // a clamped radius also lets the analytic depth bound hold for a
        // capsule written with an oversized radius. A pair is fitted on
        // its own.
        final cornerRadius = pair
            ? shape.rawCornerRadius
            : min(shape.rawCornerRadius, size.shortestSide / 2);
        final halfExtents = _matteHalfExtents(
          shape.rawShapeType,
          size * devicePixelRatio / 2,
          cornerRadius * devicePixelRatio,
          axisX,
          axisY,
        );
        _boundsData
          ..add(center.dx - halfExtents.width)
          ..add(center.dy - halfExtents.height)
          ..add(center.dx + halfExtents.width)
          ..add(center.dy + halfExtents.height);
        final blendMarker = firstInGroup
            ? -(geometry.blend * devicePixelRatio + 1)
            : geometry.blend * devicePixelRatio;

        _shapeData
          // vec4 0: primitive parameters.
          ..add(shape.rawShapeType.shaderIndex)
          ..add(size.width * devicePixelRatio)
          ..add(size.height * devicePixelRatio)
          ..add(cornerRadius * devicePixelRatio)
          // vec4 1: inverse affine basis.
          ..add(inverse00)
          ..add(inverse01)
          ..add(inverse10)
          ..add(inverse11)
          // vec4 2: transformed center, distance scale, group marker.
          ..add(centerInMatte.dx * devicePixelRatio)
          ..add(centerInMatte.dy * devicePixelRatio)
          ..add(distanceScale)
          ..add(blendMarker);
        appearances.add(shape.appearance);
        numShapes++;
        firstInGroup = false;
      }
    }

    if (numShapes == 0) {
      throw StateError('No invertible liquid-glass shapes to render.');
    }
    var (usesShapeAppearances, usesTintOnlyAppearance, _) =
        _classifyShapeAppearances(appearances, defaultAppearance);
    // A field and a per-shape material map are drawn in one pass, which
    // evaluates only so many shapes.
    const most = FlutterGpuGeometryRenderer.maxShapesPerDraw;
    if (numShapes > most && (_field != null || usesShapeAppearances)) {
      _debugWarnShapeLimitExceeded();
      numShapes = most;
      _shapeData.length = most * 12;
      _rseData.length = most * 12;
      _rseLowerData.length = most * 12;
      _boundsData.length = most * 4;
      _cullData.length = most;
      appearances.length = most;
      (usesShapeAppearances, usesTintOnlyAppearance, _) =
          _classifyShapeAppearances(appearances, defaultAppearance);
    }

    final rest = _restRequested;
    _restRequested = false;
    _analyticIneligibility = switch (()) {
      _ when !analyticGeometry => 'off',
      _ when !writeMatte => 'material update',
      _ when rest => 'rest',
      _ when _field != null => 'field',
      _ when usesShapeAppearances => 'shape appearances',
      _ when numShapes > analyticMaxShapes => 'more than $analyticMaxShapes',
      _
          when _emptyTests(textureWidth * textureHeight, numShapes) >
              analyticMaxEmptyTests =>
        'sparse',
      _ => null,
    };
    _analytic = _analyticIneligibility == null;
    if (_analytic) {
      _writeAnalyticUniforms(
        numShapes: numShapes,
        contourExtent: aaPadding * devicePixelRatio,
        blended: blended,
      );
      _scheduleAnalyticRest();
      _needsMaterialUpdate = false;
      return (
        image: _placeholder,
        materialImage: null,
        materialCenter: materialCenter,
        textureSize: const Size(1, 1),
        materialTextureSize: const Size(1, 1),
        appearances: appearances,
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          textureWidth / devicePixelRatio,
          textureHeight / devicePixelRatio,
        ),
      );
    }

    final result = renderer.render(
      writeMatte: writeMatte,
      width: textureWidth,
      height: textureHeight,
      shapeData: _shapeData,
      rseData: _rseData,
      rseLowerData: _rseLowerData,
      boundsData: _boundsData,
      numShapes: numShapes,
      refractionHeight: settings.effectiveRefractionHeight * devicePixelRatio,
      refractionAmount: settings.effectiveRefractionAmount * devicePixelRatio,
      edgeDistanceRange: settings.effectiveEdgeDistanceRange * devicePixelRatio,
      refractionFitsShape: settings.refractionFitsShape,
      contourExtent: aaPadding * devicePixelRatio,
      writeMaterials: usesShapeAppearances,
      writeTintOnly: usesTintOnlyAppearance,
      appearanceData: usesShapeAppearances
          ? _appearanceLookupData(appearances)
          : const <double>[],
      offsetX: boundsInMatteSpace.left * devicePixelRatio,
      offsetY: boundsInMatteSpace.top * devicePixelRatio,
      matteScale: _matteScale,
      field: _field,
      fieldScale: devicePixelRatio,
    );
    if (renderer.droppedShapes > 0) _debugWarnShapeLimitExceeded();
    _needsMaterialUpdate = false;
    return (
      image: result.image,
      materialImage: renderer.materialImage,
      materialCenter: materialCenter,
      textureSize: Size(
        result.textureWidth.toDouble(),
        result.textureHeight.toDouble(),
      ),
      materialTextureSize: switch (renderer.materialImage) {
        final image? => Size(image.width.toDouble(), image.height.toDouble()),
        null => const Size(1, 1),
      },
      appearances: appearances,
      matteBounds: writeMatte
          ? Rect.fromLTWH(
              boundsInMatteSpace.left,
              boundsInMatteSpace.top,
              result.width / devicePixelRatio,
              result.height / devicePixelRatio,
            )
          : _geometryMatteBounds,
    );
  }
}

// One matte of a group's glass, its origin on the first's. Glass that moves
// together lies where it lay in it, so a scroll under it renders nothing and
// only moves the mapping.
final class _GroupMatte {
  _GroupMatte._(this._renderer);

  static _GroupMatte? tryCreate() {
    final renderer = FlutterGpuGeometryRenderer.tryCreateCached(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    return renderer == null ? null : _GroupMatte._(renderer);
  }

  final FlutterGpuGeometryRenderer _renderer;
  var _signature = const <Object?>[];

  ui.Image? image;
  Rect bounds = Rect.zero;
  Size textureSize = Size.zero;

  // The tint of each shape, where they differ; a low-resolution map, so glass
  // reads it as the color of the nearest shape. NEAR: 8 bits a channel where a
  // uniform holds the tint exactly.
  ui.Image? tints;
  Size tintsSize = const Size(1, 1);

  // Where the matte's origin lies on the screen, in logical pixels.
  Offset origin = Offset.zero;

  void gather(List<RenderLiquidGlassLayer> glass) {
    final first = glass.first;
    final dpr = first.devicePixelRatio;
    final base = first._shapesOnScreen;
    origin = base / dpr;
    // A 64th of a pixel keeps rounding in the layers' moves from drawing the
    // matte again; the glass lies that much off, unseen.
    double fixed(double value) => (value * 64).roundToDouble() / 64;
    final signature = <Object?>[first.settings, dpr, first._matteScale];
    Object? tintOf(RenderLiquidGlassLayer layer) =>
        (layer._uniformAppearance ?? layer.defaultAppearance).tint;
    for (final layer in glass) {
      final at = layer._shapesOnScreen - base;
      signature.add(layer);
      signature.add(layer._encoded);
      signature.add(tintOf(layer));
      signature.add(fixed(at.dx));
      signature.add(fixed(at.dy));
    }
    if (image != null && listEquals(signature, _signature)) return;
    _signature = signature;
    RenderLiquidGlassLayer.debugGroupMatteRenders++;
    final shapes = <double>[];
    final rse = <double>[];
    final rseLower = <double>[];
    final boxes = <double>[];
    Rect? rect;
    for (final layer in glass) {
      final at = layer._shapesOnScreen - base;
      final dx = fixed(at.dx);
      final dy = fixed(at.dy);
      final from = shapes.length;
      shapes.addAll(layer._shapeData);
      for (var i = from + 8; i < shapes.length; i += 12) {
        shapes[i] += dx;
        shapes[i + 1] += dy;
      }
      final box = boxes.length;
      boxes.addAll(layer._boundsData);
      for (var i = box; i < boxes.length; i += 4) {
        boxes[i] += dx;
        boxes[i + 1] += dy;
        boxes[i + 2] += dx;
        boxes[i + 3] += dy;
      }
      rse.addAll(layer._rseData);
      rseLower.addAll(layer._rseLowerData);
      final shown = layer._frame!.drawn;
      final drawn = Rect.fromLTRB(
        shown.left * dpr - base.dx,
        shown.top * dpr - base.dy,
        shown.right * dpr - base.dx,
        shown.bottom * dpr - base.dy,
      );
      rect = rect?.expandToInclude(drawn) ?? drawn;
    }
    final all = rect!;
    final lead = first;
    final contour = max(0.5 / dpr, lead._contourOutset) * dpr;
    final room = contour.ceilToDouble() + 2;
    final left = (all.left - room).floorToDouble();
    final top = (all.top - room).floorToDouble();
    final settings = lead.settings;
    final mixed = glass.any((layer) => tintOf(layer) != tintOf(first));
    final result = _renderer.render(
      writeMaterials: mixed,
      writeTintOnly: mixed,
      appearanceData: mixed
          ? lead._appearanceLookupData([
              for (final layer in glass)
                for (var i = 0; i < layer._shapeData.length ~/ 12; i++)
                  (layer._uniformAppearance ?? layer.defaultAppearance),
            ])
          : const <double>[],
      width: (all.right + room - left).ceil(),
      height: (all.bottom + room - top).ceil(),
      shapeData: shapes,
      rseData: rse,
      rseLowerData: rseLower,
      boundsData: boxes,
      numShapes: shapes.length ~/ 12,
      refractionHeight: settings.effectiveRefractionHeight * dpr,
      refractionAmount: settings.effectiveRefractionAmount * dpr,
      edgeDistanceRange: settings.effectiveEdgeDistanceRange * dpr,
      refractionFitsShape: settings.refractionFitsShape,
      contourExtent: contour,
      offsetX: left,
      offsetY: top,
      matteScale: lead._matteScale,
    );
    image = result.image;
    bounds = Rect.fromLTWH(
      left / dpr,
      top / dpr,
      result.width / dpr,
      result.height / dpr,
    );
    textureSize = Size(
      result.textureWidth.toDouble(),
      result.textureHeight.toDouble(),
    );
    final map = mixed ? _renderer.materialImage : null;
    tints = map;
    tintsSize = map == null
        ? const Size(1, 1)
        : Size(map.width.toDouble(), map.height.toDouble());
  }

  void dispose() => _renderer.dispose();
}

// Images here borrow the renderer's handles. A retained temporary frame must
// clone both images before another render can dispose those borrowed handles.
typedef _GpuGeometryFrame = ({
  Size textureSize,
  Size materialTextureSize,
  ui.Image image,
  ui.Image? materialImage,
  Rect matteBounds,
  Offset materialCenter,
  List<LiquidGlassAppearance> appearances,
});

(bool, bool, LiquidGlassAppearance?) _classifyShapeAppearances(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (mixed, tintOnly, tintOnly || !mixed ? first : null);
}

/// Float indices of the final shader's uniforms that Dart writes one by one
/// (liquid_glass_final_render_core.glsl).
abstract final class _FinalUniforms {
  /// uGeometryOffset and uGeometrySize, four floats.
  static const int geometryBounds = 2;

  /// uTint, then the material's settings.
  static const int tint = 6;

  /// uMaterialCenter, two floats inside uProfileConfig.
  static const int materialCenter = 34;

  /// uFilterToMatteBasis and uFilterToMatteOffset, six floats.
  static const int filterToMatte = 46;

  /// uBlurFade, one float.
  static const int blurFade = 52;

  /// uBackdropBounds, four floats.
  static const int backdropBounds = 53;

  /// uColorModelParams, three slots of six vec4.
  static const int colorModels = 61;

  /// uLowResMatte and uLowResOptics, six floats.
  static const int lowResMatte = 133;
  // The band variant's uBand, where the analytic variant has its own.
  static const int band = analytic;

  /// uSolidBackdrop, four floats.
  static const int solidBackdrop = 139;

  /// uGlowSpot, uGlowBox and uGlowShape, twelve floats.
  static const int glow = 143;

  /// uBackdropShrinkAxis, two floats.
  static const int shrinkAxis = 155;

  /// uBackdropReduced, one float.
  static const int reducedBackdrop = 157;

  /// uBackdropFrost, one float.
  static const int backdropFrost = 158;

  /// uBackdropOverlay, four floats.
  static const int overlay = 159;

  /// uBackdropOrigin, two floats.
  static const int backdropOrigin = 57;

  /// The analytic variant's first uniform, uAnalyticHeader, after uEffects.
  static const int analytic = 163;
}
