import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_support.dart';
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
  static int get debugActiveMaterialTextureCount => 0;

  /// Matches the native renderer's reuse horizon; nothing is reused here.
  static const int reuseAfterFrames = 1;
  static int debugReusedTextureCount = 0;
  static int debugAllocatedTextureCount = 0;
  static int debugDroppedTextureCount = 0;

  /// Nothing is ever deferred on the web.
  static void flushPendingSubmissions() {}
  static int debugBatchedSubmitCount = 0;
  static int debugDeferredPassCount = 0;
  static int debugPostFrameFlushCount = 0;
  int get debugRetiredTextureCount => 0;
  int get debugMatteTextureCount => 0;
  Object? get debugMatteTexture => null;
  (int, int)? get debugMatteTextureSize => null;

  /// Material map texels per matte pixel along each side.
  static const int materialRasterScale = geometryMaterialRasterScale;

  /// The most shapes one draw of the matte evaluates.
  static const int maxShapesPerDraw = geometryMaxShapesPerDraw;

  /// Nothing is drawn on the web, so nothing is left out.
  int get droppedShapes => 0;

  int debugRenderCount = 0;
  int debugMatteDrawCount = 0;
  int debugMaterialDrawCount = 0;
  Object get debugPipelineIdentity => this;
  int get debugHostBufferBlockLength => 0;
  Object? get debugHostBufferIdentity => null;
  bool get debugDisposed => true;
  ui.Image? get materialImage => null;

  ({
    ui.Image image,
    int width,
    int height,
    int textureWidth,
    int textureHeight,
  })
  render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double refractionHeight,
    required double refractionAmount,
    required double offsetX,
    required double offsetY,
    double? edgeDistanceRange,
    bool refractionFitsShape = true,
    double contourExtent = 0.5,
    bool writeMatte = true,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
    List<double> rseLowerData = const <double>[],
    List<double> boundsData = const <double>[],
    required int matteScale,
    LiquidGlassField? field,
    double fieldScale = 1,
  }) => throw UnsupportedError('Flutter GPU is not available on the web.');

  void releaseOutput() {}

  void dispose() {}
}
