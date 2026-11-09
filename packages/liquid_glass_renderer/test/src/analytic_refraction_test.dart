@Tags(['macos_pixels'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('refraction');
const _view = Size(300, 200);

class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 3, size.height),
        Paint()..color = const Color(0xFF203040),
      );
    }
    for (var y = 0.0; y < size.height; y += 10) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 4),
        Paint()..color = const Color(0x80E0C060),
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

Future<Uint8List> _capture(WidgetTester tester, double ratio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets('an analytic frame refracts what its matte refracts', (
    tester,
  ) async {
    // The glass reads a copy: flutter_tester renders only a process's first
    // backdrop filter reliably, and this test draws two.
    GlassCopies.debugEnabledOverride = true;
    addTearDown(() => GlassCopies.debugEnabledOverride = null);
    const ratio = 2.0;
    tester.view
      ..physicalSize = _view * ratio
      ..devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    Widget scene(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: SizedBox.fromSize(
          size: _view,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xFFF0F0F0),
                  child: CustomPaint(painter: _Stripes()),
                ),
              ),
              LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularLight(),
                child: Stack(
                  children: [
                    Positioned(
                      left: 10,
                      top: 30,
                      width: width,
                      height: 140,
                      child: const LiquidGlass(
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: 24,
                          bottomRadius: 48,
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene(260));
    await tester.pumpWidget(scene(280));
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    expect(layer.debugAnalytic, isTrue);
    final analytic = await _capture(tester, ratio);
    for (var i = 0; i < RenderLiquidGlassLayer.analyticRestFrames + 2; i++) {
      await tester.pump();
    }
    expect(layer.debugAnalytic, isFalse, reason: 'rests on a matte');
    final matte = await _capture(tester, ratio);

    var total = 0;
    var differing = 0;
    for (var i = 0; i < matte.length; i++) {
      final d = (matte[i] - analytic[i]).abs();
      total += d;
      if (d > 16) differing++;
    }
    expect(total / matte.length, lessThan(0.2));
    expect(differing / matte.length, lessThan(0.002));
  }, skip: skipProperGlassTests);
}
