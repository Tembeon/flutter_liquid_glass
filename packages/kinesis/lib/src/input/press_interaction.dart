import 'package:flutter/foundation.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';
import 'package:kinesis/src/input/press_reach.dart';

/// A press that highlights while the finger is inside and activates on a
/// release inside.
///
/// Inside is where the region's [PointerDownInput.reach] holds the finger,
/// applied to the region's box at each input.
///
/// UIKit: `UIControl` touch tracking. SwiftUI: a `Button`'s press.
/// Flutter: `InkWell`'s highlight and tap.
class PressInteraction extends Interaction {
  /// Creates a press.
  PressInteraction({
    super.role = InteractionRole.control,
    this.onHighlightChanged,
    this.onTap,
  });

  /// Called when the highlight turns on or off, with the input's time.
  void Function(double t, {required bool highlighted})? onHighlightChanged;

  /// Called on a release inside, or an activation input, with its time.
  void Function(double t)? onTap;

  int? _pointer;
  PressReach _reach = PressReach.box;

  /// The pointer of the touch the press follows, or null between touches.
  @protected
  int? get pointer => _pointer;
  bool _inside = false;

  @override
  bool get pressed => _pointer != null && _inside;

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.activation};

  void _highlight(bool on, double t) {
    if (on == _inside) return;
    _inside = on;
    onHighlightChanged?.call(t, highlighted: on);
  }

  @override
  bool accepts(PointerDownInput down) =>
      _pointer == null && super.accepts(down);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (!accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _reach = input.reach;
        _highlight(true, input.time);
        return const InteractionUpdate(verdict: .claimed);
      case PointerMoveInput() when input.pointer == _pointer:
        _highlight(
          _reach.contains(input.regionBox, input.position),
          input.time,
        );
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        _highlight(
          _reach.contains(input.regionBox, input.position),
          input.time,
        );
        final inside = _inside;
        _end(input.time);
        if (!inside) return const InteractionUpdate(fails: true);
        onTap?.call(input.time);
        return InteractionUpdate(
          verdict: .recognized,
          events: [
            ActivationEvent(time: input.time),
          ],
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _end(input.time);
        return const InteractionUpdate(fails: true);
      case ActivateInput():
        onTap?.call(input.time);
        return InteractionUpdate(
          events: [ActivationEvent(time: input.time)],
        );
      default:
        return InteractionUpdate.none;
    }
  }

  void _end(double t) {
    _highlight(false, t);
    _pointer = null;
  }
}
