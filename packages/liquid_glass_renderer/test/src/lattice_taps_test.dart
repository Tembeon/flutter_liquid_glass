import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';

void main() {
  // What an axis of the frost weighs each pixel by: a read's weight split
  // between the two pixels it stands for.
  Map<int, double> pixelsOf(double frost) {
    final (:offsets, :weights) = latticeTaps(frost);
    final pixels = <int, double>{};
    for (var i = 0; i < 8; i++) {
      if (weights[i] == 0) continue;
      final first = offsets[i].floor();
      final far = offsets[i] - first;
      pixels[first] = (pixels[first] ?? 0) + weights[i] * (1 - far);
      pixels[first + 1] = (pixels[first + 1] ?? 0) + weights[i] * far;
    }
    return pixels;
  }

  test('a frost drawn in one pass reads the three pairs it takes, and one '
      'drawn an axis a pass more', () {
    for (var wide = 0.0001; wide <= 13; wide += 0.0001) {
      final frost = sqrt(wide);
      final (:offsets, :weights) = latticeTaps(frost);
      final pairs = weights.where((weight) => weight > 0).length;
      switch (frostLatticeOf(frost)) {
        case FrostLattice.square:
          expect(pairs, 3, reason: 'frost squared $wide');
          expect(weights.take(3).reduce((a, b) => a + b), closeTo(1, 1e-9));
        case FrostLattice.axes:
          expect(pairs, inInclusiveRange(4, 8), reason: 'frost squared $wide');
        case null:
          expect(pairs, 8, reason: 'frost squared $wide');
      }
    }
  });

  for (final frost in [0.6, 0.9, 1.2, 1.3, 1.7, 2.4, 3.0, 3.4]) {
    test('an axis of a frost by $frost pixels is a Gaussian of that '
        'width around the pixel', () {
      final pixels = pixelsOf(frost);
      var total = 0.0;
      var mean = 0.0;
      var variance = 0.0;
      for (final MapEntry(key: pixel, value: weight) in pixels.entries) {
        total += weight;
        mean += weight * pixel;
        variance += weight * pixel * pixel;
        expect(weight, closeTo(pixels[-pixel] ?? 0, 1e-9), reason: '$pixel');
      }
      expect(total, closeTo(1, 1e-9));
      expect(mean, closeTo(0, 1e-9));
      // The copy's pixels are a sixth of a pixel squared wider than the
      // frost left for a bilinear read of them. Three pairs hold a width of
      // 1.265 at most and four 1.732: a frost at the top of their ranges
      // gets that.
      final asked = sqrt(frost * frost + 1 / 6);
      expect(
        sqrt(variance),
        closeTo(asked, asked > 1.26 && asked < 1.27 ? 0.01 : 0.002),
      );
    });
  }
}
