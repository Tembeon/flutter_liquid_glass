import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
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
/// follows the size of the shape that wears it,
/// [LiquidGlassColorModel.ios27Clear], and the lenses UIKit lifts out of a
/// held control, [LiquidGlassColorModel.ios27Lens] and
/// [LiquidGlassColorModel.ios27SmallLens]. The iOS 27 models draw the recipe
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
  /// of the glass, and lights its rim by [glintStrength], [contourStrength],
  /// [contourDirectionality] and [bevelShadowStrength].
  ///
  /// The rim is a fit to iOS 27 captures, not the rim iOS 27 draws, which
  /// the iOS 27 models light as their recipes say: a 1.2 pt glint on both
  /// walls along the light axis, a 0.75 pt dark contour outside the
  /// silhouette that concentrates where the glint fades, and a faint inner
  /// shadow cast by the rim. A strength left null is regular glass's in
  /// [brightness]; dark glass's contour is stronger and vanishes where the
  /// normal faces the light axis. The glass blurs and fills what it shows as
  /// regular glass of [brightness] does.
  ///
  /// The shapes of one layer light their rims alike, by the first direct
  /// model among them.
  const factory LiquidGlassColorModel.direct({
    required Brightness brightness,
    double saturation,
    double transmissionGamma,
    double vibrancy,
    double? glintStrength,
    double? contourStrength,
    double? contourDirectionality,
    double? bevelShadowStrength,
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
  ///
  /// With [highContrast], the face iOS 27 gives glass under the
  /// Increase Contrast setting: less saturated, light glass lifts black
  /// further under a more opaque white fill, dark glass caps its brightest
  /// parts at a dark grey. The setting comes from the platform
  /// (`MediaQuery.highContrastOf` on iOS); this model never reads it.
  const factory LiquidGlassColorModel.ios27Regular({
    required Brightness brightness,
    bool highContrast,
  }) = LiquidGlassIos27RegularColorModel._;

  /// iOS 27 `Glass.clear` in [brightness], identical in light and dark
  /// appearance and at every size and slider position but under Reduce
  /// Transparency, whose fill is a quarter of white in light and of black in
  /// dark (`LiquidGlassSettings.reduceTransparency`).
  ///
  /// Clear glass lifts black to 12.5 %, takes white to 108 % and passes
  /// chroma through at 1.06: the inputs UIKit gives it on iOS 27. It takes
  /// the tint tones of light glass in both appearances, and its glint
  /// brightens its own face rather than pulling toward a fixed bright
  /// target.
  ///
  /// With [highContrast], clear glass darkens its face under a black
  /// fill and dims its rim highlight, as under iOS 27's Increase Contrast
  /// setting.
  const factory LiquidGlassColorModel.ios27Clear({
    required Brightness brightness,
    bool highContrast,
  }) = LiquidGlassIos27ClearColorModel._;

  /// The lens iOS 27 lifts out of a held control over its selection, as a
  /// tab bar's or a segmented control's, in [brightness].
  ///
  /// Its face changes no colour, its rim highlight is resting regular glass's
  /// and its dark specular is its own, darker and reaching a third of a point
  /// into the glass. It blurs and fills what it shows as regular glass of
  /// [brightness] does. Its ring and drop shadows are the widget's to draw.
  /// The numbers are those UIKit gives a held lens on iOS 27.2.1, the same
  /// from 37 to 70 points, so glass of every size wears one look.
  const factory LiquidGlassColorModel.ios27Lens({
    required Brightness brightness,
  }) = LiquidGlassIos27LensColorModel._;

  /// The lens of a held switch's knob or slider's thumb in [brightness]:
  /// [LiquidGlassColorModel.ios27Lens] whose face lifts black to a tenth of
  /// white and leaves white where it is.
  const factory LiquidGlassColorModel.ios27SmallLens({
    required Brightness brightness,
  }) = LiquidGlassIos27LensColorModel._small;
}

/// The [LiquidGlassColorModel] that applies its numbers directly
/// ([LiquidGlassColorModel.direct]).
final class LiquidGlassDirectColorModel extends LiquidGlassColorModel {
  const LiquidGlassDirectColorModel._({
    required this.brightness,
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
    double? glintStrength,
    double? contourStrength,
    double? contourDirectionality,
    double? bevelShadowStrength,
  }) : glintStrength = glintStrength ?? _regularGlintStrength,
       contourStrength =
           contourStrength ??
           (brightness == Brightness.dark
               ? _darkContourStrength
               : _lightContourStrength),
       contourDirectionality =
           contourDirectionality ??
           (brightness == Brightness.dark ? 1 : _lightContourDirectionality),
       bevelShadowStrength = bevelShadowStrength ?? _regularBevelShadowStrength,
       super._();

  static const double _regularGlintStrength = 0.6;
  static const double _lightContourStrength = 0.43;
  static const double _darkContourStrength = 0.88;
  static const double _lightContourDirectionality = 0.77;
  static const double _regularBevelShadowStrength = 0.036;

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied per channel to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  /// The scheme of the glass, whose rim and blur it takes.
  final Brightness brightness;

  /// Strength of the glint along the light axis.
  ///
  /// The glint recolors the face instead of adding white: it pulls the lit
  /// material toward a target brighter than SDR white carrying the face's own
  /// chroma amplified, so glass over color glints in that color. iOS 27
  /// glass glints at `0.6` in both schemes: the reference rim is a soft, low
  /// plateau, and higher values overexpose the first pixel inside the
  /// silhouette.
  final double glintStrength;

  /// Peak absorption of the dark contour just outside the silhouette, which
  /// is 0.75 logical pixels wide. `0` removes the contour.
  final double contourStrength;

  /// How strongly the contour concentrates where the glint fades.
  ///
  /// `0` darkens the whole silhouette evenly. `1` keeps the contour only where
  /// the normal is perpendicular to the light axis and removes it where the
  /// glint sits, as in iOS 27 dark mode.
  final double contourDirectionality;

  /// Fraction of the light transmitted through the glass that the inner
  /// shadow cast by the rim absorbs at its peak. The glass's own emission is
  /// not shaded. The shadow falls 6 pt below the lit top wall, stays at the
  /// rim on the sides and is absent at the bottom, as on iOS 27.
  final double bevelShadowStrength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassDirectColorModel &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy &&
          other.brightness == brightness &&
          other.glintStrength == glintStrength &&
          other.contourStrength == contourStrength &&
          other.contourDirectionality == contourDirectionality &&
          other.bevelShadowStrength == bevelShadowStrength;

  @override
  int get hashCode => Object.hash(
    saturation,
    transmissionGamma,
    vibrancy,
    brightness,
    glintStrength,
    contourStrength,
    contourDirectionality,
    bevelShadowStrength,
  );

  @override
  String toString() =>
      'LiquidGlassColorModel.direct(saturation: $saturation, '
      'transmissionGamma: $transmissionGamma, vibrancy: $vibrancy, '
      'brightness: $brightness, glintStrength: $glintStrength, '
      'contourStrength: $contourStrength, '
      'contourDirectionality: $contourDirectionality, '
      'bevelShadowStrength: $bevelShadowStrength)';
}

/// The [LiquidGlassColorModel] of iOS 27 regular glass
/// ([LiquidGlassColorModel.ios27Regular]).
final class LiquidGlassIos27RegularColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27RegularColorModel._({
    required this.brightness,
    this.highContrast = false,
  }) : super._();

  /// The colour scheme of the glass.
  final Brightness brightness;

  /// Whether the glass takes the face of the Increase Contrast setting.
  final bool highContrast;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassIos27RegularColorModel &&
          other.brightness == brightness &&
          other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(brightness, highContrast);

  @override
  String toString() =>
      'LiquidGlassColorModel.ios27Regular(brightness: $brightness'
      '${highContrast ? ', highContrast: true' : ''})';
}

