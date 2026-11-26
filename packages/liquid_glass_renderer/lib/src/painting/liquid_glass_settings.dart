import 'dart:math' as math;

import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/lens_settings.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:meta/meta.dart';

/// The short sides, in logical pixels, where the fitted frost response of
/// [glassFrostSigma] bends: it rises from `small` through
/// the toolbar's and a large control's, and grows no more past `largest`.
@internal
const frostFitShortSides = (
  small: 63.0,
  toolbar: 94.0,
  large: 118.0,
  largest: 150.0,
);

// The fitted frost, in logical pixels, fitted to iOS 27 at each of
// frostFitShortSides: cards and sheets diffuse more than controls.
const _frostFitSigmas = (
  small: _minBlurPassSigma,
  toolbar: _regularFrostAtClear,
  large: 5.6,
  largest: 8.0,
);

// Smallest non-zero base blur, in logical pixels, used as a floor and by
// clear glass at tinted slider positions. A fitted frost is raised further,
// per device, at render time ([glassFrostSigma]).
const double _minBlurPassSigma = 2.1;

// Base frost of regular glass at slider position `0`, in logical pixels.
// Fitted to the pinned iOS 27 captures; [ios27RegularFrost] starts here and
// grows with the slider.
const double _regularFrostAtClear = 4.5;

// `5.8` device px reaches ImpellerBlur.halfResolutionSigma through
// ImpellerBlur.deviceSigma at every device pixel ratio from 2 and stays
// below `2.1 * 3 = 6.3`, so 3x screens keep the `2.1` floor
// (frost_floor_test.dart).
const double _frostFloorDevicePx = 5.8;

/// The optics of the glass a layer draws: its lens, and how far it blurs
/// what lies under it.
///
/// The color, the material and the lit rim of each shape belong to its
/// [LiquidGlassAppearance] and its [LiquidGlassColorModel]: settings of one
/// lens draw any of them.
///
/// The defaults of the unnamed constructor may be retuned before 1.0; the
/// version-named presets (`ios27*`) track Apple's glass on that OS version.
/// `LiquidGlassMaterial` gives settings with the appearance and the shadows
/// that match them.
@immutable
final class LiquidGlassSettings {
  /// Creates settings from optical controls.
  ///
  /// The defaults are iOS 27 regular glass's
  /// ([LiquidGlassSettings.ios27Regular]). Distances are logical pixels.
  const LiquidGlassSettings({
    this.refractionHeight = _defaultRefractionHeight,
    this.refractionAmount = _defaultRefractionAmount,
    this.refractionFitsShape = true,
    this.lens = LensSettings.none,
    this.sliderPosition = 0,
    this.blur,
  });

  /// The lens of iOS 27 regular glass (`Glass.regular`, which Apple also
  /// uses for toolbars and `.glass` buttons) at the Liquid Glass slider
  /// position [sliderPosition]: the 20 pt / 60 pt bevel, fitted to smaller
  /// shapes ([refractionFitsShape]), and the [blur] of the glass's look
  /// unless one is given.
  ///
  /// This is a useful starting point, not a universal Apple-material preset:
  /// platform materials vary with appearance, control role, and accessibility
  /// settings.
  const LiquidGlassSettings.ios27Regular({this.sliderPosition = 0, this.blur})
    : refractionHeight = _defaultRefractionHeight,
      refractionAmount = _defaultRefractionAmount,
      refractionFitsShape = true,
      lens = LensSettings.none;

  /// The lens of iOS 27 `Glass.clear` at the Liquid Glass slider position
  /// [sliderPosition]: the full 20 pt / 60 pt bevel on glass from 93 points
  /// on its short side, narrowing with smaller glass; see
  /// [refractionFitsShape]. Pair it with [LiquidGlassAppearance.ios27Clear],
  /// whose glass the slider alone blurs unless a [blur] is given: at slider
  /// 0 it is completely clear and unblurred.
  const LiquidGlassSettings.ios27Clear({this.sliderPosition = 0, this.blur})
    : refractionHeight = _defaultRefractionHeight,
      refractionAmount = _defaultRefractionAmount,
      refractionFitsShape = false,
      lens = LensSettings.none;

  static const double _defaultRefractionHeight = 20;
  static const double _defaultRefractionAmount = 60;

  /// Width of the refracting bevel in logical pixels, measured inward from
  /// the silhouette.
  ///
  /// Glass is modeled as a flat face with a rounded bevel of this width.
  /// Only the bevel refracts; the face beyond it shows the backdrop
  /// undisplaced. Apple calls this the refraction height; iOS 27 glass
  /// measures `20`, Apple's text loupe `8`. See [refractionFitsShape] for how
  /// small shapes limit it.
  final double refractionHeight;

