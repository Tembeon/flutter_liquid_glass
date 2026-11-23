import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/keyframes.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/pose.dart';

/// Playback options for a [MotionSymbolEffect] added to [SymbolEffectMotion].
///
/// UIKit: `SymbolEffectOptions`.
@immutable
final class SymbolEffectOptions {
  /// Creates symbol effect options.
  const SymbolEffectOptions({
    this.speed = 1,
    this.repeatCount,
    this.repeating = false,
    this.animated = true,
  }) : assert(speed > 0, 'speed must be positive'),
       assert(
         repeatCount == null || repeatCount >= 1,
         'repeatCount must be at least 1',
       );

  /// Playback speed multiplier (`speed = 2` plays in half the time).
  final double speed;

  /// Finite number of back-to-back repetitions for discrete or repeating
  /// effects, or null for the effect's default behavior.
  final int? repeatCount;

  /// Whether a discrete or cyclic effect repeats indefinitely until removed.
  final bool repeating;

  /// Whether state transitions (such as [ScaleSymbolEffect] or
  /// [DisappearSymbolEffect]) animate; note that discrete effects like
  /// [BounceSymbolEffect] still play in full when `animated` is false,
  /// matching UIKit.
  final bool animated;

  @override
  bool operator ==(Object other) =>
      other is SymbolEffectOptions &&
      other.speed == speed &&
      other.repeatCount == repeatCount &&
      other.repeating == repeating &&
      other.animated == animated;

  @override
  int get hashCode => Object.hash(speed, repeatCount, repeating, animated);

  @override
  String toString() =>
      'SymbolEffectOptions(speed: $speed, repeatCount: $repeatCount, '
      'repeating: $repeating, animated: $animated)';
}

/// An SF Symbol-style animation effect played by [SymbolEffectMotion] and
/// `MotionSymbol`.
///
/// Durations, peak amplitudes, and queueing/stacking/removal completion
/// semantics match iOS 27 `UIImageView.addSymbolEffect(_:options:animated:)`.
/// `[approx]` Exact internal RenderBox curves between measured peak timestamps
/// are approximated with cubic/eased keyframes.
@immutable
sealed class MotionSymbolEffect {
  /// Creates a symbol effect.
  const MotionSymbolEffect();

  _Play get _play;

  /// The length in seconds of one play of a one-shot effect, one turn of a
  /// repeating one, or the way in of a held one.
  double get cycleDuration;

  // A held effect's way back out when removed.
  double get _outDuration => cycleDuration;

  // The held effect an effect of this kind ends at once.
  Type? get _ends => null;

  /// Evaluates the effect's contribution at normalized cycle progress `u`
  /// (`0..1`).
  MotionPose evaluate(double u);
}

enum _Play {
  /// One cycle, or a counted or endless run of them, queued after the one
  /// of its type still playing; [SymbolEffectMotion.removeAll] lets it
  /// finish.
  once,

  /// Cycles, endless or counted, replacing the run of its type.
  cycles,

  /// In, held while active, and out when removed, replacing the run of its
  /// type.
  held,
}

/// Direction of a [BounceSymbolEffect] or [ScaleSymbolEffect].
enum SymbolEffectDirection {
  /// Scales upward (larger).
  up,

  /// Scales downward (smaller).
  down,
}

/// Discrete elastic bounce effect (`BounceSymbolEffect`).
///
/// Measured iOS 27 timing (`0.73 s`):
/// - `up`: `1 -> 1.246 @ 0.26 s -> 0.91 @ 0.50 s -> 1.0 @ 0.73 s`.
/// - `down`: `1 -> 0.754 @ 0.23 s -> 1.106 @ 0.45 s -> 1.0 @ 0.73 s`.
/// `[approx]` Curves between measured peaks use smooth cubic keyframes.
@immutable
final class BounceSymbolEffect extends MotionSymbolEffect {
  /// Creates a bounce effect scaling [direction] (up by default).
  const BounceSymbolEffect({this.direction = SymbolEffectDirection.up});

  /// Whether the first peak scales up or down.
  final SymbolEffectDirection direction;

  static const _cycle = 0.73;

