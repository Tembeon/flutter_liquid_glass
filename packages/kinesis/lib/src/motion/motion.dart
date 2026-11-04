import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/motion/loop.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/selection.dart';
import 'package:kinesis/src/transaction.dart';

/// Drops a reaction scheduled with [Motion.at] before it runs.
typedef MotionCancel = void Function();

/// A tree of parts with one time cursor and one timeline of delayed
/// reactions: the shape of every measured motion.
///
/// Every command takes an explicit time and every read answers at [now], so
/// a motion built from commands is a pure function of its stamped inputs: a
/// test makes one, calls it at recorded times and reads it, with no clock
/// and no widget.
///
/// ```dart
/// class CardMotion extends Motion {
///   late final offset = own(MotionValue(Offset.zero));
///   late final opacity = own(
///     MotionValue(0.0),
///     rest: () => MotionRest.opacity,
///   );
///
///   void show(double t) {
///     opacity.retarget(t, 1);
///     at(t + 0.2, (t) => offset.retarget(t, const Offset(0, 40)));
///   }
/// }
/// ```
///
/// A part registers with [own] and rests within the tolerance given there,
/// its own otherwise. Rest is per part and declared, never a change:
/// [settle] declares each part that rests from its own rest time and leaves
/// the others moving.
///
/// On screen the clock steps the root of the tree while something looks at
/// it (a selection made with [MotionSelect.select] has listeners, or a
/// `MotionScope` holds it): every frame it advances the root to the frame's
/// time and, once the root [isSettled], settles it and stops stepping it
/// until a command or a reaction moves it again.
abstract class Motion extends MotionPart {
  /// Creates a motion stepped by [clock] when it is a root on screen
  /// ([MotionClock.instance] when null).
  Motion({this._clock});

  final MotionClock? _clock;
  final List<MotionPart> _parts = [];
  final List<double Function()?> _rests = [];
  final List<_Reaction> _reactions = [];
  late final _RootFollower _follower = _RootFollower(this);
  MotionTraits? _traits;
  int _holds = 0;
  double _now = 0;

  Motion get _root {
    var motion = this;
    while (true) {
      final owner = motion.owner;
      if (owner == null) return motion;
      motion = owner;
    }
  }

  /// The clock that steps the root on screen; the ambient forms of its
  /// values read it too. Explicit-time commands never do.
  MotionClock get clock => _root._clock ?? MotionClock.instance;

  /// The motion preferences of the root: those of the `MotionScope` that
  /// holds it, [MotionTraits.platform] otherwise.
  MotionTraits get traits => _root._traits ?? MotionTraits.platform();

  /// Sets the root's preferences; `MotionScope` writes them.
  @internal
  set traits(MotionTraits? traits) => _root._traits = traits;

  /// Keeps the root on the clock while held, as `MotionScope` does.
  @internal
  void hold() {
    final root = _root;
    root._holds++;
    root._wake();
  }

  /// Ends a [hold].
  @internal
  void release() {
    final root = _root;
    root._holds--;
    if (!root._attached) root.clock.unfollow(root._follower);
  }

  /// Tells the root that a part changed, so the clock steps it.
  @internal
  void partChanged() => _root._wake();

  bool get _attached => _holds > 0 || _follower.hasListeners;

  void _wake() {
    if (_attached) clock.follow(_follower);
  }

  /// The latest time the motion was advanced or commanded to; it never
  /// moves backwards. A smaller motion owned by another shares its cursor.
  double get now => _root._now;

  /// Registers [part] and returns it: `late final x = own(MotionValue(0.0))`.
  ///
  /// [rest] is the tolerance the part rests within, read whenever rest is
  /// asked; the part's own rest when it is null. A smaller motion joins
  /// this motion's cursor and timeline and rests within its own parts'
  /// tolerances. A `MotionLoop` steps its frames as the motion advances,
  /// each at its own time between the reactions.
  @protected
  P own<P extends MotionPart>(P part, {double Function()? rest}) {
    assert(part.owner == null, 'A part has one owner.');
    assert(
      part is! Motion || part._reactions.isEmpty,
      'A motion joins its owner before it schedules a reaction.',
    );
    part.owner = this;
    _parts.add(part);
    _rests.add(rest);
    return part;
  }

  /// Runs [action] at time [t] on the root's timeline: right away, at
  /// [now], when [t] is not later than [now], and as the motion advances
  /// past [t] otherwise, at [t] itself however coarse the steps.
  ///
  /// A reaction with a [slot] replaces a pending one with the same slot, so
  /// re-issuing a command never stacks its reactions. Reactions with equal
  /// times run in the order they were scheduled.
  @protected
  MotionCancel at(double t, void Function(double t) action, {Object? slot}) {
    final root = _root;
    if (slot != null) root._reactions.removeWhere((r) => r.slot == slot);
    if (t <= root._now) {
      action(root._now);
      return _noCancel;
    }
    final reaction = _Reaction(t, action, slot);
    var i = root._reactions.length;
    while (i > 0 && root._reactions[i - 1].time > t) {
      i--;
    }
    root._reactions.insert(i, reaction);
    root._wake();
    return () => root._reactions.remove(reaction);
  }

  static void _noCancel() {}

