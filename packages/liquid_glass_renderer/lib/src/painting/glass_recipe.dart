import 'dart:math' as math;
import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe_groups.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';

/// Which of iOS 27's two glass materials a [GlassRecipe] is for.
enum GlassVariant {
  /// `Glass.regular`, which Apple also uses for toolbars, `.glass` buttons
  /// and tinted and prominent glass.
  regular,

  /// `Glass.clear`, identical in light and dark.
  clear,
}

/// Everything one glass shape draws with, as iOS 27 sets it for the shape's
/// size: refraction, blur, blur fill, face, bleed, shadows, dark edge, rim
/// highlight and tint.
///
/// [GlassRecipe.of] gives the recipe of iOS 27 glass; [GlassRecipe.lerp]
/// crosses between two, for a theme that springs from light to dark, a tint
/// that fades in, regular glass that morphs into clear, or glass that grows
/// into a panel of the window. [GlassRecipeOverrides] leaves Apple's look on
/// purpose.
@immutable
final class GlassRecipe {
  /// A recipe of the given groups.
  const GlassRecipe({
    required this.refraction,
    required this.blur,
    required this.blurFill,
    required this.face,
    required this.bleed,
    required this.dropShadow,
    required this.ringShadow,
    required this.darkSpecular,
    required this.rimHighlight,
    this.tint = TintRecipe.none,
  });

  /// iOS 27 glass of [variant] in [brightness] whose shorter side is
  /// [shortSide] logical pixels, at the Liquid Glass slider position
  /// [slider], with the system's [increaseContrast] and
  /// [reduceTransparency], tinted with [tint].
  ///
  /// Every value follows a law of the size, the slider, the scheme and the
  /// variant read from UIKit on iOS 27.0 and 27.2 (notes private); on the
  /// iOS 27.2 simulator none of the values it gives lies off what UIKit
  /// sets, across buttons, panels and clear glass, light and dark, the
  /// slider at 0 to 1 and both accessibility settings, alone and together.
  ///
  /// The slider snaps to steps of 0.05, as iOS's does. Glass grows from a
  /// control's to a panel's between 64 and 160 points
  /// ([ios27PanelProgress]); the slider acts at one rate up to its middle
  /// tick and at another past it ([splitAtMiddleTick]).
  ///
  /// Increase Contrast changes only the face: less saturation, a lighter
  /// floor and a more opaque white fill in light, a dark grey ceiling in
  /// dark, a black fill on clear glass with a weaker rim highlight. Reduce
  /// Transparency takes away the refraction, the ring shadow and the bleed,
  /// blurs widely inside and flattens the face under a fill. With both,
  /// Increase Contrast's face wins, its white fill no thinner than Reduce
  /// Transparency's.
  ///
  /// The tint follows a law that is exact for fully saturated colours (HSV
  /// saturation and value 1) and NEAR for others; a grey (no saturation)
  /// takes a law of its own, and which of the two a colour takes is ours.
  /// Clear glass takes the light law in both schemes. The tint's alpha is
  /// how strongly it replaces the face.
  factory GlassRecipe.of({
    required GlassVariant variant,
    required Brightness brightness,
    required double shortSide,
    double slider = 0,
    bool increaseContrast = false,
    bool reduceTransparency = false,
    Color? tint,
  }) {
    final law = _Law(
      variant: variant,
      dark: brightness == Brightness.dark,
      shortSide: shortSide,
      slider: snapSlider(slider),
      increaseContrast: increaseContrast,
      reduceTransparency: reduceTransparency,
    );
    return GlassRecipe(
      refraction: law.refraction(),
      blur: law.blur(),
      blurFill: law.blurFill(),
      face: law.face(),
      bleed: law.bleed(),
      dropShadow: law.dropShadow(),
      ringShadow: law.ringShadow(),
      darkSpecular: law.darkSpecular(),
      rimHighlight: law.rimHighlight(),
      tint: tint == null || tint.a == 0
          ? TintRecipe.none
          : _tintOf(tint, dark: variant == GlassVariant.regular && law.dark),
    );
  }

