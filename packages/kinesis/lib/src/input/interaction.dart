import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

/// How a region takes part in a touch that may also scroll.
///
/// UIKit: a control (`UIControl`), content in a scroll view
/// (`delaysContentTouches`) or a gesture recognizer. SwiftUI: a button, a
/// tap in a scroll view, or a `DragGesture`. Flutter: no equivalent.
///
/// The role sets when an interaction hears a touch, and whether its claims
/// hold the touch.
enum InteractionRole {
  /// Hears the touch at once outside a scroll view and
  /// [InteractionSession.scrollDelay] after contact inside one; its claims
  /// hold the touch against the scroll.
  control,

  /// Hears the touch as a control does, but its claims are ignored: a
  /// scroll that starts later takes the touch.
  content,

  /// Hears the touch at contact plus its onset; its claims hold the touch.
  gesture,

  /// Hears every pointer input of each touch on the region at once, at its
  /// stamp, outside the gesture arena: its claims are ignored, a gesture
  /// that takes the touch does not cancel it, and it hears the release or
  /// the platform's cancel however the arena decided. It hears every
  /// pointer it [Interaction.accepts], several at once. A region whose
  /// interactions only observe never joins the arena, so it blocks no
  /// gesture below or around it.
  ///
  /// Flutter: a `Listener`. UIKit: a gesture recognizer that recognizes
  /// simultaneously with every other and cancels no touch.
  observer,
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

/// A step a keyboard key or an accessibility action asks of a value: what
/// a slider, a stepper or a page control does with the arrows, Home and
/// End, Page Up and Page Down.
///
/// UIKit: `accessibilityIncrement` and `accessibilityDecrement`. Flutter:
/// a slider's adjustment intent.
enum ValueCommand {
  /// One step up.
  increase,

  /// One step down.
  decrease,

  /// A larger step up, such as a page.
  increaseLarge,

  /// A larger step down, such as a page.
  decreaseLarge,

  /// To the smallest value.
  toMinimum,

  /// To the largest value.
  toMaximum,
}

/// Which ways an adjustable value can move now: a value at its maximum
/// cannot increase, one at its minimum cannot decrease.
///
/// UIKit: none; a control leaves `accessibilityIncrement` without effect
/// at its end. Flutter: `SemanticsProperties.onIncrease` left null at the
/// maximum, as `Slider` does.
///
/// An input host offers only the value commands it [allows]: the
/// accessibility increase and decrease, and the keys of
/// `AdjustValueIntent`; a key it does not take reaches what lies around
/// the host, as when nothing adjusts.
@immutable
final class AdjustRange {
  /// A value that can [canIncrease] and [canDecrease].
  const AdjustRange({this.canIncrease = true, this.canDecrease = true});

  /// The room of [value] between [min] and [max].
  const AdjustRange.of(
    double value, {
    required double min,
    required double max,
  }) : canIncrease = value < max,
       canDecrease = value > min;

  /// A value with room both ways: what a host assumes when it is given no
  /// range.
  static const AdjustRange open = AdjustRange();

  /// Whether the value can go up.
  final bool canIncrease;

  /// Whether the value can go down.
  final bool canDecrease;

  /// Whether [command] can move the value now.
  bool allows(ValueCommand command) => switch (command) {
    .increase || .increaseLarge || .toMaximum => canIncrease,
    .decrease || .decreaseLarge || .toMinimum => canDecrease,
  };

  @override
  bool operator ==(Object other) =>
      other is AdjustRange &&
      other.canIncrease == canIncrease &&
      other.canDecrease == canDecrease;

  @override
  int get hashCode => Object.hash(canIncrease, canDecrease);

