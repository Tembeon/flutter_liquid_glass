import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('lens');
const _backdrop = 128;

// A lifted lens over a flat grey at dpr 3, its left edge a quarter of a
// device pixel before a pixel boundary: the pixel whose center lies 0.75 of
// a device pixel inside the edge, at the middle of the lens's end where the
// rim highlight does not light, shows only the dark specular's inner part.
Future<int Function(int offset)> _endRow(
  WidgetTester tester, {
  required bool fake,
  LiquidGlassColorModel model = const LiquidGlassColorModel.ios27Lens(
    brightness: Brightness.light,
  ),
}) async {
  const dpr = 3.0;
  tester.view
    ..physicalSize = const Size(420, 210)
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  const left = 15 + 0.75 / dpr;
  const size = Size(110, 44);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(
                color: Color.fromARGB(255, _backdrop, _backdrop, _backdrop),
              ),
            ),
            Positioned(
              left: left,
              top: 13,
              width: size.width,
              height: size.height,
              child: LiquidGlassLayer(
                settings: const LiquidGlassSettings(blur: 0),
                fake: fake,
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(radius: size.height / 2),
                  appearance: LiquidGlassAppearance(colorModel: model),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  final pixels = await boundaryPixels(
    tester,
    find.byKey(_key),
    pixelRatio: dpr,
  );
  final y = ((13 + size.height / 2) * dpr).floor();
  final edge = (left * dpr).floor();
  return (int offset) => pixels[(y * 420 + edge + offset) * 4];
}

Future<int> _innerPixel(WidgetTester tester, {required bool fake}) async =>
    (await _endRow(tester, fake: fake))(1);

void main() {
  testWidgets(
    "real glass draws a lifted lens's dark band where it reaches inside",
    (tester) async {
      expect(await _innerPixel(tester, fake: false), lessThan(_backdrop - 4));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    "fake glass draws a lifted lens's dark band where it reaches inside",
    (tester) async {
      expect(await _innerPixel(tester, fake: true), lessThan(_backdrop - 4));
    },
  );

  testWidgets(
    "real glass draws a recipe's dark band out to its reach and no further",
    (tester) async {
      final at = await _endRow(
        tester,
        fake: false,
        model: const LiquidGlassColorModel.ios27Regular(
          brightness: Brightness.light,
        ),
      );
      expect(at(-1), lessThan(_backdrop - 4));
      expect(at(-2), closeTo(_backdrop, 1));
    },
    skip: skipProperGlassTests,
  );
}
