import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:kinesis/src/input/drag_interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';

part 'package:kinesis/src/input/interaction_relations.dart';
part 'package:kinesis/src/input/interaction_session.dart';

/// A kind of input an [Interaction] takes ([Interaction.takes]).
enum InputKind {
  /// Touches, the mouse and the stylus: [PointerDownInput] and the inputs
  /// of its touch.
  pointer,

  /// The scroll wheel and the trackpad's scrolls, as [PointerScrollInput]s.
  wheel,

  /// Space, Enter and the accessibility tap, as [ActivateInput]s.
  activation,

  /// The value keys of `AdjustValueIntent.defaultShortcuts` and the
  /// accessibility increase and decrease, as [AdjustInput]s.
  adjustment,

  /// A request for the context menu that comes without a pointer (the keys
  /// of `ContextMenuIntent.defaultShortcuts`), as a [ContextMenuInput].
  contextMenu,
}

/// One way a region answers input, such as a press, a long press, a drag,
/// a tap, a dwell or a followed pointer, without widgets, clocks or I/O.
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

  /// Whether the interaction takes a touch that starts with [down]; none
  /// when it does not take [InputKind.pointer].
  bool accepts(PointerDownInput down) =>
      takes.contains(InputKind.pointer) && down.buttons == kPrimaryButton;

  /// The kinds of input that reach this interaction, the same for its
  /// life, as `ScrollBehavior.dragDevices` names the devices that drag.
  ///
  /// A region none of whose interactions takes [InputKind.pointer] is not
  /// hit, its child included, so a touch reaches what lies under it: a
  /// target that only the keyboard and accessibility reach, such as a
  /// sheet's grabber over the sheet's content, which the sheet's own drag
  /// answers. An `InputZones` host whose interactions take none lets a
  /// touch between its zones through. An interaction that declines every
  /// touch while what its region covers stays hit (a wheel's scroll view)
  /// takes pointers and answers [accepts] with false instead.
  ///
  /// While an interaction of a region takes [InputKind.wheel], the region
  /// keeps the scroll wheel from the scroll views around it.
  Set<InputKind> get takes => const {InputKind.pointer};

  /// Whether a touch presses the region through this interaction; the
  /// region is `WidgetState.pressed` while one does.
  bool get pressed => false;

  /// Whether this interaction drags; the region is `WidgetState.dragged`
  /// while one does.
  bool get dragged => false;

  /// Whether this interaction takes touches from the controls inside its
  /// region: below it, a control's claims do not hold a touch
  /// ([PointerDownInput.contested]), so this one can take the touch once
  /// the finger travels, as a sheet's pan does from a button, unless the
  /// control recognizes its gesture first. A
  /// [DragInteraction] that [DragInteraction.contends] does.
  bool get contendsWithControls => false;

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

  /// This interaction, and once it recognizes, [next] too: [next] hears
  /// the rest of the touch from a down at the moment this one recognized,
  /// where the finger is then. The down continues the touch: its
  /// [PointerDownInput.contactTime] is the touch's, so a timed reaction of
  /// [next] counts from when the finger touched. A hold that opens a menu
  /// hands the finger on to the menu's rows this way, with
  /// `InputPort.forward` as [next].
  Interaction sequenced(Interaction next) => _Sequenced(this, next);
}
