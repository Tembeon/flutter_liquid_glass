// Setting up the tracking layer reads as one statement per field, without
// cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:meta/meta.dart';

@internal
mixin TransformTrackingRenderObjectMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  @nonVirtual
  bool get isRepaintBoundary => false;

  @override
  bool get alwaysNeedsCompositing => true;

  @mustCallSuper
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassComposer.track(owner, this);
  }

  @mustCallSuper
  @override
  void detach() {
    GlassComposer.untrack(owner!, this);
    super.detach();
  }

  /// This object's transform to the screen. While its layer composites,
  /// the one the layer read for the frame, as nothing moves a render object
  /// between paint and the scene: the walk to the root is taken once.
  Matrix4 transformToScreen() =>
      layer?._composited?.clone() ?? transformToNow(this);

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    setUpLayer(offset);
    context.pushLayer(layer!, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  GeometryTransformTrackingLayer setUpLayer(Offset offset) {
    final tracking = layer ??= GeometryTransformTrackingLayer();
    tracking.renderObject = this;
    tracking.onDetached = onTrackingLayerDetached;
    tracking.onTransformChanged = () {
      if (attached) onTransformChanged();
    };
    tracking.onPreparing = () {
      if (attached) onPreparing();
    };
    tracking.onCompositing = () {
      if (attached) onCompositing();
    };
    return tracking;
  }

  /// Paints normal children after an override has inserted its tracker.
  /// Calling this mixin's paint again would move that same tracker behind
  /// the effect whose retained-rendering dirtiness it must update first.
  @protected
  void paintTrackedChild(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }

  /// Also runs when a mounted subtree stops being painted by its ancestor.
  void onTrackingLayerDetached() {}

  /// The transform to the screen changed. Runs before paint when the view's
  /// composer polls, where a repaint lands in the same frame, and otherwise
  /// while the layer composites (see [GlassComposer.repaint]).
  void onTransformChanged();

  /// Runs every time this tracking layer is composited, before any glass of
  /// the view composes, including frames where the tracked transform is
  /// unchanged: where the glass polls its retained motion and asks for its
  /// copy. Repaints from here go through [GlassComposer.repaint].
  void onPreparing() {}

  /// Runs after [onPreparing] for every glass of the view, in paint order:
  /// where the glass chooses between its copy and the backdrop. Repaints
  /// from here go through [GlassComposer.repaint].
  void onCompositing() {}
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer with ComposedLayer {
  GeometryTransformTrackingLayer();

  RenderObject? renderObject;
  VoidCallback? onTransformChanged;
  VoidCallback? onPreparing;
  VoidCallback? onCompositing;
  VoidCallback? onDetached;
  Matrix4? _lastTransform;
  Matrix4? _composited;
  // The transform [prepare] read, for [compose] in the same frame.
  Matrix4? _prepared;

  @override
  void detach() {
    super.detach();
    onDetached?.call();
  }

  /// Reads the tracked object's transform before paint and reports a
  /// change, so that a repaint it asks for lands in the same frame.
  void pollTransform() {
    final renderObject = this.renderObject;
    if (!attached || renderObject == null || !renderObject.attached) return;
    _poll(renderObject, null);
  }

  // Resolves retained transforms after layout and paint, before the update
  // pass propagates retained-rendering dirtiness and submits engine layers.
  // Updating an effect from addToScene is too late: a containing layer may
  // already have been selected for retained rendering.
  @override
  void prepare() {
    final renderObject = this.renderObject;
    if (renderObject == null || !renderObject.attached) return;
    _prepared = _poll(renderObject, onPreparing);
  }

  @override
  void compose() {
    final planned = _prepared;
    _prepared = null;
    final renderObject = this.renderObject;
    if (renderObject == null || !renderObject.attached) return;
    _composited = planned ?? transformToNow(renderObject);
    try {
      onCompositing?.call();
    } finally {
      _composited = null;
    }
  }

  Matrix4 _poll(RenderObject renderObject, VoidCallback? then) {
    final currentTransform = transformToNow(renderObject);
    _composited = currentTransform;
    try {
      if (!MatrixUtils.matrixEquals(currentTransform, _lastTransform)) {
        onTransformChanged?.call();
        _lastTransform = currentTransform;
      }
      then?.call();
    } finally {
      _composited = null;
    }
    return currentTransform;
  }

  @override
  void updateSubtreeNeedsAddToScene() {
    final planned = composedAhead;
    super.updateSubtreeNeedsAddToScene();
    // The composer submits a planned frame's GPU work once; a scene it did
    // not plan submits here, before it reaches raster.
    if (!planned) FlutterGpuGeometryRenderer.flushPendingSubmissions();
  }
}

/// Remembers whether a glass layer polled its shapes' transforms while the
/// current frame painted, so its compositing hook can skip a second poll.
///
/// Nothing between paint and compositing in one frame moves a render object,
/// so that poll would only find the transforms paint just recorded.
@internal
class FramePollMarker {
  bool _polled = false;

  /// Whether this frame's paint already polled.
  bool get polledThisFrame => _polled;

  /// Records a poll made during the current frame's paint. Polls outside a
  /// frame, such as `toImage` captures, are not recorded.
  void markPolled() {
    if (_polled ||
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    _polled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _polled = false);
  }
}

/// [node]'s transform to the screen, taken once a frame while a tracked
/// object composites (see
/// [TransformTrackingRenderObjectMixin.transformToScreen]).
@internal
Matrix4 screenTransformOf(RenderObject node) =>
    node is TransformTrackingRenderObjectMixin
    ? node.transformToScreen()
    : transformToNow(node);