  static const _upKeyframes = MotionKeyframes<double>(
    duration: _cycle,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.26 / _cycle, 1.246),
      KeyframeStop(0.50 / _cycle, 0.91),
      KeyframeStop(1, 1),
    ],
  );

  static const _downKeyframes = MotionKeyframes<double>(
    duration: _cycle,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.23 / _cycle, 0.754),
      KeyframeStop(0.45 / _cycle, 1.106),
      KeyframeStop(1, 1),
    ],
  );

  @override
  _Play get _play => _Play.once;

  @override
  double get cycleDuration => _cycle;

  @override
  MotionPose evaluate(double u) {
    final kf = direction == SymbolEffectDirection.up
        ? _upKeyframes
        : _downKeyframes;
    return MotionPose(scale: kf.valueAt(u * _cycle));
  }

  @override
  bool operator ==(Object other) =>
      other is BounceSymbolEffect && other.direction == direction;

  @override
  int get hashCode => Object.hash(BounceSymbolEffect, direction);

  @override
  String toString() => 'BounceSymbolEffect(direction: $direction)';
}

/// Discrete wiggle effect (`WiggleSymbolEffect`).
///
/// Measured iOS 27 timing (`0.97 s`): horizontal oscillation peaking at
/// `+5% @ 0.18 s`, `-4% @ 0.365 s`, `+2.5% @ 0.515 s`, `-2.5% @ 0.72 s`,
/// returning to `0` at `0.97 s`. `[approx]` Smooth cubic keyframes through
/// measured peaks.
@immutable
final class WiggleSymbolEffect extends MotionSymbolEffect {
  /// Creates a wiggle effect (horizontal by default; vertical when
  /// [horizontal] is false).
  const WiggleSymbolEffect({this.horizontal = true});

  /// Whether the oscillation is horizontal (true) or vertical (false).
  final bool horizontal;

  static const _cycle = 0.97;

  static const _keyframes = MotionKeyframes<double>(
    duration: _cycle,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 0),
      KeyframeStop(0.18 / _cycle, 0.05),
      KeyframeStop(0.365 / _cycle, -0.04),
      KeyframeStop(0.515 / _cycle, 0.025),
      KeyframeStop(0.72 / _cycle, -0.025),
      KeyframeStop(1, 0),
    ],
  );

  @override
  _Play get _play => _Play.once;

  @override
  double get cycleDuration => _cycle;

  @override
  MotionPose evaluate(double u) {
    final v = _keyframes.valueAt(u * _cycle);
    return MotionPose(
      offsetFraction: horizontal ? Offset(v, 0) : Offset(0, v),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WiggleSymbolEffect && other.horizontal == horizontal;

  @override
  int get hashCode => Object.hash(WiggleSymbolEffect, horizontal);

  @override
  String toString() => 'WiggleSymbolEffect(horizontal: $horizontal)';
}

/// Discrete full-turn rotation effect (`RotateSymbolEffect`).
///
/// Measured iOS 27 completion duration: `2.02 s` for one full eased rotation.
/// `[approx]` Uses ease-in-out over `2 * pi`.
@immutable
final class RotateSymbolEffect extends MotionSymbolEffect {
  /// Creates a rotation effect (clockwise by default).
  const RotateSymbolEffect({this.clockwise = true});

  /// Whether rotation runs clockwise (`+2*pi`) or counter-clockwise (`-2*pi`).
  final bool clockwise;

  @override
  _Play get _play => _Play.once;

  @override
  double get cycleDuration => 2.02;

  @override
  MotionPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    final angle = (clockwise ? 2 : -2) * math.pi * eased;
    return MotionPose(rotation: angle);
  }

  @override
  bool operator ==(Object other) =>
      other is RotateSymbolEffect && other.clockwise == clockwise;

  @override
  int get hashCode => Object.hash(RotateSymbolEffect, clockwise);

  @override
  String toString() => 'RotateSymbolEffect(clockwise: $clockwise)';
}

