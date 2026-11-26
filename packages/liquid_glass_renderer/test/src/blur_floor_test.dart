import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';

const _direct = WornColorModel.direct();

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
}
