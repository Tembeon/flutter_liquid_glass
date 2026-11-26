import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// A point of a [BlurRecipe]'s ramp: the blur's `strength` at `depth`
/// logical pixels inside the edge.
typedef BlurStop = ({double depth, double strength});

/// How glass blurs what it shows, by depth from its edge.
///
/// The blur is [radius] times a strength that runs piecewise linearly
/// through [stops], ordered from the deepest to the edge and beyond it into
/// the edge's antialiased fringe. A control's glass shows what lies under it
/// sharp inside and blurs it at the rim; a panel's blurs it inside too.
///
/// [radius] is in iOS's own units of blur. A unit comes to `ios27BlurUnit`
/// logical pixels of a Gaussian's sigma over the pyramid of smaller copies
/// the blur reads.
@immutable
final class BlurRecipe {
  /// A blur of [radius] by the ramp [stops].
  const BlurRecipe({required this.radius, required this.stops});

  /// The widest blur, in iOS's units of blur.
  final double radius;

  /// The ramp of the blur's strength, four stops from the deepest.
  final List<BlurStop> stops;

  @override
  bool operator ==(Object other) =>
      other is BlurRecipe &&
      other.radius == radius &&
      listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(radius, Object.hashAll(stops));

  @override
  String toString() => 'BlurRecipe($radius, $stops)';
}

/// A wide blur of what lies under the glass, mixed into what it shows.
///
/// Every channel moves to the wide blur by [lighten] where the blur is
/// lighter and by [darken] where it is darker, and the wide blur then
/// covers the result by [cover]. Light glass lightens, dark glass darkens,
/// and the Liquid Glass slider covers. [radius] is in iOS's units of blur
/// (see [BlurRecipe]).
@immutable
final class BlurFillRecipe {
  /// A blur fill of [radius] mixed in by [lighten], [darken] and [cover].
  const BlurFillRecipe({
    required this.radius,
    required this.lighten,
    required this.darken,
    required this.cover,
  });

  /// No blur fill.
  static const none = BlurFillRecipe(
    radius: 0,
    lighten: 0,
    darken: 0,
    cover: 0,
  );

  /// How wide the blur is, in iOS's units of blur.
  final double radius;

  /// How far a channel moves to the blur where the blur is lighter.
  final double lighten;

  /// How far a channel moves to the blur where the blur is darker.
  final double darken;

  /// How far the blur covers what the glass shows.
  final double cover;

  @override
  bool operator ==(Object other) =>
      other is BlurFillRecipe &&
      other.radius == radius &&
      other.lighten == lighten &&
      other.darken == darken &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(radius, lighten, darken, cover);

  @override
  String toString() =>
      'BlurFillRecipe($radius, lighten: $lighten, darken: $darken, '
      'cover: $cover)';
}

/// The colour of glass's face, applied to what it shows on sRGB-encoded
/// values with Rec. 709 luma weights.
///
/// First the luma rolls off toward [maxLuma] near white (dimming the
/// brightest and saturating them a little). Then the luma maps from 0..1 to
/// [black]..[white], the chroma is multiplied by [saturation], and [fill]
/// lies over the result.
@immutable
final class FaceRecipe {
  /// A face of the given levels, saturation, fill and roll-off.
  const FaceRecipe({
    required this.black,
    required this.white,
    required this.saturation,
    required this.fill,
    required this.maxLuma,
  });

  /// Where the face maps black.
  final double black;

  /// Where the face maps white.
  final double white;

  /// How much the face multiplies the chroma.
  final double saturation;

  /// The colour that lies over the face.
  final Color fill;

  /// The luma the face rolls off toward, as on a display with headroom
  /// above white such as an iPhone's; 0 rolls nothing off.
  final double maxLuma;

  @override
  bool operator ==(Object other) =>
      other is FaceRecipe &&
      other.black == black &&
      other.white == white &&
      other.saturation == saturation &&
      other.fill == fill &&
      other.maxLuma == maxLuma;

  @override
  int get hashCode => Object.hash(black, white, saturation, fill, maxLuma);

