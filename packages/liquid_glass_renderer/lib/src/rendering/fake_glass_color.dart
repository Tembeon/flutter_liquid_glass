import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe_groups.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:meta/meta.dart';

/// Saturation and a midtone secant of transmissionGamma as Flutter's 4x5
/// color matrix, a native color filter on Impeller and Skia.
@internal
List<double> fakeGlassColorMatrix({
  required double saturation,
  double transmissionGamma = 1,
  double opacity = 1,
}) {
  // A color matrix cannot apply pow() per channel; a secant through 0.25 and
  // 0.75 approximates transmissionGamma at midtones without another pass or
  // backdrop sample.
  final gamma = math.max(transmissionGamma, 0.01);
  const lowerInput = 0.25;
  const upperInput = 0.75;
  final lowerOutput = math.pow(lowerInput, gamma).toDouble();
  final upperOutput = math.pow(upperInput, gamma).toDouble();
  final gammaScale = (upperOutput - lowerOutput) / (upperInput - lowerInput);
  final gammaBias = lowerOutput - gammaScale * lowerInput;
  return saturationMatrix(
    saturation,
    gain: gammaScale,
    bias: gammaBias,
    alpha: opacity.clamp(0.0, 1.0),
  );
}

// Least-squares line `slope * Y + offset` through [transfer] over `[0, 1]`,
// sampled at 17 points.
(double slope, double offset) _line(double Function(double y) transfer) {
  const samples = 17;
  var meanY = 0.0;
  var meanT = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    meanY += y / samples;
    meanT += transfer(y) / samples;
  }
  var covariance = 0.0;
  var variance = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    covariance += (y - meanY) * (transfer(y) - meanT);
    variance += (y - meanY) * (y - meanY);
  }
  final slope = covariance / variance;
  return (slope, meanT - slope * meanY);
}

/// The face of an iOS 27 recipe ([face], under its [bleed]) as a 4x5 color
/// matrix.
///
/// Evaluating the whole face in the filter clamps only the final color, so
/// amplified chroma is not clipped before the fill covers it. A matrix is
/// linear in the backdrop, so the face of a grey backdrop, roll-off and
/// bleed included, is replaced by its least-squares line, and the chroma
/// takes the mean of its gain over the backdrop's luma. The bleed's veil is
/// the backdrop itself, as real glass's is short of a wide blur.
@internal
List<double> fakeGlassFaceMatrix({
  required FaceRecipe face,
  BleedRecipe bleed = BleedRecipe.none,
  double opacity = 1,
}) {
  final luminance = [lumaWeights.$1, lumaWeights.$2, lumaWeights.$3];
  final fill = face.fill;
  final fillColor = [fill.r, fill.g, fill.b];
  final fillLuma = _lumaOf(fill);
  double kept(double y) => _kept(face, y);
  double levels(double y) => recipeFaceLuma(face, y);
  double weight(double y) {
    final luma = levels(y).clamp(0.0, 1.0);
    final base = bleed.onBright >= 0.5 ? luma : 1 - luma;
    return math.pow(base, 4) * bleed.opacity;
  }

  double veil(double y) => bleed.black + (bleed.white - bleed.black) * y;
  final (slope, offset) = _line(
    (y) => levels(y) * (1 - weight(y)) + veil(y) * weight(y),
  );
  const samples = 17;
  var chroma = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    final k = kept(y);
    final w = weight(y);
    chroma +=
        ((1 - w) * (1 - fill.a) * face.saturation * k * (1 + 0.3 * (1 - k)) +
            w * bleed.saturation) /
        samples;
  }
  final result = <double>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      result.add(
        luminance[column] * (slope - chroma) + (row == column ? chroma : 0),
      );
    }
    result
      ..add(0)
      // ColorFilter.matrix biases use the 0-255 channel scale.
      ..add((offset + fill.a * (fillColor[row] - fillLuma)) * 255);
  }
  return result..addAll([0, 0, 0, opacity.clamp(0.0, 1.0), 0]);
}

double _lumaOf(Color color) =>
    lumaWeights.$1 * color.r +
    lumaWeights.$2 * color.g +
    lumaWeights.$3 * color.b;

double _kept(FaceRecipe face, double luma) {
  final rollOff = face.maxLuma <= 0 ? 0.0 : 1 - face.maxLuma.clamp(0.0, 1.0);
  return (1 - luma * rollOff).clamp(0.0, 1.0);
}

/// The luma [face] gives a grey backdrop of luma [luma], its fill
/// included, as the final shader's recipeFaceOf.
@internal
double recipeFaceLuma(FaceRecipe face, double luma) {
  final fill = face.fill;
  return (1 - fill.a) *
          (face.black + (face.white - face.black) * _kept(face, luma) * luma) +
      fill.a * _lumaOf(fill);
}

