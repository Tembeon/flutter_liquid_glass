import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/part.dart';

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
abstract class Motion extends MotionPart {
  final List<MotionPart> _parts = [];
  final List<double Function()?> _rests = [];
  final List<_Reaction> _reactions = [];
  Motion? _owner;
  double _now = 0;

  Motion get _root {
    var motion = this;
    while (true) {
      final owner = motion._owner;
      if (owner == null) return motion;
      motion = owner;
    }
  }

  /// The latest time the motion was advanced or commanded to; it never
  /// moves backwards. A smaller motion owned by another shares its cursor.
  double get now => _root._now;

  /// Registers [part] and returns it: `late final x = own(MotionValue(0.0))`.
  ///
  /// [rest] is the tolerance the part rests within, read whenever rest is
  /// asked; the part's own rest when it is null. A smaller motion joins
  /// this motion's cursor and timeline and rests within its own parts'
  /// tolerances.
  @protected
  P own<P extends MotionPart>(P part, {double Function()? rest}) {
    if (part is Motion) {
      assert(part._owner == null, 'A motion has one owner.');
      assert(
        part._reactions.isEmpty,
        'A motion joins its owner before it schedules a reaction.',
      );
      part._owner = this;
    }
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
      if (reaction.time > root._now) root._now = reaction.time;
      reaction.action(reaction.time);
      if (stop != null && stop()) {
        root._didAdvance(root._now);
        return false;
      }
    }
    if (t > root._now) root._now = t;
    root._didAdvance(root._now);
    return true;
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
    var due = _owner == null && _reactions.isNotEmpty
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
