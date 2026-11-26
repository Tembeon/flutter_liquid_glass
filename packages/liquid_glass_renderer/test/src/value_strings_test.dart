import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('values print their fields by the names their constructors take', () {
    expect(
      const LiquidGlassContentBend(amount: 2, height: 9).toString(),
      'LiquidGlassContentBend(amount: 2.0, height: 9.0)',
    );
    expect(
      const LiquidGlassSettings().toString(),
      allOf(
        startsWith('LiquidGlassSettings(refractionHeight: '),
        contains('sliderPosition: 0.0, blur: null)'),
      ),
    );
    expect(
      const LensSettings(pull: 9, pullDepth: 36).toString(),
      startsWith('LensSettings(pull: 9.0, pullDepth: 36.0, '),
    );
    expect(
      const LiquidGlassAppearance().toString(),
      startsWith('LiquidGlassAppearance(tint: '),
    );
    expect(
      LiquidGlassMaterial.ios27Regular(
        brightness: Brightness.light,
      ).toString(),
      startsWith('LiquidGlassMaterial(settings: LiquidGlassSettings('),
    );
  });
}
