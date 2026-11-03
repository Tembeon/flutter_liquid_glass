import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';

/// The clip [ancestor] applies to [child], in [ancestor]'s coordinates, or
/// `null` when it does not clip. Impeller derives a backdrop pass's coverage
/// from these clips, so glass and captures use the same list to predict the
/// pass origin their filters see.
Rect? clipOfAncestor(RenderObject ancestor, RenderObject child) =>
    ancestor is RenderViewportBase
    ? _approximateClip(ancestor, child)
    : paintClipOfAncestor(ancestor, child);

Rect? _approximateClip(RenderObject ancestor, RenderObject child) =>
    ancestor.describeApproximatePaintClip(child);

/// The clip [ancestor] paints around [child], in [ancestor]'s coordinates.
///
/// Unlike [clipOfAncestor], a viewport only counts while its content
/// overflows, mirroring [RenderViewportBase.paint]; its approximate clip API
/// reports per-sliver semantics instead.
Rect? paintClipOfAncestor(RenderObject ancestor, RenderObject child) =>
    switch (clipGeometryOf(ancestor)) {
      (_, Clip.none) => null,
      (final geometry, _) => clipGeometryBounds(geometry),
      null => switch (ancestor) {
        RenderView(:final size) => Offset.zero & size,
        _ => _approximateClip(ancestor, child),
      },
    };

/// The shape a clip render object paints, a [Rect], [RRect], [RSuperellipse]
/// or [Path] in its own coordinates, with the behavior it paints it with, or
/// null for a render object that is not a clip.
(Object, Clip)? clipGeometryOf(RenderObject node) => switch (node) {
  final RenderClipRect clip => (
    clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
    clip.clipBehavior,
  ),
  final RenderClipRRect clip => (
    clip.clipper?.getClip(clip.size) ??
        clip.borderRadius
            .resolve(clip.textDirection)
            .toRRect(Offset.zero & clip.size),
    clip.clipBehavior,
  ),
  final RenderClipRSuperellipse clip => (
    clip.clipper?.getClip(clip.size) ??
        clip.borderRadius
            .resolve(clip.textDirection)
            .toRSuperellipse(Offset.zero & clip.size),
    clip.clipBehavior,
  ),
  final RenderClipOval clip => (
    clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
    clip.clipBehavior,
  ),
  final RenderClipPath clip => (
    clip.clipper?.getClip(clip.size) ?? Offset.zero & clip.size,
    clip.clipBehavior,
  ),
  final RenderViewportBase viewport => (
    Offset.zero & viewport.size,
    // As RenderViewportBase.paint does.
    // ignore: invalid_use_of_protected_member
    viewport.hasVisualOverflow ? viewport.clipBehavior : Clip.none,
  ),
  _ => null,
};

/// The bounds of a geometry [clipGeometryOf] returns.
Rect clipGeometryBounds(Object geometry) => switch (geometry) {
  final Rect rect => rect,
  final RRect rect => rect.outerRect,
  final RSuperellipse rect => rect.outerRect,
  final Path path => path.getBounds(),
  _ => throw ArgumentError.value(geometry, 'geometry'),
};

/// Intersection of the paint clips above [node], in [node]'s coordinates, or
/// `null` when nothing above it clips.
///
/// Walks once to the root. The root view is skipped: its bounds are the
/// screen, which is the texture edge. Clips under a rotation or skew are
/// skipped too, as their bounding box would overstate what they keep.
Rect? localPaintClipAbove(RenderObject node) {
  Rect? result;
  var toAncestor = Matrix4.identity();
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null && ancestor.parent != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final step = Matrix4.identity();
    applyPaintTransformNow(ancestor, child, step);
    toAncestor = step..multiply(toAncestor);
    final clip = paintClipOfAncestor(ancestor, child);
    if (clip != null && isRectilinearTransform(toAncestor)) {
      final toNode = Matrix4.tryInvert(toAncestor);
      if (toNode != null) {
        final local = MatrixUtils.transformRect(toNode, clip);
        result = result?.intersect(local) ?? local;
      }
    }
  }
  return result;
}

/// Whether [transform] only scales and translates, so it maps rects to rects.
bool isRectilinearTransform(Matrix4 transform) {
  final m = transform.storage;
  const epsilon = 1e-9;
  return m[1].abs() < epsilon &&
      m[4].abs() < epsilon &&
      m[3].abs() < epsilon &&
      m[7].abs() < epsilon;
}

/// Intersection of every ancestor clip of [node] in screen coordinates, or
/// `null` when nothing above [node] clips.
///
/// Each clip is mapped to the screen as [RenderObject.getTransformTo] with a
/// null target maps its owner, in one walk from the root down.
Rect? screenClipAbove(RenderObject node) =>
    _screenClipAbove(node, clipOfAncestor);

/// Intersection of every clip that is actually painted above [node], in screen
/// coordinates, or `null` when nothing above it clips.
///
/// Like [screenClipAbove], but a viewport only counts while its content
/// overflows ([paintClipOfAncestor]), matching the clip layers the framework
/// pushes, which is what Impeller derives a pass's coverage from.
Rect? screenPaintClipAbove(RenderObject node) =>
    _screenClipAbove(node, paintClipOfAncestor);

Rect? _screenClipAbove(
  RenderObject node,
  Rect? Function(RenderObject ancestor, RenderObject child) clipOf,
) {
  final path = <RenderObject>[node];
  for (
    var ancestor = node.parent;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    path.add(ancestor);
  }
  Rect? result;
  final toScreen = Matrix4.identity();
  for (var i = path.length - 1; i > 0; i--) {
    final ancestor = path[i];
    final child = path[i - 1];
    final clip = clipOf(ancestor, child);
    if (clip != null) {
      final screenClip = MatrixUtils.transformRect(toScreen, clip);
      result = result?.intersect(screenClip) ?? screenClip;
    }
    // As getTransformTo(null) does, leave out the root view's own transform
    // (the device pixel ratio).
    if (i < path.length - 1) {
      applyPaintTransformNow(ancestor, child, toScreen);
    }
  }
  return result;
}
