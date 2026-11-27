import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:material_ui/material_ui.dart';

import 'ios27_native_faces.dart';
import 'shared.dart';

void main() {
  testWidgets('glass over a plain color shows the face native glass of its '
      'size shows', (tester) async {
    tester.view
      ..physicalSize = nativeFaceView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final off = <String>[];
    for (final (brightness, size, slider, page, native, tint)
        in nativeFaceCases) {
      await tester.pumpWidget(
        nativeFaceScene(brightness, size, slider, page, tint: tint),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(nativeFaceKey),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      final rgba = bytes.buffer.asUint8List();
      final at =
          ((nativeFaceView.height ~/ 2) * nativeFaceView.width.toInt() +
              nativeFaceView.width ~/ 2) *
          4;
      final drawn = [rgba[at], rgba[at + 1], rgba[at + 2]];
      final wanted = [
        (native.r * 255).round(),
        (native.g * 255).round(),
        (native.b * 255).round(),
      ];
      for (var channel = 0; channel < 3; channel++) {
        if ((drawn[channel] - wanted[channel]).abs() > 2) {
          off.add(
            '${brightness?.name ?? 'clear'} ${size.height} pt at slider '
            '$slider over $page under $tint: drew $drawn, native $wanted',
          );
          break;
        }
      }
      await tester.pumpWidget(const SizedBox());
    }
    expect(off, isEmpty, reason: off.join('\n'));
  }, skip: skipProperGlassTests);

  testWidgets('Increase Contrast reaches the face glass draws', (
    tester,
  ) async {
    tester.view
      ..physicalSize = nativeFaceView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const black = Color(0xFF000000);
    Future<List<int>> centre(
      LiquidGlassSettings settings,
      LiquidGlassAppearance appearance,
    ) async {
      await tester.pumpWidget(
        nativeFaceGlass(settings, appearance, nativeControl, black),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(nativeFaceKey),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      final rgba = bytes.buffer.asUint8List();
      final at =
          ((nativeFaceView.height ~/ 2) * nativeFaceView.width.toInt() +
              nativeFaceView.width ~/ 2) *
          4;
      await tester.pumpWidget(const SizedBox());
      return [rgba[at], rgba[at + 1], rgba[at + 2]];
    }

    for (final (variant, brightness) in [
      (GlassVariant.regular, Brightness.light),
      (GlassVariant.regular, Brightness.dark),
      (GlassVariant.clear, Brightness.light),
    ]) {
      final drawn = <List<int>>[];
      for (final highContrast in [false, true]) {
        final (settings, appearance) = variant == GlassVariant.clear
            ? (
                const LiquidGlassSettings.ios27Clear(),
                LiquidGlassAppearance.ios27Clear(
                  brightness: Brightness.light,
                  highContrast: highContrast,
                ),
              )
            : (
                const LiquidGlassSettings.ios27Regular(),
                LiquidGlassAppearance.ios27Regular(
                  brightness: brightness,
                  highContrast: highContrast,
                ),
              );
        final face = GlassRecipe.of(
          variant: variant,
          brightness: brightness,
          shortSide: nativeControl.height,
          highContrast: highContrast,
        ).face;
        final fill = face.fill;
        final wanted = [
          for (final channel in [fill.r, fill.g, fill.b])
            ((face.black * (1 - fill.a) + channel * fill.a).clamp(0.0, 1.0) *
                    255)
                .round(),
        ];
        final colour = await centre(settings, appearance);
        for (var channel = 0; channel < 3; channel++) {
          expect(
            colour[channel],
            closeTo(wanted[channel], 2),
            reason:
                '$variant ${brightness.name} over black, '
                'highContrast $highContrast: drew $colour, '
                'the recipe gives $wanted',
          );
        }
        drawn.add(colour);
      }
      expect(drawn.first, isNot(drawn.last), reason: '$variant $brightness');
    }
  }, skip: skipProperGlassTests);

  testWidgets('a shape that grows takes the face of its new size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = nativeFaceView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<int> face(Size size) async {
      await tester.pumpWidget(
        nativeFaceScene(Brightness.dark, size, 0, const Color(0xFFFFFFFF)),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(nativeFaceKey),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      return bytes.buffer.asUint8List()[((nativeFaceView.height ~/ 2) *
                  nativeFaceView.width.toInt() +
              nativeFaceView.width ~/ 2) *
          4];
    }

    expect(await face(nativeControl), closeTo(0xB9, 2));
    expect(await face(nativePanel), closeTo(0x92, 2));
    expect(await face(nativeToolbar), closeTo(0x9C, 2));
    expect(await face(nativeControl), closeTo(0xB9, 2));
  }, skip: skipProperGlassTests);

  test('glass up to 64 points and from 160 points wears one model each', () {
    for (final brightness in Brightness.values) {
      final model = LiquidGlassColorModel.ios27Regular(brightness: brightness);
      expect(identical(model.wornAt(20), model.wornAt(64)), isTrue);
      expect(identical(model.wornAt(160), model.wornAt(900)), isTrue);
      expect(identical(model.wornAt(175), model.wornAt(192)), isTrue);
      expect(model.wornAt(159), isNot(model.wornAt(160)));
      expect(model.wornAt(64), isNot(model.wornAt(192)));
      expect(model.wornAt(100), model.wornAt(100));
      expect(model.wornAt(100), isNot(model.wornAt(120)));
      expect(
        recipeOf((model.wornAt(64) as WornRecipe).look, (
          slider: 0,
          reduceTransparency: false,
        )).bleed.opacity,
        0,
      );
    }
    const clear = LiquidGlassColorModel.ios27Clear(
      brightness: Brightness.light,
    );
    expect(identical(clear.wornAt(40), clear.wornAt(64)), isTrue);
    expect(identical(clear.wornAt(160), clear.wornAt(400)), isTrue);
    const direct = LiquidGlassColorModel.direct(brightness: Brightness.light);
    expect(direct.wornAt(40), direct.wornAt(400));
    expect(direct.wornAt(40), isA<WornDirect>());
  });

  test('a lifted lens wears one model at every size it takes', () {
    for (final brightness in Brightness.values) {
      for (final lens in [
        LiquidGlassColorModel.ios27Lens(brightness: brightness),
        LiquidGlassColorModel.ios27SmallLens(brightness: brightness),
      ]) {
        final worn = lens.wornAt(37);
        for (final side in [44.0, 57.0, 70.0, 114.0]) {
          expect(identical(lens.wornAt(side), worn), isTrue);
        }
        expect(
          worn.blurredAs,
          (variant: GlassVariant.regular, brightness: brightness),
        );
      }
    }
  });

  test('a grey tint takes its own tones, a color the tones of its scheme', () {
    const light = LiquidGlassColorModel.ios27Regular(
      brightness: Brightness.light,
    );
    const dark = LiquidGlassColorModel.ios27Regular(
      brightness: Brightness.dark,
    );
    const clear = LiquidGlassColorModel.ios27Clear(
      brightness: Brightness.light,
    );
    const white = Color(0xFFFFFFFF);
    const grey = Color(0x80808080);
    // The tone of channel [c] of a tint over a face of luminance [face].
    double tone(WornColorModel worn, double c, double face) {
      final law = tintLawOf((worn as WornRecipe).look);
      final low = law.lowScale * c + law.lowBias;
      final high = law.highScale * c + law.highBias;
      return (low < law.lowFloor ? law.lowFloor : low) +
          (high - (low < law.lowFloor ? law.lowFloor : low)) * face;
    }

    for (final model in [light, dark, clear]) {
      final tinted = model.wornAt(200, tint: white);
      // The diagonal matrix UIKit gives a grey tint g over black:
      // 1.1875 g - 0.25.
      expect(tone(tinted, 1, 0), closeTo(0.9375, 1e-9));
      expect(tone(tinted, grey.g, 0), closeTo(0.346, 1e-3));
      expect(
        identical(
          model.wornAt(200, tint: white),
          model.wornAt(300, tint: grey),
        ),
        isTrue,
      );
      expect(model.wornAt(200, tint: white), isNot(model.wornAt(200)));
      expect(
        identical(
          model.wornAt(200, tint: const Color(0x00808080)),
          model.wornAt(200),
        ),
        isTrue,
      );
    }
    // A color runs between the two tones UIKit's matrix gives it.
    const blue = Color(0xFF007AFF);
    final onLight = light.wornAt(200, tint: blue);
    expect(tone(onLight, blue.g, 0), closeTo(0.2502, 1e-3));
    expect(tone(onLight, blue.b, 0), closeTo(0.6, 1e-3));
    expect(tone(onLight, blue.g, 1), closeTo(0.4784, 1e-3));
    final onDark = dark.wornAt(200, tint: blue);
    expect(tone(onDark, blue.g, 0), closeTo(0.4651, 1e-3));
    expect(tone(onDark, blue.r, 1), closeTo(0.1735, 1e-3));
    expect(tone(onDark, blue.b, 1), closeTo(0.9681, 1e-3));
    expect(tone(clear.wornAt(200, tint: blue), blue.b, 0), closeTo(0.6, 1e-3));
  });

  test('glass between a control and a panel wears part of the veil', () {
    final panel = recipeOf(
      (
        variant: GlassVariant.regular,
        brightness: Brightness.dark,
        shortSide: 120,
        greyTint: false,
        highContrast: false,
        lift: GlassLift.resting,
      ),
      (slider: 0, reduceTransparency: false),
    );
    expect(panel.bleed.opacity, closeTo(0.8 * 56 / 96, 1e-12));
  });
}
