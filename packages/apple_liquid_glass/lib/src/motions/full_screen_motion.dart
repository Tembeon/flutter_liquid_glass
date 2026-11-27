import 'package:kinesis/motion.dart';

/// A full-screen presentation's slide: [progress] runs from 0, the page
/// below the screen, to 1, the page covering it.
///
/// UIKit's `coverVertical` presentation and dismissal, frame by frame on
/// the iOS 27.2 simulator (presentation passport): a critically damped
/// spring of response 0.344, the sheet's, which UIKit cuts at 0.5 s a point
/// short of its end; this one runs on to rest within a tenth of a point.
final class FullScreenMotion extends PresentedProgress {
  /// Creates the motion of a page [height] points tall that is not shown
  /// yet, on [clock].
  FullScreenMotion({required double height, super.clock})
    : super(openSpring: spring, restDistance: MotionRest.scale(height));

  /// The spring the page slides up and down on.
  static const spring = Spring.response(0.344, dampingRatio: 1);

  @override
  bool get needsFullFrameRate => true;
}
