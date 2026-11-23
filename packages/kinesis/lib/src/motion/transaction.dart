import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';

/// The motion preferences a motion honors.
///
/// UIKit: `UIAccessibility.isReduceMotionEnabled`. A motion reads the
/// traits of the `MotionScope` that holds it, which reads
/// `MotionTraitsOverride` or the platform; a value outside a scope reads
/// [MotionTraits.platform].
@immutable
class MotionTraits {
  /// Creates motion preferences.
  const MotionTraits({this.reduceMotion = false});

  /// The platform's preferences: Reduce Motion, which animations the
  /// platform disables count as, and so do [disableAnimations] (a
  /// `MediaQuery`'s).
  factory MotionTraits.platform({bool disableAnimations = false}) {
    final features = PlatformDispatcher.instance.accessibilityFeatures;
    final platform =
        (kDebugMode ? debugPlatformOverride : null) ??
        MotionTraits(
          reduceMotion: features.reduceMotion || features.disableAnimations,
        );
    if (!disableAnimations || platform.reduceMotion) return platform;
    return platform.copyWith(reduceMotion: true);
  }

  /// Whether `withSpring` resolves its spring to the Reduce Motion
  /// alternative (`Spring.reduced`). A retarget that names its spring keeps
  /// it: a measured control applies its own Reduce Motion rule.
  final bool reduceMotion;

  /// A copy with the given fields replaced.
  MotionTraits copyWith({bool? reduceMotion}) =>
      MotionTraits(reduceMotion: reduceMotion ?? this.reduceMotion);

  /// Replaces [MotionTraits.platform] for the whole app in debug builds,
  /// for tests.
  static MotionTraits? debugPlatformOverride;

  @override
  bool operator ==(Object other) =>
      other is MotionTraits && other.reduceMotion == reduceMotion;

  @override
  int get hashCode => reduceMotion.hashCode;

  @override
  String toString() => 'MotionTraits(reduceMotion: $reduceMotion)';
}

/// How the changes made inside one `withAnimation`, `withSpring` or
/// `withoutAnimation` body move.
///
/// SwiftUI: `Transaction`.
///
/// A layout host reads [layoutSpring], the spring of the frame's layout
/// changes, to slide what it lays out on the app's spring.
@immutable
class MotionTransaction {
  const MotionTransaction._({
    required this.animation,
    this.tracking = false,
    this.delay = 0,
  });

  /// The animation the changes follow, resolved for Reduce Motion by each
  /// value from its motion's traits; [Spring.immediate] when they jump.
  final MotionAnimation animation;

  /// Whether a finger drives the changes, so values follow the spring's
  /// tracking spring.
  final bool tracking;

  /// Seconds before the values turn toward their new targets.
  final double delay;

  static final List<MotionTransaction> _stack = [];

  static Spring? _layoutSpring;

  /// The spring of the frame's layout changes: that of the latest outermost
  /// `withSpring` or `withoutAnimation` ([Spring.immediate]) that closed
  /// after the previous frame drew, or null. Layout follows springs only: a
  /// `withAnimation` on a [TimingCurve] leaves it as it was, unless the
  /// curve takes no time and so jumps. A tracking transaction never sets
  /// it, so a finger moving one value does not slide unrelated layout. A
  /// delayed `withSpring` slides layout at once.
  ///
  /// It is kept only while a `MotionResolveHost` is attached, and forgotten
  /// once the frame it belongs to has drawn. A host jumps while it is null
  /// unless it has a spring of its own.
  static Spring? get layoutSpring => _layoutSpring;

  static MotionTransaction? get _current {
    if (_stack.isEmpty) return null;
    for (final transaction in _stack) {
      if (transaction.animation.isImmediate) return transaction;
    }
    return _stack.last;
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
    final spring = switch (transaction.animation) {
      final Spring spring => spring,
      final TimingCurve curve => curve.isImmediate ? Spring.immediate : null,
    };
    if (notify == null || spring == null) return;
    _layoutSpring = spring;
    notify();
  }
}

/// Called when an outermost, non-tracking transaction closes and gives the
/// frame its [MotionTransaction.layoutSpring]; set while a view has layout
/// to animate.
@internal
VoidCallback? onLayoutTransaction;

/// Forgets [MotionTransaction.layoutSpring] once the frame it belongs to
/// has drawn.
@internal
void clearLayoutSpring() => MotionTransaction._layoutSpring = null;

/// The active [MotionTransaction], or null outside a transaction body.
@internal
MotionTransaction? get currentMotionTransaction => MotionTransaction._current;

/// Animates every motion value whose target [changes] sets, using [animation]
/// (a [Spring] or a [TimingCurve]).
///
/// UIKit: `UIView.animate(withDuration:...)` and
/// `UIView.animate(springDuration:bounce:)`. SwiftUI: `withAnimation(_:_:)`.
///
/// Inside an enclosing [withoutAnimation] the changes jump. Under Reduce
/// Motion each value resolves [animation] via [MotionAnimation.resolve]
/// against its motion's [MotionTraits.reduceMotion].
///
/// Layout follows springs only ([MotionTransaction.layoutSpring]). With
/// [tracking] a finger drives the changes,
/// which takes a [Spring]; a tracking change that jumps is
/// `withSpring(Spring.immediate, tracking: true)`.
void withAnimation(
  MotionAnimation animation,
  VoidCallback changes, {
  bool tracking = false,
  double delay = 0,
}) {
  assert(!tracking || animation is Spring, 'A finger tracks on a Spring.');
  MotionTransaction._run(
    MotionTransaction._(animation: animation, tracking: tracking, delay: delay),
    changes,
  );
}

/// Animates every motion value whose target [changes] sets, on [spring].
///
/// UIKit: `UIView.animate(springDuration:bounce:)`. SwiftUI:
/// `withAnimation(_:_:)`.
///
/// A value already moving continues from where it is, at the speed it has
/// plus the spring's retarget [Spring.impulse], if any. With [tracking] the
/// values follow the spring's tracking spring, as they do under a finger.
/// With a [delay] in seconds each value keeps its course for that long
/// before it heads to the new target; its target reads the new value at
/// once. Inside an enclosing [withoutAnimation] the changes jump. Under
/// Reduce Motion each value moves on [spring]'s reduced alternative
/// ([MotionTraits.reduceMotion] of its motion).
///
/// The changes start at the clock's time: inside an input callback that is
/// the input's own stamp (`MotionClock.input`).
///
/// It also animates what layout does in the frame it closes before: a
/// `MotionLayout` slides its children on [spring].
void withSpring(
  Spring spring,
  VoidCallback changes, {
  bool tracking = false,
  double delay = 0,
}) => withAnimation(spring, changes, tracking: tracking, delay: delay);

/// Makes every motion value whose target [changes] sets jump there, even
/// inside an enclosing [withAnimation] or [withSpring].
///
/// UIKit: `UIView.performWithoutAnimation`.
///
/// A `MotionLayout` changed in the frame it closes before jumps too.
void withoutAnimation(VoidCallback changes) => MotionTransaction._run(
  const MotionTransaction._(animation: Spring.immediate),
  changes,
);
