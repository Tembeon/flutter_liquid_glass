import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// One trailing swipe action of a list row.
///
/// UIKit: `UIContextualAction`. SwiftUI: a `Button` in `swipeActions`.
/// Flutter: `SlidableAction` of flutter_slidable.
@immutable
final class GlassSwipeAction {
  /// Creates an action titled [title].
  const GlassSwipeAction({
    required this.title,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// What the action is called: its label when it has no [icon], and what
  /// accessibility reads.
  final String title;

  /// Shown in place of [title], usually an [Icon].
  final Widget? icon;

  /// Called when the action is pressed, or performed by a full swipe.
  final VoidCallback onPressed;

  /// Whether the action destroys, as a delete does (UIKit `.destructive`):
  /// systemRed by default.
  final bool destructive;

  /// The action's fill: systemRed for a destructive action, systemGray
  /// otherwise, by default.
  final Color? backgroundColor;

  /// The color of the action's label: white by default.
  final Color? foregroundColor;
}

/// A row that a finger swipes toward its trailing edge to show [trailing]
/// actions.
///
/// UIKit: `trailingSwipeActionsConfigurationForRowAt`. SwiftUI:
/// `swipeActions(edge: .trailing)`. Flutter: `Slidable` of
/// flutter_slidable.
///
/// The row follows the finger on a rubber band and settles open or closed
/// where the release projects; [trailing] sits against its trailing edge,
/// the first action outermost. With [fullSwipe] a swipe past most of the
/// row performs the first action, as UIKit's
/// `performsFirstActionWithFullSwipe`. A tap on the open row closes it,
/// and so does a scroll, or a swipe of another row of the same
/// `GlassListSection` or `GlassSliverListSection`. Accessibility offers
/// the actions as custom actions of the row, as UIKit does, which is also
/// how iOS's Full Keyboard Access reaches them (its actions command,
/// Tab-Z). A closed row's actions are no Tab stops; an open row's actions
/// are, before the row, and Space and Enter press the focused one. A
/// focused action draws Flutter's Cupertino focus ring inside its edge
/// and a mouse over it washes it, by the rule of the glass controls (an
/// approximation, not measured).
///
/// Not measured: the springs, the widths and the full-swipe threshold are
/// chosen by eye, as UIKit's swipe actions were not captured on iOS 27.
class GlassSwipeActions extends StatefulWidget {
  /// Creates a row that shows [trailing] when swiped.
  const GlassSwipeActions({
    required this.trailing,
    required this.child,
    this.fullSwipe = true,
    super.key,
  });

  /// The actions, the first at the trailing edge.
  final List<GlassSwipeAction> trailing;

  /// Whether a full swipe performs the first action.
  final bool fullSwipe;

  /// The row.
  final Widget child;

  /// The share of the row's width a release must pass to perform the
  /// first action; not measured.
  static const double fullSwipeShare = 0.6;

  /// The padding on each side of an action's label; not measured.
  static const double actionPadding = 15;

  /// The narrowest an action is; not measured.
  static const double minActionWidth = 74;

  /// The label of an action: 15 points, medium; not measured.
  static const TextStyle actionTextStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  @override
  State<GlassSwipeActions> createState() => _GlassSwipeActionsState();
}

/// The swiped rows of one list section, of which one is open at a time: a
/// row that starts to open closes the one open before it.
@internal
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
  _GlassSwipeActionsState? _row;

  void opened(_GlassSwipeActionsState row) {
    final open = _row;
    if (open != null && !identical(open, row)) open.close();
    _row = row;
  }

  void closed(_GlassSwipeActionsState row) {
    if (identical(_row, row)) _row = null;
  }
}

class _GlassSwipeActionsState extends State<GlassSwipeActions> {
  final _motion = SwipeActionsMotion();
  late final _offset = _motion.select((m) => m.offset.valueAt(m.now));
  late final DragInteraction _drag = DragInteraction(
    axis: Axis.horizontal,
    onStart: _start,
    onUpdate: _update,
    onEnd: _end,
    onCancel: _cancel,
  );
  late final List<Interaction> _interactions = [_drag];
  final List<List<Interaction>> _presses = [];
  final List<GlobalKey> _actionKeys = [];
  final _swipeKey = GlobalKey(debugLabel: 'swipe');
  final _zones = InputZonesController<int>();
  double _grab = 0;
  _OpenRow? _group;
  ScrollPosition? _scroll;

  Band get _band => Band(
    widget.fullSwipe ? -_motion.rowWidth : -_motion.actionsWidth,
    0,
    dimension: _motion.rowWidth,
  );

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
    _grab = _band.unshow(_motion.offset.valueAt(details.time));
    _update(details);
  }

