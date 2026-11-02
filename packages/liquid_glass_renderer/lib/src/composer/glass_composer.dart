import 'dart:ui';

import 'package:flutter/rendering.dart';
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
  static void track(PipelineOwner owner, Object site) {
    var composer = _of(owner);
    if (composer == null) {
      composer = GlassComposer._();
      owner.adoptChild(composer);
    }
    composer._sites.add(site);
  }

  /// Stops following [site]. The last site to leave drops the composer.
  /// Call from a render object's `detach`, before `super.detach`.
  static void untrack(PipelineOwner owner, Object site) {
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

  final Set<Object> _sites = Set.identity();

  /// What this composer saw since it was adopted.
  @visibleForTesting
  final ComposerCensus census = ComposerCensus();

  @override
  void flushPaint() {
    super.flushPaint();
    census.frames++;
    census.sites += _sites.length;
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
