import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';
import 'package:meta/meta.dart';

/// Where the rest of a touch goes after a hand-off: a receiving region in
/// another subtree or an overlay (`InputRegion(port:)`), or any receiver
/// given to [attach], such as a session in a replay.
///
/// The source keeps the touch, so nothing is cancelled when the receiver
/// appears above the finger. Forwarded inputs keep their stamps and are
/// mapped into the receiver's coordinates as each one is delivered. While
/// no receiver is bound they wait, so a menu built a frame after the hold
/// still hears the touch from the hand-off on; a touch that ends before a
/// receiver comes is dropped, as its source has ended it.
///
/// ```dart
/// final port = InputPort();
/// LongPressInteraction(onStart: open).sequenced(port.forward);
/// // in the menu: InputZones(port: port, slides: true, zones: rows, ...)
/// ```
final class InputPort {
  /// Creates a port with no receiver.
  InputPort();

  final List<PortEvent> _waiting = [];
  void Function(PortEvent event)? _receiver;

  /// The interaction a source hands a touch on to:
  /// `hold.sequenced(port.forward)`. One source forwards at a time.
  late final Interaction forward = _PortForward(this);

  /// Makes [receiver] the receiver and delivers what waited: how an input
  /// host receives the touches handed to it (`InputRegion(port:)` does).
  ///
  /// The host maps each event into its own coordinates with
  /// [PortEvent.input] as it arrives, and hands the result to its session.
  void attach(void Function(PortEvent event) receiver) {
    _receiver = receiver;
    final waiting = List<PortEvent>.of(_waiting);
    _waiting.clear();
    waiting.forEach(receiver);
  }

  /// Drops [receiver] if it is the receiver.
  ///
  /// Compared by equality, as a method torn off twice is equal but not
  /// identical.
  void detach(void Function(PortEvent event) receiver) {
    if (_receiver == receiver) _receiver = null;
  }

  void _send(PortEvent event) {
    if (event.handOff) _waiting.clear();
    final receiver = _receiver;
    if (receiver != null) {
      receiver(event);
    } else if (event._ends) {
      _waiting.clear();
    } else {
      _waiting.add(event);
    }
  }
}

enum _PortPhase {
  /// The hand-off.
  down,

  /// A move.
  move,

  /// The release.
  up,

  /// The touch ended without a release.
  cancel,
}

/// One pointer input an [InputPort] hands on, in global coordinates, as its
/// receiver hears it ([InputPort.attach]).
@immutable
final class PortEvent {
  const PortEvent._({
    required this._phase,
    required this.time,
    required this.pointer,
    this.position = Offset.zero,
    this._velocity = Offset.zero,
    this._heldStill = false,
    this._kind = PointerDeviceKind.touch,
    this._buttons = kPrimaryButton,
    this._reason = PointerCancelReason.platform,
  });

  final _PortPhase _phase;
  final Offset _velocity;
  final bool _heldStill;
  final PointerDeviceKind _kind;
  final int _buttons;
  final PointerCancelReason _reason;

  /// The input's stamp.
  final double time;

  /// The pointer.
  final int pointer;

  /// Where it is, in global coordinates; zero for a cancel.
  final Offset position;

  /// Whether this is the hand-off: the down that starts the touch in the
  /// receiver. A receiver works out what only a down needs, such as the
  /// scroll views around it, for this one alone.
  bool get handOff => _phase == _PortPhase.down;

  bool get _ends => _phase == _PortPhase.up || _phase == _PortPhase.cancel;

  /// The input in a receiver's coordinates: [toLocal] maps global ones,
  /// and [regionBox] is the receiver's box in them as it is at this input
  /// (see [PointerMoveInput.regionBox]).
  ///
  /// A hand-off is a down in a region of [regionBox]'s size with
  /// [PointerDownInput]'s defaults for what only the receiver knows: its
  /// reach, the scroll views and a host around it, the arena's slop, the
  /// text direction. An
  /// input host builds its own down from the hand-off and gives the later
  /// inputs in the coordinates of that down, as for a touch that landed on
  /// it.
  InteractionInput input(
    Offset Function(Offset global) toLocal, {
    required Rect regionBox,
  }) => switch (_phase) {
    _PortPhase.down => PointerDownInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionSize: regionBox.size,
      globalPosition: position,
      kind: _kind,
      buttons: _buttons,
    ),
    _PortPhase.move => PointerMoveInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionBox: regionBox,
      globalPosition: position,
    ),
    _PortPhase.up => PointerUpInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionBox: regionBox,
      velocity: toLocal(position + _velocity) - toLocal(position),
      heldStill: _heldStill,
      globalPosition: position,
      globalVelocity: _velocity,
    ),
    _PortPhase.cancel => PointerCancelInput(
      time: time,
      pointer: pointer,
      reason: _reason,
    ),
  };
}

/// Package-internal facts of a hand-off, for an input host that builds its
/// own down.
@internal
extension PortEventInternal on PortEvent {
  /// What touched.
  PointerDeviceKind get kind => _kind;

  /// The buttons it pressed.
  int get buttons => _buttons;
}

/// Forwards what it hears to its port, in global coordinates.
final class _PortForward extends Interaction {
  _PortForward(this.port) : super(role: InteractionRole.gesture);

  final InputPort port;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.down,
            time: input.time,
            pointer: input.pointer,
            position: input.globalPosition,
            kind: input.kind,
            buttons: input.buttons,
          ),
        );
      case PointerMoveInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.move,
            time: input.time,
            pointer: input.pointer,
            position: input.globalPosition,
          ),
        );
      case PointerUpInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.up,
            time: input.time,
            pointer: input.pointer,
            position: input.globalPosition,
            velocity: input.globalVelocity,
            heldStill: input.heldStill,
          ),
        );
      case PointerCancelInput():
        port._send(
          PortEvent._(
            phase: _PortPhase.cancel,
            time: input.time,
            pointer: input.pointer,
            reason: input.reason,
          ),
        );
      case PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
    }
    return InteractionUpdate.none;
  }
}
