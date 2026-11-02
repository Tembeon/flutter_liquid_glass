import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:meta/meta.dart';

/// The glass of one view, seen once a frame between paint and compositing.
///
/// A child [PipelineOwner] of the view's owner. Flutter flushes a child
/// owner after the parent's own nodes, phase by phase, and paints every view
/// before the first scene is built, so [flushCompositingBits] runs after
/// layout and before paint, and [flushPaint] after paint and before any
/// scene. Layer mutations made there are propagated by the update pass that
/// follows.
///
/// Before paint it polls where each site is on the screen, so glass that
/// moved past what its retained layers can follow repaints in this frame.
/// After paint it walks the view's layers in paint order and has every
/// [ComposedLayer] make its decisions for the frame, then submits the
/// frame's flutter_gpu passes and draws the frame's copies of what lies
/// under glass, before any scene is built.
///
/// One composer per view owner, adopted by the first glass that attaches
/// there ([track]) and dropped and disposed when the last one detaches, so a
/// view owner that is disposed never holds one.
@internal
final class GlassComposer extends PipelineOwner {
  GlassComposer._() : super(onSemanticsUpdate: _noSemantics);

  // A composer owns no render object; with semantics enabled it still gets
  // a semantics owner, which never has anything to send.
  static void _noSemantics(SemanticsUpdate update) => update.dispose();

  /// Starts following [site] on the composer of [owner], adopting one under
  /// [owner] if it has none. Call from a render object's `attach`.
  static void track(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    var composer = _of(owner);
    if (composer == null) {
      composer = GlassComposer._();
      owner.adoptChild(composer);
    }
    composer._sites.add(site);
  }

  /// Stops following [site]. The last site to leave drops the composer.
  /// Call from a render object's `detach`, before `super.detach`.
  static void untrack(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    final composer = _of(owner);
    if (composer == null || !composer._sites.remove(site)) return;
    if (composer._sites.isNotEmpty) return;
    owner.dropChild(composer);
    composer.dispose();
  }

  static GlassComposer? _of(PipelineOwner owner) {
    GlassComposer? found;
    owner.visitChildren((child) {
      if (child is GlassComposer) found = child;
    });
    return found;
  }

  /// The composers under [root] and its descendant owners, for benches and
  /// tests.
  @visibleForTesting
  static List<GlassComposer> debugAllUnder(PipelineOwner root) {
    final all = <GlassComposer>[];
    void visit(PipelineOwner owner) {
      if (owner is GlassComposer) all.add(owner);
      owner.visitChildren(visit);
    }

    visit(root);
    return all;
  }

  /// Marks [node] to paint again from a decision made between paint and the
  /// scene. While its view's composer composes, the frame's paint is over
  /// and the node paints in the next frame, as a mark made while the scene
  /// is built would.
  static void repaint(RenderObject node) {
    final owner = node.owner;
    if (owner == null || !(_of(owner)?._composing ?? false)) {
      node.markNeedsPaint();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.attached) node.markNeedsPaint();
    });
  }

  final Set<TransformTrackingRenderObjectMixin> _sites = Set.identity();

  bool _composing = false;

  // Stamps the layers composed in this frame; see [ComposedLayer].
  int _frame = 0;

  /// What this composer saw since it was adopted.
  @visibleForTesting
  final ComposerCensus census = ComposerCensus();

  @override
  void flushCompositingBits() {
    super.flushCompositingBits();
    for (final site in _sites) {
      site.layer?.pollTransform();
    }
  }

  @override
  void flushPaint() {
    super.flushPaint();
    census.frames++;
    census.sites += _sites.length;
    _frame++;
    // Copies drawn while composing replay glass whose mattes paint wrote.
    FlutterGpuGeometryRenderer.flushPendingSubmissions();
    final root = _root();
    if (root != null) {
      _composing = true;
      try {
        _compose(root);
      } finally {
        _composing = false;
      }
    }
    FlutterGpuGeometryRenderer.flushPendingSubmissions();
    BackdropUnderlay.drawPending();
  }

  ContainerLayer? _root() {
    for (final site in _sites) {
      Layer? layer = site.layer;
      if (layer == null || !layer.attached) continue;
      while (layer!.parent != null) {
        layer = layer.parent;
      }
      return layer as ContainerLayer;
    }
    return null;
  }

  // Parents before children, children in paint order, each read after its
  // parent's decisions moved layers: the order of the update pass.
  void _compose(ContainerLayer layer) {
    if (layer is ComposedLayer) layer._composeFor(this);
    var child = layer.firstChild;
    while (child != null) {
      if (child is ContainerLayer) _compose(child);
      child = child.nextSibling;
    }
  }
}

/// A layer whose decisions for a frame are made after every layer has
/// painted and before the scene is built ([compose]).
///
/// The view's [GlassComposer] composes it in paint order. A scene the
/// composer did not plan, such as an image of a subtree taken outside a
/// frame or before the composer ran, composes it in the update pass that
/// builds the scene, which also runs parents before children.
@internal
mixin ComposedLayer on ContainerLayer {
  GlassComposer? _composedBy;
  int _composedIn = 0;

  /// Makes this frame's decisions. Layers painted before this one have made
  /// theirs.
  void compose();

  void _composeFor(GlassComposer composer) {
    compose();
    _composedBy = composer;
    _composedIn = composer._frame;
  }

  /// Whether the view's composer composed this layer for the scene being
  /// built. Read before `super.updateSubtreeNeedsAddToScene`, which consumes
  /// it.
  @protected
  bool get composedAhead =>
      _composedBy?._frame == _composedIn &&
      SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;

  @override
  void updateSubtreeNeedsAddToScene() {
    if (composedAhead) {
      _composedBy = null;
    } else {
      compose();
    }
    super.updateSubtreeNeedsAddToScene();
  }
}

/// Counts of a [GlassComposer]'s frames.
@internal
final class ComposerCensus {
  /// Frames painted while the composer had a site.
  int frames = 0;

  /// Sites summed over [frames].
  int sites = 0;
}
