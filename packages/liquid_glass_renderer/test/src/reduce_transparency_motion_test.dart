// Glass under Reduce Transparency blurs what lies past it from a copy that
// holds only iOS's capture margin past the glass. A cell of its levels that
// the copy's edge cuts averages what the copy holds, and the ring around a
// level holds the cells beside it, so the face changes smoothly as the
// glass moves (copy_levels.frag).
@Tags(['composer'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('motion');
const _dpr = 3.0;
const _view = Size(402, 320);

typedef _Case = ({String name, bool rt, bool clear, Size glass, bool across});

Widget _scene(_Case c, Offset at) {
  final colors = [
    const Color(0xFFE53935),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFFFFFFFF),
    const Color(0xFF212121),
    const Color(0xFFFDD835),
  ];
  final stripes = [
    for (var i = 0; i < 20; i++)
      Expanded(child: ColoredBox(color: colors[i % colors.length])),
  ];
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        children: [
          Positioned.fill(
            child: c.across
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: stripes,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: stripes,
                  ),
          ),
          Positioned(
            left: at.dx,
            top: at.dy,
            width: c.glass.width,
            height: c.glass.height,
            child: LiquidGlassLayer(
              settings: c.clear
                  ? LiquidGlassSettings.ios27Clear(reduceTransparency: c.rt)
                  : LiquidGlassSettings.ios27Regular(reduceTransparency: c.rt),
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(
                  radius: c.glass.shortestSide / 2,
                ),
                appearance: c.clear
                    ? const LiquidGlassAppearance.ios27Clear(
                        brightness: Brightness.light,
                      )
                    : const LiquidGlassAppearance.ios27Regular(
                        brightness: Brightness.light,
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

// The face's middle line along the motion, 20 points in from either end.
List<int> _line(Uint8List pixels, _Case c, Offset at) {
  final width = (_view.width * _dpr).round();
  final out = <int>[];
  if (!c.across) {
    final y = ((at.dy + c.glass.height / 2) * _dpr).round();
    for (var x = at.dx + 20; x <= at.dx + c.glass.width - 20; x += 1) {
      final i = (y * width + (x * _dpr).round()) * 4;
      out.addAll([pixels[i], pixels[i + 1], pixels[i + 2]]);
    }
  } else {
    final x = ((at.dx + c.glass.width / 2) * _dpr).round();
    for (var y = at.dy + 12; y <= at.dy + c.glass.height - 12; y += 1) {
      final i = ((y * _dpr).round() * width + x) * 4;
      out.addAll([pixels[i], pixels[i + 1], pixels[i + 2]]);
    }
  }
  return out;
}

void main() {
  const cases = <_Case>[
    (
      name: 'a control along stripes',
      rt: true,
      clear: false,
      glass: Size(144, 58),
      across: false,
    ),
    (
      name: 'a control across stripes',
      rt: true,
      clear: false,
      glass: Size(144, 58),
      across: true,
    ),
    (
      name: 'a panel along stripes',
      rt: true,
      clear: false,
      glass: Size(240, 170),
      across: false,
    ),
  ];
  for (final c in cases) {
    testWidgets('glass under Reduce Transparency, ${c.name}, moving a point '
        'a frame changes its face smoothly', (tester) async {
      tester.view.physicalSize = _view * _dpr;
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      glassReadsCopies = true;
      addTearDown(() => glassReadsCopies = false);
      Offset at(double t) => c.across
          ? Offset((_view.width - c.glass.width) / 2, 10 + t)
          : Offset(10 + t, (_view.height - c.glass.height) / 2);
      final travel = c.across
          ? _view.height - c.glass.height - 20
          : _view.width - c.glass.width - 20;
      await tester.pumpWidget(_scene(c, at(0)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      List<int>? last;
      var worst = 0;
      var worstAt = 0.0;
      for (var t = 0.0; t <= travel; t += 1) {
        await tester.pumpWidget(_scene(c, at(t)));
        await tester.pump();
        final line = _line(
          await boundaryPixels(tester, find.byKey(_key), pixelRatio: _dpr),
          c,
          at(t),
        );
        if (last != null) {
          final step = largestDifference(line, last);
          if (step > worst) (worst, worstAt) = (step, t);
        }
        last = line;
      }
      // 3 to 6 as the glass slides over the stripes; 15 to 24 at each stripe
      // where cut cells repeated the copy's edge, and 22 to 38 where the
      // strip moved a cell under a ring that repeated the edge.
      expect(worst, lessThanOrEqualTo(6), reason: 'at $worstAt');
    }, skip: skipProperGlassTests);
  }
}