  @override
  String toString() =>
      'AdjustRange(canIncrease: $canIncrease, canDecrease: $canDecrease)';
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
    this._hitArea,
    this._globalPosition,
    this.kind = PointerDeviceKind.touch,
    this.buttons = kPrimaryButton,
    this.scrollAxes = const {},
    this.contested = false,
  }) : contactTime = contactTime ?? time;

  /// The pointer.
  final int pointer;

  /// Where it touched, in the region's coordinates.
  final Offset position;

  final Offset? _globalPosition;

  /// Where it touched, in global coordinates; [position] when the input
  /// did not say, as a replay recorded in the region's coordinates.
  Offset get globalPosition => _globalPosition ?? position;

  /// Whether an interaction around the region takes touches from the
  /// controls inside it ([Interaction.contendsWithControls]), such as a
  /// sheet's pan: the claims of a control then do not hold the touch, so
  /// the pan takes it once the finger travels far enough, and a release
  /// before that still activates the control.
  final bool contested;

  /// The size of the region.
  final Size regionSize;

  final Rect? _hitArea;

  /// Where the region takes pointers, in its coordinates: the region's box,
  /// or a larger rectangle centred on it when the region has a minimum hit
  /// size. A press counts a finger anywhere in it as inside.
  Rect get hitArea => _hitArea ?? Offset.zero & regionSize;

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
    this._globalPosition,
  });

  /// The pointer.
  final int pointer;

  /// Where it is, in the region's coordinates.
  final Offset position;

  final Offset? _globalPosition;

  /// Where it is, in global coordinates; [position] when the input did not
  /// say.
  Offset get globalPosition => _globalPosition ?? position;
}

/// A tracked pointer lifted.
final class PointerUpInput extends InteractionInput {
  /// Creates an up input.
  const PointerUpInput({
    required super.time,
    required this.pointer,
    required this.position,
    this.velocity = Offset.zero,
    this._globalPosition,
    this._globalVelocity,
  });

  /// The pointer.
  final int pointer;

  /// Where it lifted, in the region's coordinates.
  final Offset position;

  /// Its velocity at the lift, in logical pixels per second, estimated
  /// with the lift's own sample.
  final Offset velocity;

  final Offset? _globalPosition;
  final Offset? _globalVelocity;

  /// Where it lifted, in global coordinates; [position] when the input did
  /// not say.
  Offset get globalPosition => _globalPosition ?? position;

  /// [velocity] in global coordinates; [velocity] when the input did not
  /// say.
  Offset get globalVelocity => _globalVelocity ?? velocity;
}

/// The gesture arena gave the region the touch of [pointer]: no other
/// gesture competes for it any more.
///
/// Flutter: `GestureArenaMember.acceptGesture`. An input host sends it when
/// the region is alone in the arena at the touch, when every other gesture
/// gave the touch up, or when the region's own claim took it.
final class PointerAcceptedInput extends InteractionInput {
  /// Creates an acceptance of [pointer].
  const PointerAcceptedInput({required super.time, required this.pointer});

  /// The pointer.
  final int pointer;
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

/// A scroll wheel or a trackpad scrolled over the region.
///
/// It reaches a region's interactions only when one of them
/// [Interaction.takesWheel]; the region then keeps the scroll from the
/// scroll views around it.
final class PointerScrollInput extends InteractionInput {
  /// Creates a scroll input.
  const PointerScrollInput({
    required super.time,
    required this.position,
    required this.scrollDelta,
    this.kind = PointerDeviceKind.mouse,
  });

  /// Where the pointer is, in the region's coordinates.
  final Offset position;

  /// How far the content would scroll, in logical pixels: positive `dy`
  /// scrolls down, toward the end.
  final Offset scrollDelta;

  /// What scrolled.
  final PointerDeviceKind kind;
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

/// The region's value was asked to step without a touch: by a key or an
/// accessibility action.
final class AdjustInput extends InteractionInput {
  /// Creates a value command.
  const AdjustInput({
    required super.time,
    required this.command,
    this.source = ActivationSource.keyboard,
  });

  /// The step asked for.
  final ValueCommand command;

  /// Where it came from: the keyboard or accessibility.
  final ActivationSource source;
}

/// The region was asked for its context menu without a pointer: the
/// context menu key, Shift+F10, or an app's own key for it.
///
/// UIKit: the context menu a hardware keyboard opens on the focused view.
/// Flutter: none; `ContextMenuIntent` in `package:kinesis/widgets.dart`
/// is the intent an input host turns into this input.
final class ContextMenuInput extends InteractionInput {
  /// Creates a request at [position].
  const ContextMenuInput({
    required super.time,
    required this.position,
    this.source = ActivationSource.keyboard,
  });

