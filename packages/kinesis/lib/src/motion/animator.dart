import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/signal.dart';
import 'package:kinesis/src/motion/transaction.dart';
import 'package:kinesis/src/motion/value.dart';

/// Lifecycle state of a [MotionAnimator].
///
/// UIKit: `UIViewAnimatingState` (`inactive`, `active`, `stopped`).
enum MotionAnimatorState {
  /// Not started yet, or already finished/stopped without finishing.
  inactive,

  /// Started and either running or paused (including paused on completion).
  active,

  /// Stopped with `withoutFinishing: false`, awaiting [MotionAnimator.finish].
  stopped,
}

/// Terminal position handed to [MotionAnimator.finish] and completion handlers.
///
/// UIKit: `UIViewAnimatingPosition` (`start`, `current`, `end`).
enum MotionAnimatorPosition {
  /// The values at the start of the animation.
  start,

  /// The values frozen at the instant the animation stopped.
  current,

  /// The target values at the end of the animation.
  end,
}

/// An interruptible, scrubbable, reversible animator driving one or more
/// [MotionValue]s on a [MotionClock].
///
/// UIKit: `UIViewPropertyAnimator`.
///
/// Register target changes with [addAnimation], attach optional completion
/// callbacks with [addCompletion], then call [start], [pause], [scrub]
/// (or set [fractionComplete]), flip [isReversed], [continueWith] a new
/// [Spring] or [TimingCurve], or [stop] and [finish].
///
/// While paused, [scrubsLinearly] controls whether [fractionComplete] maps
/// linearly across each property (`true`, UIKit default) or evaluates the
/// underlying curve or spring (`false`, preserving ease or spring overshoot).
///
/// Under Reduce Motion ([MotionTraits.platform]) a run takes the
/// animation's [MotionAnimation.reduced] alternative, as a value that no
/// motion owns does.
final class MotionAnimator {
  /// Creates an animator driven by [animation] on [clock] (defaults to
  /// [MotionClock.instance]).
  MotionAnimator({
    required MotionAnimation animation,
    MotionClock? clock,
    this.scrubsLinearly = true,
    this.pausesOnCompletion = false,
    this.isInterruptible = true,
  }) : _animation = animation,
       _running = animation,
       _originalDuration = _durationOf(animation),
       _clock = clock ?? MotionClock.instance;

  static double _durationOf(MotionAnimation animation) => switch (animation) {
    final TimingCurve curve => curve.duration,
    final Spring spring =>
      spring.settlingDuration.isFinite ? spring.settlingDuration : 0,
  };

  final MotionClock _clock;
  final double _originalDuration;

  /// Whether scrubbing while paused maps [fractionComplete] linearly across
  /// properties instead of evaluating the animation's curve or spring.
  final bool scrubsLinearly;

  /// Whether reaching the end leaves the animator [MotionAnimatorState.active]
  /// and paused at `fractionComplete == 1` instead of completing immediately.
  final bool pausesOnCompletion;

  /// Whether [pause] and [stop] are permitted; when false, calling them throws
  /// [StateError], matching UIKit's `isInterruptible = false`.
  final bool isInterruptible;

  MotionAnimation _animation;
  MotionAnimation _running;
  MotionAnimatorState _state = MotionAnimatorState.inactive;
  bool _isRunning = false;
  bool _isReversed = false;
  double _fraction = 0;

  double _segmentStartTime = 0;
  double _segmentStartFraction = 0;
  double _segmentDuration = 0;

  final List<_Track<Object?>> _tracks = [];
  final List<void Function(MotionAnimatorPosition)> _completions = [];
  late final MotionSignal<double> _progress = MotionSignal<double>(
    0,
    clock: _clock,
  );
  late final _AnimatorFollower _follower = _AnimatorFollower(this);

  /// The active timing animation.
  MotionAnimation get animation => _animation;

  /// The clock driving this animator.
  MotionClock get clock => _clock;

  /// The nominal duration of this animator, in seconds.
  ///
  /// For a [TimingCurve] this is its duration; for a [Spring] this is
  /// [Spring.settlingDuration].
  double get duration => _originalDuration;

  /// The current lifecycle state.
  MotionAnimatorState get state => _state;

  /// Whether the animator is currently advancing over time.
  bool get isRunning => _isRunning;

  /// Whether playback runs backward toward [MotionAnimatorPosition.start].
  ///
  /// Flipping it while running turns around where the values are and
  /// retraces their path; before [start] it only sets the direction.
  bool get isReversed => _isReversed;

