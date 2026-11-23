import 'dart:math' as math;

import 'package:kinesis/motion.dart';

/// A finger resting on a context menu's view before its menu opens, as
/// UIKit's `UIContextMenuInteraction` runs it (measured on iPhone 16 Pro,
/// iOS 27, context-menu.md): the view grows by [growthAfter] while the
/// finger rests.
///
/// The hold itself is a long press its host recognizes, staged by
/// [commitAfter] and [openAfter] and dropped beyond the touch's slop of
/// travel; the host starts the growth at the touch ([down]) and ends it
/// when the hold opens the menu or drops ([release]).
final class ContextHold extends Motion {
  /// Creates a hold no finger rests on.
  ContextHold({super.clock});

  /// UIKit's growth of a held view before its menu opens, in points along
  /// its longest side, after [held] seconds: nothing for 0.184 s, then 32
  /// points a second to 8 points, then 20 a second to 15 points (within
  /// 0.21 points of every frame).
  static double growthAfter(double held) {
    if (held <= _growthStart) return 0;
    if (held <= _growthKnee) return _growthFastRate * (held - _growthStart);
    return math.min(
      _growthKneePoints + _growthSlowRate * (held - _growthKnee),
      _growthPoints,
    );
  }

  static const double _growthStart = 0.184;
  static const double _growthKnee = 0.434;
  static const double _growthFastRate = 32;
  static const double _growthSlowRate = 20;
  static const double _growthPoints = 15;
  static const double _growthKneePoints =
      _growthFastRate * (_growthKnee - _growthStart);

  /// The hold time past which a release opens the menu anyway, and the
  /// view's own controls no longer get the touch (0.400 s cancelled and
  /// 0.433 s opened).
  static const double commitAfter = 0.42;

  /// The hold time at which the menu opens under the finger (measured
  /// 0.768 - 0.797 s).
  static const double openAfter = 0.78;

  double? _since;

  /// Whether a finger rests on the view.
  bool get isHeld => _since != null;

  /// The view's growth now, 0 while no finger rests on it.
  double get growth => growthAt(now);

  /// The view's growth at time [t], 0 while no finger rests on it.
  double growthAt(double t) => switch (_since) {
    final since? => growthAfter(t - since),
    null => 0,
  };

  @override
  bool get holds => isHeld;

  /// A finger came to rest on the view at time [t].
  void down(double t) {
    advance(t);
    _since = t;
    changed();
  }

  /// The hold ended at time [t]: it opened the menu, or the finger lifted
  /// early, moved off or was cancelled. The view drops back at once.
  /// Answers the growth it had then.
  double release(double t) {
    advance(t);
    final grown = growthAt(t);
    _since = null;
    changed();
    return grown;
  }
}
