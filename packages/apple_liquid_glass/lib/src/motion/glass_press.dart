import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/touch_glow.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// How a [GlassPress] takes a touch: whether it stretches after a dragging
/// finger and glows, and how late it takes the touch up.
@internal
@immutable
final class FlexLaw {
  /// Creates a law.
  const FlexLaw({
    this.stretches = true,
    this.glows = false,
    this.activationDelay = 0,
    this.touchDelay = 0,
  });

  /// A glass button's: it stretches, glows and takes every touch
  /// [GlassPress.touchDelay] after its stamp.
  static const button = FlexLaw(glows: true, touchDelay: GlassPress.touchDelay);

  /// Whether a dragging finger stretches the surface and shifts it after
  /// the finger; without it the flex only lifts.
  final bool stretches;

  /// Whether the press carries the touch glow.
  final bool glows;

  /// Seconds between the flex taking up a touch and it following the
  /// finger.
  final double activationDelay;

  /// Seconds between a touch's own stamp and the flex taking it up: the
  /// touch-down, every move and the release.
  final double touchDelay;
}

/// UIKit's flex interaction on one glass surface: the lift, the stretch
/// and shift toward a finger that drags, and the touch glow.
///
/// The tuning comes from the surface's size ([FlexSpec.forSize]). A touch
/// scales the whole surface by [FlexSpec.liftScaleFor], the lift over its
/// long side; the press rides the tracking spring, the release the scale
/// spring, so a small button rings below its size while a wide one barely
/// does. The surface stays lifted for the whole touch, even far outside. A
/// finger that drags stretches it along the drag, narrows it across and
/// shifts it toward the finger: a quarter as much per pixel inside the
/// surface as beyond its edge, over the spec's stretch threshold. With
/// [FlexLaw.glows] a glow fades in under the finger and fades out on
/// release while the little glow at the touch point grows.
///
/// The flex takes up every touch [FlexLaw.touchDelay] after the touch's
/// own stamp, as UIKit's button does; whether the surface is pressed and
/// whether a release activates it follow the touch at once.
///
/// As a [PointerFollower] it takes the touch in its region's box, whose size
/// it takes at the touch-down.
///
/// Times are seconds and positions pixels in the surface's own space. The
/// channels rest within a tenth of a pixel over the long side and the glow
/// within a visible opacity step; a finger held still counts, so a held
/// surface stops asking for frames once its lift and glow are in place.
@internal
final class GlassPress extends Motion implements PointerFollower {
  /// Creates the press of a surface of [size] at rest, taking touches by
  /// [law].
  GlassPress({Size size = Size.zero, this.law = FlexLaw.button})
    : _size = size,
      _spec = FlexSpec.forSize(size);

  /// How far outside a button the touch still counts as inside.
  ///
  /// Measured on an iPhone 16 Pro (2026-10-13, a 120 x 44 button): a
  /// release 70 pt above or 60 pt beside it activates; below and left are
  /// not measured (glass-button passport).
  static const double highlightSlop = 70;

  /// Seconds between a touch's own time stamp and a glass button's flex
  /// taking it up: the touch-down, every move and the release.
  ///
  /// UIKit's glass button starts its lift 22.5 - 29.2 ms after the touch's
  /// stamp (median 26.1, iPhone 16 Pro: the last three taps of
  /// `button-glass-44x44-taps` and the five touches on the button in a
  /// scroll view of `tracking/scroll-delay`) and its return 22.1 - 28.3 ms
  /// after the release's (median 26.0, the seven `*-hold800` captures):
  /// delivery 10 - 25 ms, then the frame the flex begins on. Fed this late,
  /// the drag-off and alert lean replays halve their error. The first
  /// touch after the button appears starts 38 - 47 ms after its stamp, the
  /// next display frame coming ~21 ms after the one before instead of 8.3;
  /// that one-time setup is not reproduced.
  static const double touchDelay = 0.026;

  /// How the press takes a touch.
  final FlexLaw law;

  /// Whether the surface moves for Reduce Motion: it still glows but never
  /// lifts, stretches or shifts. This approximates the platform's
  /// behavior; it is not measured.
  bool reducedMotion = false;

  Size _size;
  FlexSpec _spec;

  // The glow's position and fade count only while they show: under a
  // finger the rise covers the fade, after it the fade hides the position.
  // The little glow's growth shows only through the fade.
  double _scaleRest() => MotionRest.scale(math.max(_size.width, _size.height));
  double _positionRest() => _down == null ? double.infinity : MotionRest.length;
  double _fadeRest() => _down == null ? MotionRest.opacity : double.infinity;
  static double _length() => MotionRest.length;
  static double _opacity() => MotionRest.opacity;
  static double _hidden() => double.infinity;

