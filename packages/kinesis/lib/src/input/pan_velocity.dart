import 'package:flutter/gestures.dart';

/// The velocity a touch releases at, as UIKit's pan recognizer reports it:
/// the speed of its last moves however long the finger then stayed still.
///
/// It fits positions as Flutter's [VelocityTracker] does, a least-squares
/// quadratic over the newest 20 within 100 ms, broken at a 40 ms gap, so a
/// release in motion reads what Flutter's drags read. Only a lift after a
/// longer stop differs: Flutter's tracker reads zero, this one the speed of
/// the moves before the stop.
///
/// UIKit: `UIPanGestureRecognizer.velocity(in:)`.
final class PanVelocityTracker {
  static const int _historySize = 20;
  static const double _horizon = 0.1;
  static const double _stopped = 0.04;
  static const int _minSampleSize = 3;

  final List<(double, Offset)> _samples = [];

  /// Adds the touch's [position] at [time], in seconds: its down and each
  /// move.
  void addPosition(double time, Offset position) {
    if (_samples.length == _historySize) _samples.removeAt(0);
    _samples.add((time, position));
  }

  /// The velocity, in logical pixels per second, of a touch that lifts at
  /// [position] at [time], in seconds. The lift joins the fit when it
  /// follows the last move within 40 ms; after a longer stop the fit ends
  /// at the last move. Zero when fewer than three positions moved
  /// together.
  Offset velocityAtLift(double time, Offset position) => heldStillAt(time)
      ? _fit(_samples)
      : _fit([..._samples, (time, position)]);

  /// Whether the touch stayed still for longer than 40 ms before [time], in
  /// seconds, as a finger that stops before it lifts does.
  bool heldStillAt(double time) =>
      _samples.isNotEmpty && _apart(_samples.last.$1, time);

  static bool _apart(double from, double to) => (to - from).abs() > _stopped;

  static Offset _fit(List<(double, Offset)> samples) {
    final (newest, _) = samples.last;
    final time = <double>[];
    final x = <double>[];
    final y = <double>[];
    var previous = newest;
    for (final (at, position) in samples.reversed.take(_historySize)) {
      final age = newest - at;
      if (age > _horizon || _apart(at, previous)) break;
      previous = at;
      time.add(-age * 1000);
      x.add(position.dx);
      y.add(position.dy);
    }
    if (time.length < _minSampleSize) return Offset.zero;
    final weights = List<double>.filled(time.length, 1);
    final xFit = LeastSquaresSolver(time, x, weights).solve(2);
    final yFit = LeastSquaresSolver(time, y, weights).solve(2);
    if (xFit == null || yFit == null) return Offset.zero;
    return Offset(xFit.coefficients[1] * 1000, yFit.coefficients[1] * 1000);
  }
}
