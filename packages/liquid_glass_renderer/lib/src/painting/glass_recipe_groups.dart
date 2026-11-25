import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// How glass bends what lies under it at its edge.
///
/// Inside the edge the glass reads what lies [innerAmount] farther in at the
/// edge, the push falling along a quarter circle to nothing [innerHeight]
/// deep. In a band one point wide just inside the edge it shows, at
/// [outerOpacity], what lies [outerAmount] farther out, falling the same way
/// over [outerHeight]. Lengths in logical pixels.
@immutable
final class RefractionRecipe {
  /// A refraction of the given amounts and heights.
  const RefractionRecipe({
    required this.innerAmount,
    required this.innerHeight,
    required this.outerAmount,
    required this.outerHeight,
    required this.outerOpacity,
  });

  /// The refraction [t] of the way from [a] to [b].
  factory RefractionRecipe.lerp(
    RefractionRecipe a,
    RefractionRecipe b,
    double t,
  ) => RefractionRecipe(
    innerAmount: _lerp(a.innerAmount, b.innerAmount, t),
    innerHeight: _lerp(a.innerHeight, b.innerHeight, t),
    outerAmount: _lerp(a.outerAmount, b.outerAmount, t),
    outerHeight: _lerp(a.outerHeight, b.outerHeight, t),
    outerOpacity: _lerp(a.outerOpacity, b.outerOpacity, t),
  );

  /// No refraction at all.
  static const none = RefractionRecipe(
    innerAmount: 0,
    innerHeight: 0,
    outerAmount: 0,
    outerHeight: 0,
    outerOpacity: 0,
  );

  /// How far in the glass reads what lies under its edge.
  final double innerAmount;

  /// How deep [innerAmount] reaches from the edge.
  final double innerHeight;

  /// How far out the edge band reads what lies beside the glass.
  final double outerAmount;

  /// How deep [outerAmount] would reach from the edge.
  final double outerHeight;

  /// How strongly the edge band shows what [outerAmount] reads.
  final double outerOpacity;

  /// This refraction with both amounts times [factor].
  RefractionRecipe scaled(double factor) => RefractionRecipe(
    innerAmount: innerAmount * factor,
    innerHeight: innerHeight,
    outerAmount: outerAmount * factor,
    outerHeight: outerHeight,
    outerOpacity: outerOpacity,
  );

  @override
  bool operator ==(Object other) =>
      other is RefractionRecipe &&
      other.innerAmount == innerAmount &&
      other.innerHeight == innerHeight &&
      other.outerAmount == outerAmount &&
      other.outerHeight == outerHeight &&
      other.outerOpacity == outerOpacity;

  @override
  int get hashCode => Object.hash(
    innerAmount,
    innerHeight,
    outerAmount,
    outerHeight,
    outerOpacity,
  );

  @override
  String toString() =>
      'RefractionRecipe(inner: $innerAmount over $innerHeight, '
      'outer: $outerAmount over $outerHeight at $outerOpacity)';
}

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

  /// The blur [t] of the way from [a] to [b], stop by stop.
  factory BlurRecipe.lerp(BlurRecipe a, BlurRecipe b, double t) => BlurRecipe(
    radius: _lerp(a.radius, b.radius, t),
    stops: [
      for (var i = 0; i < a.stops.length; i++)
        (
          depth: _lerp(a.stops[i].depth, b.stops[i].depth, t),
          strength: _lerp(a.stops[i].strength, b.stops[i].strength, t),
        ),
    ],
  );

  /// No blur.
  static const none = BlurRecipe(
    radius: 0,
    stops: [
      (depth: 0, strength: 0),
      (depth: 0, strength: 0),
      (depth: 0, strength: 0),
      (depth: 0, strength: 0),
    ],
  );

  /// The widest blur, in iOS's units of blur.
  final double radius;

  /// The ramp of the blur's strength, four stops from the deepest.
  final List<BlurStop> stops;

  /// This blur with its radius times [factor].
  BlurRecipe scaled(double factor) =>
      BlurRecipe(radius: radius * factor, stops: stops);

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

  /// The blur fill [t] of the way from [a] to [b].
  factory BlurFillRecipe.lerp(BlurFillRecipe a, BlurFillRecipe b, double t) =>
      BlurFillRecipe(
        radius: _lerp(a.radius, b.radius, t),
        lighten: _lerp(a.lighten, b.lighten, t),
        darken: _lerp(a.darken, b.darken, t),
        cover: _lerp(a.cover, b.cover, t),
      );

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
/// lies over the result. Last the colour is clamped to [clamp] in linear
/// light.
@immutable
final class FaceRecipe {
  /// A face of the given levels, saturation, fill and roll-off.
  const FaceRecipe({
    required this.black,
    required this.white,
    required this.saturation,
    required this.fill,
    required this.maxLuma,
    required this.maxLumaWithoutHeadroom,
  });

