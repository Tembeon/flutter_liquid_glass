import 'package:kinesis/motion.dart';

/// How a tab scaffold's chrome on a regular width moves: the selection lens
/// of the bar at the top going to the tab chosen. UIKit's lens there is not
/// measured, so the spring is this package's own.
abstract final class TabSidebarMotion {
  /// Moves the lens, its leading edge [start] and its [width], to [toStart]
  /// and [toWidth].
  static void select(
    MotionValue<double> start,
    MotionValue<double> width, {
    required double toStart,
    required double toWidth,
  }) => withSpring(_lens, () {
    start.target = toStart;
    width.target = toWidth;
  });
}

const Spring _lens = Spring.smooth;
