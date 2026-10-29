import 'package:flutter/foundation.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/listen.dart';
import 'package:kinesis/src/tracker.dart';

/// A value derived from motion values, such as a glass frame from a lens
/// rect, its scale and its lift.
///
/// Every `MotionValue` and [MotionComputed] that [compute] reads through
/// `value`, `target` or `velocity` is followed automatically. While it has
/// listeners, a [MotionComputed] recomputes in the publish phase of
/// [clock], after the values it reads, and its listeners hear it at most
/// once per frame and only when the result differs (`equals`, `==` by
/// default): a derived boolean under a `ValueListenableBuilder` rebuilds
/// only when it flips. Render listeners ([addRenderListener]) also hear it
/// when the frame's resolve phase changes what it reads. Without listeners
/// it follows nothing and computes on every read, so it needs no dispose.
class MotionComputed<T> implements ValueListenable<T>, MotionDerived {
  /// Derives a value with [compute], published on [clock]
  /// ([MotionClock.instance] when null).
  MotionComputed(
    this.compute, {
    MotionClock? clock,
    this._equals,
  }) : clock = clock ?? MotionClock.instance;

  /// Computes the value from the values it reads.
  final T Function() compute;

  /// The clock whose publish phase recomputes the value.
  final MotionClock clock;

  final bool Function(T a, T b)? _equals;
  final List<VoidCallback> _listeners = [];
  final List<VoidCallback> _renderListeners = [];
  final Set<Listenable> _inputs = {};
  bool _dirty = true;
  bool _hasValue = false;
  late T _value;
  final _Published<T> _toRender = _Published<T>();
  final _Published<T> _toWidgets = _Published<T>();

  bool get _followed => _listeners.isNotEmpty || _renderListeners.isNotEmpty;

  @override
  bool get hasWidgetFollowers => _listeners.isNotEmpty;

  bool _same(T a, T b) => _equals?.call(a, b) ?? a == b;

  @override
  T get value {
    ReadTracker.read(this);
    if (_dirty || !_followed) _evaluate();
    return _value;
  }

  void _evaluate() {
    final reads = <Listenable>{};
    _value = ReadTracker.track(reads, compute);
    _hasValue = true;
    _dirty = false;
    reads.remove(this);
    if (!_followed) return;
    for (final input in _inputs.difference(reads)) {
      unlistenForRender(input, _onInput);
    }
    for (final input in reads.difference(_inputs)) {
      listenForRender(input, _onInput);
    }
    _inputs.clear();
    _inputs.addAll(reads);
  }

  void _onInput() {
    _dirty = true;
    clock.markDirty(this);
  }

  @override
  void recompute({required bool widgets}) {
    if (!_followed) return;
    if (_dirty || !_hasValue) _evaluate();
    _publish(_toRender, _renderListeners);
    if (widgets) _publish(_toWidgets, _listeners);
  }

  void _publish(_Published<T> published, List<VoidCallback> listeners) {
    if (published.has && _same(published.value, _value)) return;
    published.set(_value);
    for (final listener in List<VoidCallback>.of(listeners)) {
      guardMotion(listener, 'while notifying a MotionComputed listener');
    }
  }

  void _start() {
    _evaluate();
    _toRender.set(_value);
    _toWidgets.set(_value);
  }

  void _stopIfAlone() {
    if (_followed) return;
    for (final input in _inputs) {
      unlistenForRender(input, _onInput);
    }
    _inputs.clear();
    _dirty = true;
    _toRender.clear();
    _toWidgets.clear();
  }

  @override
  void addListener(VoidCallback listener) {
    final first = !_followed;
    _listeners.add(listener);
    if (first) _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _stopIfAlone();
  }

  /// Adds a listener of a render object that only marks paint or
  /// composited layers: it also hears the value when the frame's resolve
  /// phase changes what it reads, before paint.
  void addRenderListener(VoidCallback listener) {
    final first = !_followed;
    _renderListeners.add(listener);
    if (first) _start();
  }

  /// Removes a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener) {
    _renderListeners.remove(listener);
    _stopIfAlone();
  }

  @override
  String toString() =>
      'MotionComputed<$T>(${_hasValue ? _value : 'not computed'})';
}

final class _Published<T> {
  bool has = false;
  late T value;

  void set(T next) {
    has = true;
    value = next;
  }

  void clear() => has = false;
}
