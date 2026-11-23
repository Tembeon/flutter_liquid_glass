import 'package:flutter/foundation.dart';

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
