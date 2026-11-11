import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';

/// Sorts [sources] into paint order under [owner], walking only their
/// ancestry; returns whether the order changed.
bool sortGlassPaintOrder<T>(
  RenderObject owner,
  List<T> sources,
  RenderObject Function(T) renderObject,
) {
  if (sources.length < 2) return false;
  final byObject = <RenderObject, T>{
    for (final source in sources) renderObject(source): source,
  };
  final ancestry = <RenderObject>{};
  for (final source in byObject.keys) {
    for (var node = source; !identical(node, owner);) {
      if (!ancestry.add(node)) break;
      final parent = node.parent;
      if (parent == null) break;
      node = parent;
    }
  }
  final ordered = <T>[];
  void visit(RenderObject node) {
    if (!ancestry.contains(node)) return;
    if (byObject.containsKey(node)) ordered.add(byObject[node] as T);
    node.visitChildren(visit);
  }

  owner.visitChildren(visit);
  if (ordered.length != sources.length) return false;
  for (var i = 0; i < sources.length; i++) {
    if (!identical(sources[i], ordered[i])) {
      sources.setAll(0, ordered);
      return true;
    }
  }
  return false;
}

/// The state of liquid glass geometry, used to determine if it needs to be
/// updated.
enum LiquidGlassGeometryState {
  /// The geometry is up to date and does not need to be updated.
  updated,

  /// The geometry might need to be updated, but could potentially be reused.
  ///
  /// This happens mainly when all of the geometry itself is unchanged, but all
  /// of the geometry has been uniformly transformed.
  ///
  /// In this case, we can use the existing geometry matte and transform it to
  /// save GPU cycles.
  mightNeedUpdate,

  /// The geometry definitely needs to be updated.
  needsUpdate,
}

/// Result of checking one geometry node against its owning layer.
@internal
typedef LiquidGlassTransformPoll = ({
  bool childChanged,
  bool selfChanged,
  Matrix4? transform,
});

/// A render object that contributes one glass shape to a geometry pass.
mixin LiquidGlassShapeRenderObject on RenderBox {
  /// Shadows painted by the parent layer before grouped glass shading.
  List<BoxShadow> get layerShadows;

  /// Resolved color and materialization controls for this shape.
  LiquidGlassAppearance get appearance;

  /// The size the shape is drawn at, which a live frame sets apart from the
  /// layout size.
  Size get paintSize;
}

