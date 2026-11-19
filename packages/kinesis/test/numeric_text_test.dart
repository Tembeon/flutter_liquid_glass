import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  group('NumericTextMotion', () {
    test('rolls only changed digits and keeps prefix/suffix stationary', () {
      final motion = NumericTextMotion(r'$1,239');
      motion.setText(0, r'$1,240');

      final mid = motion.slotsAt(0.05);
      expect(mid.map((s) => s.current).join(), r'$1,240');
      // '$', '1', ',', '2' did not change.
      expect(mid[0].previous, isNull);
      expect(mid[1].previous, isNull);
      expect(mid[2].previous, isNull);
      expect(mid[3].previous, isNull);
      // '3' -> '4' and '9' -> '0' roll upward (+1).
      expect(mid[4].previous, '3');
      expect(mid[4].current, '4');
      expect(mid[4].direction, 1);
      expect(mid[5].previous, '9');
      expect(mid[5].current, '0');
      expect(mid[5].direction, 1);
      expect(mid[5].progress, greaterThan(0));
      expect(mid[5].progress, lessThan(1));

      motion.advance(2);
      final done = motion.slots;
      expect(done.every((s) => s.previous == null), isTrue);
    });

    test(
      'infers countsDown direction and handles digit count growth/shrink',
      () {
        final motion = NumericTextMotion('10');
        motion.setText(0, '9');
        final downSlots = motion.slotsAt(0.05);
        expect(downSlots[0].leaving, isTrue);
        expect(downSlots[0].previous, '1');
        expect(downSlots[0].direction, -1);
        expect(downSlots[1].previous, '0');
        expect(downSlots[1].current, '9');
        expect(downSlots[1].direction, -1);

        motion.advance(2);
        motion.setText(2, '10');
        final upSlots = motion.slotsAt(2.05);
        expect(upSlots[0].entering, isTrue);
        expect(upSlots[0].current, '1');
        expect(upSlots[0].direction, 1);
        expect(upSlots[1].previous, '9');
        expect(upSlots[1].current, '0');
      },
    );

    test('uses direction 0 (fade) under reduceMotion', () {
      final motion = NumericTextMotion('5')
        ..traits = const MotionTraits(reduceMotion: true);
      motion.setText(0, '6');
      final mid = motion.slotsAt(0.05);
      expect(mid.single.direction, 0);
      expect(mid.single.previous, '5');
      expect(mid.single.current, '6');
    });
  });

  testWidgets('MotionNumericText animates digit rolls with zero widget '
      'rebuilds per frame', (tester) async {
    final clock = ManualMotionClock();
    Widget app(String text) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: MotionNumericText(
            text,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('42'));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(app('43'));
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (var i = 1; i <= 15; i++) {
      clock.advanceTo(i / 60);
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
  });

  testWidgets('MotionNumericText drops a leaving digit once it settles', (
    tester,
  ) async {
    final clock = ManualMotionClock();
    Widget app(String text, {Key? key}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: MotionNumericText(
            text,
            key: key,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('10'));
    await tester.pumpWidget(app('9'));
    for (var i = 1; i <= 120; i++) {
      clock.advanceTo(i / 60);
      await tester.pump();
    }
    expect(find.text('1'), findsNothing);
    final settled = tester.getSize(find.byType(MotionNumericText));

    await tester.pumpWidget(app('9', key: const ValueKey('fresh')));
    expect(tester.getSize(find.byType(MotionNumericText)), settled);
  });
}
