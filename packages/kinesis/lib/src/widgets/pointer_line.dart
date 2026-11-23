import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/port.dart';
import 'package:kinesis/src/motion/frame_cadence.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/input_target.dart';

// Where a touch began, which decides how its later events reach the line.
sealed class _Origin {}

// A touch whose velocity the line tracks from its own events.
sealed class _Tracked extends _Origin {
  _Tracked(this.tracker);

  final PanVelocityTracker tracker;
}

// On the box, with the gesture arena and the scroll views around it.
final class _Landed extends _Tracked {
  _Landed(super.tracker);
}

// Outside any box, on a screen of [screen], with no scroll view, host or
// arena around it.
final class _Captured extends _Tracked {
  _Captured(this.screen, super.tracker);

  final Size screen;
}

// Handed on by another region: [toLocal] maps its later global events into
// the coordinates of its down, and its release brings its own velocity.
final class _HandedOn extends _Origin {
  _HandedOn(this.toLocal);

  final Matrix4 toLocal;
}

final class _Touch<P extends InputTarget> {
  _Touch(this.down, this.origin);

  // In the coordinates of the line's box.
  final PointerDownInput down;

  final _Origin origin;

  // Null while only observers hear a landed touch, and for any other.
  _ArenaMember? member;

  // The input the pointer's route hands the targets for the event being
  // dispatched, made as the event reached the box.
  InteractionInput? routed;

  InputTarget? base;
  P? part;

  // Whether the finger moves the touch from part to part, and the part it
  // is over, which may have turned the touch down.
  bool slides = false;
  P? over;

  bool baseContends = false;
  bool partContends = false;

  int get pointer => down.pointer;

  bool get contended => baseContends || partContends;

  bool contends(InputTarget target) => identical(target, base)
      ? baseContends
      : identical(target, part) && partContends;

  // Whether target contended until now.
  bool gaveUp(InputTarget target) {
    if (identical(target, base) && baseContends) {
      baseContends = false;
      return true;
    }
    if (identical(target, part) && partContends) {
      partContends = false;
      return true;
    }
    return false;
  }
}

/// The pointers of one render box: turns its pointer events into stamped
/// inputs, keeps the box in the gesture arena, and hands every input to the
/// targets on the touch.
///
/// A touch has up to two targets: the [base], which hears every touch on
/// the box, and the part of type [P] under the finger ([partAt]).
/// `InputRegion` has only a base; in an `InputZones` the parts are the
/// zones and the base is the host's own interactions.
///
/// An interaction of the observer role hears an event as it reaches the
/// box, as a `Listener` does. The others hear it on the pointer's route,
/// where Flutter's recognizers hear it, after the recognizers inside the
/// box: a scroll view inside that passes its slop on the same event takes
/// the touch first, as it would from a recognizer around it. The box stays
/// in the arena for a pointer while a target contends for it, and takes it
/// when one claims.
///
/// The line and its targets do not own each other: the host's state holds
/// both, and each finds the other through it, a target its line through
/// `InputTarget.line` and the line its targets through [base] and
/// [partAt]. While a touch lasts, the line keeps the targets it found at
/// the down on that touch. The host hands every pointer event to the line
/// ([pointer]); the line asks each target's session and gives the answer
/// back to the target (`InputTarget.answer`), which plays the haptics and
/// writes the states. A target calls into the line only to end its touches
/// ([drop]) and to deliver a timed reaction that came due ([due]); keys,
/// hover and accessibility reach a target without the line.
///
/// ```text
/// down: host -> pointer -> line: partAt, then for base and part
///         session.observe + session.track, the arena if one contends,
///         target.answer
/// move: host -> pointer -> line: observers hear it (session.observe)
///       arena route -> line: session.track, a sliding finger handed
///         over to the part under it, target.answer
/// up:   as a move, then the touch leaves the route and the line
/// timer or disable: target -> line.due / line.drop -> target.answer
/// ```
@internal
abstract class PointerLine<P extends InputTarget> {
  final Map<int, _Touch<P>> _touches = {};
  final _PointerSpeed _speed = _PointerSpeed();
  InputPort? _port;

  /// The box whose events these are.
  RenderBox? get box;

  /// Where the box takes pointers and where a press on it holds the finger.
  PressReach get reach => PressReach.box;

  /// The target that hears every touch on the box.
  InputTarget get base;

  /// The element of the box.
  BuildContext get context => base.context;

