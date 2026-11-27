import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// The rows of a list by id in a sliver: a change of [ids] inside
/// `withSpring` slides the rows that stay to their new places, fades new
/// rows in and gone rows out where they were, and moves reordered rows;
/// outside one it jumps.
///
/// UIKit: `UITableView` `performBatchUpdates` with `insertRows`,
/// `deleteRows` and `moveRow`, and its reorder control. SwiftUI: `ForEach`
/// in a `List`, with `onMove`. Flutter: `SliverAnimatedList`, and
/// `SliverReorderableList`.
///
/// It has no look of its own: `GlassSliverListSection` gives rows its
/// card. Rows are built lazily by id ([SliverMotionList]). By default a
/// change moves the rows as UIKit's table does ([ListRowPlanner]): on one
/// critically damped spring of response 0.3 whatever the transaction's
/// spring, a deleted row staying while the rows below slide over it and an
/// inserted one coming down from one row up.
///
/// With [onReorderItem], a [RawGlassReorderHandle] inside a row drags it:
/// the row lifts at the touch, before any movement, and follows the finger
/// up and down, drawn above the others ([liftOf] says how lifted it is);
/// a row gives way, on a critically damped spring of response 0.3, once the
/// held row's center passes the edge between the two as they will stand
/// after the swap. On release the row heads to its place on a critically
/// damped spring whose response is 0.0085 s for each point it has to go, at
/// most 0.3 s, and [onReorderItem] hears where it went, as Flutter's
/// `onReorderItem` does: the index the row had and the index it has once
/// moved. A cancel, or [ids] changed by the app during the drag, puts the
/// rows back without a call.
///
/// Fidelity. The lift, the swap rule and both springs are UIKit 27.2's
/// ([ListReorder]; list API passport, a reorder drag on the simulator); upward
/// swaps mirror the downward ones, which were the ones captured. Not built:
/// UIKit's scroll at the list's edges while a row is held.
class RawGlassList extends StatefulWidget {
  /// Creates a list of the rows [itemBuilder] builds for [ids].
  const RawGlassList({
    required this.ids,
    required this.itemBuilder,
    this.planner = const ListRowPlanner(),
    this.onReorderItem,
    super.key,
  });

  /// What identifies each row, in order.
  final List<Object> ids;

  /// Builds the row of an id.
  final Widget Function(BuildContext context, Object id) itemBuilder;

  /// How a change of the rows animates.
  final LayoutPlanner planner;

  /// Called when a dragged row is dropped somewhere else, with the index it
  /// had and the index it takes once moved; null for a list whose rows do
  /// not reorder.
  final void Function(int fromIndex, int toIndex)? onReorderItem;

  /// How lifted the row around [context] is, for a widget inside a row
  /// [itemBuilder] built: 1 while a finger holds it, falling to 0 as it
  /// lands, as UIKit fades its shadow; null for a row at rest.
  static ValueListenable<double>? liftOf(BuildContext context) =>
      _ReorderItem.maybeOf(context)?.lift;

  /// Where the row around [context] stands in its list, for a widget
  /// inside a row [itemBuilder] built: a dragged row's new place counted;
  /// null outside a [RawGlassList].
  static int? positionOf(BuildContext context) =>
      _ReorderItem.maybeOf(context)?.position;

  /// Whether the rows of the list around [context] reorder.
  static bool reordersOf(BuildContext context) =>
      _ReorderItem.maybeOf(context)?.reorders ?? false;

  @override
  State<RawGlassList> createState() => _RawGlassListState();
}

class _RawGlassListState extends State<RawGlassList> {
  late final LayoutMotion _motion = LayoutMotion(
    planner: widget.planner,
    clock: MotionClockScope.of(context),
  );
  late final MotionSelection<double> _lift = _motion.select(
    (_) => _liftNow(),
  );
  late final MotionSelection<bool> _landed = _motion.select(
    (_) => _landing != null && _motion.itemRests(_landing!),
  );

