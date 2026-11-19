import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/clock.dart';
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
enum AnimatorPosition {
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
  MotionAnimatorState _state = MotionAnimatorState.inactive;
  bool _isRunning = false;
  bool _isReversed = false;
  double _fraction = 0;

  double _segmentStartTime = 0;
  double _segmentStartFraction = 0;
  double _segmentDuration = 0;
  double _delay = 0;
  bool _continued = false;

  final List<_Track<Object?>> _tracks = [];
  final List<void Function(AnimatorPosition)> _completions = [];
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
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

  /// Whether playback runs backward toward [AnimatorPosition.start].
  bool get isReversed => _isReversed;

  set isReversed(bool value) {
    if (_isReversed == value) return;
    if (!isInterruptible) {
      _isReversed = value;
      return;
    }
    final now = _clock.now;
    if (_isRunning) {
      _fraction = _fractionAt(now);
      _segmentStartFraction = _fraction;
      _segmentStartTime = now;
    }
    _isReversed = value;
    _applyAt(_fraction, now);
  }

  /// Normalized completion progress in `0..1`.
  ///
  /// Setting this scrubs the animator (just like [scrub]).
  double get fractionComplete =>
      _isRunning ? _fractionAt(_clock.now) : _fraction;

  set fractionComplete(double value) => scrub(value);

  /// A listenable reporting normalized progress in `0..1`.
  ValueListenable<double> get progressListenable => _progress;

  /// Registers [value] to animate to [target], starting once the overall
  /// progress passes [delayFactor] (`0 <= delayFactor < 1`).
  void addAnimation<T>(
    MotionValue<T> value,
    T target, {
    double delayFactor = 0,
  }) {
    assert(
      delayFactor >= 0 && delayFactor < 1,
      'delayFactor must be in [0, 1)',
    );
    _tracks.add(_Track<T>(value, target, delayFactor));
  }

  /// Registers a completion callback invoked synchronously in insertion order
  /// when the animation completes or [finish] is called.
  void addCompletion(void Function(AnimatorPosition position) callback) {
    _completions.add(callback);
  }

  /// Starts the animator from [MotionAnimatorState.inactive], or resumes it
  /// when paused, at time [at] (defaults to `clock.now`) after optional
  /// [delay] seconds.
  void start({double? at, double delay = 0}) {
    if (_state == MotionAnimatorState.stopped) {
      throw StateError('A stopped MotionAnimator cannot be started.');
    }
    final now = at ?? _clock.now;
    if (_state == MotionAnimatorState.inactive) {
      for (final track in _tracks) {
        track.captureStart(now);
      }
      _fraction = _isReversed ? 1.0 : 0.0;
      _segmentStartFraction = _fraction;
      _segmentDuration = _originalDuration;
      _continued = false;
    } else {
      if (_isRunning) return;
      _segmentStartFraction = _fraction;
      if (!_continued) _segmentDuration = _originalDuration;
    }
    _delay = delay < 0 ? 0 : delay;
    _segmentStartTime = now + _delay;
    _state = MotionAnimatorState.active;
    _isRunning = true;
    if (_segmentDuration <= 0 && _delay <= 0) {
      _completeAt(now);
      return;
    }
    _applyAt(_fraction, now);
    _clock.follow(_follower);
  }

  /// Pauses a running animator at [at] (defaults to `clock.now`).
  ///
  /// Throws [StateError] when [isInterruptible] is false.
  void pause({double? at}) {
    if (!isInterruptible) {
      throw StateError('A non-interruptible MotionAnimator cannot be paused.');
    }
    if (_state != MotionAnimatorState.active || !_isRunning) return;
    final now = at ?? _clock.now;
    _fraction = _fractionAt(now);
    _isRunning = false;
    _clock.unfollow(_follower);
    _applyAt(_fraction, now);
  }