/// Indefinite scale effect (`ScaleSymbolEffect`) that grows to `1.246` (up)
/// or shrinks to `0.503` (down) over `0.27 s`, holds while active, and
/// returns to `1.0` over `0.28 s` when removed.
///
/// `[approx]` Uses ease-in-out for the transition to and from the held scale.
@immutable
final class ScaleSymbolEffect extends MotionSymbolEffect {
  /// Creates an indefinite scale effect.
  const ScaleSymbolEffect({this.direction = SymbolEffectDirection.up});

  /// Whether the symbol scales up (`1.246`) or down (`0.503`).
  final SymbolEffectDirection direction;

  /// Target held scale factor (`1.246` for up, `0.503` for down).
  double get targetScale =>
      direction == SymbolEffectDirection.up ? 1.246 : 0.503;

  @override
  _Play get _play => _Play.held;

  @override
  double get cycleDuration => 0.27;

  @override
  double get _outDuration => 0.28;

  @override
  MotionPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return MotionPose(scale: 1 + (targetScale - 1) * eased);
  }

  @override
  bool operator ==(Object other) =>
      other is ScaleSymbolEffect && other.direction == direction;

  @override
  int get hashCode => Object.hash(ScaleSymbolEffect, direction);

  @override
  String toString() => 'ScaleSymbolEffect(direction: $direction)';
}

/// Indefinite repeating breathe effect (`BreatheSymbolEffect`).
///
/// Measured iOS 27 cycle (`3.02 s`): scales `1 -> 1.20` over `1.34 s`, holds
/// ~`0.34 s`, eases back down to `1.0`. `[approx]` Ease curves approximated.
@immutable
final class BreatheSymbolEffect extends MotionSymbolEffect {
  /// Creates a repeating breathe effect.
  const BreatheSymbolEffect();

  static const _cycle = 3.02;

  static const _keyframes = MotionKeyframes<double>(
    duration: _cycle,
    stops: [
      KeyframeStop(0, 1, curve: Curves.easeInOut),
      KeyframeStop(1.34 / _cycle, 1.20),
      KeyframeStop(1.68 / _cycle, 1.20, curve: Curves.easeInOut),
      KeyframeStop(1, 1),
    ],
  );

  @override
  _Play get _play => _Play.cycles;

  @override
  double get cycleDuration => _cycle;

  @override
  MotionPose evaluate(double u) =>
      MotionPose(scale: _keyframes.valueAt(u * _cycle));

  @override
  bool operator ==(Object other) => other is BreatheSymbolEffect;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BreatheSymbolEffect()';
}

/// Indefinite repeating opacity pulse effect (`PulseSymbolEffect`).
///
/// Measured iOS 27 cycle duration: `2.09 s`. `[approx]` Opacity dips to `0.35`
/// and returns to `1.0` smoothly.
@immutable
final class PulseSymbolEffect extends MotionSymbolEffect {
  /// Creates a repeating pulse effect.
  const PulseSymbolEffect({this.minOpacity = 0.35})
    : assert(
        minOpacity >= 0 && minOpacity <= 1,
        'minOpacity is an opacity, from 0 to 1',
      );

  /// Minimum opacity at the trough of each pulse (`0.35` `[approx]`).
  final double minOpacity;

  @override
  _Play get _play => _Play.cycles;

  @override
  double get cycleDuration => 2.09;

  @override
  MotionPose evaluate(double u) {
    final wave = (1 - math.cos(2 * math.pi * u.clamp(0.0, 1.0))) / 2;
    return MotionPose(opacity: 1 - (1 - minOpacity) * wave);
  }

  @override
  bool operator ==(Object other) =>
      other is PulseSymbolEffect && other.minOpacity == minOpacity;

  @override
  int get hashCode => Object.hash(PulseSymbolEffect, minOpacity);

  @override
  String toString() => 'PulseSymbolEffect(minOpacity: $minOpacity)';
}

// The scale a hidden symbol shrinks to and grows from, measured on iOS 27.
const double _hiddenScale = 0.78;

/// Transition effect hiding a symbol (`DisappearSymbolEffect`).
///
/// Measured iOS 27 timing ([cycleDuration]): shrinks to the hidden symbol's
/// scale while fading out.
/// `[approx]` Uses ease-in-out.
@immutable
final class DisappearSymbolEffect extends MotionSymbolEffect {
  /// Creates a disappear effect.
  const DisappearSymbolEffect();

