import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// UIKit's refresh control as the content is pulled, refreshes and ends
/// (refresh control passport, iOS 27.2 simulator, real drags).
///
/// Pulled, its eight ticks come in one by one clockwise from 12 o'clock:
/// the control's [opacity] follows the pull alone ([revealOf], an ease in
/// and out over the pull from 10 to 170 points), and tick i takes `1 + i x
/// (opacity - 1)` of it. At the trigger the ticks turn the control's
/// refreshing color and settle, on a critically damped spring of omega 8.86,
/// to a tail: tick i at `0.08 x i`. The ticks jump 45 degrees clockwise
/// every 0.125 s, a turn a second, over a wind-up of half a turn on the
/// same spring. At the end the jumps stop and the ticks turn smoothly on
/// to the next half turn in 0.3 s.
final class RefreshMotion extends Motion {
  /// Creates the motion of a control at rest, stepped by [clock] or the
  /// ambient one.
  RefreshMotion({super.clock});

  /// How far the content is pulled when the refresh starts, in points.
  static const double triggerPull = 174;

  /// The pull from which the ticks begin to show.
  static const double revealStart = 10;

  /// The pull at which they all show.
  static const double revealEnd = 170;

  /// How much each tick behind the head adds to the tail.
  static const double tailStep = 0.08;

  /// The steps of a turn.
  static const int steps = 8;

  /// The seconds of a turn.
  static const double turn = 1;

  /// The half turn the ticks wind up by, in turns (179.43 degrees).
  static const double windUpTurns = 179.43 / 360;

  /// The smooth turn at the end, in seconds.
  static const double endDuration = 0.3;

  /// The spring of the tail and the wind-up: stiffness 78.49, critically
  /// damped.
  @internal
  static const tailSpring = Spring.response(
    2 * math.pi / 8.86,
    dampingRatio: 1,
  );

  /// The opacity of the control at a [pull] in points.
  static double revealOf(double pull) => Curves.easeInOut.transform(
    ((pull - revealStart) / (revealEnd - revealStart)).clamp(0, 1),
  );

  late final _opacity = own(MotionValue<double>(0));
  late final _color = own(MotionValue<double>(1));
  late final _offset = own(MotionValue<double>(-1));
  late final _windUp = own(MotionValue<double>(0));
  late final _ending = own(MotionValue<double>(0));
  late final _spin = own(_SpinLoop());

  bool _refreshing = false;
  bool _ended = false;

  /// Whether the control refreshes: the ticks show the control's color.
  bool get refreshing => _refreshing;

  /// The control's opacity.
  double get opacity => _opacity.value;

  /// How opaque tick [i] draws, of the control's opacity and its color,
  /// counting clockwise from the tick the turn starts at.
  double tickOpacity(int i) => (_color.value + i * _offset.value).clamp(0, 1);

  /// How far the ticks have turned clockwise, in turns.
  double get rotation => _windUp.value + (_ended ? _ending.value : _spin.turns);

  /// Follows a pull of [pull] points while the control does not refresh.
  void pull(double pull) {
    if (_refreshing) return;
    final reveal = revealOf(pull);
    withoutAnimation(() {
      _opacity.target = reveal;
      _color.target = 1;
      _offset.target = reveal - 1;
    });
  }

  /// Starts the refresh at [t].
  void trigger(double t) {
    _refreshing = true;
    _ended = false;
    withoutAnimation(() => _opacity.target = 1);
    withSpring(tailSpring, () {
      _color.target = 0;
      _offset.target = tailStep;
      _windUp.target = windUpTurns;
    });
    _spin.begin(t);
  }

  /// Ends the refresh at [t]: the ticks turn on to the next half turn.
  void end(double t) {
    if (!_refreshing) return;
    final from = _spin.turns;
    _spin.stop();
    _ended = true;
    final to = from + (0.5 - from % 0.5);
    withoutAnimation(() => _ending.target = from);
    withAnimation(
      const TimingCurve.easeInOut(duration: endDuration),
      () => _ending.target = to,
    );
  }

  /// Puts the control back at rest, hidden.
  void reset() {
    _refreshing = false;
    _ended = false;
    _spin.stop();
    withoutAnimation(() {
      _opacity.target = 0;
      _color.target = 1;
      _offset.target = -1;
      _windUp.target = 0;
      _ending.target = 0;
    });
  }
}

final class _SpinLoop extends MotionLoop {
  _SpinLoop() : super(rate: RefreshMotion.steps / RefreshMotion.turn);

  double _start = 0;
  bool _spinning = false;
  double turns = 0;

  void begin(double t) {
    _start = t;
    _spinning = true;
    turns = 0;
    wake(t);
  }

  void stop() => _spinning = false;

  @override
  bool step(double t) {
    if (!_spinning) return false;
    // A frame's time lands on a whole step within rounding.
    final steps = ((t - _start) * rate + 1e-6).floor();
    turns = steps / RefreshMotion.steps;
    return true;
  }
}