  /// How far inside the silhouette, in logical pixels, the outermost pixel
  /// of the glass samples the backdrop.
  ///
  /// The displacement falls off across the bevel as a quarter circle,
  /// `refractionAmount * (1 - sqrt(1 - x * x))` with `x` going from `1` at
  /// the silhouette to `0` at [refractionHeight], so the bevel joins the
  /// face without a crease. The ratio to [refractionHeight] sets how
  /// rod-like the rim reads: above `1`, content near the rim is mirrored.
  /// iOS 27 glass measures `60`, Apple's text loupe `28`. `0` disables
  /// refraction.
  final double refractionAmount;

  /// Whether small shapes shrink the lens to fit.
  ///
  /// When `true`, as on iOS 27 regular glass, buttons and toolbars, the
  /// bevel is at most a quarter of the shape's short side and the rim
  /// samples no deeper than the shape's center line. A 63 pt tall button
  /// therefore refracts with a height of about `16` and an amount of about
  /// `32`, while large surfaces keep the configured values.
  ///
  /// When `false`, as on iOS 27 `.clear` glass, the bevel is at most 0.36
  /// of the shape's short side and the rim samples up to 0.65 of it inside,
  /// past the center line of a small shape, which mirrors what lies there. A
  /// 44 pt tall button refracts with a height of about `16` and an amount of
  /// about `29`.
  ///
  /// When `true`, glass more than 64 logical pixels across its short side
  /// also bends the backdrop partly toward its center instead of straight
  /// in from its edge, as iOS 27 regular glass does: what shows through the
  /// rim of a card or a tall capsule leans along the edge near its corners.
  /// Shapes of a `LiquidGlassBlendGroup` do so together, by the size of the
  /// largest of them. Glass no larger, and `.clear` glass, bends straight in.
  ///
  /// Shapes of a `LiquidGlassBlendGroup` also share one lens, sized by the
  /// smallest of them, as the elements of an iOS 27 glass container do.
  final bool refractionFitsShape;

  /// What the glass does as a lens to what lies under it: its pull,
  /// shrink, colour parting and dispersion. [LensSettings.none], the
  /// default, does none of these.
  final LensSettings lens;

  /// Position of the iOS 27 Liquid Glass slider in Settings, from `0`
  /// (Clear) to `1` (Tinted). It is not a color: a shape's color is its
  /// [LiquidGlassAppearance.tint].
  ///
  /// Apps set this themselves; the renderer does not read the system value.
  /// The slider makes the iOS 27 neutral wash more opaque and strengthens
  /// its dark contour, and a [blur] left null follows it; the direct color
  /// model ignores it.
  final double sliderPosition;

  /// How far the glass blurs what it shows, as the sigma of a Gaussian in
  /// logical pixels, or null, the default, for iOS 27's blur of each
  /// shape's look.
  ///
  /// Null follows [sliderPosition], the size of the glass and the display,
  /// and where the glass reads a copy of what lies under it, it also mixes
  /// in the wide blur iOS 27 fills that glass with. A number blurs the whole
  /// face by that much and fills nothing; `0` does not blur. The renderer
  /// may round the blur it applies.
  final double? blur;

