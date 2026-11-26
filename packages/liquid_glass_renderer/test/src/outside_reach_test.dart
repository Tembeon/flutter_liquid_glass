import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';

void main() {
  test('fake glass draws a pixel past what real glass reaches outside its '
      'shape, wearing either model', () {
    for (final slider in [0.0, 0.5, 1.0]) {
      final look = FakeGlassLook.of(
        const LiquidGlassSettings().copyWith(sliderPosition: slider),
      );
      for (final variant in GlassVariant.values) {
        for (final brightness in Brightness.values) {
          for (final shortSide in [40.0, 120.0, 300.0]) {
            final recipe = (
              variant: variant,
              brightness: brightness,
              shortSide: shortSide,
              greyTint: false,
              highContrast: false,
              lift: GlassLift.resting,
            );
            final outward = recipeEdges([recipe], slider).outward;
            expect(outward, greaterThan(0));
            expect(
              fakeGlassSurfaceOutset(look, WornColorModel.recipe(recipe)),
              outward + 1,
            );
          }
        }
      }
      const direct = WornColorModel.direct(
        brightness: Brightness.light,
        rim: DirectRim(
          glintStrength: 1,
          contourStrength: 1,
          contourDirectionality: 0,
          bevelShadowStrength: 0,
        ),
      );
      expect(
        fakeGlassSurfaceOutset(look, direct),
        GlassRim.contourWidth + 1,
      );
      expect(
        fakeGlassSurfaceOutset(
          look,
          const WornColorModel.direct(brightness: Brightness.light),
        ),
        1,
      );
    }
  });

  test("the final shader's outside reach is the recipes' outward reach", () {
    for (final dpr in [1.0, 3.0]) {
      for (final model in [
        const LiquidGlassColorModel.ios27Regular(brightness: Brightness.dark),
        const LiquidGlassColorModel.ios27Lens(brightness: Brightness.light),
      ]) {
        final worn = model.wornAt(44);
        final look = (worn as WornRecipe).look;
        final edges = recipeEdges([look], 0);
        final face = GlassFace.of(
          settings: const LiquidGlassSettings(),
          appearance: WornAppearance(
            tint: const Color(0x00000000),
            visibility: 1,
            colorModel: worn,
          ),
          colorModels: [look],
          devicePixelRatio: dpr,
          blurs: false,
          edges: edges,
        ).face;
        expect(
          face[laneOffset(FaceLane.values, FaceLane.outsideReach)],
          moreOrLessEquals(edges.outward * dpr, epsilon: 1e-6),
        );
        expect(edges.outward, recipeOf(look, 0).darkSpecular.reach);
      }
    }
  });
}
