import 'package:flutter/gestures.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';

/// Taps in a row.
///
/// UIKit: `UITapGestureRecognizer`. SwiftUI: `TapGesture`. Flutter:
/// `TapGestureRecognizer` and `DoubleTapGestureRecognizer`.
class TapInteraction extends Interaction {
  /// Creates a tap of [count] taps, each within [slop] of the first and
  /// [interval] seconds of the last; the interval defaults to Flutter's
  /// `kDoubleTapTimeout`.
  TapInteraction({
    super.role,
    this.count = 1,
    this.slop,
    double? interval,
    this.onTap,
  }) : interval = interval ?? kDoubleTapTimeout.inMicroseconds / 1e6;

  /// How many taps make the gesture.
  int count;

  /// How far a tap may land from the first, or null for the slop of the
  /// touch ([PointerDownInput.tapSlop]).
  double? slop;

  /// The longest pause between taps, in seconds.
  double interval;

  /// Called when the taps complete, or on an activation input, with the
  /// time.
  void Function(double t)? onTap;

  int? _pointer;
  double _slop = 0;
  Offset _first = Offset.zero;
  int _taps = 0;
  double? _due;

  @override
  double? get nextDue => _due;

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.activation};

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _slop = slop ?? input.tapSlop;
        if (_taps > 0 && (input.position - _first).distance > _slop) {
          _taps = 0;
        }
        if (_taps == 0) _first = input.position;
        _pointer = input.pointer;
        _due = null;
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        if ((input.position - _first).distance <= _slop) {
          return InteractionUpdate.none;
        }
        _pointer = null;
        _taps = 0;
        return const InteractionUpdate(fails: true);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (++_taps < count) {
          _due = input.time + interval;
          return const InteractionUpdate(claims: true);
        }
        _taps = 0;
        onTap?.call(input.time);
        return InteractionUpdate(
          claims: true,
          recognizes: true,
          events: [
            ActivationEvent(
              time: input.time,
              source: ActivationSource.pointer,
            ),
          ],
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _taps = 0;
        return const InteractionUpdate(fails: true);
      case ActivateInput():
        onTap?.call(input.time);
        return InteractionUpdate(
          events: [ActivationEvent(time: input.time, source: input.source)],
        );
      default:
        return InteractionUpdate.none;
    }
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    _due = null;
    _taps = 0;
    return const InteractionUpdate(fails: true);
  }
}
