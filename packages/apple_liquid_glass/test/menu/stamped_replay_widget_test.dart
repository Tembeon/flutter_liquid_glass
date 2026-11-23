import 'dart:async';
import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

import '../support/fixtures.dart';

const _dir = 'test/fixtures/ios27-device/menu_api';

List<Map<String, Object?>> _rows(String name) => [
  for (final line in Fixtures.lines('$_dir/$name.jsonl'))
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

double _n(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

List<GlassMenuEntry> _sub(List<String> log) => [
  const GlassMenuItem(title: 'Copy', icon: Icon(IconData(1))),
  const GlassMenuItem(title: 'Share', icon: Icon(IconData(2))),
  GlassSubmenu(
    title: 'More',
    icon: const Icon(IconData(3)),
    children: [
      GlassMenuItem(
        title: 'Sub one',
        icon: const Icon(IconData(11)),
        onPressed: () => log.add('Sub one'),
      ),
      GlassMenuItem(
        title: 'Sub two',
        icon: const Icon(IconData(12)),
        onPressed: () => log.add('Sub two'),
      ),
      const GlassSubmenu(
        title: 'Deeper',
        icon: Icon(IconData(13)),
        children: [
          GlassMenuItem(title: 'Deep one'),
          GlassMenuItem(title: 'Deep two'),
        ],
      ),
    ],
  ),
  const GlassMenuItem(
    title: 'Delete',
    icon: Icon(IconData(4)),
    destructive: true,
  ),
];

Future<ManualMotionClock> _pumpAnchor(
  WidgetTester tester,
  List<GlassMenuEntry> entries,
) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final clock = ManualMotionClock();
  await tester.pumpWidget(
    MotionClockScope(
      clock: clock,
      child: WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Stack(
          children: [
            Positioned(
              left: 177,
              top: 126,
              width: 48,
              height: 48,
              child: GlassMenuAnchor(
                menuChildren: entries,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return clock;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a held finger opens the card after the dwell and fires a '
      'sub row, the touches at the device stamps', (tester) async {
    final log = <String>[];
    final clock = await _pumpAnchor(tester, _sub(log));
    double? fired;
    final rows = _rows('mm-sub-slide2');
    final t0 = _n(rows.first, 't');
    final evt = rows.firstWhere((Map<String, Object?> r) => r['k'] == 'evt');
    final lift = rows.lastWhere(
      (Map<String, Object?> r) => r['k'] == 'touch' && r['phase'] == 3,
    );
    double? opened;
    TestGesture? gesture;
    const step = 1 / 120;
    Future<void> runTo(double t) async {
      while (clock.now + step < t) {
        clock.advanceTo(clock.now + step);
        await tester.pump();
        if (opened == null && find.text('Sub one').evaluate().isNotEmpty) {
          opened = clock.now;
        }
      }
      clock.advanceTo(t);
    }

    for (final row in rows) {
      if (row['k'] != 'touch') continue;
      final t = _n(row, 't') - t0;
      await runTo(t);
      final at = Offset(_n(row, 'x'), _n(row, 'y'));
      switch (row['phase']) {
        case 0:
          gesture = await tester.startGesture(at);
        case 1:
          await gesture!.moveTo(at);
        case 3:
          await gesture!.up();
      }
      if (fired == null && log.isNotEmpty) fired = clock.now;
    }
    for (var i = 0; i < 24; i++) {
      clock.advanceTo(clock.now + step);
      await tester.pump();
      if (fired == null && log.isNotEmpty) fired = clock.now;
    }
    debugPrint('opened $opened fired $fired');
    expect(opened, isNotNull);
    expect((opened! - 6.021).abs(), lessThan(0.06));
    expect(log, ['Sub two']);
    expect(
      fired! - (_n(lift, 't') - t0),
      moreOrLessEquals(_n(evt, 't') - _n(lift, 't'), epsilon: 0.008),
    );
  });

  testWidgets('a loading row turns its spinner on the scope clock, so the '
      'binding schedules no frame for it', (tester) async {
    final clock = await _pumpAnchor(tester, [
      GlassMenuDeferred(() => Completer<List<GlassMenuEntry>>().future),
    ]);
    final gesture = await tester.startGesture(const Offset(201, 150));
    for (var t = 0.0; t < 1.2; t += 1 / 120) {
      clock.advanceTo(t);
      await tester.pump();
    }
    expect(find.text('Loading...'), findsOneWidget);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.up();
  });
}
