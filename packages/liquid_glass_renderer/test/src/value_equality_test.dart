import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

// Values built at run time, so that const canonicalisation cannot make two
// of them identical.
double _n(double value) => double.parse('$value');
bool _b(bool value) => bool.parse('$value');

void _holdsValue(Object a, Object same, List<Object> different) {
  expect(identical(a, same), isFalse);
  expect(a, same);
  expect(a.hashCode, same.hashCode);
  for (final other in different) {
    expect(a, isNot(other));
  }
}

void main() {
  test('shapes compare by kind, side and radii', () {
    _holdsValue(
      LiquidRoundedSuperellipse(radius: _n(12)),
      LiquidRoundedSuperellipse(radius: _n(12)),
      [
        LiquidRoundedSuperellipse(radius: _n(13)),
        LiquidRoundedSuperellipse.vertical(top: _n(12), bottom: _n(20)),
        LiquidRoundedSuperellipse(
          radius: _n(12),
          side: const BorderSide(),
        ),
        LiquidRoundedRectangle(radius: _n(12)),
      ],
    );
    _holdsValue(
      LiquidRoundedRectangle(radius: _n(8)),
      LiquidRoundedRectangle(radius: _n(8)),
      [
        LiquidRoundedRectangle(radius: _n(9)),
        LiquidRoundedSuperellipse(radius: _n(8)),
      ],
    );
    _holdsValue(
      LiquidOval(side: BorderSide(width: _n(2))),
      LiquidOval(side: BorderSide(width: _n(2))),
      [
        LiquidOval(side: BorderSide(width: _n(3))),
        LiquidRoundedRectangle(
          radius: 0,
          side: BorderSide(width: _n(2)),
        ),
      ],
    );
  });

  test('appearances compare by tint, visibility and color model', () {
    _holdsValue(
      LiquidGlassAppearance(
        colorModel: const LiquidGlassColorModel.direct(
          brightness: Brightness.light,
        ),
        tint: Color(0x40FF0000 + _n(1).toInt()),
      ),
      LiquidGlassAppearance(
        colorModel: const LiquidGlassColorModel.direct(
          brightness: Brightness.light,
        ),
        tint: Color(0x40FF0000 + _n(1).toInt()),
      ),
      [
        LiquidGlassAppearance(
          colorModel: const LiquidGlassColorModel.direct(
            brightness: Brightness.light,
          ),
          tint: Color(0x40FF0000 + _n(2).toInt()),
        ),
        LiquidGlassAppearance(
          colorModel: const LiquidGlassColorModel.direct(
            brightness: Brightness.light,
          ),
          tint: Color(0x40FF0000 + _n(1).toInt()),
          visibility: _n(0.5),
        ),
        LiquidGlassAppearance(
          tint: Color(0x40FF0000 + _n(1).toInt()),
          colorModel: const LiquidGlassColorModel.ios27Clear(),
        ),
      ],
    );
  });

  test('color models compare by parameters and adjustments', () {
    _holdsValue(
      LiquidGlassColorModel.direct(
        brightness: Brightness.light,
        saturation: _n(1.2),
      ),
      LiquidGlassColorModel.direct(
        brightness: Brightness.light,
        saturation: _n(1.2),
      ),
      [
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.3),
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          transmissionGamma: _n(2),
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          vibrancy: _n(1),
        ),
        LiquidGlassColorModel.direct(
          saturation: _n(1.2),
          brightness: Brightness.dark,
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          glintStrength: 0,
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          contourStrength: 0,
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          contourDirectionality: 0,
        ),
        LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: _n(1.2),
          bevelShadowStrength: 0,
        ),
      ],
    );
    expect(
      const LiquidGlassColorModel.direct(brightness: Brightness.light),
      const LiquidGlassColorModel.direct(
        brightness: Brightness.light,
        glintStrength: 0.6,
        contourStrength: 0.43,
        contourDirectionality: 0.77,
        bevelShadowStrength: 0.036,
      ),
    );
    _holdsValue(
      LiquidGlassColorModel.ios27Regular(brightness: _dark()),
      LiquidGlassColorModel.ios27Regular(brightness: _dark()),
      [
        const LiquidGlassColorModel.ios27Regular(brightness: Brightness.light),
        const LiquidGlassColorModel.ios27Regular(
          brightness: Brightness.dark,
          highContrast: true,
        ),
        const LiquidGlassColorModel.ios27Clear(),
        const LiquidGlassColorModel.direct(brightness: Brightness.light),
      ],
    );
    _holdsValue(
      LiquidGlassColorModel.ios27Clear(highContrast: _b(true)),
      const LiquidGlassColorModel.ios27Clear(highContrast: true),
      [
        const LiquidGlassColorModel.ios27Clear(),
        const LiquidGlassColorModel.ios27Regular(
          brightness: Brightness.light,
          highContrast: true,
        ),
      ],
    );
  });

  test('a color model is one of three kinds, each with its own fields', () {
    String kind(LiquidGlassColorModel model) => switch (model) {
      LiquidGlassDirectColorModel(:final saturation) => 'direct $saturation',
      LiquidGlassIos27RegularColorModel(:final brightness) =>
        'regular ${brightness.name}',
      LiquidGlassIos27ClearColorModel() => 'clear',
    };
    expect(
      kind(
        const LiquidGlassColorModel.direct(
          brightness: Brightness.light,
          saturation: 2,
        ),
      ),
      'direct 2.0',
    );
    expect(
      kind(
        const LiquidGlassColorModel.ios27Regular(brightness: Brightness.dark),
      ),
      'regular dark',
    );
    expect(kind(const LiquidGlassColorModel.ios27Clear()), 'clear');
  });

  test('every appearance constructor defaults to one tint', () {
    const none = Color(0x00000000);
    expect(
      const LiquidGlassAppearance(
        colorModel: LiquidGlassColorModel.direct(brightness: Brightness.light),
      ).tint,
      none,
    );
    expect(const LiquidGlassAppearance.ios27Clear().tint, none);
    expect(
      const LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.light,
      ).tint,
      none,
    );
  });

  test('shapes of one kind lerp into each other', () {
    const from = LiquidRoundedSuperellipse(radius: 10);
    const to = LiquidRoundedSuperellipse.vertical(top: 20, bottom: 40);
    const middle = LiquidRoundedSuperellipse.vertical(top: 15, bottom: 25);
    expect(ShapeBorder.lerp(from, to, 0.5), middle);
    expect(from.lerpTo(to, 0.5), middle);
    expect(to.lerpFrom(from, 0.5), middle);
    expect(
      ShapeBorder.lerp(
        const LiquidRoundedRectangle(radius: 4),
        const LiquidRoundedRectangle(radius: 8),
        0.25,
      ),
      const LiquidRoundedRectangle(radius: 5),
    );
    expect(
      ShapeBorder.lerp(const LiquidOval(), const LiquidOval(), 0.5),
      const LiquidOval(),
    );
    expect(const LiquidOval().copyWith(), isA<LiquidOval>());
    expect(
      const LiquidRoundedSuperellipse(radius: 12).borderRadius,
      BorderRadius.circular(12),
    );
  });

  test('silhouettes compare by their shape and bounds, or by their path', () {
    const shape = LiquidRoundedSuperellipse(radius: 12);
    const bounds = Rect.fromLTWH(0, 0, 40, 20);
    _holdsValue(
      LiquidGlassSilhouette.shape(shape, Rect.fromLTWH(0, 0, _n(40), 20)),
      LiquidGlassSilhouette.shape(shape, Rect.fromLTWH(0, 0, _n(40), 20)),
      [
        const LiquidGlassSilhouette.shape(LiquidOval(), bounds),
        LiquidGlassSilhouette.shape(shape, bounds.shift(const Offset(1, 0))),
        LiquidGlassSilhouette.path(Path()..addRect(bounds)),
      ],
    );
    final path = Path()..addRect(bounds);
    expect(LiquidGlassSilhouette.path(path), LiquidGlassSilhouette.path(path));
    expect(LiquidGlassSilhouette.path(path).bounds, bounds);
    expect(
      LiquidGlassSilhouette.path(path),
      isNot(LiquidGlassSilhouette.path(Path()..addRect(bounds))),
    );
  });

  test('worn models compare by their recipe and numbers', () {
    _holdsValue(
      WornColorModel.recipe((
        variant: GlassVariant.regular,
        brightness: Brightness.light,
        shortSide: _n(100),
        greyTint: false,
        highContrast: false,
      )),
      WornColorModel.recipe((
        variant: GlassVariant.regular,
        brightness: Brightness.light,
        shortSide: _n(100),
        greyTint: false,
        highContrast: false,
      )),
      [
        WornColorModel.recipe((
          variant: GlassVariant.regular,
          brightness: Brightness.light,
          shortSide: _n(101),
          greyTint: false,
          highContrast: false,
        )),
        WornColorModel.recipe((
          variant: GlassVariant.regular,
          brightness: Brightness.light,
          shortSide: _n(100),
          greyTint: true,
          highContrast: false,
        )),
        WornColorModel.recipe((
          variant: GlassVariant.regular,
          brightness: Brightness.light,
          shortSide: _n(100),
          greyTint: false,
          highContrast: true,
        )),
        WornColorModel.direct(brightness: Brightness.light, saturation: _n(1)),
        const WornColorModel.direct(brightness: Brightness.dark),
        const WornColorModel.direct(
          brightness: Brightness.light,
          rim: DirectRim(
            glintStrength: 0.6,
            contourStrength: 0,
            contourDirectionality: 0,
            bevelShadowStrength: 0,
          ),
        ),
      ],
    );
  });

  test('settings compare by every field', () {
    final settings = LiquidGlassSettings(refractionHeight: _n(20));
    _holdsValue(settings, LiquidGlassSettings(refractionHeight: _n(20)), [
      LiquidGlassSettings(refractionHeight: _n(21)),
      settings.copyWith(blur: _n(9)),
      settings.copyWith(sliderPosition: _n(0.5)),
      settings.copyWith(refractionFitsShape: false),
    ]);
    expect(settings.copyWith(), settings);
  });
}

Brightness _dark() => Brightness.values[Brightness.dark.index];
