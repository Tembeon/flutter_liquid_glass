import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/app.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1100, 820),
}) async {
  MotionClock.debugReset();
  tester.view.physicalSize = size;
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
  testWidgets('navigates across all six Kinesis Studio screens', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('Picture-in-Picture'), findsNWidgets(2));
    expect(find.text('Toss Corner'), findsOneWidget);

    await tester.tap(find.text('Now Playing'));
    await _settle(tester);
    expect(find.text('Keyframe Motion Paths'), findsOneWidget);

    await tester.tap(find.text('Carousel & Feed'));
    await _settle(tester);
    expect(find.text('Featured Stories'), findsOneWidget);
    expect(find.text('Momentum Feed'), findsOneWidget);

    await tester.tap(find.text('Live Typography'));
    await _settle(tester);
    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.text('Fluid Headline & UIKit Caret'), findsOneWidget);

    await tester.tap(find.text('Tactile Symbols'));
    await _settle(tester);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Camera Zoom Dial & Haptics'), findsOneWidget);

    await tester.tap(find.text('Fluid Layout'));
    await _settle(tester);
    expect(find.text('Home Widget Board'), findsOneWidget);
    expect(find.text('Sliding Dock & Presentations'), findsOneWidget);
  });

  testWidgets('inspector drawer, dark mode, and interactive labs work', (
    tester,
  ) async {
    await _pumpApp(tester);

    // Toggle dark mode and inspector mode.
    await tester.tap(find.text('Light Mode'));
    await tester.pump();
    expect(find.text('Dark Mode'), findsOneWidget);

    await tester.tap(find.text('Toss Corner'));
    await _settle(tester);

    // Live Typography: update balance.
    await tester.tap(find.text('Live Typography'));
    await _settle(tester);
    await tester.tap(find.text(r'+$25'));
    await _settle(tester);
    expect(find.text(r'Deposit +$25.00'), findsOneWidget);

    // Tactile Symbols: tap control tiles directly.
    await tester.tap(find.text('Tactile Symbols'));
    await _settle(tester);
    await tester.tap(find.text('Alerts'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('AirDrop'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Stop Active'));
    await _settle(tester);
  });

  testWidgets('Fluid Layout opens share sheet and anchored quick menu', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Fluid Layout'));
    await _settle(tester);

    await tester.ensureVisible(find.text('Open Share Sheet'));
    await _settle(tester);
    await tester.tap(find.text('Open Share Sheet'));
    await _settle(tester);
    expect(find.text('Share Project'), findsOneWidget);

    await tester.tap(find.text('Send via AirDrop'));
    await _settle(tester);
    expect(find.text('Share Project'), findsNothing);
    expect(find.text('Sent via AirDrop'), findsOneWidget);

    await tester.tap(find.text('Quick Actions Menu'));
    await _settle(tester);
    expect(find.text('Duplicate'), findsOneWidget);

    await tester.tap(find.text('Duplicate'));
    await _settle(tester);
    expect(find.text('Picked: Duplicate'), findsOneWidget);
  });

  testWidgets('adapts cleanly to narrow mobile viewport', (tester) async {
    await _pumpApp(tester, size: const Size(390, 844));
    expect(find.text('Picture-in-Picture'), findsOneWidget);
    expect(find.text('Toss Corner'), findsOneWidget);
  });
}
