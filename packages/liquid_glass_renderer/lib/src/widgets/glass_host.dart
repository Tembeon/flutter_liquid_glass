import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_place.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:meta/meta.dart';

/// Where the glass below draws: on a layer, in one of its blend groups, or
/// inside the body of another glass.
@internal
class GlassHost extends InheritedWidget {
  /// Glass below draws at [place].
  const GlassHost({required this.place, required super.child, super.key});

  /// Where the glass below draws.
  final GlassPlace place;

  /// The nearest host above [context], or null outside every layer.
  static GlassHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassHost>();

  @override
  bool updateShouldNotify(GlassHost oldWidget) => place != oldWidget.place;
}

/// A layer of its own, with the settings of the layer the body around
/// [context] draws on, for glass in that body, which [builder] builds.
Widget nestedGlassLayer(BuildContext context, WidgetBuilder builder) {
  final scope = LiquidGlassRenderScope.of(context);
  return LiquidGlassLayer(
    settings: scope.settings,
    defaultAppearance: scope.defaultAppearance,
    fake: scope.fake,
    child: Builder(builder: builder),
  );
}
