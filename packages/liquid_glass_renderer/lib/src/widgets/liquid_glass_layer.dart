import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/widgets/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/fake_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_host.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/widgets/multi_shader_builder.dart';

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
    super.key,
  }) : live = null;

  /// Creates a [LiquidGlassLayer] whose settings and field follow [frame].
  ///
  /// Every notification writes the new frame straight into the layer's
  /// render object, so the glass the layer draws shows it in the same
  /// frame; nothing rebuilds. Widgets below that read the settings from the
  /// tree ([settingsOf], a nested [LiquidGlass] that opens its own layer, a
  /// [FakeGlass] without settings of its own) see those of the frame the
  /// layer last built with. A layer that draws fake glass, or whose shaders
  /// are still loading, draws no field, and rebuilds for those readers when
  /// the frame's settings change.
  const LiquidGlassLayer.live({
    required ValueListenable<LiquidGlassLayerFrame> frame,
    required this.child,
    this.defaultAppearance,
    this.fake = false,
    this.backdrop = const LiquidGlassBackdrop.read(),
    super.key,
  }) : live = frame,
       settings = const LiquidGlassSettings(),
       field = null;

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
  /// The layer also draws fake glass while full glass loads and where it
  /// does not draw, for example on Skia ([LiquidGlass.support]).
  final bool fake;

  /// The distance field of the one body this layer's shapes form, when the
  /// caller has fused them already.
  ///
  /// The layer then shades the body the field describes instead of its
  /// shapes' outlines and blend groups, and casts its shadows by the
  /// field's edge. See [LiquidGlassField].
  final LiquidGlassField? field;

  /// Where the glass takes what it shows through: read behind the layer by
  /// default, or a backdrop the caller knows. See [LiquidGlassBackdrop].
  final LiquidGlassBackdrop backdrop;

  /// The frames of a layer made with [LiquidGlassLayer.live], or null for
  /// one that uses [settings] and [field].
  final ValueListenable<LiquidGlassLayerFrame>? live;

  /// Whether there is a [LiquidGlassLayer] in the widget tree above the given
  /// [context].
  static bool existsIn(BuildContext context, {bool watch = true}) {
    return LiquidGlassRenderScope.maybeOf(context, watch: watch) != null;
  }

  /// The settings of the nearest [LiquidGlassLayer] above [context], which
  /// its glass draws with; [context] rebuilds when they change.
  ///
  /// There must be such a layer: see [existsIn].
  static LiquidGlassSettings settingsOf(BuildContext context) =>
      LiquidGlassRenderScope.of(context).settings;

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer> {
  final _link = GeometryRenderLink();

  // Debug builds say once per process why layers draw fake glass.
  static bool _loggedFallback = false;

  // Fake and real subtrees never coexist, so one key keeps the user's subtree
  // alive across a renderer swap without ever being mounted twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  // The layer's render object, real or fake, which a live frame is written
  // into.
  final _layerKey = GlobalKey(debugLabel: 'LiquidGlassLayer.layer');

  LiquidGlassSettings get _settings =>
      widget.live?.value.settings ?? widget.settings;

  // The settings the fake subtree was built with.
  LiquidGlassSettings? _builtSettings;
  LiquidGlassField? get _field => widget.live?.value.field ?? widget.field;

  bool _rebuildPending = false;

  void _onLiveFrame() {
    final frame = widget.live!.value;
    final layer = _layerKey.currentContext?.findRenderObject();
    if (layer is RenderLiquidGlassLayer) {
      layer
        ..settings = frame.settings
        ..field = frame.field;
      return;
    }
    if (layer is LiquidGlassRenderObject) layer.settings = frame.settings;
    if (frame.settings != _builtSettings) _rebuild();
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
    // After the frame: the layer and its shapes drew the new settings
    // already; this brings only the widgets that read them from the tree up
    // to date.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildPending = false;
      if (mounted) setState(() {});
    });
  }

  void _onFullGlass() {
    if (!widget.fake) setState(() {});
  }

  void _logFallback(LiquidGlassSupport support) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint(
      'liquid_glass_renderer: LiquidGlassLayer is using FakeGlass. '
      '${support.unavailableReason} Enable Impeller and Flutter GPU for the '
      'full glass effect.',
    );
  }

  @override
  void initState() {
    super.initState();
    FullGlass.state.addListener(_onFullGlass);
    widget.live?.addListener(_onLiveFrame);
  }

  @override
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.live, widget.live)) {
      oldWidget.live?.removeListener(_onLiveFrame);
      widget.live?.addListener(_onLiveFrame);
    }
  }

  @override
  void dispose() {
    FullGlass.state.removeListener(_onFullGlass);
    widget.live?.removeListener(_onLiveFrame);
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
    _builtSettings = _settings;
    final glass = widget.fake ? null : FullGlass.state.value;
    switch (glass) {
      case FullGlassPending():
        FullGlass.loadAfterFrame();
      case FullGlassUnavailable(:final support):
        _logFallback(support);
      case FullGlassReady() || null:
        break;
    }
    if (glass is! FullGlassReady) {
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
        child: GlassHost.layer(
          link: _link,
          child: _RawShapes(
            key: _layerKey,
            glass: glass,
            field: _field,
            solidBackdrop: widget.backdrop.solidColor,
            settings: _settings,
            defaultAppearance: defaultAppearance,
            link: _link,
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
          child: GlassHost.layer(
            link: _link,
            child: ConsolidatedFakeGlassLayer(
              key: _layerKey,
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
      assetKeys: ShaderKeys.fakeSurfaceAssets,
      (_, shaders, _) => buildFakeSurfaceLayer(shaders.firstOrNull),
      child: buildFakeSurfaceLayer(null),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.glass,
    required this.field,
    required this.solidBackdrop,
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    super.key,
  });

  final FullGlassReady glass;
  final LiquidGlassField? field;

  final Color? solidBackdrop;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
        glass: glass,
        devicePixelRatio: glassDevicePixelRatioOf(context),
        settings: settings,
        defaultAppearance: defaultAppearance,
        link: link,
      )
      ..field = field
      ..solidBackdrop = solidBackdrop;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..field = field
      ..solidBackdrop = solidBackdrop;
  }
}