  /// Where a menu opened for it anchors, in the region's coordinates: the
  /// centre of the region an input host was asked through.
  final Offset position;

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
  const ScrubChangeEvent({
    required super.time,
    required this.selected,
    this.atDown = false,
  });

  /// The region now under the finger, or null.
  final Object? selected;

  /// Whether the change came with the touch-down rather than a move: a
  /// control plays its selection haptic only for a finger that slides.
  final bool atDown;
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

  /// Whether the region's scroll wheel and trackpad scrolls reach this
  /// interaction as [PointerScrollInput]s. While one does, the region keeps
  /// them from the scroll views around it.
  bool get takesWheel => false;

  /// Whether a touch presses the region through this interaction; the
  /// region is `WidgetState.pressed` while one does.
  bool get pressed => false;

  /// Whether this interaction drags; the region is `WidgetState.dragged`
  /// while one does.
  bool get dragged => false;

  /// Whether the keyboard (Space, Enter) and the accessibility tap
  /// activate the region through this interaction ([ActivateInput]).
  bool get activates => false;

  /// Whether this interaction takes touches from the controls inside its
  /// region: below it, a control's claims do not hold a touch
  /// ([PointerDownInput.contested]), so this one can take the touch once
  /// the finger travels, as a sheet's pan does from a button. A
  /// [DragInteraction] with a [DragInteraction.contendedSlop] does.
  bool get contendsWithControls => false;

  /// Whether a request for the region's context menu that comes without a
  /// pointer reaches this interaction as a [ContextMenuInput]: the context
  /// menu key and Shift+F10 when the region has focus.
  bool get opensContextMenu => false;

  /// Whether the region's value commands reach this interaction as
  /// [AdjustInput]s: the arrows, Home and End, Page Up and Page Down when
  /// the region has focus, and the accessibility increase and decrease.
  bool get adjusts => false;

  /// Tells the interaction how its region's coordinates map to global ones.
  ///
  /// An input host calls it for each interaction it hosts before the first
  /// input; `InputPort.forward` hands positions on in global coordinates
  /// with it, and relations pass it to their parts. The default ignores it.
  void bindRegion(Offset Function(Offset local) toGlobal) {}

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

  /// This interaction, and once it recognizes, [next] too: [next] hears
  /// the rest of the touch from a down at the moment this one recognized,
  /// where the finger is then. A hold that opens a menu hands the finger
  /// on to the menu's rows this way, with `InputPort.forward` as [next].
  Interaction sequenced(Interaction next) => _Sequenced(this, next);
}

/// A press that highlights while the finger is inside and activates on a
/// release inside.
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

  /// How far outside the region's hit area
  /// ([PointerDownInput.hitArea]) the finger still counts as inside.
  EdgeInsets releaseSlop;

  /// Called when the highlight turns on or off, with the input's time.
  void Function(double t, {required bool highlighted})? onHighlightChanged;

  /// Called on a release inside, or an activation input, with its time.
  void Function(double t)? onTap;

  int? _pointer;
  Rect _bounds = Rect.zero;
  bool _inside = false;

  /// Whether a press is highlighted.
  bool get highlighted => _pointer != null && _inside;

  @override
  bool get pressed => highlighted;

  @override
  bool get activates => true;

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
        _bounds = releaseSlop.inflateRect(input.hitArea);
        _highlight(true, input.time);
        return InteractionUpdate(claims: role == InteractionRole.control);
      case PointerMoveInput() when input.pointer == _pointer:
        _highlight(_bounds.contains(input.position), input.time);
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        _highlight(_bounds.contains(input.position), input.time);
        final inside = _inside;
        _end(input.time);
        if (!inside) return const InteractionUpdate(fails: true);
        onTap?.call(input.time);
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
        _end(input.time);
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

