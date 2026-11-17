import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/widgets/fake_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_host.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_visibility.dart';
import 'package:liquid_glass_renderer/src/widgets/optimized_clip.dart';

/// A liquid glass shape.
///
/// To render liquid glass, you probably want to wrap this in a
/// [LiquidGlassLayer], where the glass effect will be rendered.
///
/// This can either create a single shape, or be blended together with other
/// shapes in a parent [LiquidGlassBlendGroup] by using the
/// [LiquidGlass.grouped] constructor.
///
/// If you only need a single shape with its own settings, you can also use the
/// [LiquidGlass.withOwnLayer] constructor, which will create its own
/// [LiquidGlassLayer] internally. The regular constructor also creates
/// an independent sample when nested inside another glass shape, inheriting
/// the containing layer's settings. Siblings still share their parent sample.
///
/// If you don't know whether a [LiquidGlassLayer] ancestor exists, use the
/// [LiquidGlass.auto] constructor. It will render on a parent layer if one is
/// found, or create its own layer otherwise. Place a [LiquidGlassLayer] around
/// chrome (tab bars, toolbars) so sibling `auto` widgets share that sample.
///
/// See the [LiquidGlassLayer] documentation for more information.
///
/// ## Transforms
///
/// The glass follows the shape's layout position and transforms applied by
/// widgets like [Transform] or [RotatedBox]. Transforms applied only to the
/// paint canvas, for example by a [Flow] delegate or a
/// `PaintingContext.pushTransform` call that does not push a composited
/// layer, are invisible to the glass: the [child] will transform but the
/// glass stays behind. In those cases, apply the transform with a widget
/// like [Transform] instead.
class LiquidGlass extends StatefulWidget {
  /// Creates a new [LiquidGlass] with the given [child] and [shape].
  ///
  /// This will expect a parent [LiquidGlassLayer] to be present in the widget
  /// tree, where the liquid glass effect will be rendered.
  const LiquidGlass({
    required this.child,
    required LiquidShape this.shape,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
    super.key,
  }) : _placement = _Placement.onLayer,
       _ownLayer = null,
       frame = null;

  /// Creates a new [LiquidGlass] that automatically renders on a parent
  /// [LiquidGlassLayer] if one exists, or creates its own layer if not.
  ///
  /// This is useful when you don't know whether a [LiquidGlassLayer] ancestor
  /// is present. If one is found in the widget tree, the glass will render on
  /// that layer. Otherwise, it will create its own layer with the given
  /// [settings] (or those of [LiquidGlassLayer.settings] if not provided).
  ///
  /// Note that creating many individual layers can be expensive, so prefer
  /// placing a [LiquidGlassLayer] ancestor in the tree when possible. Sibling
  /// [LiquidGlass.auto] widgets under that ancestor share one backdrop sample
  /// and do not blend unless they are also inside a [LiquidGlassBlendGroup].
  /// If another [LiquidGlass] appears before that layer, this creates a new
  /// layer instead so nested glass never renders into the same sample.
  const LiquidGlass.auto({
    required this.child,
    required LiquidShape this.shape,
    LiquidGlassSettings? settings,
    bool fake = false,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
  }) : _placement = _Placement.auto,
       _ownLayer = (settings: settings, fake: fake),
       frame = null;

  /// Creates a new [LiquidGlass] that is part of a [LiquidGlassBlendGroup].
  ///
  /// This will expect a parent [LiquidGlassBlendGroup] to be present in the
  /// widget tree, as well as a parent [LiquidGlassLayer] above that, where the
  /// result will be rendered.
  const LiquidGlass.grouped({
    required this.child,
    required LiquidShape this.shape,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
  }) : _placement = _Placement.grouped,
       _ownLayer = null,
       frame = null;

