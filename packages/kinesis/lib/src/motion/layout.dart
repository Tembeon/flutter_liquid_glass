import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/pose.dart';
import 'package:kinesis/src/motion/rect.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/value.dart';

/// The motion of a keyed layout, pure: feed it layouts at explicit times
/// and read where each item is drawn.
///
/// `MotionLayout` is its screen host; a bar, a list or a test drives it
/// directly. Each item is a rect on springs (its center, width and height)
/// and a presence from 0 to 1 that takes it from the pose its plan gives it
/// while absent to its own look. [layout] plans every
/// change through [planner]: items that moved head to their new rects,
/// items that arrived enter and items that left stay drawn while they
/// leave, then go. Each item's rect rests within its plan's
/// [LayoutPlan.rest] ([MotionRest.length] by default) and its presence
/// within [MotionRest.opacity].
final class LayoutMotion extends Motion {
  /// Creates a layout motion that plans its changes with [planner], on
  /// [clock] (`MotionClock.instance` when null).
  LayoutMotion({this.planner = const LayoutPlanner.flip(), super.clock});

  /// Plans each change of layout.
  LayoutPlanner planner;

  final Map<Object, _Slot> _slots = {};
  bool _laidOut = false;

  // Debug only: ids asked for before they were laid out, checked at the
  // next layout, and every id ever laid out, so that an id that has gone
  // is not taken for one that never was.
  final Set<Object> _debugAsked = {};
  final Set<Object> _debugSeen = {};

  void _debugAsk(Object id) {
    if (!_slots.containsKey(id)) _debugAsked.add(id);
  }

