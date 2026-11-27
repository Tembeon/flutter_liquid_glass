import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

/// What plans the glass of one view's frame, between paint and the scene
/// ([GlassFrames]).
///
/// Unless another is installed ([GlassFrames.newPlanner]), each view's glass is
/// planned by [DirectReads]: every glass reads its own backdrop.
@internal
abstract interface class GlassPlanner {
  /// Whether glass reads copies of what lies under it in place of its
  /// backdrop: only a planner that lays copies out and replays them can.
  bool get readsCopies;

  /// Asks every site of the scene under [root] ([PlanSite.ask]) and tells
  /// each its fate, before the scene is built. [painted] says whether glass
  /// painted since the last plan; without it, as for an image of a subtree
  /// taken outside a frame, it plans from nothing held.
  void plan(ContainerLayer root, {bool Function()? painted});

  /// Lets go of what it holds.
  void dispose();
}

/// The planner where none is installed: each glass and each
/// [LiquidGlassBackdropFilterLayer] reads its own backdrop, which it binds as
/// it paints. Every site is asked, so that it reads where it lies this frame.
@internal
final class DirectReads implements GlassPlanner {
  /// Creates the planner.
  DirectReads();

  final List<PlanSite> _sites = [];

  @override
  bool get readsCopies => false;

  @override
  void plan(ContainerLayer root, {bool Function()? painted}) {
    final view = root.owner;
    if (view is! RenderView) return;
    final pixels = ViewPixels(view.configuration.devicePixelRatio);
    _collect(root);
    try {
      for (final site in _sites) {
        site.ask(pixels);
      }
      for (final site in _sites) {
        site.endFrame();
      }
    } finally {
      _sites.clear();
    }
  }

  void _collect(ContainerLayer layer) {
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      switch (child) {
        case final PlanSite site:
          _sites.add(site);
        case final LiquidGlassBackdropFilterLayer filter:
          _sites.add(filter.site);
      }
      if (child is ContainerLayer) _collect(child);
    }
  }

  @override
  void dispose() {}
}

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
/// moved past what its retained layers can follow repaints in this frame,
/// and asks each site with a repaint boundary marked under it whether it
/// would paint late ([TransformTrackingRenderObjectMixin.paintsLate]), and
/// marks it to paint in this frame if so. After paint its [GlassPlanner]
/// plans the frame, before any scene is built. Then it submits the frame's
/// flutter_gpu passes.
///
/// What cannot be known before paint stays a frame late: a shape under a
/// [RenderFollowerLayer] whose leader moved this frame, as the leader's
/// offset exists only after paint. Such a mark is counted apart, in
/// [GlassWork.lateMarks].
///
/// One per view owner, adopted by the first render object holding a glass
/// layer that attaches there, a site ([track]) or a host ([host]), and
/// dropped and disposed when the last one detaches, so a view owner that is
/// disposed never holds one.
@internal
final class GlassFrames extends PipelineOwner {
  GlassFrames._(this._view) : super(onSemanticsUpdate: _noSemantics);

  factory GlassFrames._adopt(PipelineOwner owner) {
    if (_of(owner) case final frames?) return frames;
    final frames = GlassFrames._(owner);
    owner.adoptChild(frames);
    return frames;
  }

  /// Makes the planner of each view's glass, from each view's next frame on:
  /// [DirectReads] unless another is installed, as the frame's composer is.
  static GlassPlanner Function() newPlanner = DirectReads.new;

  /// Whether glass that attached to [owner] reads copies of what lies under
  /// it, as its view's planner decides.
  static bool readsCopies(PipelineOwner owner) =>
      _of(owner)?._planner.readsCopies ?? false;

  // The view's owner, which adopted this and holds its sites.
  final PipelineOwner _view;

  GlassPlanner? _held;
  GlassPlanner Function()? _heldFrom;

  GlassPlanner get _planner {
    if (_held case final held?) return held;
    _heldFrom = newPlanner;
    return _held = newPlanner();
  }

  // Takes a planner installed since the last frame before the view paints:
  // a glass layer painted for the planner it had, so each paints again. A
  // host's filter layer reads what the new planner's plan gives it.
  void _takeNewPlanner() {
    final held = _held;
    if (held == null || identical(_heldFrom, newPlanner)) return;
    held.dispose();
    _held = null;
    for (final site in _sites) {
      site.markNeedsPaint();
    }
  }

  // Counts the passes that ask sites before paint; a site holds the pass
  // that last asked it.
  int _pass = 0;

  // It owns no render object; with semantics enabled it still gets a
  // semantics owner, which never has anything to send.
  static void _noSemantics(SemanticsUpdate update) => update.dispose();

