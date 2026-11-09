import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';

/// How the appearances of a layer's shapes differ: not at all (`uniform` is
/// the one), by tint alone (`tintOnly`, `uniform` the first), or otherwise
/// (`mixed` without `uniform`).
@internal
typedef AppearanceKind = ({
  bool mixed,
  bool tintOnly,
  LiquidGlassAppearance? uniform,
});

/// How [appearances] differ; [fallback] stands for none.
@internal
AppearanceKind classifyAppearances(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (
    mixed: mixed,
    tintOnly: tintOnly,
    uniform: tintOnly || !mixed ? first : null,
  );
}

/// The adaptive color models of [appearances], then of [fallback], in
/// shader slot order.
///
/// `uColorModelParams` holds at most three distinct models; extra models
/// fold onto the first slot. The direct model needs no slot: it always
/// takes code 0. The shaded models come first, so a layer of one iOS 27
/// model has it in the first slot, which its one-model variant reads.
@internal
List<GlassColorParameters> colorModelSlots(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final slots = <GlassColorParameters>[];
  void add(LiquidGlassAppearance appearance) {
    final parameters = appearance.colorModel.parameters;
    if (parameters != null && !slots.contains(parameters) && slots.length < 3) {
      slots.add(parameters);
    }
  }

  appearances.forEach(add);
  add(fallback);
  return List.unmodifiable(slots);
}

/// The shader's model code for [model]: 0 direct, 1..3 slot index.
@internal
double colorModelCode(
  LiquidGlassColorModel model,
  List<GlassColorParameters> slots,
) {
  final parameters = model.parameters;
  if (parameters == null) return 0;
  // The slots hold the appearances' own parameter objects, so a model
  // finds its slot by identity before a field-by-field comparison.
  var index = slots.indexWhere((slot) => identical(slot, parameters));
  if (index < 0) index = slots.indexOf(parameters);
  // Models beyond the third fold onto the first slot.
  return (index.clamp(0, 2) + 1).toDouble();
}

/// The color models [shaded] needs: the direct model alone, one iOS 27
/// model in the first slot, or any.
@internal
FinalShaderModels colorModelFamily(List<LiquidGlassAppearance> shaded) {
  final first = shaded.first.colorModel.parameters;
  for (final appearance in shaded) {
    if (appearance.colorModel.parameters != first) {
      return FinalShaderModels.all;
    }
  }
  return first == null ? FinalShaderModels.direct : FinalShaderModels.ios27;
}

/// The rows of tints and material factors the matte's material map is
/// drawn from, one per shape of [appearances], [fallback] past them.
///
/// Only mixed frames draw it, so rows past the shapes take the fallback,
/// never a uniform appearance of another frame.
@internal
List<double> appearanceLookupData(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final colorModels = colorModelSlots(appearances, fallback);
  LiquidGlassAppearance at(int index) =>
      index < appearances.length ? appearances[index] : fallback;
  return <double>[
    for (var i = 0; i < geometryMaxShapesPerDraw; i++) ...<double>[
      at(i).tint.r,
      at(i).tint.g,
      at(i).tint.b,
      at(i).tint.a,
    ],
    for (var i = 0; i < geometryMaxShapesPerDraw; i++) ...<double>[
      at(i).colorModel.saturation / 4,
      at(i).colorModel.transmissionGamma / 4,
      at(i).colorModel.vibrancy / 4,
      (at(i).visibility + colorModelCode(at(i).colorModel, colorModels) * 2) /
          7,
    ],
  ];
}