  /// Creates a [LiquidGlass] with its own [LiquidGlassLayer].
  ///
  /// Use it for glass that sits on other glass or needs its own
  /// [LiquidGlassSettings]; shapes that share settings are cheaper in one
  /// shared [LiquidGlassLayer].
  const LiquidGlass.withOwnLayer({
    required this.child,
    required LiquidShape this.shape,
    LiquidGlassSettings? settings,
    bool fake = false,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
  }) : _placement = _Placement.ownLayer,
       _ownLayer = (settings: settings, fake: fake),
       frame = null;

  /// Creates a shape whose geometry, material and shadows follow [frame].
  ///
  /// Every notification of [frame] writes the new frame straight into the
  /// shape's render objects, on real and fake glass alike; the widget
  /// rebuilds only when the kind of shape changes or its shadows appear or
  /// vanish. The frame's rect and scale never rebuild or lay out anything.
  ///
  /// The child is laid out in the widget's box and drawn centered on the
  /// frame's rect, so content stays in the middle of glass that grows or
  /// shrinks.
  ///
  /// Hit testing follows the box the widget was laid out in, not the rect
  /// the frame draws it at, as UIKit hit-tests a view's model rather than
  /// its presentation.
  ///
  /// With `grouped` true, the shape joins the nearest
  /// [LiquidGlassBlendGroup].
  const LiquidGlass.live({
    required ValueListenable<LiquidGlassShapeFrame> this.frame,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    bool grouped = false,
    super.key,
  }) : shape = null,
       shadows = const [],
       appearance = null,
       _placement = grouped ? _Placement.grouped : _Placement.onLayer,
       _ownLayer = null;

  /// The child of this widget.
  ///
  /// Painted above the glass effect and clipped by [clipBehavior].
  final Widget child;

  /// {@template liquid_glass_renderer.LiquidGlass.shape}
  /// The shape of this glass.
  /// {@endtemplate}
  ///
  /// Null for a live shape ([LiquidGlass.live]), which takes it from its
  /// [frame].
  final LiquidShape? shape;

