import 'dart:math' as math;

import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds one action of a swiped row from [details]; it runs when the row
/// builds, not when the action's states change.
typedef GlassSwipeActionBuilder = Widget Function(
  BuildContext context,
  GlassSwipeActionDetails details,
);

/// What a [GlassSwipeActionBuilder] builds an action from.
@immutable
final class GlassSwipeActionDetails {
  /// Describes action [index] of a side.
  const GlassSwipeActionDetails({
    required this.index,
    required this.states,
    this.leading = false,
  });

  /// Which action this is: 0 is the first, outermost at the row's edge.
  final int index;

  /// Whether the action is one of the leading actions.
  final bool leading;

  /// The action's states as they change: pressed, hovered and focused.
  /// A look hands it to what draws the focus ring and the hover response,
  /// which follow it without a rebuild.
  final ValueListenable<Set<WidgetState>> states;
}

/// A row that a finger swipes sideways to show its actions, with the
/// behavior of iOS 27's swipe actions and no look of its own beyond the
/// colors it is given: [actionBuilder] draws each action.
///
/// UIKit: `trailingSwipeActionsConfigurationForRowAt` and
/// `leadingSwipeActionsConfigurationForRowAt`. SwiftUI: `swipeActions`.
/// Flutter: `Slidable` of flutter_slidable.
///
/// A swipe toward the trailing edge shows [actionLabels]' actions there,
/// one toward the leading edge [leadingActionLabels]' at the leading edge,
/// each side's first action outermost. The row follows the finger once it
/// has gone 25 points and settles open when the finger last moved it open,
/// closed when it last moved it back, whatever the speed; with
/// [fullSwipe] (or [leadingFullSwipe]) the row follows the finger past its
/// actions, and a swipe that moves it far enough commits with UIKit's step
/// (trailing) or resistance (leading): released there it performs the
/// first action, as UIKit's `performsFirstActionWithFullSwipe`, and
/// brought back under the commit the row closes on release. A quick short
/// flick only opens the row ([SwipeActionsMotion]). Crossing the commit
/// either way plays a light impact: UIKit plays its swipe's own "confirm
/// in" and "confirm out" patterns there, which Flutter cannot play, from a
/// configuration that carries a light impact generator (read from UIKit's
/// code); a `MotionHapticScope` turns it off.
///
/// The actions stand as UIKit's buttons do: each 44 points tall, 4 below
/// the row's top, all of a side as wide as its widest, 10 points apart and
/// 10 from the row's edge. While a finger pulls, each grows from nothing
/// as its place opens; with a full swipe the first stretches past the
/// others; after a release they stand whole and scale in on a bouncy
/// spring, and out when the row closes. While the row is moved it is drawn
/// on [swipedColor] (UIKit's systemGray5) with a round end toward the
/// actions, and the strip behind the actions shows [revealColor] (the
/// page's background: UIKit cuts the card there). In a right-to-left
/// context the sides swap.
///
/// A tap on the open row away from its actions closes it, and the row's
/// content does not hear it; so does a scroll of the scroll view around
/// the row, or a swipe of another row of the same `SwipeGroup`.
/// Accessibility offers the actions as custom actions of the row, as UIKit
/// does, which is also how iOS's Full Keyboard Access reaches them. A
/// closed row's actions take no input and are no Tab stops; an open row's
/// actions are buttons with their labels, one Tab stop each, before the
/// row, and Space and Enter press the focused one.
class RawGlassSwipeActions extends StatefulWidget {
  /// Creates a row that shows its actions when swiped.
  const RawGlassSwipeActions({
    required this.actionLabels,
    required this.onAction,
    required this.actionBuilder,
    required this.child,
    this.leadingActionLabels = const [],
    this.onLeadingAction,
    this.fullSwipe = true,
    this.leadingFullSwipe = true,
    this.swipedColor,
    this.revealColor,
    this.statesController,
    @internal this.openOn,
    super.key,
  });

