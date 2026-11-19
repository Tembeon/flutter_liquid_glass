import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  testWidgets('selection haptics throttle at 40 ms while impacts play freely', (
    tester,
  ) async {
    final clock = ManualMotionClock();
    final played = <MotionHaptic>[];
    late BuildContext leafContext;

    await tester.pumpWidget(
      MotionClockScope(
        clock: clock,
        child: MotionHapticScope(
          enabled: true,
          onFeedback: played.add,
          child: Builder(
            builder: (context) {
              leafContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    MotionHaptic.selection.play(leafContext);
    clock.advanceTo(0.02);
    MotionHaptic.selection.play(leafContext);
    clock.advanceTo(0.039);
    MotionHaptic.selection.play(leafContext);
    expect(played, [MotionHaptic.selection]);

    clock.advanceTo(0.041);
    MotionHaptic.selection.play(leafContext);
    expect(played, [MotionHaptic.selection, MotionHaptic.selection]);

    // Impacts and notifications are not throttled.
    MotionHaptic.softImpact.play(leafContext);
    MotionHaptic.rigidImpact.play(leafContext);
    MotionHaptic.success.play(leafContext);
    MotionHaptic.warning.play(leafContext);
    MotionHaptic.error.play(leafContext);
    expect(played.sublist(2), [
      MotionHaptic.softImpact,
      MotionHaptic.rigidImpact,
      MotionHaptic.success,
      MotionHaptic.warning,
      MotionHaptic.error,
    ]);
  });

  testWidgets('a disabled ancestor scope blocks custom onFeedback below it', (
    tester,
  ) async {
    final clock = ManualMotionClock();
    final played = <MotionHaptic>[];
    late BuildContext leafContext;

    await tester.pumpWidget(
      MotionClockScope(
        clock: clock,
        child: MotionHapticScope(
          enabled: false,
          child: MotionHapticScope(
            enabled: true,
            onFeedback: played.add,
            child: Builder(
              builder: (context) {
                leafContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    MotionHaptic.lightImpact.play(leafContext);
    MotionHaptic.selection.play(leafContext);
    expect(played, isEmpty);
  });

  testWidgets(
    'selection haptics advance with frames while binding clock sleeps',
    (
      tester,
    ) async {
      MotionClock.debugReset();
      final played = <MotionHaptic>[];
      late BuildContext leafContext;

      await tester.pumpWidget(
        MotionHapticScope(
          enabled: true,
          onFeedback: played.add,
          child: Builder(
            builder: (context) {
              leafContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      MotionHaptic.selection.play(leafContext);
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 20));
      MotionHaptic.selection.play(leafContext);
      expect(played, [MotionHaptic.selection]);

      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 30));
      MotionHaptic.selection.play(leafContext);
      expect(played, [MotionHaptic.selection, MotionHaptic.selection]);
    },
  );
}