  set isReversed(bool value) {
    if (_isReversed == value) return;
    final now = _clock.now;
    if (_isRunning && now > _segmentStartTime) {
      _fraction = _fractionAt(now);
      _segmentStartFraction = _fraction;
      _segmentStartTime = now;
    }
    _isReversed = value;
  }

  /// Normalized completion progress in `0..1`.
  ///
  /// Setting this scrubs the animator (just like [scrub]).
  double get fractionComplete =>
      _isRunning ? _fractionAt(_clock.now) : _fraction;

  set fractionComplete(double value) => scrub(value);

  /// A listenable reporting normalized progress in `0..1`, heard in the
  /// clock's publish phase after the tracked values moved to it.
  ValueListenable<double> get progressListenable => _progress;

  /// Registers [value] to animate to [target], starting once the overall
  /// progress passes [delayFactor] (`0 <= delayFactor < 1`).
  ///
  /// Added to a started animator, [value] moves from where it is now to
  /// [target] over the rest of the run.
  void addAnimation<T>(
    MotionValue<T> value,
    T target, {
    double delayFactor = 0,
  }) {
    assert(
      delayFactor >= 0 && delayFactor < 1,
      'delayFactor must be in [0, 1)',
    );
    // `addAnimation(opacity, 1)` infers T as num: give the int literal the
    // double the value holds, as a double context would.
    final end = target is int && value is MotionValue<double>
        ? target.toDouble() as T
        : target;
    final track = _Track<T>(value, end, delayFactor);
    if (_state != MotionAnimatorState.inactive) {
      track.join(_clock.now, fractionComplete);
    }
    _tracks.add(track);
  }

  /// Registers a completion callback invoked synchronously in insertion order
  /// when the animation completes or [finish] is called.
  void addCompletion(void Function(MotionAnimatorPosition position) callback) {
    _completions.add(callback);
  }

  /// Removes a callback registered with [addCompletion], so the runs that
  /// finish after this no longer call it.
  void removeCompletion(
    void Function(MotionAnimatorPosition position) callback,
  ) {
    _completions.remove(callback);
  }

  /// Starts the animator from [MotionAnimatorState.inactive], or resumes it
  /// when paused, at time [at] (defaults to `clock.now`) after optional
  /// [delay] seconds.
  ///
  /// A resumed animator runs its animation on from where the values are.
  void start({double? at, double delay = 0}) {
    if (_state == MotionAnimatorState.stopped) {
      throw StateError('A stopped MotionAnimator cannot be started.');
    }
    final now = at ?? _clock.now;
    if (_state == MotionAnimatorState.inactive) {
      _begin(now);
      _fraction = 1 - _endFraction;
    } else {
      if (_isRunning) return;
      if (scrubsLinearly) _anchorTracks(now);
    }
    _segmentStartFraction = _fraction;
    final effectiveDelay = delay < 0 ? 0.0 : delay;
    _segmentStartTime = now + effectiveDelay;
    _isRunning = true;
    if (_segmentDuration <= 0 && effectiveDelay <= 0) {
      _completeAt(now);
      return;
    }
    _applyAt(_fraction, now);
    _clock.follow(_follower);
  }

  /// Pauses a running animator at [at] (defaults to `clock.now`), keeping
  /// every value where it is.
  ///
  /// Throws [StateError] when [isInterruptible] is false.
  void pause({double? at}) {
    if (!isInterruptible) {
      throw StateError('A non-interruptible MotionAnimator cannot be paused.');
    }
    if (_state != MotionAnimatorState.active || !_isRunning) return;
    _pauseAt(at ?? _clock.now);
  }

  /// Scrubs all tracked values to [fraction] (`0..1`) at time [at].
  ///
  /// When called from [MotionAnimatorState.inactive], captures initial values
  /// and transitions into paused [MotionAnimatorState.active], matching UIKit.
  /// After a pause, linear scrubbing passes through the values where the
  /// pause left them.
  void scrub(double fraction, {double? at}) {
    final now = at ?? _clock.now;
    if (_state == MotionAnimatorState.inactive) {
      _begin(now);
      _isRunning = false;
    } else if (_isRunning) {
      _pauseAt(now);
    }
    _fraction = fraction.clamp(0.0, 1.0);
    _segmentStartFraction = _fraction;
    _applyAt(_fraction, now);
  }