  /// Drops the pending reaction in [slot], if any.
  @protected
  void cancel(Object slot) =>
      _root._reactions.removeWhere((reaction) => reaction.slot == slot);

  /// Whether a reaction waits in [slot].
  @protected
  bool isScheduled(Object slot) =>
      _root._reactions.any((reaction) => reaction.slot == slot);

  /// Moves to [t]: runs every reaction due by [t] at its own time, then
  /// moves [now] to [t]. A [t] before [now] runs nothing and keeps [now].
  void advance(double t) => advanceUntil(t, null);

  /// Advances toward [t] like [advance], stopping right after a reaction
  /// for which [stop] answers true, with [now] at that reaction's time.
  /// Returns whether [t] was reached.
  bool advanceUntil(double t, bool Function()? stop) {
    final root = _root;
    while (root._reactions.isNotEmpty && root._reactions.first.time <= t) {
      final reaction = root._reactions.removeAt(0);
      if (reaction.time > root._now) {
        root._runLoops(reaction.time, before: true);
        root._now = reaction.time;
      }
      reaction.action(reaction.time);
      if (stop != null && stop()) {
        root._didAdvance(root._now);
        return false;
      }
    }
    if (t > root._now) root._now = t;
    root._runLoops(root._now);
    root._didAdvance(root._now);
    return true;
  }

  void _runLoops(double t, {bool before = false}) {
    for (final part in _parts) {
      if (part is MotionLoop) part.run(t, before: before);
      if (part is Motion) part._runLoops(t, before: before);
    }
  }

  void _didAdvance(double t) {
    didAdvance(t);
    for (final part in _parts) {
      if (part is Motion) part._didAdvance(t);
    }
  }

  /// Called after every advance, on the root and every motion it owns: the
  /// place to drop parts that finished leaving.
  @protected
  void didAdvance(double t) {}

  /// Whether something outside the parts keeps the motion awake: a finger
  /// still down, a hold that has not come due.
  @protected
  bool get holds => false;

  /// Whether nothing moves from [now] on: no reaction waits, nothing
  /// [holds] and every part rests at [now].
  bool get isSettled {
    if (_root._reactions.isNotEmpty || !restsAt(now)) return false;
    final rest = restTime();
    return rest != null && rest <= now;
  }

  /// Declares at rest every part that rests at [now], each from its own
  /// rest time; parts still moving keep their courses.
  void settle() => restFrom(now);

  /// When the motion next changes while nothing visible moves now and a
  /// reaction or a part's own change waits, so its owner can doze until
  /// then; null when the next frame moves or nothing waits.
  double? get wakeTime {
    if (!restsAt(now)) return null;
    return nextDue;
  }

  @override
  double? restTime([double? tolerance]) {
    if (holds) return null;
    var latest = double.negativeInfinity;
    for (var i = 0; i < _parts.length; i++) {
      final rest = _parts[i].restTime(_rests[i]?.call());
      if (rest == null) return null;
      latest = math.max(latest, rest);
    }
    return latest;
  }

  @override
  bool restsAt(double t, [double? tolerance]) {
    if (holds) return false;
    for (var i = 0; i < _parts.length; i++) {
      if (!_parts[i].restsAt(t, _rests[i]?.call())) return false;
    }
    return true;
  }

  @override
  void restFrom(double t) {
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part is Motion) {
        part.restFrom(t);
        continue;
      }
      final rest = part.restTime(_rests[i]?.call());
      if (rest != null && rest <= t) part.restFrom(rest);
    }
  }

  @override
  double? get nextDue {
    var due = owner == null && _reactions.isNotEmpty
        ? _reactions.first.time
        : null;
    for (final part in _parts) {
      final next = part.nextDue;
      if (next != null && (due == null || next < due)) due = next;
    }
    return due;
  }
}

final class _Reaction {
  _Reaction(this.time, this.action, this.slot);

  final double time;
  final void Function(double t) action;
  final Object? slot;
}

/// What a renderer, a transition or a widget reads of a motion.
extension MotionSelect<M extends Motion> on M {
  /// [read] of this motion, recomputed after each frame that stepped its
  /// root or a command that moved it, and heard only when the result
  /// changes (`equals`, `==` by default). It tracks no reads: it depends on
  /// the root alone. Bind it once, in a State field.
  MotionSelection<T> select<T>(
    T Function(M motion) read, {
    bool Function(T a, T b)? equals,
  }) => MotionSelection<T>.of(
    _root._follower,
    () => read(this),
    clock: clock,
    equals: equals,
  );
}

final class _RootFollower implements MotionFollowed, Listenable {
  _RootFollower(this.motion);

  final Motion motion;
  final List<VoidCallback> _listeners = [];

  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    final first = _listeners.isEmpty;
    _listeners.add(listener);
    if (first) motion._wake();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (!motion._attached) motion.clock.unfollow(this);
  }

  @override
  bool stepTo(double time) {
    motion.advance(time);
    if (!motion.isSettled) return true;
    motion.settle();
    return false;
  }

  @override
  double? get wakeTime => motion.wakeTime;

  @override
  bool get hasWidgetFollowers => _listeners.isNotEmpty;

  @override
  void publish({required bool widgets}) {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      guardMotion(listener, 'while notifying a selection of a Motion');
    }
  }
}