  /// The recipe [t] of the way from [a] to [b], group by group.
  factory GlassRecipe.lerp(GlassRecipe a, GlassRecipe b, double t) {
    if (identical(a, b) || t == 0) return a;
    if (t == 1) return b;
    return GlassRecipe(
      refraction: RefractionRecipe.lerp(a.refraction, b.refraction, t),
      blur: BlurRecipe.lerp(a.blur, b.blur, t),
      blurFill: BlurFillRecipe.lerp(a.blurFill, b.blurFill, t),
      face: FaceRecipe.lerp(a.face, b.face, t),
      bleed: BleedRecipe.lerp(a.bleed, b.bleed, t),
      dropShadow: DropShadowRecipe.lerp(a.dropShadow, b.dropShadow, t),
      ringShadow: RingShadowRecipe.lerp(a.ringShadow, b.ringShadow, t),
      darkSpecular: DarkSpecularRecipe.lerp(a.darkSpecular, b.darkSpecular, t),
      rimHighlight: RimHighlightRecipe.lerp(a.rimHighlight, b.rimHighlight, t),
      tint: TintRecipe.lerp(a.tint, b.tint, t),
    );
  }

  /// How the glass bends what lies under it at its edge.
  final RefractionRecipe refraction;

  /// How the glass blurs what it shows, by depth.
  final BlurRecipe blur;

  /// The wide blur mixed into what the glass shows.
  final BlurFillRecipe blurFill;

  /// The colour of the glass's face.
  final FaceRecipe face;

  /// The veil of what lies outside large glass, over its face.
  final BleedRecipe bleed;

  /// The shadow the glass casts below itself.
  final DropShadowRecipe dropShadow;

  /// The dark band inside the glass's top edge.
  final RingShadowRecipe ringShadow;

  /// The dark line just outside the glass's edge.
  final DarkSpecularRecipe darkSpecular;

  /// The lit rim of the glass.
  final RimHighlightRecipe rimHighlight;

  /// How a tint recolours the face; [TintRecipe.none] without one.
  final TintRecipe tint;

  /// A copy with the given groups replaced.
  GlassRecipe copyWith({
    RefractionRecipe? refraction,
    BlurRecipe? blur,
    BlurFillRecipe? blurFill,
    FaceRecipe? face,
    BleedRecipe? bleed,
    DropShadowRecipe? dropShadow,
    RingShadowRecipe? ringShadow,
    DarkSpecularRecipe? darkSpecular,
    RimHighlightRecipe? rimHighlight,
    TintRecipe? tint,
  }) => GlassRecipe(
    refraction: refraction ?? this.refraction,
    blur: blur ?? this.blur,
    blurFill: blurFill ?? this.blurFill,
    face: face ?? this.face,
    bleed: bleed ?? this.bleed,
    dropShadow: dropShadow ?? this.dropShadow,
    ringShadow: ringShadow ?? this.ringShadow,
    darkSpecular: darkSpecular ?? this.darkSpecular,
    rimHighlight: rimHighlight ?? this.rimHighlight,
    tint: tint ?? this.tint,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassRecipe &&
          other.refraction == refraction &&
          other.blur == blur &&
          other.blurFill == blurFill &&
          other.face == face &&
          other.bleed == bleed &&
          other.dropShadow == dropShadow &&
          other.ringShadow == ringShadow &&
          other.darkSpecular == darkSpecular &&
          other.rimHighlight == rimHighlight &&
          other.tint == tint;

  @override
  int get hashCode => Object.hash(
    refraction,
    blur,
    blurFill,
    face,
    bleed,
    dropShadow,
    ringShadow,
    darkSpecular,
    rimHighlight,
    tint,
  );

  @override
  String toString() =>
      'GlassRecipe($refraction, $blur, $blurFill, $face, $bleed, '
      '$dropShadow, $ringShadow, $darkSpecular, $rimHighlight, $tint)';
}

/// Changes to a [GlassRecipe] that leave Apple's look, for an app that
/// wants glass of its own: each scales a part of the recipe, 1 keeping it.
@immutable
final class GlassRecipeOverrides {
  /// Overrides that scale the refraction's amounts, the blur's radius, the
  /// shadows' opacity and the rim highlight's opacity.
  const GlassRecipeOverrides({
    this.refraction = 1,
    this.blur = 1,
    this.shadows = 1,
    this.highlight = 1,
  });

  /// The overrides [t] of the way from [a] to [b].
  factory GlassRecipeOverrides.lerp(
    GlassRecipeOverrides a,
    GlassRecipeOverrides b,
    double t,
  ) => GlassRecipeOverrides(
    refraction: a.refraction + (b.refraction - a.refraction) * t,
    blur: a.blur + (b.blur - a.blur) * t,
    shadows: a.shadows + (b.shadows - a.shadows) * t,
    highlight: a.highlight + (b.highlight - a.highlight) * t,
  );

