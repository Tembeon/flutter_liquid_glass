import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/layout.dart';
import 'package:kinesis/src/widgets/layout_item.dart';
import 'package:kinesis/src/widgets/resolve.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// Builds a [MotionLayout]'s layout around its [children], which are the
/// layout's children wrapped for motion.
typedef MotionLayoutBuilder = Widget Function(
  BuildContext context,
  List<Widget> children,
);

/// Animates whatever layout did to its children.
///
/// UIKit: `layoutIfNeeded` inside `UIView.animate`. SwiftUI: a layout under
/// `withAnimation`. Flutter: `AnimatedList`, for any layout and without
/// telling it what changed.
///
/// [layoutBuilder] lays [children] out as any layout does, for example
/// `(context, children) => Column(children: children)`. Each frame, after
/// layout, the layout's [LayoutMotion] hears where layout put the children:
/// the children that moved slide from where they were drawn to where layout
/// put them, children that arrived enter from the planner's insert pose
/// and children that left stay drawn, leaving into its remove pose. The
/// frame's transaction decides: after a `withSpring` that closed before
/// this frame's layout, the motion follows that spring (a tracking one does
/// not count); after a `withoutAnimation`, and under a muted `TickerMode`,
/// it jumps; with neither, a child at rest jumps and a child in flight is
/// carried along. A [LayoutPlanner.flip] with a spring of its own always
/// moves on it; a `withoutAnimation` still makes it jump. The first layout
/// puts every child in place. Under Reduce Motion a child enters and
/// leaves with its pose's opacity alone.
///
/// A child is known by its key, or by its type and its place among the
/// unkeyed children of that type. Flex (`Expanded`, `Flexible`, `Spacer`),
/// Stack (`Positioned`) and `CustomMultiChildLayout` (`LayoutId`) parent
/// data work through the wrapping; other parent data does not. A child
/// keeps its laid out size and is drawn centered on its item's rect. The
/// children are hit where layout put them, drawn where they slide, and read
/// by accessibility where they are drawn once they rest; a child that left
/// is neither hit nor read. Nothing builds or lays out while children
/// slide.
class MotionLayout extends StatefulWidget {
  /// Creates a layout that animates its [children].
  const MotionLayout({
    required this.layoutBuilder,
    required this.children,
    this.planner = const LayoutPlanner.flip(),
    this.motion,
    this.onLayout,
    super.key,
  });

  /// Lays the wrapped children out.
  final MotionLayoutBuilder layoutBuilder;

  /// The children, in layout order.
  final List<Widget> children;

  /// How a change of layout animates, when the layout keeps its own
  /// motion.
  final LayoutPlanner planner;

  /// The motion the layout drives, kept by an owner that also reads or
  /// leans it; the layout keeps one of its own on [planner] when null.
  final LayoutMotion? motion;

  /// Called with each change of layout, after the planner planned it, in
  /// the frame's resolve phase before paint: it must not rebuild; what it
  /// marks for layout is laid out again in that frame.
  final ValueChanged<LayoutChange>? onLayout;

  /// Where the nearest child of a [MotionLayout] is drawn, in the layout's
  /// coordinates, or null outside one.
  static ValueListenable<LayoutItem>? itemOf(BuildContext context) =>
      LayoutItemScope.of(context);

  /// Like [itemOf], and tells the child's probe that [context] draws the
  /// item itself, as a glass surface takes its frame from the item at
  /// paint: while any descendant adopts it, the probe adds no transform,
  /// opacity or blur of its own, and the adopter moves, fades and scales
  /// what it draws.
  static ValueListenable<LayoutItem>? adoptItem(BuildContext context) =>
      LayoutItemScope.of(context, adopt: true);

  @override
  State<MotionLayout> createState() => _MotionLayoutState();
}

