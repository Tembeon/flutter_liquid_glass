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

  GlassPlan? _last;

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
    final basis = PlanBasis(
      screen: form.screen,
      devicePixelRatio: dpr,
      policy: glassPolicy,
      copies: glassReadsCopies,
      explain: listening || debugOnPlan != null,
    );
    // The last plan, while its sites ask as they did among the same clips,
    // state and other glass.
    final last = form.sitesKept && !form.sitesChanged ? _last : null;
    // Without a word of what painted, every frame plans.
    final stands =
        painted != null &&
        last != null &&
        planStands(last, form, basis, form.frame);
    if (stands) standPlan(last);
    // A paint empties the slots it fills, so a plan that stands is shown
    // again.
    final shows = painted == null || !stands || painted();
    final kept = !stands && painted != null && last != null
        ? keepPlan(last, form, _ledger, basis, form.frame)
        : null;
    if (!stands) {
      final (plan, edits) =
          kept ?? compilePlan(form, _ledger, basis, form.frame);
      debugOnPlan?.call(form, plan);
      edits.applyTo(_ledger, form.frame);
      _last = plan;
    }
    final planned = clock.elapsed;
    if (shows) _emit.emit(_last!, form);
    for (final node in form.siteNodes) {
      node.site.endFrame();
    }
    if (listening) {
      reportGlassFrame(
        frame: form.frame,
        plan: _last!,
        stands: stands,
        passBudget: basis.policy.maxPasses,
        walk: walk,
        planned: planned,
        done: clock.elapsed,
      );
    }
  }

  @override
  void dispose() => _emit.dispose();
}