  /// What each trailing action is called, for accessibility; their count is
  /// the count of trailing actions.
  final List<String> actionLabels;

  /// Called with the index of the trailing action pressed, or performed by
  /// a full swipe or accessibility.
  final ValueChanged<int> onAction;

  /// What each leading action is called; their count is the count of
  /// leading actions.
  final List<String> leadingActionLabels;

  /// Called with the index of the leading action pressed, or performed by
  /// a full swipe or accessibility.
  final ValueChanged<int>? onLeadingAction;

  /// Builds each action, of either side, at the size the row gives it.
  final GlassSwipeActionBuilder actionBuilder;

  /// Whether a full swipe performs the first trailing action.
  final bool fullSwipe;

  /// Whether a full swipe performs the first leading action.
  final bool leadingFullSwipe;

  /// What the moved row is drawn on, or null for nothing.
  final Color? swipedColor;

  /// What shows behind the open strip, or null for what lies under the
  /// row.
  final Color? revealColor;

  /// Where the row publishes its states (dragged), or null. The row is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The row.
  final Widget child;

  /// Opens the row to its trailing actions each time it notifies, as a list
  /// row's delete control in editing does.
  @internal
  final Listenable? openOn;

  @override
  State<RawGlassSwipeActions> createState() => _RawGlassSwipeActionsState();
}

/// The swiped rows of one list section, of which one is open at a time: a
/// [RawGlassSwipeActions] in [child] that starts to open closes the one
/// open before it.
///
/// `GlassListSection` and `GlassSliverListSection` group their rows this
/// way; a list of an app's own groups its rows with one.
class SwipeGroup extends StatefulWidget {
  /// Groups the swiped rows in [child].
  const SwipeGroup({required this.child, super.key});

  /// The subtree holding the rows.
  final Widget child;

  @override
  State<SwipeGroup> createState() => _SwipeGroupState();
}

class _SwipeGroupState extends State<SwipeGroup> {
  final _open = _OpenRow();

  @override
  Widget build(BuildContext context) =>
      _OpenRowScope(open: _open, child: widget.child);
}

class _OpenRowScope extends InheritedWidget {
  const _OpenRowScope({required this.open, required super.child});

  final _OpenRow open;

  static _OpenRow? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OpenRowScope>()?.open;

  @override
  bool updateShouldNotify(_OpenRowScope oldWidget) => false;
}

final class _OpenRow {
  _RawGlassSwipeActionsState? _row;

  void opened(_RawGlassSwipeActionsState row) {
    final open = _row;
    if (open != null && !identical(open, row)) open.close();
    _row = row;
  }

  void closed(_RawGlassSwipeActionsState row) {
    if (identical(_row, row)) _row = null;
  }
}

class _RawGlassSwipeActionsState extends State<RawGlassSwipeActions> {
  late final _motion = SwipeActionsMotion(clock: MotionClockScope.of(context));
  late final _offset = _motion.select((m) => m.offset.valueAt(m.now));
  late final _appear = _motion.select((m) => m.appear.valueAt(m.now));
  late final DragInteraction _drag = DragInteraction(
    axis: Axis.horizontal,
    slop: SwipeActionsMotion.slop,
    followsTextDirection: true,
    onStart: _start,
    onUpdate: _update,
    onEnd: _end,
    onCancel: _cancel,
  );
  late final List<Interaction> _interactions = [
    _drag,
    _CloseTap(closesAt: _closesAt, onTap: close),
  ];
  final Map<int, List<Interaction>> _presses = {};
  final _swipeKey = GlobalKey(debugLabel: 'swipe');
  final _zones = InputZonesController<int>();
  _OpenRow? _group;
  ScrollPosition? _scroll;

  // A zone's id: a trailing action's index, or a leading one's as -1 - i.
  static int _zoneOf(int index, {required bool leading}) =>
      leading ? -1 - index : index;

  @override
  void initState() {
    super.initState();
    widget.openOn?.addListener(_openFromCode);
  }

