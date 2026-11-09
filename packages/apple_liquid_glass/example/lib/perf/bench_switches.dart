// The switches a bench can flip, by name.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/scroll_edge.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart'
    show Policy, Prices;
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

/// The switches an A/B run can flip, by name. `none` flips nothing: an A/A
/// run that shows the noise floor.
final benchSwitches = <String, void Function({required bool on})>{
  'none': ({required on}) {},
  // B: a read keeps what did not change between frames, A walks all of it.
  'keeps_layers': ({required on}) => GlassCopies.debugKeepsLayers = on,
  // B: pixels a group's clip cuts cost next to nothing, so chrome at both ends
  // of the screen shares a filter.
  'dead_cheap': ({required on}) => GlassComposer.debugPrices = on
      ? const Prices(deadGpuPerMpx: 0.02)
      : const Prices(),
  'groups': ({required on}) => GlassComposer.debugPolicy = on
      ? const Policy()
      : const Policy(maxShapes: 0),
  'group_bands': ({required on}) =>
      GlassComposer.debugPolicy = Policy(bands: on),
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
  'in_place': ({required on}) =>
      GlassComposer.debugPolicy = Policy(bakesFrost: on),
  // B also takes the smallest copy the frost allows, so most frost is baked.
  'bake': ({required on}) {
    GlassComposer.debugPolicy = Policy(bakesFrost: on);
    RenderLiquidGlassLayer.debugFrostMinTexels = on ? 1.0 : double.infinity;
  },
  // B: copies as small as the frost allows, A: as large.
  'small_copies': ({required on}) =>
      RenderLiquidGlassLayer.debugFrostMinTexels = on ? 1.2 : double.infinity,
  // B: a copy under what holds still moves from the frame to an image.
  'promotes': ({required on}) => GlassComposer.debugPrices = on
      ? const Prices()
      : const Prices(imageGpu: 1e6),
  // B: a frame past its targets moves reads to images, A stays over.
  'overflow': ({required on}) =>
      GlassComposer.debugPolicy = Policy(maxTargets: on ? 8 : 1024),
  // B adds a texture to a read's scene again, A reads the backdrop live over
  // it. B only shows true where the texture shows the same frame in both.
  'texture_in_scene': ({required on}) => GlassCopies.debugTextureInScene = on,
  // B: scroll edges only fade, without blur.
  'edge_fade': ({required on}) => debugSetEdgeBlurs(on: !on),
  // B leaves a backdrop frost out of a copy for wider frosted glass.
  'drops_frost': ({required on}) =>
      GlassComposer.debugPolicy = Policy(dropsFrost: on),
  // B: a copy of a quarter of the screen's pixels holds the glass under it,
  // at the screen's pixels; A leaves that glass out.
  'coarse_holds': ({required on}) =>
      GlassComposer.debugPolicy = Policy(coarseHolds: on),
  // B: a copy smaller than the screen holds the glass under it at its own
  // pixels, A at the screen's.
  'own_grid_holds': ({required on}) =>
      GlassComposer.debugPolicy = Policy(ownGridHolds: on),
  'downscale4': ({required on}) =>
      RenderLiquidGlassLayer.debugMaxCopyDownscale = on ? 4 : 2,
  // B draws the copies asked for without a filter in the frame, A into
  // images.
  'in_frame': ({required on}) =>
      GlassComposer.debugPolicy = Policy(maxTargets: on ? 8 : 0),
  // B reads the backdrop live instead of drawing copies.
  'live_reads': ({required on}) =>
      GlassCopies.debugEnabledOverride = on ? false : null,
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
  'place_text': ({required on}) => GlassCopies.debugPlaceText = on,
};
