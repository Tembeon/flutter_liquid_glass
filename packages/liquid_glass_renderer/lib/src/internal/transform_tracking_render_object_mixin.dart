// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/form.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
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

  /// This object's transform to the screen. While its layer composites, the
  /// transform the layer read for this frame, without another walk to the
  /// root: nothing moves a render object between paint and the scene.
  Matrix4 transformToScreen() =>
      layer?._composited?.clone() ?? transformToNow(this);

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final tracking = layer ??= GeometryTransformTrackingLayer();
    tracking._site = this;
    context.pushLayer(tracking, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  /// The transform to the screen changed. Runs before paint when the view's
  /// composer polls, where a repaint lands in the same frame, and otherwise
  /// while the layer composites (see [GlassComposer.repaint]).
  void onTransformChanged();

  /// Writes what the frame's plan reads of this site.
  void fillPlanFacts(SiteFacts facts) => facts.hidden = true;

  /// Whether [onTransformChanged] would repaint, so that it must run before
  /// paint for the repaint to land in the same frame.
  bool get repaintsOnMove => false;

  /// Runs every time this tracking layer is composited, before any glass of
  /// the view composes, including frames where the tracked transform is
  /// unchanged: where the glass polls its retained motion and asks for its
  /// copy. Repaints from here go through [GlassComposer.repaint].
  void onPreparing() {}

  /// Whether this frame may run [onResting] in place of [onPreparing] when
  /// nothing changed around the object.
  bool get mayRest => true;

  /// Runs in place of [onPreparing] on a frame that changed nothing around the
  /// object: its layers, and so where its glass lies, are as they were.
  void onResting() => onPreparing();

  /// Runs after [onPreparing] for every glass of the view, in paint order:
  /// where the glass chooses between its copy and the backdrop. Repaints
  /// from here go through [GlassComposer.repaint].
  void onCompositing() {}
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer
    with ComposedLayer
    implements PlanSite {
  GeometryTransformTrackingLayer();

  // The render object whose transform the layer tracks.
  TransformTrackingRenderObjectMixin? _site;
  Matrix4? _lastTransform;
  Matrix4? _composited;
  // The transform [prepare] read, for [compose] in the same frame.
  Matrix4? _prepared;

  /// Where this frame's lowering of the layers found the layer.
  SiteNode? formNode;

  @override
  void fillPlanFacts(SiteFacts facts) {
    final site = _site;
    if (site == null || !site.attached) {
      facts.hidden = true;
      return;
    }
    site.fillPlanFacts(facts);
  }

  /// Reads the tracked object's transform before paint and reports a
  /// change, so that a repaint it asks for lands in the same frame.
  void pollTransform() {
    final site = _site;
    if (!attached || site == null || !site.attached) return;
    _poll(site, null);
  }

  // Resolves retained transforms after layout and paint, before the update
  // pass propagates retained-rendering dirtiness and submits engine layers.
  // Updating an effect from addToScene is too late: a containing layer may
  // already have been selected for retained rendering.
  @override
  void prepare() {
    final site = _site;
    if (site == null || !site.attached) return;
    final last = _lastTransform;
    if (last != null &&
        GlassComposer.debugFormRests &&
        site.mayRest &&
        (formNode?.rests ?? false)) {
      assert(
        MatrixUtils.matrixEquals(transformToNow(site), last),
        'A site moved with no layer around it changing.',
      );
      GlassComposer.debugRests++;
      _composited = last;
      try {
        site.onResting();
      } finally {
        _composited = null;
      }
      _prepared = last;
      return;
    }
    _prepared = _poll(site, site.onPreparing);
  }

  @override
  void compose() {
    final planned = _prepared;
    _prepared = null;
    final site = _site;
    if (site == null || !site.attached) return;
    _composited = planned ?? transformToNow(site);
    try {
      site.onCompositing();
    } finally {
      _composited = null;
    }
  }

  Matrix4 _poll(TransformTrackingRenderObjectMixin site, VoidCallback? then) {
    final currentTransform = transformToNow(site);
    _composited = currentTransform;
    try {
      if (!MatrixUtils.matrixEquals(currentTransform, _lastTransform)) {
        site.onTransformChanged();
        _lastTransform = currentTransform;
      }
      then?.call();
    } finally {
      _composited = null;
    }
    return currentTransform;
  }

  // It draws nothing: where it lies is all the site reads.
  @override
  void addToScene(ui.SceneBuilder builder) {
    if (firstChild != null) super.addToScene(builder);
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

/// An [OffsetLayer] that holds no layer of the scene while it does not shift:
/// glass over a scroll adds its layers again every frame, and each one the
/// scene holds costs both threads.
@internal
class ThinOffsetLayer extends OffsetLayer {
  @override
  void addToScene(ui.SceneBuilder builder) {
    if (offset != Offset.zero) {
      super.addToScene(builder);
      return;
    }
    engineLayer = null;
    addChildrenToScene(builder);
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