  @override
  void didUpdateWidget(RawGlassSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.openOn, oldWidget.openOn)) {
      oldWidget.openOn?.removeListener(_openFromCode);
      widget.openOn?.addListener(_openFromCode);
    }
  }

  void _openFromCode() {
    _group?.opened(this);
    _motion.open(_motion.clock.now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = _OpenRowScope.maybeOf(context);
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.isScrollingNotifier.removeListener(_scrolled);
      _scroll = scroll;
      scroll?.isScrollingNotifier.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.openOn?.removeListener(_openFromCode);
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _group?.closed(this);
    _zones.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (_scroll?.isScrollingNotifier.value ?? false) close();
  }

  /// Settles the row closed.
  void close() {
    _group?.closed(this);
    _motion.moveTo(_motion.clock.now, 0);
  }

  void _start(DragInteractionDetails details) {
    _group?.opened(this);
    _motion.grab(details.time);
    _update(details);
  }

  void _update(DragInteractionDetails details) {
    final committed = _motion.isCommitted;
    _motion.drag(details.time, details.translation.dx);
    if (_motion.isCommitted != committed) {
      MotionHaptic.lightImpact.play(context);
    }
  }

  void _end(DragInteractionDetails details) {
    final leading = _motion.offset.valueAt(details.time) > 0;
    final result = _motion.release(
      details.time,
      details.velocity.dx,
      canPerform: leading
          ? widget.leadingActionLabels.isNotEmpty &&
                widget.onLeadingAction != null
          : widget.actionLabels.isNotEmpty,
    );
    switch (result.release) {
      case SwipeRelease.performs:
        _group?.closed(this);
        _run(0, leading: result.leading);
      case SwipeRelease.closes:
        _group?.closed(this);
      case SwipeRelease.opens:
    }
  }

  void _cancel(double t) => _motion.moveTo(t, 0);

  void _run(int index, {required bool leading}) {
    if (leading) {
      widget.onLeadingAction?.call(index);
    } else {
      widget.onAction(index);
    }
  }

  void _perform(int index, {required bool leading}) {
    close();
    _run(index, leading: leading);
  }

  bool _closesAt(Offset position) {
    final swipe = _swipeKey.currentContext?.findRenderObject();
    return swipe is _RenderSwipe && swipe.closesAt(position);
  }

  // A press on an action yields to the row's drag once the finger moves.
  List<Interaction> _pressOf(int index, {required bool leading}) =>
      _presses.putIfAbsent(
        _zoneOf(index, leading: leading),
        () => [
          PressInteraction(
            role: InteractionRole.content,
            onTap: (t) => _perform(index, leading: leading),
          ),
        ],
      );

  // Where an action is drawn now, cut to the row: nowhere while the row is
  // closed or the action stands on the other side, so a closed row's
  // actions take no input and no focus.
  InputZoneFrame? _frameOf(int zone) {
    final swipe = _swipeKey.currentContext?.findRenderObject();
    if (swipe is! _RenderSwipe || !swipe.hasSize) return null;
    final leading = zone < 0;
    final rect = swipe.actionRect(leading ? -1 - zone : zone, leading: leading);
    if (rect == null) return null;
    return InputZoneFrame(rect.intersect(Offset.zero & swipe.size));
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _motion
      ..fullSwipe = widget.fullSwipe
      ..leadingFullSwipe = widget.leadingFullSwipe
      ..trailingCount = widget.actionLabels.length
      ..leadingCount = widget.onLeadingAction == null
          ? 0
          : widget.leadingActionLabels.length;
    final trailing = widget.actionLabels;
    final leading = widget.onLeadingAction == null
        ? const <String>[]
        : widget.leadingActionLabels;
    Widget action(int i, {required bool leading}) => ExcludeSemantics(
      child: widget.actionBuilder(
        context,
        GlassSwipeActionDetails(
          index: i,
          leading: leading,
          states: _zones.states(_zoneOf(i, leading: leading)),
        ),
      ),
    );
    final swipe = _Swipe(
      key: _swipeKey,
      motion: _motion,
      offset: _offset,
      appear: _appear,
      rtl: rtl,
      trailingCount: trailing.length,
      swipedColor: widget.swipedColor,
      revealColor: widget.revealColor,
      children: [
        widget.child,
        for (var i = 0; i < trailing.length; i++) action(i, leading: false),
        for (var i = 0; i < leading.length; i++) action(i, leading: true),
      ],
    );
    // The row's region neither activates nor adjusts, so the actions'
    // zones inside it keep their Space and Enter.
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _interactions,
        statesController: widget.statesController,
        semantics: SemanticsProperties(
          customSemanticsActions: {
            for (final (i, label) in trailing.indexed)
              CustomSemanticsAction(label: label): () => widget.onAction(i),
            for (final (i, label) in leading.indexed)
              CustomSemanticsAction(label: label): () =>
                  widget.onLeadingAction?.call(i),
          },
        ),
        child: InputZones<int>(
          zones: [
            for (final (i, label) in trailing.indexed)
              InputZone<int>(
                id: _zoneOf(i, leading: false),
                interactions: _pressOf(i, leading: false),
                semantics: SemanticsProperties(label: label, button: true),
              ),
            for (final (i, label) in leading.indexed)
              InputZone<int>(
                id: _zoneOf(i, leading: true),
                interactions: _pressOf(i, leading: true),
                semantics: SemanticsProperties(label: label, button: true),
              ),
          ],
          frameOf: _frameOf,
          frames: _offset,
          controller: _zones,
          excludeChildSemantics: false,
          child: swipe,
        ),
      ),
    );
  }
}

