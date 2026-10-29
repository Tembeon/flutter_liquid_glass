import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The tuning of a page sliding onto and off a navigation stack.
///
/// Read from UIKit on iOS 27 (`UINavigationController`'s transition and
/// its interactive pop; notes private) where marked, else fitted to the
/// iPhone 16 Pro device recordings.
@internal
abstract final class NavigationTuning {
  /// The spring a page slides in and out on without a finger: critically
  /// damped, response 0.3 (read from UIKit).
  static const pushSpring = Spring.response(0.3);

  /// The spring a page settles on after a finger lets it go, popping or
  /// returning: damping 0.85, response 0.3 (read from UIKit; the recorded
  /// completion overshoots by the 0.6 percent it predicts).
  static const interactiveSpring = Spring.response(0.3, dampingRatio: 0.85);

  /// The speed a push or pop without a finger starts at, in page widths per
  /// second: the page leaves its start at full speed. UIKit gives the
  /// spring an impulse of 0.02 s (read), which makes 0.02 (2 pi / 0.3)^2 =
  /// 8.77 (fits the device push rows within 0.9 pt).
  static const double pushVelocity = 8.77;

  /// The share of the page the page underneath keeps on screen: it moves by
  /// the width less 0.7 of it, rounded (read from UIKit).
  static const double underneathKeeps = 0.7;

  /// The opacity of the black over the page underneath when the page on
  /// top covers it fully; it follows the top page's progress linearly
  /// (read from UIKit; iPhone 16 Pro held edge samples agree).
  static const double underDimOpacity = 0.1;

  /// The corner radius of a sliding page where the platform reports no
  /// display corner radius: the moving pages are cards with the display's
  /// corners, square again at rest (read from UIKit; 62 fits a simulator
  /// film of an iPhone 17 Pro).
  static const double fallbackCardRadius = 62;

  /// The shadow of a sliding card: black at 4 percent, radius 12, offset
  /// (0, -3) (read from UIKit; a film is still due).
  static const double cardShadowOpacity = 0.04;

  /// See [cardShadowOpacity].
  static const double cardShadowRadius = 12;

  /// See [cardShadowOpacity].
  static const double cardShadowOffset = -3;

  /// The width of the screen edge an interactive pop starts from: 13
  /// points, or 9 percent of the portrait width on phones with thin bezels
  /// (read from UIKit; which branch an iPhone 16 Pro takes is not read, the
  /// port takes the thin-bezel one).
  static const double edgeShare = 0.09;

  /// How far a finger on the edge moves before the pop begins (read from
  /// UIKit).
  static const double edgeHysteresis = 15;

  /// How far a finger away from the edge moves along the page before the
  /// pop begins, or the wrong way before it fails (read from UIKit; the
  /// content swipe of `UINavigationController`).
  static const double contentHysteresis = 30;

  /// The most a finger away from the edge may move across the page before
  /// the pop begins: min(25, 0.8 |tx| + 10) points, which a straight drag
  /// passes up to about 40 degrees (read from UIKit). On a vertical list
  /// the list's own drag takes steeper ones first; the device cut-off there
  /// is 29 to 30 degrees (device recordings).
  static double contentFunnel(double along) =>
      math.min(25, 0.8 * along.abs() + 10);

  /// How far a page dragged past either end of its travel moves, at most,
  /// as a share of its width, with [rubberBandCoefficient]: UIKit rubber
  /// bands the progress outside 0 - 1 (read from UIKit; the coefficient is
  /// UIKit's default for scrolling, assumed for touch).
  static const double rubberBandExtent = 0.5;

  /// See [rubberBandExtent].
  static const double rubberBandCoefficient = 0.55;

  /// The share of an interactive pop's progress the navigation bar's
  /// capsules lean toward their places on the page below while the finger
  /// drags the page: half the way when the page is fully out (device fit
  /// over four swipes, 0.16 - 0.27 points rms).
  static const double barDrift = 0.5;

  /// The seconds a push or pop without a finger cross-fades for under
  /// Prefer Cross-Fade Transitions (`GlassTraits.prefersCrossFade`), on
  /// [crossFadeCurve], instead of sliding; an edge swipe still slides (read
  /// from UIKit).
  static const double crossFadeDuration = 0.5;

  /// The easing of the cross-fade: UIView's default animation curve.
  static const Curve crossFadeCurve = Curves.easeInOut;

  /// The drag progress outside 0 - 1 rubber banded as UIKit does.
  static double rubberBand(double progress) {
    double band(double over) =>
        rubberBandExtent *
        (1 - 1 / (rubberBandCoefficient * over / rubberBandExtent + 1));
    if (progress > 1) return 1 + band(progress - 1);
    if (progress < 0) return -band(-progress);
    return progress;
  }
}

/// The time a navigation transition counts from, shared by the page's slide
/// and the bar: the push or pop [call], unless the first frame after it
/// came more than a display period later, in which case the motion starts
/// one period before that frame, so a slow first frame delays the motion
/// and skips none of it (navigation pages passport). Without a frame
/// period yet, the call.
@internal
double transitionOrigin({
  required double call,
  required double firstFrame,
  required double? framePeriod,
}) => framePeriod == null ? call : math.max(call, firstFrame - framePeriod);

