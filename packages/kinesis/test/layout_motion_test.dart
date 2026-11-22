import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _spring = Spring.response(0.3);

class _Planner extends LayoutPlanner {
  _Planner(this.plans);

  final LayoutPlan Function(Object id, LayoutEntry entry) plans;
  final List<LayoutChange> changes = [];

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) {
    changes.add(change);
    return {
      for (final MapEntry(:key, :value) in change.entries.entries)
        key: plans(key, value),
    };
  }
}

LayoutMotion _laidOut(Map<Object, Rect> rects, {LayoutPlanner? planner}) {
  final motion = LayoutMotion(
    planner: planner ?? const LayoutPlanner.flip(),
  );
  motion.layout(0, rects);
  return motion;
}

Rect _at(LayoutMotion motion, double t, Object id) {
  motion.advance(t);
  return motion.itemAt(id).rect;
}

const _a = Rect.fromLTWH(0, 0, 10, 10);
const _b = Rect.fromLTWH(0, 20, 10, 10);
const _far = Rect.fromLTWH(100, 0, 10, 10);
const _farther = Rect.fromLTWH(200, 0, 10, 10);

void main() {
  test('the first layout puts every item in place', () {
    final motion = _laidOut({'a': _a, 'b': _b});
    expect(motion.itemAt('a').rect, _a);
    expect(motion.itemAt('b').pose.opacity, 1);
    expect(motion.isSettled, isTrue);
  });

  group('an id it never laid out', () {
    late List<FlutterErrorDetails> reported;
    late FlutterExceptionHandler? handler;
    setUp(() {
      reported = [];
      handler = FlutterError.onError;
      FlutterError.onError = reported.add;
    });
    tearDown(() => FlutterError.onError = handler);

    test('is reported at the next layout, with the key it meant', () {
      final motion = _laidOut({const ValueKey('a'): _a});
      expect(motion.laidOut('a'), isNull);
      motion.layout(0.1, {const ValueKey('a'): _a});
      expect(reported, hasLength(1));
      final message = reported.single.exception.toString();
      expect(message, contains('never laid out'));
      expect(message, contains("[<'a'>]"));
    });

    test('is not reported when the next layout brings it', () {
      final motion = _laidOut({'a': _a});
      expect(motion.itemAt('b').rect, Rect.zero);
      motion.layout(0.1, {'a': _a, 'b': _b});
      expect(reported, isEmpty);
    });

    test('is not reported once it has left', () {
      final motion = _laidOut({'a': _a, 'b': _b});
      motion.layout(0.1, {'a': _a});
      expect(motion.laidOut('b'), isNull);
      motion.layout(0.2, {'a': _a});
      expect(reported, isEmpty);
    });
  });

  test('a change pairs each item with where it was drawn', () {
    final planner = _Planner((_, _) => const LayoutPlan(spring: _spring));
    final motion = _laidOut({'a': _a}, planner: planner);
    motion.layout(0, {'a': _far}, spring: _spring);
    final drawn = _at(motion, 0.1, 'a');
    motion.layout(0.1, {'a': _farther}, spring: _spring);
    final entry = planner.changes.last.entries['a']!;
    expect(entry.phase, LayoutPhase.staying);
    expect(entry.from, _far);
    expect(entry.to, _farther);
    expect(entry.shown, drawn);
    expect(drawn.left, inExclusiveRange(0, 100));
  });

  test('an entering item starts at its origin', () {
    const origin = Rect.fromLTWH(50, 50, 2, 2);
    final motion = _laidOut(
      {'a': _a},
      planner: _Planner(
        (_, _) => const LayoutPlan(spring: _spring, origin: origin),
      ),
    );
    motion.layout(0, {'a': _a, 'b': _b});
    expect(motion.itemAt('b').rect, origin);
    expect(_at(motion, 0.05, 'b'), isNot(origin));
    expect(_at(motion, 5, 'b'), _b);
  });

  test('a leaving item goes to its destination, then is dropped', () {
    const destination = Rect.fromLTWH(0, 0, 2, 2);
    final motion = _laidOut(
      {'a': _a, 'b': _b},
      planner: _Planner(
        (_, entry) => LayoutPlan(
          spring: _spring,
          destination: entry.phase == LayoutPhase.leaving ? destination : null,
        ),
      ),
    );
    motion.layout(0, {'a': _a}, spring: _spring);
    expect(motion.isLeaving('b'), isTrue);
    final halfway = _at(motion, 0.1, 'b');
    expect(halfway.top, inExclusiveRange(0, 20));
    expect(motion.bounds, _a);
    motion.advance(5);
    expect(motion.contains('b'), isFalse);
    expect(motion.isSettled, isTrue);
  });

  test('a leaving item without a spring goes at once', () {
    final motion = _laidOut({'a': _a, 'b': _b});
    motion.layout(0, {'a': _a});
    expect(motion.contains('b'), isFalse);
  });

  test('an item brought back while it leaves enters from where it is', () {
    final motion = _laidOut({'a': _a, 'b': _b});
    motion.layout(0, {'a': _a}, spring: _spring);
    motion.advance(0.1);
    final fading = motion.itemAt('b').pose.opacity;
    motion.layout(0.1, {'a': _a, 'b': _b}, spring: _spring);
    expect(motion.isLeaving('b'), isFalse);
    expect(motion.itemAt('b').pose.opacity, closeTo(fading, 1e-9));
    motion.advance(5);
    expect(motion.itemAt('b').pose.opacity, 1);
  });

  test('each axis moves on its own spring', () {
    const wide = Rect.fromLTWH(0, 0, 110, 10);
    final motion = _laidOut(
      {'a': _a},
      planner: _Planner(
        (_, _) => const LayoutPlan(
          spring: _spring,
          springs: RectSprings(
            center: Spring.response(0.1),
            width: Spring.response(1),
          ),
        ),
      ),
    );
    motion.layout(0, {'a': wide});
    final rect = _at(motion, 0.3, 'a');
    expect(rect.center.dx, closeTo(wide.center.dx, 1));
    expect(rect.width, lessThan(80));
  });

  test('a delay keeps the item on its course before it moves', () {
    final motion = _laidOut(
      {'a': _a},
      planner: _Planner(
        (_, _) => const LayoutPlan(spring: _spring, delay: 0.2),
      ),
    );
    motion.layout(0, {'a': _far});
    expect(_at(motion, 0.15, 'a'), _a);
    expect(_at(motion, 0.3, 'a').left, greaterThan(0));
  });

  test('placeItem without snap springs home from the placed rect', () {
    final motion = _laidOut({'a': _a});
    final drawn = Rect.lerp(_a, _far, 0.5)!;
    motion.placeItem(0, 'a', drawn);
    expect(motion.itemAt('a').rect, drawn);
    expect(_at(motion, 0.1, 'a').left, inExclusiveRange(0, drawn.left));
    expect(_at(motion, 5, 'a'), _a);
  });

  test('placeItem with snap rests at the placed rect for the next layout', () {
    final motion = _laidOut({'a': _a});
    final drawn = Rect.lerp(_a, _far, 0.5)!;
    motion.placeItem(0, 'a', drawn, snap: true);
    expect(motion.itemAt('a').rect, drawn);
    expect(motion.isSettled, isTrue);
    motion.layout(0, {'a': _far}, spring: _spring);
    expect(_at(motion, 0.05, 'a').left, inExclusiveRange(drawn.left, 100));
  });

  test('without a spring an item at rest jumps', () {
    final motion = _laidOut({'a': _a});
    motion.layout(0, {'a': _far});
    expect(motion.itemAt('a').rect, _far);
  });

  test('without a spring an item in flight is carried along', () {
    final motion = _laidOut({'a': _a});
    motion.layout(0, {'a': _far}, spring: _spring);
    final drawn = _at(motion, 0.1, 'a');
    const shifted = Rect.fromLTWH(100, 30, 10, 10);
    motion.layout(0.1, {'a': shifted});
    expect(motion.itemAt('a').rect, drawn.shift(const Offset(0, 30)));
    expect(_at(motion, 5, 'a'), shifted);
  });

  test('with arrived, an entering item not in it is put in place at once '
      'and one in it follows its plan', () {
    final motion = _laidOut({'a': _a});
    motion.layout(
      0,
      {'a': _a, 'b': _b, 'c': _far},
      spring: _spring,
      arrived: {'c'},
    );
    expect(motion.itemAt('b').pose.opacity, 1);
    expect(motion.itemAt('c').pose.opacity, 0);
  });

  test('a jump puts every item in place whatever the springs', () {
    final motion = _laidOut(
      {'a': _a, 'b': _b},
      planner: const LayoutPlanner.flip(spring: _spring),
    );
    motion.layout(0, {'a': _far}, spring: Spring.immediate);
    expect(motion.itemAt('a').rect, _far);
    expect(motion.contains('b'), isFalse);
    expect(motion.isSettled, isTrue);
  });

  test('the absent pose follows the presence', () {
    final motion = _laidOut(
      {'a': _a},
      planner: const LayoutPlanner.flip(insert: MotionPose(scale: 0.5)),
    );
    motion.layout(0, {'a': _a, 'b': _b}, spring: _spring);
    expect(motion.itemAt('b').pose.scale, 0.5);
    motion.advance(5);
    expect(motion.itemAt('b').pose.scale, 1);
  });

  test('a change lists every item, an unchanged one keeping its course', () {
    final planner = _Planner((_, _) => const LayoutPlan(spring: _spring));
    final motion = _laidOut({'a': _a, 'b': _b}, planner: planner);
    motion.layout(0, {'a': _far, 'b': _b});
    final drawn = _at(motion, 0.1, 'a');
    motion.layout(0.1, {'a': _far, 'b': _farther}, spring: _spring);
    final entries = planner.changes.last.entries;
    expect(entries['a']!.from, entries['a']!.to);
    expect(entries['a']!.shown, drawn);
    expect(_at(motion, 0.2, 'a').left, greaterThan(drawn.left));
    expect(motion.layout(0.2, {'a': _far, 'b': _farther}), isNull);
  });

  test('a leaving item goes once its rect rests within its plan', () {
    const destination = Rect.fromLTWH(0, 0, 2, 2);
    final motion = _laidOut(
      {'a': _a, 'b': _b},
      planner: _Planner(
        (_, entry) => LayoutPlan(
          spring: const Spring.response(0.05),
          springs: const RectSprings.all(Spring.response(1)),
          destination: entry.phase == LayoutPhase.leaving ? destination : null,
          rest: 0.05,
          absent: const MotionPose(opacity: 0),
        ),
      ),
    );
    motion.layout(0, {'a': _a}, spring: _spring);
    motion.advance(0.5);
    expect(motion.itemAt('b').pose.opacity, closeTo(0, 1e-9));
    expect(motion.contains('b'), isTrue);
    motion.advance(5);
    expect(motion.contains('b'), isFalse);
  });

  test('a jump drops the items that leave', () {
    final motion = _laidOut({'a': _a, 'b': _b});
    motion.layout(0, {'a': _a}, spring: _spring);
    expect(motion.isLeaving('b'), isTrue);
    motion.layout(0.05, {'a': _far}, spring: Spring.immediate);
    expect(motion.contains('b'), isFalse);
  });

  test('under Reduce Motion an item enters with its absent opacity alone', () {
    final motion = LayoutMotion(
      planner: const LayoutPlanner.flip(
        insert: MotionPose(scale: 0.5, opacity: 0),
      ),
    )..traits = const MotionTraits(reduceMotion: true);
    motion.layout(0, {'a': _a});
    motion.layout(0, {'a': _a, 'b': _b}, spring: _spring);
    final entering = motion.itemAt('b').pose;
    expect(entering.scale, 1);
    expect(entering.opacity, 0);
  });

  test("a bouncy enter stops at the item's own look, and an item at rest or "
      'only moving wears the identity pose itself', () {
    final motion = _laidOut(
      {'a': _a},
      planner: const LayoutPlanner.flip(
        insert: MotionPose(offset: Offset(0, 20), scale: 0.5),
      ),
    );
    motion.layout(
      0,
      {'a': _far, 'b': _b},
      spring: const Spring.response(0.3, dampingRatio: 0.3),
    );
    var overshot = false;
    for (var t = 0.01; t < 1; t += 0.01) {
      motion.advance(t);
      overshot = overshot || motion.presenceAt('b') > 1;
      final pose = motion.itemAt('b').pose;
      expect(pose.scale, lessThanOrEqualTo(1));
      expect(pose.offset.dy, greaterThanOrEqualTo(0));
      expect(identical(motion.itemAt('a').pose, MotionPose.identity), isTrue);
    }
    expect(overshot, isTrue);
    motion.advance(5);
    expect(motion.isSettled, isTrue);
    motion.settle();
    expect(identical(motion.itemAt('b').pose, MotionPose.identity), isTrue);
  });

  test('resolves layout springs against its own reduceMotion trait', () {
    const reducedSpring = Spring.response(0.2);
    const bouncy = Spring.response(
      0.4,
      dampingRatio: 0.5,
      reduced: reducedSpring,
    );
    final reduced = _laidOut({'a': _a})
      ..traits = const MotionTraits(reduceMotion: true);
    final normal = _laidOut({'a': _a});
    reduced.layout(0, {'a': _far}, spring: bouncy);
    normal.layout(0, {'a': _far}, spring: bouncy);
    final expected = MotionValue<double>(0, spring: reducedSpring)
      ..retarget(0, 100);
    expect(_at(reduced, 0.15, 'a').left, closeTo(expected.valueAt(0.15), 1e-6));
    expect(
      _at(reduced, 0.15, 'a').left,
      isNot(closeTo(_at(normal, 0.15, 'a').left, 1e-2)),
    );
  });
}
