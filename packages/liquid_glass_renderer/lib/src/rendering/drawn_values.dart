import 'dart:math' as math;
import 'dart:ui' show Brightness, clampDouble;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';

/// The values of [LensSettings] the shaders take: each clamped to the range
/// the renderer draws.
extension DrawnLens on LensSettings {
  /// [shrink] clamped to the range [LensSettings.shrink] gives.
  double get drawnShrink => shrink.clamp(0.0, 0.75);

  /// [pull] where it reaches anywhere, else `0`; never negative.
  double get drawnPull => pullDepth > 0 ? math.max(0, pull) : 0;

  /// [aberration] where it shows anywhere, else `0`; never negative.
  double get drawnAberration =>
      aberrationDepth > 0 ? math.max(0, aberration) : 0;
}

/// The values of [LiquidGlassSettings] the shaders take: each setting clamped
/// to the range the renderer draws, and what the passes derive from them.
extension DrawnSettings on LiquidGlassSettings {
  /// The bevel width; never negative.
  double get drawnRefractionHeight => math.max(0, refractionHeight);

  /// The edge displacement; never negative.
  double get drawnRefractionAmount => math.max(0, refractionAmount);

  /// The slider position, clamped to `0` to `1`.
  double get drawnSliderPosition => sliderPosition.clamp(0.0, 1.0);
}

/// A [LiquidShape] as the shaders take it.
extension DrawnShape on LiquidShape {
  /// The corner radius in logical pixels, the top corners' of a
  /// [LiquidRoundedSuperellipse]; `0` for an oval.
  double get cornerRadius => switch (this) {
    LiquidRoundedSuperellipse(:final topRadius) => topRadius,
    LiquidRoundedRectangle(:final radius) => radius,
    LiquidOval() => 0,
  };

  /// The radius of the two bottom corners in logical pixels: [cornerRadius]
  /// except on a [LiquidRoundedSuperellipse] with bottom corners of its own.
  double get bottomCornerRadius => switch (this) {
    LiquidRoundedSuperellipse(:final bottomRadius) => bottomRadius,
    _ => cornerRadius,
  };

  /// Whether the bottom corners differ from the top ones: the one rule that
  /// tells a [LiquidRoundedSuperellipse] drawn as two halves from one drawn
  /// whole.
  bool get isPair => bottomCornerRadius != cornerRadius;

  /// The kind of shape the shaders tell this one by.
  RawShapeType get rawType => switch (this) {
    LiquidRoundedSuperellipse() =>
      isPair ? RawShapeType.squirclePair : RawShapeType.squircle,
    LiquidOval() => RawShapeType.ellipse,
    LiquidRoundedRectangle() => RawShapeType.roundedRectangle,
  };
}

/// A [WornColorModel] as fake glass draws it.
extension DrawnColorModel on WornColorModel {
  /// The single surface tint fake glass paints for [tint].
  ///
  /// Fake glass cannot read the backdrop's luminance in its analytic surface
  /// shader, so a recipe's tint takes the middle of its ramp. The face
  /// itself is the backdrop color filter's, so it is not part of this color.
  Color approximateSurfaceTint(Color tint) {
    final look = recipe;
    if (look == null) return tint;
    if (tint.a <= 0) return const Color(0x00000000);
    final law = tintLawOf(look);
    double middle(double c) => clampDouble(
      (math.max(law.lowFloor, law.lowScale * c + law.lowBias) +
              law.highScale * c +
              law.highBias) /
          2,
      0,
      1,
    );
    return Color.from(
      alpha: tint.a,
      red: middle(tint.r),
      green: middle(tint.g),
      blue: middle(tint.b),
    );
  }
}

/// The tint law glass of [look] follows.
TintLaw tintLawOf(RecipeLook look) => tintLaw(
  dark:
      look.variant == GlassVariant.regular &&
      look.brightness == Brightness.dark,
  grey: look.greyTint,
);

