import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';
import 'package:meta/meta.dart';

/// The swiped rows of one [RawGlassList], of which one is open at a time.
@internal
final class SwipeGroup extends InheritedWidget {
  /// Gives the rows below [open].
  const SwipeGroup({required this.open, required super.child, super.key});

  /// The row of the list that is open.
  final OpenSwipeRow open;

  /// The open row of the list around [context], or null.
  static OpenSwipeRow? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SwipeGroup>()?.open;

  @override
  bool updateShouldNotify(SwipeGroup oldWidget) => false;
}

/// A row of a [RawGlassList] that swipes open.
@internal
abstract interface class SwipeRow {
  /// Closes the row.
  void close();
}

/// The one row of a [RawGlassList] that is open.
@internal
final class OpenSwipeRow {
  SwipeRow? _row;

  /// Closes the row open before [row].
  void opened(SwipeRow row) {
    final open = _row;
    if (open != null && !identical(open, row)) open.close();
    _row = row;
  }

  /// Forgets [row] if it is the open one.
  void closed(SwipeRow row) {
    if (identical(_row, row)) _row = null;
  }
}

/// The rows of a list by id in a sliver: a change of [ids] inside
/// `withSpring` slides the rows that stay to their new places, fades new
/// rows in and gone rows out where they were, and moves reordered rows;
/// outside one it jumps.
///
/// UIKit: `UITableView` `performBatchUpdates` with `insertRows`,
/// `deleteRows` and `moveRow`. SwiftUI: `ForEach` in a `List`. Flutter:
/// `SliverAnimatedList`.
///
/// It has no look of its own: `GlassSliverListSection` gives rows its
/// card. Rows are built lazily by id ([SliverMotionList]), and of the
/// `GlassSwipeActions` in its rows one is open at a time. Not measured:
/// UIKit's row animations were not captured; the rows move on the app's
/// spring with [planner]'s effects.
class RawGlassList extends StatefulWidget {
  /// Creates a list of the rows [itemBuilder] builds for [ids].
  const RawGlassList({
    required this.ids,
    required this.itemBuilder,
    this.planner = const LayoutPlanner.flip(),
    super.key,
  });

  /// What identifies each row, in order.
  final List<Object> ids;

  /// Builds the row of an id.
  final Widget Function(BuildContext context, Object id) itemBuilder;

  /// How a change of the rows animates.
  final LayoutPlanner planner;

  @override
  State<RawGlassList> createState() => _RawGlassListState();
}

class _RawGlassListState extends State<RawGlassList> {
  final _open = OpenSwipeRow();

  @override
  Widget build(BuildContext context) => SwipeGroup(
    open: _open,
    child: SliverMotionList(
      ids: widget.ids,
      planner: widget.planner,
      itemBuilder: widget.itemBuilder,
    ),
  );
}
