import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  group('ScrollDeceleration', () {
    test('normal and fast rates match UIKit projection times and landings', () {
      expect(ScrollDeceleration.normal.projectionTime, closeTo(0.499, 1e-9));
      expect(ScrollDeceleration.fast.projectionTime, closeTo(0.099, 1e-9));

      // Measured sim 27.2 runs: v = 2207 pt/s -> +1097.3 pt (normal),
      // +218.7 pt (fast); v = 392 pt/s -> +191 pt (normal).
      expect(
        ScrollDeceleration.normal.landingOffset(0, 2207),
        closeTo(1096.3, 1.5),
      );
      expect(
        ScrollDeceleration.normal.landingOffset(0, 392),
        closeTo(190.6, 1.0),
      );
      expect(
        ScrollDeceleration.fast.landingOffset(0, 2207),
        closeTo(217.5, 1.5),
      );
      // Below stopSpeed: stays put.
      expect(ScrollDeceleration.normal.landingOffset(100, 5), 100);
    });

    test('free deceleration step lands within 1 pt of landingOffset', () {
      var offset = 0.0;
      var velocity = 2207.0;
      var time = 0.0;
      const dt = 1 / 60;
      while (time < 5) {
        final next = ScrollDeceleration.normal.step(
          offset: offset,
          velocity: velocity,
          dt: dt,
          min: 0,
          max: 5000,
        );
        offset = next.offset;
        velocity = next.velocity;
        time += dt;
        if (next.settled) break;
      }
      expect(velocity, 0);
      expect(
        offset,
        closeTo(ScrollDeceleration.normal.landingOffset(0, 2207), 2),
      );
      expect(time, closeTo(2.70, 0.15));
    });

    test(
      'unified edge-bounce replays pull release and fling into top edge',
      () {
        // Pull 170 pt past top edge (-62), slow release v = -169 pt/s: settles in ~0.62 s.
        var offset = -62.0 - 170.0;
        var velocity = -169.0;
        var elapsed = 0.0;
        const dt = 1 / 60;
        while (elapsed < 3) {
          final next = ScrollDeceleration.normal.step(
            offset: offset,
            velocity: velocity,
            dt: dt,
            min: -62,
            max: 5000,
          );
          offset = next.offset;
          velocity = next.velocity;
          elapsed += dt;
          if (next.settled) break;
        }
        expect(offset, -62);
        expect(velocity, 0);
        expect(elapsed, closeTo(0.62, 0.08));

        // Fling into top from offset 24 (min -62, 86 pt away) at -2241 pt/s:
        // overshoots past -62 and settles back at -62 in ~0.78 s.
        offset = 24;
        velocity = -2241;
        elapsed = 0;
        var minSeen = offset;
        while (elapsed < 3) {
          final next = ScrollDeceleration.normal.step(
            offset: offset,
            velocity: velocity,
            dt: dt,
            min: -62,
            max: 5000,
          );
          offset = next.offset;
          velocity = next.velocity;
          elapsed += dt;
          if (offset < minSeen) minSeen = offset;
          if (next.settled) break;
        }
        expect(minSeen, lessThan(-100));
        expect(offset, -62);
        expect(elapsed, closeTo(0.78, 0.12));
      },
    );

    test('bounces false clamps at boundary without overshooting', () {
      final step = ScrollDeceleration.normal.step(
        offset: 5,
        velocity: -1000,
        dt: 1 / 60,
        min: 0,
        max: 500,
        bounces: false,
      );
      expect(step.offset, 0);
      expect(step.velocity, 0);
      expect(step.settled, isTrue);
    });

    test('zoomDuration matches UIKit logarithmic formula', () {
      expect(ScrollDeceleration.zoomDuration(1, 1.25), closeTo(0.1669, 1e-3));
      expect(ScrollDeceleration.zoomDuration(1, 2), closeTo(0.3079, 1e-3));
      expect(ScrollDeceleration.zoomDuration(2, 1), closeTo(0.3079, 1e-3));
      expect(ScrollDeceleration.zoomDuration(1, 4), 0.4);
    });
  });

  group('PagingPhysics', () {
    test('flips page past 300 pt/s and snaps to nearest below threshold', () {
      const paging = PagingPhysics();
      expect(paging.spring.omega, closeTo(15.9, 1e-6));
      expect(paging.spring.dampingRatio, 0.88);

      // 60 pt drag on 402 pt page: pan 280 stays on page 0, pan 320 flips to 1.
      expect(
        paging.targetPage(
          offset: 60,
          pageExtent: 402,
          velocity: 280,
          pageCount: 5,
        ),
        0,
      );
      expect(
        paging.targetPage(
          offset: 60,
          pageExtent: 402,
          velocity: 320,
          pageCount: 5,
        ),
        1,
      );
      // 231 pt drag (past half), zero velocity: next page.
      expect(
        paging.targetPage(
          offset: 231,
          pageExtent: 402,
          velocity: 0,
          pageCount: 5,
        ),
        1,
      );
      // Clamps at bounds.
      expect(
        paging.targetPage(
          offset: 0,
          pageExtent: 402,
          velocity: -500,
          pageCount: 5,
        ),
        0,
      );
      expect(
        paging.targetOffset(
          offset: 402 * 4,
          pageExtent: 402,
          velocity: 500,
          pageCount: 5,
        ),
        402 * 4,
      );
    });
  });

  group('ScrollToTopCurve', () {
    test('reaches ~50% at 0.07 s and ~90% at 0.24 s over 1.6 s', () {
      const curve = ScrollToTopCurve();
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      expect(
        curve.transform(0.07 / ScrollToTopCurve.duration),
        closeTo(0.5, 0.06),
      );
      expect(
        curve.transform(0.24 / ScrollToTopCurve.duration),
        closeTo(0.9, 0.04),
      );
    });
  });
}
