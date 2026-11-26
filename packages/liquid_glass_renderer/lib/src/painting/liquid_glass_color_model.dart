import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// Flutter's 4x5 color matrix that sets [saturation] on the luminance glass
/// shades by ([lumaWeights]), then scales each color channel by [gain],
/// adds [bias] (a fraction of full intensity) and takes [alpha] as the alpha.
@internal
List<double> saturationMatrix(
  double saturation, {
  double gain = 1,
  double bias = 0,
  double alpha = 1,
}) {
  final (lr, lg, lb) = lumaWeights;
  final s = saturation;
  final o = bias * 255;
  double at(double weight, {bool own = false}) =>
      (weight * (1 - s) + (own ? s : 0)) * gain;
  return [
    at(lr, own: true), at(lg), at(lb), 0, o, //
    at(lr), at(lg, own: true), at(lb), 0, o, //
    at(lr), at(lg), at(lb, own: true), 0, o, //
    0, 0, 0, alpha, 0,
  ];
}

/// How glass combines its tint with the backdrop it shows through.
///
/// A model is either the direct one ([LiquidGlassColorModel.direct]), which
/// applies saturation, gamma and vibrancy per channel and adds no material
/// of its own, or iOS 27's: [LiquidGlassColorModel.ios27Regular], whose face
/// follows the size of the shape that wears it, and
/// [LiquidGlassColorModel.ios27Clear]. The iOS 27 models draw the recipe
/// UIKit gives its glass (`GlassRecipe`).
///
/// iOS gives glass a material by the shorter side of its shape. Up to 64
/// points regular glass is a control's: light glass lifts black to 40 %,
/// dark glass to 12.5 % and keeps 60 % of the backdrop's luminance. From 160
/// points it is a panel's: a veil pulls the bright parts of light glass
/// toward white and the dark parts of dark glass toward a dim grey, and dark
/// glass keeps 45 % of the luminance. Between the two every part grows
/// linearly; dark glass reaches its cap on luminance at 104 points. Each
/// shape resolves this for itself, so shapes that share a layer do not
/// change each other's look.
@immutable
sealed class LiquidGlassColorModel {
  const LiquidGlassColorModel._();

  /// Applies the tint, [saturation], [transmissionGamma] and [vibrancy]
  /// directly, per channel, with no response to the backdrop or to the size
  /// of the glass.
  const factory LiquidGlassColorModel.direct({
    double saturation,
    double transmissionGamma,
    double vibrancy,
  }) = LiquidGlassDirectColorModel._;

  /// The iOS 27 regular material (`Glass.regular`) in [brightness], which
  /// follows the size of the glass and the Liquid Glass slider.
  ///
  /// Along the slider a fill covers more of the face: white on light glass,
  /// grey on dark glass. A tint runs from a darker tone of itself over a
  /// black face to itself over a white one on light glass, and between two
  /// tones close to itself on dark glass; a grey tint follows another law
  /// than a color.
  ///
  /// The numbers are the inputs UIKit gives its glass on iOS 27, and the
  /// face they give agrees with captures of native glass over plain colors
  /// within a level out of 255. Approximation: the tones of a color are
  /// exact for fully saturated colors and up to 0.12 off the darker tone of
  /// a pale one.
  const factory LiquidGlassColorModel.ios27Regular({
    required Brightness brightness,
  }) = LiquidGlassIos27RegularColorModel._;

  /// iOS 27 `Glass.clear`, identical in light and dark appearance and at
  /// every size and slider position.
  ///
  /// Clear glass lifts black to 12.5 %, takes white to 108 % and passes
  /// chroma through at 1.06: the inputs UIKit gives it on iOS 27. It takes
  /// the tint tones of light glass in both appearances, and its glint
  /// brightens its own face rather than pulling toward a fixed bright
  /// target.
  const factory LiquidGlassColorModel.ios27Clear() =
      LiquidGlassIos27ClearColorModel._;
}

/// The [LiquidGlassColorModel] that applies its numbers directly
/// ([LiquidGlassColorModel.direct]).
final class LiquidGlassDirectColorModel extends LiquidGlassColorModel {
  const LiquidGlassDirectColorModel._({
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
  }) : super._();

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied per channel to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassDirectColorModel &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy;

  @override
  int get hashCode => Object.hash(saturation, transmissionGamma, vibrancy);

  @override
  String toString() =>
      'LiquidGlassColorModel.direct(saturation: $saturation, '
      'transmissionGamma: $transmissionGamma, vibrancy: $vibrancy)';
}

