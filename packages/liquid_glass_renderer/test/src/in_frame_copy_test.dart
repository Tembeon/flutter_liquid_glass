// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('screen');

// Glass at [top] over a gradient and text, and a second glass below it
// whose band holds the lower part of the first; [clip] cuts the first
// glass, in the screen's coordinates.
Widget _scene({
  double shift = 0,
  double top = 200,
  double frost = 0,
  bool second = true,
  double secondFrost = 0,
  Rect? clip,
}) {
  Widget glass(Rect rect, {double frost = 0}) => LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularLight().copyWith(frost: frost),
    child: Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: const LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: 28),
            child: SizedBox.expand(),
          ),
        ),
      ],
    ),
  );

  final first = glass(Rect.fromLTWH(30, top, 200, 90), frost: frost);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
                    begin: Alignment(-1 + shift, -1),
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          for (var row = 0; row < 22; row++)
            Positioned(
              left: 12,
              top: 20.0 + row * 28,
              child: const Text(
                'WWWW iiii MMMM',
                style: TextStyle(fontSize: 18, color: Color(0xFFFFFFFF)),
              ),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: clip == null
                  ? first
                  : ClipRect(clipper: _Clip(clip), child: first),
            ),
          ),
          if (second)
            Positioned.fill(
              child: RepaintBoundary(
                child: glass(
                  const Rect.fromLTWH(30, 260, 200, 60),
                  frost: secondFrost,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Clip extends CustomClipper<Rect> {
  const _Clip(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_Clip oldClipper) => oldClipper.rect != rect;
}

Future<Uint8List> _pixels(WidgetTester tester, double pixelRatio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: pixelRatio),
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

// The scene drawn over copies, once what lies under the glass changed.
Future<Uint8List> _drawn(
  WidgetTester tester, {
  required bool inFrame,
  required double pixelRatio,
  double frost = 0,
  bool second = true,
  double secondFrost = 0,
  Rect? clip,
}) async {
  BackdropUnderlay.debugInFrame = inFrame;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    _scene(
      shift: 0.3,
      frost: frost,
      second: second,
      secondFrost: secondFrost,
      clip: clip,
    ),
  );
  final drawn = BackdropUnderlay.debugImagesDrawn;
  await tester.pumpWidget(
    _scene(
      frost: frost,
      second: second,
      secondFrost: secondFrost,
      clip: clip,
    ),
  );
  final glass = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet();
  expect(glass.every((g) => g.debugDrewOverUnderlay), isTrue);
  if (inFrame && secondFrost == 0) {
    expect(BackdropUnderlay.debugImagesDrawn, drawn);
  }
  return _pixels(tester, pixelRatio);
}

void main() {
  final inFrame = BackdropUnderlay.debugInFrame;
  setUp(() {
    BackdropUnderlay.debugEnabledOverride = true;
  });
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    BackdropUnderlay.debugInFrame = inFrame;
  });

  for (final pixelRatio in [1.0, 2.0]) {
    void sized(WidgetTester tester, {double height = 360}) {
      tester.view.physicalSize = Size(260, height) * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
    }

    testWidgets('glass over a copy drawn in the frame draws what it draws '
        'over its image (dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);

    // Both copies draw the lower glass as it lies inside the upper glass's
    // band, where it reads its own edge: an image folds it in as its
    // filter, the frame draws it again inside the band.
    testWidgets('a copy over glass drawn in the frame draws that glass again '
        'inside its band (dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(3));
    }, skip: skipProperGlassTests);

    testWidgets('frosted glass reads its copy from the corner of its layer '
        '(dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        frost: 6,
        second: false,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        frost: 6,
        second: false,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);

    // The grown layer lands on the copy's pixel grid a pixel off the image's
    // edge at dpr 2, which moves a bilinear read by up to 2 levels.
    testWidgets('glass a clip cuts reads past the clip from a layer grown '
        'into it (dpr $pixelRatio)', (tester) async {
      sized(tester, height: 640);
      const clip = Rect.fromLTRB(0, 230, 260, 640);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(2));
    }, skip: skipProperGlassTests);

    // NEAR: a layer the clip cuts holds nothing past it, so the 30 px of
    // glass left above the clip read their copy mirrored at the clip, up to
    // 163 levels off what lies under the glass's hidden part.
    testWidgets('glass a clip cuts with no room to grow reads its copy '
        'mirrored at the clip (dpr $pixelRatio)', (tester) async {
      sized(tester);
      const clip = Rect.fromLTRB(0, 0, 260, 230);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(163));
    }, skip: skipProperGlassTests);
  }

  // The frost takes a copy at a quarter of the screen's pixels, which lies
  // in the corner of its layer; a layer grown past the clip leaves that
  // corner outside it and the glass reads nothing, 153 levels off.
  testWidgets('frosted glass over a smaller copy a clip cuts reads the copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const clip = Rect.fromLTRB(0, 230, 260, 640);
    final image = await _drawn(
      tester,
      inFrame: false,
      pixelRatio: 3,
      frost: 4.5,
      second: false,
      clip: clip,
    );
    final inFrame = await _drawn(
      tester,
      inFrame: true,
      pixelRatio: 3,
      frost: 4.5,
      second: false,
      clip: clip,
    );
    expect(_difference(image, inFrame), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  // The lower glass's frosted copy is an image at a fraction of the screen's
  // pixels, and the upper glass is drawn in the frame inside it as a filter,
  // whose fragments are the image's pixels.
  for (final pixelRatio in [2.0, 3.0]) {
    testWidgets("an image copy at a fraction of the screen's pixels draws "
        'glass drawn in the frame where it lies (dpr $pixelRatio)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 360) * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        secondFrost: 12,
      );
      final images = BackdropUnderlay.debugImagesDrawn;
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        secondFrost: 12,
      );
      expect(BackdropUnderlay.debugImagesDrawn, greaterThan(images));
      // At the image's own pixels the upper glass lands twice as far from
      // its layer's corner, over 70 levels off.
      expect(_difference(image, inFrame), lessThanOrEqualTo(5));
    }, skip: skipProperGlassTests);
  }
}
