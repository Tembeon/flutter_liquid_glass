import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';

Widget _scene(double width, {Key? key}) {
  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: Center(
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings(
          contourStrength: 0.3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 22),
              child: SizedBox(width: width, height: 44),
            ),
            const SizedBox(width: 12),
            // A second appearance, so every render also writes a look.
            const LiquidGlass(
              shape: LiquidOval(),
              appearance: LiquidGlassAppearance(tint: Color(0x552060FF)),
              child: SizedBox(width: 44, height: 44),
            ),
          ],
        ),
      ),
    ),
  );
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;

/// What the final shader reads of the [width] x [height] geometry buffer
/// in the atlas [image], pixel by pixel.
Future<List<(double, double, double, double)>> _geometry(
  WidgetTester tester,
  ui.Image image,
  int width,
  int height,
) async {
  final atlas = (await tester.runAsync(() => AtlasTexels.read(image)))!;
  return [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) atlas.pixel(x, y),
  ];
}

/// A tint beside [testRectangle].
final _tint = ShapeLooks(const [1, 0, 0, 1, 1, 1, 0, 1], tintOnly: true);

/// What the final shader reads of [look], a texture beside the atlas
/// [image] of a [width] x [height] geometry buffer, pixel by pixel.
Future<List<(double, double, double, double)>> _looks(
  WidgetTester tester,
  ui.Image image,
  ui.Image look,
  int width,
  int height,
) async {
  final atlas = (await tester.runAsync(() => AtlasTexels.read(image)))!;
  final texels = (await tester.runAsync(() => AtlasTexels.read(look)))!;
  return [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) atlas.lookAt(texels, x, y),
  ];
}

int get _allocated => FlutterGpuGeometryRenderer.debugAllocatedTextureCount;
int get _dropped => FlutterGpuGeometryRenderer.debugDroppedTextureCount;
int get _reused => FlutterGpuGeometryRenderer.debugReusedTextureCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGeometryTextureReuseTests();
}

