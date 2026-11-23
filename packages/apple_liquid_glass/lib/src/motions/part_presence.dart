import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:kinesis/motion.dart';

/// The measured presences of parts that are there or not and ease between
/// the two: the inline title of a navigation bar, the effect at a scroll
/// edge, the response to a pointer.
///
/// Each is a [Presence] the host turns and follows; under Reduce Motion,
/// from its traits, it switches at once.
abstract final class PartPresence {
  /// The inline title of a navigation bar with a large title: it rises in
  /// once the large title has scrolled under the bar, and leaves when the
  /// large title comes back.
  static Presence inlineTitle({required bool shown, MotionClock? clock}) =>
      Presence(
        // Fitted 0.45 - 0.48 s, damping 0.98 - 1.0.
        openSpring: const Spring.response(0.45, reduced: Spring.immediate),
        // Fitted 0.68 s, damping 0.98.
        closeSpring: const Spring.response(0.7, reduced: Spring.immediate),
        shown: shown,
        clock: clock,
      );

  /// The effect at one edge of a scroll view under a bar: it fades in once
  /// content lies beyond the edge and out when none does.
  static Presence scrollEdge({MotionClock? clock}) => Presence(
    // Fitted on the device: 0.34 - 0.35 s, critically damped.
    openSpring: const Spring.response(0.35, reduced: Spring.immediate),
    clock: clock,
  );

  /// The response of a part to the pointer over it, on the spring a
  /// press's glow fades on.
  static Presence hover({MotionClock? clock}) => Presence(
    openSpring: const Spring.response(
      TouchGlowTuning.fallResponse,
      reduced: Spring.immediate,
    ),
    restDistance: MotionRest.length,
    clock: clock,
  );
}