  /// The face [t] of the way from [a] to [b]; [fill] crosses premultiplied.
  factory FaceRecipe.lerp(FaceRecipe a, FaceRecipe b, double t) => FaceRecipe(
    black: _lerp(a.black, b.black, t),
    white: _lerp(a.white, b.white, t),
    saturation: _lerp(a.saturation, b.saturation, t),
    fill: lerpPremultiplied(a.fill, b.fill, t),
    maxLuma: _lerp(a.maxLuma, b.maxLuma, t),
    maxLumaWithoutHeadroom: _lerp(
      a.maxLumaWithoutHeadroom,
      b.maxLumaWithoutHeadroom,
      t,
    ),
  );

  /// A face that changes no colour.
  static const identity = FaceRecipe(
    black: 0,
    white: 1,
    saturation: 1,
    fill: Color(0x00FFFFFF),
    maxLuma: 0,
    maxLumaWithoutHeadroom: 0,
  );

  /// Where the face maps black.
  final double black;

  /// Where the face maps white.
  final double white;

  /// How much the face multiplies the chroma.
  final double saturation;

  /// The colour that lies over the face.
  final Color fill;

  /// The luma the face rolls off toward on a display with headroom above
  /// white, such as an iPhone's; 0 rolls nothing off.
  final double maxLuma;

  /// The luma the face rolls off toward on a display without headroom, such
  /// as the simulator's; 0 rolls nothing off.
  final double maxLumaWithoutHeadroom;

  /// The brightest the face lets a channel get, in linear light: [white]
  /// decoded from sRGB, and never below 1.
  double get clamp => math.max(1, _srgbDecode(white));

  @override
  bool operator ==(Object other) =>
      other is FaceRecipe &&
      other.black == black &&
      other.white == white &&
      other.saturation == saturation &&
      other.fill == fill &&
      other.maxLuma == maxLuma &&
      other.maxLumaWithoutHeadroom == maxLumaWithoutHeadroom;

  @override
  int get hashCode => Object.hash(
    black,
    white,
    saturation,
    fill,
    maxLuma,
    maxLumaWithoutHeadroom,
  );

  @override
  String toString() =>
      'FaceRecipe($black..$white, saturation: $saturation, fill: $fill, '
      'maxLuma: $maxLuma / $maxLumaWithoutHeadroom)';
}

/// A wide veil of what lies just outside large glass, laid over its face
/// near the edge.
///
/// The glass reads what lies [amount] farther out, falling along a quarter
/// circle to nothing [amount] deep, blurred by [blurRadius] (iOS's units of
/// blur), and maps it through levels [black]..[white] and [saturation]. The
/// veil covers the face by [opacity], weighted by the face's luma where
/// [onBright] is 1 and by its darkness where it is 0.
@immutable
final class BleedRecipe {
  /// A bleed of the given reach, blur, levels and weight.
  const BleedRecipe({
    required this.amount,
    required this.blurRadius,
    required this.opacity,
    required this.black,
    required this.white,
    required this.saturation,
    required this.onBright,
  });

  /// The bleed [t] of the way from [a] to [b].
  factory BleedRecipe.lerp(BleedRecipe a, BleedRecipe b, double t) =>
      BleedRecipe(
        amount: _lerp(a.amount, b.amount, t),
        blurRadius: _lerp(a.blurRadius, b.blurRadius, t),
        opacity: _lerp(a.opacity, b.opacity, t),
        black: _lerp(a.black, b.black, t),
        white: _lerp(a.white, b.white, t),
        saturation: _lerp(a.saturation, b.saturation, t),
        onBright: _lerp(a.onBright, b.onBright, t),
      );

  /// No bleed.
  static const none = BleedRecipe(
    amount: 0,
    blurRadius: 0,
    opacity: 0,
    black: 0,
    white: 1,
    saturation: 1,
    onBright: 1,
  );

  /// How far out the veil reads, and how deep it reaches.
  final double amount;

  /// How wide the veil is blurred, in iOS's units of blur.
  final double blurRadius;

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
      other.amount == amount &&
      other.blurRadius == blurRadius &&
      other.opacity == opacity &&
      other.black == black &&
      other.white == white &&
      other.saturation == saturation &&
      other.onBright == onBright;

  @override
  int get hashCode => Object.hash(
    amount,
    blurRadius,
    opacity,
    black,
    white,
    saturation,
    onBright,
  );

  @override
  String toString() =>
      'BleedRecipe($amount, blur: $blurRadius, opacity: $opacity, '
      '$black..$white, saturation: $saturation, onBright: $onBright)';
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

