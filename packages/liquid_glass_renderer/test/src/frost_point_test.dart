@Tags(['composer'])
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _dot = Offset(130, 95);

// A black page with one white dot, under frosted glass that covers it.
Widget _scene(double frost) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
        Positioned.fromRect(
          rect: Rect.fromCenter(center: _dot, width: 7, height: 7),
          child: const ColoredBox(color: Color(0xFFFFFFFF)),
        ),
        Positioned.fromRect(
          rect: const Rect.fromLTWH(30, 40, 200, 110),
          child: LiquidGlassLayer(
            settings: const LiquidGlassSettings.ios27Regular().copyWith(
              blur: frost,
            ),
            child: const LiquidGlass(
              shape: LiquidRoundedSuperellipse(radius: 28),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  // A frost of a few sparse taps draws a point under the glass as that many
  // points: stars under clear glass were small flowers on the iPhone. Glass
  // that blurs from the levels beside its copy reads each level's cells,
  // which average every pixel of the copy, so the point is one soft dot:
  // its light only falls along every way out of its brightest pixel. That
  // pixel lies up to half a cell of the levels read from the dot, which the
  // grid's phase picks as in Apple's pyramid: a cell is about 1.7 sigmas
  // wide.
  for (final frost in [5.0, 8.0, 12.0]) {
    testWidgets('a point under glass frosted by $frost stays one point', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      glassReadsCopies = true;
      copyIntoImages();
      await tester.pumpWidget(_scene(frost));
      await tester.pump();
      final glass = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .single;
      expect(glass.debugDrewOverCopy, isTrue);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_key),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final pixels = (await tester.runAsync(
        image.toByteData,
      ))!.buffer.asUint8List();
      final width = image.width;
      image.dispose();
      int light(int x, int y) => pixels[(y * width + x) * 4 + 1];

      final floor = light(_dot.dx.round() + 45, _dot.dy.round());
      var (x, y) = (_dot.dx.round(), _dot.dy.round());
      for (var dy = -12; dy <= 12; dy++) {
        for (var dx = -12; dx <= 12; dx++) {
          final at = (_dot.dx.round() + dx, _dot.dy.round() + dy);
          if (light(at.$1, at.$2) > light(x, y)) (x, y) = at;
        }
      }
      final peak = light(x, y);
      expect(peak - floor, greaterThan(6), reason: 'the dot shows');
      expect((x - _dot.dx).abs(), lessThanOrEqualTo(frost));
      expect((y - _dot.dy).abs(), lessThanOrEqualTo(frost));
      // The largest rise of light on the way out of the brightest pixel,
      // over the eight ways: a second point is a rise of many levels, where
      // the cells of the two levels read meet it is up to two.
      var rise = 0;
      for (final (dx, dy) in const [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (-1, 1),
        (1, -1),
        (-1, -1),
      ]) {
        var lowest = peak;
        for (var step = 1; step <= 40; step++) {
          final at = light(x + dx * step, y + dy * step);
          if (at - lowest > rise) rise = at - lowest;
          if (at < lowest) lowest = at;
        }
      }
      expect(rise, lessThanOrEqualTo(2));
    }, skip: skipProperGlassTests);
  }
}