  @override
  String toString() =>
      'FaceRecipe($black..$white, saturation: $saturation, fill: $fill, '
      'maxLuma: $maxLuma)';
}

/// A veil laid over large glass's face, where iOS shows a wide blur of what
/// lies just outside the glass.
///
/// The veil is what the glass shows, mapped through levels
/// [black]..[white] and [saturation]. It covers the face by [opacity],
/// weighted by the face's luma where [onBright] is 1 and by its darkness
/// where it is 0.
@immutable
final class BleedRecipe {
  /// A bleed of the given levels and weight.
  const BleedRecipe({
    required this.opacity,
    required this.black,
    required this.white,
    required this.saturation,
    required this.onBright,
  });

  /// No bleed.
  static const none = BleedRecipe(
    opacity: 0,
    black: 0,
    white: 1,
    saturation: 1,
    onBright: 1,
  );

  /// How strongly the veil covers the face.
  final double opacity;

  /// Where the veil maps black.
  final double black;

  /// Where the veil maps white.
  final double white;

  /// How much the veil multiplies the chroma.
  final double saturation;

  /// Whether the veil shows where the face is bright (1) or dark (0).
  final double onBright;

  @override
  bool operator ==(Object other) =>
      other is BleedRecipe &&
      other.opacity == opacity &&
      other.black == black &&
      other.white == white &&
      other.saturation == saturation &&
      other.onBright == onBright;

  @override
  int get hashCode => Object.hash(opacity, black, white, saturation, onBright);

  @override
  String toString() =>
      'BleedRecipe(opacity: $opacity, $black..$white, '
      'saturation: $saturation, onBright: $onBright)';
}

/// The shadow glass casts below itself.
///
/// [color] at [opacity], [offset] logical pixels down, fading as a Gaussian
/// of sigma `radius / sqrt 2` from the glass's outline.
@immutable
final class DropShadowRecipe {
  /// A shadow of [radius] and [opacity].
  const DropShadowRecipe({
    required this.radius,
    required this.opacity,
    this.offset = 8,
    this.color = const Color.from(alpha: 0.3, red: 0, green: 0, blue: 0),
  });

  /// How soft the shadow is, in logical pixels.
  final double radius;

  /// How strongly the shadow shows [color].
  final double opacity;

  /// How far down the shadow lies, in logical pixels.
  final double offset;

  /// The shadow's own colour.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is DropShadowRecipe &&
      other.radius == radius &&
      other.opacity == opacity &&
      other.offset == offset &&
      other.color == color;

  @override
  int get hashCode => Object.hash(radius, opacity, offset, color);

  @override
  String toString() =>
      'DropShadowRecipe($radius, opacity: $opacity, offset: $offset, '
      'color: $color)';
}

/// A soft dark band glass draws inside its top edge.
///
/// A band [strokeWidth] logical pixels wide inside the glass's outline moved
/// [offset] down, blurred with a sigma of [blurRadius], black at [opacity],
/// kept inside the glass.
@immutable
final class RingShadowRecipe {
  /// A ring shadow of the given opacity, offset, width and blur.
  const RingShadowRecipe({
    required this.opacity,
    required this.offset,
    required this.strokeWidth,
    required this.blurRadius,
  });

  /// No ring shadow.
  static const none = RingShadowRecipe(
    opacity: 0,
    offset: 0,
    strokeWidth: 0,
    blurRadius: 0,
  );

  /// How dark the band gets.
  final double opacity;

  /// How far down the outline the band follows is moved.
  final double offset;

  /// How wide the band is.
  final double strokeWidth;

  /// How soft the band is.
  final double blurRadius;

  /// Whether the band shows.
  bool get draws => opacity > 0 && blurRadius > 0;

  @override
  bool operator ==(Object other) =>
      other is RingShadowRecipe &&
      other.opacity == opacity &&
      other.offset == offset &&
      other.strokeWidth == strokeWidth &&
      other.blurRadius == blurRadius;

  @override
  int get hashCode => Object.hash(opacity, offset, strokeWidth, blurRadius);

