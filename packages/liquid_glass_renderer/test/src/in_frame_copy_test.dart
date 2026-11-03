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
// whose band holds the lower part of the first; [clip] cuts the first glass
// to its top 30 px.
Widget _scene({
  double shift = 0,
  double top = 200,
  double frost = 0,
  bool second = true,
  bool clip = false,
}) {
  Widget glass(Rect rect) => LiquidGlassLayer(
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

  final first = glass(Rect.fromLTWH(30, top, 200, 90));
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
          for (var row = 0; row < 12; row++)
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
              child: clip
                  ? ClipRect(
                      clipper: _TopOf(top + 30),
                      child: first,
                    )
                  : first,
            ),
          ),
          if (second)
            Positioned.fill(
              child: RepaintBoundary(
                child: glass(const Rect.fromLTWH(30, 260, 200, 60)),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TopOf extends CustomClipper<Rect> {
  const _TopOf(this.bottom);

  final double bottom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, bottom);

  @override
  bool shouldReclip(_TopOf oldClipper) => oldClipper.bottom != bottom;
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
  bool clip = false,
  int images = 0,
}) async {
  BackdropUnderlay.debugInFrame = inFrame;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    _scene(shift: 0.3, frost: frost, second: second, clip: clip),
  );
  final drawn = BackdropUnderlay.debugImagesDrawn;
  await tester.pumpWidget(
    _scene(frost: frost, second: second, clip: clip),
  );
  final glass = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet();
  expect(glass.every((g) => g.debugDrewOverUnderlay), isTrue);
  if (inFrame) expect(BackdropUnderlay.debugImagesDrawn, drawn + images);
  return _pixels(tester, pixelRatio);
}

void main() {
  setUp(() {
    BackdropUnderlay.debugEnabledOverride = true;
  });
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    BackdropUnderlay.debugInFrame = false;
  });

  for (final pixelRatio in [1.0, 2.0]) {
    void sized(WidgetTester tester) {
      tester.view.physicalSize = Size(260, 360) * pixelRatio;
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

    testWidgets('glass under a clip that cuts most of it reads past the '
        'clip from an image (dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        clip: true,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        clip: true,
        images: 1,
      );
      // The images draw both copies as one island, which reads what lies
      // past each band: the glass below reads 2 levels apart without it.
      expect(_difference(image, inFrame), lessThanOrEqualTo(2));
    }, skip: skipProperGlassTests);
  }
}