/// The [LiquidGlassColorModel] of iOS 27 clear glass
/// ([LiquidGlassColorModel.ios27Clear]).
final class LiquidGlassIos27ClearColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27ClearColorModel._({
    required this.brightness,
    this.highContrast = false,
  }) : super._();

  /// The colour scheme of the glass, which only Reduce Transparency's fill
  /// reads.
  final Brightness brightness;

  /// Whether the glass takes the face of the Increase Contrast setting.
  final bool highContrast;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassIos27ClearColorModel &&
      other.brightness == brightness &&
      other.highContrast == highContrast;

  @override
  int get hashCode =>
      Object.hash(LiquidGlassIos27ClearColorModel, brightness, highContrast);

  @override
  String toString() =>
      'LiquidGlassColorModel.ios27Clear(brightness: $brightness'
      '${highContrast ? ', highContrast: true' : ''})';
}

/// The [LiquidGlassColorModel] of a lens iOS 27 lifts out of a held control
/// ([LiquidGlassColorModel.ios27Lens], [LiquidGlassColorModel.ios27SmallLens]).
final class LiquidGlassIos27LensColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27LensColorModel._({required this.brightness})
    : small = false,
      super._();

  const LiquidGlassIos27LensColorModel._small({required this.brightness})
    : small = true,
      super._();

  /// The colour scheme of the glass, whose blur and fill it takes.
  final Brightness brightness;

  /// Whether the lens is a knob's or a thumb's, whose face lifts black.
  final bool small;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassIos27LensColorModel &&
      other.brightness == brightness &&
      other.small == small;

  @override
  int get hashCode =>
      Object.hash(LiquidGlassIos27LensColorModel, brightness, small);

  @override
  String toString() =>
      'LiquidGlassColorModel.${small ? 'ios27SmallLens' : 'ios27Lens'}'
      '(brightness: $brightness)';
}