  late final _scaleX = own(MotionValue<double>(1), rest: _scaleRest);
  late final _scaleY = own(MotionValue<double>(1), rest: _scaleRest);
  late final _driftX = own(MotionValue<double>(0), rest: _length);
  late final _driftY = own(MotionValue<double>(0), rest: _length);
  late final _rise = own(_GlowRise(this), rest: _opacity);
  late final _fade = own(
    MotionValue<double>(0, spring: FlexInteraction.glowSpring),
    rest: _fadeRest,
  );
  late final _littleScale = own(
    MotionValue<double>(1, spring: FlexInteraction.glowSpring),
    rest: _hidden,
  );
  late final _glowX = own(
    MotionValue<double>(0, spring: FlexSpec.ultraSmall.trackingSpring),
    rest: _positionRest,
  );
  late final _glowY = own(
    MotionValue<double>(0, spring: FlexSpec.ultraSmall.trackingSpring),
    rest: _positionRest,
  );

  static const _activation = Object();

  bool _pressed = false;
  bool _inside = false;
  Offset? _down;
  Offset _position = Offset.zero;
  bool _active = false;

  /// The size of the surface at rest.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = FlexSpec.forSize(value);
  }

  /// The deformation tuning UIKit derives for [size].
  FlexSpec get spec => _spec;

  /// The scale of the fully lifted surface.
  double get liftedScale => _spec.liftScaleFor(_size);

  /// Whether a finger is down on the surface.
  bool get isPressed => _pressed;

  /// Whether the flex follows the finger: from [FlexLaw.activationDelay]
  /// after it takes up the touch until it takes up the release.
  bool get isActive => _active;

  /// Whether the surface rests undeformed: settled with no finger on it.
  bool get isAtRest => !_pressed && isSettled;

  /// The lift: the mean of [scaleX] and [scaleY], which the stretch leaves
  /// alone.
  double get scale => (scaleX + scaleY) / 2;

  /// The horizontal scale, lift and drag stretch combined.
  double get scaleX => _scaleX.valueAt(now);

  /// The vertical scale, lift and drag stretch combined.
  double get scaleY => _scaleY.valueAt(now);

  /// How far the surface's center shows shifted toward the finger: the
  /// drift times the scale, as UIKit scales the drifted surface.
  ///
  /// Replays the glass button's drag-off captures to 0.03 pt rms on the
  /// simulator and 0.07 on the device (120 x 44, a 150 pt drag).
  Offset get lean =>
      Offset(_driftX.valueAt(now) * scaleX, _driftY.valueAt(now) * scaleY);

  /// The flex's four channels.
  FlexValues get values => (
    scaleX: scaleX,
    scaleY: scaleY,
    driftX: _driftX.valueAt(now),
    driftY: _driftY.valueAt(now),
  );

  /// The glow strength, 0 to 1.
  double get glow => _glowAt(now);

  /// The opacity of the glow over the whole surface.
  double get bigGlowOpacity => glow * _spec.bigGlowOpacity;

  /// The opacity of the little glow at the touch point.
  double get littleGlowOpacity => glow * _spec.littleGlowOpacity;

  /// The scale of the little glow.
  double get littleGlowScale => _littleScale.valueAt(now);

  /// The center of the little glow.
  Offset get littleGlowCenter =>
      Offset(_glowX.valueAt(now), _glowY.valueAt(now));

  /// The touch glow, or null when it shows nothing.
  ///
  /// Its timing and growth follow the flex; how bright the spot gets is
  /// the glass's own, which the renderer reads from the surface
  /// ([TouchGlowMotion.spotGainFor]). The press itself is the same for
  /// every glass (UIKit gives the clear configurations no press of their
  /// own, read from UIKit, notes private).
  GlassTouchGlow? get touchGlow {
    final big = bigGlowOpacity;
    final little = littleGlowOpacity;
    if (big <= 0.001 && little <= 0.001) return null;
    return GlassTouchGlow(
      wash: TouchGlowMotion.washOffset * big,
      center: littleGlowCenter,
      radius:
          TouchGlowMotion.spotSpread *
          FlexInteraction.littleGlowSize *
          littleGlowScale,
      spot: TouchGlowMotion.spotCore * little,
    );
  }

  @override
  void down(PointerDownInput input) {
    size = input.regionSize;
    pointerDown(input.time, input.position);
  }

  @override
  void move(PointerMoveInput input) => pointerMove(input.time, input.position);

  @override
  void up(PointerUpInput input) => pointerUp(input.time, input.position);

  @override
  void cancel(PointerCancelInput input) => pointerCancel(input.time);

  @override
  void hover(PointerHoverInput input) {}

  /// A finger touched the surface at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    _pressed = true;
    _inside = true;
    _later(t, (s) => _flexDown(s, position));
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (!_pressed) return;
    _later(t, (s) => _flexMove(s, position));
    _inside = (Offset.zero & size).inflate(highlightSlop).contains(position);
  }

  /// The finger left the surface at [position]; returns whether the
  /// release activates it.
  bool pointerUp(double t, Offset position) {
    advance(t);
    if (!_pressed) return false;
    pointerMove(t, position);
    final activated = _inside;
    _release(t);
    return activated;
  }

  /// The touch was cancelled; the surface returns without activating.
  void pointerCancel(double t) {
    advance(t);
    release(t);
  }

  /// Ends the touch at [t] without activating and without advancing: for
  /// an owner that lets go of the surface from a reaction of its own.
  void release(double t) {
    if (!_pressed) return;
    _release(t);
  }

  void _release(double t) {
    _pressed = false;
    _inside = false;
    _later(t, _flexRelease);
  }

  // A touch stamped earlier than the cursor runs at its own time, as the
  // flex would have taken it up then.
  void _later(double t, void Function(double t) action) {
    final due = t + law.touchDelay;
    if (due <= now) {
      action(due);
    } else {
      at(due, action);
    }
  }

  void _flexDown(double t, Offset position) {
    final glows = law.glows;
    if (glows) _rise.start(t, from: _glowAt(t));
    _down = position;
    _position = position;
    if (glows) {
      _littleScale.snap(t, 1);
      final at = _clamped(position);
      _glowX.snap(t, at.dx);
      _glowY.snap(t, at.dy);
    }
    if (law.activationDelay <= 0) {
      _activate(t);
    } else {
      at(t + law.activationDelay, _activate, slot: _activation);
    }
  }

  void _flexMove(double t, Offset position) {
    if (_down == null) return;
    _position = position;
    if (_active) _retarget(t, targets, tracking: true);
    if (law.glows) {
      final at = _clamped(position);
      final tracking = _spec.trackingSpring;
      _glowX.retarget(t, at.dx, spring: tracking);
      _glowY.retarget(t, at.dy, spring: tracking);
    }
  }

  void _flexRelease(double t) {
    unschedule(_activation);
    final strength = _glowAt(t);
    final wasDown = _down != null;
    _down = null;
    _active = false;
    _retarget(t, FlexInteraction.rest, tracking: false);
    if (law.glows && wasDown) {
      _fade.snap(t, strength);
      _fade.retarget(t, 0);
      _littleScale.retarget(t, FlexInteraction.littleGlowGrowth);
    }
  }

  void _activate(double t) {
    if (_down == null) return;
    _active = true;
    _retarget(t, targets, tracking: true);
  }

  void _retarget(double t, FlexValues to, {required bool tracking}) {
    final spring = _spec.channelSpring;
    chaseFlexChannel(_scaleX, t, to.scaleX, spring, tracking: tracking);
    chaseFlexChannel(_scaleY, t, to.scaleY, spring, tracking: tracking);
    chaseFlexChannel(_driftX, t, to.driftX, spring, tracking: tracking);
    chaseFlexChannel(_driftY, t, to.driftY, spring, tracking: tracking);
  }

  /// What the channels head to now: the dynamic targets of the finger
  /// while the flex is active ([FlexInteraction.dynamicTargets]), rest
  /// otherwise.
  FlexValues get targets {
    final down = _down;
    if (!_active || down == null || reducedMotion) return FlexInteraction.rest;
    final at = _position;
    return FlexInteraction.dynamicTargets(
      spec: _spec,
      size: _size,
      translation: at - down,
      inBounds: _clamped(at) - down,
      stretch: law.stretches,
    );
  }

  double _glowAt(double t) {
    if (!law.glows) return 0;
    if (_down != null) return _rise.valueAt(t);
    return _fade.valueAt(t).clamp(0.0, 1.0);
  }

  Offset _clamped(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));
}