  void _debugCheckAsked() {
    final unknown = _debugAsked.where((id) => !_debugSeen.contains(id));
    for (final id in unknown) {
      final key = _debugSeen
          .whereType<ValueKey<Object?>>()
          .where((key) => key.value == id)
          .firstOrNull;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError.fromParts([
            ErrorSummary(
              'LayoutMotion was asked for $id, which it never laid out.',
            ),
            ErrorDescription(
              'A layout knows its items by the ids its layouts give: '
              "MotionLayout uses each child's key, or its type and index "
              'among the unkeyed children of that type.',
            ),
            if (key != null)
              ErrorHint('It lays out $key: ask for the key, not its value.')
            else
              ErrorHint('It lays out ${_slots.keys.take(3).join(', ')}.'),
          ]),
          library: 'kinesis',
          context: ErrorDescription('while checking a LayoutMotion'),
        ),
      );
    }
    _debugAsked.clear();
  }

  /// The keys of the items drawn, those leaving included.
  Iterable<Object> get ids => _slots.keys;

  /// Whether [id] is drawn.
  bool contains(Object id) => _slots.containsKey(id);

  /// Whether [id] left the layout and is drawn until its leave ends.
  bool isLeaving(Object id) => _slots[id]?.leaving ?? false;

  /// Where layout put [id], or null before its first layout.
  ///
  /// In debug mode an [id] the next [layout] does not have either, and
  /// never had, is reported as an error: `MotionLayout` knows its children
  /// by their keys, not by the values in them.
  Rect? laidOut(Object id) {
    if (kDebugMode) _debugAsk(id);
    return hostLaidOut(id);
  }

  /// Where [id] is drawn now: its springs' rect and the pose its presence
  /// gives it; a rect of zero before its first layout. An unknown [id] is
  /// reported as for [laidOut].
  LayoutItem itemAt(Object id) {
    if (kDebugMode) _debugAsk(id);
    return hostItemAt(id);
  }

  /// How present [id] is as its spring has it, overshoot included: 0 for
  /// an item that enters or has gone, 1 for one that is there.
  double presenceAt(Object id) => _slots[id]?.presence.valueAt(now) ?? 0;

  /// Whether [id]'s presence rests where it heads, within
  /// [MotionRest.opacity].
  bool presenceRests(Object id) {
    final presence = _slots[id]?.presence;
    return presence == null ||
        (presence.restsAt(now, MotionRest.opacity) && presence.nextDue == null);
  }

  /// Moves [id]'s drawn frame to [rect] at [t]: with [snap] it rests there
  /// for the next [layout] to move on, otherwise it keeps its target and
  /// springs back with its current velocity.
  void placeItem(double t, Object id, Rect rect, {bool snap = false}) {
    advance(t);
    final slot = _slots[id];
    if (slot == null || slot.leaving) return;
    if (snap) {
      slot.frame.snap(t, rect);
    } else {
      slot.frame.setPresentation(t, rect);
    }
    changed();
  }

  /// Drops [id] at once, without a leave: for a host whose item went out
  /// of view, as a lazy list's row scrolls away.
  void forget(Object id) {
    if (!_slots.containsKey(id)) return;
    _drop(id);
    changed();
  }

  /// Whether [id] rests where it is drawn.
  bool itemRests(Object id) {
    final slot = _slots[id];
    if (slot == null) return true;
    return slot.frame.restsAt(now, slot.rest) &&
        slot.presence.restsAt(now, MotionRest.opacity) &&
        slot.frame.nextDue == null &&
        slot.presence.nextDue == null;
  }

  /// The union of the rects where the springs have the items that do not
  /// leave.
  Rect get bounds {
    Rect? union;
    for (final MapEntry(:key, :value) in _slots.entries) {
      if (value.leaving) continue;
      final rect = itemAt(key).rect;
      union = union == null ? rect : union.expandToInclude(rect);
    }
    return union ?? Rect.zero;
  }

  /// Shows the items at [rects], by key, from time [t], and returns the
  /// change it planned, or null when nothing changed.
  ///
  /// The change moves on [spring] unless [planner] has a spring of its
  /// own; with neither it jumps, except that an item in flight keeps its
  /// course, moved by its change of layout. An immediate [spring], such as
  /// `withoutAnimation`'s, makes every item jump whatever the planner's
  /// spring; the first layout puts every item in place. An item missing
  /// from [rects] leaves on its plan, or goes at once when the change jumps
  /// or it was never laid out; one that comes back while it leaves enters
  /// again from where it is drawn. With [arrived], an entering item not in
  /// it came into view, not into the data, and is put in place at once.
  /// Under Reduce Motion an item enters and leaves with its absent pose's
  /// opacity alone.
  LayoutChange? layout(
    double t,
    Map<Object, Rect> rects, {
    Spring? spring,
    Set<Object>? arrived,
  }) {
    final change = _layout(t, rects, spring: spring, arrived: arrived);
    if (kDebugMode) _debugCheckAsked();
    return change;
  }

  LayoutChange? _layout(
    double t,
    Map<Object, Rect> rects, {
    required Spring? spring,
    required Set<Object>? arrived,
  }) {
    advance(t);
    final jumps = _jumps(spring);
    final carry = spring == null && !jumps;
    final rawSpring = jumps ? null : planner.spring ?? spring;
    final moving = rawSpring?.resolve(reduceMotion: traits.reduceMotion);
    _laidOut = true;
    final entries = <Object, LayoutEntry>{};
    var changed = false;
    for (final MapEntry(key: id, value: to) in rects.entries) {
      final slot = _slots[id];
      if (slot == null) {
        entries[id] = LayoutEntry(phase: LayoutPhase.entering, to: to);
        changed = true;
        continue;
      }
      final returning = slot.leaving || slot.presence.target != 1;
      if (returning || slot.model != to) changed = true;
      entries[id] = LayoutEntry(
        phase: returning ? LayoutPhase.entering : LayoutPhase.staying,
        from: returning ? null : slot.model,
        to: to,
        shown: slot.frame.valueAt(t),
      );
    }
    for (final MapEntry(key: id, value: slot) in _slots.entries.toList()) {
      if (rects.containsKey(id)) continue;
      if (slot.leaving && !jumps) continue;
      changed = true;
      if (moving == null || slot.model == null) {
        _drop(id);
        continue;
      }
      entries[id] = LayoutEntry(
        phase: LayoutPhase.leaving,
        from: slot.model,
        shown: slot.frame.valueAt(t),
      );
    }
    if (!changed) return null;
    final change = LayoutChange(time: t, entries: entries, spring: moving);
    final plans = planner.plan(change);
    for (final MapEntry(key: id, value: entry) in entries.entries) {
      final scrolledIn =
          arrived != null &&
          entry.phase == LayoutPhase.entering &&
          !arrived.contains(id);
      final plan = scrolledIn
          ? const LayoutPlan()
          : plans[id] ?? LayoutPlan(spring: moving);
      _place(id, entry, plan, t, jumps: jumps, carry: carry);
    }
    return change;
  }

  bool _jumps(Spring? spring) => !_laidOut || (spring?.isImmediate ?? false);

  MotionPose _absent(MotionPose pose) {
    final worn = traits.reduceMotion ? MotionPose(opacity: pose.opacity) : pose;
    return worn == MotionPose.identity ? MotionPose.identity : worn;
  }

  void _place(
    Object id,
    LayoutEntry entry,
    LayoutPlan plan,
    double t, {
    required bool jumps,
    required bool carry,
  }) {
    final spring = jumps ? null : plan.spring;
    final springs = spring == null
        ? null
        : plan.springs ?? RectSprings.all(spring);
    final delay = plan.delay;
    switch (entry.phase) {
      case LayoutPhase.entering:
        final to = entry.to!;
        final existing = _slots[id];
        final slot = existing ?? _own(id, plan.origin ?? to);
        slot.leaving = false;
        slot.rest = plan.rest;
        slot.model = to;
        slot.absent = _absent(plan.absent);
        if (springs == null) {
          slot.frame.snap(t, to);
          slot.presence.snap(t, 1);
          return;
        }
        if (existing == null) {
          slot.presence.snap(t, 0);
        }
        if (existing != null || plan.origin != null) {
          slot.frame.retarget(t, to, springs: springs, delay: delay);
        }
        slot.presence.retarget(t, 1, spring: spring, delay: delay);
      case LayoutPhase.staying:
        final slot = _slots[id]!;
        final from = entry.from!;
        final to = entry.to!;
        if (from == to) return;
        slot.model = to;
        if (springs != null) {
          slot.frame.retarget(t, to, springs: springs, delay: delay);
        } else if (!carry || slot.frame.restsAt(t, MotionRest.length)) {
          slot.frame.snap(t, to);
        } else {
          slot.frame.shift(from, to);
        }
      case LayoutPhase.leaving:
        final slot = _slots[id]!;
        slot.leaving = true;
        slot.rest = plan.rest;
        slot.absent = _absent(plan.absent);
        final destination = plan.destination;
        if (spring == null) {
          slot.presence.snap(t, 0);
        } else {
          if (destination != null) {
            slot.frame.retarget(
              t,
              destination,
              springs: springs,
              delay: delay,
            );
          }
          slot.presence.retarget(t, 0, spring: spring, delay: delay);
        }
    }
  }

  _Slot _own(Object id, Rect rect) {
    final slot = _Slot(
      MotionRect(rect, springs: const RectSprings.all(Spring.smooth)),
      MotionValue<double>(1),
    );
    own(slot.frame, rest: () => slot.rest);
    own(slot.presence, rest: _opacity);
    _slots[id] = slot;
    if (kDebugMode) _debugSeen.add(id);
    return slot;
  }

  void _drop(Object id) {
    final slot = _slots.remove(id);
    if (slot == null) return;
    disown(slot.frame);
    disown(slot.presence);
  }

  static double _opacity() => MotionRest.opacity;

  @override
  void didAdvance(double t) {
    final gone = [
      for (final MapEntry(:key, :value) in _slots.entries)
        if (value.leaving &&
            value.presence.target == 0 &&
            value.presence.restsAt(t, MotionRest.opacity) &&
            value.presence.nextDue == null &&
            value.frame.restsAt(t, value.rest) &&
            value.frame.nextDue == null)
          key,
    ];
    gone.forEach(_drop);
  }
}