  /// The source of a live shape's frames, or null for a fixed shape.
  final ValueListenable<LiquidGlassShapeFrame>? frame;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.hardEdge], so [child] is clipped to the glass shape.
  final Clip clipBehavior;

  final _Placement _placement;

  /// The layer this glass makes for itself: set for [_Placement.auto] and
  /// [_Placement.ownLayer] only.
  final _OwnLayerConfig? _ownLayer;

  /// The list of shadows to paint.
  ///
  /// A containing [LiquidGlassLayer] composes shadows from its real shapes
  /// together and cuts every glass silhouette out of the combined stack; a
  /// shape alone on its layer casts them as
  /// [LiquidGlassSilhouette.paintShadows] does.
  ///
  /// Empty for a live shape, which takes them from its [frame].
  final List<LiquidGlassShadow> shadows;

  /// Color and materialization override for this shape.
  ///
  /// Omit this to inherit the containing layer's default appearance. Null
  /// for a live shape, which takes it from its [frame].
  final LiquidGlassAppearance? appearance;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('shape', shape, defaultValue: null))
      ..add(DiagnosticsProperty('frame', frame, defaultValue: null))
      ..add(
        EnumProperty('clipBehavior', clipBehavior, defaultValue: Clip.hardEdge),
      )
      ..add(IterableProperty('shadows', shadows, ifEmpty: null))
      ..add(DiagnosticsProperty('appearance', appearance, defaultValue: null));
  }
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// Keeps [LiquidGlass.child] mounted when the layer switches this shape
  /// between its fake and real subtrees.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlass.child');

  // The render objects a live frame is written into, and what the tree was
  // built with: a frame that keeps the structure goes straight to them.
  final _rawKey = GlobalKey(debugLabel: 'LiquidGlass.raw');
  final _fakeKey = GlobalKey(debugLabel: 'LiquidGlass.fake');
  final _fadeKey = GlobalKey(debugLabel: 'LiquidGlass.fade');
  LiquidGlassShapeFrame? _built;
  LiquidGlassShapeFrame? _last;
  late LiquidGlassAppearance _defaultAppearance;
  double _visibility = 1;

  @override
  void initState() {
    super.initState();
    widget.frame?.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(covariant LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) {
      oldWidget.frame?.removeListener(_onFrame);
      widget.frame?.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    widget.frame?.removeListener(_onFrame);
    super.dispose();
  }

  void _onFrame() {
    final frame = widget.frame!.value;
    final last = _last;
    _last = frame;
    // The rect and scale reach the render objects that listen to the frame.
    if (last != null &&
        frame.shape == last.shape &&
        frame.appearance == last.appearance &&
        listEquals(frame.shadows, last.shadows)) {
      return;
    }
    final built = _built;
    if (built == null || frame.shape.runtimeType != built.shape.runtimeType) {
      setState(() {});
      return;
    }
    final appearance = _visibleAppearance(frame.appearance);
    if (_rawKey.currentContext?.findRenderObject()
        case final RenderLiquidGlass raw) {
      raw
        ..shape = frame.shape
        ..layerShadows = frame.shadows
        ..appearance = frame.appearance;
    }
    if (_fakeKey.currentContext?.findRenderObject()
        case final RenderFakeGlass fake) {
      fake
        ..shape = frame.shape
        ..shownAppearance = appearance;
    }
    if (_fadeKey.currentContext?.findRenderObject()
        case final RenderOpacity fade) {
      fade.opacity = drawnVisibility(appearance.visibility);
    }
  }

  LiquidShape get _shape => widget.frame?.value.shape ?? widget.shape!;

  List<LiquidGlassShadow> get _shadows =>
      widget.frame?.value.shadows ?? widget.shadows;

  LiquidGlassAppearance? get _appearance => switch (widget.frame) {
    final frame? => frame.value.appearance,
    null => widget.appearance,
  };

  Widget get _keyedChild {
    final child = KeyedSubtree(
      key: _childKey,
      child: GlassHost.body(child: widget.child),
    );
    return switch (widget.frame) {
      final frame? => _CenteredOnRect(live: frame, child: child),
      null => child,
    };
  }

  @override
  Widget build(BuildContext context) {
    _built = _last = widget.frame?.value;
    final glass = _buildShape(context);
    final frame = widget.frame;
    return frame == null ? glass : _LiveGlassFrame(frame: frame, child: glass);
  }

  // Join an existing sample whenever one is already in the tree. Creating a
  // layer is the fallback, not the default for a row of siblings.
  Widget _buildShape(BuildContext context) {
    final host = GlassHost.of(context);
    final inBody = host != null && host.inBody;
    return switch (widget._placement) {
      _Placement.auto when host != null && !inBody => _buildGlass(context),
      _Placement.auto || _Placement.ownLayer => _buildOwnLayer(
        widget._ownLayer!,
      ),
      _Placement.onLayer || _Placement.grouped when inBody => nestedGlassLayer(
        context,
        _buildGlass,
      ),
      _Placement.onLayer || _Placement.grouped => _buildGlass(context),
    };
  }

  Widget _buildOwnLayer(_OwnLayerConfig config) => LiquidGlassLayer(
    settings: config.settings,
    defaultAppearance: _appearance,
    fake: config.fake,
    child: Builder(builder: _buildGlass),
  );

  LiquidGlassAppearance _visibleAppearance(LiquidGlassAppearance? own) =>
      shownAppearance(
        own,
        layerDefault: _defaultAppearance,
        visibility: _visibility,
      );

  /// Renders this shape on the nearest [LiquidGlassLayer].
  ///
  /// Grouped constructors join a [LiquidGlassBlendGroup] when one exists.
  /// Otherwise the shape registers directly on the layer so siblings share
  /// one backdrop sample without a dummy blend group.
  Widget _buildGlass(BuildContext context) {
    final scope = LiquidGlassRenderScope.of(context);
    _defaultAppearance = scope.defaultAppearance;
    _visibility = LiquidGlassVisibility.of(context);
    final shape = _shape;
    final appearance = _visibleAppearance(_appearance);
    final host = GlassHost.of(context);
    final blendGroupLink = switch (widget._placement) {
      _Placement.grouped || _Placement.auto => host?.group,
      _Placement.onLayer || _Placement.ownLayer => null,
    };
    return _RawLiquidGlass(
      key: _rawKey,
      blendGroupLink: blendGroupLink,
      renderLink: blendGroupLink == null ? host?.link : null,
      appearance: _appearance,
      visibility: _visibility,
      devicePixelRatio: glassDevicePixelRatioOf(context),
      shape: shape,
      layerShadows: _shadows,
      live: widget.frame,
      child: scope.fake
          ? FakeGlassSurface(
              shape: shape,
              settings: scope.settings,
              appearance: appearance,
              clipBehavior: widget.clipBehavior,
              role: FakeGlassRole.layerPaints,
              live: widget.frame,
              fakeKey: _fakeKey,
              fadeKey: _fadeKey,
              child: _keyedChild,
            )
          : OptimizedClip(
              shape: shape,
              clipBehavior: widget.clipBehavior,
              live: widget.frame,
              child: Opacity(
                key: _fadeKey,
                opacity: drawnVisibility(appearance.visibility),
                child: _keyedChild,
              ),
            ),
    );
  }
}

