import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

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
/// After paint it lowers the view's layers into a [Form], asks every site for
/// its facts, compiles the frame's [Plan] and draws it, before any scene is
/// built. Then it submits the frame's flutter_gpu passes.
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
    if (!kReleaseMode) GlassWork.marks++;
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

  final _composition = _Composition();

  bool _composing = false;

  // Whether glass painted since the last plan: it paints a slot the plan fills.
  bool _painted = true;

  /// Notes that a site of [owner]'s composer painted this frame.
  static void sitePainted(PipelineOwner owner) {
    _of(owner)?._painted = true;
  }

  // The frame this composer planned the scene of.
  Duration? _planned;

  /// What this composer saw since it was adopted.
  @visibleForTesting
  final ComposerCensus census = ComposerCensus();

  @override
  void flushCompositingBits() {
    super.flushCompositingBits();
    for (final site in _sites) {
      if (site.repaintsOnMove) site.layer?.pollTransform();
    }
  }

  @override
  void flushPaint() {
    super.flushPaint();
    census.frames++;
    census.sites += _sites.length;
    final root = _root();
    if (root == null) return;
    _composing = true;
    try {
      // A site's poll may paint it again while the plan's facts are filled.
      _composition.run(root, painted: () => _painted);
      _painted = false;
      _planned = SchedulerBinding.instance.currentFrameTimeStamp;
    } finally {
      _composing = false;
    }
  }

  @override
  void dispose() {
    _composition.dispose();
    super.dispose();
  }

  /// What the frame's plan pays for what it weighs.
  @internal
  static Prices debugPrices = const Prices();

  /// The decisions the frame's plan keeps to; a bench swaps it for a window.
  @internal
  static Policy debugPolicy = const Policy();

  /// Handed each frame's plan, with its reasons, while set.
  @visibleForTesting
  static void Function(Form form, Plan plan)? debugOnPlan;

  /// Sites that rested since this was last cleared.
  @internal
  static int debugRests = 0;

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

  static bool _plannedAhead(Layer layer) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    final view = layer.owner;
    if (view is! RenderView) return false;
    final owner = view.owner;
    if (owner == null) return false;
    final composer = _of(owner);
    return composer != null &&
        composer._planned == SchedulerBinding.instance.currentFrameTimeStamp;
  }

  // The roots a scene no composer planned was composed for, until the scene's
  // update pass is over.
  static final _composedRoots = Set<ContainerLayer>.identity();

  // What a view with no tracked site holds between frames: a view that shows
  // nothing but scroll edges still holds still.
  static final _alone = Map<ContainerLayer, _Composition>.identity();

  // A scene the view's composer did not plan: glass in a view with no tracked
  // site, or an image of a subtree taken outside a frame, which plans once from
  // nothing held. What it draws stands until the next plan.
  static void _composeAlone(Layer layer) {
    Layer top = layer;
    while (top.parent != null) {
      top = top.parent!;
    }
    final root = top as ContainerLayer;
    if (!_composedRoots.add(root)) return;
    if (_composedRoots.length == 1) {
      scheduleMicrotask(_composedRoots.clear);
    }
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      final composition = _Composition();
      try {
        composition.run(root);
      } finally {
        composition.dispose();
      }
      return;
    }
    final composition = (_alone[root] ??= _Composition())..run(root);
    final ranAt = scheduler.currentFrameTimeStamp;
    composition.ranAt = ranAt;
    // Dropped when the next frame's scene does not ask for it.
    scheduler.addPostFrameCallback((_) {
      scheduler.addPostFrameCallback((_) {
        if (composition.ranAt != ranAt) return;
        if (scheduler.currentFrameTimeStamp == ranAt) return;
        composition.dispose();
        _alone.remove(root);
      });
    });
  }
}

// One view's frame: the form of its layers, what the plan keeps between frames
// and what its reads hold.
final class _Composition {
  // The frame it last planned, while it plans alone.
  Duration? ranAt;

  final _form = Form();
  final _ledger = Ledger();
  final _emit = GlassEmit();

