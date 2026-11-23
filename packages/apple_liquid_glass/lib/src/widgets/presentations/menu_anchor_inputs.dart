part of 'menu_anchor.dart';

/// The touches of a region over a menu's source or its layer, handed to
/// the menu in global coordinates at their stamps.
///
/// It hears a touch at contact and claims it [claimAfter] later, when a
/// hold opens the menu under the finger, or at once without one: a scroll
/// view around the source takes a finger that moves before then and never
/// one that may choose from the menu. With [takes] it accepts a touch only
/// while that holds.
///
/// Once [handsOn] says the menu shows under the finger, it recognizes the
/// touch, whose rest goes to the menu's layer, from the input it recognizes
/// at on: asked at the claim, or, for an input that claims at contact, at
/// each move and at the release.
final class _MenuInput extends Interaction {
  _MenuInput({
    required this.down,
    this.move,
    this.up,
    this.cancel,
    this.claimAfter,
    this.contends = false,
    this.takes,
    this.handsOn,
  });

  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global)? move;
  final void Function(int pointer, double t, Offset global)? up;
  final void Function(int pointer, double t)? cancel;
  final double? claimAfter;
  final bool contends;
  final bool Function()? takes;
  final bool Function(int pointer, double t)? handsOn;

  int? _pointer;
  double? _claimAt;
  bool _handedOn = false;

  @override
  bool get contendsWithControls => contends;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && (takes?.call() ?? true);

  @override
  double? get nextDue => _claimAt;

  @override
  InteractionUpdate advance(double time) {
    final due = _claimAt;
    if (due == null || time < due) return InteractionUpdate.none;
    _claimAt = null;
    final pointer = _pointer;
    return InteractionUpdate(
      claims: true,
      recognizes: pointer != null && _handOn(pointer, due),
    );
  }

  bool _handOn(int pointer, double t) {
    if (_handedOn) return false;
    return _handedOn = handsOn?.call(pointer, t) ?? false;
  }

  // An input that claims at contact hands the touch on as it moves or lifts.
  bool _handsOnAt(InteractionInput input, int pointer) =>
      claimAfter == null && _handOn(pointer, input.time);

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
        final after = claimAfter;
        if (after == null) {
          claims = true;
        } else {
          _claimAt = input.time + after;
        }
      case PointerMoveInput(:final pointer) when pointer == _pointer:
        recognizes = _handsOnAt(input, pointer);
        if (!recognizes) move?.call(pointer, input.time, input.globalPosition);
      case PointerUpInput(:final pointer) when pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        recognizes = _handsOnAt(input, pointer);
        if (!recognizes) up?.call(pointer, input.time, input.globalPosition);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        cancel?.call(input.pointer, input.time);
      default:
    }
    if (!claims && !recognizes) return InteractionUpdate.none;
    return InteractionUpdate(claims: claims, recognizes: recognizes);
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
  _ObservedTouch({
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
  }) : super(role: InteractionRole.observer);

  final void Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        down(input.pointer, input.time, input.globalPosition);
      case PointerMoveInput():
        move(input.pointer, input.time, input.globalPosition);
      case PointerUpInput():
        up(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput():
        cancel(input.pointer, input.time);
      default:
    }
    return InteractionUpdate.none;
  }
}
