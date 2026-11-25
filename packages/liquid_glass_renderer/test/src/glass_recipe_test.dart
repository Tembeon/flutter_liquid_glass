import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe_groups.dart';
import 'package:liquid_glass_renderer/src/painting/lens_settings.dart';

GlassRecipe _of({
  GlassVariant variant = GlassVariant.regular,
  Brightness brightness = Brightness.light,
  double shortSide = 150,
  double slider = 0,
  bool increaseContrast = false,
  bool reduceTransparency = false,
  Color? tint,
}) => GlassRecipe.of(
  variant: variant,
  brightness: brightness,
  shortSide: shortSide,
  slider: slider,
  increaseContrast: increaseContrast,
  reduceTransparency: reduceTransparency,
  tint: tint,
);

double _deg(double degrees) => degrees * math.pi / 180;

Matcher _near(num value) => closeTo(value, 1e-9);

void main() {
  group('regular glass', () {
    test("a panel's recipe in light at slider 0", () {
      final r = _of();
      const grown = 86 / 96;

      expect(r.refraction.innerAmount, 60);
      expect(r.refraction.innerHeight, 20);
      expect(r.refraction.outerAmount, 37.5);
      expect(r.refraction.outerHeight, 30);
      expect(r.refraction.outerOpacity, 0.6);

      expect(r.blur.radius, 5);
      expect(r.blur.stops.map((s) => s.depth), [75, 1, 0, 0]);
      expect(r.blur.stops[0].strength, _near(0.8 * grown));
      expect(r.blur.stops[1].strength, _near(0.4 * grown));
      expect(r.blur.stops.skip(2).map((s) => s.strength), [0.5, 1]);

      expect(r.blurFill.radius, 8);
      expect(r.blurFill.lighten, 0.675);
      expect(r.blurFill.darken, 0);
      expect(r.blurFill.cover, 0);

      expect(r.face.black, 0.4);
      expect(r.face.white, 1.03);
      expect(r.face.saturation, 1.2);
      expect(r.face.fill.a, 0);
      expect(r.face.maxLuma, 1);
      expect(r.face.maxLumaWithoutHeadroom, 0.94);
      expect(r.face.clamp, closeTo(1.0696, 1e-4));

      expect(r.bleed.amount, 52.5);
      expect(r.bleed.blurRadius, 52.5);
      expect(r.bleed.opacity, _near(0.5 * grown));
      expect(r.bleed.onBright, 1);

      expect(r.dropShadow.radius, _near(4 + 20 * grown));
      expect(r.dropShadow.opacity, _near(0.04 + 0.36 * grown));
      expect(r.dropShadow.offset, 8);
      expect(r.dropShadow.color.a, 0.3);

      expect(r.ringShadow.opacity, 0.06);
      expect(r.ringShadow.offset, 8);
      expect(r.ringShadow.strokeWidth, 4);
      expect(r.ringShadow.blurRadius, 5);

      expect(r.darkSpecular.amount, 0.4);
      expect(r.darkSpecular.width, _near(8 / 15));
      expect(r.darkSpecular.offset, _near(-8 / 15));
      expect(r.darkSpecular.spread, _near(_deg(96)));
      expect(r.darkSpecular.spreadWithoutHeadroom, _near(_deg(106)));

      expect(r.rimHighlight.width, 1);
      expect(r.rimHighlight.diffuseWidth, 8);
      expect(r.rimHighlight.spread, _near(_deg(80 + 10 * 54 / 96)));
      expect(r.rimHighlight.opacity, 1);
      expect(r.tint, TintRecipe.none);
    });

    test("a button's recipe in dark past the slider's middle", () {
      final r = _of(brightness: Brightness.dark, shortSide: 34, slider: 0.75);

      expect(r.blur.stops.first.strength, 0);
      expect(r.blurFill.lighten, 0);
      expect(r.blurFill.darken, 0.9);
      expect(r.blurFill.cover, 0.75);
      expect(r.face.black, 0.125);
      expect(r.face.white, 1.125);
      expect(r.face.fill.r, closeTo(0.0625, 1e-6));
      expect(r.face.fill.a, closeTo(0.25, 1e-6));
      expect(r.face.maxLuma, 0.6);
      expect(r.face.clamp, closeTo(1.3083, 1e-4));
      expect(r.bleed.blurRadius, 0);
      expect(r.bleed.opacity, 0);
      expect(r.bleed.onBright, 0);
      expect(r.dropShadow.radius, 4);
      expect(r.dropShadow.opacity, 0.04);
      expect(r.darkSpecular.spread, _near(_deg(75)));
      expect(r.rimHighlight.spread, _near(_deg(80)));
    });

    test("dark glass rolls its face off by size and slider", () {
      expect(
        _of(brightness: Brightness.dark, shortSide: 104).face.maxLuma,
        _near(0.45),
      );
      expect(
        _of(
          brightness: Brightness.dark,
          shortSide: 104,
          slider: 0.5,
        ).face.maxLuma,
        _near(0.35),
      );
      expect(
        _of(brightness: Brightness.dark, shortSide: 84).face.maxLuma,
        _near(0.525),
      );
    });

    test('the slider snaps to steps of 0.05', () {
      expect(snapSlider(0.49), 0.5);
      expect(snapSlider(0.97), 0.95);
      expect(snapSlider(-1), 0);
      expect(snapSlider(2), 1);
      expect(_of(slider: 0.49), _of(slider: 0.5));
    });
  });

  test('clear glass', () {
    final r = _of(variant: GlassVariant.clear, slider: 0.75);

    expect(r.refraction.innerAmount, 60);
    expect(r.refraction.innerHeight, 20);
    expect(r.refraction.outerOpacity, 0);
    expect(r.blur.radius, 0.75);
    expect(r.blur.stops.map((s) => s.strength), [1, 0.5, 0.5, 1]);
    expect(r.blurFill.radius, 8);
    expect(r.blurFill.cover, 0.5);
    expect(r.face.black, 0.125);
    expect(r.face.white, 1.08);
    expect(r.face.saturation, 1.06);
    expect(r.bleed.opacity, 0);
    expect(r.dropShadow.opacity, 0);
    expect(r.ringShadow, RingShadowRecipe.none);
    expect(r.rimHighlight.black, 0.2);
    expect(r.darkSpecular.spread, _near(_deg(75)));
    expect(
      _of(
        variant: GlassVariant.clear,
        brightness: Brightness.dark,
        slider: 0.75,
      ),
      r,
    );
    expect(_of(variant: GlassVariant.clear).blur.radius, 0);
    expect(_of(variant: GlassVariant.clear).blur.stops.first.strength, 0);
  });

  group('Increase Contrast', () {
    test('changes only the face of regular glass', () {
      final base = _of(slider: 0.5);
      final r = _of(slider: 0.5, increaseContrast: true);

      expect(r.face.black, 0.5);
      expect(r.face.white, 1.03);
      expect(r.face.saturation, 0.8);
      expect(r.face.fill.a, closeTo(0.45, 1e-6));
      expect(r.copyWith(face: base.face), base);
      expect(
        _of(slider: 1, increaseContrast: true).face.fill.a,
        closeTo(0.5, 1e-9),
      );
    });

    test('caps dark glass at a dark grey', () {
      final r = _of(brightness: Brightness.dark, increaseContrast: true);

      expect(r.face.black, 0.1);
      expect(r.face.white, 0.3);
      expect(r.face.fill.a, closeTo(0.4, 1e-6));
      expect(r.face.clamp, 1);
    });

    test('lays black over clear glass and weakens its rim', () {
      final r = _of(variant: GlassVariant.clear, increaseContrast: true);

      expect(r.face.white, 0.6);
      expect(r.face.fill.r, 0);
      expect(r.face.fill.a, closeTo(0.35, 1e-6));
      expect(r.rimHighlight.opacity, 0.55);
    });
  });

  group('Reduce Transparency', () {
    test('takes the lens away and blurs widely', () {
      final r = _of(shortSide: 34, slider: 0.5, reduceTransparency: true);

      expect(r.refraction, RefractionRecipe.none);
      expect(r.ringShadow, RingShadowRecipe.none);
      expect(r.bleed.opacity, 0);
      expect(r.bleed.blurRadius, 0);
      expect(r.blur.radius, 35);
      expect(r.blur.stops.map((s) => s.strength), [1, 1, 5 / 35, 5 / 35]);
      expect(r.face.black, 0.9);
      expect(r.face.saturation, 0.9);
      expect(r.dropShadow.opacity, 0.04);
      expect(r.darkSpecular.amount, 0.4);
      expect(
        _of(reduceTransparency: true).blur.radius,
        _near(35 + 15 * 86 / 96),
      );
    });

    test('fills light glass most at the middle tick', () {
      double fill(double slider) =>
          _of(slider: slider, reduceTransparency: true).face.fill.a;

      expect(fill(0), 0);
      expect(fill(0.25), closeTo(0.4, 1e-6));
      expect(fill(0.5), closeTo(0.8, 1e-6));
      expect(fill(0.75), closeTo(0.65, 1e-6));
      expect(fill(1), closeTo(0.5, 1e-6));
    });

    test('flattens dark glass under black', () {
      final r = _of(
        brightness: Brightness.dark,
        slider: 0.75,
        reduceTransparency: true,
      );

      expect(r.face.black, 0.2);
      expect(r.face.white, 0.2);
      expect(r.face.fill.r, 0);
      expect(r.face.fill.a, closeTo(0.55, 1e-6));
    });

    test('blurs clear glass at every slider position', () {
      final r = _of(variant: GlassVariant.clear, reduceTransparency: true);

      expect(r.blur.radius, 50);
      expect(r.blur.stops.map((s) => s.strength), [1, 1, 1, 1]);
      expect(r.face.white, 0);
      expect(r.face.fill.a, closeTo(0.25, 1e-6));
    });

    test("under Increase Contrast keeps the contrast face", () {
      final light = _of(
        slider: 0.5,
        increaseContrast: true,
        reduceTransparency: true,
      );
      expect(light.face.black, 0.5);
      expect(light.face.saturation, 0.8);
      expect(light.face.fill.a, closeTo(0.8, 1e-6));
      expect(light.blur.radius, 48.4375);

      final dark = _of(
        brightness: Brightness.dark,
        increaseContrast: true,
        reduceTransparency: true,
      );
      expect(
        dark.face,
        _of(brightness: Brightness.dark, increaseContrast: true).face,
      );
    });
  });

  group('tint', () {
    test('runs a saturated colour from a darker one to itself in light', () {
      final t = _of(tint: const Color(0xFFFF0000)).tint;

      expect(t.lumaWeight, 1);
      expect(t.opacity, 1);
      expect(t.low.red, closeTo(0.6, 1e-9));
      expect(t.low.green, 0);
      expect(t.high, (red: 1.0, green: 0.0, blue: 0.0));
    });

    test('lifts the dark end in dark, and keeps the light law on clear', () {
      final dark = _of(
        brightness: Brightness.dark,
        tint: const Color(0xFFFF0000),
      ).tint;
      expect(dark.low.red, closeTo(1.0056, 1e-9));
      expect(dark.low.green, closeTo(-0.0306, 1e-9));
      expect(dark.high.green, closeTo(0.1735, 1e-9));

      expect(
        _of(
          variant: GlassVariant.clear,
          brightness: Brightness.dark,
          tint: const Color(0xFFFF0000),
        ).tint,
        _of(variant: GlassVariant.clear, tint: const Color(0xFFFF0000)).tint,
      );
    });

    test('ramps a grey channel by channel', () {
      final t = _of(tint: const Color(0xFF000000)).tint;

      expect(t.lumaWeight, 0);
      expect(t.low.red, -0.25);
      expect(t.high.red - t.low.red, closeTo(0.31, 1e-9));
    });

    test("takes the colour's alpha as its opacity", () {
      expect(_of(tint: const Color(0x80FF0000)).tint.opacity, 128 / 255);
      expect(_of(tint: const Color(0x00FF0000)).tint, TintRecipe.none);
    });

    test('fades in without changing hue', () {
      final red = _of(tint: const Color(0xFFFF0000)).tint;
      final half = TintRecipe.lerp(TintRecipe.none, red, 0.5);

      expect(half.low, red.low);
      expect(half.high, red.high);
      expect(half.opacity, 0.5);
    });
  });

  group('lerp', () {
    final light = _of(slider: 0.25);
    final dark = _of(brightness: Brightness.dark, slider: 0.25);

    test('returns its ends at 0 and 1', () {
      expect(GlassRecipe.lerp(light, dark, 0), same(light));
      expect(GlassRecipe.lerp(light, dark, 1), same(dark));
    });

    test('crosses group by group', () {
      final half = GlassRecipe.lerp(light, dark, 0.5);

      expect(half.face.black, closeTo((0.4 + 0.125) / 2, 1e-9));
      expect(half.blurFill.lighten, closeTo(light.blurFill.lighten / 2, 1e-9));
      expect(half.blurFill.darken, closeTo(dark.blurFill.darken / 2, 1e-9));
      expect(half.bleed.onBright, 0.5);
      expect(
        half.darkSpecular.spread,
        closeTo((_deg(96) + _deg(75)) / 2, 1e-9),
      );
    });

    test('crosses fills premultiplied', () {
      final clear = _of(variant: GlassVariant.clear);
      final contrast = _of(variant: GlassVariant.clear, increaseContrast: true);
      final fill = GlassRecipe.lerp(clear, contrast, 0.5).face.fill;

      expect(fill.r, 0);
      expect(fill.a, closeTo(0.175, 1e-6));
    });

    test('morphs regular glass into clear', () {
      final clear = _of(variant: GlassVariant.clear, slider: 0.25);
      final half = GlassRecipe.lerp(light, clear, 0.5);

      expect(half.refraction.outerOpacity, 0.3);
      expect(
        half.dropShadow.opacity,
        closeTo(light.dropShadow.opacity / 2, 1e-9),
      );
    });
  });

  group('overrides', () {
    test('keep the recipe when they change nothing', () {
      final r = _of();
      expect(const GlassRecipeOverrides().apply(r), same(r));
    });

    test('scale the refraction, blur, shadows and highlight', () {
      final r = _of();
      final o = const GlassRecipeOverrides(
        refraction: 0.5,
        blur: 2,
        shadows: 0,
        highlight: 0.5,
      ).apply(r);

      expect(o.refraction.innerAmount, 30);
      expect(o.refraction.innerHeight, 20);
      expect(o.refraction.outerAmount, 18.75);
      expect(o.blur.radius, 10);
      expect(o.blur.stops, r.blur.stops);
      expect(o.dropShadow.opacity, 0);
      expect(o.ringShadow.opacity, 0);
      expect(o.rimHighlight.opacity, 0.5);
      expect(o.face, r.face);
    });
  });

  group('LensSettings', () {
    const lens = LensSettings(
      pull: 9,
      pullDepth: 36,
      aberration: 3.6,
      aberrationDepth: 14,
    );

    test('grows with the lift and keeps its depths', () {
      final half = lens.lifted(0.5);

      expect(half.pull, 4.5);
      expect(half.pullDepth, 36);
      expect(half.aberration, 1.8);
      expect(half.aberrationDepth, 14);
      expect(lens.lifted(0).isNone, isTrue);
      expect(lens.isNone, isFalse);
    });

    test('crosses field by field', () {
      final half = LensSettings.lerp(LensSettings.none, lens, 0.5);

      expect(half.pull, 4.5);
      expect(half.pullDepth, 18);
      expect(LensSettings.lerp(lens, lens, 0.3), lens);
    });
  });

  test('equal inputs give equal recipes', () {
    expect(_of(slider: 0.3), _of(slider: 0.3));
    expect(_of(slider: 0.3).hashCode, _of(slider: 0.3).hashCode);
    expect(_of(slider: 0.3), isNot(_of(slider: 0.4)));
  });
}