  /// How far the glass bends what lies under its edge, against iOS's.
  final double refraction;

  /// How widely the glass blurs what it shows, against iOS's.
  final double blur;

  /// How dark the drop and ring shadows are, against iOS's; 0 draws none.
  final double shadows;

  /// How strongly the rim highlight brightens, against iOS's; 0 draws none.
  final double highlight;

  /// Whether these overrides change nothing.
  bool get isIdentity =>
      refraction == 1 && blur == 1 && shadows == 1 && highlight == 1;

  /// [recipe] with these overrides applied.
  GlassRecipe apply(GlassRecipe recipe) => isIdentity
      ? recipe
      : recipe.copyWith(
          refraction: recipe.refraction.scaled(refraction),
          blur: recipe.blur.scaled(blur),
          dropShadow: recipe.dropShadow.scaled(shadows),
          ringShadow: recipe.ringShadow.scaled(shadows),
          rimHighlight: recipe.rimHighlight.scaled(highlight),
        );

  @override
  bool operator ==(Object other) =>
      other is GlassRecipeOverrides &&
      other.refraction == refraction &&
      other.blur == blur &&
      other.shadows == shadows &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(refraction, blur, shadows, highlight);

  @override
  String toString() =>
      'GlassRecipeOverrides(refraction: $refraction, blur: $blur, '
      'shadows: $shadows, highlight: $highlight)';
}

/// [slider] within 0..1, snapped to the steps of 0.05 iOS's Liquid Glass
/// slider takes.
double snapSlider(double slider) =>
    (clampDouble(slider, 0, 1) * 20).roundToDouble() / 20;

final class _Law {
  _Law({
    required this.variant,
    required this.dark,
    required this.shortSide,
    required this.slider,
    required this.increaseContrast,
    required this.reduceTransparency,
  }) : grown = ios27PanelProgress(shortSide),
       split = splitAtMiddleTick(slider);

  final GlassVariant variant;
  final bool dark;
  final double shortSide;
  final double slider;
  final bool increaseContrast;
  final bool reduceTransparency;
  final double grown;
  final ({double upTo, double past}) split;

  bool get clear => variant == GlassVariant.clear;

  RefractionRecipe refraction() {
    if (reduceTransparency) return RefractionRecipe.none;
    final s = shortSide;
    if (clear) {
      return RefractionRecipe(
        innerAmount: math.min(0.65 * s, 60),
        innerHeight: math.min(0.36 * s, 20),
        outerAmount: s / 5,
        outerHeight: s / 8,
        outerOpacity: 0,
      );
    }
    return RefractionRecipe(
      innerAmount: math.min(s / 2, 60),
      innerHeight: math.min(s / 4, 20),
      outerAmount: math.max(16, s / 4),
      outerHeight: math.max(16, s / 5),
      outerOpacity: 0.6,
    );
  }

  BlurRecipe blur() {
    final depths = [shortSide / 2, 1.0, 0.0, 0.0];
    BlurRecipe ramp(double radius, List<double> strengths) => BlurRecipe(
      radius: radius,
      stops: [
        for (var i = 0; i < 4; i++) (depth: depths[i], strength: strengths[i]),
      ],
    );
    if (reduceTransparency) {
      if (clear) return ramp(50, const [1, 1, 1, 1]);
      final radius = 35 + 15 * grown;
      final edge = 5 / radius;
      return ramp(radius, [1, 1, edge, edge]);
    }
    if (clear) {
      final on = slider > 0 ? 1.0 : 0.0;
      return ramp(1.5 * split.upTo, [on, 0.5 * on, 0.5 * on, on]);
    }
    return ramp(5, [0.8 * grown, 0.4 * grown, 0.5, 1]);
  }

  BlurFillRecipe blurFill() {
    if (clear) {
      return BlurFillRecipe(
        radius: slider > sliderMiddleTick ? 8 : 0,
        lighten: 0,
        darken: 0,
        cover: 2 * split.past,
      );
    }
    final mix = 0.675 + 0.45 * split.upTo;
    return BlurFillRecipe(
      radius: 8,
      lighten: dark ? 0 : mix,
      darken: dark ? mix : 0,
      cover: slider,
    );
  }

  FaceRecipe face() {
    var face = _restingFace();
    if (reduceTransparency) face = _flatFace(face);
    if (increaseContrast) face = _contrastFace(face);
    return face;
  }