  void _end(double t) {
    _highlight(false, t);
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

  /// Called when the press is recognized, at its due time: [duration]
  /// after contact, however late the frame that runs it. It then holds the
  /// touch.
  void Function(double t)? onStart;

  /// Called on the release after the press was recognized.
  void Function(double t)? onCommit;

  /// Called when a recognized press ends without a release.
  void Function(double t)? onCancel;

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
        onCommit?.call(input.time);
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final recognized = _recognized;
        _reset();
        if (recognized) onCancel?.call(input.time);
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
    onStart?.call(due);
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
/// Travel counts from past the slop. The drag holds the touch once it
/// starts, unless a scroll view around the region scrolls along its
/// [axis]. A touch that starts within [edgeZone] of the leading edge
/// ([fromEdge]) starts past [edgeSlop], as an interactive pop does, and
/// [mayBegin] can give a touch up while it has not started: a content
/// swipe's funnel. Positions are mirrored when [mirrored], so the leading
/// edge and the travel follow a right-to-left layout. Feed the travel to a
/// `Band` and a release to a `Projection`.
///
/// A drag with a [contendedSlop] competes with the controls inside its
/// region, as UIKit's sheet pan does: alone in the arena it starts past
/// [slop]; while a control under the finger still wants the touch (its
/// press shows at the touch, its claims do not hold the touch against the
/// drag) it starts past [contendedSlop] and takes the touch from the
/// control; a release before that activates the control. A drag that moves
/// the box its region lies in, as a sheet does under the finger, measures
/// in [global] coordinates.
class DragInteraction extends Interaction {
  /// Creates a drag along [axis], or free when [axis] is null, past
  /// UIKit's pan hysteresis of 10 points.
  DragInteraction({
    super.role,
    this.axis,
    this.slop = 10,
    this.contendedSlop,
    this.global = false,
    this.edgeZone = 0,
    this.edgeSlop,
    this.mayBegin,
    this.mirrored = false,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
  });

  /// The axis the drag follows, or null for any direction.
  Axis? axis;

  /// How far the finger travels before the drag starts, once the arena
  /// gave the region the touch ([PointerAcceptedInput]).
  double slop;

  /// How far the finger travels before the drag starts while another
  /// gesture still competes for the touch, or null to start past [slop]
  /// either way. With one the drag [contendsWithControls].
  final double? contendedSlop;

  /// Whether the drag measures the finger in global coordinates
  /// ([PointerDownInput.globalPosition]) instead of its region's: for a
  /// drag that moves its own region, whose coordinates would follow the
  /// finger, and whose scale at the touch would scale the travel. Global
  /// positions are not mirrored.
  bool global;

  /// The share of the region's extent along [axis] (its width for a free
  /// drag) from the leading edge where a touch counts as [fromEdge].
  double edgeZone;

  /// The slop of a touch [fromEdge]; [slop] when null.
  double? edgeSlop;

  /// Asked on every move before the drag starts, with the travel since
  /// contact along [axis]; false gives the touch up.
  bool Function(Offset travel)? mayBegin;

  /// Whether positions are mirrored left to right.
  bool mirrored;

  /// Called when the drag starts.
  ValueChanged<DragInteractionDetails>? onStart;

  /// Called on every move of a started drag.
  ValueChanged<DragInteractionDetails>? onUpdate;

  /// Called on the release of a started drag.
  ValueChanged<DragInteractionDetails>? onEnd;

  /// Called when a started drag ends without a release, with the time.
  void Function(double t)? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  double _width = 0;
  bool _started = false;
  bool _fromEdge = false;
  bool _accepted = false;
  Set<Axis> _scrollAxes = const {};

  /// Whether a drag has started.
  bool get started => _started;

  /// Whether the touch started within [edgeZone] of the leading edge.
  bool get fromEdge => _fromEdge;

  @override
  bool get dragged => _started;

  @override
  bool get contendsWithControls => contendedSlop != null;

  // The slop the drag started past: winning the arena later does not
  // shorten a travel that is already under way.
  double? _startSlop;

  double get _slop {
    if (_startSlop case final started?) return started;
    final own = (_fromEdge ? edgeSlop : null) ?? slop;
    final contended = contendedSlop;
    return _accepted || contended == null ? own : math.max(own, contended);
  }

  Offset _at(Offset local, Offset globalPosition) =>
      global ? globalPosition : _mirror(local);

  Offset _mirror(Offset p) => mirrored ? Offset(_width - p.dx, p.dy) : p;

  Offset _along(Offset delta) => switch (axis) {
    Axis.horizontal => Offset(delta.dx, 0),
    Axis.vertical => Offset(0, delta.dy),
    null => delta,
  };

  Offset _travel(Offset at) {
    final delta = _along(at - _origin);
    final distance = delta.distance;
    if (distance <= _slop) return Offset.zero;
    return delta * ((distance - _slop) / distance);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _width = input.regionSize.width;
        final local = _mirror(input.position);
        _started = false;
        _accepted = false;
        _startSlop = null;
        _scrollAxes = input.scrollAxes;
        final extent = axis == Axis.vertical
            ? input.regionSize.height
            : input.regionSize.width;
        final lead = axis == Axis.vertical ? local.dy : local.dx;
        _fromEdge = lead <= extent * edgeZone;
        _origin = global ? input.globalPosition : local;
        return InteractionUpdate.none;
      case PointerAcceptedInput() when input.pointer == _pointer:
        _accepted = true;
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        final at = _at(input.position, input.globalPosition);
        final travel = _travel(at);
        final details = DragInteractionDetails(
          time: input.time,
          translation: travel,
          velocity: Offset.zero,
        );
        if (!_started) {
          final delta = _along(at - _origin);
          final may = mayBegin;
          if (may != null && !may(delta)) {
            _pointer = null;
            return const InteractionUpdate(fails: true);
          }
          if (delta.distance <= _slop) return InteractionUpdate.none;
          _started = true;
          _startSlop = _slop;
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
        final velocity = global ? input.globalVelocity : input.velocity;
        onEnd?.call(
          DragInteractionDetails(
            time: input.time,
            translation: _travel(_at(input.position, input.globalPosition)),
            velocity: _along(
              mirrored && !global
                  ? Offset(-velocity.dx, velocity.dy)
                  : velocity,
            ),
          ),
        );
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final started = _started;
        _pointer = null;
        _started = false;
        if (started) onCancel?.call(input.time);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }
}

/// Hold-drag-to-select: a finger moves across what [hit] answers, and a
/// release on one commits it.
///
/// UIKit: dragging through a menu's rows or a segmented control's
/// segments. SwiftUI: none. Flutter: none.
///
/// [hit] answers what lies under a position in the region's coordinates
/// (a slot map the layout writes, a motion's row at a point), or null.
class ScrubInteraction extends Interaction {
  /// Creates a scrub over what [hit] answers.
  ScrubInteraction({
    required this.hit,
    super.role,
    this.onChanged,
    this.onCommit,
  });

  /// What lies under a position, or null.
  Object? Function(Offset position) hit;

  /// Called when the finger touches or moves onto something else, or off
  /// everything, with the input's time; with null when the scrub is
  /// cancelled or the finger lifts over nothing.
  void Function(Object? selected, double t)? onChanged;

  /// Called with what lies under a release, and its time.
  void Function(Object selected, double t)? onCommit;

  int? _pointer;
  Object? _selected;

  InteractionUpdate _select(
    double time,
    Offset position, {
    bool atDown = false,
  }) {
    final selected = hit(position);
    if (selected == _selected) return InteractionUpdate.none;
    _selected = selected;
    onChanged?.call(selected, time);
    return InteractionUpdate(
      events: [
        ScrubChangeEvent(time: time, selected: selected, atDown: atDown),
      ],
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _selected = null;
        return _select(input.time, input.position, atDown: true);
      case PointerMoveInput() when input.pointer == _pointer:
        return _select(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        final selected = hit(input.position);
        final was = _selected;
        _selected = null;
        if (selected == null) {
          if (was != null) onChanged?.call(null, input.time);
          return const InteractionUpdate(fails: true);
        }
        onCommit?.call(selected, input.time);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _selected = null;
        onChanged?.call(null, input.time);
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

  /// Called when the taps complete, or on an activation input, with the
  /// time.
  void Function(double t)? onTap;

  int? _pointer;
  Offset _first = Offset.zero;
  int _taps = 0;
  double? _due;

  @override
  double? get nextDue => _due;

  @override
  bool get activates => true;

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

/// A press of the secondary button: a right click, or a two-finger click
/// on a trackpad.
///
/// UIKit: `UIContextMenuInteraction` opened by a secondary click. SwiftUI:
/// `contextMenu` on iPadOS and macOS. Flutter: `onSecondaryTapDown`.
///
/// It reports the press as it happens, where a context menu opens on
/// iPadOS and macOS, and holds the touch until the button lifts. Other
/// interactions take primary presses only, so a region adds this one beside
/// its press without either hearing the other's button. It also
/// [opensContextMenu]: the context menu key and Shift+F10 on the focused
/// region report a click at the region's centre.
class SecondaryClickInteraction extends Interaction {
  /// Creates a secondary click that calls [onClick].
  SecondaryClickInteraction({super.role, this.onClick});

  /// Called with the time of the press, or of the key, and where it is, in
  /// the region's coordinates.
  void Function(double t, Offset position)? onClick;

  int? _pointer;

  @override
  bool get opensContextMenu => true;

  @override
  bool accepts(PointerDownInput down) =>
      _pointer == null && down.buttons & kSecondaryButton != 0;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (!accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        onClick?.call(input.time, input.position);
        return const InteractionUpdate(claims: true, recognizes: true);
      case ContextMenuInput():
        onClick?.call(input.time, input.position);
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        return InteractionUpdate.none;
      default:
        return InteractionUpdate.none;
    }
  }
}

/// The pointer resting over the region for [duration]: how a submenu
/// opens under the mouse.
///
/// UIKit: none on iOS; `NSMenu` opens a submenu after the pointer stays on
/// its item. SwiftUI: none. Flutter: `SubmenuButton.hoverOpenDelay`.
///
/// The wait starts when the pointer enters the region and ends when it
/// leaves; moving inside the region keeps it, as Flutter's submenu does. It
/// fires once per entry, at its due time on the motion clock however late
/// the frame that runs it, and takes no touch, so it sits beside a press.
class HoverDwellInteraction extends Interaction {
  /// Creates a dwell of [duration] seconds that calls [onDwell].
  HoverDwellInteraction({required this.duration, this.onDwell})
    : assert(duration >= 0, 'a dwell waits forward');

  /// How long the pointer rests before the dwell fires, in seconds.
  double duration;

  /// Called with the dwell's due time: [duration] after the pointer
  /// entered.
  void Function(double t)? onDwell;

  bool _inside = false;
  double? _due;

  /// Whether the pointer is over the region and the dwell has not fired.
  bool get waiting => _due != null;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  double? get nextDue => _due;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is! PointerHoverInput) return InteractionUpdate.none;
    if (input.inside) {
      if (_inside) return InteractionUpdate.none;
      _inside = true;
      _due = input.time + duration;
      return advance(input.time);
    }
    final update = advance(input.time);
    _inside = false;
    _due = null;
    return update;
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
      a == InteractionRole.observer && b == InteractionRole.observer
      ? InteractionRole.observer
      : a == InteractionRole.gesture || b == InteractionRole.gesture
      ? InteractionRole.gesture
      : a == InteractionRole.control || b == InteractionRole.control
      ? InteractionRole.control
      : InteractionRole.content;

  @override
  double get onset => math.min(a.onset, b.onset);

  @override
  bool get activates => a.activates || b.activates;

  @override
  bool get adjusts => a.adjusts || b.adjusts;

  @override
  bool get opensContextMenu => a.opensContextMenu || b.opensContextMenu;

  @override
  bool get contendsWithControls =>
      a.contendsWithControls || b.contendsWithControls;

  @override
  bool get takesWheel => a.takesWheel || b.takesWheel;

  @override
  bool get pressed => a.pressed || b.pressed;

  @override
  bool get dragged => a.dragged || b.dragged;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) {
    a.bindRegion(toGlobal);
    b.bindRegion(toGlobal);
  }

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
  bool get activates => a.activates || b.activates;

  @override
  bool get adjusts => a.adjusts || b.adjusts;

  @override
  bool get opensContextMenu => a.opensContextMenu || b.opensContextMenu;

  @override
  bool get contendsWithControls =>
      a.contendsWithControls || b.contendsWithControls;

  @override
  bool get takesWheel => a.takesWheel || b.takesWheel;

  @override
  bool get pressed => a.pressed || b.pressed;

  @override
  bool get dragged => a.dragged || b.dragged;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) {
    a.bindRegion(toGlobal);
    b.bindRegion(toGlobal);
  }

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
            input is PointerCancelInput ||
            input is PointerAcceptedInput)) {
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

final class _Sequenced extends Interaction {
  _Sequenced(this.a, this.b) : super(role: a.role);

  final Interaction a;
  final Interaction b;
  PointerDownInput? _down;
  Offset _latest = Offset.zero;
  Offset _latestGlobal = Offset.zero;
  bool _handedOn = false;

  @override
  double get onset => a.onset;

  @override
  bool get activates => a.activates;

  @override
  bool get adjusts => a.adjusts;

  @override
  bool get opensContextMenu => a.opensContextMenu;

  @override
  bool get contendsWithControls =>
      a.contendsWithControls || b.contendsWithControls;

  @override
  bool get takesWheel => a.takesWheel;

  @override
  bool get pressed => a.pressed || b.pressed;

  @override
  bool get dragged => a.dragged || b.dragged;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) {
    a.bindRegion(toGlobal);
    b.bindRegion(toGlobal);
  }

  @override
  bool accepts(PointerDownInput down) => a.accepts(down);

  InteractionUpdate _fromA(InteractionUpdate update, double time) {
    final down = _down;
    if (!update.recognizes || _handedOn || down == null) return update;
    _handedOn = true;
    return _then(
      update,
      b.handle(
        PointerDownInput(
          time: time,
          pointer: down.pointer,
          position: _latest,
          regionSize: down.regionSize,
          hitArea: down.hitArea,
          globalPosition: _latestGlobal,
          kind: down.kind,
          buttons: down.buttons,
          scrollAxes: down.scrollAxes,
          contested: down.contested,
        ),
      ),
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        _down = input;
        _latest = input.position;
        _latestGlobal = input.globalPosition;
        _handedOn = false;
        return _fromA(a.handle(input), input.time);
      case PointerMoveInput():
        _latest = input.position;
        _latestGlobal = input.globalPosition;
      case PointerUpInput():
        _latest = input.position;
        _latestGlobal = input.globalPosition;
      case PointerAcceptedInput() ||
          PointerCancelInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
    }
    final fromA = _fromA(a.handle(input), input.time);
    if (!_handedOn ||
        input is PointerHoverInput ||
        input is PointerScrollInput ||
        input is ActivateInput ||
        input is AdjustInput ||
        input is ContextMenuInput) {
      return fromA;
    }
    final handed = _then(fromA, b.handle(input));
    if (input is PointerUpInput || input is PointerCancelInput) {
      _down = null;
      _handedOn = false;
    }
    return handed;
  }

  @override
  double? get nextDue =>
      _handedOn ? _earliest(a.nextDue, b.nextDue) : a.nextDue;

  @override
  InteractionUpdate advance(double time) {
    final due = a.nextDue;
    final fromA = due != null && due <= time
        ? _fromA(a.advance(time), due)
        : InteractionUpdate.none;
    if (!_handedOn) return fromA;
    final dueB = b.nextDue;
    if (dueB == null || dueB > time) return fromA;
    return _then(fromA, b.advance(time));
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
/// from recorded input. Observers ([InteractionRole.observer]) hear every
/// pointer they accept at once, beside all of this, and are not cancelled
/// when the touch is [lost].
class InteractionSession {
  /// Creates a session over [interactions].
  InteractionSession(List<Interaction> interactions)
    : interactions = [for (final i in interactions) ..._apart(i)] {
    _observers = [
      for (final i in this.interactions)
        if (i.role == InteractionRole.observer) i,
    ];
  }

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

  late final List<Interaction> _observers;
  final Map<int, List<Interaction>> _observing = {};
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

  /// Whether the session follows [pointer] for its interactions that take
  /// part in the arena: they accepted its down and have not given it up.
  bool follows(int pointer) => _down?.pointer == pointer;

  /// Whether an observer hears [pointer]: one accepted its down and it has
  /// not lifted or been cancelled.
  bool observes(int pointer) => _observing.containsKey(pointer);

  /// The time the next held delivery or timed reaction comes due, a
  /// reaction to hover between touches included.
  double? get nextDue {
    double? due;
    for (final at in _held.values) {
      due = _earliest(due, at);
    }
    for (final interaction in interactions) {
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
  /// Hover, scrolls, activations, value commands and context menu requests
  /// reach every interaction.
  SessionOutput handle(InteractionInput input) {
    final observed = _observe(input);
    final output = _track(input);
    if (observed.events.isEmpty) return output;
    return SessionOutput(
      claim: output.claim,
      reject: output.reject,
      events: [...observed.events, ...output.events],
    );
  }

  SessionOutput _observe(InteractionInput input) {
    final List<Interaction>? observers;
    switch (input) {
      case PointerDownInput(:final pointer):
        observers = [
          for (final observer in _observers)
            if (observer.accepts(input)) observer,
        ];
        if (observers.isEmpty) return SessionOutput.none;
        _observing[pointer] = observers;
      case PointerMoveInput(:final pointer):
        observers = _observing[pointer];
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer):
        observers = _observing.remove(pointer);
      case PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        return SessionOutput.none;
    }
    if (observers == null) return SessionOutput.none;
    final events = <InteractionEvent>[
      for (final observer in observers) ...observer.handle(input).events,
    ];
    return events.isEmpty ? SessionOutput.none : SessionOutput(events: events);
  }

  SessionOutput _track(InteractionInput input) {
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
          if (interaction.role != InteractionRole.observer &&
              interaction.accepts(input)) {
            _accepting.add(interaction);
          }
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
      case PointerAcceptedInput():
        if (_down?.pointer != input.pointer) return SessionOutput.none;
        var output = SessionOutput.none;
        for (final interaction in _accepting) {
          if (!_held.containsKey(interaction) &&
              !_cancelled.contains(interaction)) {
            output = _apply(output, interaction, interaction.handle(input));
          }
        }
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
      case PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        var output = SessionOutput.none;
        for (final interaction in interactions) {
          output = _apply(output, interaction, interaction.handle(input));
        }
        return output;
    }
  }

  /// The touch of [pointer] went to another gesture at [time], or the
  /// region gave it up: held deliveries are dropped and delivered
  /// interactions cancelled. Observers keep hearing it.
  SessionOutput lost(int pointer, double time) => _track(
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
              globalPosition: latest.globalPosition,
            ),
          ),
        );
      }
    }
    for (final interaction in interactions) {
      if (_held.containsKey(interaction) || _cancelled.contains(interaction)) {
        continue;
      }
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
        hitArea: down.hitArea,
        globalPosition: down.globalPosition,
        kind: down.kind,
        buttons: down.buttons,
        scrollAxes: down.scrollAxes,
        contested: down.contested,
      );

  SessionOutput _apply(
    SessionOutput output,
    Interaction interaction,
    InteractionUpdate update,
  ) {
    if (interaction.role == InteractionRole.observer) {
      if (update.events.isEmpty) return output;
      return SessionOutput(
        claim: output.claim,
        reject: output.reject,
        events: [...output.events, ...update.events],
      );
    }
    final holds = switch (interaction.role) {
      InteractionRole.gesture => true,
      InteractionRole.control => !(_down?.contested ?? false),
      InteractionRole.content || InteractionRole.observer => false,
    };
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