  Object? _held;
  Object? _landing;
  List<Object>? _order;
  double _fingerStart = 0;
  double _rowStart = 0;
  double _slotTop = 0;
  double _dropDistance = 0;
  bool _listening = false;

  List<Object> get _shown => _order ?? widget.ids;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;
    _landed.addListener(_endLanding);
  }

  @override
  void didUpdateWidget(RawGlassList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.planner = widget.planner;
    if (_held != null &&
        (!listEquals(oldWidget.ids, widget.ids) ||
            widget.onReorderItem == null)) {
      _cancel(_motion.clock.now);
    }
  }

  @override
  void dispose() {
    _landed.removeListener(_endLanding);
    super.dispose();
  }

  double _liftNow() {
    if (_held != null) return 1;
    final id = _landing;
    if (id == null || _dropDistance <= 0) return 0;
    final laid = _motion.laidOut(id);
    if (laid == null) return 0;
    final drawn = _motion.itemAt(id).rect;
    return ((drawn.top - laid.top).abs() / _dropDistance).clamp(0.0, 1.0);
  }

  void _endLanding() {
    if (!_landed.value || !mounted) return;
    setState(() => _landing = null);
  }

  bool _pickUp(Object id, double t, double y) {
    if (widget.onReorderItem == null || _held != null) return false;
    final laid = _motion.laidOut(id);
    if (laid == null) return false;
    if (_landing case final landing?) _motion.releaseItem(t, landing);
    setState(() {
      _held = id;
      _landing = null;
      _order = List.of(widget.ids);
      _fingerStart = y;
      _rowStart = laid.top;
      _slotTop = laid.top;
    });
    _motion.holdItem(t, id, laid);
    return true;
  }

  void _move(double t, double y) {
    final id = _held;
    final laid = id == null ? null : _motion.laidOut(id);
    if (id == null || laid == null) return;
    final top = _rowStart + y - _fingerStart;
    _motion.holdItem(
      t,
      id,
      Rect.fromLTWH(laid.left, top, laid.width, laid.height),
    );
    final order = List.of(_shown);
    final at = order.indexOf(id);
    final place = ListReorder.place(
      order.length,
      (i) =>
          _motion.contains(order[i]) ? _motion.laidOut(order[i])?.height : null,
      at: at,
      slotTop: _slotTop,
      center: top + laid.height / 2,
    );
    if (place.at == at) return;
    _slotTop = place.slotTop;
    order
      ..removeAt(at)
      ..insert(place.at, id);
    ListReorder.giveWay(() => setState(() => _order = order));
  }

  void _drop(double t, {required bool moves}) {
    final id = _held;
    if (id == null) return;
    final from = widget.ids.indexOf(id);
    final to = _shown.indexOf(id);
    final drawn = _motion.itemAt(id).rect.top;
    final distance = (drawn - _slotTop).abs();
    ListReorder.land(_motion, t, id, distance: distance);
    _change(() {
      _held = null;
      _landing = id;
      _dropDistance = distance;
      _order = null;
    });
    if (moves && from != to && from >= 0) widget.onReorderItem?.call(from, to);
  }

  // A drop the tree's teardown sends, as a handle leaving with the editing,
  // changes the rows after the frame.
  void _change(VoidCallback change) {
    void apply() => ListReorder.giveWay(() => setState(change));
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      apply();
      return;
    }
    change();
    // After the frame: the teardown that sent the drop locked the tree in a
    // frame already laid out with the held order; the rows go back from the
    // next one.
    binding.addPostFrameCallback((_) {
      if (mounted) apply();
    });
  }

  void _cancel(double t) => _drop(t, moves: false);

  void _step(Object id, int by) {
    final from = widget.ids.indexOf(id);
    final to = from + by;
    if (from < 0 || to < 0 || to >= widget.ids.length) return;
    ListReorder.giveWay(() => widget.onReorderItem?.call(from, to));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final position = {for (final (i, id) in shown.indexed) id: i};
    final raised = _held ?? _landing;
    return SliverMotionList(
      ids: shown,
      motion: _motion,
      raised: raised,
      itemBuilder: (context, id) => _ReorderItem(
        state: this,
        id: id,
        position: position[id],
        lift: id == raised ? _lift : null,
        reorders: widget.onReorderItem != null,
        child: widget.itemBuilder(context, id),
      ),
    );
  }
}

