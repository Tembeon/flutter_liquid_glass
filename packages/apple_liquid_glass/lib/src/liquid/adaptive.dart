import 'package:apple_liquid_glass/src/liquid/liquid.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/widgets.dart';

/// Loads the glass shaders and finds whether this device draws full glass,
/// ahead of the first glass frame, so that an [AdaptiveGlassRenderer]
/// draws its pick from that frame on; it may be awaited before `runApp`.
///
/// With [warmUp] it also draws every glass pipeline once, offscreen, which
/// spares the first frame after an install a stall on a mid-range Android
/// phone and costs every launch. Failures are reported through
/// `FlutterError`, never thrown. A later call loads nothing new, and warms
/// up only if no earlier call did. On the web, where the adaptive renderer
/// draws fake glass, it loads nothing.
Future<void> precacheGlass({bool warmUp = false}) async {
  if (kIsWeb) return;
  await AdaptiveGlassRenderer._learn(LiquidGlass.precache(warmUp: warmUp));
}

/// Draws with [capable] where full glass runs well and with [fallback]
/// elsewhere, as [precacheGlass] or the first adaptive surface finds it;
/// [capable] draws until one has. On the web, where real glass cannot run,
/// it draws fake glass.
final class AdaptiveGlassRenderer extends GlassRenderer {
  /// Creates an adaptive renderer, by default liquid glass where it runs
  /// well and fake glass elsewhere.
  const AdaptiveGlassRenderer({
    this.capable = const LiquidGlassRenderer(),
    this.fallback = const FakeGlassRenderer(),
  });

  /// The renderer for a GPU that draws full glass well.
  final GlassRenderer capable;

  /// The renderer for any other device.
  final GlassRenderer fallback;

  static LiquidGlassSupport? _support;
  static Future<LiquidGlassSupport>? _loading;

  // Keeps what support finds about this device for every adaptive
  // renderer; the surfaces built before it answers draw with capable.
  static Future<void> _learn(Future<LiquidGlassSupport> support) async {
    _support = await (_loading = support);
  }

  /// Forgets the device class the adaptive renderers found, for tests.
  @visibleForTesting
  static void debugReset() {
    _support = null;
    _loading = null;
  }

  GlassRenderer get _resolved => kIsWeb
      ? const FakeGlassRenderer()
      : switch (_support?.deviceClass) {
          null || LiquidGlassDeviceClass.capable => capable,
          _ => fallback,
        };

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      _Resolve(
        builder: (context) => _resolved.buildSurface(context, details),
      );

  @override
  Widget buildGroup(BuildContext context, GlassGroupDetails details) =>
      _Resolve(
        builder: (context) => _resolved.buildGroup(context, details),
      );

  @override
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => _Resolve(
    builder: (context) => _resolved.buildScrollEdge(context, details),
  );

  @override
  bool operator ==(Object other) =>
      other is AdaptiveGlassRenderer &&
      other.capable == capable &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(capable, fallback);
}

class _Resolve extends StatefulWidget {
  const _Resolve({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_Resolve> createState() => _ResolveState();
}

class _ResolveState extends State<_Resolve> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb || AdaptiveGlassRenderer._support != null) return;
    AdaptiveGlassRenderer._learn(
      AdaptiveGlassRenderer._loading ?? LiquidGlass.precache(),
    ).then((_) {
      if (mounted) setState(() {});
    }).ignore();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
