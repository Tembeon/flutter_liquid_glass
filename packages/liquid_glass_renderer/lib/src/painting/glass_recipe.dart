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

/// Whether a [GlassRecipe] is for glass at rest or for a lens lifted out of
/// it while held.
enum GlassLift {
  /// Glass at rest.
  resting,

  /// The lens lifted over a selection, as of a tab bar or a segmented
  /// control: its face changes no colour.
  lens,

  /// The lens of a switch's knob or a slider's thumb: its face lifts black
  /// to a tenth of white and leaves white where it is.
  smallLens,
}

/// What one glass shape draws with, as iOS 27 sets it for the shape's size:
/// blur, blur fill, face, bleed, ring shadow, dark edge and rim highlight.
///
/// The rest of iOS 27's glass is drawn from elsewhere: its refraction from
/// the layer's settings, its drop shadow from [ios27DropShadow], and its
/// tint by [tintLaw].
@immutable
final class GlassRecipe {
  /// A recipe of the given groups.
  const GlassRecipe({
    required this.blur,
    required this.blurFill,
    required this.face,
    required this.bleed,
    required this.ringShadow,
    required this.darkSpecular,
    required this.rimHighlight,
  });

  /// iOS 27 glass of [variant] in [brightness] whose shorter side is
  /// [shortSide] logical pixels, at the Liquid Glass slider position
  /// [slider], with the system's [highContrast].
  ///
  /// Every value follows a law of the size, the slider, the scheme and the
  /// variant read from UIKit on iOS 27.0 and 27.2 (notes private); on the
  /// iOS 27.2 simulator none of the values it gives lies off what UIKit
  /// sets, across buttons, panels and clear glass, light and dark, the
  /// slider at 0 to 1 and Increase Contrast, as a display with headroom
  /// above white shows them.
  ///
  /// The slider snaps to steps of 0.05, as iOS's does. Glass grows from a
  /// control's to a panel's between 64 and 160 points
  /// ([ios27PanelProgress]), but for dark glass's luma cap
  /// ([ios27DarkFaceRamp]) and the rim highlight's spread
  /// ([ios27RimSpreadRamp]); the slider acts at one rate up to its middle
  /// tick and at another past it ([splitAtMiddleTick]).
  ///
  /// Increase Contrast changes only the face: less saturation, a lighter
  /// floor and a more opaque white fill in light, a dark grey ceiling in
  /// dark, a black fill on clear glass with a weaker rim highlight. Reduce
  /// Transparency ([reduceTransparency]) blurs what the glass shows widely
  /// (35 points on a control's glass to 50 on a panel's, 5 at its edge, and
  /// 50 all through clear glass), lays a nearly flat face over it (light
  /// glass lifts black to 90 % under a white fill that rises to the slider's
  /// middle tick and falls past it, dark glass keeps a fifth of white under a
  /// black fill, clear glass a fill of a quarter in its scheme), and draws no
  /// ring shadow or veil; Increase Contrast's face lies over it.
  ///
  /// A lifted lens ([lift]) keeps the resting glass's rim highlight and draws
  /// its own face, its own dark specular (0.5 dark, a point wide from a third
  /// of a point inside the edge, over 120 degrees in both schemes) and no
  /// bleed or ring shadow, as read from UIKit with each lens
  /// held on iOS 27.2.1 (notes private); its ring and drop shadows are the
  /// widget's to draw. Its values are the same from 37 to 70 points. Reduce
  /// Transparency leaves its recipe as it is (27.2 simulator): it takes
  /// away only the lens's bend, which its settings' refraction draws.
  factory GlassRecipe.of({
    required GlassVariant variant,
    required Brightness brightness,
    required double shortSide,
    double slider = 0,
    bool highContrast = false,
    bool reduceTransparency = false,
    GlassLift lift = GlassLift.resting,
  }) {
    final law = _Law(
      variant: variant,
      dark: brightness == Brightness.dark,
      shortSide: shortSide,
      slider: snapSlider(slider),
      highContrast: highContrast,
      reduceTransparency: reduceTransparency,
      lift: lift,
    );
    return GlassRecipe(
      blur: law.blur(),
      blurFill: law.blurFill(),
      face: law.face(),
      bleed: law.bleed(),
      ringShadow: law.ringShadow(),
      darkSpecular: law.darkSpecular(),
      rimHighlight: law.rimHighlight(),
    );
  }

