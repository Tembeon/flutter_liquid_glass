import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/spring.dart';
import 'package:kinesis/src/motion/value.dart';

/// Where a [Presence] stands.
enum PresenceStatus {
  /// At rest at 0.
  hidden,

  /// Heading to 1.
  opening,

  /// At rest at 1.
  shown,

  /// Heading to 0.
  leaving,
}

/// A progress from 0 (hidden) to 1 (shown) on an open spring and a close
/// spring, turning from where it stands, velocity included.
///
/// The [status] follows from the direction and rest alone. Under Reduce
/// Motion ([Motion.traits]), [open] and [hide] resolve their springs'
/// [Spring.reduced] alternatives automatically.
///
/// ```dart
/// late final lift = own(Presence(openSpring: .bouncy));
/// lift.open(t);
/// final scale = 1 + 0.06 * lift.progress;
/// ```
final class Presence extends Motion {
  /// Creates a presence starting hidden (or shown when `shown` is true) that
  /// opens on [openSpring], hides on [closeSpring] ([openSpring] when null)
  /// and rests within [rest].
  Presence({
    required this.openSpring,
    Spring? closeSpring,
    this._shown = false,
    this.rest = MotionRest.opacity,
    super.clock,
  }) : closeSpring = closeSpring ?? openSpring {
    _progress = own(
      MotionValue<double>(
        _shown ? 1 : 0,
        spring: openSpring,
        restDistance: rest,
      ),
      rest: () => rest,
    );
  }

  /// The spring toward 1.
  final Spring openSpring;

  /// The spring toward 0.
  final Spring closeSpring;

  /// How close to 0 or 1 the progress rests.
  final double rest;

  bool _shown;

  late final MotionValue<double> _progress;

  /// The progress as a listenable, 0 hidden to 1 shown (and past either on a
  /// bouncy spring).
  ValueListenable<double> get listenable => _progress;

  /// Opens at [t], or [delay] seconds later.
  void open(double t, {double delay = 0}) {
    _shown = true;
    _progress.retarget(
      t,
      1,
      spring: openSpring.resolve(reduceMotion: traits.reduceMotion),
      delay: delay,
    );
  }

  /// Hides at [t], or [delay] seconds later.
  void hide(double t, {double delay = 0}) {
    _shown = false;
    _progress.retarget(
      t,
      0,
      spring: closeSpring.resolve(reduceMotion: traits.reduceMotion),
      delay: delay,
    );
  }

  /// Shows or hides the presence at [t]. When already heading to [shown] (and
  /// [animated] is true) this does nothing; with [animated] false it snaps at
  /// once.
  void turn(
    double t, {
    required bool shown,
    bool animated = true,
    double delay = 0,
  }) {
    final target = shown ? 1.0 : 0.0;
    if (_shown == shown && _progress.target == target && animated) return;
    if (!animated) {
      snap(t, target);
      return;
    }
    if (shown) {
      open(t, delay: delay);
    } else {
      hide(t, delay: delay);
    }
  }

  /// Jumps to [progress] at [t], at rest, updating the direction from
  /// `progress > 0.5`.
  void snap(double t, double progress) {
    _shown = progress > 0.5;
    _progress.snap(t, progress);
  }

  /// Holds the progress at [progress] at [t] without changing whether the
  /// presence is directed toward shown or hidden (for an interactive scrub
  /// such as predictive back).
  void hold(double t, double progress) => _progress.snap(t, progress);

  /// Gives the progress [velocity] at [t], keeping its current value and
  /// target.
  void setVelocity(double t, double velocity) =>
      _progress.setVelocity(t, velocity);

  /// The progress at [now], 0 to 1 and past it on a bouncy spring.
  double get progress => _progress.valueAt(now);

  /// The progress at [t].
  double progressAt(double t) => _progress.valueAt(t);

  /// The progress at [now] as an opacity, 0 to 1.
  double get opacity => progress.clamp(0.0, 1.0);

  /// Where the presence stands at [now].
  PresenceStatus get status {
    final rests = _progress.restsAt(now, rest) && _progress.nextDue == null;
    if (_shown) return rests ? PresenceStatus.shown : PresenceStatus.opening;
    return rests ? PresenceStatus.hidden : PresenceStatus.leaving;
  }

  /// Whether the presence is hidden and at rest.
  bool get isHidden => status == PresenceStatus.hidden;

  /// Whether the presence is shown and at rest.
  bool get isShown => status == PresenceStatus.shown;
}
