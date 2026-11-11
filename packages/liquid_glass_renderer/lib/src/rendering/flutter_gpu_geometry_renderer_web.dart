import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// Web stand-in for the Flutter GPU geometry renderer: the web has no
/// `flutter_gpu`, and every entry point that would submit GPU work throws.
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

  /// Always 0: nothing is drawn on the web.
  static int get debugTotalRenderCount => 0;

  /// Always 0: no renderer exists on the web.
  static int get debugActiveRendererCount => 0;

  /// Always 0: no atlas exists on the web.
  static int get debugActiveGeometryTextureCount => 0;

  /// Matches the native renderer's reuse horizon; nothing is reused here.
  static const int reuseAfterFrames = 1;

  /// Never counts on the web.
  static int debugReusedTextureCount = 0;

  /// Never counts on the web.
  static int debugAllocatedTextureCount = 0;

  /// Never counts on the web.
  static int debugDroppedTextureCount = 0;

  /// Nothing is ever drawn on the web.
  static void flush() {}

  /// Does nothing on the web.
  static void debugResetPages() {}

  /// Never counts on the web.
  static int debugBatchedSubmitCount = 0;

  /// Never counts on the web.
  static int debugDeferredPassCount = 0;

  /// Never counts on the web.
  static int debugPostFrameFlushCount = 0;

  /// Always null on the web.
  Object? get debugMatteTexture => null;

  /// Always null on the web.
  (int, int)? get debugMatteTextureSize => null;

  /// Nothing is drawn on the web, so nothing is left out.
  int get droppedShapes => 0;

  /// Never counts on the web.
  int debugRenderCount = 0;

  /// The renderer itself: there is no pipeline on the web.
  Object get debugPipelineIdentity => this;

  /// Always 0 on the web.
  int get debugHostBufferBlockLength => 0;

  /// Always null on the web.
  Object? get debugHostBufferIdentity => null;

  /// Always true: a web renderer holds nothing.
  bool get debugDisposed => true;

  /// Always null on the web.
  ui.Image? get atlasImage => null;

  /// Always empty on the web.
  List<ui.Image> get lookImages => const [];

  /// Always null on the web.
  AtlasPlace? get atlasPlace => null;

  /// Throws: the web has no Flutter GPU.
  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) => throw UnsupportedError('Flutter GPU is not available on the web.');

  /// Does nothing on the web.
  void releaseAtlas() {}

  /// Does nothing on the web.
  void releaseOutput() {}

  /// Does nothing on the web.
  void dispose() {}
}