  @override
  _Play get _play => _Play.held;

  @override
  double get cycleDuration => 0.21;

  @override
  MotionPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return MotionPose(
      scale: 1 + (_hiddenScale - 1) * eased,
      opacity: 1 - eased,
    );
  }

  @override
  bool operator ==(Object other) => other is DisappearSymbolEffect;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'DisappearSymbolEffect()';
}

/// Transition effect revealing a hidden symbol (`AppearSymbolEffect`).
///
/// Measured iOS 27 timing ([cycleDuration]): grows from the hidden symbol's
/// scale to full size while fading in. `[approx]` Uses ease-in-out.
@immutable
final class AppearSymbolEffect extends MotionSymbolEffect {
  /// Creates an appear effect.
  const AppearSymbolEffect();

  @override
  _Play get _play => _Play.once;

  @override
  double get cycleDuration => 0.28;

  @override
  Type? get _ends => DisappearSymbolEffect;

  @override
  MotionPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return MotionPose(
      scale: _hiddenScale + (1 - _hiddenScale) * eased,
      opacity: eased,
    );
  }

  @override
  bool operator ==(Object other) => other is AppearSymbolEffect;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppearSymbolEffect()';
}

/// Pure motion engine scheduling and composing [MotionSymbolEffect]s with
/// UIKit's exact queueing, concurrent stacking, and completion semantics.
///
/// - Adding the same discrete effect type while one is running **queues** it
///   back-to-back instead of restarting it.
/// - Different effect types **stack concurrently** (scales and opacities
///   multiply; offsets and rotations add).
/// - Removing a repeating effect (an indefinite one such as
///   [BreatheSymbolEffect], or a discrete one added with
///   [SymbolEffectOptions.repeating]) fires the removal completion
///   immediately with `isFinished = false`, lets the running cycle finish,
///   and fires the add completion with `isFinished = true` at cycle end.
/// - [removeAll] animates indefinite/disappear effects back and ends
///   repeating discrete ones at their cycle end, without aborting in-flight
///   discrete effects.
/// - An effect replaced or cut short before its completion fires it with
///   `isFinished = false`.
final class SymbolEffectMotion extends Motion {
  /// Creates a symbol effect scheduler.
  SymbolEffectMotion({super.clock});

  final Map<Type, List<_Cycles>> _queues = {};
  final Map<Type, _Run> _running = {};

  late final ValueListenable<MotionPose> _pose = select((m) => m.pose);

  /// The composed pose, for a `MotionTransition`'s `pose`.
  ValueListenable<MotionPose> get poseListenable => _pose;

  /// The composed symbol pose at [now].
  MotionPose get pose => poseAt(now);

  /// The composed symbol pose at explicit time [t].
  MotionPose poseAt(double t) {
    var pose = MotionPose.identity;
    for (final queue in _queues.values) {
      pose = pose.compose(queue.first.poseAt(t));
    }
    for (final run in _running.values) {
      pose = pose.compose(run.poseAt(t));
    }
    return pose;
  }

  /// Adds [effect] at time [t] with [options] and optional [onComplete]
  /// (`isFinished` matches UIKit `UISymbolEffectCompletionContext.isFinished`).
  void add(
    double t,
    MotionSymbolEffect effect, {
    SymbolEffectOptions options = const SymbolEffectOptions(),
    void Function(bool isFinished)? onComplete,
  }) {
    advance(t);
    if (effect._ends case final ended?) {
      _running.remove(ended)?.interrupt(removed: false);
    }
    final type = effect.runtimeType;
    final cycle = effect.cycleDuration / options.speed;
    switch (effect._play) {
      case _Play.once:
        final queue = _queues.putIfAbsent(type, () => []);
        queue.add(
          _Cycles(
            effect,
            start: queue.isEmpty ? t : queue.last.end,
            cycle: cycle,
            count: options.repeating ? null : (options.repeatCount ?? 1),
            onComplete: onComplete,
          ),
        );
      case _Play.cycles:
        _running[type]?.interrupt(removed: false);
        _running[type] = _Cycles(
          effect,
          start: t,
          cycle: cycle,
          count: options.repeatCount,
          onComplete: onComplete,
        );
      case _Play.held:
        _running[type]?.interrupt(removed: false);
        final held = _running[type] = _Held(
          effect,
          start: t,
          duration: options.animated ? cycle : 0,
          onAddComplete: onComplete,
        );
        if (!options.animated) held.completeAdd();
    }
    changed();
  }

