import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';

const _direct = WornColorModel.direct(brightness: Brightness.light);

void main() {
  test('the blur floor blurs at half resolution on a 2x display or more', () {
    const settings = LiquidGlassSettings();
    for (final dpr in [2.0, 2.25, 2.625, 3.0, 3.5, 4.0]) {
      final sigma = settings.blurSigmaAt(_direct, dpr, shapeShortSide: 1);
      expect(
        ImpellerBlur.deviceSigma(sigma, dpr),
        greaterThanOrEqualTo(ImpellerBlur.halfResolutionSigma),
        reason: 'at $dpr',
      );
    }
  });

  test('the blur floor leaves the smallest blur pass alone at 3x', () {
    expect(
      const LiquidGlassSettings().blurSigmaAt(
        _direct,
        3,
        shapeShortSide: 1,
      ),
      2.1,
    );
  });

  test('the fitted blur and the recipe take the slider on its steps alike', () {
    for (final (off, on) in [(0.52, 0.5), (0.92, 0.9), (1.4, 1.0)]) {
      for (final settings in [
        LiquidGlassSettings(sliderPosition: off),
        LiquidGlassSettings.ios27Clear(sliderPosition: off),
      ]) {
        final stepped = settings.copyWith(sliderPosition: on);
        expect(settings.drawnSliderPosition, on);
        expect(settings.blurBaseOf(_direct), stepped.blurBaseOf(_direct));
      }
    }
  });
}
