import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/copy_place.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:meta/meta.dart';

/// How a scroll edge looks where it lies this frame, which glass over it
/// draws in its own filter.
@immutable
final class BandLook {
  /// Creates the look.
  const BandLook({
    required this.sigma,
    required this.paint,
    required this.origin,
    required this.shown,
    required this.devicePixelRatio,
  });

  /// Its frost, in logical pixels.
  final double sigma;

  /// What it paints over its frost.
  final FrostBandPaint paint;

  /// Where its layer's coordinates begin on the screen.
  final Offset origin;

  /// What it covers on the screen.
  final Rect shown;

  /// The device pixels of its view per logical pixel.
  final double devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is BandLook &&
      other.sigma == sigma &&
      other.paint == paint &&
      other.origin == origin &&
      other.shown == shown &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode =>
      Object.hash(sigma, paint, origin, shown, devicePixelRatio);
}

/// What a scroll edge paints over its frost, in its layer's coordinates, and
/// how its frost changes the color.
@immutable
final class FrostBandPaint {
  /// A hard band, a navigation bar's, along the [edge] of the screen
  /// ([AxisDirection.up] or [AxisDirection.down]): what lies under it
  /// saturated by [saturation] and brightened by [brightness], all of it
  /// faded toward [fade], and a hairline of [line], one device pixel wide,
  /// along its side away from [edge].
  const FrostBandPaint.hard({
    required AxisDirection this.edge,
    required this.fade,
    required Color this.line,
    required this.presence,
    required this.saturation,
    required this.brightness,
  }) : whole = null,
       gone = null;

  /// A soft band: faded toward [fade] whole from the row [whole] of its
  /// layer and gone at the row [gone], its frost dissolving with the fade.
  const FrostBandPaint.soft({
    required this.fade,
    required double this.whole,
    required double this.gone,
    required this.presence,
  }) : edge = null,
       line = null,
       saturation = 1,
       brightness = 0;

  @override
  bool operator ==(Object other) =>
      other is FrostBandPaint &&
      other.edge == edge &&
      other.fade == fade &&
      other.line == line &&
      other.whole == whole &&
      other.gone == gone &&
      other.presence == presence &&
      other.saturation == saturation &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(
    edge,
    fade,
    line,
    whole,
    gone,
    presence,
    saturation,
    brightness,
  );

  /// The edge of the screen a hard band lies along, or null for a soft one.
  final AxisDirection? edge;

  /// The fade, straight.
  final Color fade;

  /// The hairline of a hard band, straight, or null for a soft one.
  final Color? line;

  /// The row where a soft band's fade is whole, or null for a hard one.
  final double? whole;

  /// The row where a soft band's fade is gone, or null for a hard one.
  final double? gone;

  /// How much of the band shows.
  final double presence;

  /// The saturation of what lies under the band.
  final double saturation;

  /// The brightness added, as a share of full intensity.
  final double brightness;

  /// The color matrix of the band's frost, as [ColorFilter.matrix] takes
  /// it: the saturation, on the luminance the glass shades by, and the
  /// brightness, with [presence] as the alpha; null where it changes
  /// nothing.
  @internal
  List<double>? get colorMatrix {
    if (saturation == 1 && brightness == 0 && presence == 1) return null;
    final (lr, lg, lb) = lumaWeights;
    final s = saturation;
    final o = brightness * 255;
    return [
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, o, //
      0, 0, 0, presence, 0,
    ];
  }

  /// Where the band's frost dissolves into what lies under it: where a
  /// soft band's fade does, and nowhere under a hard band.
  @internal
  FrostDissolve get dissolve => switch ((whole, gone)) {
    (final whole?, final gone?) => FrostDissolve(whole, gone),
    _ => FrostDissolve.none,
  };

  /// The rows, in the layer's coordinates, of the hairline of a band over
  /// [clip] at [devicePixelRatio]: one device pixel along the side away
  /// from [edge]; both the same row where there is none.
  @internal
  (double, double) lineRows(Rect clip, double devicePixelRatio) {
    final pixel = 1 / devicePixelRatio;
    return switch (edge) {
      AxisDirection.up => (clip.bottom - pixel, clip.bottom),
      AxisDirection.down => (clip.top, clip.top + pixel),
      _ => (0, 0),
    };
  }
}
