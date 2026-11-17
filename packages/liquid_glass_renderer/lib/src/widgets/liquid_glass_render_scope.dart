import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

/// The error of glass built at [context] with no `LiquidGlassLayer` above it.
@internal
FlutterError noLiquidGlassLayerError(BuildContext context) =>
    FlutterError.fromParts([
      ErrorSummary('No LiquidGlassLayer found.'),
      ErrorDescription(
        '${context.widget.runtimeType} draws its glass on the nearest '
        'LiquidGlassLayer above it, and there is none.',
      ),
      ErrorHint('Wrap the glass in a LiquidGlassLayer.'),
      context.describeElement('The context used was'),
    ]);

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required this.defaultAppearance,
    required super.child,
    this.fake = false,
    super.key,
  });

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance defaultAppearance;

  /// Whether the layer is consolidated fake glass: shapes register with it
  /// without backdrop filters of their own, and it paints each fake surface.
  final bool fake;

  /// The scope of the nearest layer above [context], which there must be.
  static LiquidGlassRenderScope of(BuildContext context) =>
      maybeOf(context) ?? (throw noLiquidGlassLayerError(context));

  /// Returns the nearest [LiquidGlassRenderScope] from the widget tree,
  /// or `null` if there is none.
  static LiquidGlassRenderScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();

  @override
  bool updateShouldNotify(LiquidGlassRenderScope oldWidget) =>
      oldWidget.settings != settings ||
      oldWidget.defaultAppearance != defaultAppearance ||
      oldWidget.fake != fake;
}