  /// The shadow [t] of the way from [a] to [b].
  factory DropShadowRecipe.lerp(
    DropShadowRecipe a,
    DropShadowRecipe b,
    double t,
  ) => DropShadowRecipe(
    radius: _lerp(a.radius, b.radius, t),
    opacity: _lerp(a.opacity, b.opacity, t),
    offset: _lerp(a.offset, b.offset, t),
    color: lerpPremultiplied(a.color, b.color, t),
  );

  /// No shadow.
  static const none = DropShadowRecipe(radius: 0, opacity: 0);

  /// How soft the shadow is, in logical pixels.
  final double radius;

  /// How strongly the shadow shows [color].
  final double opacity;

  /// How far down the shadow lies, in logical pixels.
  final double offset;

  /// The shadow's own colour.
  final Color color;

  /// This shadow with its opacity times [factor].
  DropShadowRecipe scaled(double factor) => DropShadowRecipe(
    radius: radius,
    opacity: opacity * factor,
    offset: offset,
    color: color,
  );

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

  /// The ring shadow [t] of the way from [a] to [b].
  factory RingShadowRecipe.lerp(
    RingShadowRecipe a,
    RingShadowRecipe b,
    double t,
  ) => RingShadowRecipe(
    opacity: _lerp(a.opacity, b.opacity, t),
    offset: _lerp(a.offset, b.offset, t),
    strokeWidth: _lerp(a.strokeWidth, b.strokeWidth, t),
    blurRadius: _lerp(a.blurRadius, b.blurRadius, t),
  );

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

  /// This ring shadow with its opacity times [factor].
  RingShadowRecipe scaled(double factor) => RingShadowRecipe(
    opacity: opacity * factor,
    offset: offset,
    strokeWidth: strokeWidth,
    blurRadius: blurRadius,
  );

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

/// The dark line just outside glass's edge, iOS 27's darker edge.
///
/// A band [width] logical pixels wide, [offset] from the edge (negative:
/// outside), darkens what lies there by [amount], biased toward the colour
/// by [colorBias]. It is strongest where the edge runs across the vertical
/// light axis and fades over [spread] radians of the edge's direction.
@immutable
final class DarkSpecularRecipe {
  /// A dark edge of the given amount, band and spread.
  const DarkSpecularRecipe({
    required this.amount,
    required this.width,
    required this.offset,
    required this.colorBias,
    required this.spread,
    required this.spreadWithoutHeadroom,
  });

  /// The dark edge [t] of the way from [a] to [b].
  factory DarkSpecularRecipe.lerp(
    DarkSpecularRecipe a,
    DarkSpecularRecipe b,
    double t,
  ) => DarkSpecularRecipe(
    amount: _lerp(a.amount, b.amount, t),
    width: _lerp(a.width, b.width, t),
    offset: _lerp(a.offset, b.offset, t),
    colorBias: _lerp(a.colorBias, b.colorBias, t),
    spread: _lerp(a.spread, b.spread, t),
    spreadWithoutHeadroom: _lerp(
      a.spreadWithoutHeadroom,
      b.spreadWithoutHeadroom,
      t,
    ),
  );

  /// No dark edge.
  static const none = DarkSpecularRecipe(
    amount: 0,
    width: 0,
    offset: 0,
    colorBias: 0,
    spread: 0,
    spreadWithoutHeadroom: 0,
  );

  /// How much the band darkens.
  final double amount;

  /// How wide the band is.
  final double width;

  /// Where the band lies from the edge; negative is outside.
  final double offset;

  /// How far the band keeps the colour it darkens.
  final double colorBias;

  /// Over how many radians of the edge's direction the band fades, on a
  /// display with headroom above white.
  final double spread;

  /// [spread] on a display without headroom.
  final double spreadWithoutHeadroom;

  @override
  bool operator ==(Object other) =>
      other is DarkSpecularRecipe &&
      other.amount == amount &&
      other.width == width &&
      other.offset == offset &&
      other.colorBias == colorBias &&
      other.spread == spread &&
      other.spreadWithoutHeadroom == spreadWithoutHeadroom;

  @override
  int get hashCode => Object.hash(
    amount,
    width,
    offset,
    colorBias,
    spread,
    spreadWithoutHeadroom,
  );

  @override
  String toString() =>
      'DarkSpecularRecipe($amount, width: $width, offset: $offset, '
      'bias: $colorBias, spread: $spread / $spreadWithoutHeadroom)';
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

