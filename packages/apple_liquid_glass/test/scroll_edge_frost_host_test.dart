// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the band
// frosts its copy through a runtime effect, which only Impeller draws.
//
// The band's copy is the renderer's: the test turns copies on under
// flutter test and asks whether one serves.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';

const _key = ValueKey('page');

Widget _page(ScrollController controller, double dpr, {required bool hard}) =>
    MediaQuery(
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
                            child: const SizedBox(
                              width: 3,
                              height: 30,
                              child: ColoredBox(color: Color(0xFFFFFFFF)),
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
  required bool hard,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_page(controller, dpr, hard: hard));
  await tester.pump();
  controller.jumpTo(200);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_band(tester).serves, isTrue);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b, {int? width, int? columns}) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    if (width != null && (i ~/ 4) % width >= columns!) continue;
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  setUp(() {
    MotionClock.debugReset();
    BackdropUnderlay.debugEnabledOverride = true;
  });
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    LiquidGlassBackdropFrost.debugShaderFrost = true;
  });

  for (final (dpr, hard, near) in [
    (2.625, true, 16),
    (2.625, false, 9),
    (3.0, true, 12),
    (3.0, false, 9),
  ]) {
    testWidgets('the ${hard ? 'hard' : 'soft'} band at $dpr frosts a copy '
        'at half size near the copy it filters', (tester) async {
      tester.view.physicalSize = Size(300 * dpr, 400 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);

      LiquidGlassBackdropFrost.debugShaderFrost = false;
      final filtered = await _scrolled(tester, dpr, hard: hard);
      final full = _band(tester).debugUnderlay.debugImage!.width;

      LiquidGlassBackdropFrost.debugShaderFrost = true;
      final frosted = await _scrolled(tester, dpr, hard: hard);
      // The copy spans the screen's width, at half size.
      expect(_band(tester).debugUnderlay.debugImage!.width, (full / 2).round());
      // NEAR, see LiquidGlassBackdropFrost.debugShaderFrost.
      expect(_difference(filtered, frosted), lessThanOrEqualTo(near));
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }

  // The view ends inside its last column of pixels at 2.625, which only the
  // frost drawn in the frame covers in part: a screen ends on a pixel. On
  // the row the band's edge splits, the frost drawn in the frame covers
  // each pixel by its share inside the band (NEAR, see
  // recordFrostedInFrame).
  for (final (dpr, near) in [(2.625, 29), (3.0, 1)]) {
    testWidgets('the band at $dpr frosts a copy drawn in the frame as it '
        'frosts its image', (tester) async {
      tester.view.physicalSize = Size(300 * dpr, 400 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      addTearDown(() => BackdropUnderlay.debugInFrame = false);

      final image = await _scrolled(tester, dpr, hard: true);
      expect(_band(tester).inFrameLayer, isNull);

      BackdropUnderlay.debugInFrame = true;
      final drawn = BackdropUnderlay.debugImagesDrawn;
      final inFrame = await _scrolled(tester, dpr, hard: true);
      expect(_band(tester).inFrameLayer, isNotNull);
      expect(BackdropUnderlay.debugImagesDrawn, drawn);
      expect(
        _difference(
          image,
          inFrame,
          width: (300 * dpr).ceil(),
          columns: (300 * dpr).floor(),
        ),
        lessThanOrEqualTo(near),
      );
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }
}
