import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:kinesis/motion.dart';

/// A part that is there or not and eases between the two on its measured
/// springs: the inline title of a navigation bar, the effect at a scroll
/// edge, the response to a pointer.
///
/// The host tells it what happened ([turn]) and follows [presence].
final class PresenceMotion {
  PresenceMotion._({
    required bool shown,
    required Spring show,
    Spring? hide,
    double? restDistance,
    MotionClock? clock,
  }) : _show = show,
       _hide = hide ?? show,
       _presence = MotionValue<double>(
         shown ? 1 : 0,
         spring: show,
         restDistance: restDistance,
         clock: clock,
       );

  /// The inline title of a navigation bar with a large title: it rises in
  /// once the large title has scrolled under the bar, and leaves when the
  /// large title comes back.
  PresenceMotion.inlineTitle({required bool shown, MotionClock? clock})
    : this._(
        shown: shown,
        // Fitted 0.45 - 0.48 s, damping 0.98 - 1.0.
        show: const Spring.response(0.45),
        // Fitted 0.68 s, damping 0.98.
        hide: const Spring.response(0.7),
        restDistance: MotionRest.opacity,
        clock: clock,
      );

  /// The effect at one edge of a scroll view under a bar: it fades in once
  /// content lies beyond the edge and out when none does.
  PresenceMotion.scrollEdge({MotionClock? clock})
    : this._(
        shown: false,
        // Fitted on the device: 0.34 - 0.35 s, critically damped.
        show: const Spring.response(0.35),
        restDistance: MotionRest.opacity,
        clock: clock,
      );

  /// The response of a part to the pointer over it.
  PresenceMotion.hover({MotionClock? clock})
    : this._(shown: false, show: HoverTuning.spring, clock: clock);

  final Spring _show;
  final Spring _hide;
  final MotionValue<double> _presence;

  /// How present the part is: 0 gone, 1 there, and past either on the way.
  ValueListenable<double> get presence => _presence;

  /// Whether the part is there or heading there.
  bool get shown => _presence.target == 1;

  /// The clock the motion runs on.
  MotionClock get clock => _presence.clock;

  /// Shows or hides the part at time [t]. With [animated] false it
  /// switches at once, as UIKit does on a jump of the content; under
  /// [reduceMotion] it moves on the reduced form of its spring.
  void turn(
    double t, {
    required bool shown,
    bool animated = true,
    bool reduceMotion = false,
  }) {
    final target = shown ? 1.0 : 0.0;
    if (_presence.target == target) return;
    if (!animated) {
      _presence.snap(t, target);
      return;
    }
    _presence.retarget(
      t,
      target,
      spring: (shown ? _show : _hide).resolve(reduceMotion: reduceMotion),
    );
  }
}

/// The snap of a released scroll between a collapsed and an expanded large
/// title.
abstract final class LargeTitleSnap {
  static const _spring = Spring.response(0.33);

  /// The spring the snap runs on, for Flutter's scroll simulation.
  static SpringDescription get spring => _spring.description;
}

/// The measured tuning of [PresenceMotion.hover].
@internal
abstract final class HoverTuning {
  /// The spring the hover response eases in and out on: the one a press's
  /// glow fades on; under Reduce Motion it switches at once.
  static const Spring spring = Spring.response(0.5, reduced: Spring.immediate);
}
