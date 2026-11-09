import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// What a final shader variant reads its geometry and appearance from.
@internal
enum FinalShaderKind {
  /// A matte, one appearance.
  single(''),

  /// A matte and a tint map: appearances that differ only by tint.
  tint('_tint'),

  /// A matte and a material map: any appearances.
  material('_material'),

  /// One shape evaluated per fragment, one appearance.
  shape('_shape'),

  /// Up to eight shapes evaluated per fragment, one appearance.
  analytic('_analytic');

  const FinalShaderKind(this.suffix);

  /// The file name part of the kind.
  final String suffix;

  /// Whether the variant works out its shapes per fragment instead of
  /// reading a matte, so it binds no matte sampler.
  bool get perFragment => this == shape || this == analytic;
}

/// The color models a final shader variant shades.
@internal
enum FinalShaderModels {
  /// Every model, blended by share.
  all(''),

  /// One iOS 27 model, in the first color model slot.
  ios27('_ios27'),

  /// The direct model alone.
  direct('_direct');

  const FinalShaderModels(this.suffix);

  /// The file name part of the models.
  final String suffix;
}

/// One compiled specialization of the final glass shader.
///
/// A variant that shades one color model family drops the other family's
/// arithmetic and the slot loop's uniform reads. On a Mali-G78 that halves
/// the registers of the one-appearance shader, which doubles its fragments
/// in flight; the tint and analytic variants keep their occupancy and spill
/// less. The general variants serve mixed models and the material map.
///
/// Every variant can frost an unblurred copy of the backdrop itself, except
/// the ones that fit in 32 registers only without that: a frosted twin of
/// each draws frosted glass ([frost]).
@internal
@immutable
final class FinalShaderVariant {
  const FinalShaderVariant._(
    this.kind,
    this.models, {
    this.frost = false,
    this.band = false,
  });

  /// Where the variant reads its geometry and appearance from.
  final FinalShaderKind kind;

  /// The color models it shades.
  final FinalShaderModels models;

  /// Whether this is the frosted twin of a variant that cannot frost.
  final bool frost;

  /// Whether the variant also draws a scroll edge beside the glass.
  final bool band;

  /// The shader's file name without its extension.
  String get name =>
      'liquid_glass_final_render${kind.suffix}${models.suffix}'
      '${frost ? '_frost' : ''}${band ? '_band' : ''}';

  /// The asset key of the compiled shader.
  String get assetKey => ShaderKeys.finalRender(name);

  /// The asset keys of [all], in its order.
  static final List<String> assetKeys = [
    for (final variant in all) variant.assetKey,
  ];

  // The variants whose frost is a twin: on a Mali-G78 they hold 32 work
  // registers without the frost loop and 46 to 52 with it.
  static const _frostTwins = {
    (FinalShaderKind.single, FinalShaderModels.ios27),
    (FinalShaderKind.tint, FinalShaderModels.ios27),
    (FinalShaderKind.tint, FinalShaderModels.direct),
  };

  /// Every variant, in the order a layer holds their shaders.
  static final List<FinalShaderVariant> all = [
    for (final kind in FinalShaderKind.values)
      if (kind == FinalShaderKind.material)
        FinalShaderVariant._(kind, FinalShaderModels.all)
      else
        for (final models in FinalShaderModels.values) ...[
          FinalShaderVariant._(kind, models),
          if (_frostTwins.contains((kind, models)))
            FinalShaderVariant._(kind, models, frost: true),
          if (kind == FinalShaderKind.single &&
              models == FinalShaderModels.ios27)
            FinalShaderVariant._(kind, models, frost: true, band: true),
        ],
  ];

  /// The index in [all] of the cheapest variant that draws [kind] with
  /// [models], and frosts an unblurred copy when [frost].
  static int indexOf(
    FinalShaderKind kind,
    FinalShaderModels models, {
    bool frost = false,
    bool band = false,
  }) {
    final general = kind == FinalShaderKind.material;
    final shaded = general ? FinalShaderModels.all : models;
    final index = all.indexWhere(
      (variant) =>
          variant.kind == kind &&
          variant.models == shaded &&
          variant.frost == (frost && _frostTwins.contains((kind, shaded))) &&
          variant.band == band,
    );
    assert(index >= 0, 'No final shader for $kind $models.');
    return index;
  }
}
