import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/rubber_band.dart';
import 'package:kinesis/src/spring.dart';
import 'package:kinesis/src/value.dart';

/// How a region takes part in a touch that may also scroll.
///
/// UIKit: a control (`UIControl`), content in a scroll view
/// (`delaysContentTouches`) or a gesture recognizer. SwiftUI: a button, a
/// tap in a scroll view, or a `DragGesture`. Flutter: no equivalent.
///
/// The role sets when an interaction hears a touch, and whether its claims
/// hold the touch.
enum InteractionRole {
  /// Hears the touch at once outside a scroll view and 0.15 s after
  /// contact inside one; its claims hold the touch against the scroll.
  control,

  /// Hears the touch as a control does, but its claims are ignored: a
  /// scroll that starts later takes the touch.
  content,

  /// Hears the touch at contact plus its onset; its claims hold the touch.
  gesture,
}

/// A haptic a control plays for an interaction event.
///
/// UIKit: `UIFeedbackGenerator`. SwiftUI: `SensoryFeedback`. Flutter:
/// `HapticFeedback`.
enum MotionHaptic {
  /// A selection change.
  selection,

  /// A light impact.
  lightImpact,

  /// A medium impact.
  mediumImpact,

  /// A heavy impact.
  heavyImpact,
}

/// Where an activation came from.
enum ActivationSource {
  /// A finger, a pen or the mouse.
  pointer,

  /// The keyboard.
  keyboard,

  /// An accessibility action.
  accessibility,
}

/// Why a touch ended without a release.
enum PointerCancelReason {
  /// The platform cancelled it.
  platform,

  /// Another gesture, such as a scroll, took it.
  taken,

  /// The region was disabled.
  disabled,
}

/// One stamped input to an [InteractionSession], at [time] on the motion
/// clock.
@immutable
sealed class InteractionInput {
  /// Creates an input at [time].
  const InteractionInput({required this.time});

  /// The motion time of the input, in seconds.
  final double time;
}

/// A pointer touched the region.
final class PointerDownInput extends InteractionInput {
  /// Creates a down input.
  const PointerDownInput({
    required super.time,
    required this.pointer,
    required this.position,
    required this.regionSize,
    double? contactTime,
    this.kind = PointerDeviceKind.touch,
    this.buttons = kPrimaryButton,
    this.scrollAxes = const {},
  }) : contactTime = contactTime ?? time;

  /// The pointer.
  final int pointer;

  /// Where it touched, in the region's coordinates.
  final Offset position;

  /// The size of the region.
  final Size regionSize;

  /// When it touched; differs from [time] when the delivery was held back.
  final double contactTime;

  /// What touched.
  final PointerDeviceKind kind;

  /// The buttons it pressed.
  final int buttons;

  /// The axes of the scroll views around the region.
  final Set<Axis> scrollAxes;
}

/// A tracked pointer moved.
final class PointerMoveInput extends InteractionInput {
  /// Creates a move input.
  const PointerMoveInput({
    required super.time,
    required this.pointer,
    required this.position,
  });

  /// The pointer.
  final int pointer;

  /// Where it is, in the region's coordinates.
  final Offset position;
}

/// A tracked pointer lifted.
final class PointerUpInput extends InteractionInput {
  /// Creates an up input.
  const PointerUpInput({
    required super.time,
    required this.pointer,
    required this.position,
    this.velocity = Offset.zero,
  });

  /// The pointer.
  final int pointer;

  /// Where it lifted, in the region's coordinates.
  final Offset position;

  /// Its velocity at the lift, in logical pixels per second, estimated
  /// with the lift's own sample.
  final Offset velocity;
}

/// A tracked pointer ended without a release.
final class PointerCancelInput extends InteractionInput {
  /// Creates a cancel input.
  const PointerCancelInput({
    required super.time,
    required this.pointer,
    required this.reason,
  });

  /// The pointer.
  final int pointer;

  /// Why it ended.
  final PointerCancelReason reason;
}

/// The mouse moved over the region, or left it.
final class PointerHoverInput extends InteractionInput {
  /// Creates a hover input.
  const PointerHoverInput({
    required super.time,
    required this.position,
    required this.inside,
  });