  /// Scrubs all tracked values to [fraction] (`0..1`) at time [at].
  ///
  /// When called from [MotionAnimatorState.inactive], captures initial values
  /// and transitions into paused [MotionAnimatorState.active], matching UIKit.
  void scrub(double fraction, {double? at}) {
    final now = at ?? _clock.now;
    final clamped = fraction.clamp(0.0, 1.0);
    if (_state == MotionAnimatorState.inactive) {
      for (final track in _tracks) {
        track.captureStart(now);
      }
      _state = MotionAnimatorState.active;
      _isRunning = false;
      _segmentDuration = _originalDuration;
      _continued = false;
    } else if (_isRunning) {
      _isRunning = false;
      _clock.unfollow(_follower);
    }
    _fraction = clamped;
    _segmentStartFraction = clamped;
    _applyAt(clamped, now);
  }

  /// Resumes a paused animator with an optional new [animation] and
  /// [durationFactor] multiplying the original [duration].
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
    }
    if (animation != null) _animation = animation;
    final remaining = _isReversed ? _fraction : 1.0 - _fraction;
    final factor = durationFactor <= 0 ? 0.0 : durationFactor;
    final targetDuration = _animation is Spring && durationFactor == 1
        ? _durationOf(_animation)
        : _originalDuration * factor;

    for (final track in _tracks) {
      track.captureContinuation(now);
    }
    _continued = true;
    _segmentStartFraction = _fraction;
    _segmentStartTime = now;
    _segmentDuration = remaining <= 0 ? 0 : targetDuration / remaining;
    _delay = 0;
    _isRunning = true;
    if (targetDuration <= 0 || remaining <= 0) {
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
    _isRunning = false;
    _clock.unfollow(_follower);
    _fraction = 0;
    _progress.value = 0;
    if (withoutFinishing) {
      _state = MotionAnimatorState.inactive;
      _isReversed = false;
      _continued = false;
    } else {
      _state = MotionAnimatorState.stopped;
    }
  }

  /// Finishes a stopped animator at [position], snapping values to [position],
  /// resetting to [MotionAnimatorState.inactive], and invoking completions
  /// synchronously in insertion order.
  ///
  /// Throws [StateError] if [state] is not [MotionAnimatorState.stopped].
  void finish(AnimatorPosition position, {double? at}) {
    if (_state != MotionAnimatorState.stopped) {
      throw StateError(
        'finish should only be called on a stopped MotionAnimator.',
      );
    }
    final now = at ?? _clock.now;
    for (final track in _tracks) {
      track.snapToPosition(now, position);
    }
    _state = MotionAnimatorState.inactive;
    _isRunning = false;
    _isReversed = false;
    _continued = false;
    _fraction = 0;
    _progress.value = 0;
    _fireCompletions(position);
  }

  /// Detaches from the clock and disposes internal resources.
  void dispose() {
    _isRunning = false;
    _clock.unfollow(_follower);
    _progress.dispose();
  }

  double _fractionAt(double time) {
    if (!_isRunning) return _fraction;
    if (time <= _segmentStartTime) return _segmentStartFraction;
    if (_segmentDuration <= 0) return _isReversed ? 0.0 : 1.0;
    final delta = (time - _segmentStartTime) / _segmentDuration;
    return (_isReversed
            ? _segmentStartFraction - delta
            : _segmentStartFraction + delta)
        .clamp(0.0, 1.0);
  }

  bool _stepTo(double time) {
    if (!_isRunning) return false;
    if (time < _segmentStartTime) return true;
    final next = _fractionAt(time);
    _fraction = next;
    final finished = _isReversed ? next <= 0.0 : next >= 1.0;
    if (finished) {
      _completeAt(time);
      return false;
    }
    _applyAt(next, time);
    return true;
  }

  void _completeAt(double time) {
    final endPosition = _isReversed
        ? AnimatorPosition.start
        : AnimatorPosition.end;
    final terminalFraction = _isReversed ? 0.0 : 1.0;
    _fraction = terminalFraction;
    _applyAt(terminalFraction, time);
    _isRunning = false;
    _clock.unfollow(_follower);

    if (pausesOnCompletion) {
      _state = MotionAnimatorState.active;
      return;
    }

    for (final track in _tracks) {
      track.snapToPosition(time, endPosition);
    }
    _state = MotionAnimatorState.inactive;
    _isReversed = false;
    _continued = false;
    _fraction = 0;
    _progress.value = 0;
    _fireCompletions(endPosition);
  }

  void _applyAt(double fraction, double time) {
    _progress.value = fraction;
    final linear = !_isRunning && scrubsLinearly;
    for (final track in _tracks) {
      final local = _localFraction(fraction, track.delayFactor);
      final double mapped;
      if (linear) {
        mapped = local;
      } else if (_continued) {
        final span = _isReversed
            ? _segmentStartFraction
            : 1.0 - _segmentStartFraction;
        final sub = span <= 0
            ? 1.0
            : ((_isReversed
                          ? _segmentStartFraction - fraction
                          : fraction - _segmentStartFraction) /
                      span)
                  .clamp(0.0, 1.0);
        mapped = _evaluateNormalized(_animation, sub, _segmentDuration * span);
        track.applyContinuation(time, mapped, reversed: _isReversed);
        continue;
      } else {
        mapped = _evaluateNormalized(
          _animation,
          local,
          _originalDuration * (1 - track.delayFactor),
        );
      }
      track.apply(time, mapped);
    }
  }

  static double _localFraction(double fraction, double delayFactor) {
    if (delayFactor <= 0) return fraction;
    if (fraction <= delayFactor) return 0;
    return ((fraction - delayFactor) / (1 - delayFactor)).clamp(0.0, 1.0);
  }

  static double _evaluateNormalized(
    MotionAnimation animation,
    double u,
    double totalDuration,
  ) {
    if (u <= 0) return 0;
    if (u >= 1) return 1;
    return switch (animation) {
      final TimingCurve curve => curve.curve.transform(u),
      final Spring spring =>
        spring.isImmediate
            ? 1.0
            : SpringSimulation(spring.description, 0, 1, 0).x(
                u *
                    (totalDuration > 0
                        ? totalDuration
                        : spring.settlingDuration),
              ),
    };
  }

  void _fireCompletions(AnimatorPosition position) {
    for (final callback in List<void Function(AnimatorPosition)>.of(
      _completions,
    )) {
      guardMotion(
        () => callback(position),
        'while notifying a MotionAnimator completion',
      );
    }
  }
}

