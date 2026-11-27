import 'package:apple_liquid_glass/src/motions/list_highlight.dart';
import 'package:apple_liquid_glass/src/motions/segment_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('list row', () {
    test('waits the touch delay, then fades after the tap', () {
      final motion = ListRowHighlight();
      motion.press(0.1, contact: 0);
      expect(motion.isSettled, isFalse);
      motion.advance(0.149);
      expect(motion.opacity, 0);
      motion.advance(0.15);
      expect(motion.opacity, 1);
      motion.fadeOut(0.6);
      expect(motion.opacity, 1);
      motion.advance(0.85);
      expect(motion.opacity, closeTo(0.5, 1e-9));
      motion.advance(1.1);
      expect(motion.opacity, 0);
      expect(motion.isSettled, isTrue);
    });

    test('a tap released before the delay shows at the release', () {
      final motion = ListRowHighlight();
      motion.press(0.067, contact: 0);
      motion.fadeOut(0.067);
      expect(motion.opacity, 1);
      motion.advance(0.2);
      expect(motion.opacity, greaterThan(0.8));
    });

    test('a scroll removes it at once', () {
      final motion = ListRowHighlight();
      motion.press(0.1, contact: 0);
      motion.advance(0.2);
      expect(motion.opacity, 1);
      motion.clear(0.2);
      expect(motion.opacity, 0);
      expect(motion.isSettled, isTrue);
    });

    test('a selected row stays highlighted through touches and fades when '
        'deselected', () {
      final motion = ListRowHighlight();
      motion.setSelected(0, selected: true);
      expect(motion.opacity, 1);
      motion.press(0.1, contact: 0);
      motion.fadeOut(0.2);
      motion.clear(0.3);
      motion.advance(1);
      expect(motion.opacity, 1);
      motion.setSelected(1, selected: false);
      motion.advance(1.25);
      expect(motion.opacity, closeTo(0.5, 1e-9));
      motion.advance(1.5);
      expect(motion.opacity, 0);
      expect(motion.isSettled, isTrue);
    });

    test('a pending highlight wakes the clock at its time', () {
      final motion = ListRowHighlight();
      motion.press(0, contact: 0);
      expect(motion.wakeTime, 0.15);
    });
  });

  group('segment label', () {
    test('dims on the measured curve and returns faster', () {
      final motion = SegmentHighlight();
      motion.press(0, 1);
      expect(motion.opacity(1), 1);
      expect(motion.opacity(0), 1);
      motion.advance(0.47);
      expect(motion.opacity(1), closeTo(0.2, 1e-9));
      expect(motion.isSettled, isTrue);
      motion.release(1);
      expect(motion.opacity(1), closeTo(0.2, 1e-9));
      motion.advance(1.2);
      expect(motion.opacity(1), closeTo(1, 1e-6));
      expect(motion.index, isNull);
      expect(motion.isSettled, isTrue);
    });

    test('a quick tap returns from where the dimming reached', () {
      final motion = SegmentHighlight();
      motion.press(0, 2);
      motion.advance(0.067);
      final reached = motion.opacity(2);
      expect(reached, lessThan(1));
      expect(reached, greaterThan(0.85));
      motion.release(0.067);
      expect(motion.opacity(2), closeTo(reached, 1e-9));
    });

    test('a second release does not start the return again', () {
      final motion = SegmentHighlight();
      motion.press(0, 1);
      motion.advance(0.47);
      motion.release(1);
      motion.advance(1.1);
      final halfway = motion.opacity(1);
      motion.release(1.1);
      expect(motion.opacity(1), halfway);
      motion.advance(1.2);
      expect(motion.opacity(1), closeTo(1, 1e-6));
    });
  });
}
