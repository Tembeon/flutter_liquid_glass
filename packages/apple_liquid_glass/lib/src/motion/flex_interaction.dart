import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The four channels a flex deforms a surface by: the scale of its width
/// and height and the drift of its center.
typedef FlexValues = ({
  double scaleX,
  double scaleY,
  double driftX,
  double driftY,
});

/// UIKit's flex interaction: the one machine that lifts, stretches and
/// shifts every flexible glass surface under a finger.
///
/// A finger that touches down activates the flex, after
/// [activationDelay]. While it is active the four channels (scale x,
/// scale y, drift x, drift y) chase [dynamicTargets] on the spec's
/// tracking spring; when the finger lifts they return to rest on its
/// scale spring. The spec comes from the surface's size
/// ([FlexSpec.forSize]). With [glows] the interaction also carries
/// the touch glow: a wash over the surface and a little glow under the
/// finger.
///
/// The menu variant of the same machine is [menuTargets] with its pulse
/// channel; the open menu drives those itself. Each of the four channels
/// moves on the spec's [FlexSpec.channelSpring] ([chaseFlexChannel]).
///
/// Times are seconds, positions pixels in the surface's own space.
///
/// A surface settles ([isSettled]) once every part's remaining swing is below
/// [GlassRest] (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
@internal
class FlexInteraction {
  /// Creates the flex of a surface of [size] at rest.
  ///
  /// Delayed reactions go on [timeline] when one is given, so they run in
  /// order with the owner's own; otherwise on a timeline of the
  /// interaction's, run by [advance].
  FlexInteraction({
    required Size size,
    this.stretches = true,
    this.glows = false,
    this.activationDelay = 0,
    MotionTimeline? timeline,
  }) : _size = size,
       _spec = FlexSpec.forSize(size),
       _timeline = timeline ?? MotionTimeline(now: 0),
       _ownsTimeline = timeline == null;

  /// The share of the stretch threshold a finger travelling inside the
  /// surface counts: inside, the stretch grows by a quarter of what the
  /// same travel beyond the edge adds. Read from UIKit, notes private;
  /// replayed by the glass button's drag-off captures.
  static const double inBoundsWeight = 0.25;

  /// The slope at which a movement scale enters its soft limit
  /// ([softClamp]). Read from UIKit, notes private.
  static const double softness = 0.55;

  /// The time constant of the glow fading in, in seconds.
  static const double glowTime = 0.023;

  /// The spring the glow fades out and the little glow grows on.
  static const glowSpring = Spring.response(0.5);

  /// The diameter of the little glow at the touch point.
  static const double littleGlowSize = 66;

  /// How much the little glow grows while it fades out.
  static const double littleGlowGrowth = 4;

  /// A flex at rest.
  static const FlexValues rest = (
    scaleX: 1,
    scaleY: 1,
    driftX: 0,
    driftY: 0,
  );

  /// Whether a dragging finger stretches the surface and shifts it after
  /// the finger; without it the flex only lifts.
  final bool stretches;

  /// Whether the interaction carries the touch glow.
  final bool glows;

  /// Seconds between the touch and the flex becoming active.
  final double activationDelay;

  /// Whether the surface moves for Reduce Motion: it still glows but
  /// never lifts, stretches or shifts. This approximates the platform's
  /// behavior; it is not measured.
  bool reducedMotion = false;

  final MotionTimeline _timeline;
  final bool _ownsTimeline;
  Size _size;
  FlexSpec _spec;
  late Spring _channelSpring = _spec.channelSpring;
  final _scaleX = MotionValue<double>(1);
  final _scaleY = MotionValue<double>(1);
  final _driftX = MotionValue<double>(0);
  final _driftY = MotionValue<double>(0);

  List<MotionValue<double>> get _channels => [
    _scaleX,
    _scaleY,
    _driftX,
    _driftY,
  ];
  final _glowOut = MotionValue<double>(0, spring: glowSpring);
  final _littleScale = MotionValue<double>(1, spring: glowSpring);
  final _glowX = MotionValue<double>(
    0,
    spring: FlexSpec.ultraSmall.trackingSpring,
  );
  final _glowY = MotionValue<double>(
    0,
    spring: FlexSpec.ultraSmall.trackingSpring,
  );

  Offset? _down;
  Offset _position = Offset.zero;
  bool _active = false;
  int _generation = 0;
  double _glowStart = 0;
  double _glowFrom = 0;

