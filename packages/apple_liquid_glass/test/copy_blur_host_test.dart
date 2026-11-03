// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copy
// is drawn as Impeller draws it.
//
// The band's copy is the renderer's: the test turns copies on under
// flutter test and asks whether one serves.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';

const _key = ValueKey('page');

Widget _page(ScrollController controller) => MediaQuery(
  data: const MediaQueryData(size: Size(300, 400), devicePixelRatio: 3),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.liquid()),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: RepaintBoundary(
            key: _key,
            child: GlassPageScaffold(
              backgroundColor: const Color(0xFF000000),
              navigationBar: const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: SizedBox(height: 60),
              ),
              child: GlassContentScroll(
                edgeEffects: const GlassScrollEdgeEffects(
                  top: GlassScrollEdgeEffect.hard,
                ),
                child: ListView(
                  controller: controller,
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(
                        height: 30,
                        child: i == 7
                            ? Center(
                                child: MotionTransition(
                                  opacity: const AlwaysStoppedAnimation(0.7),
                                  blur: const AlwaysStoppedAnimation(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var j = 0; j < 4; j++)
                                        Container(
                                          width: 12,
                                          height: 20,
                                          margin: const EdgeInsets.all(3),
                                          color: const Color(0xFFFFFFFF),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : ColoredBox(
                                color: Color(
                                  0xFF000000 | (i * 2654435761) & 0x7F7F7F,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

LiquidGlassBackdropFilterLayer _band(WidgetTester tester) =>
    tester.layers.whereType<LiquidGlassBackdropFilterLayer>().single;

Future<Uint8List> _scrolled(WidgetTester tester) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_page(controller));
  await tester.pump();
  controller.jumpTo(240);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 3),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  setUp(MotionClock.debugReset);
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    LiquidGlassBackdropFrost.debugShaderFrost = true;
  });

  // The copy bounds the blur's layer by the transition's content; bounded
  // any tighter, the blur would be cut.
  testWidgets('a blurred transition under a copy blurs as it does on the '
      'screen', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Exact parity needs the band's filtered copy; the shader frost is NEAR.
    LiquidGlassBackdropFrost.debugShaderFrost = false;

    BackdropUnderlay.debugEnabledOverride = false;
    final live = await _scrolled(tester);

    BackdropUnderlay.debugEnabledOverride = true;
    final copied = await _scrolled(tester);
    expect(_band(tester).serves, isTrue);
    expect(_difference(live, copied), 0);
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
