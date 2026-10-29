import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// The highlight of a tappable list row (UIKit `UITableViewCell` in a
/// table), as a function of the touch and time.
///
/// Inside a scroll view the highlight waits [touchDelay] after the touch
/// went down; a tap released sooner shows it at the release. It appears
/// at full strength, without a fade. A scroll that takes the touch removes
/// it at once. A tap's release fades it out over [fadeDuration] on
/// [fadeCurve]: UIKit keeps the tapped row selected until the app
/// deselects it, and this is `deselectRow(at:animated: true)`, the fade of
/// the standard tap handler.
///
/// Measured on the iOS 27.0 simulator (UITableView inset grouped, taps
/// and holds through XCUITest, 60 Hz): the delay is the scroll view's
/// `_touchDelayForScrollDetection`, 0.15 s, read from UIKit (notes
/// private), and the highlight showed 0.155 - 0.166 s after the touch (one
/// frame later); the fade is the CABasicAnimation UIKit adds, read from
/// the layer. Times are seconds.
@internal
class ListRowHighlight {
  /// The delay between a touch and the highlight inside a scroll view.
  static const double touchDelay = 0.15;

  /// The duration of the fade after a tap.
  static const double fadeDuration = 0.5;

  /// The curve of the fade after a tap: UIKit's ease-in-ease-out.
  static const Curve fadeCurve = Cubic(0.42, 0, 0.58, 1);

  double? _showAt;
  double? _fadeFrom;
  double? _undecidedUntil;

  /// A touch went down at [t]; until a tap claims it ([press]) or
  /// [touchDelay] passes, the motion keeps time without drawing.
  void touch(double t) => _undecidedUntil = t + touchDelay;

  /// The touch that went down at [downTime] may become a tap: the
  /// highlight shows at [downTime] plus [delay], or at [now] when that is
  /// later.
  void press(double downTime, double now, {double delay = touchDelay}) {
    _undecidedUntil = null;
    _fadeFrom = null;
    final at = downTime + delay;
    _showAt = at > now ? at : now;
  }

  /// The tap was released at [t]: the highlight shows if it still waited,
  /// then fades out.
  void release(double t) {
    if (_showAt == null) return;
    _showAt = null;
    _fadeFrom = t;
  }

  /// The touch was taken by a scroll or lost: the highlight goes at once.
  void cancel() {
    _undecidedUntil = null;
    _showAt = null;
    _fadeFrom = null;
  }

  /// The highlight's strength at [t], 0 to 1.
  double opacity(double t) {
    final show = _showAt;
    if (show != null) return t >= show ? 1 : 0;
    final from = _fadeFrom;
    if (from == null) return 0;
    final p = ((t - from) / fadeDuration).clamp(0.0, 1.0);
    return 1 - fadeCurve.transform(p);
  }

  /// Whether nothing changes after [t].
  bool isSettled(double t) {
    final undecided = _undecidedUntil;
    if (undecided != null && t < undecided) return false;
    final show = _showAt;
    if (show != null) return t >= show;
    final from = _fadeFrom;
    return from == null || t >= from + fadeDuration;
  }

  /// The time before which the highlight shows nothing new, or null while
  /// it changes every frame.
  double? wakeTime(double t) {
    final show = _showAt;
    if (show != null) return t < show ? show : null;
    final undecided = _undecidedUntil;
    if (_fadeFrom == null && undecided != null && t < undecided) {
      return undecided;
    }
    return null;
  }
}
