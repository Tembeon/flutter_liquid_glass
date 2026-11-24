import 'package:kinesis/motion.dart';

/// How a floating tab bar slides away for a page that hides it and comes
/// back. UIKit's `setTabBarHidden(_:animated:)` is not measured, so the
/// spring is this package's own.
abstract final class TabBarHidingMotion {
  /// Moves [shown], how far the bar shows from 0 to 1, to its end for
  /// [hidden].
  static void hide(MotionValue<double> shown, {required bool hidden}) =>
      withSpring(_spring, () => shown.target = hidden ? 0 : 1);
}

const Spring _spring = Spring.smooth;
