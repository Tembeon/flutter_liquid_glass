import 'dart:ui' show Offset, lerpDouble;

import 'package:flutter/foundation.dart';

/// A scalar start-to-end range interpolated linearly by [MotionEffect].
@immutable
final class MotionRange {
  /// Creates a range from [from] (progress `0`) to [to] (progress `1`).
  const MotionRange(this.from, this.to);

  /// The value at progress `0` (absent).
  final double from;

  /// The value at progress `1` (present).
  final double to;

  /// Linearly interpolates between [from] and [to] at [progress] clamped to
  /// `0..1`.
  double lerp(double progress) =>
      lerpDouble(from, to, progress.clamp(0.0, 1.0))!;

  @override
  bool operator ==(Object other) =>
      other is MotionRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'MotionRange($from, $to)';
}

/// How a view enters or leaves: properties that run linearly with one
/// progress from 0 (absent) to 1 (present). Removal plays it backwards.
///
/// UIKit: the from-state of an insertion animation. SwiftUI:
/// `AnyTransition`. Flutter: an `AnimatedSwitcher` transition.
@immutable
final class MotionEffect {
  /// Creates an effect; each [MotionRange] runs from absent (`0`) to present
  /// (`1`).
  const MotionEffect({
    this.opacity,
    this.scale,
    this.blur,
    this.offset,
    this._reduced,
  });

  /// No change: the view is present from the start.
  static const MotionEffect identity = MotionEffect();

  /// A fade from transparent.
  static const MotionEffect fade = MotionEffect(opacity: MotionRange(0, 1));

  /// The opacity range from progress 0 to 1, or null to leave it at 1.
  final MotionRange? opacity;

  /// The scale range from progress 0 to 1, or null to leave it at 1.
  final MotionRange? scale;

  /// The blur sigma range from progress 0 to 1, or null for none.
  final MotionRange? blur;

  /// The offset at progress 0, falling linearly to zero at 1.
  final Offset? offset;

  final MotionEffect? _reduced;

  /// The effect under Reduce Motion: this one's opacity alone unless
  /// given.
  MotionEffect get reduced => _reduced ?? MotionEffect(opacity: opacity);

  /// The opacity at [progress].
  double opacityAt(double progress) => opacity?.lerp(progress) ?? 1;

  /// The scale at [progress].
  double scaleAt(double progress) => scale?.lerp(progress) ?? 1;

  /// The blur sigma at [progress].
  double blurAt(double progress) => blur?.lerp(progress) ?? 0;

  /// The offset at [progress].
  Offset offsetAt(double progress) =>
      (offset ?? Offset.zero) * (1 - progress.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) =>
      other is MotionEffect &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.blur == blur &&
      other.offset == offset &&
      other._reduced == _reduced;

  @override
  int get hashCode => Object.hash(opacity, scale, blur, offset, _reduced);

  @override
  String toString() =>
      'MotionEffect(opacity: $opacity, scale: $scale, blur: $blur, '
      'offset: $offset)';
}