/// What an iOS 27 recipe takes that a shape's look decides: the variant,
/// the scheme, the shape's shorter side in points, whether its tint is a
/// grey, which takes a tint law of its own, the Increase Contrast setting,
/// and whether the glass is a lifted lens.
@internal
typedef RecipeLook = ({
  GlassVariant variant,
  Brightness brightness,
  double shortSide,
  bool greyTint,
  bool highContrast,
  GlassLift lift,
});

/// The rim the direct model lights ([LiquidGlassColorModel.direct]); none
/// for an iOS 27 recipe, whose rim is its own.
@internal
@immutable
final class DirectRim {
  /// A rim of these strengths.
  const DirectRim({
    required this.glintStrength,
    required this.contourStrength,
    required this.contourDirectionality,
    required this.bevelShadowStrength,
  });

  /// No rim.
  static const none = DirectRim(
    glintStrength: 0,
    contourStrength: 0,
    contourDirectionality: 0,
    bevelShadowStrength: 0,
  );

  /// [LiquidGlassDirectColorModel.glintStrength].
  final double glintStrength;

  /// [LiquidGlassDirectColorModel.contourStrength].
  final double contourStrength;

  /// [LiquidGlassDirectColorModel.contourDirectionality].
  final double contourDirectionality;

  /// [LiquidGlassDirectColorModel.bevelShadowStrength].
  final double bevelShadowStrength;

  /// The width of the dark contour in logical pixels; `0` without one.
  double get contourWidth => contourStrength > 0 ? GlassRim.contourWidth : 0;

  /// Whether the inner bevel shadow is drawn.
  bool get drawsBevelShadow =>
      bevelShadowStrength >= GlassRim.leastBevelShadowStrength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectRim &&
          other.glintStrength == glintStrength &&
          other.contourStrength == contourStrength &&
          other.contourDirectionality == contourDirectionality &&
          other.bevelShadowStrength == bevelShadowStrength;

  @override
  int get hashCode => Object.hash(
    glintStrength,
    contourStrength,
    contourDirectionality,
    bevelShadowStrength,
  );
}

/// How glass carries what it shows through the direct path's colour: the
/// saturation, display-referred transfer and backdrop-aware chroma lift the
/// lanes take.
@internal
typedef DirectTransfer = ({
  double saturation,
  double transmissionGamma,
  double vibrancy,
});

/// A [LiquidGlassColorModel] as glass of one size and tint wears it
/// ([WearColorModel.wornAt]): the constants the shaders take.
@internal
@immutable
sealed class WornColorModel {
  const WornColorModel();

  /// The direct model of these numbers.
  const factory WornColorModel.direct({
    required Brightness brightness,
    double saturation,
    double transmissionGamma,
    double vibrancy,
    DirectRim rim,
  }) = WornDirect;

  /// The iOS 27 recipe of [look] (`GlassRecipe.of`).
  const factory WornColorModel.recipe(RecipeLook look) = WornRecipe;

  /// How the glass carries what it shows through.
  DirectTransfer get transfer;

  /// The variant and scheme of iOS 27 glass whose blur and fill the glass
  /// takes: the recipe's, or regular glass of the direct model's scheme.
  ({GlassVariant variant, Brightness brightness}) get blurredAs;
}

/// The direct model as glass wears it.
@internal
final class WornDirect extends WornColorModel {
  /// The direct model of these numbers.
  const WornDirect({
    required this.brightness,
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
    this.rim = DirectRim.none,
  });

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied per channel to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  /// The scheme whose regular glass blurs and fills it.
  final Brightness brightness;

  /// The rim the model lights.
  final DirectRim rim;

  @override
  DirectTransfer get transfer => (
    saturation: saturation,
    transmissionGamma: transmissionGamma,
    vibrancy: vibrancy,
  );