  /// Removes an active effect of type [E] at time [t].
  ///
  /// If no effect of type [E] is active, invokes [onComplete] immediately with
  /// `false`. For repeating effects (indefinite ones such as
  /// [BreatheSymbolEffect], or discrete ones added with
  /// [SymbolEffectOptions.repeating]), invokes [onComplete] immediately with
  /// `false` and stops at the end of the current cycle (where the original
  /// add completion fires with `true`).
  void remove<E extends MotionSymbolEffect>(
    double t, {
    bool animated = true,
    void Function(bool isFinished)? onComplete,
  }) {
    advance(t);
    switch (_running[E]) {
      case null:
        if (_stopRepeating(E, t)) changed();
        onComplete?.call(false);
      case final _Cycles cycles:
        onComplete?.call(false);
        cycles.stopAtCycleEnd(t);
        changed();
      case final _Held held when !animated:
        _running.remove(E);
        held.interrupt(removed: true);
        onComplete?.call(true);
        changed();
      case final _Held held:
        held.beginRemoval(t, onComplete: onComplete);
        changed();
    }
  }

  /// Removes all indefinite and disappear effects at [t], animating them back
  /// when [animated] is true, and ends repeating discrete effects at their
  /// cycle end. Other in-flight discrete effects continue to completion,
  /// matching UIKit's `removeAllSymbolEffects`.
  void removeAll(double t, {bool animated = true}) {
    advance(t);
    for (final type in _queues.keys) {
      _stopRepeating(type, t);
    }
    for (final type in List<Type>.of(_running.keys)) {
      switch (_running[type]!) {
        case final _Cycles cycles:
          cycles.stopAtCycleEnd(t);
        case final _Held held when !animated:
          _running.remove(type);
          held.interrupt(removed: true);
        case final _Held held:
          held.beginRemoval(t);
      }
    }
    changed();
  }

  bool _stopRepeating(Type type, double t) {
    final queue = _queues[type];
    if (queue == null) return false;
    var stopped = false;
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].count == null && queue[i].stopAtCycleEnd(t)) {
        stopped = true;
        for (var j = i + 1; j < queue.length; j++) {
          queue[j].start = queue[j - 1].end;
        }
      }
    }
    return stopped;
  }

  // A completion may add or remove effects, so runs leave before their
  // completions fire.
  @override
  void didAdvance(double t) {
    if (!_dueAt(t)) return;
    for (final type in List<Type>.of(_queues.keys)) {
      final queue = _queues[type]!;
      while (queue.isNotEmpty && queue.first.dueAt(t)) {
        queue.removeAt(0).complete(finished: true);
      }
      if (queue.isEmpty) _queues.remove(type);
    }
    for (final type in List<Type>.of(_running.keys)) {
      final run = _running[type];
      if (run == null || !run.dueAt(t)) continue;
      if (run.leavesAt(t)) _running.remove(type);
      run.fireDue(t);
    }
  }

  bool _dueAt(double t) {
    for (final queue in _queues.values) {
      if (queue.first.dueAt(t)) return true;
    }
    for (final run in _running.values) {
      if (run.dueAt(t)) return true;
    }
    return false;
  }

  @override
  double? restTime([double? tolerance]) {
    final parts = super.restTime(tolerance);
    if (parts == null) return null;
    var end = parts;
    for (final queue in _queues.values) {
      end = math.max(end, queue.last.restTime);
    }
    for (final run in _running.values) {
      end = math.max(end, run.restTime);
    }
    return end;
  }

  @override
  bool restsAt(double t, [double? tolerance]) {
    if (!super.restsAt(t, tolerance)) return false;
    for (final queue in _queues.values) {
      if (t < queue.last.restTime) return false;
    }
    for (final run in _running.values) {
      if (t < run.restTime) return false;
    }
    return true;
  }
}

