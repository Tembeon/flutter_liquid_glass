import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/converter.dart';
import 'package:kinesis/src/motion/listen.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/tracker.dart';
import 'package:kinesis/src/motion/transaction.dart';

/// A value that moves to its target on a [Spring] or [TimingCurve]: what is on
/// screen, where it is heading and how fast it goes.
///
/// UIKit: a view property inside `UIView.animate`, with its model and
/// presentation values. SwiftUI: an animatable property.
///
/// [target] is the model: setting it inside `withAnimation` or `withSpring`
/// sends the value there on the transaction's animation, and setting it
/// anywhere else makes it jump. [value] is the presentation, what is drawn
/// now. A new target mid-flight continues from the current value and velocity,
/// so an interrupted motion never jumps in position, nor in speed unless its
/// spring gives a retarget [Spring.impulse]. Additive [TimingCurve]s sum on
/// top of running curves just as Core Animation's `isAdditive` animations do.
///
/// Every operation also has a form with an explicit time in seconds
/// ([retarget], [animate], [snap], [setVelocity], [valueAt], ...): a motion
/// built from those is a pure function of its inputs and replays recorded
/// input exactly. A change never reaches back before the previous one: a time
/// earlier than the last change takes effect at that change's time.
///
/// While it has listeners and moves or waits for a delayed change, [clock]
/// steps it every frame and its listeners hear it in the publish phase;
/// once a frame passes its [restTime] it is declared at rest from that
/// time ([restFrom]), reads answer its target and they hear it once more.
/// The declaration is not a change: a command stamped before it starts from
/// the course at its own time. A change made in the frame's resolve phase
/// reaches render listeners ([addRenderListener]) in that phase and the
/// others in the next publish. A value without listeners is not stepped by
/// the clock at all; its owner reads it at the times it needs.
///
/// Every component of the value moves on the same animation ([converter]).
class MotionValue<T> extends MotionPart
    implements ValueListenable<T>, RenderListenable {
  /// Creates a value resting at [value].
  ///
  /// [converter] maps the value to the doubles the animation moves; the
  /// built-in one for doubles, offsets, sizes, rects, radii, colors,
  /// edge insets, border radii, alignments and text styles is used when it is
  /// null. [restDistance] is how far a component may still swing before it
  /// counts as at rest; when it is null, the converter's rest for the
  /// value's swing. [clock] supplies the time of the ambient [target],
  /// [value] and [velocity]. [spring] is the default spring a [retarget] that
  /// names none uses until a change names another.
  factory MotionValue(
    T value, {
    MotionConverter<T>? converter,
    double? restDistance,
    MotionClock? clock,
    Spring spring = Spring.smooth,
  }) {
    final resolved = converter ?? MotionConverter.of<T>();
    return MotionValue._(value, resolved, restDistance, clock, spring);
  }

  MotionValue._(
    T value,
    this.converter,
    this._givenRest,
    this._givenClock,
    this._spring,
  ) : _n = converter.dimensions,
      _y0 = Float64List(converter.dimensions),
      _v0 = Float64List(converter.dimensions),
      _target = Float64List(converter.dimensions),
      _memoY = Float64List(converter.dimensions),
      _memoV = Float64List(converter.dimensions),
      _simulations = List<SpringSimulation?>.filled(
        converter.dimensions,
        null,
      ) {
    converter.write(value, _y0);
    _target.setAll(0, _y0);
  }

  /// Maps the value to the components the animation moves.
  final MotionConverter<T> converter;

  final double? _givenRest;

  /// How far a component may still swing before it counts as at rest: the
  /// rest given at construction, else the converter's for the largest swing
  /// since the value last rested ([MotionConverter.restFor]). The swing is
  /// kept across retargets, so a value aimed again every frame rests when
  /// its first move would.
  double get restDistance => _givenRest ?? converter.restFor(_swing);

  final MotionClock? _givenClock;

  /// The clock of the ambient [target], [value] and [velocity], which also
  /// steps the value and publishes it to its listeners: the clock given at
  /// construction, else the owning motion's clock, else [MotionClock.instance].
  @override
  MotionClock get clock => _givenClock ?? owner?.clock ?? MotionClock.instance;

  final int _n;
  final Float64List _y0;
  final Float64List _v0;
  final Float64List _target;
  final Float64List _memoY;
  final Float64List _memoV;
  final List<SpringSimulation?> _simulations;
  _ValuePublisher<T>? _publisher;

  Spring _spring;
  bool _tracking = false;
  bool _atRest = true;
  double? _wakeTime;
  double _origin = 0;
  bool _moved = false;
  double _memoT = double.nan;
  double? _restedAt;
  double _swing = 0;
  double _restMemoTolerance = double.nan;
  double _restMemo = 0;

  double? _pendingDue;
  Float64List? _pendingTarget;
  MotionAnimation? _pendingAnimation;
  bool _pendingTracking = false;

  List<_CurveSegment>? _curves;

  /// The spring the value moves on, which a [retarget] that names none
  /// reuses; a delayed change switches to its spring when it starts. A
  /// tracking change moves the value on its [Spring.trackingSpring].
  Spring get spring => _spring;

  Spring get _motion => _tracking ? _spring.trackingSpring : _spring;

  /// Where the value is heading: the model. A delayed change reads its new
  /// target at once.
  T get target {
    ReadTracker.read(this);
    return converter.read(_pendingTarget ?? _target);
  }

  /// Sends the value to [next] at the clock's time, on the animation of the
  /// enclosing `withAnimation` or `withSpring`, or makes it jump there outside
  /// one. Writing the target it already has changes nothing, not even the
  /// animation.
  set target(T next) {
    final components = _components(next);
    if (_same(components, _pendingTarget ?? _target)) return;
    final t = clock.now;
    final transaction = currentMotionTransaction;
    if (transaction == null ||
        (transaction.animation.isImmediate && transaction.delay <= 0)) {
      _clearPending();
      _snapAt(t, components);
      _follow();
      return;
    }
    final resolved = transaction.animation.resolve(
      reduceMotion: (owner?.traits ?? MotionTraits.platform()).reduceMotion,
    );
    _dispatchAnimation(
      t,
      components,
      resolved,
      tracking: transaction.tracking,
      delay: transaction.delay,
    );
  }

  /// What is on screen at the clock's time: the presentation.
  @override
  T get value {
    ReadTracker.read(this);
    return valueAt(clock.now);
  }

  /// The velocity at the clock's time, per second.
  T get velocity {
    ReadTracker.read(this);
    return velocityAt(clock.now);
  }

  /// Gives the value [next] as its velocity at the clock's time, keeping
  /// its position and target: a finger's speed handed to the spring.
  set velocity(T next) => setVelocity(clock.now, next);

  bool get _needsSteps {
    assert(_curves == null || !_atRest, 'curves rest only once they end');
    return !_atRest || _pendingDue != null;
  }

  @override
  void addListener(VoidCallback listener) {
    final publisher = _publisher ??= _ValuePublisher<T>(this);
    publisher.addListener(listener);
    if (_needsSteps) publisher.follow(clock);
  }

  @override
  void removeListener(VoidCallback listener) =>
      _publisher?.removeListener(listener);

  @override
  void addRenderListener(VoidCallback listener) {
    final publisher = _publisher ??= _ValuePublisher<T>(this);
    publisher.addRenderListener(listener);
    if (_needsSteps) publisher.follow(clock);
  }

  @override
  void removeRenderListener(VoidCallback listener) =>
      _publisher?.removeRenderListener(listener);

  void _follow() {
    changed();
    _wakeTime = null;
    if (_publisher case final publisher? when publisher.hasListeners) {
      publisher.follow(clock);
    }
  }

  void _shift(T from, T to) {
    final a = _components(from);
    final b = _components(to);
    for (var i = 0; i < _n; i++) {
      final delta = b[i] - a[i];
      _y0[i] += delta;
      _target[i] += delta;
      final pending = _pendingTarget;
      if (pending != null) pending[i] += delta;
    }
    _changed();
    _follow();
  }

  bool _stepTo(double time) {
    _state(time);
    final pending = _pendingDue;
    if (pending != null) {
      _wakeTime = restsAt(time) ? pending : null;
      return true;
    }
    if (_curves case final curves?) {
      final rest = restTime();
      if (rest == null || rest > time) {
        _wakeTime = restsAt(time)
            ? _earliestCurveStartAfter(curves, time)
            : null;
        return true;
      }
      _wakeTime = null;
      restFrom(rest);
      return false;
    }
    _wakeTime = null;
    final rest = restTime();
    if (rest == null || rest > time) return true;
    restFrom(rest);
    return false;
  }

  /// The earliest time from which every component stays within
  /// [tolerance] ([restDistance] when it is null) of its target until the
  /// next change, or null while a delayed change is pending.
  ///
  /// For a [TimingCurve], returns the end of the last running curve.
  /// For a [Spring], found from the course, not from frames: closed form for
  /// an underdamped spring, whose remaining swing ([reach]) decays on its
  /// envelope; for a critically damped or overdamped one, the first time
  /// [reach] falls below [tolerance], sampled every 1/32 of the spring's
  /// response and refined to within a nanosecond.
  @override
  double? restTime([double? tolerance]) {
    if (_pendingDue != null) return null;
    if (_curves case final curves?) {
      var end = double.negativeInfinity;
      for (final seg in curves) {
        end = math.max(end, seg.end);
      }
      return end;
    }
    final within = tolerance ?? restDistance;
    if (within == _restMemoTolerance) return _restMemo;
    var after = 0.0;
    for (var i = 0; i < _n; i++) {
      after = math.max(after, _settleAfter(i, within));
    }
    var rest = _origin + after;
    final rested = _restedAt;
    if (rested != null && rested < rest) rest = rested;
    _restMemoTolerance = within;
    _restMemo = rest;
    return rest;
  }

  @override
  bool restsAt(double t, [double? tolerance]) {
    if (_curves case final curves?) {
      for (final seg in curves) {
        if (t >= seg.start && t < seg.end) return false;
      }
      return true;
    }
    return reach(t) < (tolerance ?? restDistance);
  }

  @override
  void restFrom(double t) {
    if (_pendingDue != null) return;
    if (_curves case final curves?) {
      if (curves.any((seg) => seg.end > t)) return;
      _clearCurves();
      _y0.setAll(0, _target);
      _v0.fillRange(0, _n, 0);
      _origin = math.max(t, _origin);
      _restedAt = _origin;
      _atRest = true;
      _swing = 0;
      _memoT = double.nan;
      return;
    }
    _restedAt = math.max(t, _origin);
    _atRest = true;
    _swing = 0;
    _memoT = double.nan;
  }

  @override
  double? get nextDue {
    if (_pendingDue != null) return _pendingDue;
    if (_curves case final curves?) {
      final now = owner?.now ?? double.negativeInfinity;
      return _earliestCurveStartAfter(curves, now);
    }
    return null;
  }

  static double? _earliestCurveStartAfter(
    List<_CurveSegment> curves,
    double time,
  ) {
    double? due;
    for (final seg in curves) {
      if (seg.start > time && (due == null || seg.start < due)) {
        due = seg.start;
      }
    }
    return due;
  }

  double _settleAfter(int i, double tolerance) {
    final a = _y0[i] - _target[i];
    final v = _v0[i];
    final start = _reach(a, v);
    if (start < tolerance) return 0;
    final motion = _motion;
    final zeta = motion.dampingRatio;
    if (zeta < 1 - criticalDampingTolerance) {
      if (zeta <= 0) return double.infinity;
      return math.log(start / tolerance) / (zeta * motion.omega);
    }
    final step = motion.response / 32;
    var lo = 0.0;
    var hi = step;
    while (_reachAfter(i, hi) >= tolerance) {
      lo = hi;
      hi += step;
    }
    while (hi - lo > 1e-9) {
      final mid = (lo + hi) / 2;
      if (_reachAfter(i, mid) >= tolerance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }

  double _reachAfter(int i, double dt) {
    final simulation = _simulation(i);
    return _reach(simulation.x(dt) - _target[i], simulation.dx(dt));
  }

  Float64List _components(T value) {
    final components = Float64List(_n);
    converter.write(value, components);
    return components;
  }

  bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < _n; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _dispatchAnimation(
    double t,
    Float64List target,
    MotionAnimation animation, {
    required bool tracking,
    required double delay,
  }) {
    switch (animation) {
      case final Spring spring:
        _change(t, target, spring, tracking: tracking, delay: delay);
      case final TimingCurve curve:
        _changeCurve(t, target, curve, delay: delay);
    }
  }

  void _change(
    double t,
    Float64List target,
    Spring spring, {
    required bool tracking,
    required double delay,
  }) {
    _applyPending(t);
    if (delay > 0) {
      _defer(t, target, spring, tracking: tracking, delay: delay);
      return;
    }
    _clearPending();
    _retargetAt(t, target, spring, tracking: tracking);
    _follow();
  }

  void _changeCurve(
    double t,
    Float64List target,
    TimingCurve curve, {
    required double delay,
  }) {
    _applyPending(t);
    if (_curves == null && delay > 0 && !_atRest) {
      _defer(t, target, curve, tracking: false, delay: delay);
      return;
    }
    _clearPending();
    _startCurveAt(t, target, curve, delay: delay);
    _follow();
  }

  void _defer(
    double t,
    Float64List target,
    MotionAnimation animation, {
    required bool tracking,
    required double delay,
  }) {
    _state(t);
    _pendingDue = _notBefore(t) + delay;
    _pendingTarget = target;
    _pendingAnimation = animation;
    _pendingTracking = tracking;
    _follow();
  }

  void _startCurveAt(
    double t,
    Float64List target,
    TimingCurve curve, {
    required double delay,
  }) {
    if (curve.isImmediate && delay <= 0) {
      _snapAt(t, target);
      return;
    }
    final at = _since(t);
    final start = at + delay;
    final step = Float64List(_n);
    final span = Float64List(_n);
    final curves = _curves;
    if (curves == null) {
      _state(at);
      for (var i = 0; i < _n; i++) {
        step[i] = target[i] - _memoY[i];
      }
      span.setAll(0, step);
      _curves = [_CurveSegment(start, curve, step, span)];
    } else {
      curves.removeWhere((seg) => seg.end <= at);
      for (var i = 0; i < _n; i++) {
        step[i] = target[i] - _target[i];
      }
      if (curve.additive) {
        span.setAll(0, step);
      } else {
        _evalCurvesAt(curves, start, span, null);
        for (var i = 0; i < _n; i++) {
          span[i] = target[i] - span[i];
        }
        for (final seg in curves) {
          if (seg.start < start) {
            seg.cutoff = math.min(seg.cutoff, start);
            continue;
          }
          for (var i = 0; i < _n; i++) {
            step[i] += seg.step[i];
          }
        }
        curves.removeWhere((seg) => seg.start >= start);
      }
      curves.add(_CurveSegment(start, curve, step, span));
    }
    for (var i = 0; i < _n; i++) {
      _swing = math.max(_swing, math.max(step[i].abs(), span[i].abs()));
    }
    _target.setAll(0, target);
    _atRest = false;
    _restedAt = null;
    _origin = at;
    _changed();
  }

  void _retargetAt(
    double t,
    Float64List target,
    Spring spring, {
    required bool tracking,
  }) {
    final use = tracking ? spring.trackingSpring : spring;
    if (use.isImmediate) {
      _snapAt(t, target);
      return;
    }
    final at = _since(t);
    _state(at);
    _clearCurves();
    final push = use.stiffness * spring.impulse;
    for (var i = 0; i < _n; i++) {
      _y0[i] = _memoY[i];
      _v0[i] = _memoV[i] + push * (target[i] - _target[i]);
      _target[i] = target[i];
    }
    _spring = spring;
    _tracking = tracking;
    _measureSwing();
    _atRest = false;
    _restedAt = null;
    _origin = at;
    _changed();
  }

  void _snapAt(double t, Float64List value) {
    _clearCurves();
    _atRest = true;
    _restedAt = null;
    _swing = 0;
    _changed();
    _origin = _since(t);
    for (var i = 0; i < _n; i++) {
      _y0[i] = value[i];
      _v0[i] = 0;
      _target[i] = value[i];
    }
  }

  void _place(double t, Float64List value, Float64List velocity) {
    _clearCurves();
    _atRest = false;
    _restedAt = null;
    _changed();
    _origin = _since(t);
    _y0.setAll(0, value);
    _v0.setAll(0, velocity);
    _measureSwing();
  }

  void _measureSwing() {
    for (var i = 0; i < _n; i++) {
      _swing = math.max(_swing, _reach(_y0[i] - _target[i], _v0[i]));
    }
  }

  void _clearCurves() => _curves = null;

  void _clearPending() {
    _pendingDue = null;
    _pendingTarget = null;
    _pendingAnimation = null;
    _pendingTracking = false;
  }

  void _applyPending(double t) {
    final due = _pendingDue;
    if (due == null || t < due) return;
    final target = _pendingTarget!;
    final animation = _pendingAnimation!;
    final tracking = _pendingTracking;
    _clearPending();
    switch (animation) {
      case final Spring spring:
        _retargetAt(due, target, spring, tracking: tracking);
      case final TimingCurve curve:
        _startCurveAt(due, target, curve, delay: 0);
    }
  }

  double _notBefore(double t) => _moved && t < _origin ? _origin : t;

  double _since(double t) {
    final at = _notBefore(t);
    _moved = true;
    return at;
  }

  void _changed() {
    _memoT = double.nan;
    _restMemoTolerance = double.nan;
    _simulations.fillRange(0, _n, null);
  }

  void _state(double t) {
    _applyPending(t);
    if (t == _memoT) return;
    if (_curves case final curves?) {
      _evalCurvesAt(curves, math.max(t, _origin), _memoY, _memoV);
    } else {
      final dt = t - _origin;
      for (var i = 0; i < _n; i++) {
        if (dt <= 0) {
          _memoY[i] = _y0[i];
          _memoV[i] = _v0[i];
          continue;
        }
        final simulation = _simulation(i);
        _memoY[i] = simulation.x(dt);
        _memoV[i] = simulation.dx(dt);
      }
    }
    final rested = _restedAt;
    if (rested != null && t >= rested) {
      _memoY.setAll(0, _target);
      _memoV.fillRange(0, _n, 0);
    }
    _memoT = t;
  }

  // The value is the target less what each curve has still to cover: its
  // step of the target until it starts, then its own course, which for a
  // plain curve runs from where the value was when it started.
  void _evalCurvesAt(
    List<_CurveSegment> curves,
    double t,
    Float64List outY,
    Float64List? outV,
  ) {
    outY.setAll(0, _target);
    outV?.fillRange(0, _n, 0);
    for (final seg in curves) {
      if (t >= seg.cutoff) continue;
      final course = seg.courseAt(t);
      final left = 1 - seg.progressAt(t);
      final dp = outV != null ? seg.velocityAt(t) : 0.0;
      for (var i = 0; i < _n; i++) {
        outY[i] -= course[i] * left;
        if (outV != null) outV[i] += course[i] * dp;
      }
    }
  }

  SpringSimulation _simulation(int i) => _simulations[i] ??= SpringSimulation(
    _motion.description,
    _y0[i],
    _target[i],
    _v0[i],
  );

  double _reach(double a, double v) {
    final motion = _motion;
    final w0 = motion.omega;
    final zeta = motion.dampingRatio;
    if (zeta < 1 - criticalDampingTolerance) {
      final wd = w0 * math.sqrt(1 - zeta * zeta);
      final b = (v + zeta * w0 * a) / wd;
      return math.sqrt(a * a + b * b);
    }
    if (zeta <= 1 + criticalDampingTolerance) {
      return a.abs() + (v + w0 * a).abs() / (w0 * math.e);
    }
    final s = w0 * math.sqrt(zeta * zeta - 1);
    final r1 = -zeta * w0 + s;
    final r2 = -zeta * w0 - s;
    final c2 = (v - r1 * a) / (r2 - r1);
    return (a - c2).abs() + c2.abs();
  }

  @override
  String toString() =>
      'MotionValue<$T>(${valueAt(_memoT.isNaN ? _origin : _memoT)} -> $target)';
}

final class _ValuePublisher<T> extends ClockPublisher {
  _ValuePublisher(this._host) : super('while notifying a MotionValue listener');

  final MotionValue<T> _host;

  @override
  double? get wakeTime => _host._wakeTime;

  @override
  bool stepTo(double time) => _host._stepTo(time);
}

/// Internal helpers for [MotionValue] within the package.
@internal
extension MotionValueInternal<T> on MotionValue<T> {
  /// Moves the whole course by the change from [from] to [to], keeping the
  /// velocity, the animation and the time left.
  void shift(T from, T to) => _shift(from, to);
}

final class _CurveSegment {
  _CurveSegment(this.start, this.timing, this.step, this.span);

  final double start;
  final TimingCurve timing;

  /// How far the change moved the target.
  final Float64List step;

  /// How far the curve carries the value once it starts: its [step] for an
  /// additive curve, from where the value is at [start] for a plain one.
  final Float64List span;

  /// When a later plain curve takes the value over.
  double cutoff = double.infinity;

  double get end => math.min(start + timing.duration, cutoff);

  Float64List courseAt(double t) => t >= start ? span : step;

  double progressAt(double t) {
    if (t < start) return 0;
    if (timing.duration <= 0 || t >= start + timing.duration) return 1;
    return timing.progressAt(t - start);
  }

  double velocityAt(double t) =>
      t < start ? 0 : timing.progressVelocityAt(t - start);
}

/// The explicit-time commands and reads of a [MotionValue], for motions
/// that replay recorded input: every one takes the time it happens at, in
/// seconds. A change never reaches back before the previous one: a time
/// earlier than the last change takes effect at that change's time.
///
/// Apps write the ambient forms (`target`, `value`, `velocity`); a `Motion`
/// subclass commands its parts with these.
extension MotionValueCommands<T> on MotionValue<T> {
  /// The value at time [t].
  T valueAt(double t) {
    _state(t);
    return converter.read(_memoY);
  }

  /// The velocity at time [t], per second.
  T velocityAt(double t) {
    _state(t);
    return converter.read(_memoV);
  }

  /// Sends the value toward [target] from its state at time [t], on
  /// [spring] when one is given and on [MotionValue.spring] otherwise; on
  /// that spring's tracking spring when [tracking].
  ///
  /// With a [delay] in seconds the value keeps its course until `t + delay`
  /// and turns toward [target] then; the `target` getter reads the new
  /// value at once. A change replaces a delayed change still pending.
  void retarget(
    double t,
    T target, {
    Spring? spring,
    bool tracking = false,
    double delay = 0,
  }) => _change(
    t,
    _components(target),
    spring ?? _spring,
    tracking: tracking,
    delay: delay,
  );

  /// Sends the value toward [target] from its state at time [t] using
  /// [animation] (a [Spring] or a [TimingCurve]).
  ///
  /// With a [delay] in seconds the value keeps its course until `t + delay`
  /// and turns toward [target] then. When [animation] is an additive
  /// [TimingCurve], the curve stacks on top of running curves. With
  /// [tracking] a finger drives the change, which takes a [Spring].
  void animate(
    double t,
    T target, {
    required MotionAnimation animation,
    bool tracking = false,
    double delay = 0,
  }) {
    assert(!tracking || animation is Spring, 'A finger tracks on a Spring.');
    _dispatchAnimation(
      t,
      _components(target),
      animation,
      tracking: tracking,
      delay: delay,
    );
  }

  /// Puts the value at rest on [value] at time [t].
  void snap(double t, T value) {
    _clearPending();
    _snapAt(t, _components(value));
    _follow();
  }

  /// Gives the value [velocity] at time [t], keeping its position and
  /// target.
  void setVelocity(double t, T velocity) {
    _state(t);
    _place(t, _memoY, _components(velocity));
    _follow();
  }

  /// Puts the value at [value] with [velocity] (none when null) at time
  /// [t], keeping its target.
  void setPresentation(double t, T value, {T? velocity}) {
    _applyPending(t);
    _place(
      t,
      _components(value),
      velocity == null ? Float64List(_n) : _components(velocity),
    );
    _follow();
  }

  /// Declares the value at rest from [t] ([restFrom]): the course is kept,
  /// reads from [t] on answer its target and its listeners hear it. [t] is
  /// no earlier than [restTime]; an earlier one jumps to the target.
  void settle(double t) {
    restFrom(t);
    _follow();
  }

  /// A bound on how far any component still swings from its target at any
  /// time from [t] on, until the next change.
  ///
  /// An underdamped spring's offset stays inside its decaying envelope; a
  /// critically damped or overdamped one inside the sum of its modes.
  double reach(double t) {
    if (_curves case final curves?) {
      if (!curves.any((seg) => seg.end > t)) return 0;
      var reach = 0.0;
      for (var i = 0; i < _n; i++) {
        var left = 0.0;
        for (final seg in curves) {
          if (t >= seg.end) continue;
          left += t >= seg.start
              ? seg.span[i].abs() * (1 - seg.progressAt(t))
              : math.max(seg.step[i].abs(), seg.span[i].abs());
        }
        reach = math.max(reach, left);
      }
      return math.max(reach, restDistance);
    }
    _state(t);
    var reach = 0.0;
    for (var i = 0; i < _n; i++) {
      reach = math.max(reach, _reach(_memoY[i] - _target[i], _memoV[i]));
    }
    return reach;
  }
}
