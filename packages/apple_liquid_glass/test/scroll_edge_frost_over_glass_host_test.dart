// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the band
// frosts its copy through a runtime effect, which only Impeller draws.
//
// Glass under the band draws its copy at the screen's pixels: the band
// frosts that copy as much as the live read frosts the backdrop.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';

const _key = ValueKey('page');

Widget _page(
  ScrollController controller,
  double dpr, {
  required bool hard,
  required bool glass,
}) => MediaQuery(
  data: MediaQueryData(size: const Size(300, 400), devicePixelRatio: dpr),
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
              backgroundColor: const Color(0xFFFFFFFF),
              navigationBar: const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: SizedBox(height: 60),
              ),
              child: GlassContentScroll(
                edgeEffects: GlassScrollEdgeEffects(
                  top: hard
                      ? GlassScrollEdgeEffect.hard
                      : GlassScrollEdgeEffect.soft,
                ),
                child: ListView(
                  controller: controller,
                  children: [
                    // Hard edges every few pixels, where the frost's
                    // taps part most from Impeller's blur.
                    for (var i = 0; i < 40; i++)
                      Container(
                        height: 30,
                        color: Color(
                          0xFF000000 | (i * 2654435761) & 0xFFFFFF,
                        ),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.only(left: 10.0 + i * 5),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 3,
                              height: 30,
                              child: ColoredBox(color: Color(0xFFFFFFFF)),
                            ),
                            if (glass && i.isEven)
                              Padding(
                                padding: const EdgeInsets.only(left: 40),
                                child: SizedBox(
                                  width: 60,
                                  height: 24,
                                  child: LiquidGlassLayer(
                                    settings:
                                        LiquidGlassSettings.ios27RegularLight(),
                                    child: const LiquidGlass(
                                      shape: LiquidRoundedSuperellipse(
                                        borderRadius: 12,
                                      ),
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
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

Future<Uint8List> _scrolled(
  WidgetTester tester,
  double dpr, {
  required bool glass,
  required bool serves,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_page(controller, dpr, hard: false, glass: glass));
  await tester.pump();
  controller.jumpTo(200);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_band(tester).serves, serves);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

// The mean channel difference between [a] and [b] over the band's rows.
double _meanInBand(Uint8List a, Uint8List b, double dpr) {
  final width = (300 * dpr).ceil();
  var sum = 0;
  var count = 0;
  for (var y = 0; y < (110 * dpr).floor(); y++) {
    for (var x = 0; x < (300 * dpr).floor(); x++) {
      for (var c = 0; c < 3; c++) {
        final i = (y * width + x) * 4 + c;
        sum += (a[i] - b[i]).abs();
        count++;
      }
    }
  }
  return sum / count;
}

void main() {
  final inFrameDefault = BackdropUnderlay.debugInFrame;
  setUp(MotionClock.debugReset);
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    BackdropUnderlay.debugInFrame = inFrameDefault;
  });

  // Over the rows the frosted copy is 0.35 levels off the live read on
  // average (0.27 without the glass); a copy frosted for the share it was
  // asked for rather than drawn at is 1.45 off.
  for (final dpr in [2.625, 3.0]) {
    testWidgets('the band at $dpr frosts a copy drawn in the frame over '
        'glass as the live read does', (tester) async {
      tester.view.physicalSize = Size(300 * dpr, 400 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      BackdropUnderlay.debugInFrame = true;
      BackdropUnderlay.debugEnabledOverride = false;
      final live = await _scrolled(tester, dpr, glass: true, serves: false);
      BackdropUnderlay.debugEnabledOverride = true;
      final copied = await _scrolled(tester, dpr, glass: true, serves: true);
      expect(_band(tester).inFrameLayer, isNotNull);
      expect(_meanInBand(live, copied, dpr), lessThan(0.6));
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }
}
