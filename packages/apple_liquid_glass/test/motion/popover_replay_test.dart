import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/popover_motion.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _rows(String dir, String file) => [
  for (final line in File('$dir/$file').readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _event(List<Map<String, Object?>> rows, String name) => _d(
  rows.firstWhere((r) => r['k'] == 'evt' && (r['e'] == name || r['a'] == name)),
  't',
);

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / math.max(1, e.length));

/// Aligns the start of an animation to the recording: UIKit starts it a
/// frame or more after its call. Returns the best start within [maxLag]
/// of [call] and the rms error there.
(double, double) _align(
  double call,
  double maxLag,
  List<double> Function(double start) errors,
) {
  var best = call;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= maxLag; lag += 0.001) {
    final e = _rms(errors(call + lag));
    if (e < bestErr) {
      bestErr = e;
      best = call + lag;
    }
  }
  return (best, bestErr);
}

PopoverMotion _at(PopoverMotion motion, double t) {
  motion.advance(t);
  return motion;
}

void main() {
  const simulator = 'test/fixtures/ios27/alert';
  const device = 'test/fixtures/ios27-device/alert';

  group('popover motion replays', () {
    for (final (source, dir, frame, size) in [
      ('the simulator', simulator, 1 / 60, const Size(440, 956)),
      ('an iPhone 16 Pro', device, 1 / 120, const Size(402, 874)),
    ]) {
      test('present and dismiss about the arrow tip on $source', () {
        final rows = _rows(dir, 'actionsheet-present-dismiss.jsonl');
        final dismiss = _event(rows, 'dismiss');
        final popover = [
          for (final r in rows)
            if (r['cls'] == '_UIPopoverView') r,
        ];
        final first = popover.firstWhere((r) => _d(r, 'sx') < 1);
        final firstT = _d(first, 't');
        List<double> presentErrors(double start) {
          final motion = PopoverMotion();
          motion.present(start);
          return [
            for (final r in popover)
              if (_d(r, 't') >= firstT && _d(r, 't') < dismiss)
                _at(motion, _d(r, 't') + frame).scale - _d(r, 'sx'),
          ];
        }

        final (start, rms) = _align(firstT - 0.05, 0.1, presentErrors);
        expect(rms, lessThan(0.007));
        List<double> dismissErrors(double end) {
          final motion = PopoverMotion();
          motion.present(start);
          motion.dismiss(end);
          return [
            for (final r in popover)
              if (_d(r, 't') > dismiss + 0.01)
                _at(motion, _d(r, 't') + frame).scale - _d(r, 'sx'),
          ];
        }

        final (end, dismissRms) = _align(dismiss, 0.1, dismissErrors);
        expect(dismissRms, lessThan(0.006));
        final placement = placePopover(
          size: const Size(240, 208.33),
          source: Rect.fromLTWH(size.width / 2 - 60, 576, 120, 48),
          screen: size,
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(placement.arrowDirection, PopoverArrowDirection.down);
        final motion = PopoverMotion();
        motion.present(start);
        final yErrors = [
          for (final r in popover)
            if (_d(r, 't') >= firstT && _d(r, 't') < dismiss)
              () {
                final s = _at(motion, _d(r, 't') + frame).scale;
                final full = placement.bounds;
                final anchor = placement.anchor;
                return anchor.dy +
                    s * (full.center.dy - anchor.dy) -
                    _d(r, 'y');
              }(),
        ];
        expect(_rms(yErrors), lessThan(1.5));
        final shown = PopoverMotion();
        shown.present(start);
        final leaving = PopoverMotion();
        leaving.present(start);
        leaving.dismiss(end);
        final aErrors = [
          for (final r in popover)
            if (_d(r, 't') >= firstT)
              _at(
                    _d(r, 't') + frame < end ? shown : leaving,
                    _d(r, 't') + frame,
                  ).progress -
                  _d(r, 'a'),
        ];
        expect(_rms(aErrors), lessThan(0.01));
      });
    }

    for (final (source, dir, file, frame) in [
      ('the simulator', simulator, 'actionsheet-tap-out.jsonl', 1 / 60),
      ('an iPhone 16 Pro', device, 'ash-tap-out.jsonl', 0.0),
    ]) {
      test('a tap outside dismisses on the dismiss spring on $source', () {
        final rows = _rows(dir, file);
        final up = _d(rows.lastWhere((r) => r['k'] == 'touch'), 't');
        final popover = [
          for (final r in rows)
            if (r['cls'] == '_UIPopoverView' && _d(r, 't') > up) r,
        ];
        List<double> errors(double start) {
          final motion = PopoverMotion();
          motion.present(start - 5);
          motion.dismiss(start);
          return [
            for (final r in popover)
              _at(motion, _d(r, 't') + frame).scale - _d(r, 'sx'),
          ];
        }

        final (start, rms) = _align(up, 0.08, errors);
        expect(rms, lessThan(0.006));
        expect(start - up, lessThan(0.06));
      });
    }

    test('placement matches UIKit for every captured source', () {
      final data = (jsonDecode(
        File('$simulator/placements.json').readAsStringSync(),
      ) as Map).cast<String, Object?>();
      final cases = (data['cases']! as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThanOrEqualTo(15));
      for (final c in cases) {
        final s = (c['source']! as List).cast<num>();
        final m = (c['content']! as List).cast<num>();
        final placement = placePopover(
          size: Size(m[2].toDouble(), m[3].toDouble()),
          source: Rect.fromLTWH(
            s[0].toDouble(),
            s[1].toDouble(),
            s[2].toDouble(),
            s[3].toDouble(),
          ),
          screen: const Size(440, 956),
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(
          placement.content.left,
          closeTo(m[0].toDouble(), 0.5),
          reason: '${c['name']}',
        );
        expect(
          placement.content.top,
          closeTo(m[1].toDouble(), 0.5),
          reason: '${c['name']}',
        );
      }
    });

    test('Reduce Motion keeps the size and only fades', () {
      final motion = PopoverMotion();
      motion.reducedMotion = true;
      motion.present(0);
      _at(motion, 0.05);
      expect(motion.scale, 1);
      expect(motion.opacity, inExclusiveRange(0, 1));
    });
  });
}
