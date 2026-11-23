import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/presence.dart';

/// What asked a presentation to go.
enum DismissTrigger {
  /// A tap outside the content, on the barrier or on what the presentation
  /// counts as outside.
  outsideTap,

  /// A scroll of what the presentation was shown from, for a presentation
  /// that asks for it (`Presentation.dismissesOnScroll`).
  scroll,

  /// The Escape key (`DismissIntent`).
  escape,

  /// The back button, Android back or `Navigator.maybePop`.
  back,

  /// A screen reader's dismiss action.
  accessibility,

  /// A gesture of the presentation's own, such as a drag down.
  interaction,

  /// Code: `Navigator.pop` or `PresentationRoute.dismiss` with no checks.
  programmatic,
}

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

/// A presented motion that Android's predictive back gesture drives, as a
/// drag of the content that dismisses it does: the shell hands it the
/// gesture's progress while the finger moves, then commits or cancels.
///
/// The shell decides when the gesture starts (a route's
/// `PresentationRouteMixin.popGestureEnabled`); when it does not, and for a
/// motion without this mixin, the gesture's end is a plain Back. A portal
/// does not start it; Back closes a portal.
///
/// While the gesture moves it, the motion's [presence] stays toward shown:
/// a presence that turns to [PresenceStatus.leaving] is the motion leaving
/// on its own, which dismisses the presentation at once.
mixin PredictiveBack on Presented {
  /// A back gesture starts at [t]: until [backEnded] the presentation
  /// follows [backMoved] instead of its own course.
  void backStarted(double t);

  /// The gesture stands at [progress] at [t]: 0 where it started, 1 at the
  /// far end, as Android reports it.
  void backMoved(double t, double progress);

  /// The gesture ends at [t] with [velocity], its progress per second.
  ///
  /// When [commits], [leave] for [DismissTrigger.back] follows at the same
  /// time and continues from where the gesture left the presentation, with
  /// that velocity. Otherwise the presentation returns to rest open; the
  /// shell shows what is below until it settles.
  void backEnded(double t, {required bool commits, required double velocity});
}

/// A presentation that rides one progress from 0, hidden, to 1, shown.
///
/// [open] springs the progress to 1 on the open spring and [leave] to 0 on
/// the close spring, each from where it stands, velocity included.
/// Android's predictive back holds the progress at 1 minus the gesture's
/// progress; a commit leaves from there with the gesture's velocity, a
/// cancel springs back on the open spring.
abstract class PresentedProgress extends Motion with Presented, PredictiveBack {
  /// Creates a hidden presentation that opens on [openSpring], leaves on
  /// [closeSpring] ([openSpring] when null) and rests within [rest] of 0
  /// or 1.
  PresentedProgress({
    required Spring openSpring,
    required double rest,
    Spring? closeSpring,
    super.clock,
  }) {
    _presence = own(
      Presence(openSpring: openSpring, closeSpring: closeSpring, rest: rest),
    );
  }

  late final Presence _presence;

  @override
  PresenceStatus get presence => switch (_presence.status) {
    PresenceStatus.shown => PresenceStatus.of(shown: true, settled: isSettled),
    final status => status,
  };

  @override
  @mustCallSuper
  void open(double t) {
    advance(t);
    _presence.open(t);
  }

  @override
  @mustCallSuper
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    _presence.hide(t);
    return true;
  }

  /// The progress at [now]: 0 hidden, 1 shown, past either on a bouncy
  /// spring.
  double get progress => _presence.progress;

  /// The opacity of the presentation: [progress] within 0 and 1.
  double get opacity => _presence.opacity;

  @override
  void backStarted(double t) => advance(t);

  @override
  void backMoved(double t, double progress) {
    advance(t);
    _presence.hold(t, 1 - progress.clamp(0.0, 1.0));
  }

  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    advance(t);
    _presence.setVelocity(t, -velocity);
    if (!commits) _presence.open(t);
  }
}

/// Which user dismissals a presentation lets through, before the
/// content's `PopScope`s are asked. A programmatic dismissal always goes.
@immutable
final class DismissPolicy {
  /// Lets every trigger in `triggers` through, or every user trigger when
  /// it is null: a menu, a popover, a sheet.
  const DismissPolicy([Set<DismissTrigger>? triggers]) : _triggers = triggers;

  /// Everything but a tap outside and a scroll below: an alert.
  static const DismissPolicy modal = DismissPolicy({
    DismissTrigger.escape,
    DismissTrigger.back,
    DismissTrigger.accessibility,
    DismissTrigger.interaction,
  });

  final Set<DismissTrigger>? _triggers;

  static final Set<DismissTrigger> _everyUser = Set.unmodifiable({
    for (final trigger in DismissTrigger.values)
      if (trigger != DismissTrigger.programmatic) trigger,
  });

  /// The triggers let through.
  Set<DismissTrigger> get triggers => _triggers ?? _everyUser;

  /// Whether [trigger] may dismiss.
  bool allows(DismissTrigger trigger) =>
      trigger == DismissTrigger.programmatic || triggers.contains(trigger);

  @override
  bool operator ==(Object other) =>
      other is DismissPolicy && setEquals(other._user, _user);

  @override
  int get hashCode => Object.hashAllUnordered(_user);

  Set<DismissTrigger> get _user =>
      triggers.where((t) => t != DismissTrigger.programmatic).toSet();
}
