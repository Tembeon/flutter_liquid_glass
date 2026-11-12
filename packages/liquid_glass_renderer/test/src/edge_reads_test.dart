import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(40, 40, 120, 70);

const _clear = LiquidGlassSettings(
  refractionHeight: 0,
  refractionAmount: 0,
  frost: 0,
  highlight: 0,
  contourStrength: 0,
  bevelShadowStrength: 0,
);

Widget _scene(LiquidGlassSettings settings, List<Rect> white) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
        for (final rect in white)
          Positioned.fromRect(
            rect: rect,
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        Positioned.fill(
          child: LiquidGlassLayer(
            settings: settings,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: _glass,
                  child: const LiquidGlass(
                    appearance: LiquidGlassAppearance(),
                    shape: LiquidRoundedRectangle(borderRadius: 35),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);

Future<Color Function(int x, int y)> _pixels(
  WidgetTester tester,
  LiquidGlassSettings settings,
  List<Rect> white,
) async {
  await tester.pumpWidget(_scene(settings, white));
  await tester.pump();
  final (Uint8List bytes, int width) = (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
  return (int x, int y) {
    final at = (y * width + x) * 4;
    return Color.fromARGB(255, bytes[at], bytes[at + 1], bytes[at + 2]);
  };
}

int _red(Color color) => (color.r * 255).round();
int _blue(Color color) => (color.b * 255).round();

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(200, 150);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a pull shows what lies just outside the glass inside its edge '
      'and leaves its middle in place', (tester) async {
    _size(tester);
    // A stripe 2 to 6 px above the glass, and a mark on its center.
    const white = [
      Rect.fromLTWH(0, 34, 200, 4),
      Rect.fromLTWH(98, 73, 4, 4),
    ];
    final plain = await _pixels(tester, _clear, white);
    expect(_red(plain(100, 42)), lessThan(10));
    expect(_red(plain(100, 75)), greaterThan(245));

    final pulled = await _pixels(
      tester,
      _clear.copyWith(backdropPull: 9, backdropPullHeight: 36),
      white,
    );
    // 2.5 px deep the glass reads 5.7 px farther out: the stripe.
    expect(_red(pulled(100, 42)), greaterThan(200));
    // 20.5 px deep it reads 1.6 px farther out: the page under the glass.
    expect(_red(pulled(100, 60)), lessThan(10));
    expect(_red(pulled(100, 75)), greaterThan(245));
  }, skip: skipProperGlassTests);

  testWidgets('an aberration shows a line under the glass blue toward the '
      'edge and red toward the middle', (tester) async {
    _size(tester);
    // A line 8 to 10 px deep under the glass.
    const white = [Rect.fromLTWH(0, 48, 200, 2)];
    final plain = await _pixels(tester, _clear, white);
    expect(_blue(plain(100, 46)), lessThan(10));
    expect(_red(plain(100, 52)), lessThan(10));
    expect(_red(plain(100, 48)), greaterThan(245));

    final parted = await _pixels(
      tester,
      _clear.copyWith(aberration: 3, aberrationDepth: 30),
      white,
    );
    // Toward the edge blue reads the line from 2 and 3 px farther in.
    final outer = parted(100, 46);
    expect(_blue(outer), greaterThan(120));
    expect(_red(outer), lessThan(10));
    // Toward the middle red reads it from 3 px farther out.
    final inner = parted(100, 52);
    expect(_red(inner), greaterThan(50));
    expect(_blue(inner), lessThan(10));
    // The line itself dims: each color reads mostly beside it.
    expect(_red(parted(100, 48)), lessThan(200));
  }, skip: skipProperGlassTests);
}