  /// Where the mouse is, in the region's coordinates.
  final Offset position;

  /// Whether the mouse is over the region.
  final bool inside;
}

/// The region was activated without a touch.
final class ActivateInput extends InteractionInput {
  /// Creates an activation.
  const ActivateInput({
    required super.time,
    this.source = ActivationSource.keyboard,
  });

  /// Where it came from.
  final ActivationSource source;
}

/// Something an interaction did at a modelled time, which a control may
/// answer with a haptic.
@immutable
sealed class InteractionEvent {
  /// Creates an event at [time].
  const InteractionEvent({required this.time});

  /// The motion time of the event.
  final double time;
}

/// The region was activated: a tap, a click or an activation input.
final class ActivationEvent extends InteractionEvent {
  /// Creates an activation event.
  const ActivationEvent({required super.time, required this.source});

  /// Where it came from.
  final ActivationSource source;
}

/// A long press was recognized.
final class LongPressStartEvent extends InteractionEvent {
  /// Creates a long press event.
  const LongPressStartEvent({required super.time});
}

/// A scrub moved onto another region.
final class ScrubChangeEvent extends InteractionEvent {
  /// Creates a scrub change.
  const ScrubChangeEvent({required super.time, required this.selected});

  /// The region now under the finger, or null.
  final Object? selected;
}

/// Where a motion value goes after an input: a value on a spring, with
/// the velocity it starts with.
@immutable
final class MotionTarget<T> {
  /// Describes a target.
  const MotionTarget({
    required this.value,
    required this.spring,
    required this.time,
    this.tracking = false,
    this.velocity,
  });

  /// The value to go to.
  final T value;

  /// The spring to go on.
  final Spring spring;

  /// The input's motion time.
  final double time;

  /// Whether a finger drives the value: it follows the tracking spring.
  final bool tracking;

  /// The velocity it starts with, or null to keep its own.
  final T? velocity;

  /// Sends [motionValue] here at the input's own time.
  void applyTo(MotionValue<T> motionValue) {
    final v = velocity;
    if (v != null) motionValue.setVelocity(time, v);
    motionValue.retarget(time, value, spring: spring, tracking: tracking);
  }
}

/// What an interaction made of an input.
@immutable
final class InteractionUpdate {
  /// Describes an update.
  const InteractionUpdate({
    this.claims = false,
    this.recognizes = false,
    this.fails = false,
    this.events = const [],
  });

  /// Nothing happened.
  static const InteractionUpdate none = InteractionUpdate();

  /// Whether the interaction holds the touch against other gestures, as a
  /// tap waiting for its second tap does.
  final bool claims;

  /// Whether the interaction recognized its gesture: the others in its
  /// region stop hearing the touch.
  final bool recognizes;

  /// Whether the interaction gave up the touch.
  final bool fails;

  /// What it did, for haptics.
  final List<InteractionEvent> events;
}

/// One way a region answers input: a press, a long press, a drag, a scrub
/// or a tap, without widgets, clocks or I/O.
///
/// UIKit: a `UIGestureRecognizer` or a control's tracking. SwiftUI: a
/// `Gesture`. Flutter: a `GestureRecognizer` that does not join the arena
/// by itself.
///
/// An interaction is made once by its owner, like a recognizer, and keeps
/// the state of the touch it follows. Every input carries its own time, so
/// an interaction replays recorded input exactly.
abstract class Interaction {
  /// Creates an interaction with [role].
  Interaction({this.role = InteractionRole.gesture});

  /// How the interaction takes part in a touch that may also scroll.
  final InteractionRole role;

  /// Seconds after contact before a [InteractionRole.gesture] hears the
  /// touch; 0 unless an interaction overrides it with a measured onset.
  double get onset => 0;

  /// Whether the interaction takes a touch that starts with [down].
  bool accepts(PointerDownInput down) => down.buttons == kPrimaryButton;

  /// Whether a touch presses the region through this interaction; the
  /// region is `WidgetState.pressed` while one does.
  bool get pressed => false;

  /// Whether this interaction drags; the region is `WidgetState.dragged`
  /// while one does.
  bool get dragged => false;

  /// Answers [input].
  InteractionUpdate handle(InteractionInput input);

  /// The time of its next timed reaction, or null.
  double? get nextDue => null;

