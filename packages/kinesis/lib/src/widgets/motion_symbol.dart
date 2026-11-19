import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/measure.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// Hosts a [SymbolEffectMotion] and applies its composed scale, rotation,
/// opacity, and proportional translation to [child] through composited
/// `MotionTransition` layers — performing zero widget rebuilds per frame.
///
/// Trigger effects via `motion.add(t, const BounceSymbolEffect())`,
/// `motion.remove<ScaleSymbolEffect>(t)`, or `motion.removeAll(t)`.
class MotionSymbol extends StatefulWidget {
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
  State<MotionSymbol> createState() => _MotionSymbolState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<SymbolEffectMotion>('motion', motion))
      ..add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
  }
}

class _MotionSymbolState extends State<MotionSymbol> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionSignal<Size> _size = MotionSignal<Size>(
    Size.zero,
    clock: _clock,
  );
  late MotionSelection<Offset> _pixelOffset = _buildOffsetSelection();

  MotionSelection<Offset> _buildOffsetSelection() => MotionSelection<Offset>(
    () {
      final frac = widget.motion.offsetFractionListenable.value;
      final size = _size.value;
      if (frac == Offset.zero || size == Size.zero) return Offset.zero;
      return Offset(frac.dx * size.width, frac.dy * size.height);
    },
    clock: _clock,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.motion.traits = MotionTraitsOverride.of(context);
  }

  @override
  void didUpdateWidget(MotionSymbol oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.motion, oldWidget.motion)) {
      _pixelOffset = _buildOffsetSelection();
    }
  }

  @override
  Widget build(BuildContext context) => MotionMeasure(
    onSize: (t, size) => _size.write(t, size),
    child: MotionTransition(
      alignment: widget.alignment,
      scale: widget.motion.scaleListenable,
      rotation: widget.motion.rotationListenable,
      opacity: widget.motion.opacityListenable,
      offset: _pixelOffset,
      child: widget.child,
    ),
  );
}