/// Where a shape draws, which its constructor decides. A live shape
/// ([LiquidGlass.frame]) draws where a fixed one does: only its values come
/// from elsewhere.
enum _Placement {
  /// On the nearest layer beside its siblings; under another glass, in a
  /// layer of its own with the outer glass's settings.
  onLayer,

  /// In the nearest [LiquidGlassBlendGroup], or on the nearest layer when
  /// there is none; under another glass, as [onLayer] there.
  grouped,

  /// As [grouped] when a layer is nearer than any glass above; otherwise in
  /// a layer of its own.
  auto,

  /// Always in a layer of its own made with [LiquidGlass._ownLayer].
  ownLayer,
}

typedef _OwnLayerConfig = ({
  LiquidGlassSettings? settings,
  bool fake,
});

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.layerShadows,
    required this.blendGroupLink,
    required this.renderLink,
    required this.appearance,
    required this.visibility,
    required this.devicePixelRatio,
    required this.live,
    super.key,
  });

  final LiquidShape shape;

  final ValueListenable<LiquidGlassShapeFrame>? live;

  final List<LiquidGlassShadow> layerShadows;

  final GlassGroupLink? blendGroupLink;

  final GeometryRenderLink? renderLink;

  final LiquidGlassAppearance? appearance;

  final double visibility;

  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      layerShadows: layerShadows,
      blendGroupLink: blendGroupLink,
      renderLink: renderLink,
      appearance: appearance,
      visibility: visibility,
      devicePixelRatio: devicePixelRatio,
    )..live = live;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..layerShadows = layerShadows
      ..appearance = appearance
      ..visibility = visibility
      ..devicePixelRatio = devicePixelRatio
      ..live = live
      ..bindLinks(
        blendGroupLink: blendGroupLink,
        renderLink: renderLink,
      );
  }
}

class _LiveGlassFrame extends SingleChildRenderObjectWidget {
  const _LiveGlassFrame({required this.frame, required super.child});

  final ValueListenable<LiquidGlassShapeFrame> frame;

  @override
  RenderLiveGlassFrame createRenderObject(BuildContext context) =>
      RenderLiveGlassFrame(frame: frame);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiveGlassFrame renderObject,
  ) {
    renderObject.frame = frame;
  }
}

class _CenteredOnRect extends SingleChildRenderObjectWidget {
  const _CenteredOnRect({required this.live, required super.child});

  final ValueListenable<LiquidGlassShapeFrame> live;

  @override
  _RenderCenteredOnRect createRenderObject(BuildContext context) =>
      _RenderCenteredOnRect()..live = live;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnRect renderObject,
  ) {
    renderObject.live = live;
  }
}

class _RenderCenteredOnRect extends RenderProxyBox with LivePaintSize {
  Offset get _shift => hasSize ? body.childOffset : Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) =>
      super.paint(context, offset + _shift);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