sealed class _Run {
  _Run(this.effect, {required this.start});

  final MotionSymbolEffect effect;
  double start;

  MotionPose poseAt(double t);

  // When the run next stops changing: infinite while it plays on, negative
  // infinity while it holds.
  double get restTime;

  bool dueAt(double t);

  bool leavesAt(double t);

  void fireDue(double t);

  void interrupt({required bool removed});
}

final class _Cycles extends _Run {
  _Cycles(
    super.effect, {
    required super.start,
    required this.cycle,
    required this.count,
    required this.onComplete,
  });

  final double cycle;
  final int? count;
  final void Function(bool isFinished)? onComplete;
  double? _stopAt;
  bool _completed = false;

  double get end =>
      _stopAt ?? (count == null ? double.infinity : start + cycle * count!);

  @override
  double get restTime => end;

  bool stopAtCycleEnd(double t) {
    if (_stopAt != null) return false;
    final cycles = (math.max(0, t - start) / cycle).floor();
    _stopAt = start + (cycles + 1) * cycle;
    return true;
  }

  @override
  MotionPose poseAt(double t) {
    if (t <= start) return MotionPose.identity;
    if (t >= end) return effect.evaluate(1);
    return effect.evaluate(((t - start) / cycle) % 1.0);
  }

  @override
  bool dueAt(double t) => t >= end;

  @override
  bool leavesAt(double t) => dueAt(t);

  @override
  void fireDue(double t) => complete(finished: true);

  void complete({required bool finished}) {
    if (_completed) return;
    _completed = true;
    onComplete?.call(finished);
  }

  @override
  void interrupt({required bool removed}) => complete(finished: false);
}

final class _Held extends _Run {
  _Held(
    super.effect, {
    required super.start,
    required double duration,
    required this.onAddComplete,
  }) : _in = duration;

  final double _in;
  final void Function(bool isFinished)? onAddComplete;

  bool _addCompleted = false;
  bool _removing = false;
  double _removeStart = 0;
  double _removeFromProgress = 1;
  void Function(bool isFinished)? _onRemoveComplete;

  double get _out => effect._outDuration;

  @override
  double get restTime {
    if (_removing) return _removeStart + _out;
    if (_addCompleted) return double.negativeInfinity;
    return start + _in;
  }

  void completeAdd() {
    if (_addCompleted) return;
    _addCompleted = true;
    onAddComplete?.call(true);
  }

  /// Fires what is still owed when the effect leaves early: the add
  /// completion unfinished, and a removal under way as [removed].
  @override
  void interrupt({required bool removed}) {
    if (!_addCompleted) {
      _addCompleted = true;
      onAddComplete?.call(false);
    }
    final onRemove = _onRemoveComplete;
    _onRemoveComplete = null;
    onRemove?.call(removed);
  }

  void beginRemoval(double t, {void Function(bool isFinished)? onComplete}) {
    _removeFromProgress = _removing ? _outProgressAt(t) : _inProgressAt(t);
    _removing = true;
    _removeStart = t;
    if (onComplete != null) {
      final previous = _onRemoveComplete;
      _onRemoveComplete = onComplete;
      previous?.call(false);
    }
  }

  double _outProgressAt(double t) {
    final out = _out;
    if (out <= 0) return 0;
    final frac = ((t - _removeStart) / out).clamp(0.0, 1.0);
    return _removeFromProgress * (1 - frac);
  }

  double _inProgressAt(double t) {
    if (_in <= 0) return 1;
    return ((t - start) / _in).clamp(0.0, 1.0);
  }

  @override
  MotionPose poseAt(double t) =>
      effect.evaluate(_removing ? _outProgressAt(t) : _inProgressAt(t));

  bool _addDueAt(double t) => !_addCompleted && t >= start + _in;

  @override
  bool dueAt(double t) => _addDueAt(t) || leavesAt(t);

  @override
  bool leavesAt(double t) => _removing && t >= _removeStart + _out;

  @override
  void fireDue(double t) {
    if (_addDueAt(t)) completeAdd();
    if (leavesAt(t)) {
      final onRemove = _onRemoveComplete;
      _onRemoveComplete = null;
      onRemove?.call(true);
    }
  }
}
