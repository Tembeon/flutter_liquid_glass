import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How much a fully lifted lens's glass shrinks what lies under it, and
/// how much of the lens's long side, less its short side, the center line
/// it shrinks toward spans (`LiquidGlassSettings.backdropShrinkRim`).
typedef GlassLensShrinkage = ({double shrink, double rim});

/// Where the renderer of a lens reports how its fully lifted glass shrinks
/// what lies under it, so the control can grow the content it draws under
/// the lens against it: no shrink for a lens that draws no shrinking
/// glass.
@internal
class GlassLensShrink extends InheritedWidget {
  /// Hands [shrink] to the lens in [child].
  const GlassLensShrink({
    required this.shrink,
    required super.child,
    super.key,
  });

  /// The shrinkage the lens's renderer writes.
  final ValueNotifier<GlassLensShrinkage> shrink;

  /// No shrink.
  static const GlassLensShrinkage none = (shrink: 0, rim: 0);

  /// The shrinkage a lens at [context] reports to, or null.
  static ValueNotifier<GlassLensShrinkage>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlassLensShrink>()?.shrink;

  @override
  bool updateShouldNotify(GlassLensShrink oldWidget) =>
      shrink != oldWidget.shrink;
}
