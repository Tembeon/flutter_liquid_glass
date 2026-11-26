@Tags(['macos_pixels'])
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(50, 100, 200, 44);

// Black and white bars 20 pixels wide, moved by [shift], under a capsule of
// glass 44 high.
Widget _scene(
  LiquidGlassSettings settings, {
  required Brightness brightness,
  double shift = 0,
}) => Directionality(
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
                        brightness: brightness,
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
  Brightness brightness = Brightness.light,
  double shift = 0,
}) async {
  debugGlassPolicy = PlanPolicy(maxTargets: inFrame ? 64 : 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    _scene(settings, brightness: brightness, shift: shift + 7),
  );
  await tester.pumpWidget(
    _scene(settings, brightness: brightness, shift: shift),
  );
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
  test('a fill keeps its level in cells about a sigma wide', () {
    final strip = LevelStrip(
      const CopyLevels(fill: 15.5),
      devicePixelRatio: 1,
      share: 1,
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
      devicePixelRatio: 1,
      share: 1,
      copy: const Size(300, 60),
      grid: const Offset(10, 21),
    );
    expect(placed.size, strip.size);
    expect(placed.grid, const Offset(10, 21));
  });

  test('a blur takes the levels that bracket its least and most', () {
    final strip = LevelStrip(
      const CopyLevels(least: 2, most: 8),
      devicePixelRatio: 1,
      share: 1,
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
      devicePixelRatio: 1,
      share: 2,
      copy: const Size(150, 30),
      grid: Offset.zero,
    );
    expect((coarse.first, coarse.last), (1, 3));
    // A blur no wider than the copy's pixels reads level 1 and the copy.
    final fine = LevelStrip(
      const CopyLevels(least: 0, most: 1),
      devicePixelRatio: 1,
      share: 1,
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
      nestsGlass: false,
      shaderFrost: 0,
      frostLeftOut: 0,
      filter: null,
      imageBlur: null,
      levels: const CopyLevels(fill: 15.5),
    );
    Rect withRows(Rect copy) => Rect.fromLTRB(
      copy.left,
      copy.top,
      copy.right,
      copy.bottom +
          LevelStrip(
            const CopyLevels(fill: 15.5),
            devicePixelRatio: 1,
            share: 1,
            copy: copy.size,
            grid: copy.topLeft,
          ).rows,
    );
    final whole = read(share: 1);
    expect(whole.footprint, const Rect.fromLTWH(50, 100, 200, 60));
    expect(whole.layer, withRows(whole.footprint.rect));
    expect(CornerPlace.inFrame(whole).passes, 2);
    // A smaller copy lies in its layer's corner, with rows to spare.
    final corner = read(share: 2);
    expect(corner.layer, corner.footprint);
    // A clip that cuts the top of the layer by less than Impeller cuts a
    // layer for leaves it whole, and the rows fit under it.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 110, 300, 400)).layer,
      withRows(whole.footprint.rect),
    );
    // With the rows past the clip's bottom too, the layer would be cut to
    // the clip: it starts at the clip, and keeps the rows of what is left.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 113, 300, 160)).layer,
      withRows(const Rect.fromLTRB(50, 113, 250, 160)),
    );
  });

  group('drawn into a copy', () {
    setUp(() {
      glassReadsCopies = true;
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
          const LiquidGlassSettings.ios27Regular(blur: 0),
          inFrame: inFrame,
        );
        final hazed = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(),
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
          const LiquidGlassSettings.ios27Regular(blur: 0),
          inFrame: inFrame,
          brightness: Brightness.dark,
        );
        final hazed = await _row(
          tester,
          const LiquidGlassSettings.ios27Regular(),
          inFrame: inFrame,
          brightness: Brightness.dark,
        );
        // Dark glass's face passes on less of the backdrop's range than
        // light glass's, so the white bars drop less far than the dark bars
        // of light glass rise.
        expect(_most(plain) - _most(hazed), greaterThan(15));
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
        sliderPosition: 0.25,
      );
      final frame = await _row(tester, settings, inFrame: true);
      final image = await _row(tester, settings, inFrame: false);
      expect(largestDifference(frame, image), lessThanOrEqualTo(6));
    }, tags: 'composer');
  });
}