  /// Runs its timed reactions due by [time].
  InteractionUpdate advance(double time) => InteractionUpdate.none;

  /// This interaction, or [other] if this one fails before it recognizes:
  /// [other] waits, across touches while this one is undecided, and then
  /// replays the pointer input it missed.
  Interaction exclusively(Interaction other) => _Exclusive(this, other);

  /// This interaction and [other] at once, each hearing the touch when its
  /// own role does.
  Interaction simultaneously(Interaction other) => _Simultaneous(this, other);
}

/// UIKit's control tracking: a press that highlights while the finger is
/// inside, and activates on a release inside.
///
/// UIKit: `UIControl` touch tracking. SwiftUI: a `Button`'s press.
/// Flutter: `InkWell`'s highlight and tap.
class PressInteraction extends Interaction {
  /// Creates a press with [releaseSlop] around the region.
  PressInteraction({
    super.role = InteractionRole.control,
    this.releaseSlop = EdgeInsets.zero,
    this.onHighlightChanged,
    this.onTap,
  });

  /// How far outside the region the finger still counts as inside.
  EdgeInsets releaseSlop;

  /// Called when the highlight turns on or off.
  ValueChanged<bool>? onHighlightChanged;

  /// Called on a release inside, or an activation input.
  VoidCallback? onTap;

  int? _pointer;
  Rect _bounds = Rect.zero;
  bool _inside = false;

  /// Whether a press is highlighted.
  bool get highlighted => _pointer != null && _inside;

  @override
  bool get pressed => highlighted;

  void _highlight(bool on) {
    if (on == _inside) return;
    _inside = on;
    onHighlightChanged?.call(on);
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
        _bounds = releaseSlop.inflateRect(Offset.zero & input.regionSize);
        _highlight(true);
        return InteractionUpdate(claims: role == InteractionRole.control);
      case PointerMoveInput() when input.pointer == _pointer:
        _highlight(_bounds.contains(input.position));
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        _highlight(_bounds.contains(input.position));
        final inside = _inside;
        _end();
        if (!inside) return const InteractionUpdate(fails: true);
        onTap?.call();
        return InteractionUpdate(
          recognizes: true,
          events: [
            ActivationEvent(
              time: input.time,
              source: ActivationSource.pointer,
            ),
          ],
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _end();
        return const InteractionUpdate(fails: true);
      case ActivateInput():
        onTap?.call();
        return InteractionUpdate(
          events: [ActivationEvent(time: input.time, source: input.source)],
        );
      default:
        return InteractionUpdate.none;
    }
  }

  void _end() {
    _highlight(false);
    _pointer = null;
  }
}

/// A press held still long enough.
///
/// UIKit: `UILongPressGestureRecognizer`. SwiftUI: `LongPressGesture`.
/// Flutter: `LongPressGestureRecognizer`.
class LongPressInteraction extends Interaction {
  /// Creates a long press of [duration] seconds that fails beyond
  /// [allowableMovement] of travel; the defaults are UIKit's
  /// `UILongPressGestureRecognizer` ones.
  LongPressInteraction({
    super.role,
    this.duration = 0.5,
    this.allowableMovement = 10,
    this.onStart,
    this.onCommit,
    this.onCancel,
  });

  /// How long the press is held, from contact, in seconds.
  double duration;

  /// How far the finger may travel before the press fails.
  double allowableMovement;

  /// Called when the press is recognized; it then holds the touch.
  VoidCallback? onStart;

  /// Called on the release after the press was recognized.
  VoidCallback? onCommit;

  /// Called when a recognized press ends without a release.
  VoidCallback? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  double? _due;
  bool _recognized = false;

  @override
  double? get nextDue => _due;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _origin = input.position;
        _recognized = false;
        _due = input.contactTime + duration;
        if (input.time >= _due!) return advance(input.time);
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        if (_recognized) return InteractionUpdate.none;
        if ((input.position - _origin).distance <= allowableMovement) {
          return InteractionUpdate.none;
        }
        _reset();
        return const InteractionUpdate(fails: true);
      case PointerUpInput() when input.pointer == _pointer:
        final recognized = _recognized;
        _reset();
        if (!recognized) return const InteractionUpdate(fails: true);
        onCommit?.call();
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final recognized = _recognized;
        _reset();
        if (recognized) onCancel?.call();
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    _due = null;
    _recognized = true;
    onStart?.call();
    return InteractionUpdate(
      claims: true,
      recognizes: true,
      events: [LongPressStartEvent(time: due)],
    );
  }

  void _reset() {
    _pointer = null;
    _due = null;
    _recognized = false;
  }
}

