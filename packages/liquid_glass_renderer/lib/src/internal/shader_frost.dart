import 'dart:math';

import 'package:meta/meta.dart';

/// How a shader frosts an unblurred copy for a Gaussian blur of a sigma:
/// the copy holds `downscale` device pixels in each of its pixels along each
/// side, and the shader's taps frost it by `frost` device pixels.
@internal
typedef ShaderFrost = ({int downscale, double frost});

// The share of the sigma asked that Impeller's blur delivers, which the
// shader's frost matches so a copy and the live filter blur alike: the best
// of 0.70 to 1.0 against ImageFilter.blur at 3, 5 and 8 device px, where
// Impeller's blur passes deliver 0.84 to 0.87 of the sigma.
const double _deliveredFrost = 0.84;

// The largest sigma, in the copy's own pixels, the shader frosts by. Its 24
// taps lie about a sigma apart, so a wider frost shows hard edges as faint
// copies: they show at 5 copy pixels in the host test and not at 3.4.
const double _shaderFrostTexels = 3.5;

// How many device pixels along each side one pixel of a copy the shader
// frosts stands for at most.
const int _shaderFrostMaxDownscale = 4;

/// How the shader frosts a copy for Impeller's blur by [sigma] device
/// pixels, or null when the frost is too wide for it.
///
/// The copy is the largest whose pixels the frost spans by at most 3.5,
/// then halved while the frost still spans [minTexels] of its pixels. The
/// shader frosts by what is left: a pixel of a smaller copy averages k x k
/// device px (a box, variance k^2 / 12), every bilinear tap adds a tent of
/// a copy pixel (k^2 / 6), and Gaussians add in variance.
@internal
ShaderFrost? shaderFrost(double sigma, {double minTexels = double.infinity}) {
  final delivered = sigma * _deliveredFrost;
  var downscale = 1;
  while (downscale < _shaderFrostMaxDownscale &&
      delivered / downscale > _shaderFrostTexels) {
    downscale *= 2;
  }
  if (delivered <= 0 || delivered / downscale > _shaderFrostTexels) {
    return null;
  }
  while (downscale < _shaderFrostMaxDownscale &&
      delivered / (downscale * 2) >= minTexels) {
    downscale *= 2;
  }
  final carried = downscale * downscale * (downscale > 1 ? 1 / 4 : 1 / 6);
  return (
    downscale: downscale,
    frost: sqrt(max(delivered * delivered - carried, 0)),
  );
}