  /// Runs the rest of the animation from where the values are, on
  /// [animation] when given: the remaining portion takes [durationFactor]
  /// times the animation's duration ([TimingCurve.duration], or
  /// [Spring.settlingDuration] for a spring).
  ///
  /// UIKit: `continueAnimation(withTimingParameters:durationFactor:)`.
  void continueWith({
    MotionAnimation? animation,
    double durationFactor = 1,
    double? at,
  }) {
    if (_state != MotionAnimatorState.active) {
      throw StateError('continueWith requires an active MotionAnimator.');
    }
    final now = at ?? _clock.now;
    if (_isRunning) {
      _fraction = _fractionAt(now);
      _applyAt(_fraction, now);
    }
    if (animation != null) _animation = animation;
    _running = _resolved(_animation);
    _anchorTracks(now);
    final remaining = (_endFraction - _fraction).abs();
    final duration = _durationOf(_running) * math.max(durationFactor, 0);
    _segmentStartFraction = _fraction;
    _segmentStartTime = now;
    _segmentDuration = remaining <= 0 ? 0 : duration / remaining;
    _isRunning = true;
    if (duration <= 0 || remaining <= 0) {
      _completeAt(now);
      return;
    }
    _clock.follow(_follower);
  }

  /// Stops the animator and freezes every tracked value at its current
  /// presentation.
  ///
  /// When [withoutFinishing] is true, transitions straight to
  /// [MotionAnimatorState.inactive] without calling completion handlers.
  /// When false, transitions to [MotionAnimatorState.stopped]; call [finish]
  /// afterwards to run completion handlers.
  ///
  /// Throws [StateError] when [isInterruptible] is false.
  void stop({required bool withoutFinishing, double? at}) {
    if (!isInterruptible) {
      throw StateError('A non-interruptible MotionAnimator cannot be stopped.');
    }
    final now = at ?? _clock.now;
    if (_isRunning) {
      _fraction = _fractionAt(now);
      _applyAt(_fraction, now);
    }
    _clock.unfollow(_follower);
    _reset(now);
    if (!withoutFinishing) _state = MotionAnimatorState.stopped;
  }

  /// Finishes a stopped animator at [position], snapping values to [position],
  /// resetting to [MotionAnimatorState.inactive], and invoking completions
  /// synchronously in insertion order.
  ///
  /// Throws [StateError] if [state] is not [MotionAnimatorState.stopped].
  void finish(MotionAnimatorPosition position, {double? at}) {
    if (_state != MotionAnimatorState.stopped) {
      throw StateError(
        'finish should only be called on a stopped MotionAnimator.',
      );
    }
    _finishAt(at ?? _clock.now, position);
  }

  /// Detaches from the clock.
  void dispose() {
    _isRunning = false;
    _clock.unfollow(_follower);
  }

  double _fractionAt(double time) {
    if (!_isRunning) return _fraction;
    if (time <= _segmentStartTime) return _segmentStartFraction;
    if (_segmentDuration <= 0) return _endFraction;
    final delta = (time - _segmentStartTime) / _segmentDuration;
    return (_isReversed
            ? _segmentStartFraction - delta
            : _segmentStartFraction + delta)
        .clamp(0.0, 1.0);
  }

  void _pauseAt(double now) {
    _fraction = _fractionAt(now);
    _applyAt(_fraction, now);
    _isRunning = false;
    _clock.unfollow(_follower);
    if (scrubsLinearly) _anchorTracks(now);
  }

  void _anchorTracks(double now) {
    for (final track in _tracks) {
      track.anchor(now, _fraction);
    }
  }

  bool _stepTo(double time) {
    if (!_isRunning) return false;
    if (time < _segmentStartTime) return true;
    final next = _fractionAt(time);
    _fraction = next;
    if (next == _endFraction) {
      _completeAt(time);
      return false;
    }
    _applyAt(next, time);
    return true;
  }

  void _completeAt(double time) {
    final endPosition = _isReversed
        ? MotionAnimatorPosition.start
        : MotionAnimatorPosition.end;
    _fraction = _endFraction;
    _applyAt(_fraction, time);
    _isRunning = false;
    _clock.unfollow(_follower);

    if (pausesOnCompletion) {
      _state = MotionAnimatorState.active;
      if (scrubsLinearly) _anchorTracks(time);
      return;
    }

    _finishAt(time, endPosition);
  }

  void _finishAt(double t, MotionAnimatorPosition position) {
    for (final track in _tracks) {
      track.snapToPosition(t, position);
    }
    _reset(t);
    notifyGuardedWith(
      _completions,
      position,
      'while notifying a MotionAnimator completion',
    );
  }

  double get _endFraction => _isReversed ? 0.0 : 1.0;

  void _begin(double now) {
    for (final track in _tracks) {
      track.begin(now, reversed: _isReversed);
    }
    _state = MotionAnimatorState.active;
    _running = _resolved(_animation);
    _segmentDuration = _durationOf(_running);
  }

