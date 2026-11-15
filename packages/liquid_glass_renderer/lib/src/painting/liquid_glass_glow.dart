import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The glow a finger raises on the glass of one shape of a layer, in the
/// layer's coordinates, for `LiquidGlassLayer.glow`.
///
/// Inside [bounds], a wash adds [wash] to every color channel and a spot
/// multiplies the channels by `1 + gain * exp(-0.5 * (r / radius)^2)` at
/// distance `r` from [center], clamped at white. Both act on everything the
/// glass shows and stay under the content painted after the layer, as iOS
/// lights a pressed glass surface: color matrices over the backdrop, the
/// spot equal to a color dodge whose white level is `1 - 1 / m` for its
/// multiplier `m`. The widget that owns the glass decides where and how
/// strongly it glows, frame by frame; `GlassGlow` instead follows the
/// pointer itself.
///
/// A layer whose shapes differ in color model or visibility draws no glow;
/// shapes that differ only in tint still glow.
@immutable
class LiquidGlassGlow {
  /// Creates a glow.
  const LiquidGlassGlow({
    required this.bounds,
    required this.cornerRadius,
    required this.center,
    required this.radius,
    required this.gain,
    required this.wash,
  });

  /// The lit shape's box: the glow stays inside it.
  final Rect bounds;

  /// The radius of every corner of [bounds], at most half its shorter side.
  final double cornerRadius;

  /// The center of the spot.
  final Offset center;

  /// The standard deviation of the spot's falloff.
  final double radius;

  /// How much the spot brightens its center: there the channels are
  /// multiplied by `1 + gain`.
  final double gain;

  /// How much every color channel rises inside [bounds], in `[0, 1]` units.
  final double wash;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassGlow &&
      other.bounds == bounds &&
      other.cornerRadius == cornerRadius &&
      other.center == center &&
      other.radius == radius &&
      other.gain == gain &&
      other.wash == wash;

  @override
  int get hashCode =>
      Object.hash(bounds, cornerRadius, center, radius, gain, wash);
}
