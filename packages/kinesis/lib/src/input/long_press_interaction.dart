import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/press_interaction.dart';
import 'package:kinesis/src/input/press_reach.dart';

/// A press held still long enough.
///
/// UIKit: `UILongPressGestureRecognizer`; with [armAfter], the hold of a
/// `UIContextMenuInteraction`. SwiftUI: `LongPressGesture`. Flutter:
/// `LongPressGestureRecognizer`.
///
/// The press is recognized [duration] after contact, at that time however
/// late the frame that runs it, and then holds the touch. Before that, a
/// finger that travels beyond [allowableMovement] fails it, and so does a
/// release. A press with an [armAfter] stage arms at that time: it holds
/// the touch from then on, and a release before [duration] recognizes it
/// at the release instead of failing it. Travel still fails an armed press.
///
/// A press that [contends] takes the touch from the controls inside its
/// region once it arms or is recognized, as a context menu takes it from a
/// button under the finger.
class LongPressInteraction extends Interaction {
  /// Creates a long press of [duration] seconds that fails beyond
  /// [allowableMovement] of travel; the defaults are UIKit's
  /// `UILongPressGestureRecognizer` ones.
  LongPressInteraction({
    super.role,
    this.duration = 0.5,
    this.allowableMovement = 10,
    this.armAfter,
    this.contends = false,
    this.onArmed,
    this.onStart,
    this.onCommit,
    this.onCancel,
    this.onFail,
  }) : assert(
         armAfter == null || (armAfter >= 0 && armAfter <= duration),
         'a press arms before it is recognized',
       );

  /// How long the press is held, from contact, in seconds.
  double duration;

  /// How far the finger may travel before the press fails, or null for as
  /// far as its region holds a press: the press then fails when the finger
  /// leaves the region's [PointerDownInput.reach] around the region's box,
  /// where a [PressInteraction] would drop its highlight.
  double? allowableMovement;

  /// When the press arms, in seconds from contact, or null for a press
  /// without that stage.
  double? armAfter;

  /// Whether the press takes touches from the controls inside its region
  /// ([contendsWithControls]): their claims do not hold a touch below it,
  /// so the press holds it once it arms or is recognized, unless a control
  /// recognizes its gesture first.
  final bool contends;

  /// Called when the press arms, at its due time: [armAfter] after contact.
  void Function(double t)? onArmed;

  /// Called when the press is recognized: at its due time, [duration]
  /// after contact, or at the release of an armed press.
  void Function(double t)? onStart;

  /// Called on the release after the press was recognized, also when the
  /// release recognized it.
  void Function(double t)? onCommit;

  /// Called when a recognized press ends without a release.
  void Function(double t)? onCancel;

  /// Called when a press the finger started fails before it is recognized:
  /// the finger travelled or lifted too early, or the touch was cancelled
  /// or taken.
  void Function(double t)? onFail;

  int? _pointer;
  Offset _origin = Offset.zero;

  /// The pointer of the touch the press follows, or null between touches.
  @protected
  int? get pointer => _pointer;
  PressReach _reach = PressReach.box;
  double? _armDue;
  double? _due;
  bool _armed = false;
  bool _recognized = false;

  @override
  bool get contendsWithControls => contends;

  @override
  double? get nextDue => _armDue ?? _due;

  bool _travelled(PointerMoveInput input) => switch (allowableMovement) {
    final allowed? => (input.position - _origin).distance > allowed,
    null => !_reach.contains(input.regionBox, input.position),
  };

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _origin = input.position;
        _reach = input.reach;
        _armed = false;
        _recognized = false;
        _due = input.contactTime + duration;
        _armDue = switch (armAfter) {
          final after? => input.contactTime + after,
          null => null,
        };
        return advance(input.time);
      case PointerMoveInput() when input.pointer == _pointer:
        if (_recognized || !_travelled(input)) return InteractionUpdate.none;
        return _fail(input.time);
      case PointerUpInput() when input.pointer == _pointer:
        if (_recognized) {
          _reset();
          onCommit?.call(input.time);
          return InteractionUpdate.none;
        }
        if (!_armed) return _fail(input.time);
        final recognized = _recognize(input.time);
        _reset();
        onCommit?.call(input.time);
        return recognized;
      case PointerCancelInput() when input.pointer == _pointer:
        if (!_recognized) return _fail(input.time);
        _reset();
        onCancel?.call(input.time);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }

  @override
  InteractionUpdate advance(double time) {
    var update = InteractionUpdate.none;
    final armDue = _armDue;
    if (armDue != null && time >= armDue) {
      _armDue = null;
      _armed = true;
      onArmed?.call(armDue);
      update = InteractionUpdate(
        claims: true,
        events: [LongPressArmEvent(time: armDue)],
      );
    }
    final due = _due;
    if (due == null || time < due || _armDue != null) return update;
    final recognized = _recognize(due);
    if (identical(update, InteractionUpdate.none)) return recognized;
    return InteractionUpdate(
      claims: true,
      recognizes: true,
      events: [...update.events, ...recognized.events],
    );
  }

  InteractionUpdate _recognize(double t) {
    _due = null;
    _armDue = null;
    _recognized = true;
    onStart?.call(t);
    return InteractionUpdate(
      claims: true,
      recognizes: true,
      events: [LongPressStartEvent(time: t)],
    );
  }

  InteractionUpdate _fail(double t) {
    _reset();
    onFail?.call(t);
    return const InteractionUpdate(fails: true);
  }

  void _reset() {
    _pointer = null;
    _due = null;
    _armDue = null;
    _armed = false;
    _recognized = false;
  }
}
