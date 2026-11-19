import 'dart:math' as math;

/// How close a part must stay to where it comes to rest before nothing
/// visible moves any more.
///
/// A spring that rests at 0.01 pt keeps a motion asking for frames for up
/// to a second after its last visible step; these thresholds end it when
/// what remains cannot be seen. Fidelity: NEAR, invisible. A length rests
/// below [length] (0.3 device px at 3x, 0.26 px on a 2.625x Pixel 6a), a
/// scale once its swing times its surface's extent does, an opacity or
/// color mix below [opacity] (half an 8-bit step), and a double of unknown
/// unit by its own swing ([unitless]).
abstract final class MotionRest {
  MotionRest._();

  /// The rest of a position or length, in logical pixels.
  static const double length = 0.1;

  /// The rest of an opacity or color mix, 0 to 1.
  static const double opacity = 0.002;

  /// The rest of a value whose unit spans [extent] logical pixels: a scale
  /// of a surface that long, or an index of rows that tall.
  static double scale(double extent) => length / math.max(extent, 1);

  /// The rest of a double of unknown unit whose largest swing since it last
  /// rested is [swing]: 1/500 of it, between 0.0001 and [length].
  ///
  /// A 0..1 progress or an index then lands without a visible last step, a
  /// move of 50 or more rests as a length does, and a nudge of a hair does
  /// not keep the clock awake.
  static double unitless(double swing) =>
      (swing * opacity).clamp(0.0001, length);
}