  FaceRecipe _restingFace() {
    if (clear) {
      return const FaceRecipe(
        black: 0.125,
        white: 1.08,
        saturation: 1.06,
        fill: Color(0x00FFFFFF),
        maxLuma: 1,
        maxLumaWithoutHeadroom: 1,
      );
    }
    final (:upTo, :past) = split;
    if (dark) {
      final grey = 0.125 * (1 - 2 * slider).abs();
      final towardPanel = clampDouble((shortSide - 64) / 40, 0, 1);
      final maxLuma = 0.6 + (0.45 - 0.2 * upTo - 0.6) * towardPanel;
      return FaceRecipe(
        black: 0.125,
        white: 1.125,
        saturation: 1.3,
        fill: Color.from(alpha: past, red: grey, green: grey, blue: grey),
        maxLuma: maxLuma,
        maxLumaWithoutHeadroom: maxLuma,
      );
    }
    return FaceRecipe(
      black: 0.4,
      white: 1.03,
      saturation: 1.2,
      fill: Color.from(
        alpha: 0.4 * upTo + 0.6 * past,
        red: 1,
        green: 1,
        blue: 1,
      ),
      maxLuma: 1,
      maxLumaWithoutHeadroom: 0.94,
    );
  }

  FaceRecipe _flatFace(FaceRecipe resting) {
    final (:upTo, :past) = split;
    if (clear) {
      return FaceRecipe(
        black: 0.125,
        white: 0,
        saturation: dark ? 0.7 : 0.9,
        fill: dark
            ? const Color.from(alpha: 0.25, red: 0, green: 0, blue: 0)
            : const Color.from(alpha: 0.25, red: 1, green: 1, blue: 1),
        maxLuma: resting.maxLuma,
        maxLumaWithoutHeadroom: resting.maxLumaWithoutHeadroom,
      );
    }
    if (dark) {
      return FaceRecipe(
        black: 0.2,
        white: 0.2,
        saturation: 0.7,
        fill: Color.from(
          alpha: 1.2 * upTo - 0.2 * past,
          red: 0,
          green: 0,
          blue: 0,
        ),
        maxLuma: resting.maxLuma,
        maxLumaWithoutHeadroom: resting.maxLumaWithoutHeadroom,
      );
    }
    return FaceRecipe(
      black: 0.9,
      white: resting.white,
      saturation: 0.9,
      fill: Color.from(
        alpha: 1.6 * upTo - 0.6 * past,
        red: 1,
        green: 1,
        blue: 1,
      ),
      maxLuma: resting.maxLuma,
      maxLumaWithoutHeadroom: resting.maxLumaWithoutHeadroom,
    );
  }

  FaceRecipe _contrastFace(FaceRecipe under) {
    if (clear) {
      return FaceRecipe(
        black: 0.1,
        white: 0.6,
        saturation: 0.8,
        fill: const Color.from(alpha: 0.35, red: 0, green: 0, blue: 0),
        maxLuma: under.maxLuma,
        maxLumaWithoutHeadroom: under.maxLumaWithoutHeadroom,
      );
    }
    if (dark) {
      return FaceRecipe(
        black: 0.1,
        white: 0.3,
        saturation: 0.8,
        fill: const Color.from(alpha: 0.4, red: 0.12, green: 0.12, blue: 0.12),
        maxLuma: under.maxLuma,
        maxLumaWithoutHeadroom: under.maxLumaWithoutHeadroom,
      );
    }
    return FaceRecipe(
      black: 0.5,
      white: under.white,
      saturation: 0.8,
      fill: Color.from(
        alpha: math.max(0.45, under.fill.a),
        red: 1,
        green: 1,
        blue: 1,
      ),
      maxLuma: under.maxLuma,
      maxLumaWithoutHeadroom: under.maxLumaWithoutHeadroom,
    );
  }

  BleedRecipe bleed() {
    if (clear) {
      return const BleedRecipe(
        amount: 0,
        blurRadius: 0,
        opacity: 0,
        black: 0.75,
        white: 1,
        saturation: 1.2,
        onBright: 1,
      );
    }
    final amount = 0.35 * shortSide;
    final blurRadius = reduceTransparency || shortSide <= 64 ? 0.0 : amount;
    final opacity = reduceTransparency ? 0.0 : (dark ? 0.8 : 0.5) * grown;
    return dark
        ? BleedRecipe(
            amount: amount,
            blurRadius: blurRadius,
            opacity: opacity,
            black: 0.125,
            white: 0.5,
            saturation: 1,
            onBright: 0,
          )
        : BleedRecipe(
            amount: amount,
            blurRadius: blurRadius,
            opacity: opacity,
            black: 0.9,
            white: 1,
            saturation: 1.2,
            onBright: 1,
          );
  }

