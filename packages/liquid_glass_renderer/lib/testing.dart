/// Holding a screen to the glass work it was reviewed at, in widget tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';

/// Pumps a frame and checks what its glass took against matchers (an int or
/// a [Matcher]); what is left out is not checked.
///
/// ```dart
/// await expectGlassBudget(tester, reads: lessThanOrEqualTo(4), liveReads: 0);
/// ```
Future<GlassFrameReport> expectGlassBudget(
  WidgetTester tester, {
  Object? reads,
  Object? liveReads,
  Object? issuedTargets,
  Object? filtersBuilt,
  Object? picturesRecorded,
  Object? imagesDrawn,
}) async {
  GlassFrameReport? seen;
  void note(GlassFrameReport report) => seen = report;
  GlassFrameReport.addListener(note);
  try {
    // A test only draws a frame something asked for.
    tester.binding.scheduleFrame();
    await tester.pump();
  } finally {
    GlassFrameReport.removeListener(note);
  }
  final report = seen;
  if (report == null) fail('The frame had no glass.');
  void check(int actual, Object? matcher, String what) {
    if (matcher != null) expect(actual, matcher, reason: '$what in\n$report');
  }

  check(report.reads.length, reads, 'reads');
  check(report.liveReads, liveReads, 'live reads');
  check(report.issuedTargets, issuedTargets, 'targets');
  check(report.filtersBuilt, filtersBuilt, 'filters');
  check(report.picturesRecorded, picturesRecorded, 'pictures');
  check(report.imagesDrawn, imagesDrawn, 'images');
  return report;
}
