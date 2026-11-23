import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rest.dart';
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
  leaving;

  /// The status of a presentation [shown] or hidden that [settled] there
  /// or is still on its way.
  factory PresenceStatus.of({required bool shown, required bool settled}) =>
      switch ((shown, settled)) {
        (true, true) => PresenceStatus.shown,
        (true, false) => PresenceStatus.opening,
        (false, true) => PresenceStatus.hidden,
        (false, false) => PresenceStatus.leaving,
      };
}

/// A progress from 0 (hidden) to 1 (shown) on an open spring and a leave
/// spring, turning from where it stands, velocity included.
///
/// The [status] follows from the direction and rest alone. Under Reduce
/// Motion ([Motion.traits]), [open] and [leave] resolve their springs'
/// [Spring.reduced] alternatives automatically.
///
/// ```dart
/// late final lift = own(Presence(openSpring: .bouncy));
/// lift.open(t);
/// final scale = 1 + 0.06 * lift.progress;
/// ```
///
/// SwiftUI: the progress of a view's `transition` as it is inserted and
/// removed. Flutter: an `AnimationController` run forward and in reverse,
/// on two springs.
final class Presence extends Motion {
  /// Creates a presence starting hidden (or shown when `shown` is true) that
  /// opens on [openSpring], leaves on [leaveSpring] ([openSpring] when null)
  /// and rests within [restDistance].
  Presence({
    required this.openSpring,
    Spring? leaveSpring,
    this._shown = false,
    this.restDistance = MotionRest.opacity,
    super.clock,
  }) : leaveSpring = leaveSpring ?? openSpring {
    _progress = own(
      MotionValue<double>(
        _shown ? 1 : 0,
        spring: openSpring,
        restDistance: () => restDistance,
      ),
    );
  }

  /// The spring toward 1.
  final Spring openSpring;

  /// The spring toward 0.
  final Spring leaveSpring;

  /// How close to 0 or 1 the progress rests.
  final double restDistance;

  bool _shown;

  late final MotionValue<double> _progress;

  /// The progress as a listenable, 0 hidden to 1 shown (and past either on a
  /// bouncy spring).
  ValueListenable<double> get progressListenable => _progress;

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

  /// Leaves at [t], or [delay] seconds later.
  void leave(double t, {double delay = 0}) {
    _shown = false;
    _progress.retarget(
      t,
      0,
      spring: leaveSpring.resolve(reduceMotion: traits.reduceMotion),
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
      leave(t, delay: delay);
    }
  }

  /// Jumps to [progress] at [t], at rest, updating the direction from
  /// `progress > 0.5`.
  void snap(double t, double progress) {
    final shown = progress > 0.5;
    if (shown != _shown) {
      _shown = shown;
      changed();
    }
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
  PresenceStatus get status => PresenceStatus.of(
    shown: _shown,
    settled: _progress.settledAt(now),
  );

  /// Whether the presence is hidden and at rest.
  bool get isHidden => status == PresenceStatus.hidden;

  /// Whether the presence is shown and at rest.
  bool get isShown => status == PresenceStatus.shown;
}