class _MotionLayoutState extends State<MotionLayout>
    with LayoutMotionOwner<MotionLayout> {
  List<Object> _ids = const [];

  @override
  LayoutMotion? get givenMotion => widget.motion;

  @override
  LayoutPlanner get givenPlanner => widget.planner;

  @override
  ValueChanged<LayoutChange>? get onLayout => widget.onLayout;

  @override
  void didUpdateWidget(MotionLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    motionUpdated(oldWidget.motion);
  }

  static List<Object> _idsOf(List<Widget> children) {
    final counts = <Type, int>{};
    return [
      for (final child in children)
        child.key ??
            (
              child.runtimeType,
              counts[child.runtimeType] = (counts[child.runtimeType] ?? -1) + 1,
            ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    muted = !TickerMode.valuesOf(context).enabled;
    final ids = _idsOf(widget.children);
    final present = ids.toSet();
    for (final id in _ids) {
      if (present.contains(id) || ghosts.contains(id)) continue;
      if (animates && motion.hostLaidOut(id) != null) {
        ghosts.add(id);
      } else {
        entries.remove(id);
      }
    }
    ghosts.removeAll(present);
    _ids = ids;
    final children = <Widget>[
      for (var i = 0; i < ids.length; i++)
        _probe(ids[i], widget.children[i], ghost: false),
    ];
    final leaving = <Widget>[
      for (final id in ghosts) _probe(id, entries[id]!.last!, ghost: true),
    ];
    return MotionScope(
      motion: motion,
      child: _Host(
        state: this,
        children: [
          Builder(
            builder: (context) => widget.layoutBuilder(context, children),
          ),
          ...leaving,
        ],
      ),
    );
  }

  Widget _probe(Object id, Widget child, {required bool ghost}) {
    final entry = entries[id] ??= LayoutItemEntry(motion, id);
    if (!ghost) entry.last = child;
    return LayoutProbe(
      key: entry.key,
      create: _RenderProbe.new,
      motion: motion,
      entry: entry,
      ghost: ghost,
      child: LayoutItemScope(entry: entry, child: child),
    );
  }

  void _resolve(_RenderHost host) => place(host, {
    for (final probe in host.probes)
      if (!probe.ghost) probe.id: probe.layoutRect,
  });
}

class _Host extends MultiChildRenderObjectWidget {
  const _Host({required this.state, required super.children});

  final _MotionLayoutState state;

  @override
  _RenderHost createRenderObject(BuildContext context) => _RenderHost(state);

  @override
  void updateRenderObject(BuildContext context, _RenderHost renderObject) {
    renderObject.state = state;
  }
}

class _HostParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHost extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HostParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HostParentData>,
        MotionResolveHost,
        LayoutProbeHost {
  _RenderHost(this.state);

  _MotionLayoutState state;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HostParentData) {
      child.parentData = _HostParentData();
    }
  }

  @override
  void performLayout() {
    final main = firstChild;
    if (main == null) {
      size = constraints.smallest;
      return;
    }
    main.layout(constraints, parentUsesSize: true);
    size = main.size;
    var ghost = childAfter(main);
    while (ghost != null) {
      final probe = ghost as _RenderProbe;
      ghost.layout(probe.lastConstraints ?? constraints.loosen());
      final data = ghost.parentData! as _HostParentData;
      data.offset = state.motion.hostLaidOut(probe.id)?.topLeft ?? Offset.zero;
      ghost = childAfter(ghost);
    }
    scheduleResolve();
  }

  @override
  void resolve() => state._resolve(this);

  @override
  void paint(PaintingContext context, Offset offset) {
    final main = firstChild;
    if (main == null) return;
    var ghost = childAfter(main);
    while (ghost != null) {
      final data = ghost.parentData! as _HostParentData;
      context.paintChild(ghost, offset + data.offset);
      ghost = childAfter(ghost);
    }
    context.paintChild(main, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final main = firstChild;
    return main != null && main.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final main = firstChild;
    if (main != null) visitor(main);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      firstChild?.getDryLayout(constraints) ?? constraints.smallest;
}

class _RenderProbe extends LayoutProbeBox {
  _RenderProbe(super.motion, super.entry, {required super.ghost});

  BoxConstraints? lastConstraints;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    final theirs = child?.parentData;
    if (theirs != null) _copy(theirs, parentData);
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    super.layout(constraints, parentUsesSize: parentUsesSize);
    lastConstraints = this.constraints;
    host?.scheduleResolve();
  }

  @override
  Rect? get placed => motion.hostLaidOut(id);

  @override
  Size get drawnSize => size;

  /// Where layout put this child, in the host's coordinates.
  @override
  Rect get layoutRect {
    final host = this.host;
    var offset = Offset.zero;
    RenderObject node = this;
    while (!identical(node, host)) {
      assert(
        node is! RenderAbstractViewport,
        'A MotionLayout child sits in a scrolling view inside its layout.',
      );
      final data = node.parentData;
      if (data is BoxParentData) offset += data.offset;
      node = node.parent!;
    }
    return offset & size;
  }

  // The child's parent data (Expanded, Positioned, LayoutId) belongs to the
  // layout that holds this probe: the child gets the probe's kind, which
  // the probe mirrors onto itself. A child that left keeps what it had.
  @override
  void setupParentData(RenderBox child) {
    final mirror = _mirror(parentData);
    final current = child.parentData;
    if (current is BoxParentData &&
        (current.runtimeType == mirror.runtimeType || parent is _RenderHost)) {
      return;
    }
    child.parentData = mirror;
  }

  static BoxParentData _mirror(ParentData? data) {
    for (final kind in _kinds) {
      if (kind.owns(data)) return kind.create();
    }
    return BoxParentData();
  }

  @override
  void markNeedsLayout() {
    final mine = parentData;
    final theirs = child?.parentData;
    if (theirs != null && _copy(theirs, mine)) markParentNeedsLayout();
    super.markNeedsLayout();
  }

  static bool _copy(ParentData from, ParentData? to) {
    for (final kind in _kinds) {
      if (kind.owns(from)) return kind.copyInto(from, to);
    }
    return false;
  }

  static const _kinds = <_ParentDataKind<BoxParentData>>[
    _ParentDataKind<FlexParentData>(FlexParentData.new, _copyFlex),
    _ParentDataKind<StackParentData>(StackParentData.new, _copyStack),
    _ParentDataKind<MultiChildLayoutParentData>(
      MultiChildLayoutParentData.new,
      _copyId,
    ),
  ];

  static bool _copyFlex(FlexParentData a, FlexParentData b) {
    if (a.flex == b.flex && a.fit == b.fit) return false;
    b
      ..flex = a.flex
      ..fit = a.fit;
    return true;
  }

  static bool _copyStack(StackParentData a, StackParentData b) {
    if (a.top == b.top &&
        a.right == b.right &&
        a.bottom == b.bottom &&
        a.left == b.left &&
        a.width == b.width &&
        a.height == b.height) {
      return false;
    }
    b
      ..top = a.top
      ..right = a.right
      ..bottom = a.bottom
      ..left = a.left
      ..width = a.width
      ..height = a.height;
    return true;
  }

  static bool _copyId(
    MultiChildLayoutParentData a,
    MultiChildLayoutParentData b,
  ) {
    if (a.id == b.id) return false;
    b.id = a.id;
    return true;
  }

  @override
  void performLayout() {
    final theirs = child?.parentData;
    if (theirs != null) _copy(theirs, parentData);
    super.performLayout();
  }
}

/// A kind of parent data a layout gives its children, which a probe takes
/// on and copies from its child: what to make and how to copy, where the
/// copy says whether anything changed.
final class _ParentDataKind<T extends BoxParentData> {
  const _ParentDataKind(this.create, this._copy);

  final T Function() create;
  final bool Function(T from, T to) _copy;

  bool owns(ParentData? data) => data is T;

  bool copyInto(ParentData from, ParentData? to) =>
      from is T && to is T && _copy(from, to);
}
