import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/alert_motion.dart';
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

AlertMotion _at(AlertMotion motion, double t) {
  motion.advance(t);
  return motion;
}

void main() {
  for (final (source, dir, frame) in [
    ('the simulator', 'test/fixtures/ios27/alert', 1 / 60),
    ('an iPhone 16 Pro', 'test/fixtures/ios27-device/alert', 1 / 120),
  ]) {
    group('alert motion replays $source', () {
      final rows = _rows(dir, 'alert-present-dismiss.jsonl');
      final present = _event(rows, 'present');
      final dismiss = _event(rows, 'dismiss');
      final alert = [
        for (final r in rows)
          if (r['cls'] == '_UIAlertControllerPhoneTVMacView' &&
              _d(r, 't') > present)
            r,
      ];
      final dim = [
        for (final r in rows)
          if (r['cls'] == 'UIView' && _d(r, 't') > present) r,
      ];

      test('present: the scale and the dimming on one spring', () {
        List<double> scaleErrors(double start) {
          final motion = AlertMotion();
          motion.present(start);
          return [
            for (final r in alert)
              if (_d(r, 't') < dismiss)
                _at(motion, _d(r, 't') + frame).scale -
                    _d(r, 'w') / _d(r, 'bw'),
          ];
        }

        final (start, scaleRms) = _align(present, 0.15, scaleErrors);
        final motion = AlertMotion();
        motion.present(start);
        final dimErr = [
          for (final r in dim)
            if (_d(r, 't') < dismiss)
              _at(motion, _d(r, 't') + frame).dimming - _d(r, 'a'),
        ];
        expect(scaleRms, lessThan(0.0015));
        expect(_rms(dimErr), lessThan(0.012));
      });

      test(
        'dismiss: the dimming fades on the same spring, the scale stays',
        () {
          List<double> errors(double start) {
            final motion = AlertMotion();
            motion.present(present);
            motion.dismiss(start);
            return [
              for (final r in dim)
                if (_d(r, 't') > dismiss)
                  _at(motion, _d(r, 't') + frame).dimming - _d(r, 'a'),
            ];
          }

          final (start, rms) = _align(dismiss, 0.15, errors);
          expect(rms, lessThan(0.012));
          final motion = AlertMotion();
          motion.present(present);
          motion.dismiss(start);
          expect(_at(motion, start + 0.2).scale, closeTo(1, 1e-3));
        },
      );
    });
  }

  group('AlertMotion', () {
    test('presents from the measured scale, transparent', () {
      final motion = AlertMotion();
      motion.present(0);
      expect(motion.scale, AlertTuning.presentScale);
      expect(motion.opacity, 0);
      _at(motion, 1);
      expect(motion.scale, closeTo(1, 1e-3));
      expect(motion.opacity, closeTo(1, 1e-3));
    });

    test('a dismissal mid-present reverses with the velocity', () {
      final motion = AlertMotion();
      motion.present(0);
      final before = _at(motion, 0.05).opacity;
      motion.dismiss(0.05);
      expect(_at(motion, 0.06).opacity, greaterThan(before));
    });

    test('under Reduce Motion it presents at its size', () {
      final motion = AlertMotion();
      motion.reducedMotion = true;
      motion.present(0);
      expect(motion.scale, 1);
    });
  });
}
