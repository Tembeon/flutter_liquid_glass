import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where the renderer of a lens reports how much its fully lifted glass
/// shrinks what lies under it about the lens's center line, so the control
/// can grow the content it draws under the lens against it: 0 for a lens
/// that draws no shrinking glass.
@internal
class GlassLensShrink extends InheritedWidget {
  /// Hands [shrink] to the lens in [child].
  const GlassLensShrink({
    required this.shrink,
    required super.child,
    super.key,
  });

  /// The shrink the lens's renderer writes.
  final ValueNotifier<double> shrink;

  /// The shrink a lens at [context] reports to, or null.
  static ValueNotifier<double>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlassLensShrink>()?.shrink;

  @override
  bool updateShouldNotify(GlassLensShrink oldWidget) =>
      shrink != oldWidget.shrink;
}