/// A base class for any render object that represents liquid glass geometry.
///
/// Standalone shapes and blend groups both register with a
/// [GeometryRenderLink] so the parent layer can pack them into one sample.
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  /// Creates a geometry that registers on [renderLink].
  RenderLiquidGlassGeometry({
    required this._settings,
    required this._devicePixelRatio,
    this._renderLink,
  });

  LiquidGlassSettings _settings;

  /// The settings used for liquid glass rendering.
  ///
  /// If these settings change in a way that affects geometry, the geometry
  /// will be marked as needing an update.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      markGeometryNeedsUpdate(force: true);
    }

    _settings = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// The device pixel ratio used for rendering.
  ///
  /// If this changes, the geometry will be marked as needing an update.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  GeometryRenderLink? _renderLink;

  /// The link of the layer this geometry registers on, or null while it
  /// registers nowhere.
  GeometryRenderLink? get renderLink => _renderLink;
  set renderLink(GeometryRenderLink? value) {
    if (_renderLink == value) return;
    _renderLink?.unregisterGeometry(this);
    _renderLink = value;
    _renderLink?.registerGeometry(this);
  }

  /// The current state of the geometry.
  @visibleForTesting
  @protected
  LiquidGlassGeometryState geometryState = LiquidGlassGeometryState.needsUpdate;

  /// The current geometry matte image.
  @visibleForTesting
  @protected
  GeometryCache? geometry;

  int _matteRevision = 0;

  /// Marks the geometry as needing an update.
  ///
  /// If [force] is true, the geometry will be marked as definitely needing an
  /// update. Otherwise, it will be marked as possibly needing an update,
  /// unless it is already marked as definitely needing an update.
  @protected
  void markGeometryNeedsUpdate({bool force = false}) {
    geometryState =
        force || geometryState == LiquidGlassGeometryState.needsUpdate
        ? LiquidGlassGeometryState.needsUpdate
        : LiquidGlassGeometryState.mightNeedUpdate;
    _renderLink?.markDirty();
  }

  Matrix4? _lastTransformToLayer;

  /// Whether the last [pollRelativeTransforms] read a follower's last frame
  /// (see [transformToNowOrLast]): the layer polls again once the follower
  /// is in the leader's tree.
  bool get transformMayLag => _transformMayLag;
  bool _transformMayLag = false;

  /// Detects motion of this geometry relative to [layer].
  ///
  /// Reads the transform with [transformToNowOrLast], which sees only
  /// [RenderObject.applyPaintTransform]: a transform an ancestor pushes in
  /// paint (PaintingContext.pushTransform) is not followed.
  ///
  /// Called from the layer's paint and compositing hooks so descendant glass
  /// does not need its own always-composite tracking layers. The two change
  /// flags let the layer distinguish a uniformly translated geometry node
  /// from shapes moving inside a blend group.
  LiquidGlassTransformPoll pollRelativeTransforms(RenderObject layer) {
    if (!attached || !layer.attached || !hasSize) {
      return (childChanged: false, selfChanged: false, transform: null);
    }

    final (transform: toLayer, :last) = transformToNowOrLast(this, layer);
    _transformMayLag = last;
    var selfChanged = false;
    if (_lastTransformToLayer == null) {
      _lastTransformToLayer = toLayer;
    } else if (!MatrixUtils.matrixEquals(toLayer, _lastTransformToLayer)) {
      _lastTransformToLayer = toLayer;
      selfChanged = true;
    }

    final childChanged = pollChildShapeTransforms();
    if (!childChanged && selfChanged) {
      markGeometryNeedsUpdate();
    }
    return (
      childChanged: childChanged,
      selfChanged: selfChanged,
      transform: toLayer,
    );
  }

  /// Whether [candidate] was current before polling compositor motion.
  bool hasCurrentGeometryCache(GeometryCache candidate) =>
      identical(geometry, candidate) &&
      geometryState == LiquidGlassGeometryState.updated;

  /// Whether the encoded matte revision was current before compositor motion.
  bool hasCurrentMatteRevision(int revision) =>
      geometry?.matteRevision == revision &&
      geometryState == LiquidGlassGeometryState.updated;

  /// Records that a translation was applied to the retained layer instead of
  /// invalidating this node's local geometry.
  void acceptCompositorTranslation() {
    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate) {
      geometryState = LiquidGlassGeometryState.updated;
    }
  }

  /// Detects motion of registered shapes relative to this geometry node.
  ///
  /// Direct children can skip this: their offset changes go through layout.
  @protected
  bool pollChildShapeTransforms() => false;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    _renderLink?.registerGeometry(this);
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    _renderLink?.unregisterGeometry(this);
    super.detach();
  }

  @override
  @mustCallSuper
  void dispose() {
    _renderLink?.unregisterGeometry(this);
    geometry = null;
    super.dispose();
  }

  /// The shapes this node draws, their bounds in its own coordinates, and
  /// whether any shape changed against [geometry].
  (
    Rect bounds,
    List<ShapeGeometry> geometries,
    bool needsUpdate,
  )
  gatherShapeData();

  /// Smooth-union radius for shapes owned by this geometry node.
  double get geometryBlend => 0;

  /// Refresh source ordering before owner paint consumes cached geometry.
  void updatePaintOrder() {}

  /// Refreshes CPU geometry during owner paint or pre-submission preparation.
  /// This advances cache state but does not paint children or encode a matte.
  GeometryCache? maybeRebuildGeometry() {
    if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
      return geometry;
    }

    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null &&
        !_matteVisibilityChanged(geometry!.shapes, shapes)) {
      // Shadows refresh with cached geometry without re-encoding its matte.
      geometry = GeometryCache(
        bounds: geometry!.bounds,
        shapes: shapes,
        blend: geometry!.blend,
        matteRevision: geometry!.matteRevision,
      );
      renderLink?.markDirty();

      geometryState = LiquidGlassGeometryState.updated;
      return geometry;
    }

    geometry = null;
    geometryState = LiquidGlassGeometryState.updated;

    if (shapes.isEmpty) {
      return null;
    }

    final snappedBounds = layerBounds.snapToPixels(devicePixelRatio);
    final newGeo = geometry = GeometryCache(
      bounds: snappedBounds,
      shapes: shapes,
      blend: geometryBlend,
      matteRevision: ++_matteRevision,
    );

    _renderLink?.markDirty();
    return newGeo;
  }

  static bool _matteVisibilityChanged(
    List<ShapeGeometry> before,
    List<ShapeGeometry> after,
  ) {
    if (before.length != after.length) return true;
    for (var index = 0; index < before.length; index++) {
      if ((before[index].appearance.visibility > 0) !=
          (after[index].appearance.visibility > 0)) {
        return true;
      }
    }
    return false;
  }
}