class _ReorderItem extends InheritedWidget {
  const _ReorderItem({
    required this.state,
    required this.id,
    required this.position,
    required this.lift,
    required this.reorders,
    required super.child,
  });

  final _RawGlassListState state;
  final Object id;
  final int? position;
  final ValueListenable<double>? lift;
  final bool reorders;

  static _ReorderItem? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ReorderItem>();

  @override
  bool updateShouldNotify(_ReorderItem oldWidget) =>
      position != oldWidget.position ||
      lift != oldWidget.lift ||
      reorders != oldWidget.reorders;
}

/// What drags its row of a [RawGlassList] that reorders: a touch on it
/// lifts the row at once and moves it with the finger, held against the
/// scroll around the list.
///
/// UIKit: `UITableViewCell`'s reorder control. SwiftUI: a row of a `List`
/// with `onMove` in editing. Flutter: `ReorderableDragStartListener`.
///
/// Outside a list that reorders it is its [child] alone. A screen reader
/// reads it as [semanticLabel] (the localized "Reorder" when null) with a
/// move up and a move down action, which move the row one place.
class RawGlassReorderHandle extends StatefulWidget {
  /// Makes [child] drag its row.
  const RawGlassReorderHandle({
    required this.child,
    this.semanticLabel,
    super.key,
  });

  /// What shows the handle, such as the three lines of UIKit's grip.
  final Widget child;

  /// What a screen reader reads for the handle.
  final String? semanticLabel;

  @override
  State<RawGlassReorderHandle> createState() => _RawGlassReorderHandleState();
}

class _RawGlassReorderHandleState extends State<RawGlassReorderHandle> {
  late final _input = _HandleInput(this);
  late final List<Interaction> _interactions = [_input];
  _ReorderItem? _item;

  @override
  void dispose() {
    if (_input.holding) _item?.state._cancel(_item!.state._motion.clock.now);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item = _ReorderItem.maybeOf(context);
    if (item == null || !item.reorders) return widget.child;
    final strings = GlassLocalizations.of(context);
    final position = item.position ?? 0;
    final count = item.state.widget.ids.length;
    return InputRegion(
      interactions: _interactions,
      semantics: SemanticsProperties(
        label: widget.semanticLabel ?? strings.reorderLabel,
        customSemanticsActions: {
          if (position > 0)
            CustomSemanticsAction(label: strings.moveUpLabel): () =>
                item.state._step(item.id, -1),
          if (position < count - 1)
            CustomSemanticsAction(label: strings.moveDownLabel): () =>
                item.state._step(item.id, 1),
        },
      ),
      child: widget.child,
    );
  }
}

/// A touch on a reorder handle: it takes the touch at once, so the scroll
/// around the list never moves under it, and drives the drag in global
/// coordinates, as the row it moves carries the handle along.
final class _HandleInput extends Interaction {
  _HandleInput(this.owner);

  final _RawGlassReorderHandleState owner;
  int? _pointer;
  bool holding = false;

  @override
  bool get dragged => holding;

  @override
  Set<InputKind> get takes => const {InputKind.pointer};

  @override
  InteractionUpdate handle(InteractionInput input) {
    final item = owner._item;
    if (item == null) return InteractionUpdate.none;
    final state = item.state;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        if (!state._pickUp(item.id, input.time, input.globalPosition.dy)) {
          return InteractionUpdate.none;
        }
        _pointer = input.pointer;
        holding = true;
        return const InteractionUpdate(verdict: .recognized);
      case PointerMoveInput() when input.pointer == _pointer:
        state._move(input.time, input.globalPosition.dy);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        holding = false;
        state._drop(input.time, moves: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        holding = false;
        state._cancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
