import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_form.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/plan_ledger.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_report.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';

/// The frame's composer: the planner ([GlassPlanner]) that plans one view's
/// glass from the view's layers.
///
/// After paint it lowers the view's layers into a [GlassForm], asks every
/// site for its facts, compiles the frame's [GlassPlan] and draws it: copies
/// of what lies under glass ([glassReadsCopies]), held images of them, reads
/// of the backdrop, and one read shared by glass beside glass.
@internal
final class GlassComposer implements GlassPlanner {
  /// Creates a view's composer.
  GlassComposer();

  /// Plans the glass of every view with a composer, from each view's next
  /// frame on.
  static void install() => GlassFrames.newPlanner = GlassComposer.new;

  /// Handed each frame's plan, with its reasons, while set.
  @visibleForTesting
  static void Function(GlassForm form, GlassPlan plan)? debugOnPlan;

  final _form = GlassForm();
  final _ledger = PlanLedger();
  final _emit = GlassEmit();

  // The last plan and what it was compiled under.
  ({
    GlassPlan plan,
    PlanPolicy policy,
    bool copies,
    Rect screen,
    bool explained,
  })?
  _last;

  // Whether the last plan's decisions still hold, unless what lies under the
  // glass says otherwise: no site asks anew and nothing it was compiled
  // under changed.
  bool _holds(PlanPolicy policy, bool copies, bool explain) {
    final form = _form;
    return switch (_last) {
      final last? =>
        form.sitesHeld &&
            !form.asksChanged &&
            identical(policy, last.policy) &&
            copies == last.copies &&
            explain == last.explained &&
            form.screen == last.screen,
      null => false,
    };
  }

  // Whether the last plan stands: it holds, nothing changed under the glass
  // and no read is due an image. A paint empties the slots it fills, so it is
  // shown again; nothing it decided changes.
  bool _stands(PlanPolicy policy, bool copies, bool explain) =>
      _holds(policy, copies, explain) &&
      _form.dirty.isEmpty &&
      _form.frame < _last!.plan.dueAt;

  @override
  bool get readsCopies => glassReadsCopies;

  @override
  void plan(ContainerLayer root, {bool Function()? painted}) {
    final view = root.owner;
    if (view is! RenderView) return;
    final flutterView = view.flutterView;
    final dpr = view.configuration.devicePixelRatio;
    final listening = glassFrameReportsWanted;
    final clock = Stopwatch();
    if (listening) clock.start();
    final pixels = ViewPixels(dpr);
    final form = _form..lower(root, dpr, flutterView.physicalSize);
    for (final node in form.siteNodes) {
      form.noteAsk(node.facts, node.site.ask(pixels));
    }
    form
      ..noteSitesGone()
      ..settleFloors();
    final walk = clock.elapsed;
    final policy = glassPolicy;
    final copies = glassReadsCopies;
    final explain = listening || debugOnPlan != null;
    // Without a word of what painted, every frame plans.
    final stands = painted != null && _stands(policy, copies, explain);
    final shows = painted == null || !stands || painted();
    // Glass over a scroll keeps its reads; they learn what changed under
    // them.
    final kept = !stands && painted != null && _holds(policy, copies, explain)
        ? keepPlan(_last!.plan, form, _ledger, form.frame)
        : null;
    if (kept case (final plan, final edits)) {
      debugOnPlan?.call(form, plan);
      edits.applyTo(_ledger, form.frame);
      _last = (
        plan: plan,
        policy: policy,
        copies: copies,
        screen: form.screen,
        explained: explain,
      );
    } else if (!stands) {
      final (plan, edits) = compilePlan(
        form,
        _ledger,
        policy,
        form.frame,
        copies: copies,
        explain: explain,
      );
      debugOnPlan?.call(form, plan);
      edits.applyTo(_ledger, form.frame);
      _last = (
        plan: plan,
        policy: policy,
        copies: copies,
        screen: form.screen,
        explained: explain,
      );
    }
    final planned = clock.elapsed;
    if (shows) _emit.emit(_last!.plan, form, again: stands || kept != null);
    for (final node in form.siteNodes) {
      node.site.endFrame();
    }
    if (listening) {
      reportGlassFrame(
        frame: form.frame,
        plan: _last!.plan,
        stands: stands,
        targetBudget: policy.maxTargets,
        walk: walk,
        planned: planned,
        done: clock.elapsed,
      );
    }
  }

  @override
  void dispose() => _emit.dispose();
}
