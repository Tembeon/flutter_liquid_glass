import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/transaction.dart';

/// Holds [motion] on its clock while this widget is in the tree, so the
/// clock steps it whenever it moves, and gives it the motion preferences
/// of its place ([MotionTraitsOverride], else the platform and
/// `MediaQuery.disableAnimations`).
///
/// Under a muted `TickerMode` the motion is not stepped; nothing is lost,
/// because a motion is a function of its commands: shown again, it reads
/// where it would be.
class MotionScope extends StatefulWidget {
  /// Holds [motion] for [child].
  const MotionScope({required this.motion, required this.child, super.key});

  /// The motion held.
  final Motion motion;

  /// The subtree that shows the motion.
  final Widget child;

  @override
  State<MotionScope> createState() => _MotionScopeState();
}

class _MotionScopeState extends State<MotionScope> {
  Motion? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final motion = widget.motion;
    motion.traits = MotionTraitsOverride.of(context);
    final next = TickerMode.valuesOf(context).enabled ? motion : null;
    if (identical(next, _held)) return;
    _held?.unretain();
    next?.retain();
    _held = next;
  }

  @override
  void dispose() {
    _held?.unretain();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Gives the motions under it these motion preferences instead of the
/// platform's.
class MotionTraitsOverride extends InheritedWidget {
  /// Gives [traits] to the motions in [child].
  const MotionTraitsOverride({
    required this.traits,
    required super.child,
    super.key,
  });

  /// The preferences the motions below read.
  final MotionTraits traits;

  /// The preferences at [context]: the nearest override, else the platform
  /// with `MediaQuery.disableAnimations`.
  static MotionTraits of(BuildContext context) {
    final override = context
        .dependOnInheritedWidgetOfExactType<MotionTraitsOverride>();
    if (override != null) return override.traits;
    final platform = MotionTraits.platform();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disabled || platform.reduceMotion) return platform;
    return MotionTraits(
      reduceMotion: true,
      preferCrossFade: platform.preferCrossFade,
    );
  }

  @override
  bool updateShouldNotify(MotionTraitsOverride oldWidget) =>
      traits != oldWidget.traits;
}