  /// How the glass blurs what it shows, by depth.
  final BlurRecipe blur;

  /// The wide blur mixed into what the glass shows.
  final BlurFillRecipe blurFill;

  /// The colour of the glass's face.
  final FaceRecipe face;

  /// The veil of what lies outside large glass, over its face.
  final BleedRecipe bleed;

  /// The dark band inside the glass's top edge.
  final RingShadowRecipe ringShadow;

  /// The dark line just outside the glass's edge.
  final DarkSpecularRecipe darkSpecular;

  /// The lit rim of the glass.
  final RimHighlightRecipe rimHighlight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassRecipe &&
          other.blur == blur &&
          other.blurFill == blurFill &&
          other.face == face &&
          other.bleed == bleed &&
          other.ringShadow == ringShadow &&
          other.darkSpecular == darkSpecular &&
          other.rimHighlight == rimHighlight;

  @override
  int get hashCode => Object.hash(
    blur,
    blurFill,
    face,
    bleed,
    ringShadow,
    darkSpecular,
    rimHighlight,
  );

  @override
  String toString() =>
      'GlassRecipe($blur, $blurFill, $face, $bleed, $ringShadow, '
      '$darkSpecular, $rimHighlight)';
}

/// The shadow iOS 27 glass of [variant] in [brightness] casts when its
/// shorter side is [shortSide] logical pixels: none under clear glass, and
/// under regular glass one that grows from a control's to a panel's
/// ([ios27PanelProgress]). Increase Contrast and the slider leave it as it
/// is.
@internal
DropShadowRecipe ios27DropShadow({
  required GlassVariant variant,
  required Brightness brightness,
  required double shortSide,
}) {
  if (variant == GlassVariant.clear) {
    return const DropShadowRecipe(
      radius: 0,
      opacity: 0,
      color: Color.from(alpha: 0.1, red: 0, green: 0, blue: 0),
    );
  }
  final grown = ios27PanelProgress(shortSide);
  return DropShadowRecipe(
    radius: 4 + 20 * grown,
    opacity: 0.04 + (brightness == Brightness.dark ? 0.56 : 0.36) * grown,
  );
}

/// [slider] within 0..1, snapped to the steps of 0.05 iOS's Liquid Glass
/// slider takes.
double snapSlider(double slider) =>
    (clampDouble(slider, 0, 1) * 20).roundToDouble() / 20;

// How far past the glass iOS captures what lies under it, in points: 16 for
// regular glass, and for clear glass past the slider's middle tick.
const double _captureMargin = 16;

// The capture margin of clear glass up to the slider's middle tick.
const double _clearMargin = 8 / 15;

final class _Law {
  _Law({
    required this.variant,
    required this.dark,
    required this.shortSide,
    required this.slider,
    required this.highContrast,
    required this.reduceTransparency,
    required this.lift,
  }) : grown = ios27PanelProgress(shortSide),
       split = splitAtMiddleTick(slider);

  final GlassVariant variant;
  final bool dark;
  final double shortSide;
  final double slider;
  final bool highContrast;
  final bool reduceTransparency;
  final GlassLift lift;
  final double grown;
  final ({double upTo, double past}) split;

  bool get clear => variant == GlassVariant.clear;

  bool get lifted => lift != GlassLift.resting;

