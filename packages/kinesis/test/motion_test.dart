import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _bouncy = Spring.response(0.4, dampingRatio: 0.6);
const _glow = Spring.response(0.6);

class _Pair extends Motion {
  late final a = own(MotionValue<double>(0, spring: _bouncy));
  late final b = own(MotionValue<double>(0, spring: _glow));
  final List<(String, double)> log = [];
  bool held = false;

  @override
  bool get holds => held;

  void schedule(double t, String name, {Object? slot}) =>
      at(t, (t) => log.add((name, t)), slot: slot);

  void drop(Object slot) => cancel(slot);

  bool waits(Object slot) => isScheduled(slot);
}

class _Outer extends Motion {
  late final inner = own(_Pair());
  late final fade = own(
    MotionValue<double>(0, spring: _glow),
    rest: () => MotionRest.opacity,
  );
}

void main() {
  group('Motion', () {
    test('the cursor only moves forward', () {
      final m = _Pair();
      m.advance(0.5);
      m.advance(0.2);
      expect(m.now, 0.5);
    });

    test('reactions run at their own times, in order, however coarse the '
        'step', () {
      final m = _Pair();
      m.schedule(0.3, 'c');
      m.schedule(0.1, 'a');
      m.schedule(0.1, 'b');
      m.advance(1);
      expect(m.log, [('a', 0.1), ('b', 0.1), ('c', 0.3)]);
      expect(m.now, 1);
    });

    test('a reaction due by now runs right away at now', () {
      final m = _Pair();
      m.advance(0.4);
      m.schedule(0.2, 'late');
      expect(m.log, [('late', 0.4)]);
    });

    test('a slot keeps one reaction; cancel drops it', () {
      final m = _Pair();
      m.schedule(0.2, 'first', slot: #land);
      m.schedule(0.3, 'second', slot: #land);
      expect(m.waits(#land), isTrue);
      m.advance(1);
      expect(m.log, [('second', 0.3)]);
      m.schedule(1.2, 'gone', slot: #land);
      m.drop(#land);
      m.advance(2);
      expect(m.log, [('second', 0.3)]);
    });

    test('advanceUntil stops right after the reaction that answers', () {
      final m = _Pair();
      m.schedule(0.1, 'a');
      m.schedule(0.2, 'b');
      expect(m.advanceUntil(1, () => m.log.isNotEmpty), isFalse);
      expect(m.now, 0.1);
      expect(m.advanceUntil(1, () => false), isTrue);
      expect(m.log.last, ('b', 0.2));
    });

    test('an owned motion shares the cursor and the timeline', () {
      final outer = _Outer();
      outer.inner.schedule(0.2, 'inner');
      expect(outer.isSettled, isFalse);
      outer.advance(0.5);
      expect(outer.inner.now, 0.5);
      expect(outer.inner.log, [('inner', 0.2)]);
    });

    test('settles when every part rests and nothing waits or holds', () {
      final m = _Pair();
      m.a.retarget(0, 10);
      expect(m.isSettled, isFalse);
      m.advance(5);
      expect(m.isSettled, isTrue);
      m.held = true;
      expect(m.isSettled, isFalse);
      m.held = false;
      m.schedule(6, 'later');
      expect(m.isSettled, isFalse);
      expect(m.wakeTime, 6);
    });

    test('settle declares only the parts that rest; the others keep their '
        'course exactly', () {
      final m = _Pair();
      final twin = MotionValue<double>(0, spring: _glow);
      m.a.retarget(0, 10);
      m.b.retarget(0, 100);
      twin.retarget(0, 100);
      final aRest = m.a.restTime()!;
      final bRest = m.b.restTime()!;
      expect(bRest, greaterThan(aRest));
      final t = (aRest + bRest) / 2;
      m.advance(t);
      m.settle();
      expect(m.a.valueAt(t), 10);
      expect(m.a.velocityAt(t), 0);
      for (final s in [t, t + 0.05, bRest - 0.01]) {
        expect(m.b.valueAt(s), twin.valueAt(s));
      }
    });

    test('a part rests within the tolerance given to own', () {
      final outer = _Outer();
      outer.fade.retarget(0, 1);
      final loose = outer.fade.restTime(MotionRest.opacity)!;
      final tight = outer.fade.restTime(1e-6)!;
      expect(loose, lessThan(tight));
      outer.advance(loose + 1e-6);
      expect(outer.restTime(), closeTo(loose, 1e-9));
    });
  });
}