/// Details of a drag at one input.
@immutable
final class DragInteractionDetails {
  /// Describes a drag at [time].
  const DragInteractionDetails({
    required this.time,
    required this.translation,
    required this.velocity,
  });

  /// The input's motion time.
  final double time;

  /// The travel since the slop, along the drag's axis when it has one.
  final Offset translation;

  /// The finger's velocity at the release, in logical pixels per second;
  /// zero before it.
  final Offset velocity;
}

/// A finger dragging past a slop.
///
/// UIKit: `UIPanGestureRecognizer`. SwiftUI: `DragGesture`. Flutter:
/// `PanGestureRecognizer`.
///
/// Travel counts from past the [slop]. The drag holds the touch once it
/// starts, unless a scroll view around the region scrolls along its
/// [axis]. [track] turns the travel into a target for a value, meeting a
/// rubber band past its bounds, and [settle] projects a release with the
/// spring's projection onto the nearest stop.
class DragInteraction extends Interaction {
  /// Creates a drag along [axis], or free when [axis] is null, past
  /// UIKit's pan hysteresis of 10 points.
  DragInteraction({
    super.role,
    this.axis,
    this.slop = 10,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
  });

  /// The axis the drag follows, or null for any direction.
  Axis? axis;

  /// How far the finger travels before the drag starts.
  double slop;

  /// Called when the drag starts.
  ValueChanged<DragInteractionDetails>? onStart;

  /// Called on every move of a started drag.
  ValueChanged<DragInteractionDetails>? onUpdate;

  /// Called on the release of a started drag.
  ValueChanged<DragInteractionDetails>? onEnd;

  /// Called when a started drag ends without a release.
  VoidCallback? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  bool _started = false;
  Set<Axis> _scrollAxes = const {};

  /// Whether a drag has started.
  bool get started => _started;

  @override
  bool get dragged => _started;

  Offset _along(Offset delta) => switch (axis) {
    Axis.horizontal => Offset(delta.dx, 0),
    Axis.vertical => Offset(0, delta.dy),
    null => delta,
  };

  Offset _travel(Offset position) {
    final delta = _along(position - _origin);
    final distance = delta.distance;
    if (distance <= slop) return Offset.zero;
    return delta * ((distance - slop) / distance);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _origin = input.position;
        _started = false;
        _scrollAxes = input.scrollAxes;
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        final travel = _travel(input.position);
        final details = DragInteractionDetails(
          time: input.time,
          translation: travel,
          velocity: Offset.zero,
        );
        if (!_started) {
          if (_along(input.position - _origin).distance <= slop) {
            return InteractionUpdate.none;
          }
          _started = true;
          onStart?.call(details);
          final holds = axis == null || !_scrollAxes.contains(axis);
          return InteractionUpdate(claims: holds, recognizes: holds);
        }
        onUpdate?.call(details);
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        final started = _started;
        _pointer = null;
        _started = false;
        if (!started) return const InteractionUpdate(fails: true);
        onEnd?.call(
          DragInteractionDetails(
            time: input.time,
            translation: _travel(input.position),
            velocity: _along(input.velocity),
          ),
        );
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final started = _started;
        _pointer = null;
        _started = false;
        if (started) onCancel?.call();
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }

  /// The tracking target of a value grabbed at [grab] after [details]:
  /// [grab] plus the travel along [axis], past [bounds] on a rubber band
  /// [dimension] long.
  static MotionTarget<double> track(
    DragInteractionDetails details, {
    required double grab,
    required Spring spring,
    required double dimension,
    Axis axis = Axis.vertical,
    (double, double)? bounds,
  }) {
    final travel = axis == Axis.horizontal
        ? details.translation.dx
        : details.translation.dy;
    return MotionTarget(
      value: _band(grab + travel, bounds, dimension),
      spring: spring,
      time: details.time,
      tracking: true,
    );
  }

