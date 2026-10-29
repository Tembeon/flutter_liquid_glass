import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/computed.dart';
import 'package:kinesis/src/effect.dart';
import 'package:kinesis/src/screen/resolve.dart';
import 'package:kinesis/src/screen/transition.dart';
import 'package:kinesis/src/spring.dart';
import 'package:kinesis/src/transaction.dart';
import 'package:kinesis/src/value.dart';

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
/// layout, the children that moved slide from where they were drawn to
/// where layout put them, children that arrived enter with [motion]'s
/// insert effect and children that left stay drawn, leaving with its
/// remove effect. The frame's transaction decides: after a `withSpring`
/// that closed since the frame began, the motion follows that spring
/// (a tracking one does not count); after a `withoutAnimation`, and under
/// a muted `TickerMode`, it jumps; with neither, a child at rest jumps and
/// a child in flight is carried along. [LayoutMotion.flip] with a spring of
/// its own animates without a transaction too. The first layout puts every
/// child in place. Under Reduce Motion the effects are their `reduced`
/// ones.
///
/// A child is known by its key, or by its type and its place among the
/// unkeyed children of that type. Flex (`Expanded`, `Flexible`, `Spacer`),
/// Stack (`Positioned`) and `CustomMultiChildLayout` (`LayoutId`) parent
/// data work through the wrapping; other parent data does not. The children
/// are hit where layout put them, drawn where they slide, and read by
/// accessibility where they are drawn once they rest; a child that left is
/// neither hit nor read. Nothing builds or lays out while children slide.
class MotionLayout extends StatefulWidget {
  /// Creates a layout that animates its [children].
  const MotionLayout({
    required this.layoutBuilder,
    required this.children,
    this.motion = const LayoutMotion.flip(),
    this.onLayout,
    super.key,
  });

  /// Lays the wrapped children out.
  final MotionLayoutBuilder layoutBuilder;

  /// The children, in layout order.
  final List<Widget> children;

  /// How a change of layout animates.
  final LayoutMotion motion;

  /// Called with each change of layout, after [motion] planned it, in the
  /// frame's resolve phase before paint: it must not mark layout or
  /// rebuild.
  final ValueChanged<LayoutChange>? onLayout;

  /// Where the nearest child of a [MotionLayout] is drawn, in the layout's
  /// coordinates, or null outside one.
  static ValueListenable<LayoutItem>? itemOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.item;

  @override
  State<MotionLayout> createState() => _MotionLayoutState();
}

/// Plans how a change of layout animates.
abstract class LayoutMotion {
  /// Creates a layout motion.
  const LayoutMotion();

  /// Moves each child from where it was drawn to where layout puts it,
  /// entering with [insert] and leaving with [remove] (fading in and out by
  /// default, as SwiftUI does), on [spring] or on the frame's transaction
  /// when [spring] is null.
  const factory LayoutMotion.flip({
    Spring? spring,
    MotionEffect insert,
    MotionEffect remove,
  }) = _FlipLayoutMotion;

  /// The spring this motion animates on without a transaction, or null to
  /// follow the frame's transaction.
  Spring? get spring => null;

  /// The plan of each child of [change], by key: the child's key, or a
  /// `(Type, int)` record of an unkeyed child's type and place among the
  /// unkeyed children of that type. A child without a plan moves on the
  /// change's spring with no effect.
  Map<Object, LayoutPlan> plan(LayoutChange change);
}

final class _FlipLayoutMotion extends LayoutMotion {
  const _FlipLayoutMotion({
    this.spring,
    this.insert = MotionEffect.fade,
    this.remove = MotionEffect.fade,
  });

  @override
  final Spring? spring;

  final MotionEffect insert;

  final MotionEffect remove;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => {
    for (final MapEntry(:key, :value) in change.entries.entries)
      key: LayoutPlan(
        spring: change.spring,
        effect: switch (value.phase) {
          LayoutPhase.entering => insert,
          LayoutPhase.leaving => remove,
          LayoutPhase.staying => null,
        },
      ),
  };
}

/// Where a child of a change of layout stands.
enum LayoutPhase {
  /// The child arrived in this change.
  entering,

  /// The child was there before and is still there.
  staying,

  /// The child left in this change.
  leaving,
}

/// One child of a [LayoutChange].
@immutable
final class LayoutEntry {
  /// Describes one child of a change.
  const LayoutEntry({required this.phase, this.from, this.to});

  /// Whether the child arrived, stayed or left.
  final LayoutPhase phase;

