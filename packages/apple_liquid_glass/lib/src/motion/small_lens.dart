import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_integrator.dart';
import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The small liquid lens of a switch knob or a slider thumb.
///
/// A touch lifts it on a slightly bouncy spring (it grows and turns from
/// its solid platter into clear glass); the landing waits at least [hangTime]
/// after the lift, fades the glass back on a critically damped spring and
/// shrinks the lens on its own underdamped spring, so it dips below its
/// rest size before it settles. While it moves, the lens deforms by
/// UIKit's flex movement law for a loupe of its size
/// ([FlexSpec.loupeForSize]): speeding up it stretches along its
/// motion, squashes across it and its trailing edge lags ([shift]), each
/// eased into the loupe's movement bounds. Read from UIKit, notes
/// private; fed UIKit's own filtered motion, the law reproduces the
/// deformation UIKit records on switch knobs and slider thumbs to 1e-4 -
/// 4e-3 rms (device recordings).
///
/// The owner calls [advance] with the frame time and the lens position
/// as a function of time; the stretch filter steps once per frame of
/// [frameRate] in motion time, at the position of each frame. The
/// outputs can be read at any time.
///
/// The lens settles once every part's remaining swing is below
/// [GlassRest] and snaps onto its targets: invisible, NEAR.
@internal
class SmallLens {
  /// Creates a lens that rests at [restSize] and lifts to [liftedSize],
  /// filtering its motion at [frameRate] frames per second.
  SmallLens({
    required this.restSize,
    required this.liftedSize,
    this.frameRate = 120,
  }) : _frames = FlexSubClock(frameRate);

  /// The resting size of the lens.
  final Size restSize;

  /// The size of the fully lifted lens.
  final Size liftedSize;

  /// The frames per second of motion time the stretch filter steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// Whether the lens moves for Reduce Motion: it never lifts, as UIKit's
  /// lens does (read from UIKit, notes private), and never stretches, an
  /// approximation that is not measured.
  bool reducedMotion = false;

  /// The spring that lifts the lens: UIKit's small lens lift tuning, which
  /// with [liftVelocity] fits the device knob and thumb recordings (peak
  /// 1.12).
  static const liftSpring = Spring.response(0.27, dampingRatio: 0.625);

  /// The spring that fades the glass back to solid on landing, fitted to
  /// device recordings.
  static const unliftSpring = Spring.response(0.4);

  /// The spring that shrinks the lens on landing, fitted to device
  /// recordings: underdamped, so the lens dips under its rest size.
  static const sizeUnliftSpring = Spring.response(0.48, dampingRatio: 0.7);

  /// The spring the stretch follows its target on: [FlexSpec.smallLoupe]'s
  /// tracking spring.
  static final stretchSpring = FlexSpec.smallLoupe.trackingSpring;

  /// The lift's starting speed, in progress per second, fitted to device
  /// recordings; it applies only to a lens at rest.
  static const double liftVelocity = 18;

  /// The shortest time, in seconds, a lifted lens stays lifted: UIKit's
  /// lens tuning (read from UIKit, notes private).
  static const double hangTime = 0.22;

  final _progress = MotionValue<double>(0, spring: liftSpring);
  final _size = MotionValue<double>(0, spring: liftSpring);
  final _scaleX = MotionValue<double>(1, spring: stretchSpring);
  final _scaleY = MotionValue<double>(1, spring: stretchSpring);
  final _drift = MotionValue<double>(0, spring: stretchSpring);
  Size? _loupeSize;
  FlexSpec _loupe = FlexSpec.smallLoupe;

  final MotionTimeline _timeline = MotionTimeline();
  final FlexSubClock _frames;
  final FlexIntegrator _flex = FlexIntegrator();
  double _liftStart = -double.infinity;
  double? _previous;

  /// Seconds the size trails the lift progress by: one frame.
  double get sizeLag => _frames.frame;

  /// The rest of the lift's size progress ([GlassRest], NEAR): a swing
  /// that grows the lens by less than [GlassRest.length].
  double get _sizeRest =>
      GlassRest.length /
      math.max(
        math.max(
          liftedSize.width - restSize.width,
          liftedSize.height - restSize.height,
        ),
        1,
      );

  /// Whether the lens is lifted or lifting.
  bool get isLifted => _progress.target == 1;

  /// Lifts the lens at time [t], carrying its current value and velocity.
  /// The measured initial velocity applies only to a spring at rest.
  void lift(double t) {
    _timeline.clear();
    if (isLifted || reducedMotion) return;
    _liftStart = t;
    final progressResting = _progress.isWithin(t, GlassRest.opacity);
    _progress.retarget(t, 1, spring: liftSpring);
    if (progressResting) _progress.setVelocity(t, liftVelocity);
    final at = t + sizeLag;
    final sizeResting = _size.isWithin(at, _sizeRest);
    _size.retarget(at, 1, spring: liftSpring);
    if (sizeResting) _size.setVelocity(at, liftVelocity);
  }