/// The [LiquidGlassColorModel] of iOS 27 regular glass
/// ([LiquidGlassColorModel.ios27Regular]).
final class LiquidGlassIos27RegularColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27RegularColorModel._({required this.brightness})
    : super._();

  /// The colour scheme of the glass.
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassIos27RegularColorModel &&
          other.brightness == brightness;

  @override
  int get hashCode => brightness.hashCode;

  @override
  String toString() =>
      'LiquidGlassColorModel.ios27Regular(brightness: $brightness)';
}

/// The [LiquidGlassColorModel] of iOS 27 clear glass
/// ([LiquidGlassColorModel.ios27Clear]).
final class LiquidGlassIos27ClearColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27ClearColorModel._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassIos27ClearColorModel;

  @override
  int get hashCode => (LiquidGlassIos27ClearColorModel).hashCode;

  @override
  String toString() => 'LiquidGlassColorModel.ios27Clear()';
}

/// What an iOS 27 recipe takes that a shape's look decides: the variant,
/// the scheme, the shape's shorter side in points and whether its tint is
/// a grey, which takes a tint law of its own.
@internal
typedef RecipeLook = ({
  GlassVariant variant,
  Brightness brightness,
  double shortSide,
  bool greyTint,
});

/// A [LiquidGlassColorModel] as glass of one size and tint wears it
/// ([WearColorModel.wornAt]): the constants the shaders take.
@internal
@immutable
final class WornColorModel {
  /// The direct model of these numbers.
  const WornColorModel.direct({
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
  }) : recipe = null;

  /// The iOS 27 recipe of [recipe] (`GlassRecipe.of`).
  const WornColorModel.recipe(RecipeLook this.recipe)
    : saturation = 1,
      transmissionGamma = 1,
      vibrancy = 0;

  /// What the iOS 27 recipe takes, or null for the direct model.
  final RecipeLook? recipe;

  /// Saturation applied to transmitted backdrop content; `1` for a recipe.
  final double saturation;

  /// Display-referred transfer applied per channel to transmitted content;
  /// `1` for a recipe.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift; `0` for a recipe.
  final double vibrancy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WornColorModel &&
          other.recipe == recipe &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy;

  @override
  int get hashCode =>
      Object.hash(recipe, saturation, transmissionGamma, vibrancy);

  @override
  String toString() =>
      'WornColorModel($recipe, $saturation, $transmissionGamma, $vibrancy)';
}

/// Wears a color model at a size.
@internal
extension WearColorModel on LiquidGlassColorModel {
  /// The model as glass whose shorter side is [shortSide] points and whose
  /// tint is [tint] wears it.
  ///
  /// iOS 27 glass up to 64 points wears one recipe and glass from 192
  /// points another, so shapes that share a layer mostly share one; between
  /// the two each size wears its own. A grey tint takes another law than a
  /// colour.
  WornColorModel wornAt(double shortSide, {Color? tint}) {
    final grey =
        tint != null &&
        tint.a > 0 &&
        (tint.r - tint.g).abs() < 1 / 510 &&
        (tint.g - tint.b).abs() < 1 / 510;
    final side = shortSide.clamp(recipeSizes.control, recipeSizes.panel);
    switch (this) {
      case LiquidGlassDirectColorModel(
        :final saturation,
        :final transmissionGamma,
        :final vibrancy,
      ):
        return saturation == 1 && transmissionGamma == 1 && vibrancy == 0
            ? _plainDirect
            : WornColorModel.direct(
                saturation: saturation,
                transmissionGamma: transmissionGamma,
                vibrancy: vibrancy,
              );
      case LiquidGlassIos27ClearColorModel():
        return _wear(GlassVariant.clear, Brightness.light, side, grey);
      case LiquidGlassIos27RegularColorModel(:final brightness):
        return _wear(GlassVariant.regular, brightness, side, grey);
    }
  }

  static WornColorModel _wear(
    GlassVariant variant,
    Brightness brightness,
    double side,
    bool grey,
  ) {
    WornColorModel worn() => WornColorModel.recipe((
      variant: variant,
      brightness: brightness,
      shortSide: side,
      greyTint: grey,
    ));
    if (side > recipeSizes.control && side < recipeSizes.panel) return worn();
    return _worn[(variant, brightness, side, grey)] ??= worn();
  }

  static const _plainDirect = WornColorModel.direct();

  static final _worn =
      <(GlassVariant, Brightness, double, bool), WornColorModel>{};
}

/// The shorter sides, in points, between which an iOS 27 recipe changes
/// with the size of its glass: every law of the size holds still up to
/// `control` and from `panel` on.
@internal
const recipeSizes = (control: 64.0, panel: 192.0);
