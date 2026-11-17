import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

/// Lightweight color and materialization controls for one glass shape.
///
/// Optical geometry and surface lighting belong to the containing
/// `LiquidGlassLayer`. These values may differ between shapes that share a
/// layer.
///
/// Colors and color transfers are display-referred. The defaults of the
/// unnamed constructor may be retuned before 1.0; the version-named presets
/// (`ios27*`) track Apple's appearance on that OS version.
@immutable
final class LiquidGlassAppearance {
  /// Creates a per-shape glass appearance.
  ///
  /// The default [colorModel] is [LiquidGlassColorModel.direct], which adds
  /// no material of its own; [LiquidGlassAppearance.ios27Regular] and
  /// [LiquidGlassAppearance.ios27Clear] are the iOS 27 ones. The defaults may
  /// be retuned before 1.0.
  const LiquidGlassAppearance({
    this.tint = const Color.fromARGB(0, 255, 255, 255),
    this.visibility = 1,
    this.colorModel = const LiquidGlassColorModel.direct(),
  });

  /// The iOS 27 regular material (`Glass.regular`, which Apple also uses
  /// for toolbars and `.glass` buttons) in [brightness]. Its face follows
  /// the size of the shape that wears it ([at]).
  const LiquidGlassAppearance.ios27Regular({
    required Brightness brightness,
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : colorModel = brightness == Brightness.dark
           ? const LiquidGlassColorModel.ios27Regular(
               brightness: Brightness.dark,
             )
           : const LiquidGlassColorModel.ios27Regular(
               brightness: Brightness.light,
             );

  /// The iOS 27 `Glass.clear` appearance, identical in light and dark and
  /// at every size.
  const LiquidGlassAppearance.ios27Clear({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : colorModel = const LiquidGlassColorModel.ios27Clear();

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  final Color tint;

  /// Shape materialization progress from zero to one. Glass draws a value
  /// past either end, such as a spring's overshoot, as that end
  /// ([drawnVisibility]).
  final double visibility;

  /// The transfer model used to combine [tint] with the backdrop.
  ///
  /// [LiquidGlassColorModel.direct] carries its own saturation, gamma and
  /// vibrancy; the iOS 27 models derive the accompanying tonal response
  /// automatically from their fitted parameters.
  final LiquidGlassColorModel colorModel;

  /// The appearance as a shape of [size] wears it: its [colorModel] at the
  /// shape's shorter side and under its [tint] (see
  /// [LiquidGlassColorModel.at]).
  ///
  /// Returns this appearance itself where neither changes anything.
  LiquidGlassAppearance at(Size size) {
    final worn = colorModel.at(size.shortestSide, tint: tint);
    return identical(worn, colorModel) ? this : copyWith(colorModel: worn);
  }

  /// Returns a copy with the supplied appearance controls replaced.
  LiquidGlassAppearance copyWith({
    Color? tint,
    double? visibility,
    LiquidGlassColorModel? colorModel,
  }) => LiquidGlassAppearance(
    tint: tint ?? this.tint,
    visibility: visibility ?? this.visibility,
    colorModel: colorModel ?? this.colorModel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidGlassAppearance &&
          other.tint == tint &&
          other.visibility == visibility &&
          other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tint, visibility, colorModel);

  @override
  String toString() => 'LiquidGlassAppearance($tint, $visibility, $colorModel)';
}

/// [visibility] as glass draws it: within zero to one.
@internal
double drawnVisibility(double visibility) => clampDouble(visibility, 0, 1);