  static MotionAnimation _resolved(MotionAnimation animation) =>
      animation.resolve(reduceMotion: MotionTraits.platform().reduceMotion);

  void _reset(double t) {
    _state = MotionAnimatorState.inactive;
    _isRunning = false;
    _isReversed = false;
    _fraction = 0;
    _writeProgress(t, 0);
  }

  void _applyAt(double fraction, double time) {
    final animation = !_isRunning && scrubsLinearly ? null : _running;
    for (final track in _tracks) {
      track.apply(time, fraction, animation, _segmentDuration);
    }
    _writeProgress(time, fraction);
  }

  void _writeProgress(double t, double fraction) {
    if (_progress.valueAt(double.infinity) != fraction) {
      _progress.write(t, fraction);
    }
  }
}

double _progressOf(MotionAnimation animation, double u, double seconds) {
  if (u <= 0) return 0;
  if (u >= 1) return 1;
  return switch (animation) {
    final TimingCurve curve => curve.curve.transform(u),
    final Spring spring =>
      spring.isImmediate || seconds <= 0
          ? 1.0
          : SpringSimulation(spring.description, 0, 1, 0).x(u * seconds),
  };
}

/// One value of a [MotionAnimator]: where it started, where it ends, and the
/// anchor its path runs from, the value it had at a local fraction of the
/// run. From the anchor the path goes on to the end at higher fractions and
/// back to the start at lower ones, so pausing, reversing and continuing
/// never jump.
final class _Track<T> {
  _Track(this.value, T endValue, this.delayFactor)
    : _n = value.converter.dimensions,
      _start = Float64List(value.converter.dimensions),
      _end = Float64List(value.converter.dimensions),
      _anchor = Float64List(value.converter.dimensions),
      _scratch = Float64List(value.converter.dimensions) {
    value.converter.write(endValue, _end);
  }

  final MotionValue<T> value;
  final double delayFactor;
  final int _n;
  final Float64List _start;
  final Float64List _end;
  final Float64List _anchor;
  final Float64List _scratch;
  double _anchorLocal = 0;

  double _local(double fraction) {
    if (delayFactor <= 0) return fraction;
    if (fraction <= delayFactor) return 0;
    return ((fraction - delayFactor) / (1 - delayFactor)).clamp(0.0, 1.0);
  }

  void begin(double t, {required bool reversed}) {
    value.converter.write(value.valueAt(t), _start);
    _anchor.setAll(0, reversed ? _end : _start);
    _anchorLocal = reversed ? 1 : 0;
  }

  void join(double t, double fraction) {
    value.converter.write(value.valueAt(t), _start);
    _anchor.setAll(0, _start);
    _anchorLocal = _local(fraction);
  }

  void anchor(double t, double fraction) {
    value.converter.write(value.valueAt(t), _anchor);
    _anchorLocal = _local(fraction);
  }

  void apply(
    double t,
    double fraction,
    MotionAnimation? animation,
    double secondsPerFraction,
  ) {
    final local = _local(fraction);
    final forward = local >= _anchorLocal;
    final span = forward ? 1 - _anchorLocal : _anchorLocal;
    final u = span <= 0
        ? 1.0
        : (forward ? local - _anchorLocal : _anchorLocal - local) / span;
    final mapped = animation == null
        ? u
        : _progressOf(
            animation,
            u,
            span * secondsPerFraction * (1 - delayFactor),
          );
    final destination = forward ? _end : _start;
    for (var i = 0; i < _n; i++) {
      _scratch[i] = _anchor[i] + (destination[i] - _anchor[i]) * mapped;
    }
    value.snap(t, value.converter.read(_scratch));
  }

  void snapToPosition(double t, MotionAnimatorPosition position) {
    switch (position) {
      case MotionAnimatorPosition.start:
        value.snap(t, value.converter.read(_start));
      case MotionAnimatorPosition.end:
        value.snap(t, value.converter.read(_end));
      case MotionAnimatorPosition.current:
        value.snap(t, value.valueAt(t));
    }
  }
}

final class _AnimatorFollower implements MotionFollowed {
  _AnimatorFollower(this._animator);

  final MotionAnimator _animator;

  @override
  double? get wakeTime =>
      _animator._isRunning && _animator._clock.now < _animator._segmentStartTime
      ? _animator._segmentStartTime
      : null;

  @override
  bool get hasWidgetFollowers => true;

  @override
  bool stepTo(double time) => _animator._stepTo(time);

  @override
  void publish({required bool widgets}) {}
}