  /// The size of the surface at rest.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = FlexSpec.forSize(value);
    _channelSpring = _spec.channelSpring;
  }

  /// The deformation tuning UIKit derives for [size].
  FlexSpec get spec => _spec;

  /// The scale of the surface fully lifted.
  double get liftedScale => _spec.liftScaleFor(_size);

  /// Whether a finger is down on the surface.
  bool get isPressed => _down != null;

  /// Whether the flex follows the finger: from [activationDelay] after the
  /// touch until the finger lifts.
  bool get isActive => _active;

  /// Runs the reactions that came due by time [t] on the interaction's own
  /// timeline; an owner that passed its timeline runs it itself.
  void advance(double t) {
    if (_ownsTimeline) _timeline.runDue(t);
  }

  /// A finger touched the surface at [position] at time [t].
  void pointerDown(double t, Offset position) {
    advance(t);
    if (glows) _glowFrom = glow(t);
    _down = position;
    _position = position;
    if (glows) {
      _glowStart = t;
      _littleScale.snap(t, 1);
      final at = _clamped(position);
      _glowX.snap(t, at.dx);
      _glowY.snap(t, at.dy);
    }
    final generation = ++_generation;
    if (activationDelay <= 0) {
      _activate(t);
    } else {
      _timeline.at(t + activationDelay, (double s) {
        if (generation == _generation && _down != null) _activate(s);
      });
    }
  }

  /// The finger moved to [position] at time [t].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (_down == null) return;
    _position = position;
    if (_active) _retarget(t, targets, tracking: true);
    if (glows) {
      final at = _clamped(position);
      final tracking = _spec.trackingSpring;
      _glowX.retarget(t, at.dx, spring: tracking);
      _glowY.retarget(t, at.dy, spring: tracking);
    }
  }

  /// The finger lifted at time [t], at [position] when given.
  void pointerUp(double t, [Offset? position]) {
    if (position != null) pointerMove(t, position);
    release(t);
  }

  /// The touch was cancelled at time [t].
  void pointerCancel(double t) => release(t);

  /// Ends the touch at time [t]: the channels return to rest on the
  /// spec's scale spring and the glow fades.
  void release(double t) {
    advance(t);
    _generation++;
    final strength = glow(t);
    final wasDown = _down != null;
    _down = null;
    _active = false;
    _retarget(t, rest, tracking: false);
    if (glows && wasDown) {
      _glowOut.snap(t, strength);
      _glowOut.retarget(t, 0);
      _littleScale.retarget(t, littleGlowGrowth);
    }
  }

  void _activate(double t) {
    _active = true;
    _retarget(t, targets, tracking: true);
  }

  void _retarget(double t, FlexValues to, {required bool tracking}) {
    final spring = _channelSpring;
    chaseFlexChannel(_scaleX, t, to.scaleX, spring, tracking: tracking);
    chaseFlexChannel(_scaleY, t, to.scaleY, spring, tracking: tracking);
    chaseFlexChannel(_driftX, t, to.driftX, spring, tracking: tracking);
    chaseFlexChannel(_driftY, t, to.driftY, spring, tracking: tracking);
  }

  /// What the channels head to now: [dynamicTargets] of the finger while
  /// the flex is active, [rest] otherwise.
  FlexValues get targets {
    final down = _down;
    if (!_active || down == null || reducedMotion) return rest;
    final at = _position;
    return dynamicTargets(
      spec: _spec,
      size: _size,
      translation: at - down,
      inBounds: _clamped(at) - down,
      stretch: stretches,
    );
  }

  /// The channels at time [t].
  FlexValues values(double t) => (
    scaleX: _scaleX.valueAt(t),
    scaleY: _scaleY.valueAt(t),
    driftX: _driftX.valueAt(t),
    driftY: _driftY.valueAt(t),
  );

  /// The horizontal scale at time [t].
  double scaleX(double t) => _scaleX.valueAt(t);

  /// The vertical scale at time [t].
  double scaleY(double t) => _scaleY.valueAt(t);

  /// The lift at time [t]: the mean of the two scales, which the stretch
  /// leaves alone.
  double scale(double t) => (_scaleX.valueAt(t) + _scaleY.valueAt(t)) / 2;

  /// How far the surface's center shows shifted at time [t]: the drift
  /// times the scale, as UIKit scales the drifted surface.
  ///
  /// Replays the glass button's drag-off captures to 0.03 pt rms on the
  /// simulator and 0.07 on the device (120 x 44, a 150 pt drag).
  Offset translation(double t) => Offset(
    _driftX.valueAt(t) * _scaleX.valueAt(t),
    _driftY.valueAt(t) * _scaleY.valueAt(t),
  );

  /// The glow strength at time [t], 0 to 1.
  double glow(double t) {
    if (!glows) return 0;
    if (_down != null) {
      return 1 - (1 - _glowFrom) * math.exp(-(t - _glowStart) / glowTime);
    }
    return _glowOut.valueAt(t).clamp(0.0, 1.0);
  }

  /// The opacity of the glow over the whole surface at time [t].
  double bigGlowOpacity(double t) => glow(t) * _spec.bigGlowOpacity;

  /// The opacity of the little glow at the touch point at time [t].
  double littleGlowOpacity(double t) => glow(t) * _spec.littleGlowOpacity;

  /// The scale of the little glow at time [t].
  double littleGlowScale(double t) => _littleScale.valueAt(t);

  /// The center of the little glow at time [t].
  Offset littleGlowCenter(double t) =>
      Offset(_glowX.valueAt(t), _glowY.valueAt(t));

  /// Whether what remains of the surface's motion at time [t] is
  /// invisible ([GlassRest], NEAR): the scales' swing over the surface's
  /// longer side, the drifts' swing and the glow's change (fading in under
  /// a finger or out after it) below a visible step, and no reaction
  /// pending. A finger held still counts: a held surface sleeps until the
  /// finger moves or lifts.
  bool isSettled(double t) => _shapeSettled(t) && (!glows || _glowSettled(t));

  /// Whether everything but the glow has settled at time [t] while the
  /// glow still changes ([isSettled]).
  bool isGlowOnly(double t) => glows && _shapeSettled(t) && !_glowSettled(t);

  bool _shapeSettled(double t) {
    if (_ownsTimeline && !_timeline.isEmpty) return false;
    const length = GlassRest.length;
    final scale = GlassRest.scale(math.max(_size.width, _size.height));
    return _scaleX.isWithin(t, scale) &&
        _scaleY.isWithin(t, scale) &&
        _driftX.isWithin(t, length) &&
        _driftY.isWithin(t, length);
  }

  bool _glowSettled(double t) {
    if (_down == null) return _glowOut.isWithin(t, GlassRest.opacity);
    const length = GlassRest.length;
    final peak = math.max(_spec.bigGlowOpacity, _spec.littleGlowOpacity);
    return (1 - glow(t)) * peak < GlassRest.opacity &&
        _glowX.isWithin(t, length) &&
        _glowY.isWithin(t, length);
  }

  /// Puts a settled surface onto its targets at time [t]; a held glow
  /// shows at full strength. A glow that still changes keeps changing.
  void settle(double t) {
    for (final channel in _channels) {
      channel.settle(t);
    }
    if (!glows || !_glowSettled(t)) return;
    _glowX.settle(t);
    _glowY.settle(t);
    if (_down != null) {
      _glowFrom = 1;
      _glowStart = t;
    } else {
      _glowOut.snap(t, 0);
      _littleScale.settle(t);
    }
  }

  Offset _clamped(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));

  /// The targets of UIKit's dynamic flex for a finger on a surface of
  /// [size] with tuning [spec].
  ///
  /// [translation] is the finger's travel since the touch-down,
  /// [inBounds] the same travel with the finger clamped into the surface.
  /// With [lift] both scales start from the lift over the long side L,
  /// `s = (L + liftScalePoints) / L`; with [stretch], along x (y likewise
  /// with H, the scales swapped):
  ///
  /// ```text
  /// kx = |it.x| / (4 T) + (|t.x| - |it.x|) / T   (0 when t.x is 0)
  /// sx = s + kx, sy = s - kx, dx = sign(t.x) kx W
  /// ```
  ///
  /// T the spec's stretch threshold. Read from UIKit, notes private.
  static FlexValues dynamicTargets({
    required FlexSpec spec,
    required Size size,
    required Offset translation,
    required Offset inBounds,
    bool lift = true,
    bool stretch = true,
  }) {
    if (size.width <= 0 || size.height <= 0) return rest;
    final s = lift ? spec.liftScaleFor(size) : 1.0;
    var sx = s;
    var sy = s;
    var dx = 0.0;
    var dy = 0.0;
    final threshold = spec.scaleDistanceThreshold;
    if (stretch && threshold > 0) {
      final kx = stretchOf(translation.dx, inBounds.dx, threshold);
      final ky = stretchOf(translation.dy, inBounds.dy, threshold);
      sx += kx - ky;
      sy += ky - kx;
      dx = _sign(translation.dx) * kx * size.width;
      dy = _sign(translation.dy) * ky * size.height;
    }
    return (scaleX: sx, scaleY: sy, driftX: dx, driftY: dy);
  }

  /// The stretch along one axis of a finger that travelled [travel] since
  /// the touch-down, [inBounds] of it inside the surface:
  /// `|it| / (4 T) + (|t| - |it|) / T`, zero without travel.
  static double stretchOf(double travel, double inBounds, double threshold) {
    if (travel == 0) return 0;
    final inside = inBounds.abs();
    return (inBoundsWeight * inside + travel.abs() - inside) / threshold;
  }

  /// The scales movement may take a surface [extent] long to along that
  /// axis: the spec's movement points either way, within its movement
  /// scale bounds. Read from UIKit, notes private.
  static ({double low, double high}) movementBounds(
    FlexSpec spec,
    double extent,
  ) {
    final points = spec.movementScalePoints;
    return (
      low: math.max(spec.movementMinScale, (extent - points) / extent),
      high: math.min(spec.movementMaxScale, (extent + points) / extent),
    );
  }

  /// [value] eased into [low] .. [high]: unchanged inside, and beyond an
  /// end it approaches a third of the range further out, entering at the
  /// slope [softness]. Read from UIKit, notes private; the easing curve is
  /// a hyperbolic tangent (inferred: the library call's name is not
  /// recoverable, its ends and slope are).
  static double softClamp(double value, double low, double high) {
    final margin = (high - low) / 3;
    if (margin <= 0) return value.clamp(low, high);
    if (value > high) {
      return high + margin * _tanh(softness * (value - high) / margin);
    }
    if (value < low) {
      return low + margin * _tanh(softness * (value - low) / margin);
    }
    return value;
  }

  /// [base] with the movement of a surface of [size] added: [acceleration]
  /// is the filtered rate of change of its speed along each axis and
  /// [velocity] its filtered velocity, as the flex integrator reports
  /// them.
  ///
  /// Along x (y likewise, the axes swapped), with m = a.x / N (N the
  /// spec's movement normalization) and the bounds of [movementBounds]:
  ///
  /// ```text
  /// Lx = soft(1 + m (hiX - 1)), sx += Lx - 1, sy += soft(1 + m (loY - 1)) - 1
  /// dx += (1 - Lx) W / 2 sign(v.x)
  /// ```
  ///
  /// so a surface speeding up grows along its motion, narrows across it
  /// and its trailing edge lags. Read from UIKit, notes private; the
  /// lens deformation measured on UISegmentedControl and UITabBar follows
  /// the same law with [FlexSpec.loupeForSize].
  static FlexValues withMovement(
    FlexValues base, {
    required FlexSpec spec,
    required Size size,
    required Offset acceleration,
    required Offset velocity,
  }) {
    final n = spec.movementNormalizationFactor;
    final x = movementBounds(spec, size.width);
    final y = movementBounds(spec, size.height);
    var (:scaleX, :scaleY, :driftX, :driftY) = base;
    final mx = acceleration.dx / n;
    if (mx != 0 && !mx.isNaN) {
      final along = softClamp(1 + mx * (x.high - 1), x.low, x.high);
      scaleX += along - 1;
      driftX += (1 - along) * 0.5 * size.width * _sign(velocity.dx);
      scaleY += softClamp(1 + mx * (y.low - 1), y.low, y.high) - 1;
    }
    final my = acceleration.dy / n;
    if (my != 0 && !my.isNaN) {
      final along = softClamp(1 + my * (y.high - 1), y.low, y.high);
      scaleY += along - 1;
      driftY += (1 - along) * 0.5 * size.height * _sign(velocity.dy);
      scaleX += softClamp(1 + my * (x.low - 1), x.low, x.high) - 1;
    }
    return (scaleX: scaleX, scaleY: scaleY, driftX: driftX, driftY: driftY);
  }

  /// The targets of UIKit's menu flex: the stretch an open menu of [size]
  /// takes under a finger and its pulse.
  ///
  /// [translation] is the finger's travel from its touch-down, [inBounds]
  /// its travel clamped into the menu, [velocity] the pulse channel's
  /// velocity (its stepped pulse channel) and [side] +1 for a menu below its
  /// button, -1 above it. Along x (y likewise with H):
  ///
  /// ```text
  /// kx = (|t.x| - |it.x| + P |it.x| / W) / T   (0 when t.x is 0)
  /// sx = 1 + kx - ky, sy = 1 - kx + ky
  /// dx = sign(t.x) kx W, dy = sign(t.y) ky H
  /// p = velocity side / pulse normalization
  /// sx *= 1 - pulseX p / W, sy *= 1 + pulseY p / H,
  /// dy += side driftRatio pulseY p
  /// sx, sy clamped to the movement bounds
  /// ```
  ///
  /// T the spec's stretch threshold and P [inBoundsPoints]. Read from
  /// UIKit, notes private.
  static FlexValues menuTargets({
    required FlexSpec spec,
    required double inBoundsPoints,
    required Offset translation,
    required Offset inBounds,
    required Size size,
    required double velocity,
    required double side,
  }) {
    double k(double t, double it, double extent) => t == 0
        ? 0
        : (t.abs() - it.abs() + inBoundsPoints * it.abs() / extent) /
              spec.scaleDistanceThreshold;
    final w = size.width;
    final h = size.height;
    final kx = k(translation.dx, inBounds.dx, w);
    final ky = k(translation.dy, inBounds.dy, h);
    final p = velocity * side / spec.interactionPulseNormalizationFactor;
    final sx = (1 + kx - ky) * (1 - p * spec.interactionPulseScaleX / w);
    final sy = (1 - kx + ky) * (1 + p * spec.interactionPulseScaleY / h);
    return (
      scaleX: sx.clamp(spec.movementMinScale, spec.movementMaxScale),
      scaleY: sy.clamp(spec.movementMinScale, spec.movementMaxScale),
      driftX: translation.dx.sign * kx * w,
      driftY:
          translation.dy.sign * ky * h +
          side *
              spec.interactionPulseDriftRatio *
              spec.interactionPulseScaleY *
              p,
    );
  }

  static double _sign(double x) => x.isNegative ? -1 : 1;

  static double _tanh(double x) {
    final e = math.exp(-2 * x.abs());
    final y = (1 - e) / (1 + e);
    return x.isNegative ? -y : y;
  }
}