  @override
  String toString() =>
      'RingShadowRecipe($opacity, offset: $offset, stroke: $strokeWidth, '
      'blur: $blurRadius)';
}

/// The dark line just outside glass's edge, iOS 27's dark specular.
///
/// A band [width] logical pixels wide just outside the edge darkens what
/// lies there by [amount], biased toward the colour by [colorBias]. It is
/// strongest where the edge runs across the vertical light axis and fades
/// over [spread] radians of the edge's direction.
@immutable
final class DarkSpecularRecipe {
  /// A dark specular of the given amount, band and spread.
  const DarkSpecularRecipe({
    required this.amount,
    required this.width,
    required this.colorBias,
    required this.spread,
  });

  /// How much the band darkens.
  final double amount;

  /// How wide the band is.
  final double width;

  /// How far the band keeps the colour it darkens.
  final double colorBias;

  /// Over how many radians of the edge's direction the band fades, as on a
  /// display with headroom above white.
  final double spread;

  /// Whether the band shows.
  bool get draws => amount > 0 && width > 0;

  /// How far past the edge the band reaches, in logical pixels.
  double get reach => draws ? width : 0;

  @override
  bool operator ==(Object other) =>
      other is DarkSpecularRecipe &&
      other.amount == amount &&
      other.width == width &&
      other.colorBias == colorBias &&
      other.spread == spread;

  @override
  int get hashCode => Object.hash(amount, width, colorBias, spread);

  @override
  String toString() =>
      'DarkSpecularRecipe($amount, width: $width, bias: $colorBias, '
      'spread: $spread)';
}

/// The lit rim of glass: a mask from the edge that brightens and saturates
/// what lies under it, not white paint.
///
/// Two lights on the vertical axis, one above and one below, light a line
/// [width] logical pixels wide at the edge and a diffuse glow
/// [diffuseWidth] wide, [diffuseAmount] as strong, over [spread] radians of
/// the edge's direction ([diffuseSpread] of it for the glow), shaped by
/// [curvature]. Under the mask, at [opacity], what the glass shows is mapped
/// through levels [black]..[white] and [saturation].
@immutable
final class RimHighlightRecipe {
  /// A rim highlight of the given mask and brightening.
  const RimHighlightRecipe({
    required this.width,
    required this.diffuseWidth,
    required this.diffuseAmount,
    required this.diffuseSpread,
    required this.spread,
    required this.curvature,
    required this.opacity,
    required this.black,
    required this.white,
    required this.saturation,
  });

  /// How wide the lit line is.
  final double width;

  /// How wide the diffuse glow is.
  final double diffuseWidth;

  /// How strong the diffuse glow is, against the line.
  final double diffuseAmount;

  /// The part of [spread] the diffuse glow lights.
  final double diffuseSpread;

  /// Over how many radians of the edge's direction a light reaches.
  final double spread;

  /// How the light falls off along the edge.
  final double curvature;

  /// How strongly the mask brightens.
  final double opacity;

  /// Where the brightening maps black.
  final double black;

  /// Where the brightening maps white.
  final double white;

  /// How much the brightening multiplies the chroma.
  final double saturation;

  /// Whether the light shows.
  bool get draws => opacity > 0;

  @override
  bool operator ==(Object other) =>
      other is RimHighlightRecipe &&
      other.width == width &&
      other.diffuseWidth == diffuseWidth &&
      other.diffuseAmount == diffuseAmount &&
      other.diffuseSpread == diffuseSpread &&
      other.spread == spread &&
      other.curvature == curvature &&
      other.opacity == opacity &&
      other.black == black &&
      other.white == white &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(
    width,
    diffuseWidth,
    diffuseAmount,
    diffuseSpread,
    spread,
    curvature,
    opacity,
    black,
    white,
    saturation,
  );

  @override
  String toString() =>
      'RimHighlightRecipe(width: $width, diffuse: $diffuseWidth x '
      '$diffuseAmount, spread: $spread, curvature: $curvature, '
      'opacity: $opacity, $black..$white, saturation: $saturation)';
}
