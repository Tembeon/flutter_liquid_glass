import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/flex_spec.dart' show FlexSpec;
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';

/// The glow a finger raises on a pressed glass surface, in one frame.
///
/// UIKit lights a pressed glass surface with two glows of its flex
/// interaction, both color matrices over what lies behind them rather than
/// paint of their own: a wash across the whole surface that adds [wash] to
/// every color channel, and a soft spot under the finger, most at [center]
/// and fading as a Gaussian of standard deviation [radius]. Both stay
/// inside the surface's shape and under its content, and clamp at white.
/// How much the spot brightens is the glass's own: a renderer reads it from
/// the surface's glass with [gainOn]. The liquid renderer draws the glow in
/// its glass layer; the flat renderer, and the liquid one wherever it falls
/// back to flat (fake glass, Reduce Transparency), draws none.
///
/// UIKit: the flex interaction's big and little glows. SwiftUI:
/// `.glassEffect(.regular.interactive())`.
@immutable
class GlassTouchGlow {
  /// Creates a glow description.
  const GlassTouchGlow({
    required this.wash,
    required this.center,
    required this.radius,
    required this.spot,
  });

  /// How much every color channel rises across the whole surface, in
  /// `[0, 1]` units.
  final double wash;

  /// The center of the spot, in the surface's local coordinates.
  final Offset center;

  /// The standard deviation of the spot's falloff, in pixels.
  final double radius;

  /// How strongly the spot lights its center, as a share of the glass's
  /// own spot gain.
  final double spot;

  /// How much the spot brightens its center on [glass] in [brightness]:
  /// there the channels are multiplied by `1 + gainOn(glass, brightness)`.
  double gainOn(Glass glass, Brightness brightness) =>
      spot *
      TouchGlowMotion.spotGainFor(
        brightness,
        tint: glass.tint,
        clear: glass.isClear,
      );

  @override
  bool operator ==(Object other) =>
      other is GlassTouchGlow &&
      other.wash == wash &&
      other.center == center &&
      other.radius == radius &&
      other.spot == spot;

  @override
  int get hashCode => Object.hash(wash, center, radius, spot);
}

/// The touch glow of a pressed glass surface as a function of time:
/// UIKit's flex interaction glows, measured on an iPhone on iOS 27's tab
/// bar and open menu, which share the law and differ in [diameter],
/// [riseLag] and their peaks.
///
/// A touch raises both glows on a critically damped [riseSpring] after
/// [riseLag]; they hold while the finger stays down. A finger that moves
/// [dragDistance] from where it landed turns the spot into its dragging
/// state: twice as wide at half the strength, on [fallSpring]. Lifting
/// the finger lets both glows fall on [fallSpring] after [releaseLag]
/// while the spot spreads to [releaseGrowth] times its size. The spot
/// follows the finger.
///
/// Peaks come from the surface's [FlexSpec] - its big glow opacity
/// for the wash, its little glow opacity for the spot - so a 62 pixel
/// tall bar peaks at 0.845 and 0.2845, and an open menu
/// ([FlexSpec.menu]) at 0 and 0.5.
///
/// Under a finger the rise rests within [MotionRest.opacity] and the
/// spot's size and strength within a visible step; after it the glow rests
/// once both glows read zero ([hideBelow]) and the fall is within
/// [MotionRest.opacity]. A finger held still counts: the glow rests lit
/// until the finger moves or lifts.
final class TouchGlowMotion extends Motion {
  /// Creates a resting glow with the peaks of a surface's flex spec.
  TouchGlowMotion({
    required this.washPeak,
    required this.spotPeak,
    required this.diameter,
    required this.riseLag,
    this.minimumLit = 0,
  });

  /// The opacity the wash rises to.
  final double washPeak;

  /// The opacity the spot rises to.
  final double spotPeak;

  /// The spring the glows rise on.
  static const riseSpring = Spring.response(0.1);

