import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _size = Size(200, 64);
const _origin = Offset(20, 28);

/// Darkening of glass in [appearance] over white, in 8-bit levels: 8 pt
/// inside the top and bottom walls relative to the center of the face, and
/// in the pixel just outside the left wall relative to the white.
Future<({double top, double bottom, double side})> _innerShadow(
  WidgetTester tester,
  LiquidGlassSettings settings, {
  LiquidGlassAppearance appearance = const LiquidGlassAppearance.ios27Regular(
    brightness: Brightness.light,
  ),
  bool fake = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(240, 120);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: Colors.white,
          child: LiquidGlassLayer(
            fake: fake,
            settings: settings,
            defaultAppearance: appearance,
            child: Stack(
              children: [
                Positioned(
                  left: _origin.dx,
                  top: _origin.dy,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(radius: 32),
                    child: SizedBox(width: 200, height: 64),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = (await tester.runAsync(image.toByteData))!;
  final width = image.width;
  image.dispose();
  double luma(double x, double y) {
    final i = (y.round() * width + x.round()) * 4;
    return lumaWeights.$1 * bytes.getUint8(i) +
        lumaWeights.$2 * bytes.getUint8(i + 1) +
        lumaWeights.$3 * bytes.getUint8(i + 2);
  }

  final x = _origin.dx + _size.width / 2;
  final face = luma(x, _origin.dy + _size.height / 2);
  return (
    top: face - luma(x, _origin.dy + 8),
    bottom: face - luma(x, _origin.dy + _size.height - 8),
    side: 255 - luma(_origin.dx - 1, _origin.dy + _size.height / 2),
  );
}

void main() {
  final base = const LiquidGlassSettings.ios27Regular(
    brightness: Brightness.light,
    frost: LiquidGlassFrost.sigma(0),
  ).copyWith(glintStrength: 0, contourStrength: 0);

  testWidgets(
    'FakeGlass of an iOS 27 look draws its ring shadow below the top wall '
    'only, as real glass does',
    (tester) async {
      final fake = await _innerShadow(tester, base);
      final real = await _innerShadow(tester, base, fake: false);
      final noBevel = await _innerShadow(
        tester,
        base.copyWith(bevelShadowStrength: 0),
      );

      // iOS 27 darkens white about 4 levels there.
      expect(fake.top, inInclusiveRange(3, 6.5));
      expect(fake.top, closeTo(real.top, 1.5));
      expect(fake.bottom, lessThan(1.5));
      expect(noBevel.top, closeTo(fake.top, 0.6));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'FakeGlass of an iOS 27 look darkens just outside its side walls, as '
    'real glass does',
    (tester) async {
      final fake = await _innerShadow(tester, base);
      final real = await _innerShadow(tester, base, fake: false);

      expect(real.side, greaterThan(10));
      expect(fake.side, closeTo(real.side, 4));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'FakeGlass of the direct model draws the bevel shadow it is given',
    (tester) async {
      const direct = LiquidGlassAppearance();
      final preset = await _innerShadow(tester, base, appearance: direct);
      final none = await _innerShadow(
        tester,
        base.copyWith(bevelShadowStrength: 0),
        appearance: direct,
      );
      final strong = await _innerShadow(
        tester,
        base.copyWith(bevelShadowStrength: 0.15),
        appearance: direct,
      );

      expect(none.top, closeTo(0, 0.6));
      expect(preset.top, greaterThan(1));
      expect(preset.bottom, lessThan(1.5));
      expect(strong.top / preset.top, closeTo(0.15 / 0.036, 1));
    },
    skip: skipProperGlassTests,
  );
}