final class _Slot {
  _Slot(this.frame, this.presence);

  final MotionRect frame;
  final MotionValue<double> presence;
  MotionPose absent = MotionPose.identity;
  Rect? model;
  double rest = MotionRest.length;
  bool leaving = false;
}

/// What a layout host asks its motion while it builds, before any rects
/// exist.
@internal
extension LayoutMotionHosting on LayoutMotion {
  /// Whether a layout given [spring] keeps an item that left drawn while
  /// it leaves.
  bool animates(Spring? spring) =>
      !_jumps(spring) && (planner.spring ?? spring) != null;

  /// [laidOut] without the check, for a host that asks about children its
  /// layouts may leave out, such as rows scrolled out of a sliver.
  Rect? hostLaidOut(Object id) => _slots[id]?.model;

  /// [itemAt] without the check, as [hostLaidOut].
  LayoutItem hostItemAt(Object id) {
    final slot = _slots[id];
    if (slot == null) return const LayoutItem(rect: Rect.zero);
    final rect = slot.frame.valueAt(now);
    final absent = slot.absent;
    if (identical(absent, MotionPose.identity)) return LayoutItem(rect: rect);
    final p = slot.presence.valueAt(now).clamp(0.0, 1.0);
    if (p == 1) return LayoutItem(rect: rect);
    return LayoutItem(
      rect: rect,
      pose: MotionPose.lerp(absent, MotionPose.identity, p),
    );
  }
}

/// Plans how a change of layout animates. Pure.
abstract class LayoutPlanner {
  /// Creates a planner.
  const LayoutPlanner();

