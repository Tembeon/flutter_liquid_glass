import 'package:kinesis/motion.dart';

/// How a tab scaffold's chrome on a regular width moves: the glass of the
/// bar at the top becoming the tab sidebar and back, and the bar's
/// selection lens going to the tab chosen.
abstract final class TabSidebarMotion {
  /// Moves the glass between the bar at the top and the sidebar: [across],
  /// how far its place and width have gone from the bar's to the
  /// sidebar's, and [down], how far its top and height have, each 0 at the
  /// bar and 1 at the sidebar. As UIKit does on an iPad (iOS 27.2
  /// simulator, a fit of the tab sidebar passport's frames): to the sidebar
  /// it widens across first and grows down 0.105 s later, back to the bar
  /// it shrinks up first and narrows 0.13 s later. A change before a stage
  /// starts drops that stage.
  static void morph(
    MotionValue<double> across,
    MotionValue<double> down, {
    required bool toSidebar,
  }) {
    final to = toSidebar ? 1.0 : 0.0;
    if (toSidebar) {
      withSpring(_showAcross, () => across.target = to);
      withSpring(_showDown, () => down.target = to, delay: _showDelay);
    } else {
      withSpring(_hideDown, () => down.target = to);
      withSpring(_hideAcross, () => across.target = to, delay: _hideDelay);
    }
  }

  /// Moves the side's [width] to [to] as it folds into the rail or out of
  /// it: the package's own spring, critically damped with a 0.2 s
  /// response. A hand that moves on while it runs aims it again on the
  /// same spring.
  static void fold(MotionValue<double> width, {required double to}) =>
      withSpring(_fold, () => width.target = to);

  /// Moves the lens, its leading edge [start] and its [width], to [toStart]
  /// and [toWidth]. UIKit's lens there is not measured, so the spring is
  /// this package's own.
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

const Spring _fold = Spring.response(0.2, dampingRatio: 1);

const Spring _showAcross = Spring.response(0.198, dampingRatio: 1);
const Spring _showDown = Spring.response(0.4, dampingRatio: 0.9);
const double _showDelay = 0.105;
const Spring _hideDown = Spring.response(0.287, dampingRatio: 0.83);
const Spring _hideAcross = Spring.response(0.447, dampingRatio: 1);
const double _hideDelay = 0.13;