/// Also runs on devices from `example/integration_test/geometry_batch_test.dart`.
void runGeometryTextureReuseTests() {
  setUp(() {
    FlutterGpuGeometryRenderer.debugReusedTextureCount = 0;
  });

  void useDpr3(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(2400, 600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'a changing atlas ping-pongs between two textures',
    (tester) async {
      useDpr3(tester);
      // 0.05 logical px per frame keeps the atlas's size, like a stretch.
      await tester.pumpWidget(_scene(130));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final textures = <Object?>[renderer.debugMatteTexture];
      for (var frame = 1; frame <= 8; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
        textures.add(renderer.debugMatteTexture);
      }
      for (var frame = 1; frame < textures.length; frame++) {
        expect(
          identical(textures[frame], textures[frame - 1]),
          isFalse,
          reason: 'frame $frame must not rewrite the texture on screen',
        );
      }
      for (var frame = 2; frame < textures.length; frame++) {
        expect(
          identical(textures[frame], textures[frame - 2]),
          isTrue,
          reason: 'frame $frame reuses the texture retired one frame earlier',
        );
      }
      expect(renderer.debugMatteTextureCount, 2);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a texture its atlases leave half empty for 30 renders shrinks to fit',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(700));
      await tester.pumpWidget(_scene(700.05));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final (wideWidth, wideHeight) = renderer.debugMatteTextureSize!;
      for (var frame = 1; frame <= 40; frame++) {
        await tester.pumpWidget(_scene(60 + frame * 0.05));
      }
      final (width, height) = renderer.debugMatteTextureSize!;
      expect(width * height * 2, lessThanOrEqualTo(wideWidth * wideHeight));
      final allocatedBefore = _allocated;
      for (var frame = 41; frame <= 60; frame++) {
        await tester.pumpWidget(_scene(60 + frame * 0.05));
      }
      expect(_allocated - allocatedBefore, 0);
      expect(renderer.debugMatteTextureCount, 2);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a resize sweep stops allocating once the texture has grown',
    (tester) async {
      useDpr3(tester);
      // 4 logical px per frame at DPR 3 changes the atlas's size every few
      // frames, in both directions.
      double width(int frame) {
        final phase = frame % 100;
        return 130 + 4.0 * (phase < 50 ? phase : 100 - phase);
      }

      await tester.pumpWidget(_scene(width(0)));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      // Two warmup sweeps grow the ring to full capacity.
      for (var frame = 1; frame < 200; frame++) {
        await tester.pumpWidget(_scene(width(frame)));
      }
      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      final reusedBefore = _reused;
      const measured = 200;
      for (var frame = 200; frame < 200 + measured; frame++) {
        await tester.pumpWidget(_scene(width(frame)));
      }
      expect(_allocated - allocatedBefore, 0);
      expect(_dropped - droppedBefore, 0);
      expect(
        _reused - reusedBefore,
        measured,
        reason: 'every atlas comes from the ring with its look',
      );
      final (textureWidth, _) = renderer.debugMatteTextureSize!;
      expect(textureWidth, lessThanOrEqualTo(AtlasLayout.maxSize));
      expect(renderer.debugMatteTextureCount, 2);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'an atlas in a larger texture reads as a fresh one',
    (tester) async {
      useDpr3(tester);
      // Grow the texture, then come back to a much smaller atlas.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 30.0));
      }
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(131.5 + frame * 0.01));
      }
      final reusedBefore = _reused;
      await tester.pumpWidget(_scene(131.5));
      expect(
        _reused - reusedBefore,
        1,
        reason: 'the compared atlas must be a reused texture',
      );
      final layer = _layer(tester);
      final bufferSize = layer.debugGeometryMatteBounds.size * 3;
      final width = bufferSize.width.round();
      final height = bufferSize.height.round();
      final reusedImage = layer.debugGeometryImage!.clone();
      final reusedLookImages = [
        for (final look in layer.debugLookImages) look.clone(),
      ];
      expect(reusedLookImages, isNotEmpty);
      addTearDown(reusedImage.dispose);
      for (final look in reusedLookImages) {
        addTearDown(look.dispose);
      }

      // A new layer owns a new renderer, whose first textures are
      // exact-size.
      await tester.pumpWidget(_scene(131.5, key: UniqueKey()));
      final fresh = _layer(tester);
      expect(
        reusedImage.width * reusedImage.height,
        greaterThan(
          fresh.debugGeometryImage!.width * fresh.debugGeometryImage!.height,
        ),
      );
      // The larger texture is laid out to its own width, so both are read
      // as the final shader reads them: through their tables.
      final reused = await _geometry(tester, reusedImage, width, height);
      final freshGeometry = await _geometry(
        tester,
        fresh.debugGeometryImage!,
        width,
        height,
      );
      expect(reused, freshGeometry);
      expect(fresh.debugLookImages, hasLength(reusedLookImages.length));
      for (final (i, freshLook) in fresh.debugLookImages.indexed) {
        expect(
          await _looks(tester, reusedImage, reusedLookImages[i], width, height),
          await _looks(
            tester,
            fresh.debugGeometryImage!,
            freshLook,
            width,
            height,
          ),
          reason: 'look $i',
        );
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a recreated layer allocates fresh textures',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(130, key: const ValueKey('a')));
      final first = _layer(tester).gpuGeometryRenderer!;
      final firstMatte = first.debugMatteTexture;
      await tester.pumpWidget(const SizedBox());

      final allocatedBefore = _allocated;
      await tester.pumpWidget(_scene(130, key: const ValueKey('b')));
      final second = _layer(tester).gpuGeometryRenderer!;
      expect(
        _allocated - allocatedBefore,
        greaterThan(0),
        reason: 'nothing is shared between renderers',
      );
      expect(identical(second.debugMatteTexture, firstMatte), isFalse);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'spare textures stay retained while geometry is stable',
    (tester) async {
      useDpr3(tester);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
      }
      final renderer = _layer(tester).gpuGeometryRenderer!;
      expect(renderer.debugRetiredTextureCount, greaterThan(0));
      for (var frame = 0; frame < 130; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        tester.binding.scheduleFrame();
      }
      expect(renderer.debugRetiredTextureCount, greaterThan(0));
      expect(renderer.debugMatteTextureCount, lessThanOrEqualTo(2));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'renders within one frame never reuse a texture an earlier render '
    'retired',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final reusedBefore = _reused;
        final atlases = <Object?>[];
        for (var index = 0; index < 3; index++) {
          renderTestRectangle(renderer, centerX: 16.0 + index * 3);
          atlases.add(renderer.debugMatteTexture);
          expect(
            renderer.debugMatteTextureCount,
            lessThanOrEqualTo(3),
            reason: 'three renders hold at most three atlases',
          );
        }
        for (var index = 1; index < atlases.length; index++) {
          for (var earlier = 0; earlier < index; earlier++) {
            expect(
              identical(atlases[index], atlases[earlier]),
              isFalse,
              reason: 'render $index must not rewrite an earlier atlas',
            );
          }
        }
        expect(
          _reused - reusedBefore,
          0,
          reason: 'a texture retired this frame is too young to reuse',
        );
      });
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'looks come and go with the atlas they lie beside',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final reusedBefore = _reused;
        void render(ShapeLooks? looks, {int index = 0}) =>
            renderTestRectangle(renderer, centerX: 16.0 + index, looks: looks);

        render(_tint);
        final first = renderer.lookImages.single;
        render(null, index: 1);
        expect(renderer.lookImages, isEmpty);
        expect(first.debugDisposed, isTrue);
        render(ShapeLooks(List.filled(8, 1), tintOnly: false), index: 2);
        expect(renderer.lookImages, hasLength(3));
        expect(renderer.debugRenderCount, 3);
        expect(
          _reused - reusedBefore,
          0,
          reason: 'a texture retired this frame is too young to reuse',
        );
      });
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'an atlas holds its looks whatever the atlases before it held',
    (tester) async {
      // Impeller keeps a framebuffer on its first attachment's texture, so
      // an atlas texture that drew with other looks would drop these.
      final renderer = (await tester.runAsync(createGeometryRenderer))!;
      final full = ShapeLooks(const [1, 0, 0, 1, 1, 1, 0, 7], tintOnly: false);
      final reusedBefore = _reused;
      for (final (frame, looks) in [
        null,
        null,
        _tint,
        _tint,
        full,
        full,
        full,
        null,
        _tint,
        full,
      ].indexed) {
        renderTestRectangle(renderer, looks: looks);
        await tester.pumpWidget(SizedBox(width: frame.toDouble()));
        final atlas = (await tester.runAsync(
          () => AtlasTexels.read(renderer.atlasImage!),
        ))!;
        final read = [
          for (final image in renderer.lookImages)
            atlas.lookAt(
              (await tester.runAsync(() => AtlasTexels.read(image)))!,
              16,
              32,
            ),
        ];
        expect(read, switch (looks) {
          null => isEmpty,
          ShapeLooks(tintOnly: true) => [(1.0, 0.0, 0.0, 1.0)],
          _ => [
            (1.0, 0.0, 0.0, 1.0),
            (1.0, 1.0, 0.0, 1.0),
            (0.0, 0.0, 0.0, 1.0),
          ],
        }, reason: 'frame $frame');
      }
      expect(_reused - reusedBefore, greaterThan(0));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'two renders per frame stop allocating after warmup',
    (tester) async {
      final renderer = (await tester.runAsync(createGeometryRenderer))!;
      // Registers the scene-frame counter before the first pump.
      renderTestRectangle(renderer);
      var frame = 0;
      Future<void> pumpTwoRenders() async {
        // Submit a frame before recording its two geometry updates.
        await tester.pumpWidget(const SizedBox());
        renderTestRectangle(renderer, looks: frame.isEven ? _tint : null);
        renderTestRectangle(renderer, centerX: 19, looks: _tint);
        frame++;
      }

      for (var i = 0; i < 6; i++) {
        await pumpTwoRenders();
      }
      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      for (var i = 0; i < 8; i++) {
        await pumpTwoRenders();
      }
      expect(
        _allocated - allocatedBefore,
        0,
        reason: 'the ring covers two renders per submitted frame',
      );
      expect(_dropped - droppedBefore, 0);
      expect(renderer.debugMatteTextureCount, lessThanOrEqualTo(4));
      expect(renderer.lookImages, isNotEmpty);
    },
    skip: skipProperGlassTests,
  );
}
