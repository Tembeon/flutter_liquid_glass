import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Draws with [capable] where full glass runs well and with [fallback]
/// elsewhere, as `LiquidGlass.precache` finds it once per run.
@internal
final class AdaptiveGlassRenderer extends GlassRenderer {
  /// Creates an adaptive renderer.
  const AdaptiveGlassRenderer({required this.capable, required this.fallback});

  /// The renderer for a GPU that draws full glass well.
  final GlassRenderer capable;

  /// The renderer for any other device.
  final GlassRenderer fallback;

  static LiquidGlassSupport? _support;
  static Future<LiquidGlassSupport>? _loading;

  /// Forgets what `LiquidGlass.precache` found, for tests.
  @visibleForTesting
  static void debugReset() {
    _support = null;
    _loading = null;
  }

  GlassRenderer get _resolved => switch (_support?.deviceClass) {
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
    if (AdaptiveGlassRenderer._support != null) return;
    final loading = AdaptiveGlassRenderer._loading ??= LiquidGlass.precache();
    loading.then((support) {
      AdaptiveGlassRenderer._support = support;
      if (mounted) setState(() {});
    }).ignore();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
