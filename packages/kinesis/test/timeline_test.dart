import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

void main() {
  group('MotionTimeline', () {
    test('runs due actions in time order, each at its own time', () {
      final timeline = MotionTimeline(now: 0);
      final log = <String>[];
      timeline.insert(0.3, (t) => log.add('c@$t'));
      timeline.insert(0.1, (t) => log.add('a@$t'));
      timeline.insert(0.2, (t) => log.add('b@$t'));
      expect(timeline.isEmpty, isFalse);
      timeline.runDue(0.25);
      expect(log, ['a@0.1', 'b@0.2']);
      expect(timeline.now, 0.25);
      timeline.runDue(1);
      expect(log, ['a@0.1', 'b@0.2', 'c@0.3']);
      expect(timeline.isEmpty, isTrue);
    });

    test('keeps insertion order for equal times', () {
      final timeline = MotionTimeline();
      final log = <int>[];
      for (var i = 0; i < 5; i++) {
        timeline.insert(0.5, (t) => log.add(i));
      }
      timeline.insert(0.4, (t) => log.add(-1));
      timeline.runDue(0.5);
      expect(log, [-1, 0, 1, 2, 3, 4]);
    });

    test('an action sees its own time and may schedule relative to it', () {
      final timeline = MotionTimeline(now: 0);
      final log = <(String, double, double)>[];
      timeline.insert(0.1, (t) {
        log.add(('first', t, timeline.now));
        timeline.at(t + 0.05, (s) => log.add(('chained', s, timeline.now)));
        timeline.at(t, (s) => log.add(('immediate', s, timeline.now)));
      });
      timeline.runDue(0.2);
      expect(log, [
        ('first', 0.1, 0.1),
        ('immediate', 0.1, 0.1),
        ('chained', 0.15000000000000002, 0.15000000000000002),
      ]);
      expect(timeline.now, 0.2);
    });

    test('at runs an action that is already due right away at now', () {
      final timeline = MotionTimeline(now: 1);
      final log = <double>[];
      timeline.at(0.5, log.add);
      expect(log, [1]);
      expect(timeline.isEmpty, isTrue);
    });

    test('runDue never moves now backwards', () {
      final timeline = MotionTimeline(now: 1);
      timeline.runDue(0.5);
      expect(timeline.now, 1);
    });

    test('flush runs everything at the given time and clear drops it', () {
      final timeline = MotionTimeline(now: 0);
      final log = <double>[];
      timeline.insert(2, log.add);
      timeline.insert(3, log.add);
      timeline.flush(1);
      expect(log, [1, 1]);
      timeline.insert(4, log.add);
      timeline.clear();
      timeline.runDue(10);
      expect(log, [1, 1]);
    });
  });
}
