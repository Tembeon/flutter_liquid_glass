import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

part 'package:kinesis/src/motion/spring.dart';
part 'package:kinesis/src/motion/timing.dart';

/// How a value travels from its current state to a new target: either a
/// physically damped [Spring] or a duration-based [TimingCurve].
///
/// UIKit: `UITimingCurveProvider` (`UISpringTimingParameters` and
/// `UICubicTimingParameters`). SwiftUI: `Animation`.
@immutable
sealed class MotionAnimation {
  /// Creates an animation.
  const MotionAnimation();

  /// Whether the animation finishes immediately without traveling over time.
  bool get isImmediate;

  /// The alternative animation to use under Reduce Motion, or null to keep
  /// this animation.
  MotionAnimation? get reduced;

  /// This animation, or its [reduced] alternative when [reduceMotion] holds.
  MotionAnimation resolve({required bool reduceMotion}) =>
      reduceMotion ? (reduced ?? this) : this;
}
