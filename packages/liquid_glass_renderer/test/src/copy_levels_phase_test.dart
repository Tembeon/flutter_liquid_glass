@Tags(['composer'])
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_levels.dart';

// A copy of noise, so every cell of every level averages something its own.
ui.Picture _noise(Size size) {
  final random = Random(7);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0.0; y < size.height; y += 3) {
    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawRect(
        Rect.fromLTWH(x, y, 3, 3),
        Paint()..color = Color(0xFF000000 | random.nextInt(0xFFFFFF)),
      );
    }
  }
  return recorder.endRecording();
}

Future<Uint8List> _drawn(LevelStrip strip, CopyLevelPasses passes) async {
  final size = strip.size;
  final builder = ui.SceneBuilder();
  passes.push(builder, Offset.zero, size);
  builder.addPicture(Offset.zero, _noise(strip.copy));
  passes.pop(builder);
  final scene = builder.build();
  final image = scene.toImageSync(size.width.ceil(), size.height.ceil());
  scene.dispose();
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  testWidgets('the levels drawn repeat each period of the grid', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheLiquidGlass);
    expect(CopyLevelPasses.ready, isTrue);
    for (final levels in const [
      CopyLevels(least: 2, most: 9, fill: 12),
      CopyLevels(least: 1, most: 4),
      CopyLevels(fill: 7),
    ]) {
      LevelStrip strip(Offset grid) => LevelStrip(
        levels,
        pixels: 1,
        boxed: false,
        copy: const Size(70, 45),
        grid: grid,
      );
      final cell = 1 << max(strip(Offset.zero).last, 2);
      final stride = strip(Offset.zero).fillStride;
      var period = cell;
      while (stride > 0 && period % stride != 0) {
        period += cell;
      }
      const grid = Offset(37, -213);
      final here = strip(grid);
      final there = strip(grid + Offset(3.0 * period, -2.0 * period));
      final drawnHere = await tester.runAsync(
        () => _drawn(here, CopyLevelPasses.debugAtGrid(here, Offset.zero)!),
      );
      final drawnThere = await tester.runAsync(
        () => _drawn(there, CopyLevelPasses.debugAtGrid(there, Offset.zero)!),
      );
      expect(drawnThere, drawnHere, reason: '$levels over $period');
      final shifted = await tester.runAsync(
        () => _drawn(
          here,
          CopyLevelPasses.debugAtGrid(
            strip(grid + const Offset(0, 4)),
            Offset.zero,
          )!,
        ),
      );
      expect(shifted, isNot(drawnHere), reason: '$levels moved off the grid');
      expect(
        identical(
          CopyLevelPasses.of(here, Offset.zero),
          CopyLevelPasses.of(there, Offset.zero),
        ),
        isTrue,
      );
    }
  });
}
