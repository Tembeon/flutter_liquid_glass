import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/converter.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/tracker.dart';

/// How a [MotionKeyframes] sequence interpolates between consecutive stops.
///
/// UIKit: `CAAnimationCalculationMode` (`linear`, `discrete`, `cubic`).
enum KeyframeMode {
  /// Interpolates linearly (or with each stop's [KeyframeStop.curve]) between
  /// consecutive stops.
  linear,

  /// Holds each stop's value until the normalized time reaches the next stop.
  discrete,

  /// Passes a smooth Catmull-Rom cubic spline through the stops.
  cubic,
}

/// A single stop in a [MotionKeyframes] sequence.
@immutable
final class KeyframeStop<T> {
  /// Creates a stop at normalized [time] in `0..1` with [value].
  ///
  /// When [MotionKeyframes.mode] is [KeyframeMode.linear], [curve] eases the
  /// segment from this stop to the next stop (linear when null).
  const KeyframeStop(this.time, this.value, {this.curve})
    : assert(time >= 0 && time <= 1, 'stop time must be in 0..1');

  /// Normalized position in the cycle, `0..1`.
  final double time;

  /// The value at [time].
  final T value;

  /// Optional easing curve for the segment leaving this stop toward the next.
  final Curve? curve;

  @override
  bool operator ==(Object other) =>
      other is KeyframeStop<T> &&
      other.time == time &&
      other.value == value &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(time, value, curve);

  @override
  String toString() =>
      'KeyframeStop<$T>($time, $value'
      '${curve != null ? ', curve: $curve' : ''})';
}

/// A declarative keyframe timeline of values of type [T] over [duration]
/// seconds per cycle.
///
/// UIKit: `CAKeyframeAnimation` / `UIView.animateKeyframes`.
/// SwiftUI: `KeyframeTrack`.
@immutable
final class MotionKeyframes<T> {
  /// Creates a keyframe sequence over [duration] seconds per cycle.
  const MotionKeyframes({
    required this.duration,
    required this.stops,
    this.mode = KeyframeMode.linear,
    this.curve = Curves.linear,
    this.repeatCount = 1,
    this.autoreverses = false,
    this.converter,
  }) : assert(duration > 0, 'duration must be positive'),
       assert(repeatCount > 0, 'repeatCount must be positive');

  /// Duration of one forward cycle, in seconds.
  final double duration;

  /// Ordered keyframe stops with times in `0..1`.
  final List<KeyframeStop<T>> stops;

  /// How consecutive stops are joined.
  final KeyframeMode mode;

  /// Whole-cycle timing function applied to normalized cycle progress
  /// (defaults to linear; `UIView.animateKeyframes` uses ease-in-out).
  final Curve curve;

  /// Number of cycles to play, or [double.infinity] to repeat forever.
  final double repeatCount;

  /// Whether odd cycles play backward from `1` to `0`.
  final bool autoreverses;

  /// Optional converter used to interpolate [T] components; defaults to
  /// `MotionConverter.of<T>()` for non-discrete modes.
  final MotionConverter<T>? converter;

  /// Total duration across all cycles, or [double.infinity] when repeating
  /// indefinitely.
  double get totalDuration =>
      repeatCount.isInfinite ? double.infinity : duration * repeatCount;

  /// Normalized cycle position in `0..1` for [elapsed] seconds since start.
  double normalizedTimeAt(double elapsed) {
    if (elapsed <= 0) return 0;
    final total = totalDuration;
    final clamped = elapsed >= total ? total : elapsed;
    final rawCycles = clamped / duration;
    final double cycleFraction;
    final int cycleIndex;
    if (!repeatCount.isInfinite && clamped >= total) {
      cycleIndex = (repeatCount.ceil() - 1).clamp(0, 1 << 30);
      final remainder = repeatCount - repeatCount.floor();
      cycleFraction = remainder > 0 ? remainder : 1.0;
    } else {
      cycleIndex = rawCycles.floor();
      cycleFraction = rawCycles - cycleIndex;
    }
    final directed = autoreverses && cycleIndex.isOdd
        ? 1.0 - cycleFraction
        : cycleFraction;
    return curve.transform(directed.clamp(0.0, 1.0));
  }

