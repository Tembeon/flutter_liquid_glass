import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/liquid.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';

/// The root of an app's glass: the theme of every control below, and the
/// renderer that draws its glass.
///
/// Put one above the app, usually around `WidgetsApp` or its home. By
/// default the glass draws with [AdaptiveGlassRenderer]: liquid glass where
/// the device draws it well, fake glass elsewhere and on the web. Without
/// a `GlassScope` or a [GlassRendererScope] above, controls draw flat: a
/// fill per role, no backdrop reads.
///
/// A subtree takes another theme from a [GlassTheme], or another renderer
/// from a [GlassRendererScope].
class GlassScope extends StatelessWidget {
  /// Applies [data] and [renderer] to [child].
  const GlassScope({
    required this.child,
    this.data = const GlassThemeData(),
    this.renderer = const AdaptiveGlassRenderer(),
    super.key,
  });

  /// The theme of the controls below.
  final GlassThemeData data;

  /// The renderer that draws the glass below.
  final GlassRenderer renderer;

  /// The subtree the theme and renderer apply to.
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassRendererScope(
    renderer: renderer,
    child: GlassTheme(data: data, child: child),
  );
}