  /// The spring the glows fall, grow and turn dragging on.
  static const fallSpring = Spring.response(0.5);

  /// How long after the touch the glows start to rise, in seconds.
  final double riseLag;

  /// The tab bar's [riseLag]: fitted to its device rows (tab-bar.md, Spec -
  /// touch glow).
  static const double tabBarRiseLag = 0.042;

  /// The least time, in seconds, the glow rises before a release lets it
  /// fall: a lift sooner than that starts the fall this long after the
  /// rise began. Zero lets the fall follow the lift after [releaseLag].
  final double minimumLit;

  double _riseAt = 0;

  /// How long after the release the glows start to fall, in seconds.
  static const double releaseLag = 0.02;

  /// The diameter of the spot before it grows, in pixels.
  final double diameter;

  /// The tab bar's [diameter]: its LittleGlow layer is a 93 pt disc
  /// (tab-bar.md, Spec - touch glow).
  static const double tabBarDiameter = 93;

  /// How many times its size the spot grows to after a release.
  static const double releaseGrowth = 4;

  /// How many times its size the spot grows to while dragged.
  static const double dragGrowth = 2;

  /// The share of its strength the spot keeps while dragged.
  static const double dragStrength = 0.5;

  /// How far the finger moves from its landing before the spot turns
  /// dragging, in pixels.
  static const double dragDistance = 50;

  /// Each glow's opacity reads zero below this.
  static const double hideBelow = 0.005;

  /// How much the wash adds to every channel at opacity 1: the offset of
  /// its color matrix.
  static const double washOffset = 0.05;

  /// The strength of the spot's center at opacity 1, as a share of its
  /// color matrix's gain.
  static const double spotCore = 0.38;

  /// The spot's Gaussian standard deviation as a share of its diameter.
  static const double spotSpread = 0.568;

  /// The gain of the spot's color matrix over a gray backdrop, less one:
  /// 3 in the dark appearance, 0.667 in the light one. They are the
  /// color-dodge gains `1 / (1 - white) - 1` of UIKit's glow white levels
  /// 0.75 (dark) and 0.4 (light) (read from UIKit, notes private).
  static double spotGain(Brightness brightness) => switch (brightness) {
    Brightness.dark => 3,
    Brightness.light => 0.667,
  };

  /// The glow white level of clear glass in both appearances (read from
  /// UIKit, notes private).
  static const double clearGlassWhite = 0.7;

  /// The glow white level of tinted glass over the tint's luminance:
  /// UIKit lerps from [tintWhiteFrom] to [tintWhiteTo] by luminance to the
  /// power [tintLuminanceExponent] (read from UIKit, notes private).
  static const double tintWhiteFrom = 0.7;

  /// See [tintWhiteFrom].
  static const double tintWhiteTo = 0.25;

  /// See [tintWhiteFrom].
  static const double tintLuminanceExponent = 1.25;

  /// The gain less one of a spot with color-dodge white level [white].
  static double spotGainOfWhite(double white) => 1 / (1 - white) - 1;

  /// The spot's gain less one for a glass surface: tinted glass by its
  /// [tint]'s luminance (UIKit's Rec. 709 weights of the gamma-encoded
  /// channels, times alpha), clear glass by [clearGlassWhite], regular
  /// glass by [spotGain]. Tinted and clear values are read from UIKit, not
  /// measured on a device.
  static double spotGainFor(
    Brightness brightness, {
    Color? tint,
    bool clear = false,
  }) {
    if (tint != null) {
      final luminance =
          (0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b) * tint.a;
      final t = math.pow(luminance.clamp(0.0, 1.0), tintLuminanceExponent);
      return spotGainOfWhite(tintWhiteFrom + (tintWhiteTo - tintWhiteFrom) * t);
    }
    if (clear) return spotGainOfWhite(clearGlassWhite);
    return spotGain(brightness);
  }

