import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/widgets.dart';

class _Control extends StatefulWidget {
  const _Control({
    required this.enabled,
    required this.builds,
    this.statesController,
  });

  final bool enabled;
  final List<Set<WidgetState>> builds;
  final WidgetStatesController? statesController;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> with ControlStates<_Control> {
  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void writeStates() =>
      widgetStates.update(WidgetState.disabled, !widget.enabled);

  @override
  Widget build(BuildContext context) {
    widget.builds.add({...widgetStates.value});
    return const SizedBox();
  }
}

void main() {
  testWidgets('the widget states are written before the first build and '
      'on every update', (tester) async {
    final builds = <Set<WidgetState>>[];
    await tester.pumpWidget(_Control(enabled: false, builds: builds));
    expect(builds.single, {WidgetState.disabled});

    await tester.pumpWidget(_Control(enabled: true, builds: builds));
    expect(builds.last, isEmpty);
  });

  testWidgets('a change of the states rebuilds the control', (tester) async {
    final builds = <Set<WidgetState>>[];
    final controller = WidgetStatesController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _Control(enabled: true, builds: builds, statesController: controller),
    );
    controller.update(WidgetState.pressed, true);
    await tester.pump();
    expect(builds.last, {WidgetState.pressed});
  });

  testWidgets('a given controller replaces the own one and is listened to '
      'instead', (tester) async {
    final builds = <Set<WidgetState>>[];
    await tester.pumpWidget(_Control(enabled: true, builds: builds));
    final given = WidgetStatesController();
    addTearDown(given.dispose);
    await tester.pumpWidget(
      _Control(enabled: false, builds: builds, statesController: given),
    );
    expect(given.value, {WidgetState.disabled});

    final count = builds.length;
    given.update(WidgetState.hovered, true);
    await tester.pump();
    expect(builds.length, count + 1);
    expect(builds.last, {WidgetState.disabled, WidgetState.hovered});
  });
}