  /// Where layout put the child before, or null when it arrived.
  final Rect? from;

  /// Where layout puts the child now, or null when it left.
  final Rect? to;
}

/// What a frame's layout did to the children of a [MotionLayout].
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

  /// The children that moved, arrived or left, by key.
  final Map<Object, LayoutEntry> entries;

  /// The spring of the frame's transaction or of the motion, or null when
  /// the change jumps.
  final Spring? spring;
}

/// How one child of a change animates.
@immutable
final class LayoutPlan {
  /// Describes how a child animates.
  const LayoutPlan({
    this.spring,
    this.delay = Duration.zero,
    this.origin,
    this.effect,
  });

  /// The spring, or null to jump.
  final Spring? spring;

  /// How long the child keeps its course before it moves.
  final Duration delay;

  /// Where an entering child starts, instead of where layout puts it.
  final Rect? origin;

  /// How the child enters or leaves.
  final MotionEffect? effect;
}

/// Where a child of a [MotionLayout] is drawn: its rect in the layout's
/// coordinates and its effect.
@immutable
final class LayoutItem {
  /// Describes where a child is drawn.
  const LayoutItem({
    required this.rect,
    this.scale = 1,
    this.opacity = 1,
    this.blur = 0,
  });

  /// The rect the child is drawn at, before [scale].
  final Rect rect;

  /// The scale about the rect's center.
  final double scale;

  /// The opacity.
  final double opacity;

  /// The blur sigma.
  final double blur;

  @override
  bool operator ==(Object other) =>
      other is LayoutItem &&
      other.rect == rect &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(rect, scale, opacity, blur);
}

final class _Item {
  _Item(this.id, Rect frame)
    : frame = MotionValue<Rect>(frame),
      presence = MotionValue<double>(1);

  final Object id;
  final MotionValue<Rect> frame;
  final MotionValue<double> presence;
  late final MotionComputed<LayoutItem> item = MotionComputed(_item);
  final GlobalKey key = GlobalKey();
  MotionEffect effect = MotionEffect.identity;
  Rect? model;
  bool leaving = false;
  bool leavePlanned = false;
  Widget? last;

  LayoutItem _item() {
    final p = presence.value;
    final at = frame.value;
    final drawn = at.topLeft & (model?.size ?? at.size);
    return LayoutItem(
      rect: drawn.shift(effect.offsetAt(p)),
      scale: effect.scaleAt(p),
      opacity: effect.opacityAt(p),
      blur: effect.blurAt(p),
    );
  }
}

class _MotionLayoutState extends State<MotionLayout> {
  final Map<Object, _Item> _items = {};
  List<Object> _ids = const [];
  final Set<Object> _leaving = {};
  bool _laidOut = false;
  bool _muted = false;

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

  bool get _jumps {
    final layout = MotionTransaction.layout;
    return _muted || (layout != null && layout.spring.isImmediate);
  }

  bool get _animates =>
      !_jumps &&
      (widget.motion.spring != null || MotionTransaction.layout != null);

  @override
  Widget build(BuildContext context) {
    _muted = !TickerMode.valuesOf(context).enabled;
    final ids = _idsOf(widget.children);
    final present = ids.toSet();
    for (final id in _ids) {
      if (present.contains(id) || _leaving.contains(id)) continue;
      final item = _items[id];
      if (item == null) continue;
      if (_animates && item.model != null) {
        item.leaving = true;
        _leaving.add(id);
      } else {
        _forget(id);
      }
    }
    for (final id in ids) {
      if (!_leaving.remove(id)) continue;
      final item = _items[id];
      if (item == null) continue;
      item.leaving = false;
      item.leavePlanned = false;
    }
    _ids = ids;
    final children = <Widget>[
      for (var i = 0; i < ids.length; i++)
        _probe(ids[i], widget.children[i], rest: null),
    ];
    final ghosts = <Widget>[
      for (final id in _leaving) _probe(id, _items[id]!.last!, rest: id),
    ];
    return _Host(
      state: this,
      children: [
        Builder(builder: (context) => widget.layoutBuilder(context, children)),
        ...ghosts,
      ],
    );
  }

  Widget _probe(Object id, Widget child, {required Object? rest}) {
    final item = _items[id] ??= _Item(id, Rect.zero);
    if (rest == null) item.last = child;
    return _Probe(
      key: item.key,
      item: item,
      child: _ItemScope(item: item.item, child: child),
    );
  }

