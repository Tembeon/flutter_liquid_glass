import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  testWidgets('selection haptics throttle at their minimum interval while '
      'impacts play freely', (tester) async {
    const interval = MotionHaptic.selectionMinimumInterval;
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
    clock.advanceTo(interval / 2);
    MotionHaptic.selection.play(leafContext);
    clock.advanceTo(interval - 0.001);
    MotionHaptic.selection.play(leafContext);
    expect(played, [MotionHaptic.selection]);

    clock.advanceTo(interval + 0.001);
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

  testWidgets('without onFeedback, each haptic plays its own platform '
      'feedback, success, warning and error the notification ones', (
    tester,
  ) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final clock = ManualMotionClock();
    late BuildContext leafContext;
    await tester.pumpWidget(
      MotionClockScope(
        clock: clock,
        child: Builder(
          builder: (context) {
            leafContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    for (final haptic in MotionHaptic.values) {
      haptic.play(leafContext);
      clock.advanceTo(clock.now + 1);
    }
    await tester.pump();
    expect(calls, [
      for (final haptic in MotionHaptic.values)
        switch (haptic) {
          MotionHaptic.selection => 'HapticFeedbackType.selectionClick',
          MotionHaptic.lightImpact ||
          MotionHaptic.softImpact => 'HapticFeedbackType.lightImpact',
          MotionHaptic.mediumImpact => 'HapticFeedbackType.mediumImpact',
          MotionHaptic.heavyImpact ||
          MotionHaptic.rigidImpact => 'HapticFeedbackType.heavyImpact',
          MotionHaptic.success => 'HapticFeedbackType.successNotification',
          MotionHaptic.warning => 'HapticFeedbackType.warningNotification',
          MotionHaptic.error => 'HapticFeedbackType.errorNotification',
        },
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
