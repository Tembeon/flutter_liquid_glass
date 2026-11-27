import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe_groups.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

GlassRecipe _of({
  GlassVariant variant = GlassVariant.regular,
  Brightness brightness = Brightness.light,
  double shortSide = 150,
  double slider = 0,
  bool highContrast = false,
  bool reduceTransparency = false,
}) => GlassRecipe.of(
  variant: variant,
  brightness: brightness,
  shortSide: shortSide,
  slider: slider,
  highContrast: highContrast,
  reduceTransparency: reduceTransparency,
);

double _deg(double degrees) => degrees * math.pi / 180;

Matcher _near(num value) => closeTo(value, 1e-9);

void main() {
  group('regular glass', () {
    test("a panel's recipe in light at slider 0", () {
      final r = _of();
      const grown = 86 / 96;

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

      expect(r.bleed.opacity, _near(0.5 * grown));
      expect(r.bleed.onBright, 1);

      expect(r.ringShadow.opacity, 0.06);
      expect(r.ringShadow.offset, 8);
      expect(r.ringShadow.strokeWidth, 4);
      expect(r.ringShadow.blurRadius, 5);

      expect(r.darkSpecular.amount, 0.4);
      expect(r.darkSpecular.width, _near(8 / 15));
      expect(r.darkSpecular.spread, _near(_deg(96)));

      expect(r.rimHighlight.width, 1);
      expect(r.rimHighlight.diffuseWidth, 8);
      expect(r.rimHighlight.spread, _near(_deg(80 + 10 * 54 / 96)));
      expect(r.rimHighlight.opacity, 1);
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
      expect(r.bleed.opacity, 0);
      expect(r.bleed.onBright, 0);
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

    expect(r.blur.radius, 0.75);
    expect(r.blur.stops.map((s) => s.strength), [1, 0.5, 0.5, 1]);
    expect(r.blurFill.radius, 8);
    expect(r.blurFill.cover, 0.5);
    expect(r.face.black, 0.125);
    expect(r.face.white, 1.08);
    expect(r.face.saturation, 1.06);
    expect(r.bleed.opacity, 0);
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
      final r = _of(slider: 0.5, highContrast: true);

      expect(r.face.black, 0.5);
      expect(r.face.white, 1.03);
      expect(r.face.saturation, 0.8);
      expect(r.face.fill.a, closeTo(0.45, 1e-6));
      expect(
        (r.blur, r.blurFill, r.bleed, r.ringShadow, r.darkSpecular),
        (
          base.blur,
          base.blurFill,
          base.bleed,
          base.ringShadow,
          base.darkSpecular,
        ),
      );
      expect(r.rimHighlight, base.rimHighlight);
      expect(
        _of(slider: 1, highContrast: true).face.fill.a,
        closeTo(0.5, 1e-9),
      );
    });

    test('caps dark glass at a dark grey', () {
      final r = _of(brightness: Brightness.dark, highContrast: true);

      expect(r.face.black, 0.1);
      expect(r.face.white, 0.3);
      expect(r.face.fill.a, closeTo(0.4, 1e-6));
    });

    test('lays black over clear glass and weakens its rim', () {
      final r = _of(variant: GlassVariant.clear, highContrast: true);

      expect(r.face.white, 0.6);
      expect(r.face.fill.r, 0);
      expect(r.face.fill.a, closeTo(0.35, 1e-6));
      expect(r.rimHighlight.opacity, 0.55);
    });
  });

  group('Reduce Transparency', () {
    test('blurs regular glass from 35 to 50 by size, 5 at its edge, and '
        'clear glass by 50 all through', () {
      for (final (side, radius) in [(44.0, 35.0), (150.0, 48.4375)]) {
        final blur = _of(shortSide: side, reduceTransparency: true).blur;
        expect(blur.radius, _near(radius), reason: 'side $side');
        expect(
          [for (final stop in blur.stops) stop.strength],
          [1, 1, 5 / radius, 5 / radius].map(_near).toList(),
        );
      }
      final clear = _of(
        variant: GlassVariant.clear,
        reduceTransparency: true,
      ).blur;
      expect(clear.radius, 50);
      expect([for (final stop in clear.stops) stop.strength], [1, 1, 1, 1]);
    });

    test("reads iOS's capture margin past the glass: 16 points, and 8/15 on "
        'clear glass up to the middle tick; glass outside it reads as far as '
        'its blur reaches', () {
      expect(_of(reduceTransparency: true).blur.margin, 16);
      expect(_of(shortSide: 44, reduceTransparency: true).blur.margin, 16);
      for (final (slider, margin) in [
        (0.0, 8 / 15),
        (0.5, 8 / 15),
        (1.0, 16),
      ]) {
        expect(
          _of(
            variant: GlassVariant.clear,
            slider: slider,
            reduceTransparency: true,
          ).blur.margin,
          margin,
          reason: 'slider $slider',
        );
      }
      expect(_of().blur.margin, isNull);
      expect(_of(variant: GlassVariant.clear, slider: 1).blur.margin, isNull);
    });

    test('lays a nearly flat face, its fill rising to the middle tick and '
        'falling past it', () {
      for (final (slider, alpha) in [
        (0.0, 0.0),
        (0.25, 0.4),
        (0.5, 0.8),
        (0.75, 0.65),
        (1.0, 0.5),
      ]) {
        final face = _of(slider: slider, reduceTransparency: true).face;
        expect(
          (face.black, face.white, face.saturation),
          (0.9, 1.03, 0.9),
        );
        expect(face.fill.r, 1);
        expect(face.fill.a, closeTo(alpha, 1e-6), reason: 'slider $slider');
      }
      for (final (slider, alpha) in [(0.0, 0.0), (0.5, 0.6), (1.0, 0.5)]) {
        final face = _of(
          brightness: Brightness.dark,
          slider: slider,
          reduceTransparency: true,
        ).face;
        expect((face.black, face.white, face.saturation), (0.2, 0.2, 0.7));
        expect(face.fill.r, 0);
        expect(face.fill.a, closeTo(alpha, 1e-6), reason: 'slider $slider');
      }
    });

    test('draws no ring shadow or veil and keeps the edges iOS keeps', () {
      final base = _of(slider: 0.5);
      final r = _of(slider: 0.5, reduceTransparency: true);
      expect(r.ringShadow.draws, isFalse);
      expect(r.bleed, BleedRecipe.none);
      expect(
        (r.blurFill, r.darkSpecular, r.rimHighlight),
        (base.blurFill, base.darkSpecular, base.rimHighlight),
      );
    });

    test('clear glass draws one recipe in either scheme but under it, '
        'where its fill is a quarter of white in light and of black in '
        'dark', () {
      for (final side in [44.0, 150.0]) {
        for (final slider in [0.0, 0.5, 1.0]) {
          GlassRecipe clear(Brightness brightness) => _of(
            variant: GlassVariant.clear,
            brightness: brightness,
            shortSide: side,
            slider: slider,
          );
          expect(
            clear(Brightness.dark),
            clear(Brightness.light),
            reason: 'side $side, slider $slider',
          );
        }
      }
      FaceRecipe reduced(Brightness brightness) => _of(
        variant: GlassVariant.clear,
        brightness: brightness,
        reduceTransparency: true,
      ).face;
      final light = reduced(Brightness.light);
      final dark = reduced(Brightness.dark);
      expect((light.black, light.white, light.saturation), (0.125, 0, 0.9));
      expect((light.fill.r, light.fill.a), (1, 0.25));
      expect((dark.saturation, dark.fill.r, dark.fill.a), (0.7, 0, 0.25));
    });

    test("lies under Increase Contrast's face", () {
      expect(
        _of(reduceTransparency: true, highContrast: true).face.fill.a,
        closeTo(0.45, 1e-6),
      );
      expect(
        _of(
          slider: 0.5,
          reduceTransparency: true,
          highContrast: true,
        ).face.fill.a,
        closeTo(0.8, 1e-6),
      );
    });
  });

  test('the drop shadow grows with regular glass and is none under clear', () {
    const grown = 86 / 96;
    final panel = ios27DropShadow(
      variant: GlassVariant.regular,
      brightness: Brightness.light,
      shortSide: 150,
    );
    expect(panel.radius, _near(4 + 20 * grown));
    expect(panel.opacity, _near(0.04 + 0.36 * grown));
    expect(panel.offset, 8);
    expect(panel.color.a, 0.3);

    final button = ios27DropShadow(
      variant: GlassVariant.regular,
      brightness: Brightness.dark,
      shortSide: 34,
    );
    expect(button.radius, 4);
    expect(button.opacity, 0.04);

    expect(
      ios27DropShadow(
        variant: GlassVariant.clear,
        brightness: Brightness.light,
        shortSide: 150,
      ).opacity,
      0,
    );
  });

  group('a lifted lens', () {
    GlassRecipe lens(
      GlassLift lift, {
      Brightness brightness = Brightness.light,
      double shortSide = 64,
    }) => GlassRecipe.of(
      variant: GlassVariant.regular,
      brightness: brightness,
      shortSide: shortSide,
      lift: lift,
    );

    test(
      'keeps the resting rim highlight and blur, and draws its own edge',
      () {
        for (final brightness in Brightness.values) {
          for (final lift in [GlassLift.lens, GlassLift.smallLens]) {
            final resting = _of(brightness: brightness, shortSide: 64);
            final lifted = lens(lift, brightness: brightness);
            expect(lifted.rimHighlight, resting.rimHighlight);
            expect(lifted.blur, resting.blur);
            expect(lifted.blurFill, resting.blurFill);
            expect(lifted.bleed, BleedRecipe.none);
            expect(lifted.ringShadow, RingShadowRecipe.none);
            final specular = lifted.darkSpecular;
            expect(specular.amount, 0.5);
            expect(specular.width, 1);
            expect(specular.reach, _near(2 / 3));
            expect(specular.inset, _near(1 / 3));
            expect(specular.colorBias, -0.3);
            expect(specular.spread, _near(_deg(120)));
          }
        }
      },
    );

    test("a selection's face keeps every colour, a knob's lifts black", () {
      double shown(FaceRecipe face, double c, double luma) =>
          face.black +
          (face.white - face.black) * luma +
          face.saturation * (c - luma);
      final selection = lens(GlassLift.lens).face;
      final knob = lens(GlassLift.smallLens).face;
      for (final face in [selection, knob]) {
        expect(face.rollOff, 0);
        expect(face.fill.a, 0);
      }
      for (final (c, luma) in [
        (0.0, 0.0),
        (0.2, 0.5),
        (0.9, 0.4),
        (1.0, 1.0),
      ]) {
        expect(shown(selection, c, luma), _near(c));
        expect(shown(knob, c, luma), _near(0.1 + 0.9 * c));
      }
    });

    test('draws one edge and face from 37 to 70 points', () {
      for (final lift in [GlassLift.lens, GlassLift.smallLens]) {
        final at64 = lens(lift);
        for (final side in [37.0, 50.0, 70.0]) {
          final at = lens(lift, shortSide: side);
          expect(at.rimHighlight, at64.rimHighlight);
          expect(at.darkSpecular, at64.darkSpecular);
          expect(at.face, at64.face);
        }
      }
    });
  });

  test('no law of the size changes past the panel a worn recipe stops at', () {
    for (final variant in GlassVariant.values) {
      for (final brightness in Brightness.values) {
        for (final highContrast in [false, true]) {
          for (final slider in [0.0, 0.5, 1.0]) {
            GlassRecipe at(double side) => _of(
              variant: variant,
              brightness: brightness,
              shortSide: side,
              slider: slider,
              highContrast: highContrast,
            );
            final edge = at(recipeSizes.panel);
            final far = at(1000);
            expect(far.face, edge.face);
            expect(far.blurFill, edge.blurFill);
            expect(far.bleed, edge.bleed);
            expect(far.ringShadow, edge.ringShadow);
            expect(far.darkSpecular, edge.darkSpecular);
            expect(far.rimHighlight, edge.rimHighlight);
          }
        }
      }
    }
  });

  test('equal inputs give equal recipes', () {
    expect(_of(slider: 0.3), _of(slider: 0.3));
    expect(_of(slider: 0.3).hashCode, _of(slider: 0.3).hashCode);
    expect(_of(slider: 0.3), isNot(_of(slider: 0.4)));
  });
}