  void _forget(Object id) {
    _items.remove(id);
    _leaving.remove(id);
  }

  void _left(_Item item) {
    if (!mounted || !item.leaving) return;
    if (item.presence.target != 0 || item.presence.value != 0) return;
    final clock = MotionClock.instance;
    if (clock.isResolving) {
      clock.schedule(clock.now, (_) => _left(item));
      return;
    }
    setState(() => _forget(item.id));
  }

  void _resolve(_RenderHost host) {
    final clock = MotionClock.instance;
    final time = clock.now;
    final layout = MotionTransaction.layout;
    final own = widget.motion.spring;
    final jump = !_laidOut || _jumps;
    // The first layout puts every child in place: nothing was drawn before.
    final spring = jump ? null : own ?? layout?.spring;
    _laidOut = true;
    final entries = <Object, LayoutEntry>{};
    for (final probe in host.probes) {
      final item = probe.item;
      final to = item.leaving ? null : probe.layoutFrame(host);
      final from = item.model;
      final returning = !item.leaving && item.presence.target != 1;
      if (to != null && from == to && !returning) continue;
      if (to == null && item.leavePlanned) continue;
      entries[item.id] = LayoutEntry(
        phase: item.leaving
            ? LayoutPhase.leaving
            : from == null || returning
            ? LayoutPhase.entering
            : LayoutPhase.staying,
        from: returning ? null : from,
        to: to,
      );
    }
    if (entries.isEmpty) return;
    final change = LayoutChange(time: time, entries: entries, spring: spring);
    final plans = widget.motion.plan(change);
    for (final MapEntry(:key, :value) in entries.entries) {
      final item = _items[key];
      if (item == null) continue;
      final plan = plans[key] ?? LayoutPlan(spring: spring);
      _apply(item, value, plan, time, jump: jump);
    }
    widget.onLayout?.call(change);
    host.markProbesChanged();
  }

  static MotionEffect _reduced(MotionEffect effect) =>
      MotionAccessibility.reduceMotion ? effect.reduced : effect;

  void _apply(
    _Item item,
    LayoutEntry entry,
    LayoutPlan plan,
    double time, {
    required bool jump,
  }) {
    final spring = plan.spring;
    final delay = plan.delay.inMicroseconds / Duration.microsecondsPerSecond;
    final effect = plan.effect ?? MotionEffect.identity;
    switch (entry.phase) {
      case LayoutPhase.entering:
        final to = entry.to!;
        final returning = item.model != null;
        item.model = to;
        item.effect = _reduced(effect);
        if (spring == null) {
          item.frame.snap(time, to);
          item.presence.snap(time, 1);
          return;
        }
        if (returning) {
          item.frame.retarget(time, to, spring: spring, delay: delay);
        } else {
          item.frame.snap(time, plan.origin ?? to);
          if (plan.origin != null) {
            item.frame.retarget(time, to, spring: spring, delay: delay);
          }
          item.presence.snap(time, 0);
        }
        item.presence.retarget(time, 1, spring: spring, delay: delay);
      case LayoutPhase.staying:
        final from = entry.from!;
        final to = entry.to!;
        item.model = to;
        if (spring != null) {
          item.frame.retarget(time, to, spring: spring, delay: delay);
        } else if (jump || item.frame.isWithin(time)) {
          item.frame.snap(time, to);
        } else {
          item.frame.shift(from, to);
        }
      case LayoutPhase.leaving:
        item.leavePlanned = true;
        item.effect = _reduced(effect);
        if (spring == null) {
          item.presence.snap(time, 0);
        } else {
          item.presence.retarget(time, 0, spring: spring, delay: delay);
        }
    }
  }
}

class _ItemScope extends InheritedWidget {
  const _ItemScope({required this.item, required super.child});

  final ValueListenable<LayoutItem> item;

