import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/part.dart';

/// A per-frame filter on frames of its own: UIKit's display-link loops,
/// measured at a fixed [rate] (the lens's stretch at 120 Hz), stepped at
/// the same times whatever the host renders.
///
/// Frames are numbered from zero at `k / rate` seconds. The owning motion
/// runs the loop as it advances, every frame at its own time between its
/// reactions, so a replay at any sampling steps the same frames. A loop
/// sleeps once [step] answers false and runs again from [wake].
///
/// ```dart
/// final class StretchLoop extends MotionLoop {
///   StretchLoop() : super(rate: 120);
///
///   @override
///   bool step(double t) {
///     ...
///     return moving;
///   }
/// }
/// ```
abstract class MotionLoop extends MotionPart {
  /// Creates a loop that steps [rate] times per second of motion time.
  MotionLoop({required this.rate}) : assert(rate > 0, 'a loop ticks forward');

  /// The frames per second of motion time.
  final double rate;

  /// The length of one frame, in seconds.
  double get frame => 1 / rate;

  /// The most frames one advance steps through; earlier frames of a
  /// longer gap are skipped.
  static const int maxFrames = 600;

  int _last = 0;
  bool _moving = false;
  double _restAt = double.negativeInfinity;

  /// Whether the loop steps as its motion advances.
  bool get isMoving => _moving;

  /// Steps the loop from the first frame after [t] on, if it slept.
  void wake(double t) {
    if (_moving) return;
    _last = _index(t);
    _moving = true;
    owner?.partChanged();
  }

  /// One frame at time [t]; answers whether the loop needs another.
  @protected
  bool step(double t);

  /// Steps every frame after the last one up to [t], or up to just before
  /// [t] when [before], in order.
  @internal
  void run(double t, {bool before = false}) {
    if (!_moving) return;
    final end = before ? (t * rate - 1e-6).ceil() - 1 : _index(t);
    var k = _last + 1;
    if (end - k >= maxFrames) k = end - maxFrames + 1;
    for (; k <= end; k++) {
      final s = k / rate;
      if (!step(s)) {
        _last = k;
        _moving = false;
        _restAt = s;
        return;
      }
    }
    if (end > _last) _last = end;
  }

  int _index(double t) => (t * rate + 1e-6).floor();

  /// The frame the loop last slept at, or null while it steps.
  @override
  double? restTime([double? tolerance]) => _moving ? null : _restAt;

  @override
  bool restsAt(double t, [double? tolerance]) => !_moving;

  /// Declares the loop at rest from [t]. A loop with something to put in
  /// place once it rests (a filter to re-prime, a deformation to snap off)
  /// does it here, and calls super.
  @override
  @mustCallSuper
  void restFrom(double t) {}

  @override
  double? get nextDue => null;
}
