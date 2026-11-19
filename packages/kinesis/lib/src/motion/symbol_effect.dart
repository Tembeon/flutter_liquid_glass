import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/keyframes.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/part.dart';

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

/// Composed visual transform produced by [SymbolEffectMotion] at a given time.
@immutable
final class SymbolEffectPose {
  /// Creates a symbol pose.
  const SymbolEffectPose({
    this.scale = 1,
    this.offsetFraction = Offset.zero,
    this.rotation = 0,
    this.opacity = 1,
  });

  /// Identity pose (no active effect).
  static const SymbolEffectPose identity = SymbolEffectPose();

  /// Multiplicative uniform scale.
  final double scale;

  /// Translation as a fraction of the symbol's width and height (e.g. `0.05`
  /// shifts right by 5% of the symbol's width).
  final Offset offsetFraction;

  /// Clockwise rotation, in radians.
  final double rotation;

  /// Multiplicative opacity in `0..1`.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is SymbolEffectPose &&
      other.scale == scale &&
      other.offsetFraction == offsetFraction &&
      other.rotation == rotation &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(scale, offsetFraction, rotation, opacity);

  @override
  String toString() =>
      'SymbolEffectPose(scale: $scale, offsetFraction: $offsetFraction, '
      'rotation: $rotation, opacity: $opacity)';
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

  /// Whether this effect is a discrete one-shot effect (queues when re-added,
  /// not aborted by [SymbolEffectMotion.removeAll]).
  bool get isDiscrete;

  /// Whether this effect runs a repeating cycle while active (e.g. breathe,
  /// pulse).
  bool get isRepeatingIndefinite => false;

  /// Nominal single-cycle duration in seconds.
  double get cycleDuration;

  /// Duration in seconds used when animating removal of a stateful effect.
  ///
  /// Defaults to [cycleDuration].
  double get removeDuration => cycleDuration;

  /// Evaluates the effect's contribution at normalized cycle progress `u`
  /// (`0..1`).
  SymbolEffectPose evaluate(double u);
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

