import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('rim');
const _dpr = 3.0;
const _view = Size(402, 120);
const _glass = Rect.fromLTWH(21, 30, 360, 62);

// The middle of the glass's top edge, from its first lit pixel down.
Future<List<int>> _topEdge(WidgetTester tester) async {
  tester.view
    ..physicalSize = _view * _dpr
    ..devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
            Positioned.fromRect(
              rect: _glass,
              child: LiquidGlassLayer(
                settings: const LiquidGlassSettings.ios27Regular(),
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(radius: _glass.height / 2),
                  appearance: const LiquidGlassAppearance.ios27Regular(
                    brightness: Brightness.dark,
                  ),
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
    pixelRatio: _dpr,
  );
  final width = (_view.width * _dpr).round();
  final x = (_glass.center.dx * _dpr).round();
  final column = [
    for (var y = 0; y < (_glass.center.dy * _dpr).round(); y++)
      pixels[(y * width + x) * 4],
  ];
  final edge = column.indexWhere((value) => value > 0);
  return column.sublist(edge, edge + 6);
}

void main() {
  // Dark glass at rest over black, its top edge in the middle of a tab bar
  // on the iPhone 16 Pro (iOS 27.2.1, 3 px a point): 99, 79, 63, then the
  // face from 44. iOS lights the rim with a line and a diffuse glow whose
  // masks add up past 1 near the edge, the line falling off in proportion
  // to its mask: drawn as a step clamped at 1 it lay flat, 66 66 66 over 49.
  testWidgets('the rim of dark glass over black lights its top edge as the '
      'iPhone does: bright at the edge and falling off', (tester) async {
    final edge = await _topEdge(tester);
    expect(edge[0] - edge[4], greaterThanOrEqualTo(40), reason: '$edge');
    expect(edge[0], greaterThan(edge[1]), reason: '$edge');
    expect(edge[1], greaterThan(edge[2]), reason: '$edge');
    expect(edge[2], greaterThan(edge[3]), reason: '$edge');
  }, skip: skipProperGlassTests);
}
