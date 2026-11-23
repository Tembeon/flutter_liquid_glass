import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/motion/clock.dart' show MotionClockTesting;
import 'package:kinesis/testing.dart';

/// A control that shows a number its app owns.
class _Control extends StatefulWidget {
  const _Control({required this.value, required this.onChanged, super.key});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> with ControlledValue<_Control> {
  late int shown = widget.value;
  final ValueNotifier<bool> leads = ValueNotifier(false);

  @override
  MotionClock get valueClock => MotionClock.instance;

  @override
  ValueListenable<bool> get userDriving => leads;

  @override
  void syncFromWidget() => shown = widget.value;

  @override
  void dispose() {
    leads.dispose();
    super.dispose();
  }

  /// What a motion's event does when the user picks [value].
  void choose(int value) {
    shown = value;
    notifyChanged(() => widget.onChanged(value));
  }

  @override
  Widget buildControl(BuildContext context) =>
      Text('$shown', textDirection: TextDirection.ltr);
}

void main() {
  setUp(MotionClock.debugReset);

  final key = GlobalKey<_ControlState>();

  testWidgets('keeps the value an app follows', (tester) async {
    var value = 1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _Control(
          key: key,
          value: value,
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );
    key.currentState!.choose(2);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(value, 2);
  });

  testWidgets('returns to the value of an app that does not follow', (
    tester,
  ) async {
    final heard = <int>[];
    await tester.pumpWidget(
      _Control(key: key, value: 1, onChanged: heard.add),
    );
    key.currentState!.choose(2);
    expect(key.currentState!.shown, 2);
    await tester.pump();
    expect(heard, [2]);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('does not return while the user leads, and returns once '
      'they stop', (tester) async {
    await tester.pumpWidget(_Control(key: key, value: 1, onChanged: (_) {}));
    final state = key.currentState!;
    state.leads.value = true;
    state.choose(2);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    state.leads.value = false;
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets("shows a parent's new value only once the user stops leading", (
    tester,
  ) async {
    await tester.pumpWidget(_Control(key: key, value: 1, onChanged: (_) {}));
    final state = key.currentState!;
    state.leads.value = true;
    await tester.pumpWidget(_Control(key: key, value: 3, onChanged: (_) {}));
    expect(find.text('1'), findsOneWidget);
    state.leads.value = false;
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('under a muted TickerMode a moving lead keeps nothing on the '
      'clock, and is heard when the ticker runs', (tester) async {
    final clock = _WatchedClock();
    final lead = MotionValue<double>(0, clock: clock);
    final driving = MotionSelection(() => lead.value > 0.5, clock: clock);
    Widget control({required bool enabled}) => TickerMode(
      enabled: enabled,
      child: _Driven(clock: clock, driving: driving),
    );
    await tester.pumpWidget(control(enabled: false));
    withSpring(const Spring.response(0.2), () => lead.target = 1);
    expect(clock.busy, isFalse);
    await tester.pumpWidget(control(enabled: true));
    expect(clock.busy, isTrue);
  });

  testWidgets('an event raised while the framework lays out reaches the app '
      'in the coming publish phase, where it may rebuild', (tester) async {
    var value = 1;
    var raise = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return LayoutBuilder(
            builder: (context, constraints) {
              if (raise) {
                raise = false;
                key.currentState!.choose(2);
              }
              return _Control(
                key: key,
                value: value,
                onChanged: (next) => setState(() => value = next),
              );
            },
          );
        },
      ),
    );
    rebuild(() => raise = true);
    await tester.pump();
    expect(value, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 16));
    expect(value, 2);
    expect(find.text('2'), findsOneWidget);
  });
}

final class _WatchedClock extends ManualMotionClock {
  bool get busy => needsFrame;
}

/// A control whose lead is [driving], on [clock].
class _Driven extends StatefulWidget {
  const _Driven({required this.clock, required this.driving});

  final MotionClock clock;
  final ValueListenable<bool> driving;

  @override
  State<_Driven> createState() => _DrivenState();
}

class _DrivenState extends State<_Driven> with ControlledValue<_Driven> {
  @override
  MotionClock get valueClock => widget.clock;

  @override
  ValueListenable<bool> get userDriving => widget.driving;

  @override
  void syncFromWidget() {}

  @override
  Widget buildControl(BuildContext context) => const SizedBox();
}