  void _update(DragInteractionDetails details) => _motion.follow(
    details.time,
    _band.show(_grab + details.translation.dx),
  );

  void _end(DragInteractionDetails details) {
    final t = details.time;
    final shown = _motion.offset.valueAt(t);
    final first = widget.trailing.firstOrNull;
    final choice = _motion.projection.choose(
      shown,
      details.velocity.dx,
      stops: [0, -_motion.actionsWidth],
      exits: [
        if (widget.fullSwipe && first != null)
          ProjectionExit(
            threshold: -GlassSwipeActions.fullSwipeShare * _motion.rowWidth,
            sign: -1,
          ),
      ],
    );
    switch (choice) {
      case ProjectionExited():
        _motion.moveTo(t, -_motion.rowWidth, velocity: details.velocity.dx);
        first!.onPressed();
      case ProjectionStop(:final value):
        if (value == 0) _group?.closed(this);
        _motion.moveTo(t, value, velocity: details.velocity.dx);
    }
  }

  void _cancel(double t) => _motion.moveTo(t, 0);

  void _perform(GlassSwipeAction action) {
    close();
    action.onPressed();
  }

  // A press on an action yields to the row's drag once the finger moves.
  List<Interaction> _pressOf(int index) {
    while (_presses.length <= index) {
      final i = _presses.length;
      _presses.add([
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => _perform(widget.trailing[i]),
        ),
      ]);
    }
    return _presses[index];
  }

  GlobalKey _actionKey(int index) {
    while (_actionKeys.length <= index) {
      _actionKeys.add(GlobalKey(debugLabel: 'swipe action'));
    }
    return _actionKeys[index];
  }

  // Where action [index] is drawn now, cut to the row: nowhere while the
  // row is closed, so a closed row's actions take no input and no focus.
  InputZoneFrame? _frameOf(int index) {
    if (_offset.value == 0 || index >= _actionKeys.length) return null;
    final row = _swipeKey.currentContext?.findRenderObject();
    final action = _actionKeys[index].currentContext?.findRenderObject();
    if (row is! RenderBox ||
        action is! RenderBox ||
        !row.hasSize ||
        !action.hasSize ||
        !action.attached) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      action.getTransformTo(row),
      Offset.zero & action.size,
    );
    return InputZoneFrame(rect.intersect(Offset.zero & row.size));
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _drag.mirrored = rtl;
    final actions = widget.trailing;
    return MotionScope(
      motion: _motion,
      child: Semantics(
        customSemanticsActions: {
          for (final action in actions)
            CustomSemanticsAction(label: action.title): action.onPressed,
        },
        // The actions' zones sit above the row's drag: a region around them
        // would answer their Space and Enter.
        child: InputZones<int>(
          zones: [
            for (final (i, action) in actions.indexed)
              InputZone<int>(
                id: i,
                interactions: _pressOf(i),
                semantics: SemanticsProperties(
                  label: action.title,
                  button: true,
                ),
              ),
          ],
          frameOf: _frameOf,
          frames: _offset,
          controller: _zones,
          excludeChildSemantics: false,
          child: InputRegion(
            interactions: _interactions,
            child: _Swipe(
              key: _swipeKey,
              motion: _motion,
              offset: _offset,
              rtl: rtl,
              fill: actions.isEmpty ? null : _fillOf(actions.first, context),
              onTap: () {
                if (!_drag.started) close();
              },
              children: [
                widget.child,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, action) in actions.indexed.toList().reversed)
                      _ActionButton(
                        key: _actionKey(i),
                        action: action,
                        states: _ZoneStates(_zones, i),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _fillOf(GlassSwipeAction action, BuildContext context) =>
    GlassDynamicColor.resolve(
      action.backgroundColor ??
          (action.destructive ? GlassColors.systemRed : GlassColors.systemGray),
      context,
    );

/// An action's fill and label; its zone of the row's [InputZones] takes
/// its input and speaks for it.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.states,
    super.key,
  });

  final GlassSwipeAction action;
  final ValueListenable<Set<WidgetState>> states;

  @override
  Widget build(BuildContext context) {
    final foreground = GlassDynamicColor.resolve(
      action.foregroundColor ?? const Color(0xFFFFFFFF),
      context,
    );
    return ExcludeSemantics(
      child: ColoredBox(
        color: _fillOf(action, context),
        child: GlassHighlightPaint.of(
          context,
          states: states,
          shape: const GlassShape.roundedRect(0),
          inside: true,
          wash: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: GlassSwipeActions.minActionWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassSwipeActions.actionPadding,
              ),
              child: Center(
                widthFactor: 1,
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground),
                  child:
                      action.icon ??
                      Text(
                        action.title,
                        maxLines: 1,
                        style: resolveGlassText(
                          GlassSwipeActions.actionTextStyle.copyWith(
                            color: foreground,
                          ),
                          context,
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One action's states, read from the zones of all of them.
final class _ZoneStates implements ValueListenable<Set<WidgetState>> {
  _ZoneStates(this.zones, this.id);

  final InputZonesController<int> zones;
  final int id;

  @override
  Set<WidgetState> get value => zones.statesOf(id);

  @override
  void addListener(VoidCallback listener) => zones.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => zones.removeListener(listener);
}

/// The row and its actions: the row laid out in full and drawn moved by the
/// offset, the actions at their own width against its trailing edge, the
/// first action's fill reaching to the edge of the box past them.
class _Swipe extends MultiChildRenderObjectWidget {
  const _Swipe({
    required this.motion,
    required this.offset,
    required this.rtl,
    required this.fill,
    required this.onTap,
    required super.children,
    super.key,
  });

  final SwipeActionsMotion motion;
  final MotionSelection<double> offset;
  final bool rtl;
  final Color? fill;
  final VoidCallback onTap;

  @override
  MultiChildRenderObjectElement createElement() => _SwipeElement(this);

  @override
  _RenderSwipe createRenderObject(BuildContext context) => _RenderSwipe(
    motion: motion,
    offset: offset,
    rtl: rtl,
    fill: fill,
    onTap: onTap,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSwipe renderObject) {
    renderObject.motion = motion;
    renderObject.offset = offset;
    renderObject.rtl = rtl;
    renderObject.fill = fill;
    renderObject.onTap = onTap;
  }
}

// The actions of a closed row are not drawn; like an IndexedStack's
// hidden children, they are offstage to finders.
class _SwipeElement extends MultiChildRenderObjectElement {
  _SwipeElement(_Swipe super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final open = (renderObject as _RenderSwipe)._open;
    var first = true;
    for (final child in children) {
      if (first || open) visitor(child);
      first = false;
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
    required this._rtl,
    required this._fill,
    required this.onTap,
  });

  SwipeActionsMotion motion;
  VoidCallback onTap;

  MotionSelection<double> _offset;
  MotionSelection<double> get offset => _offset;
  set offset(MotionSelection<double> value) {
    if (identical(value, _offset)) return;
    if (attached) _offset.removeRenderListener(markNeedsPaint);
    _offset = value;
    if (attached) _offset.addRenderListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsPaint();
  }

  Color? _fill;
  Color? get fill => _fill;
  set fill(Color? value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  RenderBox get _row => firstChild!;
  RenderBox get _actions => lastChild!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addRenderListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeRenderListener(markNeedsPaint);
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

  @override
  void performLayout() {
    _row.layout(constraints, parentUsesSize: true);
    size = _row.size;
    _actions.layout(
      BoxConstraints.tightFor(height: size.height),
      parentUsesSize: true,
    );
    motion.rowWidth = size.width;
    motion.actionsWidth = _actions.size.width;
  }

  /// Where the row is drawn along its width.
  double get _shift => _rtl ? -_offset.value : _offset.value;

  Rect get _actionsRect {
    final shift = _shift;
    final left = _rtl ? shift - _actions.size.width : size.width + shift;
    return Rect.fromLTWH(left, 0, _actions.size.width, size.height);
  }

  bool get _open => _offset.value != 0;

  @override
  bool hitTestSelf(Offset position) => _open;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_open) return _row.hitTest(result, position: position);
    final actions = _actionsRect;
    if (!actions.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: actions.topLeft,
      position: position,
      hitTest: (result, local) => _actions.hitTest(result, position: local),
    );
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerUpEvent &&
        _open &&
        !_actionsRect.contains(entry.localPosition)) {
      onTap();
    }
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
      final actions = _actionsRect;
      final fill = _fill;
      if (fill != null) {
        final rest = _rtl
            ? Rect.fromLTRB(0, 0, actions.left, size.height)
            : Rect.fromLTRB(actions.right, 0, size.width, size.height);
        if (!rest.isEmpty) {
          final paint = Paint();
          paint.color = fill;
          context.canvas.drawRect(rest.shift(offset), paint);
        }
      }
      context.paintChild(_actions, offset + actions.topLeft);
      context.paintChild(_row, offset + Offset(shift, 0));
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = identical(child, _row)
        ? Offset(_shift, 0)
        : _actionsRect.topLeft;
    transform.translateByDouble(at.dx, at.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => visitor(_row);
}
