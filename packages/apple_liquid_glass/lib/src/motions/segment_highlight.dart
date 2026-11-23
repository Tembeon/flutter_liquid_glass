import 'package:flutter/animation.dart';
import 'package:kinesis/motion.dart';

/// The dimming of a segmented control's label under the finger (UIKit
/// `UISegmentedControl`'s `UISegmentLabel`).
///
/// A touch on a segment that is not selected dims its label to
/// [dimmedOpacity] over [dimDuration]; the release, a cancel or the finger
/// leaving the control's reach returns it to full over [restoreDuration]
/// from where it is, both on [curve]. Read from the CABasicAnimations UIKit
/// adds to the label on the iOS 27.0 simulator (XCUITest taps and a 1 s
/// hold, 2026-10-14); the dimming lifts about 74 points below the bottom
/// edge (iOS 27.2). A touch on the selected segment, a finger sliding to
/// another segment and a finger coming back into reach are not measured:
/// the dimming stays on the segment the touch went down on and does not
/// return. Times are seconds.
final class SegmentHighlight extends Motion {
  /// The opacity a pressed label dims to.
  static const double dimmedOpacity = 0.2;

  /// The duration of the dimming.
  static const double dimDuration = 0.47;

  /// The duration of the return to full opacity.
  static const double restoreDuration = 0.2;

  /// The curve of both: Core Animation's default timing function.
  static const Curve curve = Curves.ease;

  late final _opacity = own(MotionValue<double>(1));
  int? _index;

  /// The segment whose label is dimmed or returning, if any.
  int? get index => _index;

  /// A touch went down on segment [index] at [t].
  void press(double t, int index) {
    advance(t);
    if (_index != index) _opacity.snap(t, 1);
    _index = index;
    _opacity.animate(
      t,
      dimmedOpacity,
      animation: const TimingCurve(dimDuration, curve: curve),
    );
  }

  /// The touch ended, was cancelled or left the control's reach at [t].
  void release(double t) {
    advance(t);
    if (_index == null || _opacity.target == 1) return;
    _opacity.animate(
      t,
      1,
      animation: const TimingCurve(restoreDuration, curve: curve),
    );
  }

  /// The opacity of segment [index]'s label.
  double opacity(int index) => index == _index ? _opacity.valueAt(now) : 1;

  @override
  void didAdvance(double t) {
    if (_index != null && _opacity.target == 1 && _opacity.restsAt(t)) {
      _index = null;
    }
  }
}
