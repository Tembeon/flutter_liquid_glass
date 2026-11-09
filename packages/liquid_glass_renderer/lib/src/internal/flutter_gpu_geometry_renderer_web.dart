import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/liquid_glass_support.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:meta/meta.dart';

/// Web stand-in for the Flutter GPU geometry renderer: the web has no
/// `flutter_gpu`, and every entry point that would submit GPU work throws.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._();

  /// Always fails on the web; callers fall back to fake glass.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) =>
      Future<FlutterGpuGeometryRenderer>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  /// Nothing is ever cached on the web.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) => null;

  /// The web has no shader filters.
  LiquidGlassDeviceClass get deviceClass =>
      LiquidGlassDeviceClass.noShaderFilters;

  static int get debugTotalRenderCount => 0;
  static int get debugActiveRendererCount => 0;
  static int get debugActiveGeometryTextureCount => 0;

  /// Matches the native renderer's reuse horizon; nothing is reused here.
  static const int reuseAfterFrames = 1;
  static int debugReusedTextureCount = 0;
  static int debugAllocatedTextureCount = 0;
  static int debugDroppedTextureCount = 0;

  /// Nothing is ever drawn on the web.
  static void flush() {}
  static void debugResetPages() {}
  static int debugBatchedSubmitCount = 0;
  static int debugDeferredPassCount = 0;
  static int debugPostFrameFlushCount = 0;
  Object? get debugMatteTexture => null;
  (int, int)? get debugMatteTextureSize => null;

  /// Nothing is drawn on the web, so nothing is left out.
  int get droppedShapes => 0;

  int debugRenderCount = 0;
  Object get debugPipelineIdentity => this;
  int get debugHostBufferBlockLength => 0;
  Object? get debugHostBufferIdentity => null;
  bool get debugDisposed => true;
  ui.Image? get atlasImage => null;
  List<ui.Image> get lookImages => const [];
  AtlasPlace? get atlasPlace => null;

  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) => throw UnsupportedError('Flutter GPU is not available on the web.');

  void releaseAtlas() {}

  void releaseOutput() {}

  void dispose() {}
}