  @override
  ({GlassVariant variant, Brightness brightness}) get blurredAs =>
      (variant: GlassVariant.regular, brightness: brightness);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WornDirect &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy &&
          other.rim == rim &&
          other.brightness == brightness;

  @override
  int get hashCode =>
      Object.hash(saturation, transmissionGamma, vibrancy, rim, brightness);

  @override
  String toString() =>
      'WornDirect($saturation, $transmissionGamma, $vibrancy, $brightness)';
}

/// An iOS 27 recipe as glass wears it: its face does the colour, so it
/// carries what the glass shows through as it is.
@internal
final class WornRecipe extends WornColorModel {
  /// The recipe of [look].
  const WornRecipe(this.look);

  /// What the recipe takes.
  final RecipeLook look;

  /// The transfer that leaves what the glass shows as it is.
  static const DirectTransfer identity = (
    saturation: 1,
    transmissionGamma: 1,
    vibrancy: 0,
  );

  @override
  DirectTransfer get transfer => identity;

  @override
  ({GlassVariant variant, Brightness brightness}) get blurredAs =>
      (variant: look.variant, brightness: look.brightness);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WornRecipe && other.look == look;

  @override
  int get hashCode => look.hashCode;

  @override
  String toString() => 'WornRecipe($look)';
}

/// Wears a color model at a size.
@internal
extension WearColorModel on LiquidGlassColorModel {
  /// The model as glass whose shorter side is [shortSide] points and whose
  /// tint is [tint] wears it.
  ///
  /// iOS 27 glass up to a control's side ([ios27SizeRamp]) wears one
  /// recipe and glass from a panel's another, so shapes that share a layer
  /// mostly share one; between the two each size wears its own. From a
  /// panel's side on only the rim highlight's spread still widens, by at
  /// most 3.3 degrees up to [recipeSizes]' panel, so such glass wears that
  /// one's: panels of one layer keep one recipe slot and the shader of one
  /// look. A grey tint takes another law than a colour. A lifted lens wears
  /// one recipe at every size.
  WornColorModel wornAt(double shortSide, {Color? tint}) {
    final grey =
        tint != null &&
        tint.a > 0 &&
        (tint.r - tint.g).abs() < 1 / 510 &&
        (tint.g - tint.b).abs() < 1 / 510;
    final side = shortSide >= ios27SizeRamp.panel
        ? recipeSizes.panel
        : math.max(shortSide, recipeSizes.control);
    switch (this) {
      case final LiquidGlassDirectColorModel direct:
        return _wearDirect(direct);
      case LiquidGlassIos27ClearColorModel(
        :final brightness,
        :final highContrast,
      ):
        return _wear((
          variant: GlassVariant.clear,
          brightness: brightness,
          shortSide: side,
          greyTint: grey,
          highContrast: highContrast,
          lift: GlassLift.resting,
        ));
      case LiquidGlassIos27RegularColorModel(
        :final brightness,
        :final highContrast,
      ):
        return _wear((
          variant: GlassVariant.regular,
          brightness: brightness,
          shortSide: side,
          greyTint: grey,
          highContrast: highContrast,
          lift: GlassLift.resting,
        ));
      case LiquidGlassIos27LensColorModel(:final brightness, :final small):
        return _wear((
          variant: GlassVariant.regular,
          brightness: brightness,
          shortSide: recipeSizes.control,
          greyTint: grey,
          highContrast: false,
          lift: small ? GlassLift.smallLens : GlassLift.lens,
        ));
    }
  }

  static WornColorModel _wear(RecipeLook look) {
    final side = look.shortSide;
    if (side > recipeSizes.control && side < recipeSizes.panel) {
      return WornColorModel.recipe(look);
    }
    return _worn[look] ??= WornColorModel.recipe(look);
  }

  static WornColorModel _wearDirect(LiquidGlassDirectColorModel direct) =>
      WornColorModel.direct(
        saturation: direct.saturation,
        transmissionGamma: direct.transmissionGamma,
        vibrancy: direct.vibrancy,
        brightness: direct.brightness,
        rim: DirectRim(
          glintStrength: direct.glintStrength,
          contourStrength: direct.contourStrength,
          contourDirectionality: direct.contourDirectionality,
          bevelShadowStrength: direct.bevelShadowStrength,
        ),
      );

  static final _worn = <RecipeLook, WornColorModel>{};
}

/// The shorter sides, in points, between which an iOS 27 recipe changes
/// with the size of its glass: every law of the size holds still up to
/// `control` and from `panel` on.
@internal
final recipeSizes = (
  control: ios27SizeRamp.control,
  panel: ios27RimSpreadRamp.to,
);