/// CPU-side geometry metadata consumed by the Flutter GPU pass.
@immutable
@internal
class GeometryCache {
  const GeometryCache({
    required this.bounds,
    required this.shapes,
    required this.blend,
    required this.matteRevision,
  });

  final Rect bounds;
  final List<ShapeGeometry> shapes;
  final double blend;

  /// Monotonically identifies the inputs encoded into the SDF matte.
  ///
  /// Paint-only metadata refreshes retain this value, allowing a parent layer
  /// to validate translation reuse without deeply comparing every shape.
  final int matteRevision;
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings other) {
    return effectiveRefractionHeight != other.effectiveRefractionHeight ||
        effectiveRefractionAmount != other.effectiveRefractionAmount ||
        refractionFitsShape != other.refractionFitsShape ||
        contourWidth != other.contourWidth;
  }
}

@internal
enum RawShapeType {
  // none(0), unused in CPU code
  squircle(1),
  ellipse(2),
  roundedRectangle(3),

  /// A squircle whose two bottom corners have a different radius from its two
  /// top ones, drawn as two halves that meet on the split line (sdf.glsl's
  /// resolvePairHalf).
  squirclePair(4);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  static RawShapeType fromLiquidGlassShape(LiquidShape shape) =>
      switch (shape) {
        LiquidRoundedSuperellipse(:final isUniform) =>
          isUniform ? RawShapeType.squircle : RawShapeType.squirclePair,
        LiquidOval() => RawShapeType.ellipse,
        LiquidRoundedRectangle() => RawShapeType.roundedRectangle,
      };
}

/// The geometry of a single shape.
///
/// Can be part of multiple blended shapes in [RenderLiquidGlassGeometry], or on
/// its own.
@immutable
class ShapeGeometry {
  /// Describes one shape as its layer draws it.
  ShapeGeometry({
    required this.renderObject,
    required this.shape,
    required this.shapeBounds,
    required this.appearance,
    this.shadows = const [],
    this.shapeToGeometry,
  }) : rawCornerRadius = shape.cornerRadius,
       rawBottomRadius = switch (shape) {
         LiquidRoundedSuperellipse(:final effectiveBottomRadius) =>
           effectiveBottomRadius,
         _ => shape.cornerRadius,
       },
       rawShapeType = RawShapeType.fromLiquidGlassShape(shape);

  /// The render object of the shape.
  final LiquidGlassShapeRenderObject renderObject;

  /// The shape.
  final LiquidShape shape;

  /// The kind of the shape, as the geometry shaders tell it.
  final RawShapeType rawShapeType;

  /// The corner radius the geometry shaders draw the shape with.
  final double rawCornerRadius;

  /// The radius of the two bottom corners: [rawCornerRadius] except for a
  /// [RawShapeType.squirclePair].
  final double rawBottomRadius;

  /// The appearance of the shape.
  final LiquidGlassAppearance appearance;

  /// Bounds in geometry-local coordinates (for painting)
  final Rect shapeBounds;

  /// The shadows the shape casts.
  final List<BoxShadow> shadows;

  /// The transform from the shape to its geometry, or null when they share
  /// coordinates.
  final Matrix4? shapeToGeometry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ShapeGeometry &&
          other.renderObject == renderObject &&
          other.shape == shape &&
          other.appearance == appearance &&
          other.shapeBounds == shapeBounds &&
          listEquals(other.shadows, shadows) &&
          other.shapeToGeometry == shapeToGeometry;

  @override
  int get hashCode => Object.hash(
    renderObject,
    shape,
    appearance,
    shapeBounds,
    Object.hashAll(shadows),
    shapeToGeometry,
  );

  @override
  String toString() =>
      'ShapeGeometry($renderObject, $shape, $appearance, $shapeBounds, '
      '$shadows, $shapeToGeometry)';
}
