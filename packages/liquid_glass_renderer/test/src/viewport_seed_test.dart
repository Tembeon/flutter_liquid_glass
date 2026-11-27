import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('page');
const _glass = Rect.fromLTWH(40, 90, 160, 60);

// A viewport inside the screen whose content does not overflow: it pushes no
// clip, so a pass inside it starts where the screen's does.
const _viewport = Rect.fromLTWH(30, 50, 240, 220);

// Stripes a refraction shift shows in.
class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 6, size.height),
        Paint()..color = const Color(0xFF203080),
      );
    }
    for (var y = 0.0; y < size.height; y += 10) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 4),
        Paint()..color = const Color(0x80E04020),
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

Widget _seededGlass() => Opacity(
  opacity: 0.6,
  child: LiquidGlassLayer(
    settings: const LiquidGlassSettings(blur: 0),
    child: LiquidGlass(
      shape: const LiquidRoundedSuperellipse(radius: 20),
      appearance: const LiquidGlassAppearance(
        colorModel: LiquidGlassColorModel.direct(brightness: Brightness.light),
      ),
      child: SizedBox.fromSize(size: _glass.size),
    ),
  ),
);

Future<List<int>> _render(WidgetTester tester, {required bool inViewport}) {
  final glass = inViewport
      ? Positioned.fromRect(
          rect: _viewport,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  left: _glass.left - _viewport.left,
                  top: _glass.top - _viewport.top,
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _seededGlass(),
                  ),
                ),
              ),
            ],
          ),
        )
      : Positioned.fromRect(rect: _glass, child: _seededGlass());
  return tester
      .pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: _key,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _Stripes())),
                glass,
              ],
            ),
          ),
        ),
      )
      .then((_) => tester.pump())
      .then((_) => boundaryPixels(tester, find.byKey(_key)));
}

void main() {
  testWidgets(
    'seeded glass in a viewport that does not overflow reads the backdrop '
    'under it',
    (tester) async {
      tester.view
        ..physicalSize = const Size(300, 300)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final alone = await _render(tester, inViewport: false);
      final inViewport = await _render(tester, inViewport: true);
      expect(largestDifference(alone, inViewport), lessThanOrEqualTo(2));
    },
    skip: skipProperGlassTests,
  );
}
