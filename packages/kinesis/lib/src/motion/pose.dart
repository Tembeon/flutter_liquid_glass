import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How a piece of content looks at one moment of a motion: moved, scaled
/// and turned about a pivot of its own box, faded and blurred.
///
/// The one look value of kinesis: a `SymbolEffectMotion` composes its
/// effects into one, a `ContentTransition` and a `NumericTextTransition`
/// answer one for leaving and arriving content, and a `MotionTransition`
/// draws one from its `pose`.
///
/// SwiftUI: what the `offset`, `scaleEffect`, `rotationEffect`, `opacity`
/// and `blur` modifiers of a transition's modifier add up to.
@immutable
final class MotionPose {
  /// Creates a pose; every field defaults to identity.
  const MotionPose({
    this.offset = Offset.zero,
    this.offsetFraction = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.blur = 0,
  }) : assert(blur >= 0, 'blur is a sigma and cannot be negative');

  /// The pose [t] of the way from [a] to [b].
  factory MotionPose.lerp(MotionPose a, MotionPose b, double t) => MotionPose(
    offset: Offset.lerp(a.offset, b.offset, t)!,
    offsetFraction: Offset.lerp(a.offsetFraction, b.offsetFraction, t)!,
    scale: lerpDouble(a.scale, b.scale, t)!,
    rotation: lerpDouble(a.rotation, b.rotation, t)!,
    opacity: lerpDouble(a.opacity, b.opacity, t)!,
    blur: math.max(0, lerpDouble(a.blur, b.blur, t)!),
  );

  /// The pose that changes nothing.
  static const MotionPose identity = MotionPose();

  /// A move, in logical pixels.
  final Offset offset;

  /// A move in fractions of the content's own size, added to [offset]:
  /// `Offset(0, -1)` moves content up by its height.
  final Offset offsetFraction;

  /// A uniform scale about the pivot.
  final double scale;

  /// A turn about the pivot, in radians.
  final double rotation;

  /// The opacity, from 0 to 1.
  final double opacity;

  /// The blur sigma, in logical pixels.
  final double blur;

  /// Whether this pose changes nothing.
  bool get isIdentity => this == identity;

  /// The move of content of [size], [offset] and [offsetFraction] together.
  Offset offsetFor(Size size) =>
      offset +
      Offset(offsetFraction.dx * size.width, offsetFraction.dy * size.height);

  /// This pose and [other] worn by the same content at once, as two
  /// motions on one layer add up: moves and turns add, scales and opacities
  /// multiply, and blurs combine as two Gaussian blurs in a row do.
  MotionPose compose(MotionPose other) => MotionPose(
    offset: offset + other.offset,
    offsetFraction: offsetFraction + other.offsetFraction,
    scale: scale * other.scale,
    rotation: rotation + other.rotation,
    opacity: opacity * other.opacity,
    blur: math.sqrt(blur * blur + other.blur * other.blur),
  );

  @override
  bool operator ==(Object other) =>
      other is MotionPose &&
      other.offset == offset &&
      other.offsetFraction == offsetFraction &&
      other.scale == scale &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      other.blur == blur;

  @override
  int get hashCode =>
      Object.hash(offset, offsetFraction, scale, rotation, opacity, blur);

  @override
  String toString() =>
      'MotionPose(offset: $offset, offsetFraction: $offsetFraction, '
      'scale: $scale, rotation: $rotation, opacity: $opacity, blur: $blur)';
}
