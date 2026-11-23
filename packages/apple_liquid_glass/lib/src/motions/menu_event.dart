import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_placed.dart';

/// What a [MenuMotion] tells its host, at the motion [time] it
/// happened.
sealed class MenuEvent {
  const MenuEvent(this.time);

  /// The motion time of the reaction that raised the event, in seconds.
  final double time;
}

/// The highlighted target changed from [from] to [to] (null for none).
final class MenuHighlightChanged extends MenuEvent {
  /// Creates the event.
  const MenuHighlightChanged(super.time, this.from, this.to);

  /// The target highlighted before, or null.
  final MenuTarget? from;

  /// The target highlighted now, or null.
  final MenuTarget? to;
}

/// The action of [target] runs, before the menu starts closing.
final class MenuActivated extends MenuEvent {
  /// Creates the event.
  const MenuActivated(
    super.time,
    this.target, {
    required this.card,
    required this.index,
  });

  /// The target whose action runs.
  final MenuTarget target;

  /// The card [target] is on, 0 for the root list.
  final int card;

  /// The index of [target] on its card.
  final int index;
}
