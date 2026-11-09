import 'dart:typed_data';
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
            // A second appearance, so every render also writes a material
            // map.
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

/// Draws [testRectangle]'s material map at [centerX].
void _renderMaterials(
  FlutterGpuGeometryRenderer renderer, {
  double centerX = 16,
}) => renderer.renderMaterials(
  testRectangle(centerX: centerX),
  width: 64,
  height: 64,
  appearanceData: List<double>.filled(128, 0),
  tintOnly: false,
);

/// The top-left [width] x [height] texels of [image], as RGBA bytes.
Future<Uint8List> _subRect(
  WidgetTester tester,
  ui.Image image,
  int width,
  int height,
) async {
  final data = await tester.runAsync(image.toByteData);
  final bytes = data!.buffer.asUint8List();
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    out.setRange(
      y * width * 4,
      (y + 1) * width * 4,
      bytes,
      y * image.width * 4,
    );
  }
  return out;
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
        2 * measured,
        reason: 'every atlas and material map comes from the ring',
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
        await tester.pumpWidget(_scene(130 + frame * 12.0));
      }
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(131.5 + frame * 0.01));
      }
      final reusedBefore = _reused;
      await tester.pumpWidget(_scene(131.5));
      expect(
        _reused - reusedBefore,
        2,
        reason: 'the compared atlas and material map must be reused textures',
      );
      final layer = _layer(tester);
      final bufferSize = layer.debugGeometryMatteBounds.size * 3;
      final width = bufferSize.width.round();
      final height = bufferSize.height.round();
      final reusedImage = layer.debugGeometryImage!.clone();
      final reusedMaterialImage = layer.debugMaterialImage!.clone();
      addTearDown(reusedImage.dispose);
      addTearDown(reusedMaterialImage.dispose);

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
      final materialWidth = fresh.debugMaterialImage!.width;
      final materialHeight = fresh.debugMaterialImage!.height;
      expect(
        reusedMaterialImage.width * reusedMaterialImage.height,
        greaterThan(materialWidth * materialHeight),
      );
      final reused = await _geometry(tester, reusedImage, width, height);
      final reusedMaterial = await _subRect(
        tester,
        reusedMaterialImage,
        materialWidth,
        materialHeight,
      );
      final freshGeometry = await _geometry(
        tester,
        fresh.debugGeometryImage!,
        width,
        height,
      );
      final freshMaterial = await _subRect(
        tester,
        fresh.debugMaterialImage!,
        materialWidth,
        materialHeight,
      );

      expect(reused, freshGeometry);
      expect(reusedMaterial, freshMaterial);
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
            reason: 'at most three atlas textures are retained',
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
    'toggling the material map off and on within a frame stays safe',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final reusedBefore = _reused;
        void render({required bool writeMaterials, int index = 0}) {
          renderTestRectangle(renderer, centerX: 16.0 + index);
          if (writeMaterials) {
            _renderMaterials(renderer, centerX: 16.0 + index);
          } else {
            renderer.releaseMaterials();
          }
        }

        render(writeMaterials: true);
        final firstMaterial = renderer.materialImage;
        expect(firstMaterial, isNotNull);
        render(writeMaterials: false, index: 1);
        expect(renderer.materialImage, isNull);
        render(writeMaterials: false, index: 2);
        expect(renderer.materialImage, isNull);
        render(writeMaterials: true, index: 3);
        expect(renderer.materialImage, isNotNull);
        expect(
          identical(renderer.materialImage, firstMaterial),
          isFalse,
          reason: 'the spare retired this frame is too young to reuse',
        );
        expect(_reused - reusedBefore, 0);
      });
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'material maps leave the atlas and respect same-frame retirement',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final reusedBefore = _reused;
        final atlas = renderTestRectangle(renderer);
        final texture = renderer.debugMatteTexture;
        _renderMaterials(renderer);
        final firstMaterial = renderer.materialImage!.clone();
        addTearDown(firstMaterial.dispose);
        final before = (await firstMaterial.toByteData())!.buffer.asUint8List();

        _renderMaterials(renderer);
        final secondMaterial = renderer.materialImage!.clone();
        addTearDown(secondMaterial.dispose);
        expect(secondMaterial.isCloneOf(firstMaterial), isFalse);
        renderer.releaseMaterials();
        expect(renderer.materialImage, isNull);
        _renderMaterials(renderer);
        expect(renderer.materialImage!.isCloneOf(firstMaterial), isFalse);
        expect(renderer.materialImage!.isCloneOf(secondMaterial), isFalse);
        expect(renderer.debugMatteTexture, same(texture));
        expect(renderer.atlasImage, same(atlas));
        expect(renderer.debugMatteDrawCount, 1);
        expect(renderer.debugMaterialDrawCount, 3);
        expect(_reused - reusedBefore, 0);
        expect(
          (await firstMaterial.toByteData())!.buffer.asUint8List(),
          before,
          reason: 'an earlier material snapshot must not be overwritten',
        );
      });
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
        renderTestRectangle(renderer);
        if (frame.isEven) {
          _renderMaterials(renderer);
        } else {
          renderer.releaseMaterials();
        }
        renderTestRectangle(renderer, centerX: 19);
        _renderMaterials(renderer, centerX: 19);
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
      expect(renderer.debugMatteTextureCount, lessThanOrEqualTo(3));
      expect(renderer.materialImage, isNotNull);
    },
    skip: skipProperGlassTests,
  );
}