  /// The settle target of a value released at [position] after
  /// [details]: projected by the spring's projection, onto the nearest of
  /// [stops] (or within [bounds]), starting with the finger's velocity. A
  /// projection shorter than [minProjection] is dropped: the landing is
  /// [position] before the stops and bounds apply.
  static MotionTarget<double> settle(
    DragInteractionDetails details, {
    required double position,
    required Spring spring,
    Axis axis = Axis.vertical,
    List<double> stops = const [],
    (double, double)? bounds,
    double minProjection = 0,
  }) {
    final velocity = axis == Axis.horizontal
        ? details.velocity.dx
        : details.velocity.dy;
    var landing = position + velocity * spring.projection;
    if ((landing - position).abs() < minProjection) landing = position;
    if (stops.isNotEmpty) {
      landing = stops.reduce(
        (a, b) => (a - landing).abs() <= (b - landing).abs() ? a : b,
      );
    } else if (bounds != null) {
      landing = landing.clamp(bounds.$1, bounds.$2);
    }
    return MotionTarget(
      value: landing,
      spring: spring,
      time: details.time,
      velocity: velocity,
    );
  }

  static double _band(double p, (double, double)? bounds, double dimension) {
    if (bounds == null) return p;
    final (min, max) = bounds;
    if (p < min) return min - rubberBand(min - p, dimension: dimension);
    if (p > max) return max + rubberBand(p - max, dimension: dimension);
    return p;
  }
}

/// Hold-drag-to-select: a finger moves across regions, and a release on
/// one commits it.
///
/// UIKit: dragging through a menu's rows. SwiftUI: none. Flutter: none.
class ScrubInteraction extends Interaction {
  /// Creates a scrub over [regions].
  ScrubInteraction({
    super.role,
    this.regions = const {},
    this.onChanged,
    this.onCommit,
  });

  /// The regions by key, in the region's coordinates.
  Map<Object, Rect> regions;

  /// Called when the finger touches or moves onto another region, or off
  /// them all; with null when the scrub is cancelled.
  ValueChanged<Object?>? onChanged;

  /// Called with the region under a release.
  ValueChanged<Object>? onCommit;

  int? _pointer;
  Object? _selected;

  Object? _at(Offset position) {
    for (final MapEntry(:key, :value) in regions.entries) {
      if (value.contains(position)) return key;
    }
    return null;
  }

