// The switches a bench can flip, by name.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/scroll_edge.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart' show Prices;
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

/// The switches an A/B run can flip, by name. `none` flips nothing: an A/A
/// run that shows the noise floor.
final benchSwitches = <String, void Function({required bool on})>{
  'none': ({required on}) {},
  // B also lowers the frame's layers and compiles a plan it does not use.
  'shadow': ({required on}) => GlassComposer.debugShadowPlan = on,
  // B: glass with nothing changed around it skips reading where it lies.
  'form_rests': ({required on}) => GlassComposer.debugFormRests = on,
  // B: the frame's scan skips what no copy can reach.
  'scan_prune': ({required on}) => UnderlayFrame.debugPrunes = on,
  // B: the frame's groups come from its plan.
  'plan_groups': ({required on}) => UnderlayFrame.debugPlansGroups = on,
  // B: everything the planner took over so far.
  'planner': ({required on}) {
    GlassComposer.debugFormRests = on;
    UnderlayFrame.debugPrunes = on;
    UnderlayFrame.debugPlansGroups = on;
  },
  // B: pixels a group's clip cuts cost next to nothing, so chrome at both ends
  // of the screen shares a filter.
  'dead_cheap': ({required on}) => GlassComposer.debugPrices = on
      ? const Prices(deadGpuPerMpx: 0.02)
      : const Prices(),
  'groups': ({required on}) => BackdropUnderlay.debugGroups = on,
  'group_bands': ({required on}) => BackdropUnderlay.debugBandGroups = on,
  'no_shadows': ({required on}) {
    LiquidGlassRenderObject.debugNoShadows = on;
    void update(RenderObject node) {
      if (node is RenderLiquidGlassLayer) node.debugUpdateGeometry();
      node.visitChildren(update);
    }

    RendererBinding.instance.renderViews.forEach(update);
  },
  // B draws every second vsync while nothing fast moves; A every vsync.
  'cadence': ({required on}) => FrameCadence.enabled = on,
  'wide_frost': ({required on}) => debugShaderFrostMaxDownscale = on ? 8 : 4,
  // B frosts a small copy once, A in every fragment of the glass over it.
  'in_place': ({required on}) => debugFrostsInPlace = on,
  // B also takes the smallest copy the frost allows, so most frost is baked.
  'bake': ({required on}) {
    debugFrostsInPlace = on;
    RenderLiquidGlassLayer.debugFrostMinTexels = on ? 1.0 : double.infinity;
  },
  // B: copies as small as the frost allows, A: as large.
  'small_copies': ({required on}) =>
      RenderLiquidGlassLayer.debugFrostMinTexels = on ? 1.2 : double.infinity,
  // B: a copy under what holds still moves from the frame to an image.
  'promotes': ({required on}) => BackdropUnderlay.debugPromotes = on,
  // B: scroll edges only fade, without blur.
  'edge_fade': ({required on}) => debugSetEdgeBlurs(on: !on),
  // B adds a copy to the scene as its layers, A records it into a picture.
  'in_scene': ({required on}) => BackdropUnderlay.debugInScene = on,
  // B leaves a backdrop frost out of a copy for wider frosted glass.
  'drops_frost': ({required on}) => BackdropUnderlay.debugDropsFrost = on,
  // B leaves glass out of a copy of few pixels.
  'drops_glass': ({required on}) => BackdropUnderlay.debugDropsGlass = on,
  'islands': ({required on}) => BackdropUnderlay.debugIslandsEnabled = on,
  'downscale4': ({required on}) =>
      RenderLiquidGlassLayer.debugMaxCopyDownscale = on ? 4 : 2,
  // B draws the copies asked for without a filter in the frame, A into
  // images.
  'in_frame': ({required on}) => BackdropUnderlay.debugInFrame = on,
  // B reads the backdrop live instead of drawing copies.
  'live_reads': ({required on}) =>
      BackdropUnderlay.debugEnabledOverride = on ? false : null,
  // B frosts copies in the glass shader; A blurs them and draws frosted
  // glass with the shaders that cannot frost, as before.
  'shader_frost': ({required on}) {
    RenderLiquidGlassLayer.debugShaderFrost = on;
    void update(RenderObject node) {
      if (node is RenderLiquidGlassLayer) node.debugUpdateShaders();
      node.visitChildren(update);
    }

    RendererBinding.instance.renderViews.forEach(update);
  },
  // B frosts the copies of scroll edges and fake glass in a shader; A
  // filters them in the atlas.
  'copy_frost': ({required on}) =>
      LiquidGlassBackdropFrost.debugShaderFrost = on,
  // B draws the text of a copy smaller than the screen where it lies, A on
  // the copy's pixels.
  'place_text': ({required on}) => BackdropUnderlay.debugPlaceText = on,
};
