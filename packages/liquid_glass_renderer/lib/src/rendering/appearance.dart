import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// An appearance as glass of one size wears it ([WearAppearance.wear]): its
/// color model resolved for that size and its tint, its visibility the
/// drawn one ([drawnVisibility]).
@internal
@immutable
final class WornAppearance {
  /// The worn appearance of these values.
  const WornAppearance({
    required this.tint,
    required this.visibility,
    required this.colorModel,
  });

  /// The tint ([LiquidGlassAppearance.tint]).
  final Color tint;

  /// The drawn visibility, within zero to one.
  final double visibility;

  /// The color model at the size and under the tint.
  final WornColorModel colorModel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WornAppearance &&
          other.tint == tint &&
          other.visibility == visibility &&
          other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tint, visibility, colorModel);

  /// Untinted glass of the direct model that lights no rim, at full
  /// visibility.
  static const unlit = WornAppearance(
    tint: Color(0x00000000),
    visibility: 1,
    colorModel: WornColorModel.direct(brightness: Brightness.light),
  );

  @override
  String toString() => 'WornAppearance($tint, $visibility, $colorModel)';
}

/// Wears an appearance at a size: the one way glass asks what its size
/// makes of its look.
@internal
extension WearAppearance on LiquidGlassAppearance {
  /// This appearance as glass of [size] wears it.
  WornAppearance wear(Size size) => WornAppearance(
    tint: tint,
    visibility: drawnVisibility(visibility),
    colorModel: colorModel.wornAt(size.shortestSide, tint: tint),
  );

  /// This appearance where no shape wears it: its color model a panel's,
  /// whatever its tint.
  WornAppearance get wornByNone => WornAppearance(
    tint: tint,
    visibility: drawnVisibility(visibility),
    colorModel: colorModel.wornAt(double.infinity),
  );
}

/// The appearance glass shows: its [own], else its layer's [layerDefault],
/// faded by the [visibility] around it.
@internal
LiquidGlassAppearance shownAppearance(
  LiquidGlassAppearance? own, {
  required LiquidGlassAppearance layerDefault,
  required double visibility,
}) => fadedAppearance(own ?? layerDefault, visibility);

/// [appearance] faded by the [visibility] around it.
@internal
LiquidGlassAppearance fadedAppearance(
  LiquidGlassAppearance appearance,
  double visibility,
) => appearance.copyWith(visibility: appearance.visibility * visibility);

/// The appearances of a layer's shapes, by how they differ: not at all, by
/// tint alone, or otherwise; one kind of the final shader's look each.
@internal
@immutable
sealed class ShapeAppearances {
  const ShapeAppearances(this.all);

  /// How [appearances] differ; [fallback] stands for none.
  factory ShapeAppearances.of(
    List<WornAppearance> appearances,
    WornAppearance fallback,
  ) {
    final all = List<WornAppearance>.unmodifiable(appearances);
    final first = all.isEmpty ? fallback : all.first;
    if (all.every((appearance) => appearance == first)) {
      return OneAppearance(first, all);
    }
    final tinted = all.every(
      (appearance) =>
          appearance.visibility == first.visibility &&
          appearance.colorModel == first.colorModel,
    );
    return tinted ? TintedAppearances(all) : MixedAppearances(all, fallback);
  }

  /// The shapes' appearances, in paint order.
  final List<WornAppearance> all;

  /// The kind of look the final shader draws them with.
  FinalShaderKind get kind;

  /// The appearances the glass shades: the one, or each shape's.
  List<WornAppearance> get shaded => all;

  /// The appearance the glass's face is made from: the one, the first of
  /// appearances that differ by tint alone, or the layer's own where they
  /// differ otherwise.
  WornAppearance get face;

  @override
  bool operator ==(Object other) =>
      other is ShapeAppearances &&
      other.runtimeType == runtimeType &&
      other.face == face &&
      listEquals(other.all, all);

  @override
  int get hashCode => Object.hash(runtimeType, face, Object.hashAll(all));
}

/// Appearances that are all one.
@internal
final class OneAppearance extends ShapeAppearances {
  /// The appearances [all], each [face], or none.
  const OneAppearance(this.face, super.all);

  @override
  final WornAppearance face;

  @override
  FinalShaderKind get kind => FinalShaderKind.single;

  @override
  List<WornAppearance> get shaded => [face];
}

/// Appearances that differ by tint alone.
@internal
final class TintedAppearances extends ShapeAppearances {
  /// The appearances [all].
  const TintedAppearances(super.all);

  @override
  WornAppearance get face => all.first;

  @override
  FinalShaderKind get kind => FinalShaderKind.tint;
}

/// Appearances that differ by more than their tint.
@internal
final class MixedAppearances extends ShapeAppearances {
  /// The appearances [all], beside the layer's own [face].
  const MixedAppearances(super.all, this.face);

  @override
  final WornAppearance face;

  @override
  FinalShaderKind get kind => FinalShaderKind.material;
}

