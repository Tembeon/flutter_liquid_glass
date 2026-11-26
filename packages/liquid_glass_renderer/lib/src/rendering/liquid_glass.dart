import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_place.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// One glass shape: it registers its geometry with its layer, or with the blend
/// group it joins, and holds its child.
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject, LivePaintSize {
  /// Creates the render object of one glass shape.
  RenderLiquidGlass({
    required this._shape,
    required this._layerShadows,
    required this._appearance,
    required this._visibility,
    required super.devicePixelRatio,
    required DrawnPlace place,
  }) : _place = place,
       super(
         renderLink: switch (place) {
           OnLayer(:final link) => link,
           InGroup() => null,
         },
       );

  LiquidGlassAppearance? _appearance;
  double _visibility;
  WornAppearance? _worn;
  Size? _wornAt;
  LiquidGlassAppearance? _wornOver;

  /// The appearance it was given, or null where it wears its layer's
  /// default.
  LiquidGlassAppearance? get appearance => _appearance;
  set appearance(LiquidGlassAppearance? value) {
    if (_appearance == value) return;
    _appearance = value;
    _lookChanged();
  }

  /// What the visibility around it multiplies its appearance's by.
  double get visibility => _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value;
    _lookChanged();
  }

  void _lookChanged() {
    _worn = null;
    // The owning layer draws its atlas again only when its shapes' looks
    // differ.
    _shapeChanged(outline: false);
    markNeedsPaint();
  }

  @override
  WornAppearance appearanceOn(LiquidGlassAppearance defaultAppearance) {
    final size = hasSize ? paintSize : Size.zero;
    if (_worn case final worn?
        when size == _wornAt && identical(defaultAppearance, _wornOver)) {
      return worn;
    }
    _wornAt = size;
    _wornOver = defaultAppearance;
    return _worn = shownAppearance(
      _appearance,
      layerDefault: defaultAppearance,
      visibility: _visibility,
    ).wear(size);
  }

  LiquidShape _shape;

  @override
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _shapeChanged(outline: true);
  }

  List<LiquidGlassShadow> _layerShadows;
  @override
  List<LiquidGlassShadow> get layerShadows => _layerShadows;
  set layerShadows(List<LiquidGlassShadow> value) {
    if (_layerShadows == value) return;
    _layerShadows = value;
    _shapeChanged(outline: false);
    markNeedsPaint();
  }

  DrawnPlace _place;

  static GlassGroupLink? _groupOf(DrawnPlace place) => switch (place) {
    InGroup(:final group) => group,
    OnLayer() => null,
  };

  // Tells what draws this glass that it changed: its blend group, or its own
  // geometry on the layer, which an outline change rebuilds.
  void _shapeChanged({required bool outline}) {
    switch (_place) {
      case InGroup(:final group):
        group.notifyShapeChanged(this);
      case OnLayer():
        if (outline) {
          markGeometryToRebuild();
        } else {
          markGeometryToCompare();
        }
    }
  }

  /// Registers this shape where it draws ([place]): grouped glass with its
  /// blend group, which packs it, standalone glass with its layer, as a
  /// geometry node of its own.
  void bindPlace(DrawnPlace place) {
    final from = _groupOf(_place);
    final moves = switch (place) {
      InGroup(:final group) => !identical(group, from),
      OnLayer(:final link) => from != null || !identical(link, renderLink),
    };
    if (moves) _reportGlow(draws: false);
    switch (place) {
      case InGroup(:final group):
        renderLink = null;
        _place = place;
        if (!identical(group, from)) {
          from?.unregisterShape(this);
          group.registerShape(this);
        }
      case OnLayer(:final link):
        _place = place;
        from?.unregisterShape(this);
        renderLink = link;
    }
    if (moves && glow != null) _reportGlow(draws: true);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _groupOf(_place)?.registerShape(this);
    if (glow != null) _reportGlow(draws: true);
  }

  @override
  void detach() {
    _reportGlow(draws: false);
    _groupOf(_place)?.unregisterShape(this);
    super.detach();
  }

  @override
  void liveGlowChanged() {
    if (attached) _reportGlow(draws: glow != null);
  }

  void _reportGlow({required bool draws}) {
    switch (_place) {
      case InGroup(:final group):
        group.reportGlow(this, draws: draws);
      case OnLayer(:final link):
        link.reportGlow(this, draws: draws);
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    _shapeChanged(outline: false);
  }

  @override
  void livePaintSizeChanged() {
    // A size change must not pass for the pure move a retained frame can
    // follow by translation.
    _shapeChanged(outline: true);
    markNeedsPaint();
  }

  @override
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes =>
      hasSize ? [this] : const [];

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData(
    LiquidGlassAppearance defaultAppearance,
  ) {
    if (!hasSize) return (Rect.zero, const [], false);
    final shapeData = ShapeGeometry(
      renderObject: this,
      shape: shape,
      appearance: appearanceOn(defaultAppearance),
      shapeBounds: Offset.zero & paintSize,
      shadows: castShadows,
    );
    final cached = geometry?.shapes ?? const <ShapeGeometry>[];
    final outlineChanged =
        cached.length != 1 || !cached.first.sameOutline(shapeData);
    return (shapeData.shapeBounds, [shapeData], outlineChanged);
  }
}

/// Moves and scales a live glass and its child to the frame's rect
/// at paint.
///
/// [applyPaintTransform] reports the move, so the layer, which polls
/// [getTransformTo] when it paints, draws the shape where the child is
/// drawn. Hit testing follows the layout box.
class RenderLiveGlassFrame extends RenderProxyBox {
  /// Creates a frame that follows [frame].
  RenderLiveGlassFrame({required this._frame});

  /// The frame this glass is moved and scaled to.
  ValueListenable<LiquidGlassShapeFrame> get frame => _frame;
  ValueListenable<LiquidGlassShapeFrame> _frame;
  set frame(ValueListenable<LiquidGlassShapeFrame> value) {
    if (identical(_frame, value)) return;
    if (attached) {
      _frame.removeListener(_onFrame);
      value.addListener(_onFrame);
    }
    _frame = value;
    _onFrame();
  }

  LiquidGlassShapeFrame? _placed;

  void _onFrame() {
    final frame = _frame.value;
    final placed = _placed;
    if (placed != null &&
        frame.rect == placed.rect &&
        frame.scaleX == placed.scaleX &&
        frame.scaleY == placed.scaleY) {
      return;
    }
    _placed = frame;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// The move and scale of the child, or null when it draws where it was
  /// laid out.
  Matrix4? get _transform => _placed?.bodyIn(size).toBox;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrame);
    _onFrame();
  }

  @override
  void detach() {
    _frame.removeListener(_onFrame);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _transform;
    if (child == null || transform == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_transform case final move?) transform.multiply(move);
  }
}
