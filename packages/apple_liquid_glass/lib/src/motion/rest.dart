import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';

/// The visible rest of a motion: how close every part must stay to its
/// target before the motion stops asking for frames and snaps onto it.
///
/// A spring that rests at 0.01 pt keeps the motion clock running for up to
/// a second after its last visible step. These thresholds end it when what
/// remains cannot be seen. Fidelity: NEAR, invisible. A motion settles once
/// every part's remaining swing (`MotionValue.reach`) is below [length]
/// (0.3 device px at 3x, 0.26 px on a 2.625x Pixel 6a), a scale's swing
/// times its surface's extent below [length], and an opacity's below
/// [opacity] (half an 8-bit step); the snap moves no edge by more than
/// that.
@internal
abstract final class GlassRest {
  /// The remaining swing of a position or length, in logical pixels.
  static const double length = 0.1;

  /// The remaining swing of an opacity or color mix, 0 to 1.
  static const double opacity = 0.002;

  /// The remaining swing of a scale of a surface [extent] pixels long.
  static double scale(double extent) => length / math.max(extent, 1);

  /// The extent, in pixels, a motion assumes before its host has measured
  /// what it moves: about a phone screen's longer side.
  static const double screen = 1000;

  /// The farthest an edge moves between frames [from] and [to]: the
  /// center's travel plus half the change of width or height. A progress
  /// from one to the other rests visibly at [scale] of it.
  static double travel(Rect from, Rect to) =>
      (to.center - from.center).distance +
      math.max((to.width - from.width).abs(), (to.height - from.height).abs()) /
          2;
}
