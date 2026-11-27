import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// A context menu's hold around a button: a staged long press of UIKit's
/// context menu times over a region whose press taps.
class _HeldButton extends StatefulWidget {
  const _HeldButton({required this.heard, this.contends = true});

  final List<String> heard;
  final bool contends;

  @override
  State<_HeldButton> createState() => _HeldButtonState();
}

class _HeldButtonState extends State<_HeldButton> {
  late final List<Interaction> _hold = [
    LongPressInteraction(
      duration: 0.78,
      armAfter: 0.42,
      allowableMovement: 18,
      contends: widget.contends,
      onArmed: (t) => widget.heard.add('armed'),
      onStart: (t) => widget.heard.add('start'),
      onFail: (t) => widget.heard.add('fail'),
    ),
  ];

  late final List<Interaction> _press = [
    PressInteraction(onTap: (t) => widget.heard.add('tap')),
  ];

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: InputRegion(
        interactions: _hold,
        child: SizedBox(
          width: 200,
          height: 200,
          child: Center(
            child: InputRegion(
              interactions: _press,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(MotionClock.debugReset);

  Future<void> holdFor(WidgetTester tester, double seconds) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_HeldButton)),
    );
    final frames = (seconds / 0.01).round();
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a hold that contends takes the touch from the button once it '
      'arms, and a release then recognizes it', (tester) async {
    final heard = <String>[];
    await tester.pumpWidget(_HeldButton(heard: heard));
    await holdFor(tester, 0.6);
    expect(heard, ['armed', 'start']);
  });

  testWidgets('a release before the hold arms taps the button', (
    tester,
  ) async {
    final heard = <String>[];
    await tester.pumpWidget(_HeldButton(heard: heard));
    await holdFor(tester, 0.3);
    expect(heard, ['tap', 'fail']);
  });

  testWidgets('a hold that does not contend loses the touch to the button '
      'at the down', (tester) async {
    final heard = <String>[];
    await tester.pumpWidget(_HeldButton(heard: heard, contends: false));
    await holdFor(tester, 1);
    expect(heard, ['fail', 'tap']);
  });
}