  static const _upKeyframes = MotionKeyframes<double>(
    duration: 0.73,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.26 / 0.73, 1.246),
      KeyframeStop(0.50 / 0.73, 0.91),
      KeyframeStop(1, 1),
    ],
  );

  static const _downKeyframes = MotionKeyframes<double>(
    duration: 0.73,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.23 / 0.73, 0.754),
      KeyframeStop(0.45 / 0.73, 1.106),
      KeyframeStop(1, 1),
    ],
  );

  @override
  bool get isDiscrete => true;

  @override
  double get cycleDuration => 0.73;

  @override
  SymbolEffectPose evaluate(double u) {
    final kf = direction == SymbolEffectDirection.up
        ? _upKeyframes
        : _downKeyframes;
    return SymbolEffectPose(scale: kf.valueAt(u * cycleDuration));
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

  static const _keyframes = MotionKeyframes<double>(
    duration: 0.97,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 0),
      KeyframeStop(0.18 / 0.97, 0.05),
      KeyframeStop(0.365 / 0.97, -0.04),
      KeyframeStop(0.515 / 0.97, 0.025),
      KeyframeStop(0.72 / 0.97, -0.025),
      KeyframeStop(1, 0),
    ],
  );

  @override
  bool get isDiscrete => true;

  @override
  double get cycleDuration => 0.97;

  @override
  SymbolEffectPose evaluate(double u) {
    final v = _keyframes.valueAt(u * cycleDuration);
    return SymbolEffectPose(
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
  bool get isDiscrete => true;

  @override
  double get cycleDuration => 2.02;

  @override
  SymbolEffectPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    final angle = (clockwise ? 2 : -2) * math.pi * eased;
    return SymbolEffectPose(rotation: angle);
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
  bool get isDiscrete => false;

  @override
  double get cycleDuration => 0.27;

  @override
  double get removeDuration => 0.28;

  @override
  SymbolEffectPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return SymbolEffectPose(scale: 1 + (targetScale - 1) * eased);
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

  static const _keyframes = MotionKeyframes<double>(
    duration: 3.02,
    stops: [
      KeyframeStop(0, 1, curve: Curves.easeInOut),
      KeyframeStop(1.34 / 3.02, 1.20),
      KeyframeStop(1.68 / 3.02, 1.20, curve: Curves.easeInOut),
      KeyframeStop(1, 1),
    ],
  );

  @override
  bool get isDiscrete => false;

  @override
  bool get isRepeatingIndefinite => true;

  @override
  double get cycleDuration => 3.02;

  @override
  SymbolEffectPose evaluate(double u) =>
      SymbolEffectPose(scale: _keyframes.valueAt(u * cycleDuration));

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
  const PulseSymbolEffect({this.minOpacity = 0.35});

  /// Minimum opacity at the trough of each pulse (`0.35` `[approx]`).
  final double minOpacity;

  @override
  bool get isDiscrete => false;

  @override
  bool get isRepeatingIndefinite => true;

  @override
  double get cycleDuration => 2.09;

  @override
  SymbolEffectPose evaluate(double u) {
    final wave = (1 - math.cos(2 * math.pi * u.clamp(0.0, 1.0))) / 2;
    return SymbolEffectPose(opacity: 1 - (1 - minOpacity) * wave);
  }

  @override
  bool operator ==(Object other) =>
      other is PulseSymbolEffect && other.minOpacity == minOpacity;

  @override
  int get hashCode => Object.hash(PulseSymbolEffect, minOpacity);

  @override
  String toString() => 'PulseSymbolEffect(minOpacity: $minOpacity)';
}

/// Transition effect hiding a symbol (`DisappearSymbolEffect`).
///
/// Measured iOS 27 timing (`0.21 s`): shrinks to `0.78` while fading to `0`.
/// `[approx]` Uses ease-in-out.
@immutable
final class DisappearSymbolEffect extends MotionSymbolEffect {
  /// Creates a disappear effect.
  const DisappearSymbolEffect();

  @override
  bool get isDiscrete => false;

  @override
  double get cycleDuration => 0.21;

  @override
  SymbolEffectPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return SymbolEffectPose(scale: 1 - 0.22 * eased, opacity: 1 - eased);
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
/// Measured iOS 27 timing (`0.28 s`): grows from `0.78` to `1.0` while fading
/// in. `[approx]` Uses ease-in-out.
@immutable
final class AppearSymbolEffect extends MotionSymbolEffect {
  /// Creates an appear effect.
  const AppearSymbolEffect();

  @override
  bool get isDiscrete => true;

  @override
  double get cycleDuration => 0.28;

  @override
  SymbolEffectPose evaluate(double u) {
    final eased = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    return SymbolEffectPose(scale: 0.78 + 0.22 * eased, opacity: eased);
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
  SymbolEffectMotion({super.clock}) {
    _driver = own(_SymbolDriver(this));
  }

  late final _SymbolDriver _driver;
  final Map<Type, List<_ActiveDiscrete>> _discreteQueues = {};
  final Map<Type, _ActiveIndefinite> _indefinites = {};

  late final ValueListenable<double> _scale = select((m) => m.pose.scale);
  late final ValueListenable<double> _rotation = select((m) => m.pose.rotation);
  late final ValueListenable<double> _opacity = select((m) => m.pose.opacity);
  late final ValueListenable<Offset> _offsetFraction = select(
    (m) => m.pose.offsetFraction,
  );

  /// Reactive scale listenable for `MotionTransition`.
  ValueListenable<double> get scaleListenable => _scale;

  /// Reactive rotation listenable (radians) for `MotionTransition`.
  ValueListenable<double> get rotationListenable => _rotation;

  /// Reactive opacity listenable for `MotionTransition`.
  ValueListenable<double> get opacityListenable => _opacity;

  /// Reactive offset-fraction listenable for `MotionTransition`.
  ValueListenable<Offset> get offsetFractionListenable => _offsetFraction;

  /// The composed symbol pose at [now].
  SymbolEffectPose get pose => poseAt(now);

  /// The composed symbol pose at explicit time [t].
  SymbolEffectPose poseAt(double t) {
    var scale = 1.0;
    var offset = Offset.zero;
    var rotation = 0.0;
    var opacity = 1.0;

    for (final queue in _discreteQueues.values) {
      if (queue.isEmpty) continue;
      final head = queue.first;
      final contribution = head.evaluateAt(t);
      scale *= contribution.scale;
      offset += contribution.offsetFraction;
      rotation += contribution.rotation;
      opacity *= contribution.opacity;
    }

    for (final active in _indefinites.values) {
      final contribution = active.evaluateAt(t);
      scale *= contribution.scale;
      offset += contribution.offsetFraction;
      rotation += contribution.rotation;
      opacity *= contribution.opacity;
    }

    return SymbolEffectPose(
      scale: scale,
      offsetFraction: offset,
      rotation: rotation,
      opacity: opacity.clamp(0.0, 1.0),
    );
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
    if (effect is AppearSymbolEffect) {
      _indefinites.remove(DisappearSymbolEffect)?.interrupt(removed: false);
    }
    if (effect.isDiscrete) {
      final queue = _discreteQueues.putIfAbsent(effect.runtimeType, () => []);
      final startTime = queue.isEmpty ? t : queue.last.endTime;
      final count = options.repeating ? null : (options.repeatCount ?? 1);
      final cycle = effect.cycleDuration / options.speed;
      final item = _ActiveDiscrete(
        effect: effect,
        startTime: startTime,
        cycleDuration: cycle,
        repeatCount: count,
        onComplete: onComplete,
      );
      queue.add(item);
      _driver.markChanged();
      changed();
      return;
    }

    final cycle = effect.cycleDuration / options.speed;
    _indefinites[effect.runtimeType]?.interrupt(removed: false);
    if (effect.isRepeatingIndefinite) {
      final finiteCycles = options.repeatCount;
      _indefinites[effect.runtimeType] = _ActiveIndefinite.repeating(
        effect: effect,
        startTime: t,
        cycleDuration: cycle,
        finiteCycles: finiteCycles,
        onAddComplete: onComplete,
      );
    } else {
      final active = _ActiveIndefinite.stateful(
        effect: effect,
        startTime: t,
        duration: options.animated ? cycle : 0,
        onAddComplete: onComplete,
      );
      _indefinites[effect.runtimeType] = active;
      if (!options.animated) {
        active.fireAddComplete();
      }
    }
    _driver.markChanged();
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
    final active = _indefinites[E];
    if (active == null) {
      if (_stopRepeating(E, t)) {
        _driver.markChanged();
        changed();
      }
      onComplete?.call(false);
      return;
    }
    if (active.effect.isRepeatingIndefinite) {
      onComplete?.call(false);
      active.stopAtCycleEnd(t);
      _driver.markChanged();
      changed();
      return;
    }
    if (!animated) {
      _indefinites.remove(E)?.interrupt(removed: true);
      onComplete?.call(true);
      _driver.markChanged();
      changed();
      return;
    }
    active.beginRemoval(
      t,
      duration: active.effect.removeDuration,
      onComplete: onComplete,
    );
    _driver.markChanged();
    changed();
  }

  /// Removes all indefinite and disappear effects at [t], animating them back
  /// when [animated] is true, and ends repeating discrete effects at their
  /// cycle end. Other in-flight discrete effects continue to completion,
  /// matching UIKit's `removeAllSymbolEffects`.
  void removeAll(double t, {bool animated = true}) {
    advance(t);
    for (final type in List<Type>.of(_discreteQueues.keys)) {
      _stopRepeating(type, t);
    }
    final types = List<Type>.of(_indefinites.keys);
    for (final type in types) {
      final active = _indefinites[type]!;
      if (active.effect.isRepeatingIndefinite) {
        active.stopAtCycleEnd(t);
      } else if (!animated) {
        _indefinites.remove(type)!.interrupt(removed: true);
      } else {
        active.beginRemoval(t, duration: active.effect.removeDuration);
      }
    }
    _driver.markChanged();
    changed();
  }

  bool _stopRepeating(Type type, double t) {
    final queue = _discreteQueues[type];
    if (queue == null) return false;
    var stopped = false;
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].stopAtCycleEnd(t)) {
        stopped = true;
        for (var j = i + 1; j < queue.length; j++) {
          queue[j].startTime = queue[j - 1].endTime;
        }
      }
    }
    return stopped;
  }

  @override
  void didAdvance(double t) {
    final completedDiscrete = <Type>[];
    for (final entry in _discreteQueues.entries) {
      final queue = entry.value;
      while (queue.isNotEmpty && t >= queue.first.endTime) {
        final finished = queue.removeAt(0);
        finished.fireComplete(true);
      }
      if (queue.isEmpty) completedDiscrete.add(entry.key);
    }
    for (final type in completedDiscrete) {
      _discreteQueues.remove(type);
    }

    final completedIndefinite = <Type>[];
    for (final entry in _indefinites.entries) {
      final active = entry.value;
      if (active.didFinishAt(t)) {
        completedIndefinite.add(entry.key);
      }
    }
    for (final type in completedIndefinite) {
      _indefinites.remove(type);
    }
  }

  double? _restTime() {
    var end = double.negativeInfinity;
    for (final queue in _discreteQueues.values) {
      if (queue.isEmpty) continue;
      final last = queue.last;
      if (last.endTime.isInfinite) return double.infinity;
      end = math.max(end, last.endTime);
    }
    for (final active in _indefinites.values) {
      final activeEnd = active.restTime;
      if (activeEnd == null) continue;
      if (activeEnd.isInfinite) return double.infinity;
      end = math.max(end, activeEnd);
    }
    return end;
  }

  bool _restsAt(double t) {
    for (final queue in _discreteQueues.values) {
      if (queue.isNotEmpty && t < queue.last.endTime) return false;
    }
    for (final active in _indefinites.values) {
      if (!active.restsAt(t)) return false;
    }
    return true;
  }
}

