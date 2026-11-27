import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_form.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

/// What the plans of the current test decided.
final class PlanWatch {
  /// Watches every plan from here to the end of the test.
  PlanWatch() {
    GlassComposer.debugOnPlan = _note;
    addTearDown(() => GlassComposer.debugOnPlan = null);
  }

  final _changes = Map<Object, int>.identity();

  /// The last plan.
  GlassPlan? last;

  void _note(GlassForm form, GlassPlan plan) {
    last = plan;
    for (var i = 0; i < plan.fates.length; i++) {
      final read = switch (plan.fates[i]) {
        LeadFate(:final read) || FollowFate(:final read) => read,
        HiddenFate() => null,
      };
      if (read == null || !read.changed) continue;
      final id = form.sites[i].id;
      final site = id is TransformTrackingLayer ? id.trackedSite! : id;
      _changes[site] = (_changes[site] ?? 0) + 1;
    }
  }

  /// In how many plans the read of [site], a render object or a filter layer,
  /// held something new.
  int changes(Object site) => _changes[site] ?? 0;
}