/// A tap on an open row away from its actions: it closes the row. The row
/// takes such a touch from its content, which it does not hit-test while
/// open, so the content does not hear it.
final class _CloseTap extends Interaction {
  _CloseTap({required this.closesAt, required this.onTap})
    : super(role: InteractionRole.content);

  final bool Function(Offset position) closesAt;
  final VoidCallback onTap;

  bool _touching = false;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && closesAt(down.position);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when accepts(input):
        _touching = true;
      case PointerUpInput() when _touching:
        _touching = false;
        onTap();
        return const InteractionUpdate(verdict: .recognized);
      case PointerCancelInput() when _touching:
        _touching = false;
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The row and its actions: the row laid out in full and drawn moved by the
/// offset, over the swiped color and the reveal color, and the actions of
/// the open side at the widths and places [SwipeActionsMotion] gives them.
class _Swipe extends MultiChildRenderObjectWidget {
  const _Swipe({
    required this.motion,
    required this.offset,
    required this.appear,
    required this.rtl,
    required this.trailingCount,
    required this.swipedColor,
    required this.revealColor,
    required super.children,
    super.key,
  });

  final SwipeActionsMotion motion;
  final MotionSelection<double> offset;
  final MotionSelection<double> appear;
  final bool rtl;
  final int trailingCount;
  final Color? swipedColor;
  final Color? revealColor;

  @override
  MultiChildRenderObjectElement createElement() => _SwipeElement(this);

  @override
  _RenderSwipe createRenderObject(BuildContext context) => _RenderSwipe(
    motion: motion,
    offset: offset,
    appear: appear,
    rtl: rtl,
    trailingCount: trailingCount,
    swipedColor: swipedColor,
    revealColor: revealColor,
    following: followsMotion(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSwipe renderObject) {
    renderObject
      ..motion = motion
      ..offset = offset
      ..appear = appear
      ..rtl = rtl
      ..trailingCount = trailingCount
      ..swipedColor = swipedColor
      ..revealColor = revealColor
      ..following = followsMotion(context);
  }
}

// The actions of a closed row are not drawn; like an IndexedStack's
// hidden children, they are offstage to finders.
class _SwipeElement extends MultiChildRenderObjectElement {
  _SwipeElement(_Swipe super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final swipe = renderObject as _RenderSwipe;
    var index = 0;
    for (final child in children) {
      if (index == 0 || swipe.showsChild(index - 1)) visitor(child);
      index++;
    }
  }
}

class _SwipeParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSwipe extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwipeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwipeParentData> {
  _RenderSwipe({
    required this.motion,
    required this._offset,
    required this._appear,
    required this._rtl,
    required this._trailingCount,
    required this._swipedColor,
    required this._revealColor,
    required bool following,
  }) : _follow = MotionFollow.render(following: following) {
    _hear();
  }

