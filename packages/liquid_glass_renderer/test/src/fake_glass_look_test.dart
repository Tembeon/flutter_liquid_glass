import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';

void main() {
  const settings = LiquidGlassSettings();

  test('settings that differ where fake glass draws nothing look alike', () {
    expect(
      FakeGlassLook.of(
        settings.copyWith(
          refractionAmount: 30,
          refractionHeight: 40,
          lens: const LiquidGlassLens(aberration: 1),
        ),
      ),
      FakeGlassLook.of(settings),
    );
    expect(
      FakeGlassLook.of(settings.copyWith(sliderPosition: 2)),
      FakeGlassLook.of(settings.copyWith(sliderPosition: 1)),
    );
  });

  test('settings that differ where fake glass draws look different', () {
    for (final other in [
      settings.copyWith(blur: 4),
      settings.copyWith(sliderPosition: 0.5),
      settings.copyWith(reduceTransparency: true),
    ]) {
      expect(FakeGlassLook.of(other), isNot(FakeGlassLook.of(settings)));
    }
  });

  test('a look blur and the same blur given look different: only the look '
      'grows with the glass', () {
    const regular = WornColorModel.direct(brightness: Brightness.light);
    final base = glassBlurBase(
      blur: null,
      system: (slider: 0, reduceTransparency: false),
      variant: GlassVariant.regular,
    );
    final given = FakeGlassLook.of(settings.copyWith(blur: base));
    expect(given, isNot(FakeGlassLook.of(settings)));
    expect(
      FakeGlassLook.of(settings).blurSigmaAt(regular, 3, shapeShortSide: 150),
      greaterThan(given.blurSigmaAt(regular, 3, shapeShortSide: 150)),
    );
  });
}