  /// Evaluates the sequence at [elapsed] seconds since start.
  T valueAt(double elapsed, {MotionConverter<T>? converter}) {
    if (stops.isEmpty) {
      throw StateError('MotionKeyframes requires at least one stop.');
    }
    if (stops.length == 1) return stops.first.value;
    final u = normalizedTimeAt(elapsed);
    if (u <= stops.first.time) return stops.first.value;
    if (u >= stops.last.time) return stops.last.value;

    var index = 0;
    for (var i = 0; i < stops.length - 1; i++) {
      if (u >= stops[i].time) {
        index = i;
      } else {
        break;
      }
    }

    if (mode == KeyframeMode.discrete) {
      return stops[index].value;
    }

    final a = stops[index];
    final b = stops[index + 1];
    final span = b.time - a.time;
    final local = span <= 0 ? 1.0 : ((u - a.time) / span).clamp(0.0, 1.0);
    final conv = converter ?? this.converter ?? MotionConverter.of<T>();
    final n = conv.dimensions;

    if (mode == KeyframeMode.linear) {
      final eased = a.curve?.transform(local) ?? local;
      final va = Float64List(n);
      final vb = Float64List(n);
      final out = Float64List(n);
      conv.write(a.value, va);
      conv.write(b.value, vb);
      for (var i = 0; i < n; i++) {
        out[i] = va[i] + (vb[i] - va[i]) * eased;
      }
      return conv.read(out);
    }

    // Catmull-Rom cubic Hermite interpolation over stops[index-1..index+2].
    final prev = stops[index > 0 ? index - 1 : index];
    final next = stops[index + 2 < stops.length ? index + 2 : index + 1];
    final p0 = Float64List(n);
    final p1 = Float64List(n);
    final p2 = Float64List(n);
    final p3 = Float64List(n);
    final out = Float64List(n);
    conv.write(prev.value, p0);
    conv.write(a.value, p1);
    conv.write(b.value, p2);
    conv.write(next.value, p3);

    final t = local;
    final t2 = t * t;
    final t3 = t2 * t;
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;

    for (var i = 0; i < n; i++) {
      final m1 = index > 0 ? 0.5 * (p2[i] - p0[i]) : (p2[i] - p1[i]);
      final m2 = index + 2 < stops.length
          ? 0.5 * (p3[i] - p1[i])
          : (p2[i] - p1[i]);
      out[i] = h00 * p1[i] + h10 * m1 + h01 * p2[i] + h11 * m2;
    }
    return conv.read(out);
  }

  @override
  bool operator ==(Object other) =>
      other is MotionKeyframes<T> &&
      other.duration == duration &&
      listEquals(other.stops, stops) &&
      other.mode == mode &&
      other.curve == curve &&
      other.repeatCount == repeatCount &&
      other.autoreverses == autoreverses &&
      other.converter == converter;

  @override
  int get hashCode => Object.hash(
    duration,
    Object.hashAll(stops),
    mode,
    curve,
    repeatCount,
    autoreverses,
    converter,
  );

  @override
  String toString() =>
      'MotionKeyframes<$T>(duration: $duration, stops: ${stops.length}, '
      'mode: $mode)';
}

/// A live [MotionPart] and [ValueListenable] playing a [MotionKeyframes]
/// sequence on a [MotionClock] or owning `Motion`.
final class KeyframeValue<T> extends MotionPart implements ValueListenable<T> {
  /// Creates a keyframe player for [keyframes].
  ///
  /// When `playing` is true (default), playback begins at `startTime`.
  KeyframeValue(
    this._keyframes, {
    this._converter,
    MotionClock? clock,
    this._playing = true,
    this._startTime = 0,
  }) : _givenClock = clock;

  MotionKeyframes<T> _keyframes;
  final MotionConverter<T>? _converter;
  final MotionClock? _givenClock;
  final List<VoidCallback> _listeners = [];
  final List<VoidCallback> _renderListeners = [];
  late final _KeyframeFollower<T> _follower = _KeyframeFollower<T>(this);

  bool _playing;
  double _startTime;
  double _pausedElapsed = 0;

  /// The active keyframe sequence.
  MotionKeyframes<T> get keyframes => _keyframes;

  /// The clock driving playback when listened to.
  MotionClock get clock => _givenClock ?? owner?.clock ?? MotionClock.instance;

  /// Whether the sequence is currently playing.
  bool get isPlaying => _playing;

