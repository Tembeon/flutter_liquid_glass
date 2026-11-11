import 'package:apple_liquid_glass/src/surfaces/flat.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/widgets.dart';

/// Sets the [GlassRenderer] that draws every glass surface, group and
/// scroll edge below it.
///
/// An app usually gets one from the root widget of the umbrella library,
/// `GlassScope`; this scope sets a renderer of its own, or another one for
/// a subtree. Without a scope above, surfaces draw with the flat renderer:
/// a fill per role, no backdrop reads.
///
/// A surface depends on the renderer only: changing it rebuilds the
/// surfaces, which keep their content and its state.
class GlassRendererScope extends InheritedWidget {
  /// Draws the glass in [child] with [renderer].
  const GlassRendererScope({
    required this.renderer,
    required super.child,
    super.key,
  });

  /// The renderer of the glass below.
  final GlassRenderer renderer;

  /// The renderer at [context], or the flat renderer without a scope above.
  static GlassRenderer of(BuildContext context) =>
      maybeOf(context) ?? const FlatGlassRenderer();

  /// The renderer at [context], or null without a scope above.
  static GlassRenderer? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassRendererScope>()
      ?.renderer;

  @override
  bool updateShouldNotify(GlassRendererScope oldWidget) =>
      renderer != oldWidget.renderer;
}