/// The recipe of [look] at the Liquid Glass slider position
/// [sliderPosition].
GlassRecipe recipeOf(RecipeLook look, double sliderPosition) {
  final key = (look, sliderPosition);
  final cached = _recipes[key];
  if (cached != null) return cached;
  if (_recipes.length >= 64) _recipes.clear();
  return _recipes[key] = GlassRecipe.of(
    variant: look.variant,
    brightness: look.brightness,
    shortSide: look.shortSide,
    slider: sliderPosition,
    increaseContrast: look.increaseContrast,
  );
}

final _recipes = <(RecipeLook, double), GlassRecipe>{};

/// The floats of one slot of the final shader's uRecipes for [look] at the
/// slider position [sliderPosition], by [RecipeLane], its widths in device
/// pixels at [devicePixelRatio].
///
/// The rim highlight's line takes its full amount, 1, and its diffuse glow
/// the diffuse amount of it; each mask is biased by one over its amount
/// less two, as UIKit's. The dark specular lies its own width outside the
/// edge.
List<double> recipeLanes(
  RecipeLook look, {
  required double sliderPosition,
  required double devicePixelRatio,
}) {
  final key = (look, sliderPosition, devicePixelRatio);
  final cached = _recipeLanes[key];
  if (cached != null) return cached;
  if (_recipeLanes.length >= 64) _recipeLanes.clear();
  final dpr = devicePixelRatio;
  final recipe = recipeOf(look, sliderPosition);
  final face = recipe.face;
  final fill = face.fill;
  final bleed = recipe.bleed;
  final highlight = recipe.rimHighlight;
  final specular = recipe.darkSpecular;
  final ring = recipe.ringShadow;
  final law = tintLawOf(look);
  final lanes = laneBlock(RecipeLane.values, {
    RecipeLane.face: [face.black, face.white, face.saturation],
    RecipeLane.faceRollOff: [
      if (face.maxLuma <= 0) 0 else 1 - clampDouble(face.maxLuma, 0, 1),
    ],
    RecipeLane.faceFill: [
      fill.r * fill.a,
      fill.g * fill.a,
      fill.b * fill.a,
      fill.a,
    ],
    RecipeLane.bleed: [bleed.black, bleed.white, bleed.saturation],
    RecipeLane.bleedOpacity: [
      if (bleed.onBright >= 0.5) -bleed.opacity else bleed.opacity,
    ],
    RecipeLane.tintRamp: [
      law.lowScale,
      law.lowBias,
      law.highScale,
      law.highBias,
    ],
    RecipeLane.brighten: [
      highlight.black,
      highlight.white,
      highlight.saturation,
    ],
    RecipeLane.highlightOpacity: [highlight.opacity],
    RecipeLane.highlightWidth: [highlight.width * dpr],
    RecipeLane.highlightDiffuseWidth: [highlight.diffuseWidth * dpr],
    RecipeLane.highlightCurvature: [highlight.curvature],
    RecipeLane.tintLumaWeight: [law.lumaWeight],
    RecipeLane.highlightSpread: [
      math.cos(highlight.spread),
      math.cos(highlight.spread * highlight.diffuseSpread),
    ],
    RecipeLane.highlightDiffuseBias: [
      if (highlight.diffuseAmount > 0) 1 / highlight.diffuseAmount - 2 else 0,
    ],
    RecipeLane.tintFloor: [law.lowFloor],
    RecipeLane.specularBias: [
      if (specular.amount > 0) 1 / specular.amount - 2 else 0,
    ],
    RecipeLane.specularWidth: [specular.width * dpr],
    RecipeLane.specularColorBias: [
      if (specular.amount > 0) specular.colorBias else 0,
    ],
    RecipeLane.specularSpread: [math.cos(specular.spread)],
    RecipeLane.ringOpacity: [if (ring.blurRadius > 0) ring.opacity else 0],
    RecipeLane.ringOffset: [ring.offset * dpr],
    RecipeLane.ringStroke: [ring.strokeWidth * dpr],
    RecipeLane.ringInverseRadius: [
      if (ring.blurRadius > 0) 1 / (ring.blurRadius * dpr) else 0,
    ],
  });
  return _recipeLanes[key] = lanes;
}

final _recipeLanes = <(RecipeLook, double, double), List<double>>{};

