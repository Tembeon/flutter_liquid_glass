import 'dart:ui' show Rect;

import 'package:kinesis/motion.dart';

/// How a tab scaffold's chrome on a regular width moves: the glass of the
/// bar at the top becoming the tab sidebar and back, and the bar's
/// selection lens going to the tab chosen.
abstract final class TabSidebarMotion {
  /// Moves the glass between the bar at the top and the sidebar, its
  /// [left], [top], [width] and [height] to [to], as UIKit does on an iPad
  /// (iOS 27.2 simulator, a fit of the tab sidebar passport's frames): to
  /// the sidebar it widens across first and grows down 0.105 s later, back
  /// to the bar it shrinks up first and narrows 0.13 s later. A change
  /// before a stage starts drops that stage.
  static void morph(
    MotionValue<double> left,
    MotionValue<double> top,
    MotionValue<double> width,
    MotionValue<double> height, {
    required Rect to,
    required bool toSidebar,
  }) {
    void across() {
      left.target = to.left;
      width.target = to.width;
    }

    void down() {
      top.target = to.top;
      height.target = to.height;
    }

    if (toSidebar) {
      withSpring(_showAcross, across);
      withSpring(_showDown, down, delay: _showDelay);
    } else {
      withSpring(_hideDown, down);
      withSpring(_hideAcross, across, delay: _hideDelay);
    }
  }

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

const Spring _showAcross = Spring.response(0.198, dampingRatio: 1);
const Spring _showDown = Spring.response(0.4, dampingRatio: 0.9);
const double _showDelay = 0.105;
const Spring _hideDown = Spring.response(0.287, dampingRatio: 0.83);
const Spring _hideAcross = Spring.response(0.447, dampingRatio: 1);
const double _hideDelay = 0.13;
