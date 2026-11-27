import 'package:kinesis/motion.dart';

/// How a floating tab bar fades away for a page that hides it and comes
/// back: in place, on a critically damped 0.3 s spring, as UIKit's
/// `setTabBarHidden(_:animated:)` fades its floating bar, the page's safe
/// area following the same curve (read off UIKit's live layers on the
/// iOS 27.2 simulator: the layout spring of the bar's other changes, 1.2e-5
/// rms).
abstract final class TabBarHidingMotion {
  /// Moves [shown], how far the bar shows from 0 to 1, to its end for
  /// [hidden].
  static void hide(MotionValue<double> shown, {required bool hidden}) =>
      withSpring(_spring, () => shown.target = hidden ? 0 : 1);
}

const Spring _spring = Spring.response(0.3);