final class _SymbolDriver extends MotionPart {
  _SymbolDriver(this._host);

  final SymbolEffectMotion _host;

  void markChanged() => changed();

  @override
  double? restTime([double? tolerance]) => _host._restTime();

  @override
  bool restsAt(double t, [double? tolerance]) => _host._restsAt(t);

  @override
  void restFrom(double t) {}

  @override
  double? get nextDue => null;
}

final class _ActiveDiscrete {
  _ActiveDiscrete({
    required this.effect,
    required this.startTime,
    required this.cycleDuration,
    required this.repeatCount,
    required this.onComplete,
  });

  final MotionSymbolEffect effect;
  double startTime;
  final double cycleDuration;
  final int? repeatCount;
  final void Function(bool isFinished)? onComplete;
  double? _stopAt;

  double get endTime =>
      _stopAt ??
      (repeatCount == null
          ? double.infinity
          : startTime + cycleDuration * repeatCount!);

  bool stopAtCycleEnd(double t) {
    if (repeatCount != null || _stopAt != null) return false;
    final cycles = (math.max(0, t - startTime) / cycleDuration).floor();
    _stopAt = startTime + (cycles + 1) * cycleDuration;
    return true;
  }

  SymbolEffectPose evaluateAt(double t) {
    if (t <= startTime) return SymbolEffectPose.identity;
    if (t >= endTime) return effect.evaluate(1);
    final elapsed = t - startTime;
    final u = (elapsed / cycleDuration) % 1.0;
    return effect.evaluate(u);
  }