  /// Starts or restarts playback at [t] (plus optional [delay] seconds),
  /// optionally replacing [keyframes].
  void play(
    double t, {
    MotionKeyframes<T>? keyframes,
    double delay = 0,
  }) {
    if (keyframes != null) _keyframes = keyframes;
    _playing = true;
    _startTime = t + delay;
    _pausedElapsed = 0;
    _follow();
  }

  /// Pauses playback at [t], freezing the elapsed progress.
  void pause(double t) {
    if (!_playing) return;
    _pausedElapsed = math.max(0, t - _startTime);
    _playing = false;
    _follow();
  }

  /// Resumes playback from the paused position at [t].
  void resume(double t) {
    if (_playing) return;
    _playing = true;
    _startTime = t - _pausedElapsed;
    _follow();
  }

  /// Resets the sequence to `elapsed = 0` at [t] (staying playing or paused).
  void reset(double t) {
    _startTime = t;
    _pausedElapsed = 0;
    _follow();
  }

  /// Seeks the sequence to [elapsed] seconds at time [t].
  void seek(double t, double elapsed) {
    final clamped = elapsed < 0 ? 0.0 : elapsed;
    _pausedElapsed = clamped;
    _startTime = t - clamped;
    _follow();
  }

  double _elapsedAt(double t) =>
      _playing ? math.max(0, t - _startTime) : _pausedElapsed;

  /// The value at time [t].
  T valueAt(double t) =>
      _keyframes.valueAt(_elapsedAt(t), converter: _converter);

  /// The current value at the clock's time.
  @override
  T get value {
    ReadTracker.read(this);
    return valueAt(clock.now);
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (_playing) clock.follow(_follower);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _unfollowIfAlone();
  }

  /// Adds a render listener notified during the frame's resolve phase as well
  /// as publish.
  void addRenderListener(VoidCallback listener) {
    _renderListeners.add(listener);
    if (_playing) clock.follow(_follower);
  }

  /// Removes a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener) {
    _renderListeners.remove(listener);
    _unfollowIfAlone();
  }

  void _unfollowIfAlone() {
    if (_listeners.isEmpty && _renderListeners.isEmpty) {
      clock.unfollow(_follower);
    }
  }

  void _follow() {
    changed();
    if (_listeners.isNotEmpty || _renderListeners.isNotEmpty) {
      clock.follow(_follower);
    }
  }

  @override
  double? restTime([double? tolerance]) {
    if (!_playing) return double.negativeInfinity;
    final total = _keyframes.totalDuration;
    if (total.isInfinite) return double.infinity;
    return _startTime + total;
  }

  @override
  bool restsAt(double t, [double? tolerance]) {
    if (!_playing) return true;
    if (t < _startTime) return true;
    final total = _keyframes.totalDuration;
    if (total.isInfinite) return false;
    return t >= _startTime + total;
  }

  @override
  void restFrom(double t) {
    if (!_playing) return;
    final total = _keyframes.totalDuration;
    if (total.isInfinite || t < _startTime + total) return;
    _pausedElapsed = total;
    _playing = false;
  }

  @override
  double? get nextDue {
    if (!_playing) return null;
    final now = owner?.now ?? double.negativeInfinity;
    return _startTime > now ? _startTime : null;
  }

  void _publish({required bool widgets}) {
    _notify(_renderListeners);
    if (widgets) _notify(_listeners);
  }

  static void _notify(List<VoidCallback> listeners) {
    if (listeners.isEmpty) return;
    for (final listener in List<VoidCallback>.of(listeners)) {
      guardMotion(listener, 'while notifying a KeyframeValue listener');
    }
  }
}

final class _KeyframeFollower<T> implements MotionFollowed {
  _KeyframeFollower(this._host);

  final KeyframeValue<T> _host;
  double? _wakeTime;

  @override
  double? get wakeTime => _wakeTime;

  @override
  bool get hasWidgetFollowers => _host._listeners.isNotEmpty;

  @override
  bool stepTo(double time) {
    if (!_host._playing) {
      _wakeTime = null;
      return false;
    }
    if (time < _host._startTime) {
      _wakeTime = _host._startTime;
      return true;
    }
    _wakeTime = null;
    final total = _host._keyframes.totalDuration;
    if (total.isInfinite || time < _host._startTime + total) return true;
    _host.restFrom(_host._startTime + total);
    return false;
  }

  @override
  void publish({required bool widgets}) => _host._publish(widgets: widgets);
}
