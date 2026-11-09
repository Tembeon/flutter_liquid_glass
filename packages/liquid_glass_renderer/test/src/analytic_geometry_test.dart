import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('analytic');
const _view = Size(300, 200);
const _gray = Color(0xFF808080);

Widget _transformed(Matrix4? transform, Widget child) => transform == null
    ? child
    : Transform(
        transform: transform,
        alignment: Alignment.center,
        child: child,
      );

Widget _one(
  LiquidShape shape, {
  double width = 180,
  double height = 120,
  Matrix4? transform,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox.fromSize(
        size: _view,
        child: ColoredBox(
          color: _gray,
          child: _transformed(
            transform,
            LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight(),
              // A paint over a solid color, not a backdrop filter:
              // flutter_tester renders only a process's first backdrop
              // filter reliably.
              backdrop: const LiquidGlassBackdrop.solid(_gray),
              child: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: LiquidGlass(
                    shape: shape,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The scene at the view's own pixel ratio: a capture at another scale
/// resamples the matte, which the screen never does.
Future<Uint8List> _capture(WidgetTester tester, double ratio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

/// The mean channel difference and the share of channels that differ by
/// more than 16.
(double, double) _difference(Uint8List a, Uint8List b) {
  var total = 0;
  var differing = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    total += d;
    if (d > 16) differing++;
  }
  return (total / a.length, differing / a.length);
}

/// Pumps [scene] at width 170, then at 180, which the layer shades
/// analytically, and returns what that frame draws.
Future<Uint8List> _analyticFrame(
  WidgetTester tester,
  Widget Function(double width) scene,
  double ratio,
) async {
  tester.view
    ..physicalSize = _view * ratio
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scene(170));
  expect(_layer(tester).debugAnalyticIneligibility, 'new shapes');
  await tester.pumpWidget(scene(180));
  expect(_layer(tester).debugAnalytic, isTrue);
  return _capture(tester, ratio);
}

Future<(double, double)> _analyticAgainstRest(
  WidgetTester tester,
  Widget Function(double width) scene,
  double ratio,
) async {
  final analytic = await _analyticFrame(tester, scene, ratio);
  for (var i = 0; i < RenderLiquidGlassLayer.analyticRestFrames + 2; i++) {
    await tester.pump();
  }
  expect(_layer(tester).debugAnalytic, isFalse, reason: 'rests on a matte');
  final matte = await _capture(tester, ratio);
  // The glass draws: its edges and highlights leave the gray.
  final glass = [
    for (var i = 0; i < matte.length; i += 4)
      if ((matte[i] - 0x80).abs() > 8) i,
  ];
  expect(glass.length * 4 / matte.length, greaterThan(0.02));
  return _difference(matte, analytic);
}

void main() {
  testWidgets('a capsule with an oversized radius draws what one of half '
      'its height draws', (tester) async {
    Widget Function(double width) capsule(double radius) =>
        (width) => _one(
          LiquidRoundedSuperellipse(borderRadius: radius),
          width: width,
          height: 44,
        );
    final half = await _analyticFrame(tester, capsule(22), 1);
    await tester.pumpWidget(const SizedBox());
    final oversized = await _analyticFrame(tester, capsule(10000), 1);
    expect(_difference(half, oversized), (0.0, 0.0));
  }, skip: skipProperGlassTests);

  for (final (name, shape) in [
    ('rounded superellipse', const LiquidRoundedSuperellipse(borderRadius: 30)),
    (
      'pair',
      const LiquidRoundedSuperellipse(borderRadius: 16, bottomRadius: 44),
    ),
    ('rounded rectangle', const LiquidRoundedRectangle(borderRadius: 24)),
    ('oval', const LiquidOval()),
  ]) {
    for (final (scale, ratio, transform) in [
      ('1x', 1.0, null),
      ('2x', 2.0, null),
      (
        '2.625x, scaled and turned',
        2.625,
        Matrix4.rotationZ(0.2)..scaleByDouble(0.9, 0.7, 1, 1),
      ),
    ]) {
      testWidgets('one $name draws what its matte draws ($scale)', (
        tester,
      ) async {
        final (mean, share) = await _analyticAgainstRest(
          tester,
          (width) => _one(shape, width: width, transform: transform),
          ratio,
        );
        expect(mean, lessThan(0.05));
        expect(share, lessThan(0.0005));
      }, skip: skipProperGlassTests);
    }
  }

  testWidgets('one shape is shaded analytically while it changes', (
    tester,
  ) async {
    const shape = LiquidRoundedSuperellipse(borderRadius: 30);
    await tester.pumpWidget(_one(shape));
    final layer = _layer(tester);
    expect(layer.debugAnalytic, isFalse, reason: 'a new shape has a matte');
    expect(layer.debugAnalyticIneligibility, 'new shapes');

    await tester.pumpWidget(_one(shape, width: 200));
    expect(layer.debugAnalytic, isTrue);
    expect(
      layer.debugLiveShader,
      same(
        layer.finalShaders[FinalShaderVariant.indexOf(
          FinalShaderKind.shape,
          FinalShaderModels.ios27,
        )],
      ),
    );
    for (var i = 0; i < RenderLiquidGlassLayer.analyticRestFrames + 2; i++) {
      await tester.pump();
    }
    expect(layer.debugAnalytic, isFalse, reason: 'rests on a matte');

    RenderLiquidGlassLayer.debugAnalyticShape = false;
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticShape = true);
    await tester.pumpWidget(_one(shape, width: 220));
    expect(layer.debugAnalytic, isFalse);
    expect(layer.debugAnalyticIneligibility, 'off');
  }, skip: skipProperGlassTests);

  testWidgets('more than one shape keeps the matte', (tester) async {
    Widget two(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27RegularLight(),
        backdrop: const LiquidGlassBackdrop.solid(_gray),
        child: Row(
          children: [
            for (var i = 0; i < 2; i++)
              SizedBox(
                width: width,
                height: 60,
                child: const LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(two(80));
    await tester.pumpWidget(two(90));
    expect(_layer(tester).debugAnalytic, isFalse);
    expect(_layer(tester).debugAnalyticIneligibility, 'more than one shape');
  }, skip: skipProperGlassTests);
}
