import 'package:kinesis/motion.dart';

/// How far a swiped row is moved toward its trailing edge (negative), and
/// the extents it settles between.
final class SwipeActionsMotion extends Motion {
  /// Creates the motion of a row at rest.
  SwipeActionsMotion({super.clock});

  // Not measured.
  static const _spring = Spring.smooth;

  /// How far the row is moved.
  late final offset = own(MotionValue<double>(0));

  /// The width of the row at the last layout.
  double rowWidth = 0;

  /// The width of the row's actions at the last layout.
  double actionsWidth = 0;

  /// Where a released row lands: the projection of the spring it settles
  /// on.
  Projection get projection => Projection.of(_spring);

  /// The finger holds the row at [value] at time [t].
  void follow(double t, double value) {
    advance(t);
    offset.snap(t, value);
  }

  /// The row settles at [value] from time [t], carrying [velocity].
  void moveTo(double t, double value, {double velocity = 0}) {
    advance(t);
    if (velocity != 0) offset.setVelocity(t, velocity);
    offset.retarget(t, value, spring: _spring);
  }
}
