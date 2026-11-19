import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/tracker.dart';

/// A value written from outside at explicit times (scroll pixels, a
/// keyboard inset): no physics, the latest write at or before a time.
///
/// Implements [ValueListenable] and tracks reads inside `MotionSelection`:
/// a write wakes the owning motion or publishes on [clock], so a large title
/// or a tab bar's minimize follows the scroll without a wrapper motion.
final class MotionSignal<T> extends MotionPart implements ValueListenable<T> {
  /// Creates a signal holding [value] from the start, published on [clock]
  /// (the owning motion's clock, or [MotionClock.instance], when null).
  MotionSignal(T value, {MotionClock? clock})
    : _givenClock = clock,
      _writes = [(double.negativeInfinity, value)];

  final MotionClock? _givenClock;
  final List<(double, T)> _writes;
  final List<VoidCallback> _listeners = [];
  final List<VoidCallback> _renderListeners = [];
  late final _SignalFollower<T> _follower = _SignalFollower<T>(this);
  late final ClockFollowing _following = ClockFollowing(_follower);

  /// The clock that publishes writes to listeners of this signal.
  MotionClock get clock => _givenClock ?? owner?.clock ?? MotionClock.instance;

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
    if (_listeners.isNotEmpty || _renderListeners.isNotEmpty) {
      _following.follow(clock);
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
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _unfollowIfAlone();
  }

  /// Adds a listener of a render object that hears writes in the frame's
  /// resolve phase as well as in publish.
  void addRenderListener(VoidCallback listener) =>
      _renderListeners.add(listener);

  /// Removes a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener) {
    _renderListeners.remove(listener);
    _unfollowIfAlone();
  }

  void _unfollowIfAlone() {
    if (_listeners.isEmpty && _renderListeners.isEmpty) {
      _following.unfollow();
    }
  }

  void _publish({required bool widgets}) {
    _notify(_renderListeners);
    if (widgets) _notify(_listeners);
  }

  static void _notify(List<VoidCallback> listeners) {
    if (listeners.isEmpty) return;
    for (final listener in List<VoidCallback>.of(listeners)) {
      guardMotion(listener, 'while notifying a MotionSignal listener');
    }
  }

  @override
  double? restTime([double? tolerance]) => double.negativeInfinity;

  @override
  bool restsAt(double t, [double? tolerance]) => true;

  @override
  void restFrom(double t) {}

  @override
  double? get nextDue => null;

  @override
  String toString() => 'MotionSignal<$T>(${_writes.last.$2})';
}

final class _SignalFollower<T> implements MotionFollowed {
  _SignalFollower(this.signal);

  final MotionSignal<T> signal;

  @override
  bool stepTo(double time) => false;

  @override
  double? get wakeTime => null;

  @override
  bool get hasWidgetFollowers => signal._listeners.isNotEmpty;

  @override
  void publish({required bool widgets}) => signal._publish(widgets: widgets);
}
