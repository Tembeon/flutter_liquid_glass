@Tags(['composer'])
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/composer_install.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

Widget _glass() => const LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
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
}
