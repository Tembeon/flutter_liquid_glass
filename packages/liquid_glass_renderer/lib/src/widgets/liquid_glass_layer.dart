import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_backdrop.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_glow.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
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
                settings: _settings,
                defaultAppearance: defaultAppearance,
                link: _link,
                gpuGeometryRenderer: gpuRenderer,
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
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    this.gpuGeometryRenderer,
    super.key,
  });

  final List<FragmentShader> finalShaders;
  final LiquidGlassField? field;

  final Color? solidBackdrop;
  final LiquidGlassGlow? glow;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        finalShaders: finalShaders,
        settings: settings,
        defaultAppearance: defaultAppearance,
        link: link,
        gpuGeometryRenderer: gpuGeometryRenderer,
      )
      ..field = field
      ..solidBackdrop = solidBackdrop
      ..glow = glow;
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
      ..field = field
      ..solidBackdrop = solidBackdrop
      ..glow = glow;
  }
}