  DropShadowRecipe dropShadow() {
    if (clear) {
      return const DropShadowRecipe(
        radius: 0,
        opacity: 0,
        color: Color.from(alpha: 0.1, red: 0, green: 0, blue: 0),
      );
    }
    return DropShadowRecipe(
      radius: 4 + 20 * grown,
      opacity: 0.04 + (dark ? 0.56 : 0.36) * grown,
    );
  }

  RingShadowRecipe ringShadow() {
    if (clear || reduceTransparency) return RingShadowRecipe.none;
    return const RingShadowRecipe(
      opacity: 0.06,
      offset: 8,
      strokeWidth: 4,
      blurRadius: 5,
    );
  }

  DarkSpecularRecipe darkSpecular() {
    final lightRegular = !clear && !dark;
    return DarkSpecularRecipe(
      amount: 0.4,
      width: 8 / 15,
      offset: -8 / 15,
      colorBias: -0.3,
      spread: _degrees(lightRegular ? 96 : 75),
      spreadWithoutHeadroom: _degrees(lightRegular ? 106 : 75),
    );
  }

  RimHighlightRecipe rimHighlight() {
    final spread = _degrees(
      80 + 10 * clampDouble((shortSide - 96) / 96, 0, 1),
    );
    final opacity = clear && increaseContrast ? 0.55 : 1.0;
    return clear
        ? RimHighlightRecipe(
            width: 1,
            diffuseWidth: 8,
            diffuseAmount: 0.15,
            diffuseSpread: 0.65,
            spread: spread,
            curvature: 0.75,
            opacity: opacity,
            black: 0.2,
            white: 1.4666,
            saturation: 1.3334,
          )
        : RimHighlightRecipe(
            width: 1,
            diffuseWidth: 8,
            diffuseAmount: 0.15,
            diffuseSpread: 0.65,
            spread: spread,
            curvature: 0.75,
            opacity: opacity,
            black: 0.1471,
            white: 1.0588,
            saturation: 1.1765,
          );
  }
}

double _degrees(double degrees) => degrees * math.pi / 180;

TintRecipe _tintOf(Color tint, {required bool dark}) {
  final law = tintLaw(
    dark: dark,
    grey: tint.r == tint.g && tint.g == tint.b,
  );
  TintEnd end(double scale, double bias, double floor) => (
    red: math.max(floor, scale * tint.r + bias),
    green: math.max(floor, scale * tint.g + bias),
    blue: math.max(floor, scale * tint.b + bias),
  );
  return TintRecipe(
    low: end(law.lowScale, law.lowBias, law.lowFloor),
    high: end(law.highScale, law.highBias, -1),
    lumaWeight: law.lumaWeight,
    opacity: tint.a,
  );
}

/// The law a tint's ramp follows over each of the tint's channels c: where
/// the face is black a channel becomes the larger of `lowFloor` and
/// `lowScale * c + lowBias`, where it is white `highScale * c + highBias`.
/// The face's brightness runs by its luma where `lumaWeight` is 1 and by
/// each channel where it is 0.
@internal
typedef TintLaw = ({
  double lowScale,
  double lowBias,
  double lowFloor,
  double highScale,
  double highBias,
  double lumaWeight,
});

/// The tint law of glass in the dark scheme ([dark]; clear glass takes the
/// light one) for a grey tint ([grey]) or a colour.
@internal
TintLaw tintLaw({required bool dark, required bool grey}) {
  if (grey) {
    return (
      lowScale: 1.1875,
      lowBias: -0.25,
      lowFloor: -1,
      highScale: 1.1875,
      highBias: -0.25 + 0.31,
      lumaWeight: 0,
    );
  }
  return dark
      ? (
          lowScale: 1.0362,
          lowBias: -0.0306,
          lowFloor: -1,
          highScale: 0.7946,
          highBias: 0.1735,
          lumaWeight: 1,
        )
      : (
          lowScale: 0.6706,
          lowBias: -0.0706,
          lowFloor: 0,
          highScale: 1,
          highBias: 0,
          lumaWeight: 1,
        );
}
