import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/app.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  MotionClock.debugReset();
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const KinesisStudioApp());
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('navigates cleanly across all six Kinesis Studio tabs', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('Magnetic Dock Arena'), findsOneWidget);
    expect(find.text('Spring & TimingCurve Tuner'), findsOneWidget);

    await tester.tap(find.text('Animator'));
    await _settle(tester);
    expect(find.text('MotionAnimator Scrub Deck'), findsOneWidget);
    expect(find.text('MotionKeyframes Choreography'), findsOneWidget);

    await tester.tap(find.text('Scroll'));
    await _settle(tester);
    expect(find.text('iOS Scroll Deceleration & Edge Bounce'), findsOneWidget);
    expect(find.text('PagingPhysics Card Deck'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await _settle(tester);
    expect(find.text('MotionNumericText Rolling Digits'), findsOneWidget);
    expect(find.text('Zero-Rebuild MotionText'), findsOneWidget);

    await tester.tap(find.text('Symbols'));
    await _settle(tester);
    expect(find.text('SymbolEffectMotion & MotionSymbol'), findsOneWidget);
    expect(
      find.text('MotionHaptic & 40 ms Selection Throttle'),
      findsOneWidget,
    );

    await tester.tap(find.text('Layout'));
    await _settle(tester);
    expect(find.text('MotionLayout Spring Grid'), findsOneWidget);
    expect(
      find.text('Presentations: Route Sheet & Source Portal'),
      findsOneWidget,
    );
  });

  testWidgets('interactive labs respond to taps and global toggles', (
    tester,
  ) async {
    await _pumpApp(tester);

    // Toggle dark mode and reduce motion.
    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Reduce Motion'));
    await tester.pump();

    // Retarget spring mid-flight without throwing.
    await tester.ensureVisible(find.text('Retarget Mid-Flight'));
    await _settle(tester);
    await tester.tap(find.text('Retarget Mid-Flight'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Retarget Mid-Flight'));
    await _settle(tester);

    // Animator tab: scrub and play.
    await tester.tap(find.text('Animator'));
    await _settle(tester);
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Pause').first);
    await tester.pump();

    // Text tab: increment rolling counter.
    await tester.tap(find.text('Text'));
    await _settle(tester);
    await tester.tap(find.text('+1'));
    await _settle(tester);
    expect(find.text('3'), findsWidgets);

    // Symbols tab: trigger discrete bounce and indefinite pulse.
    await tester.tap(find.text('Symbols'));
    await _settle(tester);
    await tester.tap(find.text('Bounce Up'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Pulse'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Remove All'));
    await _settle(tester);
  });

  testWidgets('Layout tab opens and dismisses PresentationRoute sheet', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Layout'));
    await _settle(tester);

    await tester.ensureVisible(find.text('Open Draggable Sheet'));
    await _settle(tester);
    await tester.tap(find.text('Open Draggable Sheet'));
    await _settle(tester);
    expect(find.text('PresentationRoute Sheet'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await _settle(tester);
    expect(find.text('PresentationRoute Sheet'), findsNothing);
    expect(find.text('Last sheet result: confirmed'), findsOneWidget);

    // Open and close source-anchored PresentationPortal popover.
    await tester.tap(find.text('Open Anchored Popover'));
    await _settle(tester);
    expect(find.text('Source-Anchored Portal'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(find.text('Source-Anchored Portal'), findsNothing);
  });
}