  Plan? _plan;
  Policy? _planPolicy;
  Prices? _planPrices;
  Rect _planScreen = Rect.zero;
  bool _planExplained = false;

  // Whether the last plan stands: nothing asked anew or changed and no read is
  // due an image. A paint empties the slots it fills, so it is shown again;
  // nothing it decided changes.
  bool _stands(Policy policy, Prices prices, bool explain) {
    final plan = _plan;
    final form = _form;
    return plan != null &&
        form.sitesHeld &&
        !form.asksChanged &&
        form.dirty.isEmpty &&
        form.frame < plan.dueAt &&
        identical(policy, _planPolicy) &&
        identical(prices, _planPrices) &&
        explain == _planExplained &&
        form.screen == _planScreen;
  }

  void run(ContainerLayer root, {bool Function()? painted}) {
    final view = root.owner;
    if (view is! RenderView) return;
    final flutterView = view.flutterView;
    final dpr = flutterView.devicePixelRatio;
    final listening = GlassFrameReport.listening;
    final clock = Stopwatch();
    if (listening) clock.start();
    FrameAncestors.current = FrameAncestors();
    try {
      final form = _form..lower(root, dpr, flutterView.physicalSize);
      for (final node in form.siteNodes) {
        form.noteAsk(node.facts, node.site.ask());
      }
      form
        ..noteSitesGone()
        ..settleFloors();
      final walk = clock.elapsed;
      final policy = GlassCopies.enabled
          ? GlassComposer.debugPolicy
          : const Policy(copies: false);
      final prices = GlassComposer.debugPrices;
      final explain = listening || GlassComposer.debugOnPlan != null;
      // Without a word of what painted, every frame plans.
      final stands = painted != null && _stands(policy, prices, explain);
      final shows = painted == null || !stands || painted();
      if (!stands) {
        final (plan, edits) = compile(
          form,
          _ledger,
          prices,
          policy,
          form.frame,
          explain: explain,
        );
        GlassComposer.debugOnPlan?.call(form, plan);
        edits.applyTo(_ledger, form.frame);
        _plan = plan;
        _planPolicy = policy;
        _planPrices = prices;
        _planScreen = form.screen;
        _planExplained = explain;
      }
      final planned = clock.elapsed;
      if (shows) _emit.emit(_plan!, form, again: stands);
      for (final node in form.siteNodes) {
        node.site.endFrame();
      }
      if (listening) {
        _report(form, _plan!, policy, walk, planned, clock.elapsed, stands);
      }
    } finally {
      FrameAncestors.current = null;
      // The atlases of a frame that emits nothing.
      FlutterGpuGeometryRenderer.flush();
    }
  }

  void _report(
    Form form,
    Plan plan,
    Policy policy,
    Duration walk,
    Duration planned,
    Duration done,
    bool stands,
  ) {
    final frame = form.frame;
    final reads = [
      for (final read in plan.reads)
        GlassFrameReport.readOf(read, stands: stands),
    ];
    GlassFrameReport.deliver(
      () => GlassFrameReport(
        frame: frame,
        planned: !stands,
        reads: reads,
        targetBudget: policy.maxTargets,
        issuedTargets: plan.issuedTargets,
        walk: walk,
        compile: planned - walk,
        emit: done - planned,
        filtersBuilt: GlassWork.filters,
        picturesRecorded: GlassWork.pictures,
        imagesDrawn: GlassWork.images,
        layersReplayed: GlassWork.replayed,
        repaintsAsked: GlassWork.marks,
        notes: plan.notes,
      ),
    );
  }

  void dispose() => _emit.dispose();
}

/// A layer whose decisions for a frame are the frame's plan's.
///
/// A scene the view's [GlassComposer] did not plan, such as an image of a
/// subtree taken outside a frame or before the composer ran, plans in the
/// update pass that builds the scene.
@internal
mixin ComposedLayer on ContainerLayer {
  /// Whether the view's composer planned the scene being built.
  @protected
  bool get composedAhead => GlassComposer._plannedAhead(this);

  @override
  void updateSubtreeNeedsAddToScene() {
    if (!composedAhead) GlassComposer._composeAlone(this);
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
