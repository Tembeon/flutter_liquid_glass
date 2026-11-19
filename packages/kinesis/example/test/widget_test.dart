import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

  testWidgets('a quick switch back keeps one page once it settles', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Now Playing'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Picture-in-Picture').first);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);
    await _settle(tester);
    expect(find.text('Toss Corner'), findsOneWidget);
    expect(find.text('Keyframe Motion Paths'), findsNothing);
  });

  testWidgets('custom transitions and the pose lab answer taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpApp(tester);

    await tester.tap(find.text('Live Typography'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Burst'));
    await _settle(tester);
    await tester.tap(find.text('+150'));
    await _settle(tester);
    expect(find.bySemanticsLabel('270'), findsOneWidget);
    expect(find.text('Champion'), findsOneWidget);
    for (final look in ['Roll', 'Pop', 'Fade', 'Blur', 'Drop', 'Slide']) {
      await tester.tap(find.text(look).last);
      await tester.pump();
    }
    await tester.tap(find.text('Burst'));
    await _settle(tester);
    await _settle(tester);
    expect(find.bySemanticsLabel('395'), findsOneWidget);

    await tester.tap(find.text('Tactile Symbols'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Ghost'));
    await _settle(tester);
    await tester.tap(find.text('Ghost'));
    await _settle(tester);
    final alphas = [
      for (final layer in tester.layers.whereType<MotionTransitionLayer>())
        layer.alpha,
    ];
    expect(alphas, contains(89));
    await tester.tap(find.text('Disappear'));
    await _settle(tester);
    expect(find.text('Appear'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the input lab holds, opens its menu and adjusts', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpApp(tester);
    await tester.ensureVisible(find.text('Hold'));
    await _settle(tester);

    final hold = await tester.startGesture(tester.getCenter(find.text('Hold')));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Pinned'), findsNothing);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await hold.up();
    await _settle(tester);
    expect(find.text('Pinned'), findsOneWidget);

    await tester.tap(find.text('Menu'), buttons: kSecondaryButton);
    await _settle(tester);
    await tester.tap(find.text('Make Favorite'));
    await _settle(tester);
    expect(find.text('Make Favorite'), findsOneWidget);
    expect(find.text('Copy Style'), findsNothing);

    await tester.tap(find.text('Adjust'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.bySemanticsLabel('6'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _settle(tester);
    expect(find.bySemanticsLabel('10'), findsOneWidget);
    await tester.drag(find.text('Adjust'), const Offset(-60, 0));
    await _settle(tester);
    expect(find.bySemanticsLabel('6'), findsOneWidget);
    semantics.dispose();
  });
}