  /// Lands the lens at time [t], or once it has hung for [hangTime].
  void unlift(double t) {
    if (!isLifted) return;
    final at = math.max(t, _liftStart + hangTime);
    if (at <= t) {
      _land(t);
    } else {
      _timeline.clear();
      _timeline.insert(at, _land);
    }
  }

  void _land(double t) {
    _timeline.clear();
    _progress.retarget(t, 0, spring: unliftSpring);
    _size.retarget(t, 0, spring: sizeUnliftSpring);
  }

  /// Advances the lens to time [t]: applies a landing that came due and
  /// steps the stretch filter through every frame since the last call,
  /// reading the lens position at each frame from [position].
  ///
  /// UIKit's filters weigh each frame the same whatever the frame rate, so
  /// the stretch reacts twice as fast at 120 Hz as at 60 Hz.
  void advance(double t, [double Function(double t)? position]) {
    if (position != null) {
      _frames.run(t, (double s) {
        _timeline.runDue(s);
        _sample(s, position(s));
      });
    }
    _timeline.runDue(t);
  }

  void _sample(double t, double position) {
    final previous = _previous ?? position;
    final af = _flex.step(previous, _frames.frame);
    if (reducedMotion) {
      _scaleX.retarget(t, 1);
      _scaleY.retarget(t, 1);
      _drift.retarget(t, 0);
    } else {
      final lens = size(t);
      if (lens != _loupeSize) {
        _loupeSize = lens;
        _loupe = FlexSpec.loupeForSize(lens);
      }
      final v = FlexInteraction.withMovement(
        FlexInteraction.rest,
        spec: _loupe,
        size: lens,
        acceleration: Offset(af, 0),
        velocity: Offset(_flex.vf, 0),
      );
      _scaleX.retarget(t, v.scaleX);
      _scaleY.retarget(t, v.scaleY);
      _drift.retarget(t, v.driftX);
    }
    _previous = position + shift(t);
  }

  /// Primes the deformation loop at [position] after a discontinuous
  /// programmatic move or a relayout, restoring an undeformed lens.
  void resetFlex(double t, double position) {
    _previous = position;
    _flex.reset(position);
    _scaleX.snap(t, 1);
    _scaleY.snap(t, 1);
    _drift.snap(t, 0);
  }

  /// The lift progress at time [t]: 0 solid and resting, 1 clear and
  /// lifted; it may overshoot slightly.
  double progress(double t) => _progress.valueAt(t);

  /// The lens size at time [t], stretch excluded.
  Size size(double t) {
    final q = _size.valueAt(t);
    return Size(
      restSize.width + (liftedSize.width - restSize.width) * q,
      restSize.height + (liftedSize.height - restSize.height) * q,
    );
  }

  /// The stretch along the track at time [t].
  double scaleX(double t) => _scaleX.valueAt(t);

  /// The squash across the track at time [t].
  double scaleY(double t) => math.max(1e-6, _scaleY.valueAt(t));

  /// How far the lens shows shifted along the track at time [t]: its
  /// trailing edge lags while it speeds up. The drift times the scale, as
  /// UIKit scales the drifted lens.
  double shift(double t) => _drift.valueAt(t) * _scaleX.valueAt(t);

  /// Whether the deformation loop has sampled the lens at [position]: a
  /// lens whose track moved under a held finger since its last frame has
  /// a frame of following left.
  bool hasSampled(double t, double position) {
    final previous = _previous;
    return previous == null ||
        (position + shift(t) - previous).abs() < GlassRest.length;
  }

  /// Whether what remains of the lens's motion at time [t] is invisible:
  /// every spring's remaining swing is below [GlassRest] (NEAR,
  /// invisible; [settle] snaps the rest).
  bool isSettled(double t) {
    if (!_timeline.isEmpty) return false;
    const length = GlassRest.length;
    final scale = GlassRest.scale(liftedSize.width);
    return _progress.isWithin(t, GlassRest.opacity) &&
        _size.isWithin(t, _sizeRest) &&
        _scaleX.isWithin(t, scale) &&
        (_scaleX.target - 1).abs() < scale &&
        _scaleY.isWithin(t, scale) &&
        (_scaleY.target - 1).abs() < scale &&
        _drift.isWithin(t, length) &&
        _drift.target.abs() < length;
  }

  /// Puts a settled lens onto its targets at time [t], undeformed, its
  /// filter primed at [position].
  void settle(double t, double position) {
    _progress.settle(t);
    _size.settle(t);
    resetFlex(t, position);
  }
}
