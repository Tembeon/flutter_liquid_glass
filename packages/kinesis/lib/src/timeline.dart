/// Pending actions ordered by the time they come due.
///
/// A motion schedules delayed reactions (a landing after a hang, an opening
/// after a tap) on its timeline and runs them as it advances. [runDue]
/// hands each action the time it was scheduled for, so a motion advanced
/// in coarse steps still applies every action at its own time. Actions
/// with equal times run in the order they were inserted.
class MotionTimeline {
  /// Creates an empty timeline whose clock starts at [now].
  MotionTimeline({this._now = double.negativeInfinity});

  final List<(double, void Function(double))> _events = [];
  double _now;

  /// The latest time [runDue] reached or ran an action at; [flush] leaves
  /// it.
  double get now => _now;

  /// Whether no action is pending.
  bool get isEmpty => _events.isEmpty;

  /// The time the earliest pending action comes due, or null when none is
  /// pending.
  double? get nextDue => _events.isEmpty ? null : _events.first.$1;

  /// Schedules [action] for time [t], after every action already scheduled
  /// for [t] or earlier.
  void insert(double t, void Function(double t) action) {
    var i = _events.length;
    while (i > 0 && _events[i - 1].$1 > t) {
      i--;
    }
    _events.insert(i, (t, action));
  }

  /// Runs [action] right away at [now] when [t] is not later than [now],
  /// and schedules it for [t] otherwise.
  void at(double t, void Function(double t) action) {
    if (t <= _now) {
      action(_now);
    } else {
      insert(t, action);
    }
  }

  /// Runs every action due by [t] in order, each at its own time, then moves
  /// [now] to [t] unless it is already later.
  ///
  /// While an action runs, [now] is no earlier than its time, so an action
  /// that schedules another one relative to it lands on the right side of
  /// the clock. Actions that come due while the run is in progress run in
  /// the same call.
  ///
  /// When [until] answers true after an action, the run stops there and
  /// [now] stays at that action's time; a later call goes on from it.
  /// Returns whether the run reached [t].
  bool runDue(double t, {bool Function()? until}) {
    while (_events.isNotEmpty && _events.first.$1 <= t) {
      final (at, action) = _events.removeAt(0);
      if (at > _now) _now = at;
      action(at);
      if (until != null && until()) return false;
    }
    if (t > _now) _now = t;
    return true;
  }

  /// Runs every pending action right away at [t], whatever its time.
  void flush(double t) {
    while (_events.isNotEmpty) {
      _events.removeAt(0).$2(t);
    }
  }

  /// Drops every pending run of [action].
  void remove(void Function(double t) action) =>
      _events.removeWhere((event) => identical(event.$2, action));

  /// Drops every pending action.
  void clear() => _events.clear();
}
