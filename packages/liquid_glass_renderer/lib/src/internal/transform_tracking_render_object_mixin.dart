// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/form.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/composer/scene_out.dart';
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
    GlassComposer.sitePainted(owner!);
    final tracking = layer ??= GeometryTransformTrackingLayer();
    tracking._site = this;
    tracking._paintOffset = offset;
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

  /// Runs every frame, before the frame's plan, including frames where the
  /// tracked transform is unchanged: where the glass polls its retained motion.
  /// Repaints from here go through [GlassComposer.repaint].
  void onPreparing() {}

  /// Whether this frame may run [onResting] in place of [onPreparing] when
  /// nothing changed around the object.
  bool get mayRest => true;

  /// Runs in place of [onPreparing] on a frame that changed nothing around the
  /// object: its layers, and so where its glass lies, are as they were.
  void onResting() => onPreparing();

  /// This frame's [fate], in paint order, before any read of the frame is
  /// drawn (see [PlanSite.beginFate]).
  void beginFate(Fate fate) {}

  /// See [PlanSite.showScene].
  void showScene(Read read, ReadCopy copy) {}

  /// See [PlanSite.showPage].
  void showPage(Read read, PageCopy page) {}

  /// See [PlanSite.showLive].
  void showLive(BackdropKey? group) {}

  /// See [PlanSite.addOutput].
  void addOutput(SceneOut out, ReadCopy outer) {}

  /// See [PlanSite.readPainter].
  ReadPainter? get readPainter => null;
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
  // Where the render object paints in the coordinates of this layer.
  Offset _paintOffset = Offset.zero;

  @override
  SiteNode? formNode;

  /// The render object whose transform the layer tracks.
  TransformTrackingRenderObjectMixin? get trackedSite => _site;

  bool get _live {
    final site = _site;
    return site != null && site.attached;
  }

  @override
  void fillPlanFacts(SiteFacts facts) {
    final site = _site;
    if (site == null || !site.attached) {
      facts.hidden = true;
      return;
    }
    final last = _lastTransform;
    final node = formNode;
    if (last != null && site.mayRest && (node?.rests ?? false)) {
      assert(
        _near(transformToNow(site), last),
        'A site moved with no layer around it changing.',
      );
      GlassComposer.debugRests++;
      _composited = last;
      site.onResting();
    } else {
      final fromForm = node?.screenTransform(_paintOffset);
      assert(
        fromForm == null ||
            transformToNowOrLast(site).last ||
            _near(transformToNow(site), fromForm),
        'The form says the site lies elsewhere than its render objects do.',
      );
      final now = fromForm ?? transformToNow(site);
      _composited = now;
      if (!MatrixUtils.matrixEquals(now, last)) {
        site.onTransformChanged();
        _lastTransform = now;
      }
      site.onPreparing();
    }
    site.fillPlanFacts(facts);
  }

  static bool _near(Matrix4 a, Matrix4 b) {
    final x = a.storage;
    final y = b.storage;
    for (var i = 0; i < 16; i++) {
      if ((x[i] - y[i]).abs() > 1e-3) return false;
    }
    return true;
  }

  /// Reads the tracked object's transform before paint and reports a
  /// change, so that a repaint it asks for lands in the same frame.
  void pollTransform() {
    final site = _site;
    if (!attached || site == null || !site.attached) return;
    final now = transformToNow(site);
    final last = _lastTransform;
    if (last != null && _near(now, last)) return;
    _composited = now;
    site.onTransformChanged();
    _lastTransform = now;
    _composited = null;
  }

  @override
  void beginFate(Fate fate) {
    if (_live) _site!.beginFate(fate);
  }

  @override
  void showScene(Read read, ReadCopy copy) {
    if (_live) _site!.showScene(read, copy);
  }

  @override
  void showPage(Read read, PageCopy page) {
    if (_live) _site!.showPage(read, page);
  }

  @override
  void showLive(BackdropKey? group) {
    if (_live) _site!.showLive(group);
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    if (_live) _site!.addOutput(out, outer);
  }

  // The slot it is shown in holds what it draws; the tracking layer holds only
  // where it lies.
  @override
  bool get drawsOwnChildren => false;

  @override
  bool get outputsInPlace => false;

  @override
  ReadPainter? get readPainter => _live ? _site!.readPainter : null;

  @override
  void endFrame() => _composited = null;

  // It draws nothing: where it lies is all the site reads.
  @override
  void addToScene(ui.SceneBuilder builder) {
    if (firstChild != null) super.addToScene(builder);
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
