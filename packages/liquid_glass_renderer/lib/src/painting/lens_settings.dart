import 'package:flutter/foundation.dart';

/// What a lens does to what lies under it beyond the `GlassRecipe` of its
/// glass: a lifted knob, thumb or selection, or a loupe.
///
/// Resting glass has none of these; a lens grows them as it lifts, and its
/// recipe crosses toward the lens's own (no blur, no blur fill, a face that
/// changes no colour, its bend) by the same lift.
///
/// Lengths are in logical pixels, depths measured from the edge. Every one
/// of them is 0 by default, which leaves what lies under the glass as its
/// recipe shows it.
@immutable
final class LensSettings {
  /// A lens of the given pull, shrink, parting and dispersion.
  const LensSettings({
    this.pull = 0,
    this.pullDepth = 0,
    this.shrink = 0,
    this.aberration = 0,
    this.aberrationDepth = 0,
    this.dispersion = 0,
  });

  /// The lens [t] of the way from [a] to [b].
  factory LensSettings.lerp(LensSettings a, LensSettings b, double t) {
    double between(double x, double y) => x + (y - x) * t;
    return LensSettings(
      pull: between(a.pull, b.pull),
      pullDepth: between(a.pullDepth, b.pullDepth),
      shrink: between(a.shrink, b.shrink),
      aberration: between(a.aberration, b.aberration),
      aberrationDepth: between(a.aberrationDepth, b.aberrationDepth),
      dispersion: between(a.dispersion, b.dispersion),
    );
  }

  /// A lens that changes nothing.
  static const none = LensSettings();

  /// How far outside itself the glass reads what lies under it at its edge:
  /// the edge pulls its surroundings in, falling along a quarter circle to
  /// nothing [pullDepth] deep, so the middle shows what lies under it in
  /// place. iOS's lifted lenses pull 9 over 36.
  final double pull;

  /// How deep [pull] reaches from the edge.
  final double pullDepth;

  /// How much smaller the glass shows all of what lies under it, about the
  /// middle of its layer's glass, from 0 (its own size) toward 1.
  final double shrink;

  /// How far the glass parts the colours of what it shows: red reads up to
  /// this far one way and blue the other, from several points each, the
  /// far ones weighing most. The parted colours lie over the glass in full
  /// at the edge and fade out [aberrationDepth] deep.
  final double aberration;

  /// How deep [aberration] reaches from the edge.
  final double aberrationDepth;

  /// How far the bend at the edge separates the colours: red bends
  /// `1 + dispersion / 2` and blue `1 - dispersion / 2` times the edge's
  /// bend. iOS's loupe measures about -0.06.
  final double dispersion;

  /// Whether this lens changes nothing.
  bool get isNone =>
      (pull == 0 || pullDepth == 0) &&
      shrink == 0 &&
      (aberration == 0 || aberrationDepth == 0) &&
      dispersion == 0;

  /// This lens as it shows lifted by [lift], 0 at rest and 1 lifted: the
  /// pull, shrink, parting and dispersion grow with it, their depths stay.
  LensSettings lifted(double lift) => LensSettings(
    pull: pull * lift,
    pullDepth: pullDepth,
    shrink: shrink * lift,
    aberration: aberration * lift,
    aberrationDepth: aberrationDepth,
    dispersion: dispersion * lift,
  );

  @override
  bool operator ==(Object other) =>
      other is LensSettings &&
      other.pull == pull &&
      other.pullDepth == pullDepth &&
      other.shrink == shrink &&
      other.aberration == aberration &&
      other.aberrationDepth == aberrationDepth &&
      other.dispersion == dispersion;

  @override
  int get hashCode => Object.hash(
    pull,
    pullDepth,
    shrink,
    aberration,
    aberrationDepth,
    dispersion,
  );

  @override
  String toString() =>
      'LensSettings(pull: $pull over $pullDepth, shrink: $shrink, '
      'aberration: $aberration over $aberrationDepth, '
      'dispersion: $dispersion)';
}
