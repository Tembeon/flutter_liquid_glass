// Glass under Reduce Transparency blurs what lies past it from a copy that
// holds only iOS's capture margin past the glass, but never cuts a cell of
// the levels it reads: a cut cell changes as the glass moves.
@Tags(['composer'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('rt');
const _dpr = 3.0;
const _view = Size(402, 240);
const _glass = Size(144, 58);

Widget _scene(double left, Brightness brightness) {
  final colors = [
    const Color(0xFFE53935),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFFFFFFFF),
    const Color(0xFF212121),
    const Color(0xFFFDD835),
  ];
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 20; i++)
                  Expanded(child: ColoredBox(color: colors[i % colors.length])),
              ],
            ),
          ),
          Positioned(
            left: left,
            top: 91,
            width: _glass.width,
            height: _glass.height,
            child: LiquidGlassLayer(
              settings: const LiquidGlassSettings.ios27Regular(
                reduceTransparency: true,
              ),
              child: LiquidGlass(
                shape: const LiquidRoundedSuperellipse(radius: 29),
                appearance: LiquidGlassAppearance.ios27Regular(
                  brightness: brightness,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// The face's middle row, from 20 points inside one end to 20 inside the
// other, in the glass's own coordinates.
List<int> _row(Uint8List pixels, double left) {
  final width = (_view.width * _dpr).round();
  final y = ((91 + _glass.height / 2) * _dpr).round();
  final out = <int>[];
  for (var x = left + 20; x <= left + _glass.width - 20; x += 1) {
    final i = (y * width + (x * _dpr).round()) * 4;
    out.addAll([pixels[i], pixels[i + 1], pixels[i + 2]]);
  }
  return out;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('glass under Reduce Transparency moving a point a frame over '
        'stripes changes its face smoothly in $brightness', (tester) async {
      tester.view.physicalSize = _view * _dpr;
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      glassReadsCopies = true;
      addTearDown(() => glassReadsCopies = false);
      await tester.pumpWidget(_scene(100, brightness));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      List<int>? last;
      var worst = 0;
      var worstAt = 0.0;
      for (var left = 100.0; left <= 150; left += 1) {
        await tester.pumpWidget(_scene(left, brightness));
        await tester.pump();
        final row = _row(
          await boundaryPixels(tester, find.byKey(_key), pixelRatio: _dpr),
          left,
        );
        if (last != null) {
          final step = largestDifference(row, last);
          if (step > worst) (worst, worstAt) = (step, left);
        }
        last = row;
      }
      // 3 to 5 as the glass slides over the stripes, 22 to 38 where the
      // copy's edge cuts a cell of the coarsest level.
      expect(worst, lessThanOrEqualTo(6), reason: 'at $worstAt');
    }, skip: skipProperGlassTests);
  }
}
