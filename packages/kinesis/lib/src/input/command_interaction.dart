import 'package:flutter/foundation.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// An interaction that the keyboard and accessibility reach and no touch
/// does: Space, Enter and the accessibility tap call [onActivate], the
/// value keys and the accessibility increase and decrease call [onAdjust].
///
/// UIKit: an accessibility element's `accessibilityActivate` and
/// `accessibilityIncrement`. Flutter: the actions of a `Shortcuts` and
/// `Actions` pair.
///
/// It takes no [InputKind.pointer]: a region that holds only such
/// interactions is not hit, so a touch reaches what lies under it, and a
/// zone's touches stay with what holds the zone. An activation answers
/// with an [ActivationEvent], as a press does.
final class CommandInteraction extends Interaction {
  /// Creates an interaction for [onActivate], [onAdjust] or both.
  CommandInteraction({super.role, this.onActivate, this.onAdjust})
    : assert(
        onActivate != null || onAdjust != null,
        'A CommandInteraction answers an activation, a value command or '
        'both.',
      ),
      takes = {
        if (onActivate != null) InputKind.activation,
        if (onAdjust != null) InputKind.adjustment,
      };

  /// Called with each activation.
  final ValueChanged<ActivateInput>? onActivate;

  /// Called with each value command.
  final ValueChanged<AdjustInput>? onAdjust;

  @override
  final Set<InputKind> takes;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case ActivateInput() when onActivate != null:
        onActivate!(input);
        return InteractionUpdate(
          events: [ActivationEvent(time: input.time)],
        );
      case AdjustInput() when onAdjust != null:
        onAdjust!(input);
      default:
    }
    return InteractionUpdate.none;
  }
}
