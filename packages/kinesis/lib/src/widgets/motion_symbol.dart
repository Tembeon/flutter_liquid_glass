import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// Hosts a [SymbolEffectMotion] and puts its composed [MotionPose] on
/// [child] through one `MotionTransition` layer, with no rebuild, layout or
/// repaint per frame.
///
/// The motion runs on the clock in a `MotionScope`, which gives it the
/// motion preferences of its place.
///
/// Trigger effects via `motion.add(t, const BounceSymbolEffect())`,
/// `motion.remove<ScaleSymbolEffect>(t)`, or `motion.removeAll(t)`.
class MotionSymbol extends StatelessWidget {
  /// Creates a symbol effect host for [child] driven by [motion].
  const MotionSymbol({
    required this.motion,
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  /// The [SymbolEffectMotion] scheduling effects for [child].
  final SymbolEffectMotion motion;

  /// The symbol or icon widget to animate.
  final Widget child;

  /// The pivot point for scale and rotation effects.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => MotionScope(
    motion: motion,
    child: MotionTransition(
      alignment: alignment,
      pose: motion.poseListenable,
      child: child,
    ),
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<SymbolEffectMotion>('motion', motion))
      ..add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
  }
}