  /// Returns a copy with the supplied controls replaced. A [blur] given
  /// replaces this one; settings that blur as their look does are made
  /// anew.
  LiquidGlassSettings copyWith({
    double? refractionHeight,
    double? refractionAmount,
    bool? refractionFitsShape,
    LensSettings? lens,
    double? sliderPosition,
    double? blur,
  }) => LiquidGlassSettings(
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    refractionFitsShape: refractionFitsShape ?? this.refractionFitsShape,
    lens: lens ?? this.lens,
    sliderPosition: sliderPosition ?? this.sliderPosition,
    blur: blur ?? this.blur,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassSettings &&
          other.refractionHeight == refractionHeight &&
          other.refractionAmount == refractionAmount &&
          other.refractionFitsShape == refractionFitsShape &&
          other.lens == lens &&
          other.sliderPosition == sliderPosition &&
          other.blur == blur;

  @override
  int get hashCode => Object.hash(
    refractionHeight,
    refractionAmount,
    refractionFitsShape,
    lens,
    sliderPosition,
    blur,
  );

  @override
  String toString() =>
      'LiquidGlassSettings($refractionHeight, $refractionAmount, '
      '$refractionFitsShape, $lens, $sliderPosition, $blur)';
}

/// The one blur, in logical pixels, that glass blurs what it shows by where
/// a single blur stands in for iOS 27's: [blur] as given (a negative one as
/// `0`), or else iOS 27's for glass of [variant] at [sliderPosition], whose
/// short side is [shapeShortSide] logical pixels (toolbar size without one),
/// on a display of [devicePixelRatio] device pixels per logical pixel.
///
/// iOS 27's grows with the short side and is raised for the display; `0`
/// stays `0`. Pass the smaller axis scale when [devicePixelRatio] is not
/// uniform.
@internal
double glassFrostSigma({
  required double? blur,
  required double sliderPosition,
  required GlassVariant variant,
  required double devicePixelRatio,
  double? shapeShortSide,
}) => frostSigmaOf(
  glassFrostBase(blur: blur, sliderPosition: sliderPosition, variant: variant),
  fitted: blur == null,
  devicePixelRatio: devicePixelRatio,
  shapeShortSide: shapeShortSide,
);

/// [glassFrostSigma] at toolbar size before the display raises it.
@internal
double glassFrostBase({
  required double? blur,
  required double sliderPosition,
  required GlassVariant variant,
}) => switch ((blur, variant)) {
  (final sigma?, _) => math.max(0, sigma),
  (null, GlassVariant.regular) => ios27RegularFrost(sliderPosition),
  (null, GlassVariant.clear) =>
    sliderPosition <= 0
        ? 0
        : math.max(_minBlurPassSigma, ios27ClearFrost(sliderPosition)),
};

/// The blur of [LiquidGlassSettings] for glass wearing a color model.
@internal
extension GlassFrost on LiquidGlassSettings {
  /// [glassFrostSigma] of glass wearing [model].
  double frostSigmaAt(
    WornColorModel model,
    double devicePixelRatio, {
    double? shapeShortSide,
  }) => glassFrostSigma(
    blur: blur,
    sliderPosition: sliderPosition,
    variant: model.blurredAs.variant,
    devicePixelRatio: devicePixelRatio,
    shapeShortSide: shapeShortSide,
  );

  /// [glassFrostBase] of glass wearing [model].
  double frostBaseOf(WornColorModel model) => glassFrostBase(
    blur: blur,
    sliderPosition: sliderPosition,
    variant: model.blurredAs.variant,
  );
}

/// Backdrop blur of iOS 27 regular glass, in logical pixels, at toolbar size
/// for the Liquid Glass slider position [sliderPosition] where one blur
/// stands in for iOS 27's: 4.5, 6.9 and 18.7 pt at 0, 0.5 and 1
/// ([glassFrostSigma]).
@internal
double ios27RegularFrost(double sliderPosition) {
  final amount = sliderPosition.clamp(0.0, 1.0);
  final (:upTo, :past) = splitAtMiddleTick(amount);
  return _regularFrostAtClear * math.exp(0.85 * upTo + 2 * past);
}

/// Apple's measured backdrop blur of iOS 27 `.clear` glass, in logical
/// pixels, for the Liquid Glass slider position [sliderPosition]: 0.35, 1.28
/// and 16.4 pt at 0, 0.5 and 1 ([glassFrostSigma] draws none at `0` and
/// floors tinted positions at `2.1`).
@internal
double ios27ClearFrost(double sliderPosition) {
  final amount = sliderPosition.clamp(0.0, 1.0);
  final (:upTo, :past) = splitAtMiddleTick(amount);
  return 0.35 * math.exp(2.6 * upTo + 5.1 * past);
}

/// [glassFrostSigma] of a blur at toolbar size of [frost], fitted to iOS 27
/// where [fitted].
@internal
double frostSigmaOf(
  double frost, {
  required bool fitted,
  required double devicePixelRatio,
  double? shapeShortSide,
}) {
  final sigma = math.max<double>(0, frost);
  if (!fitted || sigma <= 0) return sigma;
  var sizedSigma = sigma;
  if (shapeShortSide != null && shapeShortSide > 0) {
    double smooth(double t) {
      final clamped = t.clamp(0.0, 1.0);
      return clamped * clamped * (3 - 2 * clamped);
    }

    final (:small, :toolbar, :large, :largest) = frostFitShortSides;
    const fit = _frostFitSigmas;
    final sizeFrost =
        fit.small +
        (fit.toolbar - fit.small) *
            smooth((shapeShortSide - small) / (toolbar - small)) +
        (fit.large - fit.toolbar) *
            smooth((shapeShortSide - toolbar) / (large - toolbar)) +
        (fit.largest - fit.large) *
            ((shapeShortSide - large) / (largest - large)).clamp(0.0, 1.0);
    final sizeScale = sizeFrost / fit.toolbar;
    sizedSigma = math.max(
      _minBlurPassSigma,
      sigma * sizeScale,
    );
  }
  return math.max(
    sizedSigma,
    _frostFloorDevicePx / math.max(devicePixelRatio, 2.0),
  );
}