/// The iOS 27 recipes of [appearances], then of [fallback] where a slot is
/// left, in shader slot order.
///
/// Where the appearances wear more than the slots
/// ([overflowsColorModelSlots]), each kind of glass (a look but for its
/// size) takes a slot first, in their order, and sizes fill the slots left:
/// the looks without a slot draw with the slot nearest them
/// (colorModelCode).
@internal
List<RecipeLook> colorModelSlots(
  List<WornAppearance> appearances,
  WornAppearance fallback,
) {
  final recipes = _distinctRecipes(appearances);
  final slots = recipes.length <= colorModelSlotCount
      ? recipes
      : <RecipeLook>[];
  if (recipes.length > colorModelSlotCount) {
    for (final look in recipes) {
      if (slots.length < colorModelSlotCount &&
          !slots.any((slot) => _sameKind(slot, look))) {
        slots.add(look);
      }
    }
    for (final look in recipes) {
      if (slots.length < colorModelSlotCount && !slots.contains(look)) {
        slots.add(look);
      }
    }
  }
  if (fallback.colorModel case WornRecipe(:final look)
      when slots.length < colorModelSlotCount && !slots.contains(look)) {
    slots.add(look);
  }
  return List.unmodifiable(slots);
}

/// Whether [appearances] wear more iOS 27 recipes than the final shader has
/// slots for ([colorModelSlots]).
@internal
bool overflowsColorModelSlots(List<WornAppearance> appearances) =>
    _distinctRecipes(appearances).length > colorModelSlotCount;

List<RecipeLook> _distinctRecipes(List<WornAppearance> appearances) => [
  ...{
    for (final appearance in appearances)
      if (appearance.colorModel case WornRecipe(:final look)) look,
  },
];

bool _sameKind(RecipeLook a, RecipeLook b) =>
    a.variant == b.variant &&
    a.brightness == b.brightness &&
    a.greyTint == b.greyTint &&
    a.highContrast == b.highContrast &&
    a.lift == b.lift;

// The slot of [slots] that [look] draws with: its own, or the one whose
// recipe lies nearest it, compared from what shows most: brightness,
// regular or clear, the lens's lift, contrast and a grey tint, then size.
int _slotOf(RecipeLook look, List<RecipeLook> slots) {
  final own = slots.indexOf(look);
  if (own >= 0 || slots.isEmpty) return own < 0 ? 0 : own;
  List<num> distance(RecipeLook slot) => [
    if (slot.brightness == look.brightness) 0 else 1,
    if (slot.variant == look.variant) 0 else 1,
    if (slot.lift == look.lift) 0 else 1,
    (slot.highContrast == look.highContrast ? 0 : 1) +
        (slot.greyTint == look.greyTint ? 0 : 1),
    (slot.shortSide - look.shortSide).abs(),
  ];
  bool nearer(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  var nearest = 0;
  var nearestDistance = distance(slots.first);
  for (var i = 1; i < slots.length; i++) {
    final next = distance(slots[i]);
    if (nearer(next, nearestDistance)) {
      nearest = i;
      nearestDistance = next;
    }
  }
  return nearest;
}

/// The recipes glass of [appearances] draws, or [fallback]'s where there
/// are none.
@internal
List<RecipeLook> drawnRecipes(
  List<WornAppearance> appearances,
  WornAppearance fallback,
) => [
  for (final appearance in appearances.isEmpty ? [fallback] : appearances)
    if (appearance.colorModel case WornRecipe(:final look)) look,
];

/// The shader's model code for [model]: 0 direct, else its slot, from 1: a
/// recipe without a slot of its own takes the slot nearest it.
@internal
double colorModelCode(WornColorModel model, List<RecipeLook> slots) =>
    switch (model) {
      WornDirect() => 0,
      WornRecipe(:final look) => (_slotOf(look, slots) + 1).toDouble(),
    };

/// The color models [shaded] needs: the direct model alone, one iOS 27
/// recipe in the first slot, or any.
@internal
FinalShaderModels colorModelFamily(List<WornAppearance> shaded) {
  final first = shaded.first.colorModel;
  bool sameAsFirst(WornAppearance appearance) =>
      switch ((appearance.colorModel, first)) {
        (WornDirect(), WornDirect()) => true,
        (WornRecipe(:final look), WornRecipe(look: final firstLook)) =>
          look == firstLook,
        _ => false,
      };
  if (!shaded.every(sameAsFirst)) return FinalShaderModels.all;
  return switch (first) {
    WornDirect() => FinalShaderModels.direct,
    WornRecipe() => FinalShaderModels.ios27,
  };
}

/// The looks of a buffer's shapes, one appearance a shape, their color
/// models in the slots [colorModels] holds (colorModelSlots); [tintOnly]
/// where only their tints differ.
@internal
ShapeLooks shapeLooks(
  List<WornAppearance> appearances, {
  required List<RecipeLook> colorModels,
  required bool tintOnly,
}) {
  return ShapeLooks([
    for (final appearance in appearances)
      ...laneBlock(LookLane.values, {
        LookLane.tint: [
          appearance.tint.r,
          appearance.tint.g,
          appearance.tint.b,
          appearance.tint.a,
        ],
        LookLane.saturation: [appearance.colorModel.transfer.saturation],
        LookLane.transmissionGamma: [
          appearance.colorModel.transfer.transmissionGamma,
        ],
        LookLane.vibrancy: [appearance.colorModel.transfer.vibrancy],
        LookLane.visibilityAndModel: [
          lookVisibilityAndModel(
            appearance.visibility,
            colorModelCode(appearance.colorModel, colorModels),
          ),
        ],
      }),
  ], tintOnly: tintOnly);
}
