import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A Gaussian blur followed by a color matrix: a backdrop filter that the
/// renderer draws from an unblurred copy at a fraction of the screen's
/// pixels, frosted by a shader as it is drawn, wherever a copy serves and
/// the frost is narrow enough for the shader; otherwise the copy is
/// filtered.
///
/// NEAR: the shader's taps over a smaller copy are not Impeller's blur (see
/// [debugShaderFrost]).
@immutable
final class LiquidGlassBackdropFrost {
  /// Creates the filter: a blur by [sigma] logical pixels along both axes,
  /// reading past the backdrop's edge as [tileMode] says, then
  /// [colorMatrix] as [ui.ColorFilter.matrix] takes it, or none.
  LiquidGlassBackdropFrost({
    required this.sigma,
    this.colorMatrix,
    this.tileMode,
  }) : assert(sigma > 0, 'A frost blurs.'),
       assert(colorMatrix == null || colorMatrix.length == 20, '5 x 4 values.');

  /// Whether a frost is drawn from an unblurred copy through a shader;
  /// without, its copy is filtered as [filter] filters the backdrop.
  ///
  /// NEAR: the shader reads 8 or 16 taps per fragment, mirrored over a 2 x 2
  /// cell of pixels, so a thin hard edge under the frost shows a faint dither
  /// a screen's pixels hide. Over the colored rows and white lines of
  /// apple_liquid_glass's scroll edge frost host test, the bands differ from
  /// the copy filtered as the backdrop by at most 27 channel levels at a
  /// device pixel ratio of 2.625 and 22 at 3, by under 0.7 on average, with
  /// 0.3 to 0.5 % of the channels off by more than 8. Fake glass with 6 px of
  /// frost over the test font's white blocks, the hardest edges a frost meets,
  /// differs by at most 30 at 2.625 (13 for the filtered copy); at 3 the frost
  /// is too wide for the shader and the copy stays filtered. In return the copy takes no blur passes and, once the frost
  /// spans 3.6 device px, holds a quarter of the pixels or fewer; a change of
  /// the color matrix alone, as a band or a glass fades in, keeps it.
  static bool debugShaderFrost = true;

  /// The blur's sigma, in logical pixels.
  final double sigma;

  /// The color matrix applied after the blur, row by row, as
  /// [ui.ColorFilter.matrix] takes it; null for none.
  final List<double>? colorMatrix;

  /// What the live blur reads past the backdrop's edge, as
  /// [ui.ImageFilter.blur] takes it. A copy is frosted inside the screen,
  /// where it reads its own edge.
  final ui.TileMode? tileMode;

  /// The same filter as a backdrop filter, for what reads the backdrop.
  late final ui.ImageFilter filter = _filter();

  ui.ImageFilter _filter() {
    final blur = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: tileMode,
    );
    final matrix = colorMatrix;
    if (matrix == null) return blur;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(matrix),
      inner: blur,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassBackdropFrost &&
      other.sigma == sigma &&
      other.tileMode == tileMode &&
      listEquals(other.colorMatrix, colorMatrix);

  @override
  int get hashCode => Object.hash(
    sigma,
    tileMode,
    colorMatrix == null ? null : Object.hashAll(colorMatrix!),
  );
}