  BlurRecipe blur() {
    final depths = [shortSide / 2, 1.0, 0.0, 0.0];
    BlurRecipe ramp(
      double radius,
      List<double> strengths, {
      double? margin,
    }) => BlurRecipe(
      radius: radius,
      stops: [
        for (var i = 0; i < 4; i++) (depth: depths[i], strength: strengths[i]),
      ],
      margin: margin,
    );
    if (reduceTransparency && !lifted) {
      if (clear) {
        return ramp(
          50,
          [1, 1, 1, 1],
          margin: slider > sliderMiddleTick ? _captureMargin : _clearMargin,
        );
      }
      final radius = 35 + 15 * grown;
      return ramp(radius, [
        1,
        1,
        5 / radius,
        5 / radius,
      ], margin: _captureMargin);
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
    switch (lift) {
      case GlassLift.lens:
        return const FaceRecipe(
          black: 0,
          white: 1,
          saturation: 1,
          fill: Color(0x00000000),
          maxLuma: 0,
        );
      case GlassLift.smallLens:
        return const FaceRecipe(
          black: 0.1,
          white: 1,
          saturation: 0.9,
          fill: Color(0x00000000),
          maxLuma: 0,
        );
      case GlassLift.resting:
        final resting = _restingFace();
        final face = reduceTransparency ? _transparencyFace(resting) : resting;
        return highContrast ? _contrastFace(face) : face;
    }
  }

  FaceRecipe _restingFace() {
    if (clear) {
      return const FaceRecipe(
        black: 0.125,
        white: 1.08,
        saturation: 1.06,
        fill: Color(0x00FFFFFF),
        maxLuma: 1,
      );
    }
    final (:upTo, :past) = split;
    if (dark) {
      final grey = 0.125 * (1 - 2 * slider).abs();
      final towardPanel = ios27RampProgress(ios27DarkFaceRamp, shortSide);
      final maxLuma = 0.6 + (0.45 - 0.2 * upTo - 0.6) * towardPanel;
      return FaceRecipe(
        black: 0.125,
        white: 1.125,
        saturation: 1.3,
        fill: Color.from(alpha: past, red: grey, green: grey, blue: grey),
        maxLuma: maxLuma,
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
    );
  }

  FaceRecipe _transparencyFace(FaceRecipe under) {
    final (:upTo, :past) = split;
    if (clear) {
      final page = dark ? 0.0 : 1.0;
      return FaceRecipe(
        black: 0.125,
        white: 0,
        saturation: dark ? 0.7 : 0.9,
        fill: Color.from(alpha: 0.25, red: page, green: page, blue: page),
        maxLuma: under.maxLuma,
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
        maxLuma: under.maxLuma,
      );
    }
    return FaceRecipe(
      black: 0.9,
      white: under.white,
      saturation: 0.9,
      fill: Color.from(
        alpha: 1.6 * upTo - 0.6 * past,
        red: 1,
        green: 1,
        blue: 1,
      ),
      maxLuma: under.maxLuma,
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
      );
    }
    if (dark) {
      return FaceRecipe(
        black: 0.1,
        white: 0.3,
        saturation: 0.8,
        fill: const Color.from(alpha: 0.4, red: 0.12, green: 0.12, blue: 0.12),
        maxLuma: under.maxLuma,
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
    );
  }

  BleedRecipe bleed() {
    if (lifted || reduceTransparency) return BleedRecipe.none;
    if (clear) {
      return const BleedRecipe(
        opacity: 0,
        black: 0.75,
        white: 1,
        saturation: 1.2,
        onBright: 1,
      );
    }
    final opacity = (dark ? 0.8 : 0.5) * grown;
    return dark
        ? BleedRecipe(
            opacity: opacity,
            black: 0.125,
            white: 0.5,
            saturation: 1,
            onBright: 0,
          )
        : BleedRecipe(
            opacity: opacity,
            black: 0.9,
            white: 1,
            saturation: 1.2,
            onBright: 1,
          );
  }

  RingShadowRecipe ringShadow() {
    if (clear || lifted || reduceTransparency) return RingShadowRecipe.none;
    return const RingShadowRecipe(
      opacity: 0.06,
      offset: 8,
      strokeWidth: 4,
      blurRadius: 5,
    );
  }

  DarkSpecularRecipe darkSpecular() {
    if (lifted) {
      return DarkSpecularRecipe(
        amount: 0.5,
        width: 1,
        outset: 2 / 3,
        colorBias: -0.3,
        spread: _degrees(120),
      );
    }
    final lightRegular = !clear && !dark;
    return DarkSpecularRecipe(
      amount: 0.4,
      width: 8 / 15,
      outset: 8 / 15,
      colorBias: -0.3,
      spread: _degrees(lightRegular ? 96 : 75),
    );
  }

  RimHighlightRecipe rimHighlight() {
    final spread = _degrees(
      80 + 10 * ios27RampProgress(ios27RimSpreadRamp, shortSide),
    );
    final opacity = clear && highContrast ? 0.55 : 1.0;
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
