import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('screen');

Widget _scene({
  double shift = 0,
  double dot = 0,
  bool texture = false,
  double opacity = 1,
  bool pair = false,
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
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: 0,
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

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
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
}