  void fireComplete(bool isFinished) => onComplete?.call(isFinished);
}

final class _ActiveIndefinite {
  _ActiveIndefinite.stateful({
    required this.effect,
    required this.startTime,
    required this._duration,
    this.onAddComplete,
  }) : _isRepeating = false,
       _finiteCycles = null;

  _ActiveIndefinite.repeating({
    required this.effect,
    required this.startTime,
    required double cycleDuration,
    required this._finiteCycles,
    this.onAddComplete,
  }) : _isRepeating = true,
       _duration = cycleDuration;

  final MotionSymbolEffect effect;
  final double startTime;
  final bool _isRepeating;
  final double _duration;
  final int? _finiteCycles;
  final void Function(bool isFinished)? onAddComplete;

  bool _addCompleted = false;
  double? _stopAt;
  bool _removing = false;
  double _removeStart = 0;
  double _removeDuration = 0;
  double _removeFromProgress = 1;
  void Function(bool isFinished)? _onRemoveComplete;

  double? get _repeatLimit =>
      _stopAt ??
      (_finiteCycles != null ? startTime + _duration * _finiteCycles : null);

  double? get restTime {
    if (_isRepeating) return _repeatLimit ?? double.infinity;
    if (_removing) return _removeStart + _removeDuration;
    if (_addCompleted) return null;
    return startTime + _duration;
  }