final class _Track<T> {
  _Track(this.value, this.endValue, this.delayFactor)
    : _n = value.converter.dimensions,
      _start = Float64List(value.converter.dimensions),
      _end = Float64List(value.converter.dimensions),
      _contStart = Float64List(value.converter.dimensions),
      _scratch = Float64List(value.converter.dimensions) {
    value.converter.write(endValue, _end);
  }

  final MotionValue<T> value;
  final T endValue;
  final double delayFactor;
  final int _n;
  final Float64List _start;
  final Float64List _end;
  final Float64List _contStart;
  final Float64List _scratch;

  void captureStart(double t) {
    value.converter.write(value.valueAt(t), _start);
    _contStart.setAll(0, _start);
  }

  void captureContinuation(double t) {
    value.converter.write(value.valueAt(t), _contStart);
  }

  void apply(double t, double mapped) {
    for (var i = 0; i < _n; i++) {
      _scratch[i] = _start[i] + (_end[i] - _start[i]) * mapped;
    }
    value.snap(t, value.converter.read(_scratch));
  }

  void applyContinuation(double t, double mapped, {required bool reversed}) {
    final dst = reversed ? _start : _end;
    for (var i = 0; i < _n; i++) {
      _scratch[i] = _contStart[i] + (dst[i] - _contStart[i]) * mapped;
    }
    value.snap(t, value.converter.read(_scratch));
  }

  void snapToPosition(double t, AnimatorPosition position) {
    switch (position) {
      case AnimatorPosition.start:
        value.snap(t, value.converter.read(_start));
      case AnimatorPosition.end:
        value.snap(t, value.converter.read(_end));
      case AnimatorPosition.current:
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