  /// Whether [context] is still in the tree.
  bool get mounted => base.mounted;

  /// The clock that stamps the events.
  MotionClock get clock => base.clock;

  /// The part that takes input at [position], or null.
  P? partAt(Offset position) => null;

  /// Whether a finger slides from part to part: a touch that lands on a
  /// part, where [slidesFrom] says, or arrives through the [port] stays in
  /// the arena with no part under it, moves on to the part it comes over
  /// as a fresh contact there, and leaves the part it was on when it comes
  /// over none. One touch at a time slides; another one reaches no part.
  bool get slides => false;

  /// Whether a touch that lands at [position] on no part slides.
  bool slidesFrom(Offset position) => false;

  /// A sliding finger moved onto [part].
  void slidOnto(P part, double time) {}

  /// Where touches handed on from another region arrive, or null.
  ///
  /// The port attaches after the current frame. The line maps positions
  /// with its box, laid out in the frame that builds it, and the touches
  /// that waited run interactions that may rebuild or lay out, which that
  /// frame's layout and resolve phases do not allow; the clock's coming
  /// phases can run before that layout when the host is built outside a
  /// frame.
  InputPort? get port => _port;
  set port(InputPort? value) {
    if (identical(value, _port)) return;
    _port?.detach(_receive);
    _port = value;
    if (value == null) return;
    // After the frame: a port delivers in the box's coordinates, which the
    // frame's layout gives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_port, value)) value.attach(_receive);
    });
  }

  /// Lets go of the port.
  void dispose() {
    _port?.detach(_receive);
    _port = null;
  }

  void _receive(PortEvent event) {
    final box = this.box;
    if (box == null || !box.hasSize) return;
    if (event.handOff) {
      final handOff = Matrix4.tryInvert(box.getTransformTo(null));
      if (handOff == null) return;
      clock.input(
        event.time,
        () => _begin(
          _downAt(
            time: event.time,
            pointer: event.pointer,
            position: MatrixUtils.transformPoint(handOff, event.position),
            globalPosition: event.position,
            kind: event.kind,
            buttons: event.buttons,
            regionSize: box.size,
          ),
          _HandedOn(handOff),
        ),
      );
      return;
    }
    final touch = _touches[event.pointer];
    if (touch == null) return;
    if (touch.origin case _HandedOn(:final toLocal)) {
      final input = event.input(
        (global) => MatrixUtils.transformPoint(toLocal, global),
        regionBox: _regionBox(toLocal, touch),
      );
      clock.input(input.time, () {
        _observe(touch, input);
        _track(touch, input);
      });
    }
  }

  /// Takes a pointer event of the box: a down, an event of a touch the
  /// line follows, or the wheel.
  void pointer(PointerEvent event) {
    switch (event) {
      case PointerScrollEvent():
        _wheel(event);
      case PointerDownEvent():
      case _ when _touches.containsKey(event.pointer):
        final time = clock.stamp(event.timeStamp);
        clock.input(time, () => _heard(event, time));
      default:
        break;
    }
  }

  void _wheel(PointerScrollEvent event) {
    final base = this.base;
    final target = switch (partAt(event.localPosition)) {
      final part? when part.takes.contains(InputKind.wheel) => part,
      _ when base.enabled && base.takes.contains(InputKind.wheel) => base,
      _ => null,
    };
    if (target == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!target.mounted || event is! PointerScrollEvent) return;
      target.input(
        PointerScrollInput(
          time: clock.stamp(event.timeStamp),
          position: event.localPosition,
          scrollDelta: event.scrollDelta,
          kind: event.kind,
        ),
      );
    });
  }

  /// Whether the line follows a touch.
  bool get touched => _touches.isNotEmpty;

  /// Whether the line follows the touch of [pointer].
  bool follows(int pointer) => _touches.containsKey(pointer);

  /// Takes an event of a touch that came to no box, in global coordinates
  /// on a [screen] of that size: a down starts a touch the line follows
  /// outside the gesture arena, as one handed on through a [port], and the
  /// later events of a touch it follows reach the targets as they happen.
  void captured(PointerEvent event, Size screen) {
    final time = clock.stamp(event.timeStamp);
    clock.input(time, () => _heard(event, time, screen: screen));
  }

  // A [screen] marks a captured down.
  void _heard(PointerEvent event, double time, {Size? screen}) {
    if (event is PointerDownEvent) {
      final Size size;
      if (screen != null) {
        size = screen;
      } else {
        final box = this.box;
        if (box == null || !box.hasSize) return;
        size = box.size;
      }
      _speed.touched(event.timeStamp);
      final tracker = PanVelocityTracker()
        ..addPosition(time, event.localPosition);
      _begin(
        _downAt(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          globalPosition: event.position,
          kind: event.kind,
          buttons: event.buttons,
          regionSize: size,
          captured: screen != null,
        ),
        screen == null ? _Landed(tracker) : _Captured(screen, tracker),
      );
      return;
    }
    final touch = _touches[event.pointer];
    if (touch == null) return;
    final InteractionInput input;
    switch (event) {
      case PointerMoveEvent():
        if (touch.origin case _Tracked(:final tracker)) {
          tracker.addPosition(time, event.localPosition);
        }
        if (mounted) _speed.moved(event, View.of(context).devicePixelRatio);
        input = PointerMoveInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionBox: _regionBox(event.transform, touch),
          globalPosition: event.position,
        );
      case PointerUpEvent():
        _speed.lifted();
        final (velocity, heldStill) = switch (touch.origin) {
          _Tracked(:final tracker) => (
            tracker.velocityAtLift(time, event.localPosition),
            tracker.heldStillAt(time),
          ),
          _HandedOn() => (Offset.zero, false),
        };
        input = PointerUpInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionBox: _regionBox(event.transform, touch),
          velocity: velocity,
          heldStill: heldStill,
          globalPosition: event.position,
          globalVelocity: _globalVector(
            event.transform,
            velocity,
            event.localPosition,
          ),
        );
      case PointerCancelEvent():
        input = PointerCancelInput(
          time: time,
          pointer: event.pointer,
          reason: PointerCancelReason.platform,
        );
      default:
        return;
    }
    _observe(touch, input);
    if (touch.member != null) {
      touch.routed = input;
    } else if (touch.origin is _Captured) {
      _track(touch, input);
    } else if (input is! PointerMoveInput) {
      _touches.remove(touch.pointer);
    }
  }

  // A captured touch has no scroll view or host around it.
  PointerDownInput _downAt({
    required double time,
    required int pointer,
    required Offset position,
    required Offset globalPosition,
    required PointerDeviceKind kind,
    required int buttons,
    required Size regionSize,
    bool captured = false,
  }) => PointerDownInput(
    time: time,
    pointer: pointer,
    position: position,
    regionSize: regionSize,
    reach: reach,
    globalPosition: globalPosition,
    kind: kind,
    buttons: buttons,
    scrollAxes: captured ? const {} : _scrollAxesAround(context),
    contested: !captured && ContestScope.of(context, listen: false),
    gestureSettings: MediaQuery.maybeGestureSettingsOf(context),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
  );

  // The box as it is now, in the coordinates [toLocal] maps global ones
  // to, which a touch keeps from its down.
  Rect _regionBox(Matrix4? toLocal, _Touch<P> touch) {
    if (touch.origin case _Captured(:final screen)) return Offset.zero & screen;
    final box = this.box;
    if (box == null || !box.attached || !box.hasSize) {
      return Offset.zero & touch.down.regionSize;
    }
    final global = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return toLocal == null
        ? global
        : MatrixUtils.transformRect(toLocal, global);
  }

  void _begin(PointerDownInput down, _Origin origin) {
    final pointer = down.pointer;
    if (_touches.containsKey(pointer)) return;
    final base = this.base.enabled ? this.base : null;
    final landed = partAt(down.position);
    final touch = _Touch<P>(down, origin);
    touch.slides =
        slides &&
        (landed != null || origin is _HandedOn || slidesFrom(down.position)) &&
        !_touches.values.any((other) => other.slides);
    touch.over = landed;
    final part = slides && !touch.slides ? null : landed;
    // Both hear the down before either is answered: a target that takes
    // nothing must not give up a touch the other takes.
    final baseAsked = base == null ? null : _ask(base, down);
    if (base != null && baseAsked != null) {
      touch.baseContends =
          baseAsked.tracked.disposition != GestureDisposition.rejected;
      if (touch.baseContends || base.session.observes(pointer)) {
        touch.base = base;
      }
    }
    final partAsked = part == null ? null : _ask(part, down);
    if (part != null && partAsked != null) {
      touch.partContends =
          partAsked.tracked.disposition != GestureDisposition.rejected;
      if (touch.partContends || part.session.observes(pointer)) {
        touch.part = part;
      }
    }
    if (touch.base != null || touch.part != null || touch.slides) {
      _touches[pointer] = touch;
      if (origin is _Landed && (touch.contended || touch.slides)) {
        final member = _ArenaMember(_lost, _accepted);
        touch.member = member;
        member.entry = GestureBinding.instance.gestureArena.add(
          pointer,
          member,
        );
        GestureBinding.instance.pointerRouter.addRoute(pointer, _route);
      }
    }
    if (base != null && baseAsked != null) {
      base.answer(baseAsked.observed);
      _settle(touch, base, baseAsked.tracked);
    }
    if (part != null && partAsked != null) {
      part.answer(partAsked.observed);
      _settle(touch, part, partAsked.tracked);
    }
  }

  static ({SessionOutput observed, SessionOutput tracked}) _ask(
    InputTarget target,
    PointerDownInput down,
  ) {
    final at = target.local(down);
    return (
      observed: target.session.observe(at),
      tracked: target.session.track(at),
    );
  }

  void _observe(_Touch<P> touch, InteractionInput input) {
    final pointer = touch.pointer;
    if (touch.base case final base? when base.session.observes(pointer)) {
      base.answer(base.session.observe(base.local(input)));
    }
    if (touch.part case final part? when part.session.observes(pointer)) {
      part.answer(part.session.observe(part.local(input)));
    }
  }

  void _route(PointerEvent event) {
    final touch = _touches[event.pointer];
    final input = touch?.routed;
    if (touch == null || input == null) return;
    touch.routed = null;
    clock.input(input.time, () => _track(touch, input));
  }

  void _track(_Touch<P> touch, InteractionInput input) {
    switch (input) {
      case PointerMoveInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (touch.slides &&
            _slide(
              touch,
              time: input.time,
              position: input.position,
              globalPosition: input.globalPosition,
            )) {
          return;
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
      case PointerUpInput() || PointerCancelInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (input case PointerUpInput() when touch.slides) {
          _slide(
            touch,
            time: input.time,
            position: input.position,
            globalPosition: input.globalPosition,
          );
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
        if (identical(_touches[touch.pointer], touch)) {
          _touches.remove(touch.pointer);
        }
        _leave(touch);
      case PointerDownInput() ||
          PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        break;
    }
  }

  // Whether the finger came over another part, or off the one it was on.
  bool _slide(
    _Touch<P> touch, {
    required double time,
    required Offset position,
    required Offset globalPosition,
  }) {
    final to = partAt(position);
    if (identical(to, touch.over)) return false;
    final from = touch.part;
    touch.part = null;
    touch.partContends = false;
    touch.over = to;
    if (from != null) {
      from.answer(
        from.session.handle(
          PointerCancelInput(
            time: time,
            pointer: touch.pointer,
            reason: PointerCancelReason.taken,
          ),
        ),
      );
    }
    if (to == null) return true;
    final output = to.session.handle(
      to.local(
        touch.down.handedOver(
          time: time,
          position: position,
          globalPosition: globalPosition,
        ),
      ),
    );
    if (output.disposition == GestureDisposition.rejected) {
      to.answer(output);
      return true;
    }
    touch.part = to;
    touch.partContends = true;
    slidOnto(to, time);
    _settle(touch, to, output);
    return true;
  }

  // Acts on what a target made of an input of the touch: a claim takes the
  // pointer in the arena, and the box leaves the arena when the last
  // target that contended gives the touch up.
  void _settle(_Touch<P> touch, InputTarget target, SessionOutput output) {
    if (output.disposition == GestureDisposition.accepted) {
      touch.member?.entry?.resolve(GestureDisposition.accepted);
    }
    if (output.disposition == GestureDisposition.rejected &&
        touch.gaveUp(target) &&
        !touch.contended &&
        !touch.slides) {
      touch.member?.entry?.resolve(GestureDisposition.rejected);
    }
    target.answer(output);
  }

  // The box is out of the gesture arena for the touch.
  void _leave(_Touch<P> touch) {
    if (touch.member == null) return;
    touch.member = null;
    touch.routed = null;
    GestureBinding.instance.pointerRouter.removeRoute(touch.pointer, _route);
  }

  void _accepted(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    final time = clock.now;
    final input = PointerAcceptedInput(time: time, pointer: pointer);
    clock.input(time, () {
      if (touch.base case final base?) {
        _settle(touch, base, base.session.handle(input));
      }
      if (touch.part case final part?) {
        _settle(touch, part, part.session.handle(input));
      }
    });
  }

  void _lost(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    _leave(touch);
    final base = touch.base;
    final part = touch.part;
    touch.baseContends = false;
    touch.partContends = false;
    // Observers keep hearing a touch another gesture took.
    if (base != null && !base.session.observes(pointer)) touch.base = null;
    if (part != null && !part.session.observes(pointer)) touch.part = null;
    if (touch.base == null && touch.part == null) _touches.remove(pointer);
    final time = clock.now;
    base?.answer(base.session.lost(pointer, time));
    part?.answer(part.session.lost(pointer, time));
  }

  /// Ends every touch [target] is on, for it alone: it hears a cancel for
  /// [reason], and the box leaves the arena for a touch nothing else
  /// contends for.
  void drop(InputTarget target, PointerCancelReason reason) {
    for (final touch in _touches.values.toList()) {
      if (identical(touch.base, target)) {
        touch.base = null;
        touch.baseContends = false;
      } else if (identical(touch.part, target)) {
        touch.part = null;
        touch.partContends = false;
        // The finger comes onto the part afresh with its next move.
        touch.over = null;
      } else {
        continue;
      }
      if (!touch.contended && !touch.slides) {
        final entry = touch.member?.entry;
        _leave(touch);
        entry?.resolve(GestureDisposition.rejected);
        if (touch.base == null && touch.part == null) {
          _touches.remove(touch.pointer);
        }
      }
      target.answer(
        target.session.handle(
          PointerCancelInput(
            time: clock.now,
            pointer: touch.pointer,
            reason: reason,
          ),
        ),
      );
    }
  }

  /// Acts on what a timed reaction of [target] made, for the touch it
  /// contends for when there is one: a hold that comes due claims the
  /// pointer.
  void due(InputTarget target, SessionOutput output) {
    for (final touch in _touches.values) {
      if (!touch.contends(target)) continue;
      _settle(touch, target, output);
      return;
    }
    target.answer(output);
  }
}

/// An input host's place in the gesture arena for one pointer: it waits for
/// the host to resolve it and tells the host when it won the pointer and
/// when another gesture took it.
final class _ArenaMember extends GestureArenaMember {
  /// Creates a member that calls [onRejected] when it loses its pointer and
  /// [onAccepted] when it wins it.
  _ArenaMember(this.onRejected, this.onAccepted);

  /// Called with the pointer another gesture took.
  final void Function(int pointer) onRejected;

  /// Called with the pointer the arena gave the host.
  final void Function(int pointer) onAccepted;

  /// The arena entry, once the member joined.
  GestureArenaEntry? entry;

  @override
  void acceptGesture(int pointer) => onAccepted(pointer);

  @override
  void rejectGesture(int pointer) => onRejected(pointer);
}

/// The vector [local] at [at] in an event's local coordinates, mapped to
/// global ones through the inverse of the event's [transform].
Offset _globalVector(Matrix4? transform, Offset local, Offset at) {
  if (transform == null) return local;
  final inverse = Matrix4.tryInvert(transform);
  if (inverse == null) return local;
  return MatrixUtils.transformPoint(inverse, at + local) -
      MatrixUtils.transformPoint(inverse, at);
}

/// The axes of the scroll views around [context].
Set<Axis> _scrollAxesAround(BuildContext context) {
  final axes = <Axis>{};
  context.visitAncestorElements((element) {
    if (element case StatefulElement(state: final ScrollableState state)) {
      axes.add(state.position.axis);
    }
    return true;
  });
  return axes;
}

/// Tells the frame cadence how fast a followed pointer moves.
final class _PointerSpeed {
  Duration? _movedAt;

  /// A pointer touched at [stamp].
  void touched(Duration stamp) {
    _movedAt = stamp;
    FrameCadence.instance.input(changed: true);
  }

  /// A followed pointer lifted.
  void lifted() => FrameCadence.instance.input(changed: true);

  /// A followed pointer moved; [devicePixelRatio] turns its travel into
  /// device pixels.
  void moved(PointerMoveEvent event, double devicePixelRatio) {
    final last = _movedAt;
    _movedAt = event.timeStamp;
    if (last == null) return;
    final seconds = (event.timeStamp - last).inMicroseconds / 1e6;
    if (seconds <= 0) return;
    FrameCadence.instance.input(
      pixelsPerSecond: event.delta.distance * devicePixelRatio / seconds,
    );
  }
}
