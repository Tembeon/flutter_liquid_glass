import 'package:apple_liquid_glass/src/liquid/liquid.dart';
import 'package:apple_liquid_glass/surfaces.dart';
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
/// up only if no earlier call did.
Future<void> precacheGlass({bool warmUp = false}) =>
    LiquidGlass.precache(warmUp: warmUp);

/// Draws with [capable] where full glass runs well and with [fallback]
/// elsewhere, as `LiquidGlass.support` says; [capable] draws until full
/// glass has loaded, which the first adaptive surface starts if
/// [precacheGlass] has not. Where the engine draws no shader filters, as
/// on the web, [fallback] draws from the first frame.
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

  GlassRenderer _of(LiquidGlassSupport support) =>
      support.isPending ||
          support.deviceClass == LiquidGlassDeviceClass.capable
      ? capable
      : fallback;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      _Resolve(
        builder: (context, support) =>
            _of(support).buildSurface(context, details),
      );

  @override
  Widget buildGroup(BuildContext context, GlassGroupDetails details) =>
      _Resolve(
        builder: (context, support) =>
            _of(support).buildGroup(context, details),
      );

  @override
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => _Resolve(
    builder: (context, support) =>
        _of(support).buildScrollEdge(context, details),
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

  final Widget Function(BuildContext context, LiquidGlassSupport support)
  builder;

  @override
  State<_Resolve> createState() => _ResolveState();
}

class _ResolveState extends State<_Resolve> {
  @override
  void initState() {
    super.initState();
    LiquidGlass.support.addListener(_rebuild);
    if (LiquidGlass.support.value.isPending) {
      LiquidGlass.precache().ignore();
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    LiquidGlass.support.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, LiquidGlass.support.value);
}
