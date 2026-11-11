import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'checks.dart';

/// The reviewed list of the (entry, check) pairs that fail today.
final File knownFile = File('test/conformance/known_failures.txt');

/// Whether `UPDATE_CONFORMANCE=1` asks to drop the lines that now pass.
bool get updateRequested => Platform.environment['UPDATE_CONFORMANCE'] == '1';

const _header = '''
# The (entry, check) pairs of the conformance suite that fail today, with
# what the check observed. Reviewed by hand: a new failure fails the suite,
# and so does a line whose pair now passes. The list only shrinks:
# UPDATE_CONFORMANCE=1 drops the lines that pass and never adds one.
# Format: <entry> <check>: <reason>
''';

/// The key of a pair in the list.
String pairKey(String entry, String check) => '$entry $check';

/// The listed pairs and their reasons.
Map<String, String> readKnown() {
  final known = <String, String>{};
  if (!knownFile.existsSync()) return known;
  for (final line in knownFile.readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final colon = line.indexOf(': ');
    final key = colon < 0 ? line.trim() : line.substring(0, colon);
    known[key] = colon < 0 ? '' : line.substring(colon + 2);
  }
  return known;
}

/// What this run observed: a pair's reason, or null when it passed.
final Map<String, String?> observed = {};

/// The entries whose leak test ran in this file.
final Set<String> leakSubjects = {};

/// Holds the run's results to the list, and rewrites it when asked.
void holdToKnown(Map<String, String?> results) {
  final known = readKnown();
  if (updateRequested) {
    final kept = <String, String>{};
    for (final MapEntry(:key, :value) in known.entries) {
      if (!results.containsKey(key)) {
        kept[key] = value;
      } else if (results[key] != null) {
        kept[key] = results[key]!;
      }
    }
    final keys = kept.keys.toList();
    keys.sort();
    final lines = [for (final key in keys) '$key: ${kept[key]}'];
    knownFile.writeAsStringSync('$_header${lines.join('\n')}\n');
  }
}

/// Fails for a pair whose result disagrees with the list.
void judge(String key, String? reason) {
  final listed = readKnown()[key];
  if (reason != null && listed == null) {
    fail(
      'a new failure; fix it, or add this line to known_failures.txt '
      'after review:\n$key: $reason',
    );
  }
  if (reason == null && listed != null && !updateRequested) {
    fail(
      'it passes now; remove this line from known_failures.txt '
      '(or run with UPDATE_CONFORMANCE=1):\n$key: $listed',
    );
  }
}

/// Holds the leaks collected for the file's leak tests to the list.
void reportLeaks(Leaks leaks) {
  if (leakSubjects.isEmpty) return;
  final byEntry = <String, Set<String>>{};
  for (final report in leaks.all) {
    final phase = report.phase ?? '';
    if (!phase.startsWith('$leakCheck ')) continue;
    final entry = phase.substring(leakCheck.length + 1);
    byEntry.putIfAbsent(entry, () => {}).add(report.type);
  }
  final results = <String, String?>{};
  for (final entry in leakSubjects) {
    final types = byEntry[entry]?.toList();
    types?.sort();
    results[pairKey(entry, leakCheck)] = types == null
        ? null
        : 'leaks ${types.join(', ')}';
  }
  observed.addAll(results);
  holdToKnown(observed);
  final problems = <String>[];
  for (final MapEntry(:key, :value) in results.entries) {
    try {
      judge(key, value);
    } on TestFailure catch (failure) {
      problems.add(failure.message ?? '$failure');
    }
  }
  if (problems.isNotEmpty) fail(problems.join('\n\n'));
}