  bool restsAt(double t) {
    final end = restTime;
    if (end == null) return true;
    if (end.isInfinite) return false;
    return t >= end;
  }

  void fireAddComplete() {
    if (_addCompleted) return;
    _addCompleted = true;
    onAddComplete?.call(true);
  }

  /// Fires what is still owed when the effect leaves early: the add
  /// completion unfinished, and a removal under way as [removed].
  void interrupt({required bool removed}) {
    if (!_addCompleted) {
      _addCompleted = true;
      onAddComplete?.call(false);
    }
    final onRemove = _onRemoveComplete;
    _onRemoveComplete = null;
    onRemove?.call(removed);
  }

  void stopAtCycleEnd(double t) {
    if (!_isRepeating || _stopAt != null) return;
    final elapsed = math.max(0, t - startTime);
    final completedCycles = (elapsed / _duration).floor();
    _stopAt = startTime + (completedCycles + 1) * _duration;
  }

  void beginRemoval(
    double t, {
    required double duration,
    void Function(bool isFinished)? onComplete,
  }) {
    _removeFromProgress = _removing ? _outProgressAt(t) : _inProgressAt(t);
    _removing = true;
    _removeStart = t;
    _removeDuration = duration;
    if (onComplete != null) {
      final previous = _onRemoveComplete;
      _onRemoveComplete = onComplete;
      previous?.call(false);
    }
  }

  double _outProgressAt(double t) {
    if (_removeDuration <= 0) return 0;
    final frac = ((t - _removeStart) / _removeDuration).clamp(0.0, 1.0);
    return _removeFromProgress * (1 - frac);
  }

  double _inProgressAt(double t) {
    if (_duration <= 0) return 1;
    return ((t - startTime) / _duration).clamp(0.0, 1.0);
  }

  SymbolEffectPose evaluateAt(double t) {
    if (_isRepeating) {
      final limit = _repeatLimit;
      if (limit != null && t >= limit) return effect.evaluate(1);
      final elapsed = math.max(0, t - startTime);
      final u = (elapsed / _duration) % 1.0;
      return effect.evaluate(u);
    }
    if (_removing) return effect.evaluate(_outProgressAt(t));
    return effect.evaluate(_inProgressAt(t));
  }

  bool didFinishAt(double t) {
    if (_isRepeating) {
      final limit = _repeatLimit;
      if (limit != null && t >= limit) {
        fireAddComplete();
        return true;
      }
      return false;
    }

    if (!_addCompleted && t >= startTime + _duration) {
      fireAddComplete();
    }
    if (_removing && t >= _removeStart + _removeDuration) {
      _onRemoveComplete?.call(true);
      return true;
    }
    return false;
  }
}