/// Predicts whether an interactive back swipe completes.
///
/// Read from UIKit (notes private), then replayed from iPhone 16 Pro,
/// iOS 27.0.1 touches: pan speed mixes the last two movement speeds with
/// weights 0.2 / 0.8. The last three normalized speeds and accelerations
/// predict progress after 0.35 s. The page pops past the smaller of
/// 187.5 points and half its width. Holding a finger keeps its last pan
/// speed; a lift updates the statistics without adding a stationary move.
/// An uninterrupted fast flick also boosts the spring's starting speed
/// by [flickBoost] until its mean speed falls below [flickThreshold].
///
/// Supply positions before recognition with [addPosition], call [begin]
/// when the drag wins, then [update] after each page movement and at lift.
/// Times are monotonic seconds; positions increase toward the popping side.
/// The equations reproduce the recorded inputs; platform event timing and
/// gesture admission can differ (NEAR).
@internal
class NavigationPopMotion {
  /// Creates a predictor for a page [width] points wide.
  NavigationPopMotion(this.width) : assert(width > 0, 'a page has a width');

  /// The page width captured when the pointer starts.
  final double width;

  /// The native prediction interval, in seconds (read from UIKit).
  static const double predictionTime = 0.35;

  /// The maximum projected distance needed to pop, in points.
  static const double predictionDistance = 187.5;

  /// The projected fraction needed on narrower pages.
  static const double predictionFraction = 0.5;

  /// The mean speed below which the initial flick phase ends, in widths/s.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickThreshold = 1.5;

  /// The settle-speed boost while the initial flick phase persists.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickBoost = 4.25;

  final _velocities = List<double>.filled(3, 0);
  final _accelerations = List<double>.filled(3, 0);
  double? _positionTime;
  double _position = 0;
  double? _rawVelocity;
  double _panVelocity = 0;
  double _previousVelocity = 0;
  double _previousAcceleration = 0;
  double _previousDisplacement = 0;
  double _previousTime = 0;
  double _attemptTime = 0;
  bool _changed = false;
  bool _flick = true;
  int _sampleCount = 0;
  double _averageVelocity = 0;
  double _averageAcceleration = 0;

  /// The number of accepted statistics samples, including recognition.
  int get sampleCount => _sampleCount;

  double get _currentVelocity => _panVelocity / width;

  /// The last accepted pan speed in page widths per second.
  double get velocity => _previousVelocity;

  /// The initial settle speed, including an uninterrupted fast flick.
  double get settleVelocity => velocity * (_flick ? flickBoost : 1);

  /// The mean of the last three accepted speeds, in widths per second.
  double get averageVelocity => _averageVelocity;

  /// The mean of the last three limited accelerations, in widths/s^2.
  double get averageAcceleration => _averageAcceleration;

  /// Records a pointer position, including movement before recognition.
  /// A lift does not add a position: UIKit preserves the last move speed.
  void addPosition(double t, double x) {
    final previous = _positionTime;
    if (previous != null) {
      final dt = t - previous;
      if (dt > 0) {
        final raw = dt >= 0.001 ? (x - _position) / dt : 0.0;
        final old = _rawVelocity;
        _panVelocity = old == null ? raw : 0.2 * raw + 0.8 * old;
        _rawVelocity = raw;
      }
    }
    _positionTime = t;
    _position = x;
  }

  /// Starts statistics at recognition, with the current drag [progress].
  void begin(double t, {double progress = 0}) {
    _previousTime = t;
    _attemptTime = t;
    _previousDisplacement = progress;
    _previousVelocity = _currentVelocity;
    _previousAcceleration = 0;
    _averageVelocity = _currentVelocity;
    _averageAcceleration = 0;
    _velocities.fillRange(0, 3, 0);
    _accelerations.fillRange(0, 3, 0);
    _velocities[0] = _currentVelocity;
    _sampleCount = 1;
    _changed = false;
    _flick = true;
  }

  /// Samples movement or a lift at [t], with the actual page [progress].
  /// Set [ending] for a lift so a never-updated drag cannot complete.
  void update(double t, double progress, {bool ending = false}) {
    if (_sampleCount == 0) return;
    if (!ending && t > _attemptTime) _changed = true;
    final attempt = t - _attemptTime;
    _attemptTime = t;
    final displacement = progress < 0 ? 0.0 : progress;
    if (attempt < 0.01 &&
        (attempt <= 0.001 || displacement == _previousDisplacement)) {
      return;
    }
    final dt = t - _previousTime;
    if (dt <= 0) return;
    final v = _currentVelocity;
    final acceleration = (v - _previousVelocity) / dt;
    final limited =
        _previousAcceleration +
        (acceleration - _previousAcceleration).clamp(-5.0, 5.0);
    final slot = _sampleCount % 3;
    final count = math.min(3, _sampleCount);
    final divisor = math.min(3, _sampleCount + 1);
    _averageVelocity =
        (v +
            _averageVelocity * count -
            (_sampleCount >= 3 ? _velocities[slot] : 0)) /
        divisor;
    _averageAcceleration =
        (limited +
            _averageAcceleration * count -
            (_sampleCount >= 3 ? _accelerations[slot] : 0)) /
        divisor;
    if (_averageVelocity.abs() < flickThreshold) _flick = false;
    _velocities[slot] = v;
    _accelerations[slot] = limited;
    _previousVelocity = v;
    _previousAcceleration = limited;
    _previousDisplacement = displacement;
    _previousTime = t;
    _sampleCount++;
  }

  /// Whether the page released at [progress] completes its pop.
  bool shouldPop(double progress) {
    if (!_changed) return false;
    if (_sampleCount < 3) return _averageVelocity > 0;
    final projected =
        progress +
        predictionTime * _averageVelocity +
        0.5 * predictionTime * predictionTime * _averageAcceleration;
    return projected > math.min(predictionDistance / width, predictionFraction);
  }
}
