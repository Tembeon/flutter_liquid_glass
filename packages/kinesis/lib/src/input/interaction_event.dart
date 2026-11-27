import 'package:flutter/foundation.dart';

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
  const ActivationEvent({required super.time});
}

/// A long press with an arming stage armed: a release from now on
/// recognizes it (`LongPressInteraction.armAfter`).
final class LongPressArmEvent extends InteractionEvent {
  /// Creates an arming event.
  const LongPressArmEvent({required super.time});
}

/// A long press was recognized.
final class LongPressStartEvent extends InteractionEvent {
  /// Creates a long press event.
  const LongPressStartEvent({required super.time});
}

/// A finger that slides across the targets of a control moved onto
/// another one: what `InputZones(slides:)` reports to its feedback for each
/// zone the finger slides onto, never for the one it lands on.
final class ScrubChangeEvent extends InteractionEvent {
  /// Creates the event.
  const ScrubChangeEvent({required super.time});
}

/// How far an interaction has taken a touch, each one holding what the
/// one before it holds.
enum InteractionVerdict {
  /// It has not taken the touch.
  none,

  /// It holds the touch against other gestures, as a tap waiting for its
  /// second tap does.
  claimed,

  /// It recognized its gesture: it holds the touch, and the others in its
  /// region stop hearing it.
  recognized,
}

/// What an interaction made of an input.
@immutable
final class InteractionUpdate {
  /// Describes an update.
  const InteractionUpdate({
    this.verdict = InteractionVerdict.none,
    this.fails = false,
    this.events = const [],
  });

  /// Nothing happened.
  static const InteractionUpdate none = InteractionUpdate();

  /// How far the interaction has taken the touch.
  final InteractionVerdict verdict;

  /// Whether the interaction holds the touch against other gestures.
  bool get claims => verdict != InteractionVerdict.none;

  /// Whether the interaction recognized its gesture.
  bool get recognizes => verdict == InteractionVerdict.recognized;

  /// Whether the interaction gave up the touch.
  final bool fails;

  /// What it did, for haptics.
  final List<InteractionEvent> events;
}
