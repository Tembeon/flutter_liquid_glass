import 'package:flutter/foundation.dart';
import 'package:kinesis/src/spring.dart';

/// The motion preferences animations honor, which the app mirrors from the
/// platform.
///
/// UIKit: `UIAccessibility.isReduceMotionEnabled`. Flutter:
/// `AccessibilityFeatures.reduceMotion` in `dart:ui`.
abstract final class MotionAccessibility {
  /// Whether `withSpring` resolves its spring to the Reduce Motion
  /// alternative (`Spring.reduced`). A retarget that names its spring keeps
  /// it: a measured control applies its own Reduce Motion rule.
  static bool reduceMotion = false;
}

/// How the changes made inside one `withSpring` or `withoutAnimation` body
/// move.
@immutable
class MotionTransaction {
  const MotionTransaction._({
    required this.spring,
    this.tracking = false,
    this.delay = 0,
  });

  /// The spring the changes follow, already resolved for Reduce Motion;
  /// [Spring.immediate] when they jump.
  final Spring spring;

  /// Whether a finger drives the changes, so values follow the spring's
  /// tracking spring.
  final bool tracking;

  /// Seconds before the values turn toward their new targets.
  final double delay;

  static final List<MotionTransaction> _stack = [];

  static MotionTransaction? _layout;

  /// Called when an outermost, non-tracking transaction closes and becomes
  /// the frame's [layout]; set while a view has layout to animate.
  @internal
  static VoidCallback? onLayoutTransaction;

  /// The transaction of the frame's layout changes: the latest outermost
  /// `withSpring` or `withoutAnimation` that closed since the frame began,
  /// or null. A tracking transaction never sets it, so a finger moving one
  /// value does not slide unrelated layout.
  @internal
  static MotionTransaction? get layout => _layout;

  /// Forgets [layout] once the frame it belongs to has drawn.
  @internal
  static void clearLayout() => _layout = null;

  /// The transaction in effect, or null outside every body.
  ///
  /// An enclosing `withoutAnimation` dominates every spring inside it;
  /// otherwise the innermost spring wins, resolved for Reduce Motion.
  @internal
  static MotionTransaction? get current {
    if (_stack.isEmpty) return null;
    for (final transaction in _stack) {
      if (transaction.spring.isImmediate) return transaction;
    }
    final innermost = _stack.last;
    final spring = innermost.spring.resolve(
      reduceMotion: MotionAccessibility.reduceMotion,
    );
    if (identical(spring, innermost.spring)) return innermost;
    return MotionTransaction._(
      spring: spring,
      tracking: innermost.tracking,
      delay: innermost.delay,
    );
  }

  static void _run(MotionTransaction transaction, VoidCallback changes) {
    _stack.add(transaction);
    try {
      changes();
    } finally {
      _stack.removeLast();
    }
    if (_stack.isNotEmpty || transaction.tracking) return;
    final notify = onLayoutTransaction;
    if (notify == null) return;
    _layout = transaction.spring.isImmediate
        ? transaction
        : MotionTransaction._(
            spring: transaction.spring.resolve(
              reduceMotion: MotionAccessibility.reduceMotion,
            ),
          );
    notify();
  }
}

/// Animates every motion value whose target [changes] sets, on [spring].
///
/// UIKit: `UIView.animate(springDuration:bounce:)`. SwiftUI:
/// `withAnimation(_:_:)`.
///
/// A value already moving continues from where it is, at the speed it has
/// plus the spring's retarget [Spring.impulse], if any.
/// With [tracking] the values follow the spring's tracking spring, as they
/// do under a finger. With a [delay] each value keeps its course for that
/// long before it heads to the new target; its target reads the new value
/// at once. Inside an enclosing [withoutAnimation] the changes jump.
///
/// It also animates what layout does in the frame it closes before: a
/// `MotionLayout` slides its children on [spring].
void withSpring(
  Spring spring,
  VoidCallback changes, {
  bool tracking = false,
  Duration delay = Duration.zero,
}) => MotionTransaction._run(
  MotionTransaction._(
    spring: spring,
    tracking: tracking,
    delay: delay.inMicroseconds / Duration.microsecondsPerSecond,
  ),
  changes,
);

/// Makes every motion value whose target [changes] sets jump there, even
/// inside an enclosing [withSpring].
///
/// UIKit: `UIView.performWithoutAnimation`.
///
/// A `MotionLayout` changed in the frame it closes before jumps too.
void withoutAnimation(VoidCallback changes) => MotionTransaction._run(
  const MotionTransaction._(spring: Spring.immediate),
  changes,
);
