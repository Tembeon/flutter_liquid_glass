@Tags(['composer'])
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/composer_install.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

Widget _glass() => const LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27Regular(),
  child: SizedBox(
    width: 120,
    height: 60,
    child: LiquidGlass(
      shape: LiquidRoundedSuperellipse(radius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

List<GlassFrames> _frames() =>
    GlassFrames.debugAllUnder(RendererBinding.instance.rootPipelineOwner);

void main() {
  for (final (name, glass) in [
    ('a glass layer', _glass()),
    (
      'fake glass',
      const FakeGlass(
        shape: LiquidRoundedSuperellipse(radius: 20),
        child: SizedBox(width: 120, height: 60),
      ),
    ),
  ]) {
    testWidgets('$name installs the composer as it makes its render object', (
      tester,
    ) async {
      GlassFrames.newPlanner = DirectReads.new;
      addTearDown(GlassComposer.install);
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: glass),
      );
      expect(_frames().single.debugPlanner, isA<GlassComposer>());
    });
  }

  testWidgets(
    'the composer installed while glass shows plans the next '
    'frame, and the glass paints for it',
    (tester) async {
      installsGlassComposer = false;
      GlassFrames.newPlanner = DirectReads.new;
      glassReadsCopies = true;
      addTearDown(() {
        installsGlassComposer = true;
        GlassComposer.install();
        glassReadsCopies = false;
      });
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: _glass()),
      );
      final frames = _frames().single;
      final layer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .single;
      expect(frames.debugPlanner, isA<DirectReads>());
      expect(layer.debugDrewOverCopy, isFalse);

      GlassComposer.install();
      expect(frames.debugPlanner, isA<DirectReads>());
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(frames.debugPlanner, isA<GlassComposer>());
      expect(layer.debugDrewOverCopy, isTrue);
    },
    skip: skipProperGlassTests,
  );

  testWidgets('a band that hosts its own filter layer, shown before the '
      'composer is installed, reads its copy from the next frame', (
    tester,
  ) async {
    installsGlassComposer = false;
    GlassFrames.newPlanner = DirectReads.new;
    glassReadsCopies = true;
    addTearDown(() {
      installsGlassComposer = true;
      GlassComposer.install();
      glassReadsCopies = false;
    });
    tester.view
      ..physicalSize = const Size(260, 200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    LiquidGlassBackdropFilterLayer band() =>
        tester.layers.whereType<LiquidGlassBackdropFilterLayer>().single;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Color(0xFF3060C0),
                child: Center(child: Text('Page under the band')),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, height: 60, child: _Band()),
          ],
        ),
      ),
    );
    expect(_frames().single.debugPlanner, isA<DirectReads>());
    expect(band().serves, isFalse);

    GlassComposer.install();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(_frames().single.debugPlanner, isA<GlassComposer>());
    expect(band().serves, isTrue);
  }, skip: skipProperGlassTests);
}

class _Band extends LeafRenderObjectWidget {
  const _Band();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBand();
}

class _RenderBand extends RenderBox with LiquidGlassBackdropFilterHost {
  final _layer = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer => _layer.layer;

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = (_layer.layer ??= LiquidGlassBackdropFilterLayer(
      filter: LiquidGlassBackdropFilter.image(
        ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        sigma: 3,
      ),
      clip: offset & size,
    ))..clip = offset & size;
    context.pushLayer(layer, (_, _) {}, offset);
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}
