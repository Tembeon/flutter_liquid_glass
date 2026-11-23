import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// What follows one touch as it goes: a press body, a lens, a slider's
/// knob, a menu's card. It decides nothing about the touch; the region's
/// other interactions do.
abstract class PointerFollower {
  /// A finger touched at [input]'s position.
  void down(PointerDownInput input);

  /// The finger moved.
  void move(PointerMoveInput input);

  /// The finger lifted.
  void up(PointerUpInput input);

  /// The touch ended without a release.
  void cancel(PointerCancelInput input);

  /// The mouse moved over the region, or left it.
  void hover(PointerHoverInput input) {}
}

/// Feeds one pointer at a time to [follower], and the hover, as they come;
/// it claims nothing and never fails.
///
/// A gesture by default, so it hears the touch at contact even inside a
/// scroll view, which holds back only the region's press: a glass button
/// lifts at once there, as UIKit's does.
final class FollowInteraction extends Interaction {
  /// Creates an interaction that feeds [follower].
  FollowInteraction(this.follower, {super.role});

  /// What hears the touch.
  final PointerFollower follower;

  int? _pointer;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        follower.down(input);
      case PointerMoveInput() when input.pointer == _pointer:
        follower.move(input);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        follower.up(input);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        follower.cancel(input);
      case PointerHoverInput():
        follower.hover(input);
      default:
    }
    return InteractionUpdate.none;
  }
}
