import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// Web stand-in for the Flutter GPU geometry renderer: the web has no
/// `flutter_gpu`, and every entry point that would submit GPU work throws.
///
/// It names only what the library calls; the native renderer's debug
/// counters are read by host tests, which run native.
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._();

  /// Throws: no renderer loads on the web for [other] to share.
  factory FlutterGpuGeometryRenderer.sharing(
    FlutterGpuGeometryRenderer other,
  ) => throw UnsupportedError(
    'Flutter GPU is not available on the web; $other has nothing to share.',
  );

  /// Always fails on the web; callers fall back to fake glass.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) =>
      Future<FlutterGpuGeometryRenderer>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  /// Nothing is ever drawn on the web.
  static void flush() {}

  /// The web has no shader filters.
  LiquidGlassDeviceClass get deviceClass =>
      LiquidGlassDeviceClass.noShaderFilters;

  /// Does nothing on the web.
  void releaseAtlas() {}

  /// Does nothing on the web.
  void dispose() {}
}

/// A web renderer for a host test: the web build itself never makes one.
@visibleForTesting
FlutterGpuGeometryRenderer debugWebGeometryRenderer() =>
    FlutterGpuGeometryRenderer._();

/// The renderer's atlas, which only the rendering library draws and reads.
extension FlutterGpuGeometryRendererAtlas on FlutterGpuGeometryRenderer {
  /// Throws: the web has no Flutter GPU.
  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) => throw UnsupportedError('Flutter GPU is not available on the web.');
}
