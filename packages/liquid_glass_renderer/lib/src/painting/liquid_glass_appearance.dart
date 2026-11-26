import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

/// Lightweight color and materialization controls for one glass shape.
///
/// The lens and the blur belong to the settings of the containing
/// `LiquidGlassLayer`, the lit rim to [colorModel]. These values may differ
/// between shapes that share a layer.
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
  /// [LiquidGlassAppearance.ios27Clear] are the iOS 27 ones.
  const LiquidGlassAppearance({
    this.tint = const Color(0x00000000),
    this.visibility = 1,
    this.colorModel = const LiquidGlassColorModel.direct(),
  });

  /// The iOS 27 regular material (`Glass.regular`, which Apple also uses
  /// for toolbars and `.glass` buttons) in [brightness], with the face of
  /// the Increase Contrast setting where [increaseContrast] says so. Its
  /// face follows the size of the shape that wears it (see
  /// [LiquidGlassColorModel.ios27Regular]).
  const LiquidGlassAppearance.ios27Regular({
    required Brightness brightness,
    bool increaseContrast = false,
    this.tint = const Color(0x00000000),
    this.visibility = 1,
  }) : colorModel = brightness == Brightness.dark
           ? (increaseContrast ? _darkContrast : _dark)
           : (increaseContrast ? _lightContrast : _light);

  /// The iOS 27 `Glass.clear` appearance, identical in light and dark and
  /// at every size, with the face of the Increase Contrast setting where
  /// [increaseContrast] says so.
  const LiquidGlassAppearance.ios27Clear({
    bool increaseContrast = false,
    this.tint = const Color(0x00000000),
    this.visibility = 1,
  }) : colorModel = increaseContrast ? _clearContrast : _clear;

  static const _light = LiquidGlassColorModel.ios27Regular(
    brightness: Brightness.light,
  );
  static const _dark = LiquidGlassColorModel.ios27Regular(
    brightness: Brightness.dark,
  );
  static const _lightContrast = LiquidGlassColorModel.ios27Regular(
    brightness: Brightness.light,
    increaseContrast: true,
  );
  static const _darkContrast = LiquidGlassColorModel.ios27Regular(
    brightness: Brightness.dark,
    increaseContrast: true,
  );
  static const _clear = LiquidGlassColorModel.ios27Clear();
  static const _clearContrast = LiquidGlassColorModel.ios27Clear(
    increaseContrast: true,
  );

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  /// Every constructor defaults to no tint.
  final Color tint;

  /// Shape materialization progress from zero to one. Glass draws a value
  /// past either end, such as a spring's overshoot, as that end.
  ///
  /// This is one shape's own visibility; a `LiquidGlassVisibility` above the
  /// shape fades every shape below it, and the shape shows the product of
  /// the two.
  final double visibility;

  /// The transfer model used to combine [tint] with the backdrop.
  ///
  /// [LiquidGlassColorModel.direct] carries its own saturation, gamma and
  /// vibrancy; the iOS 27 models take theirs from their recipe, worn at the
  /// size of the shape that wears the appearance.
  final LiquidGlassColorModel colorModel;

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
