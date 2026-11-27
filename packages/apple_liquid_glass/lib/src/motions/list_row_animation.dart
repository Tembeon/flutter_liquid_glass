import 'dart:ui';

import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// How a list row that is deleted leaves, and one that is inserted
/// arrives, while the rows around them make room.
///
/// UIKit: `UITableView.RowAnimation`. SwiftUI: a `List`'s default
/// transitions. Flutter: `SliverAnimatedList`'s builders.
enum GlassListRowAnimation {
  /// [bottom] for a deleted row and [top] for an inserted one, as UIKit's
  /// `.automatic`.
  automatic,

  /// The row fades out, or in, where it stands.
  fade,

  /// The row slides off to the right edge, or in from it, and fades.
  right,

  /// The row slides off to the left edge, or in from it, and fades.
  left,

  /// A deleted row slides up one row with the rows below it, which cover
  /// it; an inserted one slides down from one row up.
  top,

  /// A deleted row stays and the rows below slide up over it, or fades
  /// where no row is below it (the last row; not captured); an inserted
  /// one slides up from one row down (not captured; mirrors [top]).
  bottom,

  /// The row moves half a row up and fades, or comes from half a row up
  /// and fades in.
  middle,

  /// The row goes or comes at once; the others still move.
  none,
}

/// Plans a list change as UIKit's table animates it (list API passport,
/// "Table animations", iOS 27.2 simulator): every row moves on one
/// critically damped spring of response 0.3 (stiffness 438.65, damping
/// 41.89), whatever spring the change came with, and a row that leaves or
/// arrives wears [animation]'s pose. A change outside a transaction jumps,
/// as a `reloadData` does.
@immutable
final class ListRowPlanner extends LayoutPlanner {
  /// Plans changes with [animation].
  const ListRowPlanner({this.animation = GlassListRowAnimation.automatic});

  /// How rows leave and arrive.
  final GlassListRowAnimation animation;

  static const _table = Spring.response(0.3, dampingRatio: 1);
  static const _fade = MotionPose(opacity: 0);

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) {
    final spring = change.spring == null ? null : _table;
    final remaining = [
      for (final entry in change.entries.values)
        switch (entry) {
          LayoutStaying(:final to) || LayoutEntering(:final to) => to,
          LayoutLeaving() => null,
        },
    ].nonNulls;
    // A row that stays only because the rows below cover it fades where
    // none is below it.
    bool covered(Rect from) =>
        remaining.any((to) => to.bottom > from.bottom + 0.5);
    return {
      for (final MapEntry(:key, :value) in change.entries.entries)
        key: switch (value) {
          LayoutStaying() => LayoutPlan(spring: spring),
          LayoutEntering(:final to) => _enter(to, spring),
          LayoutLeaving(:final from) => _leave(
            from,
            spring,
            covered: covered(from),
          ),
        },
    };
  }

  LayoutPlan _enter(Rect to, Spring? spring) {
    final up = to.translate(0, -to.height);
    return switch (animation) {
      GlassListRowAnimation.none => const LayoutPlan(),
      GlassListRowAnimation.fade => LayoutPlan(spring: spring, absent: _fade),
      GlassListRowAnimation.right => LayoutPlan(
        spring: spring,
        absent: const MotionPose(offsetFraction: Offset(1, 0), opacity: 0),
      ),
      GlassListRowAnimation.left => LayoutPlan(
        spring: spring,
        absent: const MotionPose(offsetFraction: Offset(-1, 0), opacity: 0),
      ),
      GlassListRowAnimation.top ||
      GlassListRowAnimation.automatic => LayoutPlan(spring: spring, origin: up),
      GlassListRowAnimation.bottom => LayoutPlan(
        spring: spring,
        origin: to.translate(0, to.height),
      ),
      GlassListRowAnimation.middle => LayoutPlan(
        spring: spring,
        origin: to.translate(0, -to.height / 2),
        absent: _fade,
      ),
    };
  }

  LayoutPlan _leave(
    Rect from,
    Spring? spring, {
    required bool covered,
  }) => switch (animation) {
    GlassListRowAnimation.none => const LayoutPlan(),
    GlassListRowAnimation.fade => LayoutPlan(spring: spring, absent: _fade),
    GlassListRowAnimation.right => LayoutPlan(
      spring: spring,
      absent: const MotionPose(offsetFraction: Offset(1, 0), opacity: 0),
    ),
    GlassListRowAnimation.left => LayoutPlan(
      spring: spring,
      absent: const MotionPose(offsetFraction: Offset(-1, 0), opacity: 0),
    ),
    GlassListRowAnimation.top => LayoutPlan(
      spring: spring,
      destination: from.translate(0, -from.height),
    ),
    GlassListRowAnimation.bottom ||
    GlassListRowAnimation.automatic => LayoutPlan(
      spring: spring,
      absent: covered ? MotionPose.identity : _fade,
    ),
    GlassListRowAnimation.middle => LayoutPlan(
      spring: spring,
      destination: from.translate(0, -from.height / 2),
      absent: _fade,
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is ListRowPlanner && other.animation == animation;

  @override
  int get hashCode => animation.hashCode;
}

/// A list row's change into and out of editing: [progress] runs from 0,
/// out of editing, to 1 on UIKit's table spring, critically damped at 0.3,
/// which moves the content, slides and fades the edit control in and
/// fades the reorder control (list API passport, `setEditing(_:animated:)`).
final class ListEditMotion extends Motion {
  /// Creates the motion of a row out of editing.
  ListEditMotion({super.clock});

  static const _table = Spring.response(0.3, dampingRatio: 1);

  /// How far the row has gone into editing.
  late final progress = own(MotionValue<double>(0));

  /// The row goes into editing, or out of it, at time [t]: on the spring
  /// when [animated], at once otherwise.
  void edit(double t, {required bool editing, required bool animated}) {
    advance(t);
    final target = editing ? 1.0 : 0.0;
    if (animated) {
      progress.retarget(t, target, spring: _table);
    } else {
      progress.snap(t, target);
    }
  }

  /// Whether the row rests out of editing.
  bool get restsOut =>
      progress.target == 0 && progress.valueAt(now) <= MotionRest.opacity;
}

/// The turn of an outline row's disclosure chevron: 0 pointing forward, 1
/// pointing down, a quarter turn on the critically damped 0.25 s spring a
/// UIKit collection view list moves on (UIKit's CA animations, iOS 27.2
/// simulator), not the 0.3 s table spring of the rows (`ListEditMotion`).
final class OutlineDisclosureMotion extends Motion {
  /// Creates the turn of a row that is expanded or not.
  OutlineDisclosureMotion({required this._expanded, super.clock});

  static const _list = Spring.response(0.25);

  bool _expanded;

  /// How far the chevron has turned toward pointing down.
  late final turn = own(MotionValue<double>(_expanded ? 1 : 0));

  /// The row expands or collapses at time [t].
  void expand(double t, {required bool expanded}) {
    advance(t);
    if (expanded == _expanded) return;
    final turn = this.turn;
    _expanded = expanded;
    turn.retarget(t, expanded ? 1 : 0, spring: _list);
  }
}
