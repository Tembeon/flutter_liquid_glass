@Tags(['macos_pixels'])
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_haze.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(50, 100, 200, 44);

// Black and white bars 20 pixels wide, moved by [shift], under a capsule of
// glass 44 high.
Widget _scene(LiquidGlassSettings settings, {double shift = 0}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _Bars(shift)),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: LiquidGlassLayer(
                  settings: settings,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: _glass,
                        child: LiquidGlass(
                          shape: const LiquidRoundedSuperellipse(
                            radius: 22,
                          ),
                          appearance: LiquidGlassAppearance.ios27Regular(
                            brightness: switch (settings.haze) {
                              LiquidGlassIos27RegularHaze(:final brightness) =>
                                brightness,
                              _ => Brightness.light,
                            },
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

class _Bars extends CustomPainter {
  const _Bars(this.shift);

  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    for (var x = shift - 40; x < size.width; x += 40) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 20, size.height),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(_Bars oldDelegate) => oldDelegate.shift != shift;
}

// The red of the row through the middle of the glass, over its face.
Future<List<int>> _row(
  WidgetTester tester,
  LiquidGlassSettings settings, {
  required bool inFrame,
  double shift = 0,
}) async {
  debugGlassPolicy = PlanPolicy(maxTargets: inFrame ? 64 : 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_scene(settings, shift: shift + 7));
  await tester.pumpWidget(_scene(settings, shift: shift));
  final glass = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet();
  expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  final width = image.width;
  image.dispose();
  final pixels = bytes.buffer.asUint8List();
  final y = _glass.center.dy.round();
  return [
    for (var x = 90; x < 210; x++) pixels[(y * width + x) * 4],
  ];
}

int _sharpest(List<int> row) {
  var step = 0;
  for (var i = 1; i < row.length; i++) {
    final d = (row[i] - row[i - 1]).abs();
    if (d > step) step = d;
  }
  return step;
}

int _least(List<int> row) => row.reduce((a, b) => a < b ? a : b);
int _most(List<int> row) => row.reduce((a, b) => a > b ? a : b);

void main() {
  test('the iOS 27 hazes follow the slider', () {
    const light = LiquidGlassHaze.ios27Regular(brightness: Brightness.light);
    final atClear = drawnHazeOf(light, 0)!;
    expect(atClear.sigma, 15.52);
    expect(atClear.lighten, closeTo(0.675, 1e-9));
    expect(atClear.darken, 0);
    expect(atClear.cover, 0);
    const dark = LiquidGlassHaze.ios27Regular(brightness: Brightness.dark);
    final atMiddle = drawnHazeOf(dark, 0.5)!;
    expect(atMiddle.lighten, 0);
    expect(atMiddle.darken, closeTo(0.9, 1e-9));
    expect(atMiddle.cover, 0.5);
    expect(drawnHazeOf(light, 1)!.lighten, closeTo(0.9, 1e-9));
    const clear = LiquidGlassHaze.ios27Clear();
    expect(drawnHazeOf(clear, 0.5), isNull);
    expect(drawnHazeOf(clear, 0.75)!.cover, 0.5);
    expect(drawnHazeOf(clear, 1)!.cover, 1);
    expect(drawnHazeOf(const LiquidGlassHaze.none(), 1), isNull);
  });

  test('a haze of numbers is drawn as given at every slider position', () {
    const haze = LiquidGlassHaze(lighten: 0.5);
    expect(drawnHazeOf(haze, 0), haze);
    expect(drawnHazeOf(haze, 1), haze);
    expect(const LiquidGlassHaze(), const LiquidGlassHaze.none());
    expect(drawnHazeOf(const LiquidGlassHaze(sigma: 0, cover: 1), 0), isNull);
  });

  test('the presets carry the haze of their scheme', () {
    expect(
      const LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
        sliderPosition: 0.5,
      ).haze,
      const LiquidGlassHaze.ios27Regular(brightness: Brightness.light),
    );
    expect(
      const LiquidGlassSettings.ios27Regular(brightness: Brightness.dark).haze,
      const LiquidGlassHaze.ios27Regular(brightness: Brightness.dark),
    );
    expect(const LiquidGlassSettings.ios27Clear().drawnHaze, isNull);
    expect(
      const LiquidGlassSettings(),
      const LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
    );
    const settings = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.dark,
      sliderPosition: 0.25,
    );
    expect(
      settings.copyWith(haze: const LiquidGlassHaze.none()).drawnHaze,
      isNull,
    );
  });

  test('a copy at another slider position takes its frost and haze along', () {
    for (final brightness in Brightness.values) {
      expect(
        LiquidGlassSettings.ios27Regular(
          brightness: brightness,
        ).copyWith(sliderPosition: 1),
        LiquidGlassSettings.ios27Regular(
          brightness: brightness,
          sliderPosition: 1,
        ),
      );
    }
    const clear = LiquidGlassSettings.ios27Clear();
    final tinted = clear.copyWith(sliderPosition: 1);
    expect(tinted, const LiquidGlassSettings.ios27Clear(sliderPosition: 1));
    expect(tinted.drawnHaze!.cover, 1);
    expect(tinted.frostBase, closeTo(16.4, 0.05));
    expect(clear.frostBase, 0);

    final unnamed = const LiquidGlassSettings().copyWith(sliderPosition: 0.5);
    expect(unnamed.frostBase, closeTo(6.9, 0.05));
    expect(unnamed.drawnHaze!.lighten, closeTo(0.9, 1e-9));
    expect(unnamed.drawnHaze!.cover, 0.5);
  });

  test('a frost goes from fitted to a sigma and back through copyWith', () {
    const fitted = LiquidGlassSettings();
    final fixed = fitted.copyWith(frost: const LiquidGlassFrost.sigma(3));
    expect(fixed.frostIsFitted, isFalse);
    expect(fixed == fitted, isFalse);
    expect(fixed.copyWith(sliderPosition: 1).frostBase, 3);
    expect(
      fixed.copyWith(frost: const LiquidGlassFrost.ios27Regular()),
      fitted,
    );
    expect(
      const LiquidGlassSettings(frost: LiquidGlassFrost.sigma(4.5)) == fitted,
      isFalse,
    );
  });

  test('under its haze a preset frosts by the blur iOS leaves the page', () {
    const regular = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.light,
    );
    for (final side in [20.0, 44.0, 64.0]) {
      expect(regular.hazedFrostSigmaAt(3, shapeShortSide: side), 0);
    }
    // 0.85 of the 7.76 points iOS blurs the middle of large glass by.
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(6.596, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 400),
      closeTo(6.596, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 112),
      closeTo(3.298, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3),
      regular.hazedFrostSigmaAt(3, shapeShortSide: 94),
    );
    expect(
      const LiquidGlassSettings.ios27Regular(
        brightness: Brightness.dark,
        sliderPosition: 1,
      ).hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(6.596, 1e-3),
    );
    expect(
      const LiquidGlassSettings.ios27Clear().hazedFrostSigmaAt(
        3,
        shapeShortSide: 160,
      ),
      0,
    );
    expect(
      const LiquidGlassSettings.ios27Clear(
        sliderPosition: 1,
      ).hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(1.237, 1e-3),
    );
    expect(
      regular
          .copyWith(frost: const LiquidGlassFrost.sigma(3))
          .hazedFrostSigmaAt(3, shapeShortSide: 44),
      3,
    );
  });

  test('a fill keeps its level in cells about a sigma wide', () {
    final strip = LevelStrip(
      const CopyLevels(fill: 15.5),
      pixels: 1,
      boxed: false,
      copy: const Size(300, 60),
      grid: Offset.zero,
    );
    // 8 / 3 + 28^2 / 3 is a sigma of 16.2: the stride is a whole number of
    // level 2's cells, which it averages.
    expect(strip.fillStride, 28);
    expect(strip.blurs, isFalse);
    expect((strip.first, strip.last), (2, 2));
    // Twelve cells across and a ring, then level 2's 76 and its ring.
    expect(strip.fillColumns, 14);
    expect(strip.columnOf(2), 15);
    expect(strip.across, 92);
    // Level 2's 16 rows and its ring, and a row for Impeller to lose.
    expect(strip.rows, 19);
    expect(strip.size, const Size(300, 79));
    expect(strip.passes, 2);
    // The cells lie on the screen: a copy elsewhere takes as many.
    final placed = LevelStrip(
      const CopyLevels(fill: 15.5),
      pixels: 1,
      boxed: false,
      copy: const Size(300, 60),
      grid: const Offset(10, 21),
    );
    expect(placed.size, strip.size);
    expect(placed.grid, const Offset(10, 21));
  });

  test('a blur takes the levels that bracket its least and most', () {
    final strip = LevelStrip(
      const CopyLevels(least: 2, most: 8),
      pixels: 1,
      boxed: false,
      copy: const Size(300, 60),
      grid: Offset.zero,
    );
    expect((strip.first, strip.last), (1, 4));
    expect(strip.blurs, isTrue);
    expect(strip.width, 304);
    expect(strip.height, 64);
    expect(strip.columnOf(1), 1);
    expect(strip.columnOf(2), 1 + 152 + 3);
    expect(strip.passes, 2);
    // Half the copy's pixels hold half the blur's.
    final coarse = LevelStrip(
      const CopyLevels(least: 2, most: 8),
      pixels: 0.5,
      boxed: true,
      copy: const Size(150, 30),
      grid: Offset.zero,
    );
    expect((coarse.first, coarse.last), (1, 3));
    // A blur no wider than the copy's pixels reads level 1 and the copy.
    final fine = LevelStrip(
      const CopyLevels(least: 0, most: 1),
      pixels: 1,
      boxed: false,
      copy: const Size(40, 40),
      grid: Offset.zero,
    );
    expect((fine.first, fine.last), (1, 2));
    expect(fine.passes, 1);
  });

  test('a read leaves the rows of its levels under its copy', () {
    ReadLayout read({required int share, Rect? clip}) => ReadLayout.resolve(
      devicePixelRatio: 1,
      askedShare: share,
      atScreen: false,
      reads: const Rect.fromLTWH(50, 100, 200, 60),
      screen: const Rect.fromLTWH(0, 0, 300, 400),
      clip: clip,
      holdsGlass: false,
      edgeFrost: 0,
      frostLeftOut: 0,
      filter: null,
      imageBlur: 0,
      levels: const CopyLevels(fill: 15.5),
    );
    // Sixty rows of the copy are fifteen of level 2, its ring and a spare
    // row.
    final whole = read(share: 1);
    expect(whole.footprint, const Rect.fromLTWH(50, 100, 200, 60));
    expect(whole.layer, const Rect.fromLTRB(50, 100, 250, 179));
    expect(whole.levelLayers, 2);
    // A smaller copy lies in its layer's corner, with rows to spare.
    final corner = read(share: 2);
    expect(corner.layer, corner.footprint);
    // A clip that cuts the top of the layer by less than Impeller cuts a
    // layer for leaves it whole, and the rows fit under it.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 110, 300, 400)).layer,
      const Rect.fromLTRB(50, 100, 250, 179),
    );
    // With the rows past the clip's bottom too, the layer would be cut to
    // the clip: it starts at the clip, and keeps the rows of what is left.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 113, 300, 160)).layer,
      const Rect.fromLTRB(50, 113, 250, 176),
    );
  });

  group('drawn into a copy', () {
    setUp(() {
      glassReadsCopies = true;
    });
    tearDown(() {
      glassReadsCopies = false;
      debugGlassPolicy = const PlanPolicy();
    });

    void sized(WidgetTester tester) {
      tester.view.physicalSize = const Size(300, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    for (final inFrame in [true, false]) {
      final where = inFrame ? 'in the frame' : 'in an image';

      testWidgets('light glass pales dark bars and keeps them sharp, $where', (
        tester,
      ) async {
        sized(tester);
        final plain = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
            frost: LiquidGlassFrost.sigma(0),
          ).copyWith(haze: const LiquidGlassHaze.none()),
          inFrame: inFrame,
        );
        final hazed = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
          inFrame: inFrame,
        );
        // Half of the page is white: the wide blur is mid grey, and dark
        // bars move 0.675 of the way to it.
        expect(_least(hazed) - _least(plain), greaterThan(40));
        expect(_most(hazed) - _most(plain), lessThan(4));
        expect(_sharpest(hazed), greaterThan(80));
      }, tags: 'composer');

      testWidgets('dark glass dims white bars and keeps them sharp, $where', (
        tester,
      ) async {
        sized(tester);
        final plain = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.dark,
            frost: LiquidGlassFrost.sigma(0),
          ).copyWith(haze: const LiquidGlassHaze.none()),
          inFrame: inFrame,
        );
        final hazed = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(brightness: Brightness.dark),
          inFrame: inFrame,
        );
        expect(_most(plain) - _most(hazed), greaterThan(40));
        expect(_least(hazed) - _least(plain), lessThan(4));
        expect(_sharpest(hazed), greaterThan(50));
      }, tags: 'composer');

      testWidgets(
        'the slider at 1 covers the page with the wide blur, $where',
        (
          tester,
        ) async {
          sized(tester);
          final covered = await _row(
            tester,
            const LiquidGlassSettings.ios27Regular(
              brightness: Brightness.light,
              sliderPosition: 1,
            ),
            inFrame: inFrame,
          );
          expect(_most(covered) - _least(covered), lessThan(24));
        },
        tags: 'composer',
      );
    }

    // Every pixel of the copy is weighed, so a page that scrolls under the
    // glass takes its wide blur with it: no line is caught by one frame's
    // samples and missed by the next's.
    testWidgets('a page moving under the glass moves its wide blur smoothly', (
      tester,
    ) async {
      sized(tester);
      const settings = LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
        sliderPosition: 1,
      );
      List<int>? last;
      var step = 0;
      for (var shift = 0.0; shift <= 40; shift++) {
        final row = await _row(tester, settings, inFrame: true, shift: shift);
        if (last != null) {
          for (var i = 0; i < row.length; i++) {
            final d = (row[i] - last[i]).abs();
            if (d > step) step = d;
          }
        }
        last = row;
      }
      // A Gaussian this wide leaves the bars 17 levels from dark to light
      // over their 40 pixels, under 2 a pixel.
      expect(step, lessThanOrEqualTo(4));
    }, tags: 'composer');

    testWidgets('a copy in the frame and one in an image draw alike', (
      tester,
    ) async {
      sized(tester);
      const settings = LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
        sliderPosition: 0.25,
      );
      final frame = await _row(tester, settings, inFrame: true);
      final image = await _row(tester, settings, inFrame: false);
      var largest = 0;
      for (var i = 0; i < frame.length; i++) {
        final d = (frame[i] - image[i]).abs();
        if (d > largest) largest = d;
      }
      expect(largest, lessThanOrEqualTo(6));
    }, tags: 'composer');
  });
}