  InteractionUpdate _select(double time, Offset position) {
    final selected = _at(position);
    if (selected == _selected) return InteractionUpdate.none;
    _selected = selected;
    onChanged?.call(selected);
    return InteractionUpdate(
      events: [ScrubChangeEvent(time: time, selected: selected)],
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _selected = null;
        return _select(input.time, input.position);
      case PointerMoveInput() when input.pointer == _pointer:
        return _select(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        final selected = _at(input.position);
        _selected = null;
        if (selected == null) return const InteractionUpdate(fails: true);
        onCommit?.call(selected);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _selected = null;
        onChanged?.call(null);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }
}

/// Taps in a row.
///
/// UIKit: `UITapGestureRecognizer`. SwiftUI: `TapGesture`. Flutter:
/// `TapGestureRecognizer` and `DoubleTapGestureRecognizer`.
class TapInteraction extends Interaction {
  /// Creates a tap of [count] taps, each within [slop] of the first and
  /// [interval] seconds of the last; the defaults are Flutter's
  /// `kTouchSlop` and `kDoubleTapTimeout`.
  TapInteraction({
    super.role,
    this.count = 1,
    this.slop = kTouchSlop,
    this.interval = 0.3,
    this.onTap,
  });

  /// How many taps make the gesture.
  int count;

  /// How far a tap may land from the first.
  double slop;

  /// The longest pause between taps, in seconds.
  double interval;

  /// Called when the taps complete.
  VoidCallback? onTap;

  int? _pointer;
  Offset _first = Offset.zero;
  int _taps = 0;
  double? _due;

  @override
  double? get nextDue => _due;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        if (_taps > 0 && (input.position - _first).distance > slop) {
          _taps = 0;
        }
        if (_taps == 0) _first = input.position;
        _pointer = input.pointer;
        _due = null;
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        if ((input.position - _first).distance <= slop) {
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
        onTap?.call();
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
        onTap?.call();
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

InteractionUpdate _then(InteractionUpdate a, InteractionUpdate b) {
  if (identical(b, InteractionUpdate.none)) return a;
  if (identical(a, InteractionUpdate.none)) return b;
  return InteractionUpdate(
    claims: a.claims || b.claims,
    recognizes: a.recognizes || b.recognizes,
    fails: a.fails || b.fails,
    events: [...a.events, ...b.events],
  );
}

double? _earliest(double? a, double? b) =>
    a == null ? b : (b == null ? a : math.min(a, b));

final class _Simultaneous extends Interaction {
  _Simultaneous(this.a, this.b) : super(role: _stronger(a.role, b.role));

  final Interaction a;
  final Interaction b;
  bool _aFailed = false;
  bool _bFailed = false;

  static InteractionRole _stronger(InteractionRole a, InteractionRole b) =>
      a == InteractionRole.gesture || b == InteractionRole.gesture
      ? InteractionRole.gesture
      : a == InteractionRole.control || b == InteractionRole.control
      ? InteractionRole.control
      : InteractionRole.content;

  @override
  double get onset => math.min(a.onset, b.onset);

  @override
  bool accepts(PointerDownInput down) => a.accepts(down) || b.accepts(down);

  InteractionUpdate _both(InteractionUpdate fromA, InteractionUpdate fromB) {
    _aFailed = _aFailed || fromA.fails;
    _bFailed = _bFailed || fromB.fails;
    return InteractionUpdate(
      claims: fromA.claims || fromB.claims,
      recognizes: fromA.recognizes || fromB.recognizes,
      fails: _aFailed && _bFailed,
      events: [...fromA.events, ...fromB.events],
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput) {
      _aFailed = false;
      _bFailed = false;
    }
    return _both(a.handle(input), b.handle(input));
  }

  @override
  double? get nextDue => _earliest(a.nextDue, b.nextDue);

  @override
  InteractionUpdate advance(double time) =>
      _both(a.advance(time), b.advance(time));
}

final class _Exclusive extends Interaction {
  _Exclusive(this.a, this.b) : super(role: a.role);

  final Interaction a;
  final Interaction b;
  final List<InteractionInput> _waiting = [];
  bool _recognized = false;
  bool _aFailed = false;

  @override
  double get onset => a.onset;

  @override
  bool accepts(PointerDownInput down) => a.accepts(down) || b.accepts(down);

  bool get _decided => _recognized || _aFailed;

  InteractionUpdate _fromA(InteractionUpdate update) {
    if (update.recognizes) {
      _recognized = true;
      _waiting.clear();
      return update;
    }
    if (!update.fails) return update;
    _aFailed = true;
    var replayed = InteractionUpdate(claims: update.claims);
    for (final input in _waiting) {
      replayed = _then(replayed, b.handle(input));
    }
    _waiting.clear();
    return replayed;
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput && _decided) {
      _recognized = false;
      _aFailed = false;
      _waiting.clear();
    }
    if (_aFailed) return b.handle(input);
    if (!_recognized &&
        (input is PointerDownInput ||
            input is PointerMoveInput ||
            input is PointerUpInput ||
            input is PointerCancelInput)) {
      _waiting.add(input);
    }
    return _fromA(a.handle(input));
  }

  @override
  double? get nextDue => _aFailed ? b.nextDue : a.nextDue;

  @override
  InteractionUpdate advance(double time) {
    if (_aFailed) return b.advance(time);
    final update = _fromA(a.advance(time));
    if (!_aFailed) return update;
    return _then(update, b.advance(time));
  }
}

/// [interaction] and the interactions its relations hold.
@internal
Iterable<Interaction> flattenInteraction(Interaction interaction) sync* {
  switch (interaction) {
    case _Simultaneous(:final a, :final b) || _Exclusive(:final a, :final b):
      yield* flattenInteraction(a);
      yield* flattenInteraction(b);
    default:
      yield interaction;
  }
}

/// What a session made of an input: whether the region holds or gives up
/// the touch, and the interactions' events.
@immutable
final class SessionOutput {
  /// Describes a session's answer.
  const SessionOutput({
    this.claim = false,
    this.reject = false,
    this.events = const [],
  });

  /// Nothing to do.
  static const SessionOutput none = SessionOutput();

  /// Whether the region holds the touch against other gestures.
  final bool claim;

  /// Whether the region gives the touch up.
  final bool reject;

  /// What the interactions did, for haptics.
  final List<InteractionEvent> events;
}

/// One region's input policy without widgets: who hears which input when,
/// the scroll delay, onsets, claims and loss.
///
/// UIKit: `UIScrollView.delaysContentTouches` with a control's tracking.
/// SwiftUI: a gesture's priority in a scroll view. Flutter: the gesture
/// arena, without its timers.
///
/// A control or content hears a touch at once outside a scroll view and
/// [scrollDelay] after contact inside one; a gesture hears it at contact
/// plus its onset. Interactions joined with [Interaction.simultaneously]
/// each keep their own timing. A touch released while held back is
/// delivered with its release, so a quick tap still activates. A touch
/// that a scroll takes while held back never reaches content; one already
/// delivered is cancelled. When an interaction recognizes its gesture, the
/// others are cancelled for the rest of the touch. Claims of content are
/// ignored. A second pointer during a touch is rejected. Timed deliveries
/// come due at [nextDue] and run in [advance], so scroll timing replays
/// from recorded input.
class InteractionSession {
  /// Creates a session over [interactions].
  InteractionSession(List<Interaction> interactions)
    : interactions = [for (final i in interactions) ..._apart(i)];

  /// UIScrollView's delay before content hears a touch, in seconds.
  static const double scrollDelay = 0.15;

  /// The interactions, with simultaneous ones taken apart; when two
  /// recognize on one input, the first wins.
  final List<Interaction> interactions;

  static Iterable<Interaction> _apart(Interaction interaction) sync* {
    if (interaction case _Simultaneous(:final a, :final b)) {
      yield* _apart(a);
      yield* _apart(b);
    } else {
      yield interaction;
    }
  }

  final List<Interaction> _accepting = [];
  final Set<Interaction> _failed = {};
  final Set<Interaction> _cancelled = {};
  double _time = 0;
  final Map<Interaction, double> _held = {};
  PointerDownInput? _down;
  PointerMoveInput? _latest;
  bool _claimed = false;

  /// Whether a touch is being followed.
  bool get isActive => _down != null;

  /// The time the next held delivery or timed reaction comes due.
  double? get nextDue {
    double? due;
    for (final at in _held.values) {
      due = _earliest(due, at);
    }
    for (final interaction in _accepting) {
      if (!_held.containsKey(interaction) &&
          !_cancelled.contains(interaction)) {
        due = _earliest(due, interaction.nextDue);
      }
    }
    return due;
  }

  double _deliveryTime(Interaction interaction, PointerDownInput down) =>
      switch (interaction.role) {
        InteractionRole.gesture => down.contactTime + interaction.onset,
        _ when down.scrollAxes.isEmpty => down.time,
        _ => down.contactTime + scrollDelay,
      };

  /// Answers a stamped pointer, keyboard, hover or accessibility input.
  SessionOutput handle(InteractionInput input) {
    _time = input.time;
    switch (input) {
      case PointerDownInput():
        if (_down != null) return const SessionOutput(reject: true);
        _accepting.clear();
        _failed.clear();
        _cancelled.clear();
        _held.clear();
        _claimed = false;
        for (final interaction in interactions) {
          if (interaction.accepts(input)) _accepting.add(interaction);
        }
        if (_accepting.isEmpty) return const SessionOutput(reject: true);
        _down = input;
        _latest = null;
        var output = SessionOutput.none;
        for (final interaction in _accepting) {
          final at = _deliveryTime(interaction, input);
          if (at > input.time) {
            _held[interaction] = at;
          } else {
            output = _apply(output, interaction, interaction.handle(input));
          }
        }
        return output;
      case PointerMoveInput():
        if (_down?.pointer != input.pointer) return SessionOutput.none;
        _latest = input;
        var output = advance(input.time);
        for (final interaction in _accepting) {
          if (!_held.containsKey(interaction) &&
              !_cancelled.contains(interaction)) {
            output = _apply(output, interaction, interaction.handle(input));
          }
        }
        return output;
      case PointerUpInput():
        final down = _down;
        if (down == null || down.pointer != input.pointer) {
          return SessionOutput.none;
        }
        var output = advance(input.time);
        for (final interaction in _held.keys.toList()) {
          _held.remove(interaction);
          output = _apply(
            output,
            interaction,
            interaction.handle(_at(down, input.time)),
          );
        }
        for (final interaction in _accepting) {
          if (_cancelled.contains(interaction)) continue;
          output = _apply(output, interaction, interaction.handle(input));
        }
        _end();
        return output;
      case PointerCancelInput():
        final down = _down;
        if (down == null || down.pointer != input.pointer) {
          return SessionOutput.none;
        }
        var output = SessionOutput.none;
        for (final interaction in _accepting) {
          if (!_held.containsKey(interaction) &&
              !_cancelled.contains(interaction)) {
            output = _apply(output, interaction, interaction.handle(input));
          }
        }
        _end();
        return output;
      case PointerHoverInput() || ActivateInput():
        var output = SessionOutput.none;
        for (final interaction in interactions) {
          output = _apply(output, interaction, interaction.handle(input));
        }
        return output;
    }
  }

  /// The touch of [pointer] went to another gesture at [time], or the
  /// region gave it up: held deliveries are dropped and delivered
  /// interactions cancelled.
  SessionOutput lost(int pointer, double time) => handle(
    PointerCancelInput(
      time: time,
      pointer: pointer,
      reason: PointerCancelReason.taken,
    ),
  );

  /// Runs the held deliveries and timed reactions due by [time], each at
  /// its own time.
  SessionOutput advance(double time) {
    _time = time;
    var output = SessionOutput.none;
    final down = _down;
    while (true) {
      Interaction? next;
      double? at;
      for (final MapEntry(:key, :value) in _held.entries) {
        if (value <= time && (at == null || value < at)) {
          next = key;
          at = value;
        }
      }
      if (next == null || at == null || down == null) break;
      _held.remove(next);
      output = _apply(output, next, next.handle(_at(down, at)));
      final latest = _latest;
      if (latest != null) {
        output = _apply(
          output,
          next,
          next.handle(
            PointerMoveInput(
              time: at,
              pointer: latest.pointer,
              position: latest.position,
            ),
          ),
        );
      }
    }
    for (final interaction in _accepting) {
      if (_cancelled.contains(interaction)) continue;
      final due = interaction.nextDue;
      if (due != null && due <= time) {
        output = _apply(output, interaction, interaction.advance(time));
      }
    }
    return output;
  }

  static PointerDownInput _at(PointerDownInput down, double time) =>
      PointerDownInput(
        time: time,
        pointer: down.pointer,
        position: down.position,
        regionSize: down.regionSize,
        contactTime: down.contactTime,
        kind: down.kind,
        buttons: down.buttons,
        scrollAxes: down.scrollAxes,
      );

  SessionOutput _apply(
    SessionOutput output,
    Interaction interaction,
    InteractionUpdate update,
  ) {
    final holds = interaction.role != InteractionRole.content;
    final claim = holds && (update.claims || update.recognizes) && !_claimed;
    if (claim) _claimed = true;
    if (update.recognizes) _recognized(interaction);
    var reject = false;
    if (update.fails &&
        _failed.add(interaction) &&
        !_claimed &&
        _failed.length == _accepting.length) {
      reject = true;
    }
    if (!claim && !reject && update.events.isEmpty) return output;
    return SessionOutput(
      claim: output.claim || claim,
      reject: output.reject || reject,
      events: [...output.events, ...update.events],
    );
  }

  void _recognized(Interaction winner) {
    final pointer = _down?.pointer;
    for (final other in _accepting) {
      if (identical(other, winner) || !_cancelled.add(other)) continue;
      if (_held.remove(other) != null || pointer == null) continue;
      other.handle(
        PointerCancelInput(
          time: _time,
          pointer: pointer,
          reason: PointerCancelReason.taken,
        ),
      );
    }
  }

  void _end() {
    _down = null;
    _latest = null;
    _held.clear();
  }
}
