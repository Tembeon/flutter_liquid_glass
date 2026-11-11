import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// What turns a tab bar into a circle and back: the same bar throughout,
/// its glass and content following [morph], whatever asks for it (a scroll,
/// a search).
@internal
abstract class BarCollapse {
  /// The way from the bar (0) to the circle (1); a spring may overshoot both.
  MotionSelection<double> get morph;

  /// How far a finger has lifted the circle, 0 to 1, or null if it never
  /// does.
  MotionSelection<double>? get press;

  /// The circle in the bar's box of [size].
  Rect circleIn(Size size);

  /// Whether a finger on the bar now means the circle, not a tab.
  bool get takesFinger;

  /// A finger went down on the circle at [x] along the bar, at time [t].
  void pressDown(double t, double x);

  /// The finger moved to [x]; true on the move that hands it to the bar's
  /// selection drag.
  bool pressMove(double t, double x);

  /// The finger lifted without having moved along the bar.
  void pressUp(double t);

  /// The touch was taken away.
  void pressCancel(double t);

  /// A screen reader activated the circle.
  void activate();

  /// The collapse of the bar around [context], or null.
  static BarCollapse? maybeOf(BuildContext context) =>
      BarCollapseScope.maybeOf(context)?.collapse;
}

/// Gives the tab bar below it its [collapse]; a bar under one has a box as
/// wide as it is given, and draws its glass where the collapse says.
@internal
class BarCollapseScope extends InheritedWidget {
  /// Creates a scope.
  const BarCollapseScope({
    required this.collapse,
    required this.hosted,
    required super.child,
    super.key,
  });

  /// The bar's collapse.
  final BarCollapse collapse;

  /// Whether the bar hosts an accessory or a search, which makes it span the
  /// width it is given whatever its tabs.
  final bool hosted;

  /// The nearest scope around [context], or null.
  static BarCollapseScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarCollapseScope>();

  @override
  bool updateShouldNotify(BarCollapseScope oldWidget) =>
      !identical(collapse, oldWidget.collapse) || hosted != oldWidget.hosted;
}
