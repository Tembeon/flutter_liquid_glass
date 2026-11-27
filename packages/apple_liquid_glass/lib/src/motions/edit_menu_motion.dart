import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// UIKit's edit menu as it opens (edit menu passport, iOS 27.2 simulator):
/// the bar grows from [hiddenScale] to full size about its edge that faces
/// the point it shows from, its opacity `(scale - 0.2) / 0.8`, on
/// [presentSpring]. Under Reduce Motion it only fades in, on the same
/// spring.
final class EditMenuMotion {
  /// Creates the motion of a hidden menu on [clock].
  EditMenuMotion({required MotionClock clock})
    : _shown = MotionValue<double>(hiddenScale, clock: clock);

  /// The scale a menu opens from: the first frame shows it at a fifth.
  static const double hiddenScale = 0.2;

  /// The spring of the opening: omega 26.75, zeta 0.94 fitted (peak 1.005
  /// at 0.35 s).
  @internal
  static const presentSpring = Spring.response(0.23, dampingRatio: 0.94);

  final MotionValue<double> _shown;
  bool _reduced = false;

  /// The bar's scale about its edge that faces the point.
  late final MotionSelection<double> scale = MotionSelection(
    clock: _shown.clock,
    () => _reduced ? 1 : _shown.value,
  );

  /// The bar's opacity.
  late final MotionSelection<double> opacity = MotionSelection(
    clock: _shown.clock,
    () => ((_shown.value - hiddenScale) / (1 - hiddenScale)).clamp(0, 1),
  );

  /// Opens the menu; [reduceMotion] keeps it at full size while it fades
  /// in.
  void present({required bool reduceMotion}) {
    _reduced = reduceMotion;
    withSpring(presentSpring, () => _shown.target = 1);
  }
}
