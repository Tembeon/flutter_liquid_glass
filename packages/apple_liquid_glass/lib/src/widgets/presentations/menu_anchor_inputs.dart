part of 'menu_anchor.dart';

/// The touches of a region over a menu's layer, or of a capture while the
/// menu waits to open, handed to the menu in global coordinates at their
/// stamps.
///
/// It claims a touch at contact, so a scroll view under it never takes one
/// that may choose from the menu. With [takes] it accepts a touch only
/// while that holds.
///
/// In the content role its claims are ignored: a scroll view under it
/// takes a finger that drags, which ends the touch here.
///
/// Once [handsOn] says the menu shows under the finger, asked at each move
/// and at the release, it recognizes the touch, whose rest goes to the
/// menu's layer from that input on.
final class _MenuInput extends Interaction {
  _MenuInput({
    required this.down,
    this.move,
    this.up,
    this.cancel,
    this.takes,
    this.handsOn,
    super.role,
  });

  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global)? move;
  final void Function(int pointer, double t, Offset global)? up;
  final void Function(int pointer, double t)? cancel;
  final bool Function()? takes;
  final bool Function(int pointer, double t)? handsOn;

  int? _pointer;
  bool _handedOn = false;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && (takes?.call() ?? true);

  bool _handOn(int pointer, double t) {
    if (_handedOn) return false;
    return _handedOn = handsOn?.call(pointer, t) ?? false;
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    var claims = false;
    var recognizes = false;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        if (!down(input.pointer, input.time, input.globalPosition)) {
          return InteractionUpdate.none;
        }
        _pointer = input.pointer;
        _handedOn = false;
        claims = true;
      case PointerMoveInput(:final pointer) when pointer == _pointer:
        recognizes = _handOn(pointer, input.time);
        if (!recognizes) move?.call(pointer, input.time, input.globalPosition);
      case PointerUpInput(:final pointer) when pointer == _pointer:
        _pointer = null;
        recognizes = _handOn(pointer, input.time);
        if (!recognizes) up?.call(pointer, input.time, input.globalPosition);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        cancel?.call(input.pointer, input.time);
      default:
    }
    if (!claims && !recognizes) return InteractionUpdate.none;
    return InteractionUpdate(claims: claims, recognizes: recognizes);
  }
}

/// A hold on a menu's source: a long press that takes only the touch
/// [takes] names, the one the menu may open under, and tells
/// [onTouchCancelled] when that touch ends without a release, such as when
/// a scroll view takes it, unless the press has given it up first.
final class _SourceHold extends LongPressInteraction {
  _SourceHold({
    required this.takes,
    this.onTouchCancelled,
    super.duration,
    super.allowableMovement,
    super.armAfter,
    super.contends,
    super.onArmed,
    super.onStart,
    super.onCommit,
    super.onFail,
  });

  final bool Function(int pointer) takes;
  final void Function(int pointer, double t)? onTouchCancelled;

  int? _touch;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && takes(down.pointer);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _touch == null && accepts(input):
        _touch = input.pointer;
      case PointerUpInput(:final pointer) when pointer == _touch:
        _touch = null;
      case PointerCancelInput(:final pointer) when pointer == _touch:
        _touch = null;
        onTouchCancelled?.call(pointer, input.time);
      default:
    }
    final update = super.handle(input);
    if (update.fails) _touch = null;
    return update;
  }
}

/// Escape on an open submenu card sends it back; on the root list it
/// dismisses the menu through the presentation, as an app's remapping of
/// `DismissIntent` does.
class _MenuEscape extends Action<DismissIntent> {
  _MenuEscape(this.layer);

  final _MenuLayerState layer;

  @override
  bool isEnabled(DismissIntent intent) => layer.mounted;

  @override
  Object? invoke(DismissIntent intent) {
    if (layer.current && layer.built.top > 0) {
      layer._keys.back(keys: true);
      return null;
    }
    return Actions.maybeInvoke(layer.context, intent);
  }
}

/// The mouse resting on a row, which moves the focus there.
final class _RowHover extends Interaction {
  _RowHover({required this.onEnter});

  final VoidCallback onEnter;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerHoverInput && input.inside) onEnter();
    return InteractionUpdate.none;
  }
}

/// The mouse moving over the open menu, in the layer's coordinates.
final class _HoverInput extends Interaction {
  _HoverInput({required this.onHover});

  final ValueChanged<Offset> onHover;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input case PointerHoverInput(inside: true, :final position)) {
      onHover(position);
    }
    return InteractionUpdate.none;
  }
}

/// Every touch on a region, heard outside the gesture arena however it
/// decides (a `Listener`'s view), handed on in global coordinates at its
/// stamps.
final class _ObservedTouch extends Interaction {
  _ObservedTouch({required this.down, this.move, this.up, this.cancel})
    : super(role: InteractionRole.observer);

  final void Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global)? move;
  final void Function(int pointer, double t, Offset global)? up;
  final void Function(int pointer, double t)? cancel;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        down(input.pointer, input.time, input.globalPosition);
      case PointerMoveInput():
        move?.call(input.pointer, input.time, input.globalPosition);
      case PointerUpInput():
        up?.call(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput():
        cancel?.call(input.pointer, input.time);
      default:
    }
    return InteractionUpdate.none;
  }
}
