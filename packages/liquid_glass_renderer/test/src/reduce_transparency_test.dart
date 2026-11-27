import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';

void main() {
  const reduced = LiquidGlassSettings.ios27Regular(reduceTransparency: true);

  test('Reduce Transparency is a setting of its own', () {
    const regular = LiquidGlassSettings.ios27Regular();
    expect(reduced, isNot(regular));
    expect(reduced.hashCode, isNot(regular.hashCode));
    expect(regular.copyWith(reduceTransparency: true), reduced);
    expect(reduced.copyWith(sliderPosition: 0.5).reduceTransparency, isTrue);
    expect(reduced.toString(), contains('reduceTransparency: true'));
    expect(
      const LiquidGlassSettings.ios27Clear(reduceTransparency: true),
      isNot(const LiquidGlassSettings.ios27Clear()),
    );
  });

  test('glass under Reduce Transparency refracts nothing', () {
    expect(reduced.drawnRefractionAmount, 0);
    expect(reduced.drawnRefractionHeight, 0);
    expect(const LiquidGlassSettings.ios27Regular().drawnRefractionAmount, 60);
  });

  test('the one blur of glass under Reduce Transparency is its recipe deep '
      'blur, as Impeller is asked for it, and a blur given still wins', () {
    const system = (slider: 0.0, reduceTransparency: true);
    for (final (variant, side) in [
      (GlassVariant.regular, 44.0),
      (GlassVariant.regular, 150.0),
      (GlassVariant.clear, 80.0),
    ]) {
      final blur = GlassRecipe.of(
        variant: variant,
        brightness: Brightness.light,
        shortSide: side,
        reduceTransparency: true,
      ).blur;
      expect(
        glassBlurSigma(
          blur: null,
          system: system,
          variant: variant,
          devicePixelRatio: 3,
          shapeShortSide: side,
        ),
        closeTo(
          blur.radius * ios27BlurUnit / ImpellerBlur.deliveredFraction,
          1e-9,
        ),
        reason: '$variant at $side',
      );
    }
    expect(
      glassBlurSigma(
        blur: 6,
        system: system,
        variant: GlassVariant.regular,
        devicePixelRatio: 3,
      ),
      6,
    );
  });
}
