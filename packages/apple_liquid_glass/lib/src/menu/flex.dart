import 'dart:math' as math;

import 'package:apple_liquid_glass/src/menu/motion.dart';
import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The stretch of the open menu under a finger: four channels, the scale of
/// its width and height and the drifts of its center across and of its
/// edge facing the button, that chase the targets of the finger
/// ([MenuTuning.flexTargets]) on the flex spec's tracking spring while it
/// is down and return to rest on its scale spring after it lifts, each
/// changed target pushing them by the spec's retarget impulse
/// ([chaseFlexChannel]).
///
/// The flex sees every touch [MenuTuning.flexDelay] late. While a finger
/// is down, the pulse channel ([MenuTuning.flexPulseSpring]) steps on a
/// grid of its own from the touch-down ([MenuTuning.flexPulseRate]) and
/// its velocity sways the targets, until held still it can no longer move
/// the menu by [MenuTuning.flexPulseRest].
///
/// Positions are in the coordinates [frame] answers in; [frame] is the
/// menu's frame at rest, [side] +1 for a menu below its button and -1
/// above it, and [active] whether the menu is open, read when a delayed
/// touch comes due.
@internal
final class MenuFlex extends Motion {
  /// Creates the flex of a menu at rest.
  MenuFlex(
    this.tuning, {
    required this.frame,
    required this.side,
    required this.active,
  }) : _pulse = FlexPulse(
         tuning.flexPulseSpring,
         retargetStep: tuning.flexPulseRetargetStep,
       );

  /// The measured behavior the flex reproduces.
  final MenuTuning tuning;

  /// The menu's frame at rest.
  final Rect Function() frame;

  /// +1 for a menu below its button, -1 above it.
  final double Function() side;

  /// Whether the menu is open.
  final bool Function() active;

  static const _down = #down;
  static const _up = #up;
  static const _step = #step;

  double _rest() =>
      _touch == null ? MenuTuning.flexReturnRest : MenuTuning.flexPulseRest;

  double _scaleRest() {
    final size = frame();
    return _rest() / math.max(1.0, math.max(size.width, size.height));
  }

  late final _scaleX = own(MotionValue<double>(1), rest: _scaleRest);
  late final _scaleY = own(MotionValue<double>(1), rest: _scaleRest);
  late final _driftX = own(MotionValue<double>(0), rest: _rest);
  late final _driftY = own(MotionValue<double>(0), rest: _rest);
  final FlexPulse _pulse;
  _Touch? _touch;
  bool _pending = false;

  late final Spring _spring = tuning.flex.channelSpring;

  /// Whether a finger flexes the menu, or one that touched down is about
  /// to.
  bool get isTouched => _touch != null || _pending;

  /// What the pulse channel last published: its value and its velocity
  /// per second of its own clock.
  ({double value, double velocity}) get pulse =>
      (value: _pulse.value, velocity: _pulse.velocity);

  /// The scales and drifts of the flex at time [t].
  FlexValues valuesAt(double t) => (
    scaleX: _scaleX.valueAt(t),
    scaleY: _scaleY.valueAt(t),
    driftX: _driftX.valueAt(t),
    driftY: _driftY.valueAt(t),
  );

  /// A finger touched the menu at [position] at time [t]: the flex takes
  /// it up [MenuTuning.flexDelay] later, where UIKit resets the pulse
  /// channel without animation.
  void down(double t, Offset position) {
    unschedule(_up);
    unschedule(_step);
    _pending = true;
    at(t + tuning.flexDelay, (double s) {
      _pending = false;
      if (!active()) return;
      _pulse.snap(s, 0);
      _touch = _Touch(position, s);
    }, slot: _down);
  }

  /// The finger moved to [position] at time [t].
  void move(double t, Offset position) {
    at(t + tuning.flexDelay, (double s) {
      final touch = _touch;
      if (touch == null || !active()) return;
      final before = _targetsOf(touch);
      touch.position = position;
      _chase(touch, s, before);
      _schedulePulse(touch, s);
    });
  }

  /// The finger lifted, or stopped flexing the menu, at time [t]: the flex
  /// takes it up [MenuTuning.flexDelay] later, where UIKit zeroes the
  /// pulse channel's velocity and sends the channels to rest on the flex
  /// spec's scale spring, from where they show with their velocity.
  void up(double t) {
    unschedule(_down);
    unschedule(_step);
    _pending = false;
    at(t + tuning.flexDelay, (double s) {
      if (_touch == null) return;
      _touch = null;
      _pulse.velocity = 0;
      chaseFlexChannel(_scaleX, s, 1, _spring);
      chaseFlexChannel(_scaleY, s, 1, _spring);
      chaseFlexChannel(_driftX, s, 0, _spring);
      chaseFlexChannel(_driftY, s, 0, _spring);
    }, slot: _up);
  }

  FlexValues _targetsOf(_Touch touch) {
    final rect = frame();
    final at = touch.position;
    final inside = Offset(
      at.dx.clamp(rect.left, rect.right),
      at.dy.clamp(rect.top, rect.bottom),
    );
    return tuning.flexTargets(
      translation: at - touch.origin,
      inBounds: inside - touch.origin,
      size: rect.size,
      velocity: _pulse.velocity,
      side: side(),
    );
  }

  /// Sends the targets of [touch] to the channels at time [t] on their
  /// tracking spring when they changed from [before].
  void _chase(_Touch touch, double t, FlexValues before) {
    final after = _targetsOf(touch);
    if (after == before) return;
    chaseFlexChannel(_scaleX, t, after.scaleX, _spring, tracking: true);
    chaseFlexChannel(_scaleY, t, after.scaleY, _spring, tracking: true);
    chaseFlexChannel(_driftX, t, after.driftX, _spring, tracking: true);
    chaseFlexChannel(_driftY, t, after.driftY, _spring, tracking: true);
  }

  /// Makes sure the pulse channel steps after time [t] while the finger
  /// is down, on its grid from the touch-down.
  void _schedulePulse(_Touch touch, double t) {
    if (touch.nextStep != null) return;
    final period = 1 / tuning.flexPulseRate;
    final steps = ((t - touch.start) / period + 1e-6).floor() + 1;
    final due = touch.start + steps * period;
    touch.nextStep = due;
    at(due, (double s) {
      if (!identical(_touch, touch)) return;
      touch.nextStep = null;
      final target = touch.position.dy - touch.origin.dy;
      final before = _targetsOf(touch);
      _pulse.step(s, target);
      _chase(touch, s, before);
      final flex = tuning.flex;
      final reach =
          math.max(
            flex.interactionPulseScaleX / 2,
            flex.interactionPulseScaleY * (1 + flex.interactionPulseDriftRatio),
          ) /
          flex.interactionPulseNormalizationFactor;
      if (!_pulse.holdsWithin(target, reach, MenuTuning.flexPulseRest)) {
        _schedulePulse(touch, s);
      }
    }, slot: _step);
  }
}

/// A finger flexing the open menu, as the flex sees it
/// [MenuTuning.flexDelay] after the touches.
class _Touch {
  _Touch(this.origin, this.start) : position = origin;

  /// Where the finger touched down.
  final Offset origin;

  /// When the flex saw the touch-down; the pulse channel steps from here.
  final double start;

  /// Where the finger is.
  Offset position;

  /// When the pulse channel steps next, or null while it rests.
  double? nextStep;
}

/// The open menu's pulse channel: a spring that runs on a clock of its own,
/// as UIKit's low refresh rate scope runs it
/// ([MenuTuning.flexPulseRate]).
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