/// The light the rim highlight of [recipe] adds where it is full, over the
/// face of a mid grey: FakeGlass adds it to a face it cannot read.
@internal
double fakeGlassHighlightLift(GlassRecipe recipe) {
  final face = recipeFaceLuma(recipe.face, 0.5).clamp(0.0, 1.0);
  final highlight = recipe.rimHighlight;
  final lit = highlight.black + (highlight.white - highlight.black) * face;
  return (math.min(lit, 1) - face).clamp(0.0, 1.0);
}

/// What fake glass draws of a [LiquidGlassSettings]: the fake painters take
/// this, not the settings, so settings of one look draw alike.
@internal
@immutable
final class FakeGlassLook {
  /// The look of [settings].
  FakeGlassLook.of(LiquidGlassSettings settings)
    : blur = settings.blur,
      sliderPosition = settings.effectiveSliderPosition;

  /// [LiquidGlassSettings.blur].
  final double? blur;

  /// The slider position, clamped to `0` to `1`.
  final double sliderPosition;

  /// [glassBlurSigma] of glass wearing [model] in this look.
  double blurSigmaAt(
    WornColorModel model,
    double devicePixelRatio, {
    double? shapeShortSide,
  }) => glassBlurSigma(
    blur: blur,
    sliderPosition: sliderPosition,
    variant: model.blurredAs.variant,
    devicePixelRatio: devicePixelRatio,
    shapeShortSide: shapeShortSide,
  );

  @override
  bool operator ==(Object other) =>
      other is FakeGlassLook &&
      other.blur == blur &&
      other.sliderPosition == sliderPosition;

  @override
  int get hashCode => Object.hash(blur, sliderPosition);
}

/// A fake glass backdrop filter, and the frost `full` stands for when it
/// blurs.
@internal
typedef FakeGlassFilterParts = ({
  ImageFilter full,
  LiquidGlassBackdropFrost? frost,
});

/// What fake glass does to the color of its backdrop: the untinted face of
/// an iOS 27 recipe under its bleed, or else a saturation and a
/// transmission gamma.
@internal
typedef FakeGlassTransfer = ({
  FaceRecipe? face,
  BleedRecipe bleed,
  double saturation,
  double transmissionGamma,
});

/// The transfer fake glass wearing [model] applies to its backdrop in
/// [look], or null where it leaves the backdrop's color as it is.
@internal
FakeGlassTransfer? fakeGlassTransfer(
  FakeGlassLook look,
  WornColorModel model,
) {
  final recipe = switch (model.recipe) {
    final worn? => recipeOf(worn, look.sliderPosition),
    null => null,
  };
  if (recipe == null && model.saturation == 1 && model.transmissionGamma == 1) {
    return null;
  }
  return (
    face: recipe?.face,
    bleed: recipe?.bleed ?? BleedRecipe.none,
    saturation: model.saturation,
    transmissionGamma: model.transmissionGamma,
  );
}

/// Whether fake glass drawn in [look] and [appearance] changes its backdrop
/// ([fakeGlassBackdropFilterParts] gives it a filter).
@internal
bool fakeGlassReadsBackdrop(
  FakeGlassLook look,
  WornAppearance appearance,
) => fakeGlassBackdropFilterParts(look, appearance) != null;

/// The backdrop filter of fake glass, standalone or consolidated, with its
/// frost, or null where it leaves its backdrop as it is: it does not show,
/// or it neither frosts it nor moves its color.
@internal
FakeGlassFilterParts? fakeGlassBackdropFilterParts(
  FakeGlassLook look,
  WornAppearance appearance, {
  double devicePixelRatio = 1,
  double? shapeShortSide,
}) {
  if (!appearance.shows) return null;
  final visibility = appearance.visibility;
  final sigma = look.blurSigmaAt(
    appearance.colorModel,
    devicePixelRatio,
    shapeShortSide: shapeShortSide,
  );
  final matrix = switch (fakeGlassTransfer(look, appearance.colorModel)) {
    (face: final face?, :final bleed, saturation: _, transmissionGamma: _) =>
      fakeGlassFaceMatrix(face: face, bleed: bleed, opacity: visibility),
    (
      face: null,
      bleed: _,
      :final saturation,
      :final transmissionGamma,
    ) =>
      fakeGlassColorMatrix(
        saturation: saturation,
        transmissionGamma: transmissionGamma,
        opacity: visibility,
      ),
    null when sigma != 0 && visibility < 1 => fakeGlassColorMatrix(
      saturation: 1,
      opacity: visibility,
    ),
    null => null,
  };
  if (sigma == 0) {
    return matrix == null
        ? null
        : (full: ColorFilter.matrix(matrix), frost: null);
  }
  final frost = backdropFrost(
    sigma: sigma,
    colorMatrix: matrix,
    tileMode: glassBlurTileMode,
  );
  return (full: frost.filter, frost: frost);
}
