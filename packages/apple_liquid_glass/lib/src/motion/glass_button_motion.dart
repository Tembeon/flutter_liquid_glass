import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/touch_glow.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

@internal
/// The motion of an iOS 27 glass button: the lift, the stretch and shift
/// toward a finger that drags, and the touch glow.
///
/// It is UIKit's flex interaction for a surface of the button's size
/// ([FlexSpec.forSize]). A touch scales the whole button by
/// [FlexSpec.liftScaleFor], the lift over its long side; the press
/// rides the tracking spring, the release the scale spring, so a small
/// button rings below its size while a wide one barely does. The button
/// stays lifted for the whole touch, even far outside. A finger that
/// drags stretches it along the drag, narrows it across and shifts it
/// toward the finger: a quarter as much per pixel inside the button as
/// beyond its edge, over the spec's stretch threshold. A glow fades in
/// under the finger and fades out on release while the little glow at
/// the touch point grows.
///
/// The flex takes up every touch [touchDelay] after the touch's own time
/// stamp, as UIKit's does; whether the button is pressed and whether a
/// release activates it follow the touch at once.
///
/// Times are seconds and positions pixels in the button's own space.
///
/// The button settles once every part's remaining swing is below
/// `GlassRest` (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
/// A finger held still counts: a held button stops asking for frames once
/// its lift and glow are in place and wakes on the finger's next move or its
/// lift.
class GlassButtonMotion {
  /// Creates the motion of a button of [size].
  GlassButtonMotion({required Size size})
    : _flex = FlexInteraction(size: size, glows: true);

  /// The time constant of the glow fading in, in seconds.
  static const double glowTime = FlexInteraction.glowTime;

  /// The spring the glow fades out and the little glow grows on.
  static const glowSpring = FlexInteraction.glowSpring;

  /// How far outside the button the touch still counts as inside.
  ///
  /// Measured on an iPhone 16 Pro (2026-10-13, a 120 x 44 button): a
  /// release 70 pt above or 60 pt beside it activates; below and left are
  /// not measured (glass-button passport).
  static const double highlightSlop = 70;

  /// Seconds between a touch's own time stamp and the flex taking it up:
  /// the touch-down, every move and the release.
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

  /// The diameter of the little glow at the touch point.
  static const double littleGlowSize = FlexInteraction.littleGlowSize;

  /// How much the little glow grows while it fades out.
  static const double littleGlowGrowth = FlexInteraction.littleGlowGrowth;

  /// Whether the button moves for Reduce Motion: it glows under the touch
  /// but never lifts or leans. This approximates the platform's behavior;
  /// it is not measured.
  bool get reducedMotion => _flex.reducedMotion;

  set reducedMotion(bool value) => _flex.reducedMotion = value;

  final FlexInteraction _flex;
  final MotionTimeline _input = MotionTimeline();
  double _now = 0;
  bool _pressed = false;
  bool _inside = false;

  /// The size of the button at rest.
  Size get size => _flex.size;

  set size(Size value) => _flex.size = value;

  /// The deformation tuning UIKit derives for [size].
  FlexSpec get spec => _flex.spec;

  /// The scale of the fully lifted button.
  double get liftedScale => _flex.liftedScale;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether a finger is down on the button.
  bool get isPressed => _pressed;

  /// Whether the finger is close enough that a release activates.
  bool get isHighlighted => _pressed && _inside;

  /// The lift: the mean of [scaleX] and [scaleY], which the stretch
  /// leaves alone.
  double get scale => _flex.scale(_now);

  /// The horizontal scale, lift and drag stretch combined.
  double get scaleX => _flex.scaleX(_now);

  /// The vertical scale, lift and drag stretch combined.
  double get scaleY => _flex.scaleY(_now);

  /// How far the button shows shifted toward the finger: the flex's
  /// drift at the button's scale.
  Offset get lean => _flex.translation(_now);

  /// The glow strength, 0 to 1.
  double get glow => _flex.glow(_now);

  /// The opacity of the glow over the whole button.
  double get bigGlowOpacity => _flex.bigGlowOpacity(_now);

  /// The opacity of the little glow at the touch point.
  double get littleGlowOpacity => _flex.littleGlowOpacity(_now);

  /// The scale of the little glow.
  double get littleGlowScale => _flex.littleGlowScale(_now);

  /// The center of the little glow.
  Offset get littleGlowCenter => _flex.littleGlowCenter(_now);

  /// The touch glow, or null when it shows nothing.
  ///
  /// Its timing and growth follow this button's flex interaction; how
  /// bright the spot gets is the glass's own, which the renderer reads from
  /// the surface ([TouchGlowMotion.spotGainFor]). The press itself is the
  /// same for every glass (UIKit gives the clear configurations no press of
  /// their own, read from UIKit, notes private).
  GlassTouchGlow? get touchGlow {
    final big = bigGlowOpacity;
    final little = littleGlowOpacity;
    if (big <= 0.001 && little <= 0.001) return null;
    return GlassTouchGlow(
      wash: TouchGlowMotion.washOffset * big,
      center: littleGlowCenter,
      radius: TouchGlowMotion.spotSpread * littleGlowSize * littleGlowScale,
      spot: TouchGlowMotion.spotCore * little,
    );
  }

  /// Whether what remains of the button's motion is invisible
  /// (`GlassRest`, NEAR); a button held still under a finger settles too
  /// and wakes on the finger's next move or its lift.
  bool get isSettled => _input.isEmpty && _flex.isSettled(_now);

  /// Whether all of the button's motion but its touch glow has settled
  /// while the glow still rises, follows the finger or fades.
  bool get isGlowOnly => _input.isEmpty && _flex.isGlowOnly(_now);

  /// Whether the button rests undeformed: settled with no finger on it.
  bool get isAtRest => !_pressed && isSettled;

  /// Puts a settled button onto its targets; a glow that still changes
  /// keeps changing.
  void settle() => _flex.settle(_now);

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
    _input.runDue(t);
  }

  /// A finger touched the button at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    _pressed = true;
    _inside = true;
    _later(t, (s) => _flex.pointerDown(s, position));
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (!_pressed) return;
    _later(t, (s) => _flex.pointerMove(s, position));
    _inside = (Offset.zero & size).inflate(highlightSlop).contains(position);
  }

  /// The finger left the button at [position]; returns whether the
  /// release activates the button.
  bool pointerUp(double t, Offset position) {
    advance(t);
    if (!_pressed) return false;
    pointerMove(t, position);
    final activated = _inside;
    _release(t);
    return activated;
  }

  /// The touch was cancelled; the button returns without activating.
  void pointerCancel(double t) {
    advance(t);
    if (!_pressed) return;
    _release(t);
  }

  void _release(double t) {
    _pressed = false;
    _inside = false;
    _later(t, _flex.release);
  }

  void _later(double t, void Function(double t) action) {
    _input.insert(t + touchDelay, action);
    _input.runDue(_now);
  }
}
