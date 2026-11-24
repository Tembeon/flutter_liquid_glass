import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';

/// How a toast moves. UIKit has no toast: every number here is this
/// package's own, chosen to read like the system's notices at the top of
/// the screen, and none is measured.
abstract final class ToastMotion {
  /// How the toasts of a toaster come, go and make room: a toast drops in
  /// from half its height above at nine tenths of its size, and leaves the
  /// same way.
  static const LayoutPlanner planner = LayoutPlanner.flip(
    spring: Spring.response(0.4, dampingRatio: 0.85),
    insert: MotionPose(offsetFraction: Offset(0, -0.5), scale: 0.9, opacity: 0),
    remove: MotionPose(offsetFraction: Offset(0, -0.5), scale: 0.9, opacity: 0),
  );

  /// The spring a toast let go of short of a dismissal returns on.
  static const Spring settle = Spring.smooth;

  /// How a toast follows a finger: freely up, resisting down.
  static const RubberBand drag = RubberBand(
    double.negativeInfinity,
    0,
    dimension: 24,
  );

  /// How far up a toast travels before a release dismisses it.
  static const double dismissTravel = 16;

  /// How fast up a release dismisses a toast however far it traveled, in
  /// points a second.
  static const double dismissVelocity = 300;
}
