import 'package:flutter/foundation.dart';

/// What a lens does to what lies under it beyond the rest of its glass's
/// settings: a lifted knob, thumb or selection, or a loupe.
///
/// Resting glass has none of these; a lens grows them as it lifts. Lengths
/// are in logical pixels, depths measured from the edge. Every one of them is
/// 0 by default, which leaves what lies under the glass as the rest of its
/// settings show it.
@immutable
final class LiquidGlassLens {
  /// A lens of the given pull, shrink, parting and dispersion.
  const LiquidGlassLens({
    this.pull = 0,
    this.pullDepth = 0,
    this.shrink = 0,
    this.aberration = 0,
    this.aberrationDepth = 0,
    this.dispersion = 0,
  });

  /// A lens that changes nothing.
  static const none = LiquidGlassLens();

  /// How far outside itself the glass reads what lies under it at its edge:
  /// the edge pulls its surroundings in, so the glass shows more of what is
  /// around it, as a lifted iOS lens does.
  ///
  /// The pull is whole at the edge and falls along a quarter circle to
  /// nothing [pullDepth] from it, so the middle of glass deeper than that
  /// shows what lies under it in place and at its own size, where [shrink]
  /// shows all of it smaller. It points away from the long center line of
  /// the layer's glass bounds, which spans the long side less the short
  /// side, and the depth is measured from a capsule of those bounds. The
  /// bevel reads what the pull brings in, as glass lying over it would.
  /// Never negative.
  final double pull;

  /// How deep [pull] reaches from the edge; 0 pulls nothing.
  final double pullDepth;

  /// How much smaller the glass shows all of what lies under it, about the
  /// middle of its layer's glass: 0 keeps its size, 0.08 shows it at 92 %.
  ///
  /// Clamped to 0 to 0.75, so the glass can show more of its surroundings
  /// but never enlarges (and pixelates) what it captured; a magnifier draws
  /// its content again at full resolution instead (the example app's loupe
  /// does). The bevel bends on top. All glass of a layer shares that
  /// middle, so a shrinking shape that should shrink about itself takes a
  /// layer of its own.
  final double shrink;

  /// How far the glass parts the colours of what it shows: red reads up to
  /// this far one way and blue up to this far the other, so a bright line
  /// under the glass shows with a red side and a blue side, and dimmer, as
  /// under a lifted iOS lens.
  ///
  /// The way red reads is the edge's outward direction mirrored across the
  /// line that falls from the upper left to the lower right, 52.5 degrees
  /// below the horizontal (read from UIKit on iOS 27.2). At the upper left
  /// and the lower right of a rounded end it points out of the glass, at
  /// the upper right and the lower left into it, and between them it runs
  /// 15 degrees off the edge: leftward along the top, rightward along the
  /// bottom, up the left side and down the right one. It does not turn with
  /// the text direction.
  ///
  /// Each colour is read at several points up to that distance, the far
  /// ones weighing most, and green on both sides of its place. The parted
  /// colour lies over the glass in full at the edge and fades to nothing
  /// [aberrationDepth] from it; the outward direction is the one [pull]
  /// takes. Unlike [dispersion], it does not need the bevel and shows over
  /// the whole depth. Never negative.
  final double aberration;

  /// How deep [aberration] reaches from the edge; 0 parts nothing.
  final double aberrationDepth;

  /// How far the bend at the edge separates the colours: red bends
  /// `1 + dispersion / 2` and blue `1 - dispersion / 2` times the edge's
  /// bend. Negative values bend blue more, as real glass does; iOS 27's
  /// loupe measures about -0.06 and other iOS 27 glass 0. Glass that
  /// disperses costs more to draw.
  final double dispersion;

  /// A copy with the given values replaced.
  LiquidGlassLens copyWith({
    double? pull,
    double? pullDepth,
    double? shrink,
    double? aberration,
    double? aberrationDepth,
    double? dispersion,
  }) => LiquidGlassLens(
    pull: pull ?? this.pull,
    pullDepth: pullDepth ?? this.pullDepth,
    shrink: shrink ?? this.shrink,
    aberration: aberration ?? this.aberration,
    aberrationDepth: aberrationDepth ?? this.aberrationDepth,
    dispersion: dispersion ?? this.dispersion,
  );

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassLens &&
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
      'LiquidGlassLens(pull: $pull, pullDepth: $pullDepth, shrink: $shrink, '
      'aberration: $aberration, aberrationDepth: $aberrationDepth, '
      'dispersion: $dispersion)';
}
