import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:meta/meta.dart';

/// Where the rest of a touch goes after a hand-off: a receiving region in
/// another subtree or an overlay (`InputRegion(port:)`), or a session bound
/// with [bind].
///
/// The source keeps the touch, so nothing is cancelled when the receiver
/// appears above the finger. Forwarded inputs keep their stamps and are
/// mapped into the receiver's coordinates as each one is delivered. While
/// no receiver is bound they wait, so a menu built a frame after the hold
/// still hears the touch from the hand-off on.
///
/// ```dart
/// final port = InputPort();
/// LongPressInteraction(onStart: open).sequenced(port.forward);
/// // in the menu: InputRegion(port: port, interactions: [scrub], ...)
/// ```
final class InputPort {
  /// Creates a port with no receiver.
  InputPort();

  final List<PortEvent> _waiting = [];
  void Function(PortEvent event)? _receiver;

  /// The interaction a source hands a touch on to:
  /// `hold.sequenced(port.forward)`. One source forwards at a time.
  late final Interaction forward = PortForward(this);

  /// Delivers forwarded touches to [receiver] without widgets, mapped by
  /// [transform] from the source's coordinates into the receiver's, in a
  /// region of [size]; for replays.
  void bind(
    InteractionSession receiver, {
    Matrix4? transform,
    Size size = Size.zero,
  }) => attach(
    (event) => receiver.handle(
      event.input(
        transform == null
            ? (p) => p
            : (p) => MatrixUtils.transformPoint(transform, p),
        size: size,
      ),
    ),
  );

  /// Drops the receiver; later inputs wait for the next one.
  void unbind() => _receiver = null;

  /// Makes [receiver] the receiver and delivers what waited.
  @internal
  void attach(void Function(PortEvent event) receiver) {
    _receiver = receiver;
    final waiting = List<PortEvent>.of(_waiting);
    _waiting.clear();
    waiting.forEach(receiver);
  }

  /// Drops [receiver] if it is the receiver.
  @internal
  void detach(void Function(PortEvent event) receiver) {
    if (identical(_receiver, receiver)) _receiver = null;
  }

  void _send(PortEvent event) {
    if (event.phase == PortPhase.down) _waiting.clear();
    final receiver = _receiver;
    if (receiver == null) {
      _waiting.add(event);
      return;
    }
    receiver(event);
  }
}

/// The phase of a forwarded pointer.
@internal
enum PortPhase {
  /// The hand-off.
  down,

  /// A move.
  move,

  /// The release.
  up,

  /// The touch ended without a release.
  cancel,
}

/// One forwarded pointer input, in global coordinates.
@internal
@immutable
final class PortEvent {
  /// Creates a forwarded input.
  const PortEvent({
    required this.phase,
    required this.time,
    required this.pointer,
    this.position = Offset.zero,
    this.velocity = Offset.zero,
    this.kind = PointerDeviceKind.touch,
    this.buttons = kPrimaryButton,
    this.reason = PointerCancelReason.platform,
  });

  /// What happened.
  final PortPhase phase;

  /// The input's stamp.
  final double time;

  /// The pointer.
  final int pointer;

  /// Where it is, in global coordinates.
  final Offset position;

  /// Its velocity at a release, in global coordinates.
  final Offset velocity;

  /// What touched.
  final PointerDeviceKind kind;

  /// The buttons it pressed.
  final int buttons;

  /// Why a cancelled touch ended.
  final PointerCancelReason reason;

  /// The input in a receiver's coordinates, [toLocal] mapping global ones;
  /// a hand-off is a down in a region of [size] inside scroll views along
  /// [scrollAxes].
  InteractionInput input(
    Offset Function(Offset global) toLocal, {
    required Size size,
    Set<Axis> scrollAxes = const {},
  }) => switch (phase) {
    PortPhase.down => PointerDownInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      regionSize: size,
      kind: kind,
      buttons: buttons,
      scrollAxes: scrollAxes,
    ),
    PortPhase.move => PointerMoveInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
    ),
    PortPhase.up => PointerUpInput(
      time: time,
      pointer: pointer,
      position: toLocal(position),
      velocity: toLocal(position + velocity) - toLocal(position),
    ),
    PortPhase.cancel => PointerCancelInput(
      time: time,
      pointer: pointer,
      reason: reason,
    ),
  };
}

/// Forwards what it hears to its port, mapped to global coordinates by
/// [toGlobal], which the source region sets.
@internal
final class PortForward extends Interaction {
  /// Creates a forwarder to [port].
  PortForward(this.port) : super(role: InteractionRole.gesture);

  /// Where it forwards.
  final InputPort port;

  /// Maps the source region's coordinates to global ones; identity when
  /// null.
  Offset Function(Offset local)? toGlobal;

  Offset _global(Offset p) => toGlobal?.call(p) ?? p;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        port._send(
          PortEvent(
            phase: PortPhase.down,
            time: input.time,
            pointer: input.pointer,
            position: _global(input.position),
            kind: input.kind,
            buttons: input.buttons,
          ),
        );
      case PointerMoveInput():
        port._send(
          PortEvent(
            phase: PortPhase.move,
            time: input.time,
            pointer: input.pointer,
            position: _global(input.position),
          ),
        );
      case PointerUpInput():
        final at = _global(input.position);
        port._send(
          PortEvent(
            phase: PortPhase.up,
            time: input.time,
            pointer: input.pointer,
            position: at,
            velocity: _global(input.position + input.velocity) - at,
          ),
        );
      case PointerCancelInput():
        port._send(
          PortEvent(
            phase: PortPhase.cancel,
            time: input.time,
            pointer: input.pointer,
            reason: input.reason,
          ),
        );
      case PointerHoverInput() || ActivateInput():
    }
    return InteractionUpdate.none;
  }
}