  /// Starts following [site] on the glass of [owner]'s view, adopting it
  /// under [owner] if [owner] has none. Call from a render object's `attach`.
  static void track(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    GlassFrames._adopt(owner)._sites.add(site);
  }

  /// Stops following [site]. The last site or host to leave drops the
  /// view's glass. Call from a render object's `detach`, before
  /// `super.detach`.
  static void untrack(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    final frames = _of(owner);
    if (frames == null || !frames._sites.remove(site)) return;
    frames._dropIfEmpty(owner);
  }

  /// Plans the scenes of [owner]'s view for [holder], a render object that
  /// holds a glass layer without being a site, adopting the view's glass
  /// under [owner] if it has none. Call from a render object's `attach`.
  static void host(PipelineOwner owner, LiquidGlassBackdropFilterHost holder) {
    GlassFrames._adopt(owner)._hosts.add(holder);
  }

  /// Stops planning for [holder]. The last site or host to leave drops the
  /// view's glass. Call from a render object's `detach`, before
  /// `super.detach`.
  static void unhost(
    PipelineOwner owner,
    LiquidGlassBackdropFilterHost holder,
  ) {
    final frames = _of(owner);
    if (frames == null || !frames._hosts.remove(holder)) return;
    frames._dropIfEmpty(owner);
  }

  void _dropIfEmpty(PipelineOwner owner) {
    if (_sites.isNotEmpty || _hosts.isNotEmpty) return;
    owner.dropChild(this);
    dispose();
  }

  static GlassFrames? _of(PipelineOwner owner) {
    GlassFrames? found;
    owner.visitChildren((child) {
      if (child is GlassFrames) found = child;
    });
    return found;
  }

  /// The glass of the views under [root] and its descendant owners, for
  /// benches and tests.
  @visibleForTesting
  static List<GlassFrames> debugAllUnder(PipelineOwner root) {
    final all = <GlassFrames>[];
    void visit(PipelineOwner owner) {
      if (owner is GlassFrames) all.add(owner);
      owner.visitChildren(visit);
    }

    visit(root);
    return all;
  }

  /// The planner this view's glass is planned by, for tests.
  @visibleForTesting
  GlassPlanner get debugPlanner => _planner;

