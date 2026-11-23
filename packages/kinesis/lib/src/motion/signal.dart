import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/listen.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/tracker.dart';

/// A value written from outside at explicit times (scroll pixels, a
/// keyboard inset): no physics, the latest write at or before a time.
///
/// Implements [ValueListenable] and tracks reads inside `MotionSelection`:
/// a write wakes the owning motion or publishes on [clock], so a large title
/// or a tab bar's minimize follows the scroll without a wrapper motion.
final class MotionSignal<T> extends MotionPart
    implements ValueListenable<T>, RenderListenable {
  /// Creates a signal holding [value] from the start, published on [clock]
  /// (the owning motion's clock, or [MotionClock.instance], when null).
  MotionSignal(T value, {MotionClock? clock})
    : _givenClock = clock,
      _writes = [(double.negativeInfinity, value)];

  final MotionClock? _givenClock;
  final List<(double, T)> _writes;
  _SignalPublisher? _publisher;

  /// The clock that publishes writes to listeners of this signal.
  @override
  MotionClock get clock => _givenClock ?? ownerClock;

  /// The latest value written.
  @override
  T get value {
    ReadTracker.read(this);
    return _writes.last.$2;
  }

  /// Sets the value to [value] from time [t], replacing every write stamped
  /// at or after [t].
  ///
  /// Writes the clock has passed are dropped but the one in force; a signal
  /// with no owner has no clock, so [t] stands for it.
  void write(double t, T value) {
    while (_writes.length > 1 && _writes.last.$1 >= t) {
      _writes.removeLast();
    }
    final now = owner?.now ?? t;
    while (_writes.length > 1 && _writes[1].$1 <= now) {
      _writes.removeAt(0);
    }
    _writes.add((t, value));
    changed();
    if (_publisher case final publisher? when publisher.hasListeners) {
      publisher.follow(clock);
    }
  }

  /// The latest value written at or before [t].
  T valueAt(double t) {
    for (var i = _writes.length - 1; i > 0; i--) {
      if (_writes[i].$1 <= t) return _writes[i].$2;
    }
    return _writes.first.$2;
  }

  @override
  void addListener(VoidCallback listener) =>
      (_publisher ??= _SignalPublisher()).addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _publisher?.removeListener(listener);

  @override
  void addRenderListener(VoidCallback listener) =>
      (_publisher ??= _SignalPublisher()).addRenderListener(listener);

  @override
  void removeRenderListener(VoidCallback listener) =>
      _publisher?.removeRenderListener(listener);

  @override
  double? restTime([double? tolerance]) => double.negativeInfinity;

  @override
  bool restsAt(double t, [double? tolerance]) => true;

  @override
  void restFrom(double t) {}

  @override
  double? dueAfter(double t) => null;

  @override
  String toString() => 'MotionSignal<$T>(${_writes.last.$2})';
}

final class _SignalPublisher extends ClockPublisher {
  _SignalPublisher() : super('while notifying a MotionSignal listener');

  @override
  bool stepTo(double time) => false;

  @override
  double? get wakeTime => null;
}
