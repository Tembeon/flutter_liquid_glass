@Tags(['macos_pixels'])
library;

import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ValueKey('lens');
const _dpr = 3.0;
const _lens = Rect.fromLTWH(15, 13, 110, 44);

// A segmented control's lens held up over a page of grey [page] in
// [brightness]: the darkest red at its left end, from 3 points outside it
// to 6 inside.
Future<int> _end(
  WidgetTester tester, {
  required Brightness brightness,
  required int page,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        platformBrightness: brightness,
        devicePixelRatio: _dpr,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _key,
          child: GlassScope(
            renderer: const LiquidGlassRenderer(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Color.fromARGB(255, page, page, page),
                  ),
                ),
                Positioned.fromRect(
                  rect: _lens,
                  child: GlassSurface.live(
                    role: GlassRole.lens,
                    frame: MotionSelection(() => const GlassFrame(lift: 1)),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => render.toImage(pixelRatio: _dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  final pixels = bytes.buffer.asUint8List();
  final y = (_lens.center.dy * _dpr).round();
  var least = 255;
  for (
    var x = ((_lens.left - 3) * _dpr).round();
    x <= ((_lens.left + 6) * _dpr).round();
    x++
  ) {
    final value = pixels[(y * image.width + x) * 4];
    if (value < least) least = value;
  }
  image.dispose();
  return least;
}

void main() {
  setUp(MotionClock.debugReset);

  // The iPhone 16 Pro on iOS 27.2.1, a segmented control's selection held
  // up over its grouped page: the darkest pixel of the lens's two ends, which
  // lie at two pixel phases, is 10 and 8 over a page of 28 in dark mode and
  // 148 and 162 over 227 in light mode.
  for (final (brightness, page, ends) in [
    (Brightness.dark, 28, (8, 10)),
    (Brightness.light, 227, (148, 162)),
  ]) {
    testWidgets('a lifted lens darkens its end as the iPhone does '
        '(${brightness.name})', (tester) async {
      tester.view
        ..physicalSize = const Size(140, 70) * _dpr
        ..devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      expect(
        await _end(tester, brightness: brightness, page: page),
        inInclusiveRange(ends.$1 - 2, ends.$2 + 2),
      );
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }
}