  /// Marks [node] to paint again from a decision made between paint and the
  /// scene. While its view's glass is planned, the frame's paint is over
  /// and the node paints in the next frame, as a mark made while the scene
  /// is built would.
  static void repaint(RenderObject node) {
    if (!kReleaseMode) GlassWork.marks++;
    final owner = node.owner;
    if (owner == null || !(_of(owner)?._planning ?? false)) {
      node.markNeedsPaint();
      return;
    }
    if (!kReleaseMode) GlassWork.lateMarks++;
    // After the frame: paint is over, so the mark is the next frame's.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.attached) node.markNeedsPaint();
    });
  }

  final Set<TransformTrackingRenderObjectMixin> _sites = Set.identity();
  final Set<LiquidGlassBackdropFilterHost> _hosts = Set.identity();
  bool _planning = false;

  // Whether glass painted since the last plan: it paints a slot the plan fills.
  bool _painted = true;

  /// Notes that a site of [owner]'s view painted this frame.
  static void sitePainted(PipelineOwner owner) {
    _of(owner)?._painted = true;
  }

  // The frame this view's glass was planned in.
  Duration? _planned;

  /// What this view's glass saw since it was adopted.
  @visibleForTesting
  final GlassFramesCensus census = GlassFramesCensus();

  /// Sites that rested since this was last cleared.
  @internal
  static int debugRests = 0;

  @override
  void flushCompositingBits() {
    super.flushCompositingBits();
    _takeNewPlanner();
    for (final site in _sites) {
      if (site.repaintsOnMove) site.layer?.pollTransform();
    }
    _askOverDirtyBoundaries();
  }

  // Asks the nearest site above each boundary the view is about to paint
  // whether it would paint late. A layout may run this again in the frame
  // (a resolve phase), which asks again.
  void _askOverDirtyBoundaries() {
    final dirty = _view.nodesNeedingPaint;
    if (dirty.isEmpty || _sites.isEmpty) return;
    final pass = ++_pass;
    var shallowest = -1;
    for (final site in _sites) {
      if (shallowest < 0 || site.depth < shallowest) shallowest = site.depth;
    }
    var marks = false;
    for (final node in dirty) {
      for (
        var parent = node.parent;
        parent != null && parent.depth >= shallowest;
        parent = parent.parent
      ) {
        if (parent is! TransformTrackingRenderObjectMixin) continue;
        if (parent.paintsLateAsked != pass) {
          parent.paintsLateAsked = pass;
          if (parent.paintsLate()) {
            parent.paintsLateMarked = pass;
            marks = true;
          }
        }
        break;
      }
    }
    // Marking adds to the list walked above.
    if (!marks) return;
    for (final site in _sites) {
      if (site.paintsLateMarked == pass) repaint(site);
    }
  }

  @override
  void flushPaint() {
    super.flushPaint();
    census.frames++;
    census.sites += _sites.length;
    final root = _root();
    if (root == null) return;
    _planning = true;
    try {
      // A site's poll may paint it again while the plan's facts are filled.
      _plan(_planner, root, painted: () => _painted);
      _painted = false;
      _planned = SchedulerBinding.instance.currentFrameTimeStamp;
    } finally {
      _planning = false;
    }
  }

  static void _plan(
    GlassPlanner planner,
    ContainerLayer root, {
    bool Function()? painted,
  }) {
    FrameAncestors.current = FrameAncestors();
    try {
      planner.plan(root, painted: painted);
    } finally {
      FrameAncestors.current = null;
      // The atlases of a frame whose plan draws none.
      FlutterGpuGeometryRenderer.flush();
    }
  }

  @override
  void dispose() {
    _held?.dispose();
    _held = null;
    super.dispose();
  }

  ContainerLayer? _root() {
    for (final site in _sites) {
      if (_rootOf(site.layer) case final root?) return root;
    }
    for (final host in _hosts) {
      if (_rootOf(host.backdropFilterLayer) case final root?) return root;
    }
    return null;
  }

  static ContainerLayer? _rootOf(Layer? layer) =>
      layer == null || !layer.attached ? null : _topOf(layer);

  static bool _plannedAhead(Layer layer) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    final view = layer.owner;
    if (view is! RenderView) return false;
    final owner = view.owner;
    if (owner == null) return false;
    final frames = _of(owner);
    return frames != null &&
        frames._planned == SchedulerBinding.instance.currentFrameTimeStamp;
  }

  // The roots a scene no view's glass planned was planned for, until the
  // scene's update pass is over: every glass layer of the scene asks.
  static final _plannedRoots = Set<ContainerLayer>.identity();

  /// Scenes planned alone since this was last cleared.
  @visibleForTesting
  static int debugPlannedAlone = 0;

  // A scene the view's glass did not plan: an image of a subtree taken
  // outside a frame, which plans once from nothing held. What it draws stands
  // until the next plan.
  static void _planAlone(Layer layer) {
    final root = _topOf(layer);
    if (!_plannedRoots.add(root)) return;
    if (_plannedRoots.length == 1) {
      scheduleMicrotask(_plannedRoots.clear);
    }
    assert(
      !_inFrameUnregistered(root),
      '$layer is composited in a frame, but no render object of its view is '
      "registered with the view's GlassFrames, so nothing planned the scene "
      'ahead. A render object that holds a LiquidGlassBackdropFilterLayer '
      'mixes in LiquidGlassBackdropFilterHost and returns the layer from '
      'backdropFilterLayer.',
    );
    if (!kReleaseMode) debugPlannedAlone++;
    final planner = newPlanner();
    try {
      _plan(planner, root);
    } finally {
      planner.dispose();
    }
  }

  static ContainerLayer _topOf(Layer layer) {
    var top = layer;
    while (top.parent != null) {
      top = top.parent!;
    }
    return top as ContainerLayer;
  }

  static bool _inFrameUnregistered(ContainerLayer root) =>
      SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks &&
      switch (root.owner) {
        RenderView(:final owner?) => _of(owner) == null,
        _ => false,
      };
}

/// Plans the scene [layer] is built in, where the view's glass did not plan
/// it ahead.
///
/// A layer whose decisions for a frame are the frame's plan's calls it as
/// the scene is built. A scene the view's [GlassFrames] did not plan, an
/// image of a subtree taken outside a frame, plans here. In a frame the
/// view's glass plans ahead for the render object that holds the layer,
/// registered as a site or a [LiquidGlassBackdropFilterHost].
@internal
void planUnlessPlanned(Layer layer) {
  if (!GlassFrames._plannedAhead(layer)) GlassFrames._planAlone(layer);
}

/// Whether the view's glass planned the scene [layer] is being built in.
@visibleForTesting
bool debugPlannedAhead(Layer layer) => GlassFrames._plannedAhead(layer);

/// Counts of a [GlassFrames]'s frames.
@internal
final class GlassFramesCensus {
  /// Frames painted while the view had a site or a host.
  int frames = 0;

  /// Sites summed over [frames].
  int sites = 0;
}