  /// The rim highlight [t] of the way from [a] to [b].
  factory RimHighlightRecipe.lerp(
    RimHighlightRecipe a,
    RimHighlightRecipe b,
    double t,
  ) => RimHighlightRecipe(
    width: _lerp(a.width, b.width, t),
    diffuseWidth: _lerp(a.diffuseWidth, b.diffuseWidth, t),
    diffuseAmount: _lerp(a.diffuseAmount, b.diffuseAmount, t),
    diffuseSpread: _lerp(a.diffuseSpread, b.diffuseSpread, t),
    spread: _lerp(a.spread, b.spread, t),
    curvature: _lerp(a.curvature, b.curvature, t),
    opacity: _lerp(a.opacity, b.opacity, t),
    black: _lerp(a.black, b.black, t),
    white: _lerp(a.white, b.white, t),
    saturation: _lerp(a.saturation, b.saturation, t),
  );

  /// No rim highlight.
  static const none = RimHighlightRecipe(
    width: 0,
    diffuseWidth: 0,
    diffuseAmount: 0,
    diffuseSpread: 0,
    spread: 0,
    curvature: 0,
    opacity: 0,
    black: 0,
    white: 1,
    saturation: 1,
  );

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

  /// This rim highlight with its opacity times [factor].
  RimHighlightRecipe scaled(double factor) => RimHighlightRecipe(
    width: width,
    diffuseWidth: diffuseWidth,
    diffuseAmount: diffuseAmount,
    diffuseSpread: diffuseSpread,
    spread: spread,
    curvature: curvature,
    opacity: opacity * factor,
    black: black,
    white: white,
    saturation: saturation,
  );

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

/// An sRGB-encoded colour a tint ramp runs through; a channel may lie
/// outside 0..1.
typedef TintEnd = ({double red, double green, double blue});

/// How a tint recolours glass's face.
///
/// Each channel runs from [low] to [high] as the face's brightness does:
/// the face's luma where [lumaWeight] is 1, the channel itself where it is
/// 0. The result is scaled down to keep its brightest channel at most 1.2,
/// and replaces the face by [opacity], the tint's alpha. The tint shows in
/// full at the edge and fades out 10 logical pixels deep.
@immutable
final class TintRecipe {
  /// A tint running from [low] to [high].
  const TintRecipe({
    required this.low,
    required this.high,
    required this.lumaWeight,
    required this.opacity,
  });

  /// The tint [t] of the way from [a] to [b]. A tint of no opacity takes
  /// the other's ramp, so a tint fades in and out without changing hue.
  factory TintRecipe.lerp(TintRecipe a, TintRecipe b, double t) {
    final from = a.opacity == 0 ? b : a;
    final to = b.opacity == 0 ? a : b;
    return TintRecipe(
      low: _lerpEnd(from.low, to.low, t),
      high: _lerpEnd(from.high, to.high, t),
      lumaWeight: _lerp(from.lumaWeight, to.lumaWeight, t),
      opacity: _lerp(a.opacity, b.opacity, t),
    );
  }

  /// No tint.
  static const none = TintRecipe(
    low: (red: 0, green: 0, blue: 0),
    high: (red: 1, green: 1, blue: 1),
    lumaWeight: 1,
    opacity: 0,
  );

  /// What a channel becomes where the face is black.
  final TintEnd low;

  /// What a channel becomes where the face is white.
  final TintEnd high;

  /// Whether the ramp follows the face's luma (1) or each channel (0).
  final double lumaWeight;

  /// How far the tint replaces the face.
  final double opacity;

  static TintEnd _lerpEnd(TintEnd a, TintEnd b, double t) => (
    red: _lerp(a.red, b.red, t),
    green: _lerp(a.green, b.green, t),
    blue: _lerp(a.blue, b.blue, t),
  );

  @override
  bool operator ==(Object other) =>
      other is TintRecipe &&
      other.low == low &&
      other.high == high &&
      other.lumaWeight == lumaWeight &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(low, high, lumaWeight, opacity);

  @override
  String toString() =>
      'TintRecipe($low..$high, lumaWeight: $lumaWeight, opacity: $opacity)';
}

/// [a] and [b] crossed [t] of the way premultiplied, so a colour of no
/// alpha takes the other's hue.
Color lerpPremultiplied(Color a, Color b, double t) {
  final alpha = _lerp(a.a, b.a, t);
  if (alpha <= 0) return Color.lerp(a, b, t)!.withValues(alpha: 0);
  double channel(double x, double y) =>
      clampDouble(_lerp(x * a.a, y * b.a, t) / alpha, 0, 1);
  return Color.from(
    alpha: clampDouble(alpha, 0, 1),
    red: channel(a.r, b.r),
    green: channel(a.g, b.g),
    blue: channel(a.b, b.b),
  );
}

double _srgbDecode(double encoded) =>
    math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
