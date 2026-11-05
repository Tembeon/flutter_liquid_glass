import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// A widget that groups multiple liquid glass shapes for blending.
///
/// Any [LiquidGlass.grouped] widgets inside this group will blend together.
///
/// This widget will expect a parent [LiquidGlassLayer] to render the liquid
/// glass effect on.
class LiquidGlassBlendGroup extends StatefulWidget {
  /// Creates a new [LiquidGlassBlendGroup].
  const LiquidGlassBlendGroup({
    required this.child,
    this.blend = 20.0,
    super.key,
  });

  /// The amount of blending between shapes in this group.
  ///
  /// Roughly corresponds to distance of logical pixels at which shapes start to
  /// blend.
  final double blend;

  /// The child widget containing liquid glass shapes.
  final Widget child;

  /// Maximum number of glass shapes a [LiquidGlassLayer] renders in one
  /// cluster: shapes that blend, or lie within a few pixels of each other's
  /// edges. A layer renders any number of clusters, but caps the whole layer
  /// at this many shapes when the shapes carry their own appearances or the
  /// layer draws a field.
  ///
  /// Shapes beyond it are not drawn; debug builds print a warning when that
  /// happens. Split the glass across several layers if you need more.
  static const int maxShapesPerCluster = 16;

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup], or null if none is found.
  @internal
  static GlassGroupLink? maybeOf(BuildContext context) {
    final inherited = _InheritedLiquidGlassBlendGroup.of(context);
    return inherited?.link;
  }

  @override
  State<LiquidGlassBlendGroup> createState() => _LiquidGlassBlendGroupState();
}

class _LiquidGlassBlendGroupState extends State<LiquidGlassBlendGroup> {
  late final GlassGroupLink _geometryLink = GlassGroupLink();

  @override
  void dispose() {
    _geometryLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderLink = InheritedGeometryRenderLink.of(context);
    return _InheritedLiquidGlassBlendGroup(
      link: _geometryLink,
      renderLink: renderLink,
      child: _RawLiquidGlassBlendGroup(
        blend: widget.blend,
        link: _geometryLink,
        renderLink: renderLink!,
        settings: LiquidGlassRenderScope.of(context).settings,
        child: widget.child,
      ),
    );
  }
}

class _InheritedLiquidGlassBlendGroup extends InheritedWidget {
  const _InheritedLiquidGlassBlendGroup({
    required this.link,
    required this.renderLink,
    required super.child,
  });

  final GlassGroupLink link;
  final GeometryRenderLink? renderLink;

  static _InheritedLiquidGlassBlendGroup? of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedLiquidGlassBlendGroup>();
    // A nested layer owns a different backdrop sample. Its shapes must not
    // register in a blend group belonging to an outer layer.
    return inherited?.renderLink == InheritedGeometryRenderLink.of(context)
        ? inherited
        : null;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! _InheritedLiquidGlassBlendGroup ||
        oldWidget.link != link ||
        oldWidget.renderLink != renderLink;
  }
}

class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassBlendGroup({
    required this.blend,
    required this.renderLink,
    required this.link,
    required this.settings,
    super.child,
  });

  final double blend;
  final GeometryRenderLink renderLink;
  final GlassGroupLink link;
  final LiquidGlassSettings settings;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassBlendGroup(
      renderLink: renderLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      settings: settings,
      link: link,
      blend: blend,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassBlendGroup renderObject,
  ) {
    renderObject
      ..blend = blend
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..link = link;
  }
}

@visibleForTesting
@internal
class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry {
  RenderLiquidGlassBlendGroup({
    required super.renderLink,
    required super.devicePixelRatio,
    required super.settings,
    required this._link,
    required this._blend,
  }) {
    link
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged;
  }

  GlassGroupLink _link;

  /// The link that provides shape information to this geometry.
  GlassGroupLink get link => _link;

  set link(GlassGroupLink value) {
    if (_link == value) return;
    _link
      ..removeListener(_onLinkUpdate)
      ..onMembershipChanged = null;
    _link = value;
    value
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged;
    markNeedsPaint();
  }

