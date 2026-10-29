import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// The dimming of a segmented control's label under the finger (UIKit
/// `UISegmentedControl`'s `UISegmentLabel`).
///
/// A touch on a segment that is not selected dims its label to
/// [dimmedOpacity] over [dimDuration]; the release or a cancel returns it
/// to full over [restoreDuration] from where it is, both on [curve]. Read
/// from the CABasicAnimations UIKit adds to the label on the iOS 27.0
/// simulator (XCUITest taps and a 1 s hold, 2026-10-14). A touch on the
/// selected segment and a finger sliding to another segment are not
/// measured: the dimming stays on the segment the touch went down on. Times
/// are seconds.
@internal
class SegmentHighlight {
  /// The opacity a pressed label dims to.
  static const double dimmedOpacity = 0.2;

  /// The duration of the dimming.
  static const double dimDuration = 0.47;

  /// The duration of the return to full opacity.
  static const double restoreDuration = 0.2;

  /// The curve of both: Core Animation's default timing function.
  static const Curve curve = Cubic(0.25, 0.1, 0.25, 1);

  int? _index;
  double _start = 0;
  double _from = 1;
  double _to = 1;
  double _duration = 0;

  /// The segment whose label is dimmed or returning, if any.
  int? get index => _index;

  /// A touch went down on segment [index] at [t].
  void press(double t, int index) {
    final from = _index == index ? _value(t) : 1.0;
    _index = index;
    _set(t, from, dimmedOpacity, dimDuration);
  }

  /// The touch ended or was cancelled at [t].
  void release(double t) {
    if (_index == null) return;
    _set(t, _value(t), 1, restoreDuration);
  }

  void _set(double t, double from, double to, double duration) {
    _start = t;
    _from = from;
    _to = to;
    _duration = duration;
  }

  double _value(double t) {
    final p = _duration <= 0 ? 1.0 : ((t - _start) / _duration).clamp(0.0, 1.0);
    return _from + (_to - _from) * curve.transform(p);
  }

  /// The opacity of segment [index]'s label at [t].
  double opacity(double t, int index) => index == _index ? _value(t) : 1;

  /// Advances to [t]: a label back at full opacity is no longer tracked.
  void advance(double t) {
    if (_index != null && _to == 1 && t >= _start + _duration) _index = null;
  }

  /// Whether nothing changes after [t].
  bool isSettled(double t) =>
      _index == null || (_to != 1 && t >= _start + _duration);
}