/// The glow rising under a finger, `1 - (1 - from) e^(-(t - start) / tau)`
/// with tau [FlexInteraction.glowTime]; it rests once what is left of the
/// rise, at the surface's brightest glow, is below the tolerance.
final class _GlowRise extends MotionPart {
  _GlowRise(this._press);

  final GlassPress _press;
  double _from = 0;
  double _start = 0;

  bool get _rising => _press._down != null;

  double get _peak =>
      math.max(_press.spec.bigGlowOpacity, _press.spec.littleGlowOpacity);

  void start(double t, {required double from}) {
    _from = from;
    _start = t;
    changed();
  }

  double valueAt(double t) =>
      1 - (1 - _from) * math.exp(-(t - _start) / FlexInteraction.glowTime);

  @override
  double? restTime([double? tolerance]) {
    if (!_rising) return double.negativeInfinity;
    final gap = (1 - _from) * _peak;
    final within = tolerance ?? MotionRest.opacity;
    if (gap < within) return _start;
    return _start + FlexInteraction.glowTime * math.log(gap / within);
  }

  @override
  bool restsAt(double t, [double? tolerance]) =>
      !_rising || (1 - valueAt(t)) * _peak < (tolerance ?? MotionRest.opacity);

  @override
  void restFrom(double t) {
    if (!_rising) return;
    _from = 1;
    _start = t;
  }

  @override
  double? get nextDue => null;
}