  double _blend;
  double get blend => _blend;
  set blend(double value) {
    if (_blend == value) return;
    _blend = value;
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  @override
  double get geometryBlend => blend;

  @override
  void updatePaintOrder() {
    if (sortGlassPaintOrder(this, link.shapeEntries, (entry) => entry.key)) {
      markGeometryNeedsUpdate(force: true);
    }
  }

  void _onLinkUpdate() {
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  // A shape joining or leaving under a repaint boundary of its own repaints
  // only that boundary, and this group may sit under one too: the layer has to
  // paint this frame as it does for a glass that joins it directly.
  void _onMembershipChanged() => renderLink?.onMembershipChanged?.call();

  List<Matrix4?> _lastShapeTransforms = const [];

  @override
  bool pollChildShapeTransforms() {
    final entries = link.shapeEntries;
    if (_lastShapeTransforms.length != entries.length) {
      _lastShapeTransforms = List<Matrix4?>.filled(entries.length, null);
      for (var i = 0; i < entries.length; i++) {
        final shape = entries[i].key;
        if (shape.attached && shape.parent != this) {
          _lastShapeTransforms[i] = _paintedTransform(shape);
        }
      }
      return false;
    }

    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      final shape = entries[i].key;
      if (!shape.attached || shape.parent == this) continue;
      final transform = _paintedTransform(shape);
      final last = _lastShapeTransforms[i];
      // `matrixEquals` reads null as the identity; a shape that stops or
      // starts being painted is a change either way.
      if ((transform == null) != (last == null) ||
          !MatrixUtils.matrixEquals(transform, last)) {
        _lastShapeTransforms[i] = transform;
        changed = true;
      }
    }
    if (changed) {
      markGeometryNeedsUpdate();
    }
    return changed;
  }

  /// The shape's transform to this group, or null while the shape is not
  /// painted (see [isGlassShapePainted]).
  Matrix4? _paintedTransform(RenderObject shape) =>
      isGlassShapePainted(shape, this) ? transformToNow(shape, this) : null;

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    final shapes = <ShapeGeometry>[];
    final cachedShapes = geometry?.shapes ?? [];

    var anyShapeChangedInLayer = false;

    // A hidden shape draws nothing: in the bounds it stretches the matte, the
    // copy and the glass's pass from wherever it lies to the shapes that show.
    Rect? layerBounds;
    Rect? everyBounds;

    for (final MapEntry(key: renderObject, value: shape) in link.shapeEntries) {
      if (!renderObject.attached ||
          !renderObject.hasSize ||
          !isGlassShapePainted(renderObject, this)) {
        continue;
      }
      final index = shapes.length;
      final shapeData = _computeShapeInfo(renderObject, shape);
      shapes.add(shapeData);
      everyBounds =
          everyBounds?.expandToInclude(shapeData.shapeBounds) ??
          shapeData.shapeBounds;
      if (shapeData.appearance.visibility > 0) {
        layerBounds =
            layerBounds?.expandToInclude(shapeData.shapeBounds) ??
            shapeData.shapeBounds;
      }
      final existingShape = cachedShapes.length > index
          ? cachedShapes[index]
          : null;
      if (existingShape == null ||
          existingShape.shapeBounds != shapeData.shapeBounds ||
          existingShape.shape != shapeData.shape ||
          !MatrixUtils.matrixEquals(
            existingShape.shapeToGeometry,
            shapeData.shapeToGeometry,
          )) {
        anyShapeChangedInLayer = true;
      }
    }

    if (cachedShapes.length != shapes.length) anyShapeChangedInLayer = true;

    return (
      (layerBounds ?? everyBounds ?? Rect.zero).inflate(blend * .25),
      shapes,
      anyShapeChangedInLayer,
    );
  }

  ShapeGeometry _computeShapeInfo(
    LiquidGlassShapeRenderObject renderObject,
    LiquidShape shape,
  ) {
    final transformToGeometry = transformToNow(renderObject, this);

    final blendGroupRect = MatrixUtils.transformRect(
      transformToGeometry,
      Offset.zero & renderObject.paintSize,
    );

    return ShapeGeometry(
      renderObject: renderObject,
      shape: shape,
      appearance: renderObject.appearance,
      shapeBounds: blendGroupRect,
      shadows: renderObject.layerShadows,
      shapeToGeometry: transformToGeometry,
    );
  }
}

/// A link that connects liquid glass shapes to their parent
/// [LiquidGlassBlendGroup] for efficient communication of position, size, and
/// transform changes.
@internal
class GlassGroupLink with ChangeNotifier {
  /// Called when a shape registers with or leaves the group.
  VoidCallback? onMembershipChanged;

  /// Information about a shape registered with this link.
  final Map<LiquidGlassShapeRenderObject, LiquidShape> _shapes = {};

  List<MapEntry<LiquidGlassShapeRenderObject, LiquidShape>>? _shapeEntriesCache;

  List<MapEntry<LiquidGlassShapeRenderObject, LiquidShape>> get shapeEntries =>
      _shapeEntriesCache ??= _shapes.entries.toList(growable: false);

  /// Register a shape with this link.
  void registerShape(
    LiquidGlassShapeRenderObject renderObject,
    LiquidShape shape,
  ) {
    _shapes[renderObject] = shape;
    _shapeEntriesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Unregister a shape from this link.
  void unregisterShape(LiquidGlassShapeRenderObject renderObject) {
    _shapes.remove(renderObject);
    _shapeEntriesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    LiquidGlassShapeRenderObject renderObject,
    LiquidShape shape,
  ) {
    _shapes[renderObject] = shape;
    _shapeEntriesCache = null;
    notifyListeners();
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _shapes.clear();
    _shapeEntriesCache = null;
    super.dispose();
  }
}
