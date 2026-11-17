import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// What a glass layer's last painted frame committed to the retained layer
/// tree.
@internal
enum GlassFrameState {
  /// The frame drew no glass effect: no shapes are registered, or none is
  /// drawn and the effect keeps no matte.
  empty,

  /// Shapes are registered but none is drawn ([FrameShapes.drawn]).
  idle,

  /// The frame drew the glass effect for at least one drawn shape.
  active,
}

/// How a shape's own axes map into its layer: the images of its unit axes
/// and their determinant.
@internal
typedef ShapeBasis = ({Offset axisX, Offset axisY, double determinant});

/// One shape a layer's committed frame draws.
@internal
final class FrameShape {
  FrameShape._(
    this.source,
    this.geometry,
    this.shape,
    this.geometryToLayer,
    this.basis,
  );

  /// The render object whose geometry holds [shape]: the glass itself, or
  /// the blend group it joins.
  final RenderLiquidGlassGeometry source;

  /// The geometry that holds [shape].
  final GeometryCache geometry;

  /// The shape.
  final ShapeGeometry shape;

  /// The transform of [geometry] into the layer.
  final Matrix4 geometryToLayer;

  /// How the shape's axes map into the layer, invertibly.
  final ShapeBasis basis;

  /// The transform from the shape's own coordinates into the layer, over
  /// storage no one can write, so it may be kept past the frame.
  late final Matrix4 toLayer = Matrix4.fromFloat64List(
    switch (shape.shapeToGeometry) {
      final toGeometry? => geometryToLayer.multiplied(toGeometry),
      null => geometryToLayer.clone(),
    }.storage.asUnmodifiableView(),
  );

  /// The shape's glow where it draws.
  DrawnGlow? get glow => shape.renderObject.glow;
}

/// The shapes a glass layer's frame committed, and the ones it draws: those
/// that show ([DrawnAppearance.shows]) through a transform that keeps them a
/// shape.
@internal
final class FrameShapes {
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> _geometries =
      [];
  final List<FrameShape> _drawn = [];
  double? _smallestShortSide;

  /// The committed geometries in paint order, each with its transform into
  /// the layer.
  late final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  geometries = UnmodifiableListView(_geometries);

  /// The committed shapes the layer draws, in paint order.
  late final List<FrameShape> drawn = UnmodifiableListView(_drawn);

  /// The logical short side of the smallest drawn shape; null without one.
  double? get smallestShortSide => _smallestShortSide;

  /// The state of this frame in an effect that [encodesMatte] or not.
  GlassFrameState state({required bool encodesMatte}) {
    if (_geometries.isEmpty) return GlassFrameState.empty;
    if (_drawn.isNotEmpty) return GlassFrameState.active;
    return encodesMatte ? GlassFrameState.idle : GlassFrameState.empty;
  }

  /// The drawn shape of [renderObject], or null where the frame draws none.
  FrameShape? drawnOf(RenderObject? renderObject) {
    if (renderObject == null) return null;
    for (final drawn in _drawn) {
      if (identical(drawn.shape.renderObject, renderObject)) return drawn;
    }
    return null;
  }

  /// Takes [geometries] as the committed frame.
  void commit(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    _geometries
      ..clear()
      ..addAll(geometries);
    _drawn.clear();
    _smallestShortSide = null;
    for (final (source, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (!shape.appearance.shows) continue;
        final basis = _basis(shape, geometryToLayer);
        if (basis == null) continue;
        _drawn.add(
          FrameShape._(source, geometry, shape, geometryToLayer, basis),
        );
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        _smallestShortSide = min(_smallestShortSide ?? side, side);
      }
    }
  }

  static ShapeBasis? _basis(ShapeGeometry shape, Matrix4 geometryToLayer) {
    final shapeToGeometry = shape.shapeToGeometry;
    Offset toLayer(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      shapeToGeometry == null
          ? point
          : MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toLayer(Offset.zero);
    final axisX = toLayer(const Offset(1, 0)) - origin;
    final axisY = toLayer(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }
}
