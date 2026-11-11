import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_support.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/warm_up.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';

/// Implementation of [LiquidGlass.precache]. The warm-up runs only when
/// every full-glass program and the geometry bundle loaded.
Future<LiquidGlassSupport> precacheLiquidGlass({bool warmUp = false}) async {
  final fullGlass = !kIsWeb && ui.ImageFilter.isShaderFilterSupported;
  final finalShaders = FinalShaderVariant.assetKeys;
  FlutterGpuGeometryRenderer? renderer;
  final results = await Future.wait<bool>([
    MultiShaderBuilder.precacheShaders([
      ShaderKeys.fakeGlassSurface,
    ]).then((_) => true),
    if (fullGlass) ...[
      MultiShaderBuilder.precacheShaders([
        ...finalShaders,
        ShaderKeys.backdropFrost,
        ShaderKeys.backdropFrostAxis,
        ShaderKeys.backdropFrostSquare,
      ]).then((_) => finalShaders.every(MultiShaderBuilder.isCached)),
      _guard(() async {
        renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
      }),
    ],
  ]);
  try {
    if (!fullGlass) {
      return const LiquidGlassSupport(
        deviceClass: LiquidGlassDeviceClass.noShaderFilters,
        unavailableReason: 'Impeller shader filters are unavailable.',
      );
    }
    if (!results.every((loaded) => loaded)) {
      return const LiquidGlassSupport(
        deviceClass: LiquidGlassDeviceClass.unknown,
        unavailableReason:
            'A full-glass program or the Flutter GPU geometry bundle did not '
            'load; the error was reported through FlutterError.',
      );
    }
    final loaded = renderer!;
    if (warmUp) {
      await (_warmUp ??= _guard(() => warmLiquidGlassPipelines(loaded)));
    }
    return LiquidGlassSupport(deviceClass: loaded.deviceClass);
  } finally {
    renderer?.dispose();
  }
}

// The pipelines a warm-up creates last as long as the process.
Future<bool>? _warmUp;

Future<bool> _guard(Future<void> Function() load) async {
  try {
    await load();
    return true;
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'liquid_glass_renderer',
        context: ErrorDescription('while precaching liquid glass shaders'),
      ),
    );
    return false;
  }
}