/// Sends a flex [channel] toward [target] at time [t] on [spring], on its
/// tracking spring when [tracking].
///
/// A target equal to the channel's current one changes nothing, not even
/// the spring, so a finger that holds still never re-anchors the spring or
/// pushes it with [Spring.impulse]. Read from UIKit, notes private; the
/// impulse replays the open menu's channels to the recorded velocity on
/// every retarget (iPhone 16 Pro, iOS 27.0.1).
@internal
void chaseFlexChannel(
  MotionValue<double> channel,
  double t,
  double target,
  Spring spring, {
  bool tracking = false,
}) {
  if (target == channel.target) return;
  channel.retarget(t, target, spring: spring, tracking: tracking);
}

/// The open menu's pulse channel: a spring that runs on a clock of its own,
/// as UIKit's low refresh rate scope runs it
/// (`MorphMenuTuning.flexPulseRate`).
///
/// [step] advances the spring by [retargetStep] seconds when the target
/// changed and by the time that passed otherwise, and publishes its value
/// and velocity, which hold until the next step.
@internal
class FlexPulse {
  /// Creates a pulse channel at rest on 0 on [spring].
  FlexPulse(Spring spring, {required this.retargetStep})
    : _channel = MotionValue<double>(0, spring: spring);

  /// The spring time a step whose target changed advances the channel by.
  final double retargetStep;
  final MotionValue<double> _channel;
  double _clock = 0;
  double _stepped = 0;

  /// The value the last step published.
  double get value => _channel.valueAt(_clock);

  /// The velocity the last step published, per second of the channel's
  /// own clock; UIKit zeroes it when the finger lifts, leaving the spring.
  double velocity = 0;

  /// Puts the channel at rest on [to] at motion time [t].
  void snap(double t, double to) {
    _channel.snap(_clock, to);
    _stepped = t;
    velocity = 0;
  }

  /// Steps the channel at motion time [t] toward [target] and publishes.
  void step(double t, double target) {
    final h = target != _channel.target ? retargetStep : t - _stepped;
    _channel.retarget(_clock, target);
    _clock += h;
    _stepped = t;
    velocity = _channel.velocityAt(_clock);
  }

  /// Whether, held at [target], the most the channel can still publish
  /// moves its reader by less than [rest]; [reach] is how far the reader
  /// moves per unit per second of published velocity.
  bool holdsWithin(double target, double reach, double rest) =>
      target == _channel.target &&
      (velocity.abs() + _channel.spring.omega * (value - target).abs()) *
              reach <
          rest;
}
