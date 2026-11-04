import 'package:kinesis/src/motion/part.dart';

/// A value written from outside at explicit times (scroll pixels, a
/// keyboard inset): no physics, the latest write at or before a time.
///
/// A write wakes the root, so its selections recompute: a large title or a
/// tab bar's minimize follows the scroll without a listener of its own.
final class MotionSignal<T> extends MotionPart {
  /// Creates a signal holding [value] from the start.
  MotionSignal(T value) : _writes = [(double.negativeInfinity, value)];

  final List<(double, T)> _writes;

  /// The latest value written.
  T get value => _writes.last.$2;

  /// Sets the value to [value] from time [t], replacing every write stamped
  /// at or after [t].
  void write(double t, T value) {
    while (_writes.length > 1 && _writes.last.$1 >= t) {
      _writes.removeLast();
    }
    final now = owner?.now;
    if (now != null) {
      while (_writes.length > 1 && _writes[1].$1 <= now) {
        _writes.removeAt(0);
      }
    }
    _writes.add((t, value));
    owner?.partChanged();
  }

  /// The latest value written at or before [t].
  T valueAt(double t) {
    for (var i = _writes.length - 1; i > 0; i--) {
      if (_writes[i].$1 <= t) return _writes[i].$2;
    }
    return _writes.first.$2;
  }

  @override
  double? restTime([double? tolerance]) => double.negativeInfinity;

  @override
  bool restsAt(double t, [double? tolerance]) => true;

  @override
  void restFrom(double t) {}

  @override
  double? get nextDue => null;
}
