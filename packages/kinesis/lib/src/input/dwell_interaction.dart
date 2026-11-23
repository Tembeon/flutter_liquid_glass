import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';
import 'package:kinesis/src/input/press_reach.dart';

/// A pointer resting over the region for [duration]: how a submenu opens
/// under a finger that slid onto its row, or under the mouse.
///
/// UIKit: none; a `UIMenu` opens a submenu 0.525 s after the finger
/// entered its row, and `NSMenu` after the pointer stays on its item.
/// SwiftUI: none. Flutter: `SubmenuButton.hoverOpenDelay`.
///
/// The wait starts when the pointer enters the region: a touch the region
/// gets, at its contact, a finger that comes back inside the region's
/// reach, or, while [hovers], the mouse moving over it between touches. It
/// ends when the pointer leaves, lifts or is cancelled; moving inside keeps
/// it, as Flutter's submenu does, and a mouse that rests and then presses
/// keeps the wait its entry started. It fires once per entry, at its due
/// time on the motion clock however late the frame that runs it. It never
/// claims a touch, so it sits beside a press, and a gesture that takes the
/// touch, such as a scroll view's drag, ends the wait.
class DwellInteraction extends Interaction {
  /// Creates a dwell of [duration] seconds that calls [onDwell].
  DwellInteraction({required this.duration, this.onDwell, this.hovers = true})
    : assert(duration >= 0, 'a dwell waits forward'),
      super(role: InteractionRole.content);

  /// How long the pointer rests before the dwell fires, in seconds.
  double duration;

  /// Called with the dwell's due time: [duration] after the pointer
  /// entered.
  void Function(double t)? onDwell;

  /// Whether the mouse over the region between touches starts the wait,
  /// as well as a touch; an iPhone menu opens a submenu under a finger
  /// only, and on a click.
  bool hovers;

  int? _pointer;
  PressReach _reach = PressReach.box;
  bool _inside = false;
  double? _due;

  /// Whether the pointer is over the region and the dwell has not fired.
  bool get waiting => _due != null;

  @override
  bool accepts(PointerDownInput down) =>
      _pointer == null && super.accepts(down);

  @override
  double? get nextDue => _due;

  InteractionUpdate _enter(double t) {
    if (_inside) return InteractionUpdate.none;
    _inside = true;
    _due = t + duration;
    return advance(t);
  }

  InteractionUpdate _leave(double t) {
    final update = advance(t);
    _inside = false;
    _due = null;
    return update;
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerHoverInput(:final inside) when _pointer == null:
        if (!inside) return _leave(input.time);
        return hovers ? _enter(input.time) : InteractionUpdate.none;
      case PointerDownInput() when accepts(input):
        _pointer = input.pointer;
        _reach = input.reach;
        return _enter(input.contactTime);
      case PointerMoveInput() when input.pointer == _pointer:
        return _reach.contains(input.regionBox, input.position)
            ? _enter(input.time)
            : _leave(input.time);
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer)
          when pointer == _pointer:
        _pointer = null;
        return _leave(input.time);
      default:
        return InteractionUpdate.none;
    }
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    _due = null;
    onDwell?.call(due);
    return InteractionUpdate.none;
  }
}
