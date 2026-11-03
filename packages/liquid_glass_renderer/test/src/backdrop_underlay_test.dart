import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('screen');

// Two glass layers, the first in its own boundary so that an image can be
// taken of it alone.
const _shadow = [
  BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
];

Widget _pairScene({
  double shift = 0,
  double top = 40,
  double frost = 0,
  bool shadowed = false,
  bool second = true,
}) => Directionality(
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
        for (final (key, rect) in [
          (_first, Rect.fromLTWH(30, top, 200, 90)),
          if (second) (null, const Rect.fromLTWH(30, 260, 200, 60)),
        ])
          Positioned.fill(
            child: RepaintBoundary(
              key: key,
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                  frost: frost,
                ),
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: LiquidGlass(
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 28,
                        ),
                        shadows: shadowed ? _shadow : const [],
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

const _first = ValueKey('first');

final _leader = LayerLink();

// [child] placed under the leader, where it lies with the leader at its
// first place, when [follows].
Widget _following(bool follows, Widget child) => follows
    ? CompositedTransformFollower(
        link: _leader,
        offset: const Offset(-20, -30),
        child: child,
      )
    : child;

Widget _scene({
  double shift = 0,
  double dot = 0,
  bool texture = false,
  bool follower = false,
  double leader = 20,
  bool glassFollows = false,
  double opacity = 1,
  bool pair = false,
  bool mask = false,
  bool clipped = false,
  double scaleX = 1,
  double scaleY = 1,
  double frost = 0,
}) => Directionality(
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
                  colors: const [
                    Color(0xFF1E3A8A),
                    Color(0xFFF59E0B),
                    Color(0xFF10B981),
                  ],
                  begin: Alignment(-1 + shift, -1),
                  end: Alignment.bottomRight,
                  tileMode: TileMode.mirror,
                ),
              ),
              child: const Center(
                child: Text(
                  'Page under the glass',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
                ),
              ),
            ),
          ),
        ),
        if (mask)
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0x00000000), Color(0xFF000000)],
              ).createShader(bounds),
              child: const RepaintBoundary(
                child: ColoredBox(color: Color(0x40FFFFFF)),
              ),
            ),
          ),
        // A list scrolled under a clip whose edge runs through the glass's
        // band: the item above the edge, clipped, is an empty rect lying
        // across that band, beside one the clip shows.
        if (clipped)
          Positioned(
            left: 0,
            right: 0,
            top: 100,
            height: 100,
            child: ClipRect(
              child: Transform.translate(
                offset: const Offset(0, -60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (color, height) in const [
                      (Color(0xFFEF4444), 60.0),
                      (Color(0xFF22C55E), 40.0),
                    ])
                      RepaintBoundary(
                        child: SizedBox(
                          height: height,
                          width: double.infinity,
                          child: ColoredBox(color: color),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (follower) ...[
          Positioned(
            left: leader,
            top: 30,
            child: CompositedTransformTarget(
              link: _leader,
              child: const SizedBox.square(dimension: 4),
            ),
          ),
          CompositedTransformFollower(
            link: _leader,
            offset: const Offset(20, 20),
            child: const SizedBox(
              width: 60,
              height: 30,
              child: ColoredBox(color: Color(0xFFDB2777)),
            ),
          ),
        ],
        if (texture)
          const Positioned(
            left: 40,
            top: 50,
            width: 20,
            height: 20,
            child: Texture(textureId: 1),
          ),
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: Transform(
              alignment: const Alignment(-0.3, -0.5),
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: _following(
                glassFollows,
                LiquidGlassLayer(
                  settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                    frost: frost,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: const Rect.fromLTWH(30, 40, 200, 90),
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 28),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (pair)
          Positioned.fill(
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: 0,
              ),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: const Rect.fromLTWH(30, 260, 200, 60),
                    child: const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 28),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Something that moves far from the glass, in its own boundary.
        Positioned(
          left: 10 + dot,
          bottom: 6,
          child: const RepaintBoundary(
            child: SizedBox.square(
              dimension: 6,
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ],
    ),
  ),
);

RenderLiquidGlassLayer _glass(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

Iterable<BackdropFilterLayer> _liveFilters(WidgetTester tester) => tester.layers
    .whereType<BackdropFilterLayer>()
    .where((layer) => layer is! OpacitySeedLayer || layer.seeded);

Future<Uint8List> _pixels(WidgetTester tester, {double pixelRatio = 1}) async {
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

Future<void> _settle(WidgetTester tester, {double dot = 0}) async {
  for (var i = 0; i < 4; i++) {
    await tester.pumpWidget(_scene(dot: dot + i));
  }
}

void main() {
  setUp(() {
    BackdropUnderlay.debugEnabledOverride = true;
  });
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
  });

  testWidgets('glass over a copy drawn in the very frame what lies under '
      'it changed draws what reading it draws, with no backdrop filter in '
      'the frame', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_scene());
    await tester.pump();
    final reading = await _pixels(tester);
    expect(_liveFilters(tester), isNotEmpty);

    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    await tester.pumpWidget(_scene());
    expect(_glass(tester).debugUnderlay.debugCaptures, 2);
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass reads its backdrop over a layer the copy cannot draw', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(texture: true));
    expect(_glass(tester).debugDrewOverUnderlay, isFalse);
    expect(_glass(tester).debugUnderlay.debugMiss, 'blocked by TextureLayer');
    expect(_liveFilters(tester), isNotEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('glass over what a follower paints draws over its copy, as '
      'reading the backdrop draws it', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_scene(follower: true));
    await tester.pump();
    final reading = await _pixels(tester);

    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(follower: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass over a follower draws over a copy taken where the '
      'leader is in that frame', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_scene(follower: true, leader: 70));
    await tester.pump();
    final reading = await _pixels(tester);

    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(follower: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true));
    final captures = _glass(tester).debugUnderlay.debugCaptures;
    // One frame: the leader moves and the copy is taken under the follower
    // where it lands.
    await tester.pumpWidget(_scene(follower: true, leader: 70));
    expect(_glass(tester).debugUnderlay.debugCaptures, captures + 1);
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass under a follower draws over a copy taken where it '
      'lands in the frame its leader moves', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(
      _scene(follower: true, glassFollows: true, leader: 40),
    );
    await tester.pump();
    final reading = await _pixels(tester);

    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(follower: true, glassFollows: true, dot: 1));
    await tester.pumpWidget(_scene(follower: true, glassFollows: true));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    await tester.pumpWidget(
      _scene(follower: true, glassFollows: true, leader: 40),
    );
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(1));
  }, skip: skipProperGlassTests);

  testWidgets('glass in a fading group draws over its copy and leaves the '
      'group unseeded', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(opacity: 0.6));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);

    await tester.pumpWidget(_scene(opacity: 0.6, texture: true));
    expect(_glass(tester).debugDrewOverUnderlay, isFalse);
    expect(
      tester.layers.whereType<OpacitySeedLayer>().single.seeded,
      isTrue,
    );
  }, skip: skipProperGlassTests);

  testWidgets('motion away from the glass keeps the copy', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene());
    await _settle(tester);
    final captures = _glass(tester).debugUnderlay.debugCaptures;
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(_scene(dot: 20.0 + i));
      expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    }
    expect(_glass(tester).debugUnderlay.debugCaptures, captures);
  }, skip: skipProperGlassTests);

  testWidgets('glass draws over its copy above a shader mask', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(mask: true));
    await tester.pumpWidget(_scene(mask: true, shift: 0.3));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass stretched along the axes draws over its copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(frost: 6, scaleX: 1.2, scaleY: 0.8));
    await tester.pumpWidget(
      _scene(frost: 6, scaleX: 1.2, scaleY: 0.8, shift: 0.3),
    );
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('mirrored glass reads its backdrop', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(frost: 6, scaleX: -1));
    await tester.pumpWidget(_scene(frost: 6, scaleX: -1, shift: 0.3));
    expect(_glass(tester).debugDrewOverUnderlay, isFalse);
    expect(_liveFilters(tester), isNotEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('content clipped away at the edge of the band is left out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(clipped: true));
    await tester.pumpWidget(_scene(clipped: true, shift: 0.3));
    expect(_glass(tester).debugDrewOverUnderlay, isTrue);
    expect(_liveFilters(tester), isEmpty);
  }, skip: skipProperGlassTests);

  testWidgets('an image taken between frames leaves the next frame to copy '
      'what it changed', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_pairScene());
    await tester.pumpWidget(_pairScene());
    RenderLiquidGlassLayer second() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .last;
    final captures = second().debugUnderlay.debugCaptures;
    tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_first))
        .toImageSync()
        .dispose();
    // The first glass leaves the screen and copies nothing: the second is
    // the first to copy in the frame.
    await tester.pumpWidget(_pairScene(shift: 0.3, top: -400));
    expect(second().debugDrewOverUnderlay, isTrue);
    expect(second().debugUnderlay.debugCaptures, captures + 1);
  }, skip: skipProperGlassTests);

  testWidgets('copies redrawn in one frame share one image', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(pair: true, shift: 0.3));
    final drawn = BackdropUnderlay.debugImagesDrawn;
    await tester.pumpWidget(_scene(pair: true));
    expect(BackdropUnderlay.debugImagesDrawn, drawn + 1);
    final glass = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(glass, hasLength(2));
    expect(glass.every((g) => g.debugDrewOverUnderlay), isTrue);
    expect(_liveFilters(tester), isEmpty);
    final [a, b] = [for (final g in glass) g.debugUnderlay.debugImage!];
    expect(a.isCloneOf(b), isTrue);
  }, skip: skipProperGlassTests);

  for (final (top, folds) in [(160.0, 0), (200.0, 1)]) {
    testWidgets('glass beside glass and glass over glass copy in the same '
        'image, the copy over glass drawing that glass in (top $top)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_pairScene(shift: 0.3, top: top));
      final drawn = BackdropUnderlay.debugImagesDrawn;
      final folded = BackdropUnderlay.debugFolds;
      await tester.pumpWidget(_pairScene(top: top));
      expect(BackdropUnderlay.debugImagesDrawn, drawn + 1);
      expect(BackdropUnderlay.debugFolds, folded + folds);
      final glass = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet();
      expect(glass, hasLength(2));
      expect(glass.every((g) => g.debugDrewOverUnderlay), isTrue);
    }, skip: skipProperGlassTests);
  }

  testWidgets('a copy over glass whose copy is drawn in the same image '
      'holds what reading the backdrop draws there', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first: the lower glass
    // alone, as the upper glass's copy should hold it.
    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_pairScene(top: 200, second: false));
    final reading = await _pixels(tester);
    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_pairScene(shift: 0.3, top: 200));
    final folded = BackdropUnderlay.debugFolds;
    await tester.pumpWidget(_pairScene(top: 200));
    expect(BackdropUnderlay.debugFolds, folded + 1);
    final upper = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .map((g) => g.debugUnderlay)
        .reduce(
          (a, b) => a.debugPlace.$1.bottom > b.debugPlace.$1.bottom ? a : b,
        );
    final (rect, offset) = upper.debugPlace;
    final image = upper.debugImage!;
    final bytes = (await tester.runAsync(image.toByteData))!.buffer
        .asUint8List();
    var largest = 0;
    for (var y = 0; y < rect.height.round(); y++) {
      for (var x = 0; x < rect.width.round(); x++) {
        final copied =
            ((offset.dy.round() + y) * image.width + offset.dx.round() + x) * 4;
        final read = ((rect.top.round() + y) * 260 + rect.left.round() + x) * 4;
        for (var c = 0; c < 4; c++) {
          final d = (bytes[copied + c] - reading[read + c]).abs();
          if (d > largest) largest = d;
        }
      }
    }
    // Without the lower glass the copy differs by 89 levels.
    expect(largest, lessThanOrEqualTo(3));
  }, skip: skipProperGlassTests);

  testWidgets('copies of glass side by side are drawn as one island, as '
      'each draws its own', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => BackdropUnderlay.debugIslandsEnabled = true);

    Future<Uint8List> draw({required bool islands}) async {
      BackdropUnderlay.debugIslandsEnabled = islands;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_pairScene(top: 160));
      return _pixels(tester);
    }

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    BackdropUnderlay.debugEnabledOverride = false;
    final reading = await draw(islands: false);
    BackdropUnderlay.debugEnabledOverride = true;
    final apart = await draw(islands: false);
    final before = BackdropUnderlay.debugIslands[2] ?? 0;
    final together = await draw(islands: true);
    expect(BackdropUnderlay.debugIslands[2], before + 1);
    final glass = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(glass.every((g) => g.debugDrewOverUnderlay), isTrue);
    final [a, b] = [for (final g in glass) g.debugUnderlay.debugImage!];
    expect(a.isCloneOf(b), isTrue);
    // The island blurs and refracts what lies beside a band where a copy of
    // its own mirrors its edge: closer to reading the backdrop.
    expect(
      _difference(reading, together),
      lessThanOrEqualTo(_difference(reading, apart)),
    );
    expect(_difference(reading, together), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  testWidgets('frosted copies apart are blurred in one layer and draw what '
      'reading the backdrop draws', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => BackdropUnderlay.debugEnabledOverride = null);

    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_pairScene(frost: 6));
    final reading = await _pixels(tester, pixelRatio: 2);
    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    final layers = BackdropUnderlay.debugBlurLayers;
    await tester.pumpWidget(_pairScene(frost: 6));
    expect(BackdropUnderlay.debugBlurLayers, layers + 1);
    final [a, b] = [
      for (final g
          in tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet())
        g.debugUnderlay.debugImage!,
    ];
    expect(a.isCloneOf(b), isTrue);
    expect(
      _difference(reading, await _pixels(tester, pixelRatio: 2)),
      lessThanOrEqualTo(2),
    );
  }, skip: skipProperGlassTests);

  testWidgets('glass over its copy lays its shadows under it, whole, and '
      'draws what its shadows cut outside it draw', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => BackdropUnderlay.debugEnabledOverride = null);
    List<bool> under() => [
      for (final g
          in tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet())
        g.debugShadowsUnderGlass,
    ];

    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(under(), [false, false]);
    final cut = await _pixels(tester, pixelRatio: 2);
    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(under(), [true, true]);
    final whole = await _pixels(tester, pixelRatio: 2);
    // The cut reached half a pixel into the glass's edge: only along the
    // edge do the two differ.
    bool nearEdge(Offset point) =>
        [
          const Rect.fromLTWH(30, 160, 200, 90),
          const Rect.fromLTWH(30, 260, 200, 60),
        ].any((rect) {
          final outer = rect.inflate(1.5);
          if (!outer.contains(point)) return false;
          const radius = 28.0;
          return RSuperellipse.fromRectAndRadius(
                outer,
                const Radius.circular(radius + 1.5),
              ).contains(point) &&
              !RSuperellipse.fromRectAndRadius(
                rect.deflate(1.5),
                const Radius.circular(radius - 1.5),
              ).contains(point);
        });
    var away = 0;
    for (var i = 0; i < cut.length; i++) {
      final pixel = i ~/ 4;
      final point = Offset(pixel % 520 / 2, pixel ~/ 520 / 2);
      final difference = (cut[i] - whole[i]).abs();
      if (difference > away && !nearEdge(point)) away = difference;
    }
    expect(away, lessThanOrEqualTo(3));
  }, skip: skipProperGlassTests);

  testWidgets('an island holds while what lies under it is unchanged and '
      'is recorded again, once, when it changes', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BackdropUnderlay.debugEnabledOverride = true;
    addTearDown(() => BackdropUnderlay.debugEnabledOverride = null);
    List<RenderLiquidGlassLayer> glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    await tester.pumpWidget(_pairScene(top: 160));
    final captures = [for (final g in glass()) g.debugUnderlay.debugCaptures];
    final islands = BackdropUnderlay.debugIslands[2] ?? 0;

    tester.binding.scheduleFrame();
    await tester.pump();
    expect(
      [for (final g in glass()) g.debugUnderlay.debugCaptures],
      captures,
    );

    await tester.pumpWidget(_pairScene(top: 160, shift: 0.3));
    expect(
      [
        for (final g in glass()) g.debugUnderlay.debugCaptures,
      ],
      [for (final c in captures) c + 1],
    );
    expect(BackdropUnderlay.debugIslands[2], islands + 1);
    final [a, b] = [for (final g in glass()) g.debugUnderlay.debugImage!];
    expect(a.isCloneOf(b), isTrue);
  }, skip: skipProperGlassTests);

  testWidgets('glass whose shadow paints between it and the next glass '
      'still joins it in an island', (tester) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BackdropUnderlay.debugEnabledOverride = true;
    addTearDown(() => BackdropUnderlay.debugEnabledOverride = null);
    final before = BackdropUnderlay.debugIslands[2] ?? 0;
    await tester.pumpWidget(_pairScene(top: 160, shadowed: true));
    expect(BackdropUnderlay.debugIslands[2], before + 1);
  }, skip: skipProperGlassTests);

  testWidgets('the composer draws the copies of a frame before its scene', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BackdropUnderlay.debugEnabledOverride = true;
    addTearDown(() => BackdropUnderlay.debugEnabledOverride = null);
    await tester.pumpWidget(_pairScene(shift: 0.3, top: 200));
    final flushes = Map.of(BackdropUnderlay.debugFlushes);
    await tester.pumpWidget(_pairScene(top: 200));
    expect(
      BackdropUnderlay.debugFlushes['planned'],
      (flushes['planned'] ?? 0) + 1,
    );
    expect(BackdropUnderlay.debugFlushes['read'], flushes['read']);
  }, skip: skipProperGlassTests);
}
