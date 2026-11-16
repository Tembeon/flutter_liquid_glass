import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/warm_up.dart';

/// Whether full glass draws in this process: loading ([FullGlassPending]),
/// ready to draw ([FullGlassReady]), or not drawn ([FullGlassUnavailable]).
///
/// One state for the process, the only place the renderer asks whether the
/// engine draws shader filters ([shaderFilters]) and the only source of the
/// final shaders and the geometry renderer of real glass: a glass layer
/// draws real glass with what [FullGlassReady] gives it and fake glass in
/// every other state. Without shader filters, as on Skia and the web, the
/// state starts unavailable and stays so; elsewhere it starts pending and
/// [load] settles it once, ready or unavailable for good.
@internal
sealed class FullGlass {
  const FullGlass._();

  /// Whether the engine draws shader filters: Impeller does, Skia and the
  /// web do not. Fake glass frosts copies and keeps backdrops fresh by it,
  /// and full glass needs it.
  static final bool shaderFilters =
      !kIsWeb && ui.ImageFilter.isShaderFilterSupported;

  static final FullGlass _first = shaderFilters
      ? const FullGlassPending._()
      : const FullGlassUnavailable._(
          LiquidGlassSupport(
            deviceClass: LiquidGlassDeviceClass.noShaderFilters,
            unavailableReason: 'Impeller shader filters are unavailable.',
          ),
        );

  static final ValueNotifier<FullGlass> _state = ValueNotifier(_first);

  /// The state of full glass in this process.
  static ValueListenable<FullGlass> get state => _state;

  static Future<FullGlass>? _loading;
  static bool _loadScheduled = false;

  // What the last load found, which a test override gives back.
  static FullGlass? _found;

  /// Loads the fake glass programs everywhere and, where the engine draws
  /// shader filters, every full-glass program and the Flutter GPU geometry
  /// bundle, then settles [state]. Every call shares the first load.
  ///
  /// Failures are reported through `FlutterError` and leave full glass
  /// unavailable for the life of the process.
  static Future<FullGlass> load() => _loading ??= _load();

  /// Starts [load] after the frame being drawn, unless it started: loading
  /// creates the engine's GPU context, which a first frame need not wait
  /// for.
  static void loadAfterFrame() {
    if (_loading != null || _loadScheduled) return;
    _loadScheduled = true;
    // After the frame: the layers it shows draw fake glass until the load
    // settles, which is no glass a frame late.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      unawaited(load());
    });
  }

  /// Loads full glass ([load]), with [warmUp] draws each of its pipelines
  /// once offscreen, and says what it found.
  ///
  /// The warm-up runs once in the process, when full glass is ready.
  static Future<LiquidGlassSupport> precache({bool warmUp = false}) async {
    final glass = await load();
    if (warmUp && glass is FullGlassReady) {
      await (_warmUp ??= _guard(() async {
        final renderer = glass.geometryRenderer();
        try {
          await warmLiquidGlassPipelines(renderer);
        } finally {
          renderer.dispose();
        }
      }));
    }
    return glass.support;
  }

  // The pipelines a warm-up creates last as long as the process.
  static Future<bool>? _warmUp;

  static Future<FullGlass> _load() async {
    final finals = FinalShaderVariant.assetKeys;
    FlutterGpuGeometryRenderer? geometry;
    await Future.wait<void>([
      GlassShaderPrograms.precacheShaders([
        ...ShaderKeys.fakeSurfaceAssets,
        ShaderKeys.bentContent,
      ]),
      if (shaderFilters) ...[
        GlassShaderPrograms.precacheShaders([
          ...finals,
          ShaderKeys.backdropFrost,
          ShaderKeys.backdropFrostAxis,
          ShaderKeys.backdropFrostSquare,
          ShaderKeys.backdropHazeStrip,
          ShaderKeys.backdropHazeMix,
        ]),
        _guard(() async {
          geometry = await FlutterGpuGeometryRenderer.fromAsset(
            ShaderKeys.gpuGeometryShaderBundle,
          );
        }),
      ],
    ]);
    final programs = finals.map(GlassShaderPrograms.cached).nonNulls.toList();
    final FullGlass found;
    if (!shaderFilters) {
      found = _first;
    } else if (geometry case final geometry?
        when programs.length == finals.length) {
      found = FullGlassReady._(programs, geometry);
    } else {
      geometry?.dispose();
      found = const FullGlassUnavailable._(
        LiquidGlassSupport(
          deviceClass: LiquidGlassDeviceClass.unknown,
          unavailableReason:
              'A full-glass program or the Flutter GPU geometry bundle did '
              'not load; the error was reported through FlutterError.',
        ),
      );
    }
    _found = found;
    _state.value = found;
    return found;
  }

  /// Makes [state] say [support] for a test, as if loading full glass had
  /// found it: [LiquidGlassSupport.pending] forgets what was found, so glass
  /// draws as while it loads until the next [load], an unavailable support
  /// holds until the next override, and null gives back what the last load
  /// found. `LiquidGlass.debugOverrideSupport` calls it.
  static void debugOverride(LiquidGlassSupport? support) {
    switch (support) {
      case null:
        final found = _found;
        _loading = found == null ? null : Future.value(found);
        _state.value = found ?? _first;
      case LiquidGlassSupport(isPending: true):
        _loading = null;
        _state.value = const FullGlassPending._();
      case _:
        assert(!support.available, 'Only a load makes full glass ready.');
        final unavailable = FullGlassUnavailable._(support);
        _loading = Future.value(unavailable);
        _state.value = unavailable;
    }
  }

  /// What this state says about the device.
  LiquidGlassSupport get support;
}

/// Full glass is loading: layers draw fake glass meanwhile.
@internal
final class FullGlassPending extends FullGlass {
  const FullGlassPending._() : super._();

  @override
  LiquidGlassSupport get support => LiquidGlassSupport.pending;
}

/// Full glass draws: every final program and the geometry bundle loaded.
///
/// It gives each glass that draws real glass the final shaders and the
/// geometry renderer it owns, so nothing draws real glass without them.
@internal
final class FullGlassReady extends FullGlass {
  FullGlassReady._(this._programs, this._geometry)
    : support = LiquidGlassSupport(deviceClass: _geometry.deviceClass),
      super._();

  final List<ui.FragmentProgram> _programs;

  // Never draws: the renderers it gives share the bundle it loaded.
  final FlutterGpuGeometryRenderer _geometry;

  @override
  final LiquidGlassSupport support;

  /// New final shaders, one per `FinalShaderVariant.all`, which the caller
  /// disposes.
  List<ui.FragmentShader> finalShaders() => [
    for (final program in _programs) program.fragmentShader(),
  ];

  /// A new geometry renderer, which the caller disposes.
  FlutterGpuGeometryRenderer geometryRenderer() =>
      FlutterGpuGeometryRenderer.sharing(_geometry);
}

/// Full glass does not draw, for the reason [support] gives: layers draw
/// fake glass.
@internal
final class FullGlassUnavailable extends FullGlass {
  const FullGlassUnavailable._(this.support) : super._();

  @override
  final LiquidGlassSupport support;
}

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
        context: ErrorDescription('while loading liquid glass shaders'),
      ),
    );
    return false;
  }
}