  /// A button's height and its place below the row's top (swipe actions
  /// passport: 44 tall, 4 below the strip, which stands 0.67 down).
  static const double _buttonHeight = 44;
  static const double _buttonTop = 4.67;

  SwipeActionsMotion motion;

  MotionSelection<double> _offset;
  MotionSelection<double> get offset => _offset;
  set offset(MotionSelection<double> value) {
    if (identical(value, _offset)) return;
    _offset = value;
    _hear();
    markNeedsLayout();
  }

  MotionSelection<double> _appear;
  MotionSelection<double> get appear => _appear;
  set appear(MotionSelection<double> value) {
    if (identical(value, _appear)) return;
    _appear = value;
    _hear();
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  int _trailingCount;
  int get trailingCount => _trailingCount;
  set trailingCount(int value) {
    if (value == _trailingCount) return;
    _trailingCount = value;
    markNeedsLayout();
  }

  Color? _swipedColor;
  Color? get swipedColor => _swipedColor;
  set swipedColor(Color? value) {
    if (value == _swipedColor) return;
    _swipedColor = value;
    markNeedsPaint();
  }

  Color? _revealColor;
  Color? get revealColor => _revealColor;
  set revealColor(Color? value) {
    if (value == _revealColor) return;
    _revealColor = value;
    markNeedsPaint();
  }

  RenderBox get _row => firstChild!;

  List<RenderBox> get _actions {
    final actions = <RenderBox>[];
    var child = childAfter(_row);
    while (child != null) {
      actions.add(child);
      child = childAfter(child);
    }
    return actions;
  }

  final MotionFollow _follow;
  bool get following => _follow.following;
  set following(bool value) => _follow.following = value;

  void _hear() => _follow.hear([
    (_offset, markNeedsLayout),
    (_appear, markNeedsPaint),
  ]);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow.attach();
  }