/// How far the edges the recipes of [looks] draw reach, in logical pixels:
/// into the glass, its rim highlight and its ring shadow's band two sigmas
/// past the moved outline, and out of it, its dark specular band.
({double inward, double outward}) recipeEdges(
  List<RecipeLook> looks,
  double sliderPosition,
) {
  var inward = 0.0;
  var outward = 0.0;
  for (final look in looks) {
    final recipe = recipeOf(look, sliderPosition);
    final ring = recipe.ringShadow;
    if (ring.opacity > 0 && ring.blurRadius > 0) {
      inward = math.max(
        inward,
        ring.offset + ring.strokeWidth + 2 * ring.blurRadius,
      );
    }
    final highlight = recipe.rimHighlight;
    if (highlight.opacity > 0) {
      inward = math.max(
        inward,
        math.max(highlight.width, highlight.diffuseWidth),
      );
    }
    if (recipe.darkSpecular.amount > 0) {
      outward = math.max(outward, recipe.darkSpecular.width);
    }
  }
  return (inward: inward, outward: outward);
}

/// A [WornAppearance] as a layer draws it.
extension DrawnAppearance on WornAppearance {
  /// Whether glass in this appearance shows at all.
  bool get shows => visibility > 0;
}

/// A glow that draws: one with a wash or a spot.
extension type const DrawnGlow._(LiquidGlassGlow _glow)
    implements LiquidGlassGlow {
  /// [glow] where it draws, else null.
  static DrawnGlow? of(LiquidGlassGlow? glow) {
    if (glow == null) return null;
    final drawn = DrawnGlow._(glow);
    return drawn.drawsWash || drawn.drawsSpot ? drawn : null;
  }

  /// Whether the spot brightens anything: it has a gain and a radius.
  bool get drawsSpot => gain > 0 && radius > 0;

  /// Whether the wash raises the channels.
  bool get drawsWash => wash > 0;
}

/// The glow's lanes of the final shader's uEffects: glowSpot, glowBox and
/// glowWash.
typedef GlowUniforms = Map<EffectsLane, List<double>>;

/// The glow of a layer whose glass glows nowhere.
const GlowUniforms noGlowUniforms = {
  EffectsLane.glowSpot: [0, 0, 0, 0],
  EffectsLane.glowBox: [0, 0, 0, 0],
  EffectsLane.glowWash: [0],
};

/// The glow of [glow] on a shape that [toLayer] maps into a layer whose
/// matte has [devicePixelRatio] device pixels per unit.
///
/// The spot's radius goes in as its falloff `log2(e) / (2 sigma^2)` per
/// squared device pixel, so the shader's Gaussian is one exp2 with no divide.
GlowUniforms glowUniforms(
  DrawnGlow glow, {
  required Matrix4 toLayer,
  required Rect? box,
  required double devicePixelRatio,
}) {
  final dpr = devicePixelRatio;
  final m = toLayer.storage;
  final stretch = math.sqrt((m[0] * m[5] - m[1] * m[4]).abs());
  final sigma = glow.radius * stretch * dpr;
  final spot = glow.drawsSpot && sigma > 0;
  final center = MatrixUtils.transformPoint(toLayer, glow.center) * dpr;
  final lit = box == null ? null : MatrixUtils.transformRect(toLayer, box);
  return Map.unmodifiable(<EffectsLane, List<double>>{
    EffectsLane.glowSpot: [
      center.dx,
      center.dy,
      if (spot) math.log2e / (2 * sigma * sigma) else 0,
      if (spot) glow.gain else 0,
    ],
    EffectsLane.glowBox: lit == null
        ? const [0, 0, _unboxed, _unboxed]
        : [
            lit.center.dx * dpr,
            lit.center.dy * dpr,
            lit.width / 2 * dpr + _antialiasedEdgeRoom,
            lit.height / 2 * dpr + _antialiasedEdgeRoom,
          ],
    EffectsLane.glowWash: [if (glow.drawsWash) glow.wash else 0],
  });
}

const double _unboxed = 1000000;

const double _antialiasedEdgeRoom = 1;
