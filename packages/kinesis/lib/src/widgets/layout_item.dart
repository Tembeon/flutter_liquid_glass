import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/layout.dart' show LayoutMotionHosting;
import 'package:kinesis/src/widgets/follow.dart';
import 'package:kinesis/src/widgets/resolve.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// One item of a layout host: where it is drawn, and which descendants
/// draw it themselves.
@internal
final class LayoutItemEntry {
  /// Follows [id] of [motion].
  LayoutItemEntry(LayoutMotion motion, this.id)
    : item = motion.select((m) => m.hostItemAt(id));

  /// The item's key.
  final Object id;

  /// Where the item is drawn.
  final MotionSelection<LayoutItem> item;

  /// The probe's key, which keeps the item's element through moves.
  final GlobalKey key = GlobalKey();

  final Set<Element> _adopters = {};

  /// The probe that draws the item, told when adoption changes.
  RenderObject? probe;

  /// The widget the item last built, which a leaving item keeps.
  Widget? last;

  /// Whether a descendant draws the item itself.
  bool get adopted => _adopters.isNotEmpty;

  /// Records whether [adopter] draws the item.
  void adopt(Element adopter, {required bool adopts}) {
    final was = adopted;
    if (adopts) {
      _adopters.add(adopter);
    } else {
      _adopters.remove(adopter);
    }
    if (adopted != was) probe?.markNeedsCompositedLayerUpdate();
  }
}

const Object _adoptsItem = #adopts;

/// Hands an item's [entry] to the item's content.
@internal
class LayoutItemScope extends InheritedWidget {
  /// Scopes [child] to [entry].
  const LayoutItemScope({required this.entry, required super.child, super.key});

  /// The item.
  final LayoutItemEntry entry;

  /// The item around [context], or null; with [adopt] the dependent draws
  /// it itself.
  static ValueListenable<LayoutItem>? of(
    BuildContext context, {
    bool adopt = false,
  }) => context
      .dependOnInheritedWidgetOfExactType<LayoutItemScope>(
        aspect: adopt ? _adoptsItem : null,
      )
      ?.entry
      .item;

  @override
  bool updateShouldNotify(LayoutItemScope oldWidget) =>
      !identical(oldWidget.entry, entry);

  @override
  InheritedElement createElement() => _LayoutItemScopeElement(this);
}

class _LayoutItemScopeElement extends InheritedElement {
  _LayoutItemScopeElement(super.widget);

  LayoutItemEntry get _entry => (widget as LayoutItemScope).entry;

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);
    if (identical(aspect, _adoptsItem)) _entry.adopt(dependent, adopts: true);
  }

  @override
  void removeDependent(Element dependent) {
    _entry.adopt(dependent, adopts: false);
    super.removeDependent(dependent);
  }

  @override
  void updated(LayoutItemScope oldWidget) {
    if (!identical(oldWidget.entry, _entry)) {
      for (final adopter in oldWidget.entry._adopters.toList()) {
        oldWidget.entry.adopt(adopter, adopts: false);
        _entry.adopt(adopter, adopts: true);
      }
    }
    super.updated(oldWidget);
  }
}

