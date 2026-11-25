// Run with `flutter test --enable-impeller --enable-flutter-gpu`; glass is fake
// otherwise and the test skips.
//
// What the gallery's screens take is reviewed like an API: a change to the plan
// shows up here as a diff of glass_budgets.txt. After reading the diff:
// flutter test --enable-impeller --enable-flutter-gpu
//   --dart-define=UPDATE_GLASS_BUDGETS=true test/glass_budget_host_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_test/liquid_glass_test.dart';

const _frame = Duration(milliseconds: 16);
const _update = bool.fromEnvironment('UPDATE_GLASS_BUDGETS');
const _budgets = 'test/glass_budgets.txt';

// A tab, how far it scrolls, and whether on an 11 inch iPad Pro in
// portrait, under the bar at the top, rather than on a phone.
const _scenes = [
  ('Controls', 0.0, false),
  ('Controls', 500.0, false),
  ('Controls', 1000.0, false),
  ('Photos', 100.0, false),
  ('Motion', 300.0, false),
  ('Controls', 500.0, true),
  ('Photos', 100.0, true),
];

// The frame after a scroll step: reads and targets of a scroll under chrome.
Future<String> _measure(
  WidgetTester tester,
  String tab,
  double scroll, {
  required bool iPad,
}) async {
  final scale = iPad ? 2.0 : 2.625;
  tester.view.physicalSize =
      (iPad ? const Size(1032, 1376) : const Size(411, 914)) * scale;
  tester.view.devicePixelRatio = scale;
  tester.view.padding = iPad
      ? const FakeViewPadding(top: 32 * 2, bottom: 20 * 2)
      : const FakeViewPadding(top: 62 * 2.625, bottom: 34 * 2.625);
  addTearDown(tester.view.reset);
  glassReadsCopies = true;
  addTearDown(() => glassReadsCopies = false);
  await tester.pumpWidget(
    const GalleryApp(home: StandHome()),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(_frame);
  }
  await tester.tap(find.text(tab));
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
  final scrollable = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere(
        (state) =>
            state.position.maxScrollExtent > 200 &&
            state.position.axis == Axis.vertical &&
            state.mounted,
      );
  for (var i = 0; i < 12; i++) {
    scrollable.position.jumpTo(scroll + i * 3);
    await tester.pump(_frame);
  }
  scrollable.position.jumpTo(scroll + 40);
  final report = await expectGlassBudget(tester);
  final name = '${iPad ? 'iPad ' : ''}$tab@${scroll.round()}'.padRight(18);
  return '$name reads ${report.reads.length}  '
      'targets ${report.targetCount}  images ${report.imageReads}  '
      'backdrop ${report.backdropReads}';
}

void main() {
  final lines = <String>[];

  for (final (tab, scroll, iPad) in _scenes) {
    testWidgets('budget of $tab at $scroll${iPad ? ' on an iPad' : ''}', (
      tester,
    ) async {
      lines.add(await _measure(tester, tab, scroll, iPad: iPad));
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 5; i++) {
        await tester.pump(_frame);
      }
      // Test fonts are wider than any real one and overflow a row.
      tester.takeException();
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }

  test('the screens take what was reviewed', () {
    final file = File(_budgets);
    final measured = '${lines.join('\n')}\n';
    if (_update) file.writeAsStringSync(measured);
    expect(measured, file.readAsStringSync());
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
