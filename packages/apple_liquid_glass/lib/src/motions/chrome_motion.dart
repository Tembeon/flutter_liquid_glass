import 'package:flutter/physics.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The inline title of a navigation bar with a large title: it rises in
/// once the large title has scrolled under the bar, and leaves when the
/// large title comes back.
final class InlineTitleMotion {
  /// Creates the motion of a title that is [shown] or not, at rest.
  InlineTitleMotion({required bool shown, MotionClock? clock})
    : presence = MotionValue<double>(
        shown ? 1 : 0,
        spring: _showSpring,
        restDistance: MotionRest.opacity,
        clock: clock,
      );

  // Fitted 0.45 - 0.48 s, damping 0.98 - 1.0.
  static const _showSpring = Spring.response(0.45);

  // Fitted 0.68 s, damping 0.98.
  static const _hideSpring = Spring.response(0.7);

  /// How present the title is, 0 gone to 1 there.
  final MotionValue<double> presence;

  /// Shows or hides the title at time [t]; with [animated] false it
  /// switches at once, as UIKit does on a jump of the content.
  void turn(double t, {required bool shown, bool animated = true}) {
    final target = shown ? 1.0 : 0.0;
    if (presence.target == target) return;
    if (animated) {
      presence.retarget(
        t,
        target,
        spring: shown ? _showSpring : _hideSpring,
      );
    } else {
      presence.snap(t, target);
    }
  }
}

/// The effect at one edge of a scroll view under a bar: it fades in once
/// content lies beyond the edge and out when none does.
final class ScrollEdgeMotion {
  /// Creates the motion of an edge with no effect showing.
  ScrollEdgeMotion({MotionClock? clock})
    : presence = MotionValue<double>(
        0,
        spring: _spring,
        restDistance: MotionRest.opacity,
        clock: clock,
      );

  // Fitted on the device: 0.34 - 0.35 s, critically damped.
  static const _spring = Spring.response(0.35);

  /// How present the effect is, 0 gone to 1 there.
  final MotionValue<double> presence;

  /// Shows or hides the effect at time [t]; with [animated] false it
  /// switches at once.
  void turn(double t, {required bool shown, bool animated = true}) {
    final target = shown ? 1.0 : 0.0;
    if (presence.target == target) return;
    if (animated) {
      presence.retarget(t, target);
    } else {
      presence.snap(t, target);
    }
  }
}

/// The snap of a released scroll between a collapsed and an expanded large
/// title.
abstract final class LargeTitleSnap {
  static const _spring = Spring.response(0.33);

  /// The spring the snap runs on, for Flutter's scroll simulation.
  static SpringDescription get spring => _spring.description;
}

/// The response of a part to the pointer over it.
final class HoverMotion {
  /// Creates the motion of a part with no pointer over it.
  HoverMotion() : presence = MotionValue<double>(0, spring: HoverTuning.spring);

  /// How strongly the part shows the pointer, 0 to 1.
  final MotionValue<double> presence;

  /// Whether the pointer is over the part or the response is heading there.
  bool get hovered => presence.target == 1;

  /// Puts the response at rest, [hovered] or not, at the clock's time.
  void snap({required bool hovered}) {
    final target = hovered ? 1.0 : 0.0;
    if (presence.target != target) presence.snap(presence.clock.now, target);
  }

  /// The pointer came over the part or left it, at the clock's time; with
  /// [reduceMotion] the response switches at once.
  void turn({required bool hovered, required bool reduceMotion}) {
    final target = hovered ? 1.0 : 0.0;
    if (presence.target == target) return;
    presence.retarget(
      presence.clock.now,
      target,
      spring: HoverTuning.spring.resolve(reduceMotion: reduceMotion),
    );
  }
}

/// The measured tuning of [HoverMotion].
@internal
abstract final class HoverTuning {
  /// The spring the hover response eases in and out on: the one a press's
  /// glow fades on; under Reduce Motion it switches at once.
  static const Spring spring = Spring.response(0.5, reduced: Spring.immediate);
}
