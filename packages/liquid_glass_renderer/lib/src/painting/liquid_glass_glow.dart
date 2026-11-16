import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The glow a finger raises on one glass shape, for
/// `LiquidGlassShapeFrame.glow`, in the shape's own space: the body the frame
/// draws, from its top left corner, so it moves and scales with the body.
///
/// A wash adds [wash] to every color channel and a spot multiplies the
/// channels by `1 + gain * exp(-0.5 * (r / radius)^2)` at distance `r` from
/// [center], clamped at white. Both act on everything the glass shows,
/// inside its silhouette, and stay under the content painted after it, as
/// iOS lights a pressed glass surface: color matrices over the backdrop, the
/// spot equal to a color dodge whose white level is `1 - 1 / m` for its
/// multiplier `m`. The widget that owns the glass decides where and how
/// strongly it glows, frame by frame.
///
/// A layer lights one shape: the last whose glow changed to one that
/// [draws], until that glow stops drawing. Real glass whose layer's shapes
/// differ in color model or visibility draws no glow; shapes that differ
/// only in tint still glow.
@immutable
class LiquidGlassGlow {
  /// Creates a glow.
  const LiquidGlassGlow({
    required this.center,
    required this.radius,
    required this.gain,
    required this.wash,
  });

  /// The center of the spot.
  final Offset center;

  /// The standard deviation of the spot's falloff.
  final double radius;

  /// How much the spot brightens its center: there the channels are
  /// multiplied by `1 + gain`.
  final double gain;

  /// How much every color channel rises, in `[0, 1]` units.
  final double wash;

  /// Whether the glow changes the glass: it has a wash or a spot. One that
  /// does not is drawn as none.
  bool get draws => wash > 0 || gain > 0 && radius > 0;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassGlow &&
      other.center == center &&
      other.radius == radius &&
      other.gain == gain &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(center, radius, gain, wash);
}
