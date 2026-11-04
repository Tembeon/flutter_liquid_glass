import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/presence.dart';
import 'package:kinesis/src/presentation/route.dart';

/// What a presentation shell needs from the motion it presents: where it
/// stands, and the two commands, at stamped times.
///
/// The shell opens the motion at the commit's time, starts its leave at
/// the dismissal's, completes the push once [presence] is
/// [PresenceStatus.shown] and ends once it is [PresenceStatus.hidden]
/// after a leave. The motion keeps no lifecycle flag of its own.
mixin Presented on Motion {
  /// Where the presentation stands at [now].
  PresenceStatus get presence;

  /// Opens the presentation at [t].
  void open(double t);

  /// Starts leaving at [t] for [trigger]; false when nothing is shown,
  /// which ends the presentation at once.
  bool leave(double t, DismissTrigger trigger);
}

/// Which user dismissals a presentation lets through, before the
/// content's `PopScope`s are asked. A programmatic dismissal always goes.
@immutable
final class DismissPolicy {
  /// Lets every trigger in [triggers] through.
  const DismissPolicy([this.triggers = all]);

  /// Every trigger: a menu, a popover, a sheet.
  static const Set<DismissTrigger> all = {
    DismissTrigger.outsideTap,
    DismissTrigger.escape,
    DismissTrigger.back,
    DismissTrigger.accessibility,
    DismissTrigger.interaction,
    DismissTrigger.programmatic,
  };

  /// Everything but a tap outside: an alert.
  static const DismissPolicy modal = DismissPolicy({
    DismissTrigger.escape,
    DismissTrigger.back,
    DismissTrigger.accessibility,
    DismissTrigger.interaction,
    DismissTrigger.programmatic,
  });

  /// The triggers let through.
  final Set<DismissTrigger> triggers;

  /// Whether [trigger] may dismiss.
  bool allows(DismissTrigger trigger) =>
      trigger == DismissTrigger.programmatic || triggers.contains(trigger);

  @override
  bool operator ==(Object other) =>
      other is DismissPolicy && setEquals(other.triggers, triggers);

  @override
  int get hashCode => Object.hashAllUnordered(triggers);
}
