import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/listen.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/tracker.dart';

/// A value derived from motions, such as a card's shadow from its lift and
/// scale: what a renderer, a transition or a widget reads.
///
/// Every `MotionValue` and [MotionSelection] that [compute] reads through
/// `value`, `target` or `velocity` is followed automatically; a selection made
/// with `Motion.select` follows its motion instead and tracks no reads. While
/// it has listeners, a [MotionSelection] recomputes in the publish phase of
/// [clock], after the values it reads, and its listeners hear it at most
/// once per frame and only when the result differs (`equals`, `==` by
/// default): a derived boolean under a `ValueListenableBuilder` rebuilds
/// only when it flips. Render listeners ([addRenderListener]) also hear it
/// when the frame's resolve phase changes what it reads. Without listeners
/// it follows nothing and computes on every read, so it needs no dispose.
class MotionSelection<T> implements ValueListenable<T>, RenderListenable {
  /// Derives a value with [compute], published on [clock]
  /// ([MotionClock.instance] when null).
  MotionSelection(
    this.compute, {
    MotionClock? clock,
    this._equals,
  }) : clock = clock ?? MotionClock.instance,
       _source = null,
       _settled = null;

  MotionSelection._of(
    Listenable source,
    this.compute, {
    required this.clock,
    required this._settled,
    this._equals,
  }) : _source = source;

  /// Computes the value from the values it reads.
  final T Function() compute;

  /// The clock whose publish phase recomputes the value.
  @override
  final MotionClock clock;

  final bool Function(T a, T b)? _equals;
  final Listenable? _source;
  final bool Function()? _settled;
  final List<VoidCallback> _listeners = [];
  final List<VoidCallback> _renderListeners = [];
  final Set<Listenable> _inputs = {};
  bool _dirty = true;
  bool _hasValue = false;
  late T _value;
  final _Published<T> _toRender = _Published<T>();
  final _Published<T> _toWidgets = _Published<T>();
  late final _SelectionDerived<T> _derived = _SelectionDerived<T>(this);

  bool get _followed => _listeners.isNotEmpty || _renderListeners.isNotEmpty;

  /// Whether every motion part this selection follows is at rest now.
  bool get isSettled => _settled?.call() ?? _inputs.every(settledNow);

  bool _same(T a, T b) => _equals?.call(a, b) ?? a == b;

  @override
  T get value {
    ReadTracker.read(this);
    if (_dirty || !_followed) {
      _evaluate();
      // A reader between publishes may draw this value: the next publish
      // tells the listeners even if the inputs came back by then.
      if (_toRender.has && !_same(_toRender.value, _value)) _toRender.clear();
      if (_toWidgets.has && !_same(_toWidgets.value, _value)) {
        _toWidgets.clear();
      }
    }
    return _value;
  }

  void _evaluate() {
    final source = _source;
    if (source != null) {
      _value = ReadTracker.untracked(compute);
      _hasValue = true;
      _dirty = false;
      if (_followed && _inputs.isEmpty) {
        _inputs.add(source);
        source.addRenderListener(_onInput);
      }
      return;
    }
    final reads = <Listenable>{};
    _value = ReadTracker.track(reads, compute);
    _hasValue = true;
    _dirty = false;
    reads.remove(this);
    if (!_followed) return;
    for (final input in _inputs.difference(reads)) {
      input.removeRenderListener(_onInput);
    }
    for (final input in reads.difference(_inputs)) {
      input.addRenderListener(_onInput);
    }
    _inputs.clear();
    _inputs.addAll(reads);
  }

  void _onInput() {
    _dirty = true;
    clock.markDirty(_derived);
  }

  void _recompute({required bool widgets}) {
    if (!_followed) return;
    if (_dirty) _evaluate();
    _publish(_toRender, _renderListeners);
    if (widgets) _publish(_toWidgets, _listeners);
  }

  void _publish(_Published<T> published, List<VoidCallback> listeners) {
    if (published.has && _same(published.value, _value)) return;
    published.set(_value);
    notifyGuarded(listeners, 'while notifying a MotionSelection listener');
  }

  void _start() {
    _evaluate();
    _toRender.set(_value);
    _toWidgets.set(_value);
  }

  void _stopIfAlone() {
    if (_followed) return;
    for (final input in _inputs) {
      input.removeRenderListener(_onInput);
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

  @override
  void addRenderListener(VoidCallback listener) {
    final first = !_followed;
    _renderListeners.add(listener);
    if (first) _start();
  }

  @override
  void removeRenderListener(VoidCallback listener) {
    _renderListeners.remove(listener);
    _stopIfAlone();
  }

  @override
  String toString() =>
      'MotionSelection<$T>(${_hasValue ? _value : 'not computed'})';
}

final class _SelectionDerived<T> implements MotionDerived {
  _SelectionDerived(this._host);

  final MotionSelection<T> _host;

  @override
  bool get hasWidgetFollowers => _host._listeners.isNotEmpty;

  @override
  void recompute({required bool widgets}) => _host._recompute(widgets: widgets);
}

/// Creates a [MotionSelection] bound to a single [source] listenable without
/// read-tracking allocations, settled when [settled] says so.
@internal
MotionSelection<T> createMotionSelectionOf<T>(
  Listenable source,
  T Function() compute, {
  required MotionClock clock,
  required bool Function() settled,
  bool Function(T a, T b)? equals,
}) => MotionSelection<T>._of(
  source,
  compute,
  clock: clock,
  settled: settled,
  equals: equals,
);

class _Published<T> {
  bool has = false;
  late T value;

  void set(T next) {
    has = true;
    value = next;
  }

  void clear() => has = false;
}

/// Whether [input] rests now: a selection when what it follows rests, a
/// motion part a clock publishes when it rests at that clock's time with
/// nothing due, and anything else always.
@internal
bool settledNow(Listenable input) => switch (input) {
  final MotionSelection<Object?> selection => selection.isSettled,
  final MotionPart part && RenderListenable(:final clock) =>
    part.restsAt(clock.now) && part.nextDue == null,
  _ => true,
};