  @override
  void detach() {
    _follow.detach();
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwipeParentData) {
      child.parentData = _SwipeParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _row.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _row.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _row.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _row.getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _row.getDryLayout(constraints);

  /// Where the row is moved: positive toward the right.
  double get _shift => _rtl ? -_offset.value : _offset.value;

  // Each action's rect at the last layout, or null for one not shown.
  final List<Rect?> _rects = [];

  /// Whether action child [index] (trailing first, then leading) shows.
  bool showsChild(int index) => index < _rects.length && _rects[index] != null;

  /// Where the shown action [index] of a side stands, or null.
  Rect? actionRect(int index, {required bool leading}) {
    final at = leading ? _trailingCount + index : index;
    return at < _rects.length ? _rects[at] : null;
  }

  @override
  void performLayout() {
    _row.layout(constraints, parentUsesSize: true);
    size = _row.size;
    final actions = _actions;
    double widest(Iterable<RenderBox> side) => side.fold(
      0,
      (w, box) => math.max(w, box.getMaxIntrinsicWidth(_buttonHeight)),
    );
    motion
      ..rowWidth = size.width
      ..trailingButton = widest(actions.take(_trailingCount))
      ..leadingButton = widest(actions.skip(_trailingCount));
    final value = _offset.value;
    final pull = value.abs();
    final leading = value > 0;
    _rects
      ..clear()
      ..addAll(List<Rect?>.filled(actions.length, null));
    for (final (i, box) in actions.indexed) {
      final ofLeading = i >= _trailingCount;
      final index = ofLeading ? i - _trailingCount : i;
      final shown = pull > 0 && ofLeading == leading;
      final width = shown
          ? motion.buttonWidth(index, leading: leading, pull: pull)
          : 0.0;
      box.layout(
        BoxConstraints.tightFor(width: width, height: _buttonHeight),
        parentUsesSize: true,
      );
      if (!shown || width <= 0) continue;
      _rects[i] = _place(index, width, leading: leading, pull: pull);
    }
  }

  // A shown button's rect: the side's buttons laid from the row's edge
  // inward, each centered in its slot of the opened strip.
  Rect _place(
    int index,
    double width, {
    required bool leading,
    required double pull,
  }) {
    final gap = motion.gapAt(leading: leading, pull: pull);
    final whole = leading ? motion.leadingButton : motion.trailingButton;
    var from = gap;
    for (var j = 0; j < index; j++) {
      final w = motion.buttonWidth(j, leading: leading, pull: pull);
      from += math.max(w, whole) + gap;
    }
    final slot = math.max(width, whole);
    // Distance from the row's edge to the slot's center, along the row.
    final center = from + slot / 2;
    final edgeRight = leading == _rtl;
    final x = edgeRight ? size.width - center : center;
    return Rect.fromCenter(
      center: Offset(x, _buttonTop + _buttonHeight / 2),
      width: width,
      height: _buttonHeight,
    );
  }

  bool get _open => _offset.value != 0;

  /// Whether a touch at [position] is a tap that closes the row: the row is
  /// open and the touch is away from its actions.
  bool closesAt(Offset position) =>
      _open && !_rects.any((rect) => rect != null && rect.contains(position));

  @override
  bool hitTestSelf(Offset position) => _open;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_open) return _row.hitTest(result, position: position);
    final actions = _actions;
    for (final (i, box) in actions.indexed) {
      final rect = _rects[i];
      if (rect == null || !rect.contains(position)) continue;
      return result.addWithPaintOffset(
        offset: rect.topLeft,
        position: position,
        hitTest: (result, local) => box.hitTest(result, position: local),
      );
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shift = _shift;
    if (shift == 0) {
      context.paintChild(_row, offset);
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      if (_revealColor case final reveal?) {
        context.canvas.drawRect(offset & size, Paint()..color = reveal);
      }
      final scale = motion.held ? 1.0 : _appear.value;
      for (final (i, box)
          in scale <= 0 ? const <(int, RenderBox)>[] : _actions.indexed) {
        final rect = _rects[i];
        if (rect == null) continue;
        final at = offset + rect.topLeft;
        if (scale == 1) {
          context.paintChild(box, at);
          continue;
        }
        final center = rect.center;
        final transform = Matrix4.identity()
          ..translateByDouble(center.dx, center.dy, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1)
          ..translateByDouble(-center.dx, -center.dy, 0, 1);
        context.pushOpacity(
          offset,
          (scale.clamp(0.0, 1.0) * 255).round(),
          (context, offset) => context.pushTransform(
            needsCompositing,
            offset,
            transform,
            (context, offset) => context.paintChild(box, offset + rect.topLeft),
          ),
        );
      }
      if (_swipedColor case final swiped?) {
        final body = (offset + Offset(shift, 0)) & size;
        final round = Radius.circular(size.height / 2);
        final towardRight = shift < 0;
        context.canvas.drawRRect(
          RRect.fromRectAndCorners(
            body,
            topRight: towardRight ? round : Radius.zero,
            bottomRight: towardRight ? round : Radius.zero,
            topLeft: towardRight ? Radius.zero : round,
            bottomLeft: towardRight ? Radius.zero : round,
          ),
          Paint()..color = swiped,
        );
      }
      context.paintChild(_row, offset + Offset(shift, 0));
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _row)) {
      transform.translateByDouble(_shift, 0, 0, 1);
      return;
    }
    final i = _actions.indexOf(child);
    final rect = i < 0 || i >= _rects.length ? null : _rects[i];
    if (rect != null) transform.translateByDouble(rect.left, rect.top, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => visitor(_row);
}
