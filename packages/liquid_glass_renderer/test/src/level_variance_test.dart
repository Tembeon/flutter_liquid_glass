import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';

void main() {
  test('a variance reads the deepest level that blurs by at most it', () {
    for (final share in [1, 2]) {
      for (var variance = 0.0; variance < 5500; variance += 0.01) {
        final k = levelBelow(variance, share: share);
        final reason = 'variance $variance, share $share';
        if (k > 0) {
          expect(
            levelVariance(k, share: share),
            lessThanOrEqualTo(variance + 1e-9),
            reason: reason,
          );
        }
        expect(
          levelVariance(k + 1, share: share),
          greaterThan(variance - 1e-9),
          reason: reason,
        );
      }
    }
  });
}
