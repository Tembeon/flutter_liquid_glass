import 'dart:math';

import 'package:meta/meta.dart';

// The share of the sigma asked that Impeller's blur delivers, which the
// shader's frost matches so a copy and the live filter blur alike: the best
// of 0.70 to 1.0 against ImageFilter.blur at 3, 5 and 8 device px, where
// Impeller's blur passes deliver 0.84 to 0.87 of the sigma.
const double _deliveredFrost = 0.84;

// The largest sigma, in the copy's own pixels, the shader frosts by. Its taps
// lie about a sigma apart, so a wider frost shows hard edges as faint copies:
// they show at 5 copy pixels in the host test and not at 3.4.
const double _shaderFrostTexels = 3.5;

// How many device pixels along each side one pixel of a copy the shader
// frosts stands for at most. 8 gave no clear GPU gain on the Pixel 6a.
const int _shaderFrostMaxShare = 4;

// A copy blurred by at least this many of its own pixels is drawn as the blur
// leaves it at a fraction of the screen's pixels: sampled back up, it adds a
// tent of its pixel's width to a blur many times wider.
const double _blurredCopySigma = 2.5;

// How many device pixels along each side one pixel holds where Impeller's
// blur by [sigma] device pixels downsamples (GaussianBlurFilterContents::
// CalculateScale: none up to 4, else 2^round(log2(sigma / 4))).
int _blurShare(double sigma) =>
    sigma <= 4 ? 1 : 1 << max(0, (log(sigma / 4) / ln2).round());

// How many device pixels along each side one pixel of a copy holds that the
// shader frosts for Impeller's blur by [sigma] device pixels, or null when
// the frost is too wide for it: the largest whose pixels the frost spans by at
// most 3.5, then halved while the frost still spans [minTexels] of its pixels
// and, with [atBlurScale], while Impeller's own blur would downsample as far.
// Past that a weak frost leaves the copy's pixels showing: its taps then span
// about one of them, where Impeller's passes span two.
int? _shaderFrostShare(
  double sigma, {
  required double minTexels,
  bool atBlurScale = false,
}) {
  final delivered = sigma * _deliveredFrost;
  var share = 1;
  while (share < _shaderFrostMaxShare &&
      delivered / share > _shaderFrostTexels) {
    share *= 2;
  }
  if (delivered <= 0 || delivered / share > _shaderFrostTexels) return null;
  final floor = atBlurScale ? _blurShare(sigma) : _shaderFrostMaxShare;
  while (share < _shaderFrostMaxShare &&
      share * 2 <= floor &&
      delivered / (share * 2) >= minTexels) {
    share *= 2;
  }
  return share;
}

/// The sigma, in device pixels, the shaders' taps frost a copy by for
/// Impeller's blur by [sigma] device pixels, where each pixel of the copy
/// holds [share] device pixels along each side.
///
/// The taps frost by what the copy leaves: a pixel of a smaller copy averages
/// k x k device px (a box, variance k^2 / 12), every bilinear tap adds a tent
/// of a copy pixel (k^2 / 6), and Gaussians add in variance.
@internal
double frostResidual(double sigma, {required int share}) {
  final delivered = sigma * _deliveredFrost;
  final carried = share * share * (share > 1 ? 1 / 4 : 1 / 6);
  return sqrt(max(delivered * delivered - carried, 0));
}

/// What a site needs of a copy of its backdrop: how many device pixels along
/// each side one pixel of the copy may stand for, and the frost a shader
/// draws over it.
///
/// The one place a copy's share is chosen: a site states its need, and
/// everything that sizes, joins or reaches by the copy reads it from here.
@internal
@immutable
final class CopyNeed {
  /// A need of [share] device pixels a copy pixel, frosted by [frost].
  const CopyNeed(this.devicePixelRatio, {this.share = 1, this.frost = 0});

  /// A copy at the screen's pixels with nothing frosted over it.
  const CopyNeed.exact(this.devicePixelRatio) : share = 1, frost = 0;

  /// The need of a copy Impeller blurs by at least [sigma] logical pixels
  /// along each axis: halved while the blur spans 2.5 of its pixels, to at
  /// most [maxShare].
  factory CopyNeed.blurred(
    double sigma, {
    required double devicePixelRatio,
    required int maxShare,
  }) {
    var share = 1;
    while (share * 2 <= maxShare &&
        sigma * devicePixelRatio / (share * 2) >= _blurredCopySigma) {
      share *= 2;
    }
    return CopyNeed(devicePixelRatio, share: share);
  }

  /// The need of glass whose final shader frosts an unblurred copy by
  /// [sigma] logical pixels, or null where the frost is too wide for its
  /// taps. The copy is no coarser than Impeller's own blur would take: weak
  /// frosts (1.5 to 2.7 logical pixels) then come out half as far from
  /// Impeller's blur (host, dpr 2 and 3), where a copy of four device pixels
  /// a side left its pixels showing on the iPhone.
  static CopyNeed? glassFrost(
    double sigma, {
    required double devicePixelRatio,
  }) => switch (_shaderFrostShare(
    sigma * devicePixelRatio,
    minTexels: 1,
    atBlurScale: true,
  )) {
    final share? => CopyNeed(devicePixelRatio, share: share, frost: sigma),
    null => null,
  };

  /// The need of a scroll edge or fake glass whose frost shader frosts an
  /// unblurred copy by [sigma] logical pixels, or null where the frost is too
  /// wide for it. A copy whose pixels the frost spans by less than 1.5 is not
  /// halved again: drawn smaller, its edges show through the frost.
  static CopyNeed? edgeFrost(
    double sigma, {
    required double devicePixelRatio,
  }) => switch (_shaderFrostShare(sigma * devicePixelRatio, minTexels: 1.5)) {
    final share? => CopyNeed(devicePixelRatio, share: share, frost: sigma),
    null => null,
  };

  /// The screen's device pixels per logical pixel.
  final double devicePixelRatio;

  /// Device pixels along each side one pixel of the copy may stand for.
  final int share;

  /// The frost a shader draws over the copy, in logical pixels: 0 where the
  /// copy is blurred instead or nothing frosts it.
  final double frost;

  /// The logical pixels a shader frosting the copy reads around a region:
  /// its taps reach 2.8 frosts, one copy pixel more sampled bilinearly.
  ///
  /// A copy drawn at the screen's pixels in place of the ones asked reaches
  /// less: its taps lie at most a sigma wider and its pixel is smaller.
  double get reach => frost > 0
      ? (2.8 * frostResidual(frost * devicePixelRatio, share: share) + share) /
            devicePixelRatio
      : 0;

  /// Whether a shader's written-out taps stay smooth drawing a band with this
  /// need for glass with [glass]'s over one copy: past 2.8 of the copy's
  /// pixels they speckle, by the Mali model, which counts them in parallel
  /// unlike a loop of twelve.
  bool bandFits(CopyNeed glass) {
    final share = min(this.share, glass.share);
    final residual = frostResidual(frost * devicePixelRatio, share: share);
    return residual / share <= 2.8;
  }

  @override
  bool operator ==(Object other) =>
      other is CopyNeed &&
      other.devicePixelRatio == devicePixelRatio &&
      other.share == share &&
      other.frost == frost;

  @override
  int get hashCode => Object.hash(devicePixelRatio, share, frost);
}