/// What `MotionLayout` and `SliverMotionList` keep the same way: the
/// motion (given, or one of their own), the items by id, and the ghosts of
/// items that left while they are still drawn leaving.
@internal
mixin LayoutMotionOwner<W extends StatefulWidget> on State<W> {
  /// The motion the widget was given, or null.
  LayoutMotion? get givenMotion;

  /// The planner of the motion the widget keeps itself.
  LayoutPlanner get givenPlanner;

  /// Called with each change of layout, in the frame's resolve phase.
  ValueChanged<LayoutChange>? get onLayout;

  /// The items by id, ghosts included.
  final Map<Object, LayoutItemEntry> entries = {};

  /// The ids of items that left and are drawn leaving.
  final Set<Object> ghosts = {};

  bool _muted = false;

  LayoutMotion? _kept;
  late MotionSelection<int> _drawn;
  bool _leftPending = false;

  /// The motion the widget drives.
  LayoutMotion get motion =>
      givenMotion ??
      (_kept ??= LayoutMotion(
        planner: givenPlanner,
        clock: MotionClockScope.of(context),
      ));

  Spring? get _spring =>
      _muted ? Spring.immediate : MotionTransaction.layoutSpring;

  /// Whether the frame's layout keeps an item that left drawn while it
  /// leaves.
  bool get animates => motion.animates(_spring);

  /// Called by each build with the ids of the last build and those it
  /// builds: an id that left stays a ghost, drawn leaving, while the frame
  /// animates and its probe draws it where the host laid it out, and is
  /// forgotten otherwise; an id that came back is no longer a ghost. Under
  /// a muted `TickerMode` ([followsMotion]) the frame does not animate.
  void updateGhosts(Iterable<Object> last, Set<Object> present) {
    _muted = !followsMotion(context);
    for (final id in last) {
      if (present.contains(id) || ghosts.contains(id)) continue;
      if (animates &&
          entries[id]?.probe != null &&
          motion.hostLaidOut(id) != null) {
        ghosts.add(id);
      } else {
        entries.remove(id);
      }
    }
    ghosts.removeAll(present);
  }

  /// Lays the items out at [rects] on the frame's spring and, when that
  /// changed them, tells [onLayout] and the probes of [host]; [arrived] as
  /// `LayoutMotion.layout` takes it.
  void place(
    LayoutProbeHost host,
    Map<Object, Rect> rects, {
    Set<Object>? arrived,
  }) {
    final change = motion.layout(
      motion.clock.now,
      rects,
      spring: _spring,
      arrived: arrived,
    );
    if (change == null) return;
    onLayout?.call(change);
    host.markProbesChanged();
  }

  /// Follows a change of the given motion from [previous].
  void motionUpdated(LayoutMotion? previous) {
    final kept = _kept;
    if (givenMotion == null && kept != null) kept.planner = givenPlanner;
    if (identical(previous, givenMotion)) return;
    _unbind();
    entries.clear();
    ghosts.clear();
    _bind();
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _bind() {
    _drawn = motion.select((m) => m.ids.length);
    _drawn.addRenderListener(_dropped);
  }

  void _unbind() => _drawn.removeRenderListener(_dropped);

  // Heard in the resolve phase too, where nothing may rebuild: the rebuild
  // that lets the ghosts go waits for the clock's coming publish phase.
  void _dropped() {
    if (_leftPending || ghosts.every(motion.contains)) return;
    _leftPending = true;
    motion.clock.schedulePublish(() {
      _leftPending = false;
      _left();
    });
  }

  void _left() {
    if (!mounted) return;
    final gone = ghosts.where((id) => !motion.contains(id)).toList();
    if (gone.isEmpty) return;
    setState(() {
      ghosts.removeAll(gone);
      gone.forEach(entries.remove);
    });
  }
}

/// The render object that hosts the probes of a layout's items and lays
/// its motion out in the resolve phase.
@internal
mixin LayoutProbeHost on MotionResolveHost {
  /// The probes attached under this host.
  final Set<LayoutProbeBox> probes = {};

  /// Marks every probe to draw its item again.
  void markProbesChanged() {
    for (final probe in probes) {
      probe.markNeedsCompositedLayerUpdate();
    }
  }
}

/// The widget of one item of a layout host, which [create] makes the render
/// object of.
@internal
class LayoutProbe extends SingleChildRenderObjectWidget {
  /// Draws the item [entry] of [motion] around [child].
  const LayoutProbe({
    required this.create,
    required this.motion,
    required this.entry,
    required this.ghost,
    required Widget super.child,
    super.key,
  });

  /// Makes the host's kind of probe.
  final LayoutProbeBox Function(
    LayoutMotion motion,
    LayoutItemEntry entry, {
    required bool ghost,
  })
  create;

  /// The motion that places the item.
  final LayoutMotion motion;

  /// The item.
  final LayoutItemEntry entry;

  /// Whether the item left and is drawn leaving.
  final bool ghost;

  @override
  LayoutProbeBox createRenderObject(BuildContext context) =>
      create(motion, entry, ghost: ghost);

  @override
  void updateRenderObject(BuildContext context, LayoutProbeBox renderObject) {
    renderObject
      ..motion = motion
      ..entry = entry
      ..ghost = ghost;
  }
}

/// The render object of one item of a layout host: it draws the item
/// where its motion puts it, through one composited layer, unless a
/// descendant draws the item itself.
@internal
abstract class LayoutProbeBox extends RenderProxyBox {
  /// Draws the item [entry] of [motion].
  LayoutProbeBox(this.motion, this._entry, {required this.ghost});

  /// The motion that places the item.
  LayoutMotion motion;

  /// Whether the item left and is drawn leaving.
  bool ghost;

  LayoutItemEntry _entry;

  /// The item.
  LayoutItemEntry get entry => _entry;
  set entry(LayoutItemEntry value) {
    if (identical(value, _entry)) return;
    _unfollow();
    _entry = value;
    _follow();
    markNeedsCompositedLayerUpdate();
  }

  LayoutProbeHost? _host;

  /// The host this probe is attached under, or null.
  @protected
  LayoutProbeHost? get host => _host;

  /// The item's key.
  Object get id => _entry.id;

  /// Whether the probe draws the item: no descendant adopted it.
  bool get _drawsItem => !_entry.adopted;

  /// Where the host's layout puts the item, in the rects the host lays its
  /// motion out in.
  Rect get layoutRect;

  /// The rect the item's drawn rect is placed against, or null while the
  /// motion has not laid the item out.
  @protected
  Rect? get placed;

  /// The size the item's content is drawn at.
  @protected
  Size get drawnSize;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var ancestor = parent;
    while (ancestor != null && ancestor is! LayoutProbeHost) {
      ancestor = ancestor.parent;
    }
    _host = ancestor as LayoutProbeHost?;
    _host?.probes.add(this);
    _follow();
  }

  @override
  void detach() {
    _unfollow();
    _host?.probes.remove(this);
    _host = null;
    super.detach();
  }

  void _follow() {
    if (!attached) return;
    _entry.item.addRenderListener(_itemChanged);
    _entry.probe = this;
  }

  void _unfollow() {
    _entry.item.removeRenderListener(_itemChanged);
    if (identical(_entry.probe, this)) _entry.probe = null;
  }

  void _itemChanged() {
    if (_drawsItem) markNeedsCompositedLayerUpdate();
    if (motion.itemRests(id)) markNeedsSemanticsUpdate();
  }

  /// The move, scale and turn the item's motion gives the child, or null
  /// at identity or while a descendant draws the item.
  Matrix4? get _itemTransform {
    if (!_drawsItem || !hasSize) return null;
    final placed = this.placed;
    if (placed == null) return null;
    final item = _entry.item.value;
    return poseTransform(
      item.pose,
      drawnSize,
      shift: item.rect.center - placed.center,
    );
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    if (!_drawsItem) {
      layer.update(transform: null, clip: null, opacity: 1, blur: 0);
      return layer;
    }
    final pose = _entry.item.value.pose;
    layer.update(
      transform: _itemTransform,
      clip: null,
      opacity: pose.opacity,
      blur: pose.blur,
    );
    return layer;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_itemTransform case final move?) transform.multiply(move);
  }
}