  /// Moves each item from where it was drawn to where layout puts it, an
  /// entering item from the pose [insert] and a leaving one into the pose
  /// [remove] (fading in and out by default, as SwiftUI does), on [spring]
  /// or on the change's spring when [spring] is null.
  const factory LayoutPlanner.flip({
    Spring? spring,
    MotionPose insert,
    MotionPose remove,
  }) = _FlipPlanner;

  /// The spring every change moves on, or null to move on the change's own
  /// (a transaction's).
  Spring? get spring => null;

  /// The plan of each item of [change], by key. An item without a plan
  /// moves on the change's spring and wears no pose while absent.
  Map<Object, LayoutPlan> plan(LayoutChange change);
}

final class _FlipPlanner extends LayoutPlanner {
  const _FlipPlanner({
    this.spring,
    this.insert = _fade,
    this.remove = _fade,
  });

  static const _fade = MotionPose(opacity: 0);

  @override
  final Spring? spring;

  final MotionPose insert;

  final MotionPose remove;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => {
    for (final MapEntry(:key, :value) in change.entries.entries)
      key: LayoutPlan(
        spring: change.spring,
        absent: switch (value.phase) {
          LayoutPhase.entering => insert,
          LayoutPhase.leaving => remove,
          LayoutPhase.staying => MotionPose.identity,
        },
      ),
  };
}

/// Where an item of a change of layout stands.
enum LayoutPhase {
  /// The item arrived in this change, or came back while it left.
  entering,

  /// The item was there before and is still there.
  staying,

  /// The item left in this change.
  leaving,
}

/// One item of a [LayoutChange].
@immutable
final class LayoutEntry {
  /// Describes one item of a change.
  const LayoutEntry({required this.phase, this.from, this.to, this.shown});

  /// Whether the item arrived, stayed or left.
  final LayoutPhase phase;

  /// Where layout put the item before, or null when it arrived.
  final Rect? from;

  /// Where layout puts the item now, or null when it left.
  final Rect? to;

  /// Where the item was drawn when the change came, or null when it
  /// arrived: what a planner pairing items by where they show reads.
  final Rect? shown;
}

/// What one layout did to the items of a [LayoutMotion].
@immutable
final class LayoutChange {
  /// Describes a change of layout.
  const LayoutChange({
    required this.time,
    required this.entries,
    this.spring,
  });

  /// The time of the change, in seconds.
  final double time;

  /// Every item laid out, by key, and the items that left: an item whose
  /// rect did not change stays with [LayoutEntry.from] equal to
  /// [LayoutEntry.to] and keeps its course.
  final Map<Object, LayoutEntry> entries;

  /// The spring of the change (the planner's or a transaction's), or null
  /// when it jumps.
  final Spring? spring;
}

/// How one item of a change animates.
@immutable
final class LayoutPlan {
  /// Describes how an item animates.
  const LayoutPlan({
    this.spring,
    this.springs,
    this.delay = 0,
    this.origin,
    this.destination,
    this.absent = MotionPose.identity,
    this.rest = MotionRest.length,
  });

  /// The spring of the presence and, without [springs], of the rect; null
  /// jumps.
  final Spring? spring;

  /// The springs of the rect's center, width and height, when they differ.
  final RectSprings? springs;

  /// Seconds the item keeps its course before it moves.
  final double delay;

  /// Where an entering item starts, instead of where layout puts it.
  final Rect? origin;

  /// Where a leaving item goes while it leaves, instead of staying where
  /// it was laid out.
  final Rect? destination;

  /// The pose the item wears while absent: an entering item starts in it
  /// and a leaving one ends in it.
  final MotionPose absent;

  /// The distance, in logical pixels, within which the item's rect rests;
  /// a leaving item goes once its presence and its rect both rest, so a
  /// finer [rest] keeps an item that shrinks into a [destination] drawn
  /// until it lands.
  final double rest;
}

/// Where an item of a [LayoutMotion] is drawn: the rect its springs have
/// in the layout's coordinates, and the pose its presence gives it.
@immutable
final class LayoutItem {
  /// Describes where an item is drawn.
  const LayoutItem({required this.rect, this.pose = MotionPose.identity});

  /// Where the item's springs have it, size included.
  final Rect rect;

  /// The pose the item wears on [rect], about its center; its
  /// `offsetFraction` is of the box that wears it.
  final MotionPose pose;

  @override
  bool operator ==(Object other) =>
      other is LayoutItem && other.rect == rect && other.pose == pose;

  @override
  int get hashCode => Object.hash(rect, pose);

  @override
  String toString() => 'LayoutItem(rect: $rect, pose: $pose)';
}
