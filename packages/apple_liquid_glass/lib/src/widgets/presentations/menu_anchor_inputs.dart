part of 'menu_anchor.dart';

/// A touch made while the menu waits to open after a tap, which no region
/// lies under yet, handed to the menu in global coordinates at its stamps.
///
/// It accepts a touch only while [takes] holds, and claims it at contact,
/// so a scroll view under it never takes one that may choose from the menu.
/// Once [handsOn] says the menu shows under the finger, asked at each move
/// and at the release, it recognizes the touch, whose rest goes on to the
/// menu's layer from that input on: no kinesis interaction recognizes on a
/// condition of its host. A release before the menu shows ends here, as the
/// port drops a touch that ends before a layer hears it, and the menu keeps
/// that release for its opening ([MenuMotion.releaseBeforeOpen]).
final class _EarlyTouch extends Interaction {
  _EarlyTouch({
    required this.takes,
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
    required this.handsOn,
  });

  final bool Function() takes;
  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;
  final bool Function(int pointer, double t) handsOn;

  int? _pointer;
  bool _handedOn = false;

  @override
  bool accepts(PointerDownInput down) => super.accepts(down) && takes();

  bool _handOn(int pointer, double t) {
    if (_handedOn) return false;
    return _handedOn = handsOn(pointer, t);
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
        if (!recognizes) move(pointer, input.time, input.globalPosition);
      case PointerUpInput(:final pointer) when pointer == _pointer:
        _pointer = null;
        recognizes = _handOn(pointer, input.time);
        if (!recognizes) up(pointer, input.time, input.globalPosition);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        cancel(input.pointer, input.time);
      default:
    }
    if (!claims && !recognizes) return InteractionUpdate.none;
    return InteractionUpdate(claims: claims, recognizes: recognizes);
  }
}

/// What a touch on the open menu's layer does off the rows, which only
/// choose, as on an iPhone 16 Pro ([MenuArea]):
///
/// * one that lands off the menu closes it once it travels
///   [MenuMotion.outsideMoveClose], or after its release
///   ([MenuMotion.closeAfterRelease]);
/// * one that lands on the list beside a submenu card and lifts there sends
///   the card back ([MenuMotion.backAfterRelease]);
/// * one from the top list lifted beside the card sends it back too, and
///   lifted off a menu with no card open closes it; not the finger that
///   held the menu open, which closes nothing, and sends no card back while
///   it rests where it held;
/// * one on a free-form row does neither.
///
/// A touch handed on from the source or the early capture is a touch of the
/// top list wherever it rests. It decides by where the touch the menu
/// follows landed and lifted, and never claims, so the rows and a scroll
/// view under it keep their own.
final class _OffRows extends Interaction {
  _OffRows(this._host) : super(role: InteractionRole.content);

  final _MenuHost<StatefulWidget> _host;

  int? _pointer;
  MenuArea _from = MenuArea.list;
  Offset _start = Offset.zero;
  bool _held = false;
  bool _inPlace = false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final motion = _host._motion;
    if (motion == null) return InteractionUpdate.none;
    switch (input) {
      case PointerDownInput(:final pointer)
          when _pointer == null && pointer == _host._pointer:
        final at = _host._local(input.globalPosition);
        if (pointer == _host._handedOn) {
          _from = MenuArea.list;
          _held = motion.isSliding;
          _inPlace = motion.holdsInPlace;
        } else if (motion.areaAt(at) case final area?) {
          _from = area;
          _held = false;
        } else {
          return InteractionUpdate.none;
        }
        _pointer = pointer;
        _start = at;
      case PointerMoveInput(:final pointer) when pointer == _pointer:
        _inPlace = _inPlace && motion.holdsInPlace;
        final travel = (_host._local(input.globalPosition) - _start).distance;
        if (_from == MenuArea.off &&
            motion.isOpen &&
            travel >= MenuMotion.outsideMoveClose) {
          _pointer = null;
          _host._command((motion, t) => motion.close(t), at: input.time);
        }
      case PointerUpInput(:final pointer) when pointer == _pointer:
        _pointer = null;
        final to = motion.areaAt(_host._local(input.globalPosition));
        if (to == null) break;
        if (_backs(to)) {
          _host._command(
            (motion, t) => motion.backAfterRelease(t),
            at: input.time,
          );
        } else if (_closes(to, motion.topCard)) {
          _host._command(
            (motion, t) => motion.closeAfterRelease(t),
            at: input.time,
          );
        }
      case PointerCancelInput(:final pointer) when pointer == _pointer:
        _pointer = null;
      default:
    }
    return InteractionUpdate.none;
  }

  bool _backs(MenuArea to) =>
      to == MenuArea.beside &&
      switch (_from) {
        MenuArea.beside => true,
        MenuArea.list => !(_held && _inPlace),
        MenuArea.widgetRow || MenuArea.off => false,
      };

  bool _closes(MenuArea to, int topCard) => switch (_from) {
    MenuArea.off => true,
    MenuArea.list => to == MenuArea.off && !_held && topCard == 0,
    MenuArea.widgetRow || MenuArea.beside => false,
  };
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

/// A touch the menu follows, handed on in global coordinates at its
/// stamps.
final class _FollowedTouch extends PointerFollower {
  _FollowedTouch({required this.onDown, this.onMove, this.onUp, this.onCancel});

  final void Function(int pointer, double t, Offset global) onDown;
  final void Function(int pointer, double t, Offset global)? onMove;
  final void Function(int pointer, double t, Offset global)? onUp;
  final void Function(int pointer, double t)? onCancel;

  @override
  void down(PointerDownInput input) =>
      onDown(input.pointer, input.time, input.globalPosition);

  @override
  void move(PointerMoveInput input) =>
      onMove?.call(input.pointer, input.time, input.globalPosition);

  @override
  void up(PointerUpInput input) =>
      onUp?.call(input.pointer, input.time, input.globalPosition);

  @override
  void cancel(PointerCancelInput input) =>
      onCancel?.call(input.pointer, input.time);
}
