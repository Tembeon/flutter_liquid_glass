// ignore_for_file: avoid_setters_without_getters, cascade_invocations

import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/internal/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_backdrop.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
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
/// Make sure not to stack any other widgets between the [LiquidGlassLayer] and
/// the [LiquidGlass] widgets, otherwise the liquid glass effect will be behind
/// them.
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

  late final logger = Logger(LgrLogNames.layer);

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
        // The old real render subtree is removed during this rebuild. Retire
        // its textures after that frame so it cannot contaminate subsequent
        // fake-only measurements, without invalidating a sampler still used by
        // the outgoing subtree.
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
    // Each layer picks its own matte scale from its device pixel ratio.
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
    // Match the full renderer's retained subtree boundary. FakeGlass paints
    // several contour-following canvas bands; without this boundary an
    // ancestor/compositor transform can make every band record again even
    // though neither the shape nor material changed.
    Widget buildFakeSurfaceLayer(
      FragmentShader? surfaceShader,
    ) {
      return RepaintBoundary(
        child: LiquidGlassRenderScope(
          settings: settings,
          defaultAppearance: defaultAppearance,
          consolidatesFakeBackdrop: true,
          consolidatesFakeSurface: true,
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
    this.gpuGeometryRenderer,
    this.matteScale = 2,
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

/// The real glass layer: renders the shared shape geometry into a GPU matte
/// and paints the final shader filter over it. All shared machinery — shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state — lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassLayer({
    required this.finalShaders,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
    int matteScale = 2,
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
      _usesShapeAppearances,
      _usesTintOnlyAppearance,
    )) {
      (true, _, _) => FinalShaderKind.analytic,
      (false, false, _) => FinalShaderKind.single,
      (false, true, true) => FinalShaderKind.tint,
      (false, true, false) => FinalShaderKind.material,
    };
    final shader =
        finalShaders[FinalShaderVariant.indexOf(kind, _colorModelFamily)];
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
      _shaderInputsChanged = true;
    }
    return shader;
  }

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
    _shaderInputsChanged = true;
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
    shader.setFloatUniforms(initialIndex: 6, (value) {
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
    // Float index 52, after the 46-float common block and the 6-float
    // filter->matte mapping: frosted glass cross-fades its blur away, while
    // unfrosted glass stays alpha-1 and cross-fades its material in the
    // shader, so both match the backdrop exactly at visibility 0.
    shader.setFloat(52, blurPassSigma > 0 ? 1 : 0);
    // uSolidBackdrop's alpha; 0 reads the backdrop. A paint over a solid
    // sets it only while it records.
    shader.setFloat(_FinalUniforms.solidBackdrop + 3, 0);
    _writeGlow(shader);
    // uBackdropOverlay's alpha; 0 lays no color over the backdrop. A paint
    // over a cached copy sets it only while it records.
    shader.setFloat(_FinalUniforms.overlay + 3, 0);
    // Float index 61, after the geometry/material texture sizes: the three
    // adaptive color-model slots (six vec4 each), zero-filled when fewer
    // than three distinct models are in use.
    shader.setFloatUniforms(initialIndex: 61, (value) {
      value.setFloats([
        for (var i = 0; i < 3; i++)
          ...i < colorModels.length
              ? colorModels[i].toShaderParameters()
              : GlassColorParameters.ios27Light.toShaderParameters(),
      ]);
    });
  }

  /// Logical short side of the smallest live shape, measured when geometry is
  /// bound. Used by the blur's size response. Groups use their smallest
  /// shape; a mixed-size group has one layer-wide blur.
  ///
  /// Starts at the largest fitted size so a pre-paint effect-bounds query
  /// over-allocates rather than clips the blur on its first frame.
  double _shapeShortSide = 150;

  double _measureShapeShortSide() {
    double? shortest;
    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shape.appearance.visibility <= 0) continue;
        // shapeBounds is already in the geometry's local space.
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        shortest = shortest == null ? side : min(shortest, side);
      }
    }
    return shortest == null ? 150 : max(1, shortest);
  }

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  ///
  /// This is the unscaled toolbar-size value; painting uses
  /// [_frostSigmaForCurrentShapes], which applies the shape-size response.
  double get blurPassSigma => _frostSigma;

  double get _frostSigma => settings.frostSigmaAt(devicePixelRatio);

  double _frostSigmaForCurrentShapes() => settings.frostSigmaAt(
    devicePixelRatio,
    shapeShortSide: _shapeShortSide,
  );

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

  /// The copy of what lies under the glass.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _rig.underlay;

  bool get _wantsUnderlay => BackdropUnderlay.enabled;

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
    _shaderInputsChanged = true;
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
    if (_rig.filterLayer == null ||
        !attached ||
        drawableEmpty ||
        !hasReusableGeometry) {
      return false;
    }
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

  /// Whether the committed shapes exist but none can be drawn by this
  /// effect — a function of the committed geometry, so it stays correct
  /// when a retained refresh commits new shapes between paints.
  bool get drawableEmpty =>
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometryImage != null;

  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.idle;

  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
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

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSize = Size.zero;
  // The matte and material map fill the top-left of textures that only grow.
  Size _geometryTextureSize = Size.zero;
  Size _materialTextureSize = const Size(1, 1);

  /// The pre-rendered geometry texture in screen space.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  @visibleForTesting
  ui.Image? get debugGeometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  /// Layer-local bounds of the geometry matte. Ancestor transforms must not
  /// change this: they are applied by the compositor, not the shader.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  /// Refreshes already recorded contributors before layer-tree descent.
  /// No child painting occurs here, and the unchanged/translation paths do
  /// not call this method or evaluate geometry.
  @protected
  bool refreshRetainedGeometry(
    void Function(
      List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>,
      Rect,
      Offset,
    )
    updateMaterial,
  ) {
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
      final reuseMatte =
          !needsGeometryUpdate &&
          !_analytic &&
          _geometryImage != null &&
          _reuseUniformlyTranslatedGeometry(bounds);
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
        final result = _buildGpuGeometryImage(
          shapesWithGeometry,
          bounds,
          writeMatte: !reuseMatte,
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
      _bindGeometryShader(_geometryImage!);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
    recordGlassShadows(retainedPaintOffset);
    updateMaterial(shapesWithGeometry, materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
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
        if (shapesWithGeometry.isEmpty) {
          releaseRetainedEffectLayer();
          return;
        }
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

          final canReuseTranslatedGeometry =
              !needsGeometryUpdate &&
              !_analytic &&
              _geometryImage != null &&
              _reuseUniformlyTranslatedGeometry(geometryBounds);
          needsGeometryUpdate = false;

          if (!canReuseTranslatedGeometry || _needsMaterialUpdate) {
            if (!canReuseTranslatedGeometry) _clearGeometryImage();
            final gpuResult = _buildGpuGeometryImage(
              shapesWithGeometry,
              geometryBounds,
              writeMatte: !canReuseTranslatedGeometry,
            );
            _releaseGeometryImageHandles();
            _geometryImage = gpuResult.image;
            _materialImage = gpuResult.materialImage;
            _geometryMatteBounds = gpuResult.matteBounds;
            _geometryTextureSize = gpuResult.textureSize;
            _materialTextureSize = gpuResult.materialTextureSize;
            _materialCenterInMatte = gpuResult.materialCenter;
            _materialSize = geometryBounds.size;
            _setShapeAppearances(gpuResult.appearances);
            _rememberEncodedGeometry(geometryBounds);
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
    _shapeShortSide = _measureShapeShortSide();
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
    final materialBounds = boundingBox.inflate(_contourOutset);
    effectPaintBounds = expandBoundsForShadows(materialBounds);
    return materialBounds;
  }

  // Resource binding is separate from recording/painting children so a
  // changed geometry frame can be prepared without invoking child paint.
  // The coordinate mapping is written by the material paint
  // (_syncMaterialFilter, or _paintOverSolid over a solid color) once this
  // frame's material bounds are set; written here it would use the previous
  // frame's.
  void _bindGeometryShader(ui.Image geometryImage) {
    final activeRenderShader = renderShader;
    activeRenderShader
      // Float index 133, after the shared uniforms: the matte scale and the
      // texture size, then the two values that set the bevel.
      ..setFloatUniforms(initialIndex: 133, (value) {
        value.setFloats([
          _matteScale.toDouble(),
          _geometryTextureSize.width,
          _geometryTextureSize.height,
          0,
          settings.effectiveRefractionHeight * devicePixelRatio,
          settings.refractionFitsShape ? 1 : 0,
        ]);
      })
      ..setFloatUniforms(initialIndex: 2, (value) {
        value
          ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
          ..setSize(_geometryMatteBounds.size * devicePixelRatio);
      })
      ..setFloatUniforms(initialIndex: 34, (value) {
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
      // Float index 57, after uBackdropBounds: uBackdropOrigin, zero for a
      // filter, whose fragment coordinates are its input's.
      ..setFloatUniforms(initialIndex: 57, (value) {
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
    if (_materialImage case final materialImage? when _usesShapeAppearances) {
      if (_usesTintOnlyAppearance) {
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
        !identical(_materialImage, _boundMaterialImage) ||
        _geometryMatteBounds != _boundMatteBounds) {
      _boundRenderShader = activeRenderShader;
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = _materialImage;
      _boundMatteBounds = _geometryMatteBounds;
      _shaderInputsChanged = true;
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
    passOrigin: _rig.passPlan.globalOrigin,
  );

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null) return null;
    final translation = compositorTranslation;
    // The backdrop the filter reads is the seeded pass, which holds nothing
    // outside its rect.
    final pass = _rig.passPlan.frameLocalRect;
    // Unblurred, the filter input is the backdrop inside the filter's own
    // clip. With a blur pass, Impeller re-rasterizes the blurred input into
    // the filter's coverage, which every clip around the filter narrows: the
    // retained clips between this layer and its shapes, and the clips above
    // this layer up to its pass. The texture is transparent outside it.
    if (blurPassSigma <= 0) return pass == null ? clip : clip.intersect(pass);
    var captured = clip.shift(translation);
    if (pass != null) captured = captured.intersect(pass.shift(translation));
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
    // The pass origin is part of the mapping, so it is placed first.
    _syncBackdropPass();
    final mapping = _currentCoordinateMapping();
    final backdropBounds = backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _shaderInputsChanged = true;
    _writeCoordinateMapping(renderShader, mapping, backdropBounds);
    return changed;
  }

  (double, double, double, double, double, double) _currentCoordinateMapping() {
    final globalToMatte = Matrix4.inverted(shaderCoordinateTransform);
    final origin = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
    final axisX = MatrixUtils.transformPoint(globalToMatte, const Offset(1, 0));
    final axisY = MatrixUtils.transformPoint(globalToMatte, const Offset(0, 1));
    return (
      axisX.dx - origin.dx,
      axisY.dx - origin.dx,
      axisX.dy - origin.dy,
      axisY.dy - origin.dy,
      origin.dx * devicePixelRatio,
      origin.dy * devicePixelRatio,
    );
  }

  void _writeCoordinateMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    shader.setFloatUniforms(initialIndex: 46, (value) {
      value.setFloats([
        mapping.$1,
        mapping.$2,
        mapping.$3,
        mapping.$4,
        mapping.$5,
        mapping.$6,
      ]);
    });
    // Float index 53, after uBlurFade.
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloatUniforms(initialIndex: 53, (value) {
      value.setFloats([
        matteBounds.left * devicePixelRatio,
        matteBounds.top * devicePixelRatio,
        matteBounds.right * devicePixelRatio,
        matteBounds.bottom * devicePixelRatio,
      ]);
    });
  }

  // MARK: Native filter

  // The live read: a filter in a clip, inside a seeded pass while seeds are
  // on and the frost blurs. Whether the pass is in effect changes the
  // coordinate mapping, so the rig reports it through onActiveChanged. No
  // share: a filter inside a seeded pass reads that pass, and sharing one
  // backdrop would hand every glass the first one's pass.
  late final _rig = BackdropRig(
    plan: planBackdropPass,
    onActiveChanged: _onPassActiveChanged,
  );

  // The clip around the filter in the coordinates of the layer holding the
  // pass.
  Rect? _innerClipLayerRect;

  @visibleForTesting
  SeededBackdropPassLayer? get debugBackdropPassLayer => _rig.passLayer;

  @visibleForTesting
  BackdropPassPlan get debugBackdropPassPlan => _rig.passPlan;

  /// How far the blur reads past the filter's clip: three sigma plus one
  /// logical pixel, or nothing without a blur.
  double get _passReach {
    final sigma = _frostSigmaForCurrentShapes();
    return sigma > 0 ? sigma * 3 + 1 : 0;
  }

  // Requests the pass. Whether it is in effect is the pass layer's decision,
  // made when it composes, so the plan that shaders map coordinates by is
  // the requested one only while the layer says so. The rig may pin the clip
  // to the pass, and nothing the shader reads depends on the clip's size:
  // [backdropSampleBounds] is derived from the bucketed bounds, and the
  // coordinate mapping depends only on the pass origin.
  void _syncBackdropPass() {
    _rig.place(
      drawableEmpty ? null : _innerClipLayerRect,
      _filterPaintOffset,
      _passReach,
    );
  }

  // The pass layer switched between seeding and painting without a pass while
  // the scene was being prepared: map coordinates for the one that
  // will be built, before the filter is added to the scene.
  void _onPassActiveChanged() {
    if (attached) _resyncMappingIntoFilter();
  }

  // Re-syncs the coordinate mapping into the retained filter, or repaints
  // when its inputs cannot be reused.
  void _resyncMappingIntoFilter() {
    if (!syncCoordinateMapping()) return;
    if (!drawableEmpty && hasReusableGeometry && _rig.filterLayer != null) {
      _bindFilter();
    } else {
      GlassComposer.repaint(this);
    }
  }

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _rig.filterLayer;

  /// The most recent layer-local clip used by the native glass filter.
  ///
  /// This intentionally excludes exterior-shadow support, which is painted in
  /// a separate canvas layer before the clipped filter pass.
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
  ImageFilter? _cachedShaderFilter;
  double? _filterFrostSigma;

  // Hands the filter to its layer. A seeded pass may take the blur over and
  // keep only the shader (see SeededBackdropPassLayer.bindFilter): the shader
  // inputs it sees are the same either way, because the blurred pass is what
  // the filter would have produced, so uBlurFade and the sample bounds stay
  // those of a blurred filter.
  void _bindFilter() {
    final full = _updateShaderFilter();
    final sigma = _filterFrostSigma ?? 0;
    _rig.bindFilter(
      full,
      sigma > 0
          ? PassBlur(sigma: sigma, withoutBlur: _cachedShaderFilter!)
          : null,
    );
  }

  ImageFilter _updateShaderFilter() {
    final inputsChanged = takeShaderInputsChanged();
    final frostSigma = _frostSigmaForCurrentShapes();
    if (_cachedFilter != null &&
        !inputsChanged &&
        frostSigma == _filterFrostSigma) {
      return _cachedFilter!;
    }
    final shader = ImageFilter.shader(renderShader);
    final filter = frostSigma > 0
        ? ImageFilter.compose(
            inner: ImageFilter.blur(
              tileMode: glassBlurTileMode,
              sigmaX: frostSigma,
              sigmaY: frostSigma,
            ),
            outer: shader,
          )
        : shader;
    _cachedFilter = filter;
    _cachedShaderFilter = shader;
    _filterFrostSigma = frostSigma;
    return filter;
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
      _cachedFilter = null;
      _cachedShaderFilter = null;
      _syncBackdropPass();
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
      _paintOverSolid(context, offset, materialBounds);
      return;
    }
    // Without seeds or a blur there is no pass: the clip and the filter
    // paint directly in this layer.
    _rig.usesPass = seedsBackdrop && _passReach > 0;
    final filterBounds = _syncMaterialFilter(materialBounds, offset);

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
      copies: _wantsUnderlay && !drawableEmpty,
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
    final shader = renderShader
      // uSize, which the engine fills in only for a filter. Only backdrop
      // reads divide by it, so any nonzero size works.
      ..setFloat(0, max(filterBounds.width * dpr, 1))
      ..setFloat(1, max(filterBounds.height * dpr, 1))
      ..setFloat(46, dpr)
      ..setFloat(47, 0)
      ..setFloat(48, 0)
      ..setFloat(49, dpr)
      ..setFloat(50, -offset.dx * dpr)
      ..setFloat(51, -offset.dy * dpr)
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

  /// Drops native backdrop-filter state while this sample is idle.
  void _releaseCompositorFilter() {
    _rig.clear();
    _innerClipLayerRect = null;
    _cachedFilter = null;
    _cachedShaderFilter = null;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // Retained geometry follows the move in onPreparing; glass with nothing
    // to reuse repaints.
    if (!hasReusableGeometry && !hasReusableIdleContents) {
      GlassComposer.repaint(this);
    }
  }

  @override
  void onPreparing() {
    runCompositorPoll();
    _asked = _rig.hasSlot ? _askUnderlay() : null;
  }

  @override
  void onCompositing() {
    if (_rig.hasSlot) _composeUnderlay();
  }

  // Chosen at compositing: what lies under the glass can change in a frame
  // in which this layer does not repaint. The slot holds the live filter
  // (the seeded pass, or the clip around the filter) while what lies under
  // the glass cannot be copied.
  void _composeUnderlay() {
    // Glass over its copy reads no backdrop: an opacity pass around it needs
    // no seed.
    compositionSeedSuppressed = true;
    final served = _recordUnderlay();
    if (served == null) compositionSeedSuppressed = false;
    debugDrewOverUnderlay = served != null;
    _rig.show(served);
  }

  /// How many device pixels along each side one pixel of a frosted copy
  /// stands for at most.
  ///
  /// NEAR: a copy drawn at half size differs from the full one by at most 10
  /// channel levels on the Pixel 6a (5 in the scroll scene, 10 under the
  /// crowd of buttons), and by 15 in the host test of white text under 8 px
  /// of frost at dpr 1, where half size draws the text bolder. In return the
  /// Pixel's rails spend 7 % less on a dot or the Liquid tab and 32 % less
  /// under the crowd. A quarter size differs by 15 on the Liquid tab and
  /// saves no more.
  @visibleForTesting
  static int debugMaxCopyDownscale = 2;

  // The blur, in the copy's own pixels, that hides its size.
  static const double _copySigma = 2.5;

  // This frame's copy asked for: the glass's transform to the screen, the
  // logical rect the shader draws and the material it paints there.
  ({Matrix4 screen, Rect logical, Rect drawn})? _asked;

  // Asks for the copy of what lies under the glass, or returns null when the
  // glass reads its backdrop this frame.
  ({Matrix4 screen, Rect logical, Rect drawn})? _askUnderlay() {
    final bounds = _filterMaterialBounds;
    final anchor = layer;
    if (bounds == null || anchor == null || drawableEmpty) return null;
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
    // same blur unscaled: NEAR, at most 7 channel levels apart in the host
    // test of glass stretched 1.2 x 0.8 under 6 px of frost, and only while
    // the glass is scaled.
    final storage = screen.storage;
    final scaleX = storage[0];
    final scaleY = storage[5];
    if (scaleX <= 0 ||
        scaleY <= 0 ||
        storage[1].abs() > 1e-6 ||
        storage[4].abs() > 1e-6) {
      return null;
    }
    final logical = MatrixUtils.transformRect(
      screen,
      bounds.expandToPixelBuckets(dpr),
    );
    // What the shader paints: the material, not the rect it is drawn in.
    final drawn = MatrixUtils.transformRect(screen, bounds);
    final sigma = _frostSigmaForCurrentShapes();
    final frostX = sigma * scaleX;
    final frostY = sigma * scaleY;
    // A copy blurred by at least [_copySigma] of its own pixels is drawn as
    // the blur leaves it at a fraction of the screen's pixels: sampled back
    // up, it adds a tent of its pixel's width to a blur many times wider.
    var downscale = 1;
    while (downscale * 2 <= debugMaxCopyDownscale &&
        min(frostX, frostY) * dpr / (downscale * 2) >= _copySigma) {
      downscale *= 2;
    }
    _rig.underlay.request(
      anchor: anchor,
      own: paintLayer,
      devicePixelRatio: dpr,
      region: drawn.inflate(
        (backdropSamplingReach(bounds) + 1) * max(scaleX, scaleY),
      ),
      blur: sigma > 0 ? (frostX, frostY) : null,
      downscale: downscale,
      body: drawn,
    );
    return (screen: screen, logical: logical, drawn: drawn);
  }

  // The glass as one rect painted with the final shader over the underlay's
  // copy, or null when there is no copy. The shader reads the copy as
  // a filter reads its input: fragment coordinates are taken from the copy's
  // origin (uBackdropOrigin), so the mapping into the matte is the screen's
  // shifted by that origin.
  PictureLayer? _recordUnderlay() {
    final asked = _asked;
    _asked = null;
    if (asked == null) return null;
    final copy = _rig.underlay.serve();
    if (copy == null) return null;
    final (:screen, :logical, :drawn) = asked;
    final dpr = devicePixelRatio;
    final canvasToScreen = screen.clone();
    canvasToScreen.multiply(
      Matrix4.translationValues(
        -_filterPaintOffset.dx,
        -_filterPaintOffset.dy,
        0,
      ),
    );
    final screenToCanvas = Matrix4.zero();
    if (screenToCanvas.copyInverse(canvasToScreen) == 0) return null;
    screenToCanvas.multiply(Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1));
    final globalToMatte = Matrix4.inverted(screen);
    final device = Rect.fromLTRB(
      logical.left * dpr,
      logical.top * dpr,
      logical.right * dpr,
      logical.bottom * dpr,
    );
    // The compositor poll wrote this frame's bounds to the live filter.
    final backdropBounds = _backdropBounds;
    assert(
      backdropBounds == backdropSampleBounds,
      'The copy samples the bounds the live filter does.',
    );
    final paintOffset = _filterPaintOffset;
    // The live filter's inputs, as one object: a new one whenever a uniform
    // or sampler changed.
    Object keyOf() => (
      copy.image,
      copy.offset,
      copy.rect,
      _updateShaderFilter(),
      device,
      backdropBounds,
      paintOffset,
      screen,
    );
    ui.Picture record() {
      final image = copy.image;
      // The shader reads the copy in device pixels: a smaller copy stands
      // for an image as many times larger.
      final stretch = dpr / copy.pixelRatio;
      final origin = copy.rect.topLeft * dpr - copy.offset * stretch;
      final o = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
      final ax = MatrixUtils.transformPoint(
        globalToMatte,
        const Offset(1, 0),
      );
      final ay = MatrixUtils.transformPoint(
        globalToMatte,
        const Offset(0, 1),
      );
      final mapping = (
        ax.dx - o.dx,
        ay.dx - o.dx,
        ax.dy - o.dy,
        ay.dy - o.dy,
        o.dx * dpr + (ax.dx - o.dx) * origin.dx + (ay.dx - o.dx) * origin.dy,
        o.dy * dpr + (ax.dy - o.dy) * origin.dx + (ay.dy - o.dy) * origin.dy,
      );
      final shader = renderShader;
      _writeCoordinateMapping(shader, mapping, backdropBounds);
      shader.setFloat(0, image.width * stretch);
      shader.setFloat(1, image.height * stretch);
      shader.setFloat(_FinalUniforms.backdropOrigin, origin.dx);
      shader.setFloat(_FinalUniforms.backdropOrigin + 1, origin.dy);
      shader.setFloat(_FinalUniforms.reducedBackdrop, stretch > 1 ? 1 : 0);
      shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.transform(screenToCanvas.storage);
      final paint = Paint();
      paint.shader = shader;
      // The filter's clip cuts its output with a hard edge.
      paint.isAntiAlias = false;
      canvas.drawRect(device, paint);
      // The live filter takes the shader's uniforms when it is next created:
      // they go back to the filter's.
      shader.setFloat(_FinalUniforms.backdropOrigin, 0);
      shader.setFloat(_FinalUniforms.backdropOrigin + 1, 0);
      shader.setFloat(_FinalUniforms.reducedBackdrop, 0);
      if (_coordinateMapping case final live?) {
        _writeCoordinateMapping(shader, live, _backdropBounds);
      }
      if (_geometryImage case final matte?) {
        shader.setImageSampler(0, matte, filterQuality: FilterQuality.low);
      }
      return recorder.endRecording();
    }

    // A copy for glass nearby holds this glass only where it paints.
    final pictureBounds = MatrixUtils.transformRect(
      screenToCanvas,
      Rect.fromLTRB(
        drawn.left * dpr,
        drawn.top * dpr,
        drawn.right * dpr,
        drawn.bottom * dpr,
      ),
    ).inflate(1);
    return _rig.servedPicture(
      copy,
      pictureBounds,
      keyOf: keyOf,
      record: record,
    );
  }

  @override
  void onCompositorTranslated(Offset translation) {
    final clip = _filterClip;
    if (clip != null && _rig.hasClip) {
      _innerClipLayerRect = clip.shift(_filterPaintOffset);
      _rig.clipTo(_innerClipLayerRect!);
    }
    // Also moves the pass, whose placement depends on where the glass is now.
    final remapped = syncCoordinateMapping();
    if (remapped && !drawableEmpty && hasReusableGeometry) {
      if (_rig.filterLayer != null) _bindFilter();
    }
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
        refreshRetainedGeometry((shapes, bounds, offset) {
          _syncMaterialFilter(bounds, offset);
        })) {
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
    _cachedFilter = null;
    _cachedShaderFilter = null;
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
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

  // The encoder's drawable-shape decision. Called only while preparing
  // geometry, never during retained compositing sync.
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
    _shaderInputsChanged = true;
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
    bool writeMatte = true,
  }) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    try {
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
      final materialCenter = writeMatte
          ? bounds.center
          : _materialCenterInMatte;

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
            ..add(
              shape.appearance.visibility <= 0
                  ? 0
                  : shape.rawShapeType.shaderIndex,
            )
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
        edgeDistanceRange:
            settings.effectiveEdgeDistanceRange * devicePixelRatio,
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
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
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

/// Float indices of what the final shader declares after uLowResOptics: the
/// optional effects' uEffects (liquid_glass_final_render_core.glsl).
abstract final class _FinalUniforms {
  /// uSolidBackdrop, four floats.
  static const int solidBackdrop = 139;

  /// uGlowSpot, uGlowBox and uGlowShape, twelve floats.
  static const int glow = 143;

  /// uBackdropShrinkAxis, two floats.
  static const int shrinkAxis = 155;

  /// uBackdropReduced, one float.
  static const int reducedBackdrop = 157;

  /// uBackdropOverlay, four floats.
  static const int overlay = 159;

  /// uBackdropOrigin, two floats.
  static const int backdropOrigin = 57;

  /// The analytic variant's first uniform, uAnalyticHeader, after uEffects.
  static const int analytic = 163;
}