  double _progressRest() {
    if (_down != null) return MotionRest.opacity;
    final peak = math.max(math.max(washPeak, spotPeak), hideBelow);
    return math.min(MotionRest.opacity, hideBelow / peak);
  }

  double _scaleRest() =>
      _down == null ? double.infinity : MotionRest.scale(diameter);
  double _strengthRest() =>
      _down == null ? double.infinity : MotionRest.opacity;

  late final _progress = own(
    MotionValue<double>(0, spring: riseSpring),
    rest: _progressRest,
  );
  late final _scale = own(
    MotionValue<double>(1, spring: fallSpring),
    rest: _scaleRest,
  );
  late final _strength = own(
    MotionValue<double>(1, spring: fallSpring),
    rest: _strengthRest,
  );
  Offset _center = Offset.zero;
  Offset? _down;
  bool _dragging = false;
  static const _riseSlot = #rise;
  static const _dragSlot = #drag;
  static const _fallSlot = #fall;

  /// Whether a finger is down.
  bool get isDown => _down != null;

  /// A finger touched at [position] at time [t].
  void pointerDown(double t, Offset position) {
    advance(t);
    unschedule(_dragSlot);
    unschedule(_fallSlot);
    _center = position;
    _down = position;
    _dragging = false;
    _scale.snap(t, 1);
    _strength.snap(t, 1);
    _riseAt = t + riseLag;
    at(_riseAt, _rise, slot: _riseSlot);
  }

  void _rise(double at) => _progress.retarget(at, 1, spring: riseSpring);

  /// The finger moved to [position] at time [t].
  void pointerMove(double t, Offset position) {
    advance(t);
    final down = _down;
    if (down == null) return;
    _center = position;
    if (_dragging || (position - down).distance < dragDistance) return;
    _dragging = true;
    at(t + riseLag, (at) {
      _scale.retarget(at, dragGrowth, spring: fallSpring);
      _strength.retarget(at, dragStrength, spring: fallSpring);
    }, slot: _dragSlot);
  }

  /// The finger lifted, or its touch was cancelled, at time [t].
  void pointerUp(double t) {
    advance(t);
    if (_down == null) return;
    _down = null;
    unschedule(_riseSlot);
    unschedule(_dragSlot);
    if (minimumLit > 0 && _riseAt > t) at(_riseAt, _rise, slot: _riseSlot);
    final start = math.max(t + releaseLag, _riseAt + minimumLit);
    at(start, (at) {
      _progress.retarget(at, 0, spring: fallSpring);
      _scale.retarget(at, releaseGrowth, spring: fallSpring);
    }, slot: _fallSlot);
  }

  /// The wash's opacity at time [t], from [now] on.
  double washOpacity(double t) {
    advance(t);
    return _wash(t);
  }

  /// The spot's opacity at time [t], from [now] on.
  double spotOpacity(double t) {
    advance(t);
    return _spot(t);
  }

  /// The spot's scale over [diameter] at time [t], from [now] on.
  double spotScale(double t) {
    advance(t);
    return _scale.valueAt(t);
  }

  /// The glow to paint now.
  GlassTouchGlow? get glow => _glow(now);

  double _wash(double t) {
    final value = washPeak * _progress.valueAt(t).clamp(0.0, 1.0);
    return value < hideBelow ? 0 : value;
  }

  double _spot(double t) {
    final value =
        spotPeak * _progress.valueAt(t).clamp(0.0, 1.0) * _strength.valueAt(t);
    return value < hideBelow ? 0 : value;
  }

  GlassTouchGlow? _glow(double t) {
    final wash = _wash(t);
    final spot = _spot(t);
    if (wash == 0 && spot == 0) return null;
    return GlassTouchGlow(
      wash: washOffset * wash,
      center: _center,
      radius: spotSpread * diameter * _scale.valueAt(t),
      spot: spotCore * spot,
    );
  }
}