  @override
  bool updateShouldNotify(_ItemScope oldWidget) =>
      !identical(oldWidget.item, item);
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
        MotionResolveHost {
  _RenderHost(this.state);

  _MotionLayoutState state;
  final Set<_RenderProbe> _probes = {};

  Iterable<_RenderProbe> get probes => _probes;

  void markProbesChanged() {
    for (final probe in _probes) {
      probe.markNeedsCompositedLayerUpdate();
    }
  }

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
      data.offset = probe.item.model?.topLeft ?? Offset.zero;
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

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.item, required super.child, super.key});

  final _Item item;

  @override
  _RenderProbe createRenderObject(BuildContext context) => _RenderProbe(item);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe renderObject) {
    renderObject.item = item;
  }
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this._item);

  _Item _item;
  _Item get item => _item;
  set item(_Item value) {
    if (identical(value, _item)) return;
    _unfollow();
    _item = value;
    _follow();
    markNeedsCompositedLayerUpdate();
  }

  _RenderHost? _host;
  BoxConstraints? lastConstraints;

  void _follow() {
    if (!attached) return;
    _item.frame.addRenderListener(_frameChanged);
    _item.presence.addRenderListener(_presenceChanged);
  }

  void _unfollow() {
    _item.frame.removeRenderListener(_frameChanged);
    _item.presence.removeRenderListener(_presenceChanged);
  }

  void _frameChanged() {
    markNeedsCompositedLayerUpdate();
    _semanticsAtRest();
  }

  void _presenceChanged() {
    markNeedsCompositedLayerUpdate();
    _semanticsAtRest();
    _host?.state._left(_item);
  }

  void _semanticsAtRest() {
    final frame = _item.frame;
    final presence = _item.presence;
    if (frame.value == frame.target && presence.value == presence.target) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var ancestor = parent;
    while (ancestor != null && ancestor is! _RenderHost) {
      ancestor = ancestor.parent;
    }
    _host = ancestor as _RenderHost?;
    _host?._probes.add(this);
    final theirs = child?.parentData;
    if (theirs != null) _copy(theirs, parentData);
    _follow();
  }

  @override
  void detach() {
    _unfollow();
    _host?._probes.remove(this);
    _host = null;
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    super.layout(constraints, parentUsesSize: parentUsesSize);
    lastConstraints = this.constraints;
    _host?.scheduleResolve();
  }

  /// Where layout put this child, in the host's coordinates.
  Rect layoutFrame(_RenderHost host) {
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

  static BoxParentData _mirror(ParentData? data) => switch (data) {
    FlexParentData() => FlexParentData(),
    StackParentData() => StackParentData(),
    MultiChildLayoutParentData() => MultiChildLayoutParentData(),
    _ => BoxParentData(),
  };

  @override
  void markNeedsLayout() {
    final mine = parentData;
    final theirs = child?.parentData;
    if (theirs != null && _copy(theirs, mine)) markParentNeedsLayout();
    super.markNeedsLayout();
  }

  static bool _copy(ParentData from, ParentData? to) {
    switch ((from, to)) {
      case (final FlexParentData a, final FlexParentData b):
        if (a.flex == b.flex && a.fit == b.fit) return false;
        b.flex = a.flex;
        b.fit = a.fit;
        return true;
      case (final StackParentData a, final StackParentData b):
        if (a.top == b.top &&
            a.right == b.right &&
            a.bottom == b.bottom &&
            a.left == b.left &&
            a.width == b.width &&
            a.height == b.height) {
          return false;
        }
        b.top = a.top;
        b.right = a.right;
        b.bottom = a.bottom;
        b.left = a.left;
        b.width = a.width;
        b.height = a.height;
        return true;
      case (
        final MultiChildLayoutParentData a,
        final MultiChildLayoutParentData b,
      ):
        if (a.id == b.id) return false;
        b.id = a.id;
        return true;
      default:
        return false;
    }
  }

  @override
  void performLayout() {
    final theirs = child?.parentData;
    if (theirs != null) _copy(theirs, parentData);
    super.performLayout();
  }

  Offset get _shift {
    final model = _item.model;
    if (model == null) return Offset.zero;
    return _item.frame.value.topLeft - model.topLeft;
  }

  Matrix4? get _transform {
    final presence = _item.presence.value;
    final shift = _shift + _item.effect.offsetAt(presence);
    final scale = _item.effect.scaleAt(presence);
    if (shift == Offset.zero && scale == 1) return null;
    final center = size.center(Offset.zero);
    final transform = Matrix4.translationValues(
      shift.dx + center.dx,
      shift.dy + center.dy,
      0,
    );
    transform.scaleByDouble(scale, scale, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    final presence = _item.presence.value;
    final opacity = _item.effect.opacityAt(presence).clamp(0.0, 1.0);
    final alpha = (opacity * 255).round();
    layer.update(
      transform: _transform,
      clip: null,
      alpha: alpha == 255 ? null : alpha,
      blur: math.max(0, _item.effect.blurAt(presence)),
    );
    return layer;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_transform case final move?) transform.multiply(move);
  }
}
