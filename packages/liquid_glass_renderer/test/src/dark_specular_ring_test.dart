@Tags(['macos_pixels'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('ring');
const _dpr = 3.0;
const _view = Size(140, 70);
const _glass = Rect.fromLTWH(15, 13, 110, 44);

// A lifted lens over [backdrop], which iOS rims with its dark specular.
Future<Uint8List> _drawn(
  WidgetTester tester,
  Widget backdrop, {
  double blur = 0,
  bool copies = false,
  bool fake = false,
  bool resting = false,
  LiquidGlassLens lens = LiquidGlassLens.none,
  Brightness brightness = Brightness.light,
}) async {
  glassReadsCopies = copies;
  addTearDown(() => glassReadsCopies = false);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            Positioned.fill(child: backdrop),
            Positioned.fromRect(
              rect: _glass,
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings(blur: blur, lens: lens),
                fake: fake,
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(radius: _glass.height / 2),
                  appearance: LiquidGlassAppearance(
                    colorModel: resting
                        ? LiquidGlassColorModel.ios27Regular(
                            brightness: brightness,
                          )
                        : LiquidGlassColorModel.ios27Lens(
                            brightness: brightness,
                          ),
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
  return boundaryPixels(tester, find.byKey(_key), pixelRatio: _dpr);
}

Widget _grey(int value) =>
    ColoredBox(color: Color.fromARGB(255, value, value, value));

// The darkest value of [channel] on the ring left of the glass's middle row,
// from 3 points outside its end to 6 inside it.
int _endRing(Uint8List pixels, {int channel = 0, double inside = 6}) {
  final width = (_view.width * _dpr).round();
  final y = (_glass.center.dy * _dpr).round();
  var least = 255;
  for (
    var x = ((_glass.left - 3) * _dpr).round();
    x <= ((_glass.left + inside) * _dpr).round();
    x++
  ) {
    final value = pixels[(y * width + x) * 4 + channel];
    if (value < least) least = value;
  }
  return least;
}

// The darkest red on the ring above the glass at column [x] (logical), from
// 3 points above its top to [inside] points below it.
int _topRing(Uint8List pixels, double x, {double inside = 6}) {
  final width = (_view.width * _dpr).round();
  final column = (x * _dpr).round();
  var least = 255;
  for (
    var y = ((_glass.top - 3) * _dpr).round();
    y <= ((_glass.top + inside) * _dpr).round();
    y++
  ) {
    final value = pixels[(y * width + column) * 4];
    if (value < least) least = value;
  }
  return least;
}

// A dark page with a light band from 5 points outside the glass's left end
// to 3 inside it.
Widget _endBand() => Stack(
  children: [
    const Positioned.fill(
      child: ColoredBox(color: Color.fromARGB(255, 28, 28, 28)),
    ),
    Positioned(
      left: _glass.left - 5,
      width: 8,
      top: 0,
      bottom: 0,
      child: const ColoredBox(color: Color.fromARGB(255, 242, 242, 242)),
    ),
  ],
);

Widget _step() => const Row(
  children: [
    Expanded(
      child: ColoredBox(
        color: Color.fromARGB(255, 28, 28, 28),
        child: SizedBox.expand(),
      ),
    ),
    Expanded(
      child: ColoredBox(
        color: Color.fromARGB(255, 242, 242, 242),
        child: SizedBox.expand(),
      ),
    ),
  ],
);

// The darkening of the ring over a grey of [value]: one less what it leaves.
double _darkening(int value, int ring) => 1 - ring / value;

void main() {
  for (final resting in [false, true]) {
    testWidgets('the dark specular darkens what lies under it as iOS does: '
        'three times as much over black as over white '
        '(${resting ? 'resting glass' : 'a lifted lens'})', (tester) async {
      tester.view
        ..physicalSize = _view * _dpr
        ..devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      Future<int> ring(int value) async =>
          _endRing(await _drawn(tester, _grey(value), resting: resting));
      final light = _darkening(242, await ring(242));
      for (final value in [28, 128]) {
        // iOS darkens by `bias K (3 - 2 B)`: against the light grey, the
        // ratio of `3 - 2 B`. A ring of black at one alpha keeps it at 1.
        expect(
          _darkening(value, await ring(value)) / light,
          closeTo((3 - 2 * value / 255) / (3 - 2 * 242 / 255), 0.1),
          reason: 'over a grey of $value',
        );
      }
    }, skip: skipProperGlassTests);
  }

  testWidgets('over a colour the dark specular darkens by its brightest '
      'channel', (tester) async {
    tester.view
      ..physicalSize = _view * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    final blue = await _drawn(
      tester,
      const ColoredBox(color: Color(0xFF0000FF)),
    );
    final white = await _drawn(tester, _grey(255));
    expect(_endRing(blue), 0);
    expect(_endRing(blue, channel: 1), 0);
    expect(
      _endRing(blue, channel: 2),
      closeTo(_endRing(white, channel: 2), 1),
    );
  }, skip: skipProperGlassTests);

  for (final copies in [false, true]) {
    final path = copies ? 'a copy' : 'the backdrop';
    testWidgets(
      'over a step the ring darkens each side by what lies there, '
      'reading $path',
      (tester) async {
        tester.view
          ..physicalSize = _view * _dpr
          ..devicePixelRatio = _dpr;
        addTearDown(tester.view.reset);
        final sharp = await _drawn(tester, _step(), copies: copies);
        final dark = await _drawn(tester, _grey(28), copies: copies);
        final light = await _drawn(tester, _grey(242), copies: copies);
        // The step lies at 70, under the glass's top edge.
        expect(_topRing(sharp, 40), closeTo(_topRing(dark, 40), 1));
        expect(_topRing(sharp, 69), closeTo(_topRing(dark, 69), 1));
        expect(_topRing(sharp, 71), closeTo(_topRing(light, 71), 1));
        expect(_topRing(sharp, 100), closeTo(_topRing(light, 100), 1));
        // A lens shrinks what it shows, its edge reading from farther out,
        // but never what its ring darkens outside it: over a light band around
        // its end with the dark page past it, the ring stays the ring over
        // the band.
        const lens = LiquidGlassLens(shrink: 0.5);
        expect(
          _endRing(
            await _drawn(tester, _endBand(), copies: copies, lens: lens),
            inside: -0.5,
          ),
          closeTo(
            _endRing(
              await _drawn(tester, _endBand(), copies: copies),
              inside: -0.5,
            ),
            1,
          ),
        );
        // Glass that blurs reads what lies under its ring blurred as its face
        // is, on either path: within its blur of the step the ring follows the
        // blurred step, past it what lies there.
        var share = 1;
        GlassComposer.debugOnPlan = (_, plan) {
          if (plan.reads.isNotEmpty) share = plan.reads.single.layout.share;
        };
        addTearDown(() => GlassComposer.debugOnPlan = null);
        final blurred = await _drawn(tester, _step(), blur: 8, copies: copies);
        GlassComposer.debugOnPlan = null;
        if (copies) expect(share, greaterThan(1));
        expect(
          _topRing(blurred, 71),
          inExclusiveRange(_topRing(sharp, 69), 190),
        );
        expect(_topRing(blurred, 100), closeTo(_topRing(light, 100), 1));
      },
      skip: skipProperGlassTests,
      tags: copies ? ['composer'] : null,
    );
  }

  // Fake glass reads nothing under its ring and takes the page of its
  // scheme: black under dark glass, white under light glass. Over such a
  // page its ring lies near real glass's (7 levels off over the light page,
  // 242 and not white); taken for white under dark glass, it lay 13 lighter.
  for (final (brightness, page) in [
    (Brightness.dark, 28),
    (Brightness.light, 242),
  ]) {
    testWidgets('fake glass darkens its ring over the page of its scheme as '
        'real glass does ($brightness)', (tester) async {
      tester.view
        ..physicalSize = _view * _dpr
        ..devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      final real = _endRing(
        await _drawn(tester, _grey(page), brightness: brightness),
      );
      final fake = _endRing(
        await _drawn(tester, _grey(page), brightness: brightness, fake: true),
      );
      expect(fake, closeTo(real, 7));
    });
  }

  testWidgets('over nothing the dark specular draws no ring', (tester) async {
    tester.view
      ..physicalSize = _view * _dpr
      ..devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    final pixels = await _drawn(tester, const SizedBox.expand());
    final width = (_view.width * _dpr).round();
    final y = (_glass.center.dy * _dpr).round();
    final ring = [
      for (
        var x = ((_glass.left - 3) * _dpr).round();
        x < (_glass.left * _dpr).round() - 1;
        x++
      )
        pixels[(y * width + x) * 4 + 3],
    ];
    expect(ring, everyElement(0));
  }, skip: skipProperGlassTests);
}
