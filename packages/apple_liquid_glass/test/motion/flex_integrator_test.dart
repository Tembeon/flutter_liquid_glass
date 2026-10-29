import 'package:apple_liquid_glass/src/motion/flex_integrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlexSubClock', () {
    test('reports every frame boundary crossed, once', () {
      final clock = FlexSubClock(60);
      final frames = <double>[];
      clock.start(0);
      clock.run(0.05, frames.add);
      clock.run(0.05, frames.add);
      clock.run(1 / 15, frames.add);
      expect(frames, [1 / 60, 2 / 60, 3 / 60, 4 / 60]);
    });

    test('does not depend on how the time is split', () {
      List<double> collect(List<double> steps) {
        final clock = FlexSubClock(120);
        final frames = <double>[];
        clock.start(0.003);
        for (final t in steps) {
          clock.run(t, frames.add);
        }
        return frames;
      }

      final coarse = collect([0.5]);
      final fine = collect([for (var i = 1; i <= 50; i++) i / 100]);
      expect(fine, coarse);
      expect(coarse.length, 60);
    });
  });

  group('FlexIntegrator', () {
    test('filters the rate of change of speed with weight 0.3', () {
      final flex = FlexIntegrator();
      flex.reset(0);
      final af = flex.step(10, 0.5);
      expect(flex.pf, 3);
      expect(flex.vf, closeTo(1.8, 1e-12));
      expect(af, closeTo(1.08, 1e-12));
      expect(flex.af, af);
    });

    test('an unprimed filter starts at rest on the first position', () {
      final flex = FlexIntegrator();
      expect(flex.step(5, 1 / 60), 0);
      expect(flex.pf, 5);
      expect(flex.vf, 0);
    });
  });
}
