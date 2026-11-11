import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// The measured UIKit control whose motion and geometry a
/// [RawGlassSelector] takes.
enum GlassSelectorMotion {
  /// `UISegmentedControl`: a track 32 points tall with a lens inset 2
  /// points in it. A touch dims the label of a segment that is not
  /// selected, a drag lifts the lens into glass and carries it, and a
  /// release outside 70 points of the control selects nothing.
  segmented,

  /// `UITabBar`: a bar 62 points tall with a lens 54 points tall. The bar
  /// swells and drifts under the finger and a glow follows it, and inside
  /// the lens every item shows its selected look.
  tabBar,
}

/// What turns a tab bar selector into a circle and back: the same bar
/// throughout, its glass and content following [morph], whatever asks for
/// it (a scroll, a search).
abstract interface class GlassSelectorCollapse {
  /// The way from the bar (0) to the circle (1); a spring may overshoot both.
  MotionSelection<double> get morph;

  /// How far a finger has lifted the circle, 0 to 1, or null if it never
  /// does.
  MotionSelection<double>? get press;

  /// The circle in the bar's box of [size].
  Rect circleIn(Size size);

  /// Whether a finger on the bar now means the circle, not a tab.
  bool get takesFinger;

  /// A finger went down on the circle at [x] along the bar, at time [t].
  void pressDown(double t, double x);

  /// The finger moved to [x]; true on the move that hands it to the bar's
  /// selection drag.
  bool pressMove(double t, double x);

  /// The finger lifted without having moved along the bar.
  void pressUp(double t);

  /// The touch was taken away.
  void pressCancel(double t);

  /// A key or a screen reader activated the circle.
  void activate();
}

/// Builds the item at [index] of a [RawGlassSelector] for [states]: the
/// item's own states, which include [WidgetState.selected] for the selected
/// item, [WidgetState.disabled] for an item that cannot be selected, and
/// the pressed, hovered and focused states of the item's own target: a
/// touch presses the item it lands on until the finger moves and the lens
/// takes it.
///
/// Every item is built three times: without [WidgetState.selected] for the
/// row under the lens, and with it for the copies the lens shows wherever
/// it is, as UIKit masks a selected copy of every tab by the lens: one over
/// the resting lens and one under its glass, which bends it.
typedef GlassSelectorItemBuilder = Widget Function(
  BuildContext context,
  int index,
  Set<WidgetState> states,
);

/// Builds a glass selector from [details]; it runs again when the
/// selector's states, selection or items change, never while the lens
/// moves.
typedef GlassSelectorBuilder = Widget Function(
  BuildContext context,
  GlassSelectorDetails details,
);

/// What a [GlassSelectorBuilder] builds a selector from.
@immutable
final class GlassSelectorDetails {
  /// Describes a selector.
  const GlassSelectorDetails({
    required this.body,
    required this.lens,
    required this._items,
    required this.selectedIndex,
    required this.states,
    @internal this.lensShrink,
  });

  /// The frames of the track or bar, which fills the selector: the glow a
  /// finger raises on a tab bar.
  final MotionSelection<GlassFrame> body;

  /// The frames of the lens in the selector's box: where it sits, how it
  /// stretches, and how far a finger has lifted it into glass.
  final MotionSelection<GlassFrame> lens;

  final Widget Function(Widget? lens) _items;

  /// The items laid out in their slots, with [lens] filling the selector
  /// over their regular look. Their selected look shows only inside the
  /// lens: over it at rest and under its glass once it lifts, so as in
  /// UIKit the lifted lens bends it and, at its rim, the items around it.
  /// The builder places this once, over the body: it gives the selector
  /// its size.
  Widget items({Widget? lens}) => _items(lens);

  /// The selected item, or null when none is and the lens is hidden.
  final int? selectedIndex;

  /// The states the selector is in.
  final Set<WidgetState> states;

  /// Where the renderer of the lens given to [items] reports how its glass
  /// shrinks what lies under it, so the selector grows its selected copies
  /// against it.
  @internal
  final ValueNotifier<GlassLensShrink>? lensShrink;
}

/// A pick-one control with the measured selection lens of iOS 27 and no
/// look of its own: [builder] decides how it looks.
///
/// UIKit: `UISegmentedControl`, `UITabBar`. SwiftUI: `Picker` with
/// `.segmented`, `TabView`. Flutter: `CupertinoSlidingSegmentedControl`,
/// `NavigationBar`.
///
/// [motion] picks the UIKit control whose motion and geometry it takes. A
/// tap selects on release; a finger that drags lifts the lens into glass
/// and carries it, and the release selects where it lands. Everything the
/// lens does reaches the look through [GlassSelectorDetails.lens], so its
/// motion rebuilds neither builder; [itemBuilder] runs again for an item
/// whose own states change.
///
/// Each item is a target of its own for the keyboard and assistive
/// technology, 44 points tall at least: a button in a group of one choice
/// on a segmented control, a tab on a tab bar, read by [itemLabels]. The
/// group is one Tab stop, entered at the selected item; an arrow key moves
/// focus to the neighbouring item and selects it, mirrored in a
/// right-to-left context and skipping [disabledItems], and Home and End
/// move to the first and last item and select it. Space and Enter on the
/// focused item, which is the selected one, report [onReselected]. A tap
/// in an item's 44 point extension above or below the look reaches that
/// item. [focusNode] stands for the selector: focusing it focuses the
/// selected item. In a right-to-left context the items run from the right.
class RawGlassSelector extends StatefulWidget {
  /// Creates a selector of [itemCount] items.
  const RawGlassSelector({
    required this.itemCount,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    required this.builder,
    this.motion = GlassSelectorMotion.segmented,
    this.onReselected,
    this.disabledItems = const {},
    this.itemKeys,
    this.itemWidths,
    this.proportionalWidth = false,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.itemLabels,
    this.collapse,
    @internal this.hosted = false,
    super.key,
  }) : assert(
         itemKeys == null || itemKeys.length == itemCount,
         'One key per item.',
       ),
       assert(
         itemLabels == null || itemLabels.length == itemCount,
         'One label per item.',
       );

  /// The number of items.
  final int itemCount;

  /// What identifies each item across changes of the items, or null to
  /// identify them by position.
  ///
  /// When the items change inside `withSpring`, the items that stay slide
  /// to their new slots, new ones fade in, the ones that go fade out where
  /// they were, and the lens moves with its item; outside one the change
  /// jumps. Not measured: UIKit's animated `insertSegment`,
  /// `removeSegment` and `setItems` were not captured.
  final List<Object>? itemKeys;

  /// The selected item, clamped to the items, or null for none
  /// (`UISegmentedControl.noSegment`): the lens is hidden, and a tap
  /// selects on release and shows the lens at rest on its item, without
  /// travel or lift (how UIKit shows a first selection is not measured).
  final int? selectedIndex;

  /// Called with the item the user selects; with [onReselected] null too,
  /// the selector is disabled. A selector whose [selectedIndex] does not
  /// follow returns to it.
  final ValueChanged<int>? onChanged;

  /// Builds each item.
  final GlassSelectorItemBuilder itemBuilder;

  /// Builds the selector's look.
  final GlassSelectorBuilder builder;

  /// The UIKit control whose motion and geometry the selector takes.
  final GlassSelectorMotion motion;

  /// Called with the selected item when the user selects it again (UIKit's
  /// `tabBarController(_:didSelect:)` for the selected tab): a touch that
  /// lifts on it (on a tab bar, one that also went down on it), Space,
  /// Enter, or an accessibility tap.
  final ValueChanged<int>? onReselected;

  /// The items a touch, a key or accessibility cannot select (UIKit
  /// `setEnabled(_:forSegmentAt:)`).
  final Set<int> disabledItems;

  /// The width of each segment in points, or null in a slot to share the
  /// room with the others (UIKit `setWidth(_:forSegmentAt:)`); segmented
  /// only.
  final List<double?>? itemWidths;

  /// Whether segments are as wide as their items rather than equal (UIKit
  /// `apportionsSegmentWidthsByContent`); segmented only.
  final bool proportionalWidth;

  /// Where the selector writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The selector's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the selector takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the selector as a whole.
  final String? semanticLabel;

  /// What accessibility reads for each item, or null for none; the items'
  /// own semantics are not read.
  final List<String?>? itemLabels;

  /// What collapses a tab bar into a circle, or null; a bar under one has a
  /// box as wide as it is given and draws its glass where the collapse
  /// says.
  final GlassSelectorCollapse? collapse;

  /// Whether a tab bar hosts an accessory or a search, which makes it span
  /// the width it is given whatever its tabs.
  @internal
  final bool hosted;

  /// How far outside a segmented control a finger may lift and still
  /// select: a release beyond it changes nothing, and the lens settles back
  /// as after a cancelled touch.
  ///
  /// UISegmentedControl selects on a release 60 points below its bottom
  /// edge but not 70 (iPhone 16 Pro, iOS 27.0.1; the capture is not among
  /// this package's fixtures). 70 with the bottom and right edges
  /// excluded, the way `CGRectContainsPoint` tests a point, also gives the
  /// glass button's measured edges.
  static const double segmentedReleaseSlop = GlassPress.highlightSlop;

  @override
  State<RawGlassSelector> createState() => _RawGlassSelectorState();
}

class _RawGlassSelectorState extends State<RawGlassSelector>
    with ControlStates<RawGlassSelector> {
  late _SelectorMotion _motion = _create(widget.selectedIndex ?? 0);
  late _SelectorFrames _frames = _SelectorFrames(
    _motion,
    mirrored: false,
    collapse: widget.collapse,
  );
  late Listenable _zoneFrames = _zoneFramesOf(_frames);
  bool _fingerOnCircle = false;
  late final _SelectorInput _input = _SelectorInput(this);
  late final List<Interaction> _interactions = [_input];
  final _zones = InputZonesController<Object>();
  final Map<Object, List<Interaction>> _presses = {};
  // A selection the app may not follow: the next build returns the lens to
  // the selected item if it did not.
  bool _returning = false;
  bool _rtl = false;
  final _lensShrink = ValueNotifier<GlassLensShrink>((
    shrink: 0,
    rim: 0,
  ));
  late List<Object> _keys = _keysOf(widget);
  // Items gone from the widget that still fade out where they were, and
  // the last children each item built, which a fading item keeps.
  final List<Object> _ghosts = [];
  final Map<Object, List<Widget>> _built = {};
  int? _noneDown;
  int? _downSlot;
  int? _downSelected;

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  bool get _enabled => widget.onChanged != null || widget.onReselected != null;

  bool get _segmented => widget.motion == GlassSelectorMotion.segmented;

  int? get _selected {
    final index = widget.selectedIndex;
    if (index == null || widget.itemCount == 0) return null;
    return index.clamp(0, widget.itemCount - 1);
  }

  bool _selectable(int index) =>
      _enabled &&
      index >= 0 &&
      index < widget.itemCount &&
      !widget.disabledItems.contains(index);

  static List<Object> _keysOf(RawGlassSelector widget) =>
      widget.itemKeys ?? [for (var i = 0; i < widget.itemCount; i++) i];

  _SelectorMotion _create(int selected) => _SelectorMotion(
    kind: widget.motion,
    selected: selected,
    isSelectable: _selectable,
    onEvent: _deliver,
  );

  static Listenable _zoneFramesOf(_SelectorFrames frames) => Listenable.merge([
    _HeardInResolve(frames.items),
    ?frames.collapse?.morph,
  ]);

  double get _now => _motion.clock.now;

  @override
  void initState() {
    super.initState();
    _zones.addListener(_zonesChanged);
    _frames.placed.addListener(_placedChanged);
  }

  @override
  void didUpdateWidget(RawGlassSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.motion != _motion.kind) {
      _motion = _create(_motion.selected);
      _setFrames(_frames.mirrored);
    }
    final keys = _keysOf(widget);
    final wasNone = oldWidget.selectedIndex == null;
    if (listEquals(keys, _keys)) {
      _sync(wasNone);
    } else {
      final present = keys.toSet();
      for (final key in _keys) {
        if (!present.contains(key) &&
            _built.containsKey(key) &&
            !_ghosts.contains(key)) {
          _ghosts.add(key);
        }
      }
      _ghosts.removeWhere(present.contains);
      _built.removeWhere(
        (key, _) => !present.contains(key) && !_ghosts.contains(key),
      );
      _presses.removeWhere((key, _) => !present.contains(key));
      _keys = keys;
      final selected = _selected;
      if (selected != null && !wasNone) {
        _motion.remap(selected);
      } else {
        _sync(wasNone);
      }
    }
  }

  @override
  void dispose() {
    _zones.removeListener(_zonesChanged);
    _zones.dispose();
    _frames.placed.removeListener(_placedChanged);
    _lensShrink.dispose();
    super.dispose();
  }

  @override
  void writeStates() {
    final disabled = !_enabled;
    widgetStates.update(WidgetState.disabled, disabled);
    if (disabled) {
      widgetStates.update(WidgetState.pressed, false);
      widgetStates.update(WidgetState.dragged, false);
    }
  }

  void _writeTouch() {
    if (!_enabled) return;
    widgetStates.update(WidgetState.pressed, _input.pressed);
    widgetStates.update(WidgetState.dragged, _input.dragged);
  }

  // The selector is hovered and focused when one of its items is.
  void _zonesChanged() {
    var hovered = false;
    var focused = false;
    for (final key in _keys) {
      final states = _zones.statesOf(key);
      hovered = hovered || states.contains(WidgetState.hovered);
      focused = focused || states.contains(WidgetState.focused);
    }
    widgetStates.update(WidgetState.hovered, hovered);
    widgetStates.update(WidgetState.focused, focused);
  }

  // An item that faded out leaves the children it kept: once, when the
  // motion lets it go, not each frame.
  void _placedChanged() {
    if (_ghosts.any((key) => !_motion.items.contains(key))) setState(() {});
  }

  void _setFrames(bool mirrored) {
    _frames.placed.removeListener(_placedChanged);
    _frames = _SelectorFrames(
      _motion,
      mirrored: mirrored,
      collapse: widget.collapse,
    );
    _zoneFrames = _zoneFramesOf(_frames);
    _frames.placed.addListener(_placedChanged);
  }

  void _sync(bool wasNone) {
    final selected = _selected;
    if (selected == null) return;
    if (wasNone) {
      _motion.place(_now, selected);
    } else if (_motion.selected != selected) {
      _motion.choose(_now, selected, notify: false);
    }
  }

  // A selection the app does not follow returns in the next build, which
  // the selection itself asks for: the app's own rebuild may never come.
  void _return() {
    if (!_returning || _input.active) return;
    _returning = false;
    final selected = _selected;
    if (selected != null && _motion.selected != selected) {
      _motion.choose(_now, selected, notify: false);
    }
  }

  void _deliver(LensEvent event) {
    switch (event) {
      case LensSelected(:final index):
        _chosen(index);
    }
  }

  void _chosen(int index) {
    if (index != widget.selectedIndex) widget.onChanged?.call(index);
    if (mounted) setState(() => _returning = true);
  }

  void _select(int index) {
    if (!_selectable(index)) return;
    final selected = _selected;
    if (selected == null) {
      _motion.place(_now, index);
      _chosen(index);
    } else if (index == selected) {
      widget.onReselected?.call(index);
    } else {
      _motion.choose(_now, index);
    }
  }

  double _x(Offset position) =>
      _rtl ? _motion.size.width - position.dx : position.dx;

  bool _within(Offset position) {
    if (!_segmented) return true;
    return (Offset.zero & _motion.size)
        .inflate(RawGlassSelector.segmentedReleaseSlop)
        .contains(position);
  }

  void _down(PointerDownInput input) {
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      _fingerOnCircle = true;
      collapse.pressDown(input.time, input.position.dx);
      return;
    }
    final x = _x(input.position);
    final slot = _motion.slotAt(x);
    final selected = _selected;
    if (_segmented && _selectable(slot) && slot != selected) {
      _motion.highlight.press(input.time, slot);
    }
    if (selected == null) {
      _noneDown = slot;
      return;
    }
    _downSlot = slot;
    _downSelected = _motion.selected;
    _motion.down(input.time, x, input.position, glows: _selectable(slot));
  }

  void _move(PointerMoveInput input) {
    if (_fingerOnCircle) {
      if (!widget.collapse!.pressMove(input.time, input.position.dx)) return;
      _fingerOnCircle = false;
      _motion.drag(input.time, _x(input.position), input.position);
    }
    if (_noneDown != null) return;
    _motion.move(input.time, _x(input.position), input.position);
  }

  void _up(PointerUpInput input) {
    if (_fingerOnCircle) {
      _fingerOnCircle = false;
      widget.collapse!.pressUp(input.time);
      return;
    }
    final x = _x(input.position);
    final slot = _motion.slotAt(x);
    final before = _downSelected;
    final down = _downSlot;
    _downSlot = null;
    _downSelected = null;
    if (_noneDown != null) {
      _noneDown = null;
      _motion.cancel(input.time);
      if (_within(input.position)) _select(slot);
      return;
    }
    if (!_within(input.position)) {
      _motion.cancel(input.time);
      return;
    }
    _motion.up(input.time, x);
    final reselected =
        before != null &&
        slot == before &&
        _motion.selected == before &&
        (_segmented || down == before);
    if (reselected && _selectable(before)) widget.onReselected?.call(before);
  }

  void _cancel(double time) {
    if (_fingerOnCircle) {
      _fingerOnCircle = false;
      widget.collapse!.pressCancel(time);
      return;
    }
    _noneDown = null;
    _downSlot = null;
    _downSelected = null;
    _motion.cancel(time);
  }

  void _activate(Object key) {
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      collapse.activate();
      return;
    }
    final index = _keys.indexOf(key);
    if (index >= 0) _select(index);
  }

  void _focusSelected(bool focused) {
    if (!focused || !(widget.focusNode?.hasPrimaryFocus ?? false)) return;
    final selected = _selected;
    final index = selected != null && _selectable(selected)
        ? selected
        : Iterable<int>.generate(widget.itemCount)
              .where(_selectable)
              .firstOrNull;
    if (index != null) _zones.requestFocus(_keys[index]);
  }

  // The selected item is the one the lens shows; when a collapse holds the
  // finger, it is the circle and the only item there is.
  InputZoneFrame? _zoneFrame(Object key) {
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      final selected = _selected;
      if (selected == null || _keys[selected] != key) return null;
      return InputZoneFrame(collapse.circleIn(_motion.size));
    }
    final drawn = _motion.drawn(key);
    if (drawn == null) return null;
    final (rect, opacity) = drawn;
    return InputZoneFrame(rect, opacity: opacity);
  }

  List<InputZone<Object>> _zoneList() {
    final selected = _selected;
    return [
      for (final (i, key) in _keys.indexed)
        InputZone<Object>(
          id: key,
          interactions: _presses[key] ??= [_ItemPress(() => _activate(key))],
          enabled: _selectable(i),
          minimumHitSize: const Size.square(44),
          autofocus: widget.autofocus && i == (selected ?? 0),
          semantics: SemanticsProperties(
            label: widget.itemLabels?[i],
            button: _segmented ? true : null,
            selected: i == selected,
            inMutuallyExclusiveGroup: _segmented ? true : null,
            role: _segmented ? null : SemanticsRole.tab,
          ),
        ),
    ];
  }

  Widget _item(BuildContext context, int index, {required bool selected}) =>
      _ItemStates(
        zones: _zones,
        id: _keys[index],
        own: {
          if (selected) WidgetState.selected,
          if (!_selectable(index)) WidgetState.disabled,
        },
        builder: (context, states) =>
            Center(child: widget.itemBuilder(context, index, states)),
      );

  List<Widget> _build(BuildContext context, int index) {
    final key = _keys[index];
    return _built[key] = [
      RepaintBoundary(
        key: ValueKey((0, key)),
        child: _item(context, index, selected: false),
      ),
      // The copy under the glass draws once per strip of the lens: a
      // boundary's layer could sit in only one.
      KeyedSubtree(
        key: ValueKey((1, key)),
        child: _item(context, index, selected: true),
      ),
      RepaintBoundary(
        key: ValueKey((2, key)),
        child: _item(context, index, selected: true),
      ),
    ];
  }

  Widget _items(BuildContext context, Widget? lens) {
    final selected = _selected;
    final zones = InputZones<Object>(
      zones: _zoneList(),
      frameOf: _zoneFrame,
      frames: _zoneFrames,
      controller: _zones,
      stops: InputZoneStops.one,
      current: selected == null ? null : _keys[selected],
      activatesOnMove: true,
      child: _SelectorRow(
        motion: _motion,
        frames: _frames,
        kind: widget.motion,
        keys: _keys,
        ghosts: List.of(_ghosts),
        itemWidths: widget.itemWidths,
        proportional: widget.proportionalWidth,
        collapse: widget.collapse,
        hosted: widget.hosted,
        showsLens: selected != null,
        hasLens: lens != null,
        lensShrink: _lensShrink,
        children: [
          for (var i = 0; i < _keys.length; i++) ..._build(context, i),
          for (final key in _ghosts) ..._built[key]!,
          ?lens,
        ],
      ),
    );
    if (_segmented) return zones;
    return _TabBarNode(
      frames: _zoneFrames,
      hasTabs: () => _keys.any((key) => _zoneFrame(key)?.live ?? false),
      child: zones,
    );
  }

  @override
  Widget build(BuildContext context) {
    _return();
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (_rtl != _frames.mirrored ||
        !identical(widget.collapse, _frames.collapse)) {
      _setFrames(_rtl);
    }
    _ghosts.removeWhere((key) {
      if (_motion.items.contains(key)) return false;
      _built.remove(key);
      return true;
    });
    final look = widget.builder(
      context,
      GlassSelectorDetails(
        body: _frames.body,
        lens: _frames.lens,
        items: (lens) => _items(context, lens),
        selectedIndex: _selected,
        states: {...widgetStates.value},
        lensShrink: _lensShrink,
      ),
    );
    // The lens drag lies above the look, so its 44 point target reaches
    // past the look's box and hands an item the nearest point of it; it
    // takes no key, so the focused item keeps Space and Enter.
    final dragged = InputRegion(
      interactions: _interactions,
      enabled: _enabled && widget.itemCount > 0,
      minimumHitSize: const Size.square(44),
      child: look,
    );
    Widget child = _SelectorBox(
      frame: widget.collapse == null ? null : _frames.body,
      label: widget.semanticLabel,
      child: _segmented
          ? dragged
          : MotionTransition(
              offset: _frames.drift,
              scaleX: _frames.scaleX,
              scaleY: _frames.scaleY,
              child: dragged,
            ),
    );
    if (widget.focusNode case final node?) {
      // The app's node stands for the selector: focusing it focuses the
      // selected item.
      child = Focus(
        focusNode: node,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _focusSelected,
        child: child,
      );
    }
    return MotionScope(motion: _motion, child: child);
  }
}

/// The tab bar's semantics node, holding its tabs: without a tab that
/// shows (a bar given no room), it is no tab bar.
class _TabBarNode extends SingleChildRenderObjectWidget {
  const _TabBarNode({
    required this.frames,
    required this.hasTabs,
    required super.child,
  });

  final Listenable frames;
  final bool Function() hasTabs;

  @override
  _RenderTabBarNode createRenderObject(BuildContext context) =>
      _RenderTabBarNode(frames, hasTabs);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTabBarNode renderObject,
  ) {
    renderObject.frames = frames;
    renderObject.hasTabs = hasTabs;
  }
}

class _RenderTabBarNode extends RenderProxyBox {
  _RenderTabBarNode(this._frames, this.hasTabs);

  bool Function() hasTabs;

  Listenable _frames;
  Listenable get frames => _frames;
  set frames(Listenable value) {
    if (identical(value, _frames)) return;
    if (attached) _frames.removeListener(markNeedsSemanticsUpdate);
    _frames = value;
    if (attached) _frames.addListener(markNeedsSemanticsUpdate);
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _frames.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
    if (hasTabs()) config.role = SemanticsRole.tabBar;
  }
}

/// [selection] heard in the frame it moves: the items move in the resolve
/// phase, after the layout that places them, where only a render listener
/// hears them.
final class _HeardInResolve implements Listenable {
  const _HeardInResolve(this.selection);

  final MotionSelection<Object?> selection;

  @override
  void addListener(VoidCallback listener) =>
      selection.addRenderListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      selection.removeRenderListener(listener);
}

/// An item's look for its own states and those its zone has.
class _ItemStates extends StatefulWidget {
  const _ItemStates({
    required this.zones,
    required this.id,
    required this.own,
    required this.builder,
  });

  final InputZonesController<Object> zones;
  final Object id;
  final Set<WidgetState> own;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;

  @override
  State<_ItemStates> createState() => _ItemStatesState();
}

class _ItemStatesState extends State<_ItemStates> {
  late Set<WidgetState> _zone = _read();

  Set<WidgetState> _read() => {
    for (final state in widget.zones.statesOf(widget.id))
      if (state != WidgetState.disabled) state,
  };

  @override
  void initState() {
    super.initState();
    widget.zones.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ItemStates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.zones, widget.zones)) {
      oldWidget.zones.removeListener(_changed);
      widget.zones.addListener(_changed);
    }
    _zone = _read();
  }

  @override
  void dispose() {
    widget.zones.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = _read();
    if (!setEquals(next, _zone)) setState(() => _zone = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, {...widget.own, ..._zone});
}

/// An item's press: it holds no touch, so the selector's lens drag takes a
/// finger that moves, and a key or a screen reader activates the item.
final class _ItemPress extends PressInteraction {
  _ItemPress(this.onActivate) : super(role: InteractionRole.content);

  final VoidCallback onActivate;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is ActivateInput) onActivate();
    return super.handle(input);
  }
}

/// The geometry a selector lays its items out in.
@immutable
final class _Geometry {
  const _Geometry({
    required this.size,
    required this.slots,
    required this.lenses,
    this.drawn,
  });

  factory _Geometry.of(
    GlassSelectorMotion kind,
    BoxConstraints constraints,
    List<double> items, {
    required List<double?>? fixed,
    required bool proportional,
    required bool spans,
    required bool hosted,
  }) {
    final h = height(kind);
    switch (kind) {
      case GlassSelectorMotion.segmented:
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : natural(kind, items, fixed);
        final size = constraints.constrain(Size(width, h));
        final widths = _segmentWidths(
          size.width,
          items,
          fixed,
          proportional: proportional,
        );
        final slots = <Rect>[];
        final lenses = <LensSlot>[];
        var left = 0.0;
        for (final w in widths) {
          slots.add(Rect.fromLTWH(left, 0, w, size.height));
          lenses.add((center: left + w / 2, width: w - 2 * segmentedInset));
          left += w;
        }
        return _Geometry(size: size, slots: slots, lenses: lenses);
      case GlassSelectorMotion.tabBar:
        final box = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : tabBarWidth;
        final bar = TabBarLayout.of(
          items,
          available: box < TabBarLayout.phoneBelow ? box : tabBarWidth,
          hosted: hosted,
        );
        final size = constraints.constrain(
          Size(spans ? box : bar.width, h),
        );
        final left = (size.width - bar.width) / 2;
        return _Geometry(
          size: size,
          drawn: Rect.fromLTWH(left, 0, bar.width, size.height),
          slots: [
            for (final button in bar.buttons)
              Rect.fromLTWH(
                left + button.center - button.width / 2,
                0,
                button.width,
                size.height,
              ),
          ],
          lenses: [
            for (final button in bar.buttons)
              (center: left + button.center, width: button.width),
          ],
        );
    }
  }

  final Size size;

  /// Where a tab bar under a [GlassSelectorCollapse] draws in its box,
  /// which spans the whole group.
  final Rect? drawn;

  /// Where the control draws its track or bar in its box.
  Rect get bar => drawn ?? Offset.zero & size;

  /// Each item's box, left to right.
  final List<Rect> slots;

  /// Each item's resting lens along the track, left to right.
  final List<LensSlot> lenses;

  /// The height of a segmented control.
  static const double segmentedHeight = 32;

  /// The gap between a segmented track and its resting lens.
  static const double segmentedInset = 2;

  /// The padding on each side of a segment's item when segments size by
  /// content: UIKit pads a label by 9 points a side (read from UIKit, notes
  /// private), and with Flutter's label widths the device's content rows
  /// fit 9.13 - 9.18.
  static const double segmentedPadding = 9.15;

  /// The height of a tab bar (tab bar passport, layout and device).
  static const double tabBarHeight = 62;

  /// The height of a tab bar's resting lens (tab bar passport).
  static const double tabBarLensHeight = 54;

  /// The width of a tab bar without a bound: an iPhone's 402 points, less
  /// the bar's 21 at each side.
  static const double tabBarWidth = 360;

  static double height(GlassSelectorMotion kind) => switch (kind) {
    GlassSelectorMotion.segmented => segmentedHeight,
    GlassSelectorMotion.tabBar => tabBarHeight,
  };

  static double lensHeight(GlassSelectorMotion kind) => switch (kind) {
    GlassSelectorMotion.segmented => segmentedHeight - 2 * segmentedInset,
    GlassSelectorMotion.tabBar => tabBarLensHeight,
  };

  /// The width the items claim without a bound.
  static double natural(
    GlassSelectorMotion kind,
    List<double> items,
    List<double?>? fixed,
  ) {
    switch (kind) {
      case GlassSelectorMotion.segmented:
        var total = 0.0;
        for (var i = 0; i < items.length; i++) {
          total += _fixed(fixed, i) ?? _claim(items[i]);
        }
        return total;
      case GlassSelectorMotion.tabBar:
        return TabBarLayout.of(items, available: tabBarWidth).width;
    }
  }

  static double? _fixed(List<double?>? fixed, int i) =>
      fixed == null || i >= fixed.length ? null : fixed[i];

  static double _claim(double item) =>
      math.max(segmentedHeight, item + 2 * segmentedPadding);

  /// The widths of segments in a control [width] wide: a segment with a
  /// fixed width keeps it and the others share the rest, equally, or with
  /// `proportional` as UIKit apportions them, by what each claims (its item
  /// plus the padding a side, at least the height), each share rounded down
  /// to a point and the remainder left at the trailing end.
  static List<double> _segmentWidths(
    double width,
    List<double> items,
    List<double?>? fixed, {
    required bool proportional,
  }) {
    final count = items.length;
    var room = width;
    var free = 0;
    var claimed = 0.0;
    for (var i = 0; i < count; i++) {
      final set = _fixed(fixed, i);
      if (set != null) {
        room -= set;
      } else {
        free++;
        claimed += _claim(items[i]);
      }
    }
    return [
      for (var i = 0; i < count; i++)
        _fixed(fixed, i) ??
            (proportional
                ? (_claim(items[i]) * room / claimed).floorToDouble()
                : room / free),
    ];
  }
}

/// The motion of a selector: its lens, made at the first layout, its
/// items and bounds through changes of the items, the dimming of a pressed
/// segment and a tab bar's touch glow.
final class _SelectorMotion extends Motion {
  _SelectorMotion({
    required this.kind,
    required this._selected,
    required this.isSelectable,
    required this.onEvent,
  });

  final GlassSelectorMotion kind;
  final bool Function(int index) isSelectable;
  final void Function(LensEvent event) onEvent;

  late final highlight = own(SegmentHighlight());
  late final glow = own(TouchGlowMotion.tabBar());

  /// The items by key, and the control's bounds, in the selector's box
  /// moved by [_anchor].
  late final items = own(LayoutMotion());
  static final Object _bounds = Object();
  Offset _anchor = Offset.zero;
  LensMotion? _lens;
  int _selected;
  int? _remapped;
  List<LensSlot> _lenses = const [];

  /// The size of the control at its last layout.
  Size size = Size.zero;

  /// Where the control draws its track or bar at its last layout.
  Rect bar = Rect.zero;

  bool get tabBar => kind == GlassSelectorMotion.tabBar;

  LensMotion? get lens => _lens;

  int get selected => _remapped ?? _lens?.selected ?? _selected;

  bool get isDragging => _lens?.isDragging ?? false;

  int slotAt(double x) => _lens?.slotAt(x) ?? -1;

  /// Where [key] is drawn in the selector's box and its opacity, or null
  /// once it is gone.
  (Rect, double)? drawn(Object key) {
    if (!items.contains(key)) return null;
    final item = items.itemAt(key);
    return (item.rect.shift(-_anchor), item.opacity);
  }

  /// Where the bounds are drawn while they move to a new size, or null at
  /// rest.
  Rect? get movingBounds => items.contains(_bounds) && !items.itemRests(_bounds)
      ? items.itemAt(_bounds).rect.shift(-_anchor)
      : null;

  /// Selects [index] of the items laid out next, without travel: the
  /// selected item moved to it in a change of the items.
  void remap(int index) {
    _selected = index;
    _remapped = index;
  }

  /// Lays the items out at [rects] in the selector's box at time [t], on
  /// [spring] when it is not null; [shift] is how far the box moved in
  /// its parents in this layout, which the items and the lens keep their
  /// place on screen through.
  void layout(
    double t,
    _Geometry geometry,
    Map<Object, Rect> rects, {
    required Offset shift,
    required bool mirrored,
    Spring? spring,
  }) {
    final jump = spring?.isImmediate ?? false;
    final moves = jump ? null : spring;
    final before = size;
    _anchor += shift;
    items.layout(
      t,
      {
        for (final MapEntry(:key, :value) in rects.entries)
          key: value.shift(_anchor),
        _bounds: geometry.bar.shift(_anchor),
      },
      spring: moves,
      carry: spring == null,
      jump: jump,
    );
    final changed =
        !listEquals(geometry.lenses, _lenses) || geometry.size != size;
    size = geometry.size;
    bar = geometry.bar;
    _lenses = geometry.lenses;
    final remapped = _remapped;
    _remapped = null;
    final lens = _lens;
    if (lens == null) {
      final created = switch (kind) {
        GlassSelectorMotion.segmented => LensMotion.segmented(
          slots: geometry.lenses,
          selected: _selected,
          height: _Geometry.lensHeight(kind),
          frameRate: clock.frameRate,
          chromeSize: geometry.bar.size,
          onEvent: onEvent,
        ),
        GlassSelectorMotion.tabBar => LensMotion.tabBar(
          slots: geometry.lenses,
          selected: _selected,
          height: _Geometry.lensHeight(kind),
          frameRate: clock.frameRate,
          chromeSize: geometry.bar.size,
          onEvent: onEvent,
        ),
      };
      created.isSelectable = isSelectable;
      _lens = own(created);
    } else if (changed || remapped != null) {
      lens.reslot(
        t,
        geometry.lenses,
        remapped ?? lens.selected,
        spring: moves,
        shift: mirrored
            ? shift.dx + geometry.size.width - before.width
            : -shift.dx,
      );
      lens.chromeSize = geometry.bar.size;
    }
  }

  void choose(double t, int index, {bool notify = true}) {
    _selected = index;
    _remapped = null;
    _lens?.select(t, index, notify: notify);
  }

  void place(double t, int index) {
    _selected = index;
    _remapped = null;
    _lens?.place(t, index);
  }

  void down(double t, double x, Offset position, {required bool glows}) {
    final lens = _lens;
    if (lens == null) return;
    lens.pointerDown(t, x, y: position.dy);
    if (glows && tabBar) glow.pointerDown(t, position);
  }

  /// A finger that slid off a minimized bar's circle takes the lens.
  void drag(double t, double x, Offset position) {
    _lens?.pointerDrag(t, x, y: position.dy);
    if (tabBar) glow.pointerDown(t, position);
  }

  void move(double t, double x, Offset position) {
    _lens?.pointerMove(t, x, y: position.dy);
    if (tabBar) glow.pointerMove(t, position);
  }

  void up(double t, double x) {
    _lens?.pointerUp(t, x);
    _release(t);
  }

  void cancel(double t) {
    _lens?.pointerCancel(t);
    _release(t);
  }

  void _release(double t) {
    highlight.release(t);
    glow.pointerUp(t);
  }
}

/// What a selector shows of its motion, laid out left to right or
/// mirrored.
final class _SelectorFrames {
  _SelectorFrames(this._motion, {required this.mirrored, this.collapse});

  final _SelectorMotion _motion;
  final bool mirrored;

  /// What collapses the bar, when something does.
  final GlassSelectorCollapse? collapse;

  late final MotionSelection<GlassFrame> lens = collapse == null
      ? _lens
      : MotionSelection(() {
          final frame = _lens.value;
          final morph = collapse!.morph.value;
          if (morph <= 0) return frame;
          return frame.copyWith(opacity: lensOpacity(morph, frame.lift));
        });

  /// How much of the lens shows at [morph]: a lens a finger carries stays.
  static double lensOpacity(double morph, double lift) => math
      .max(
        1 - morph / TabBarMinimizeMotion.lensGoneAt,
        lift,
      )
      .clamp(0.0, 1.0);

  late final MotionSelection<GlassFrame> _lens = _motion.select((motion) {
    final lens = motion.lens;
    if (lens == null) return const GlassFrame();
    final size = lens.size;
    final width = motion.size.width;
    return GlassFrame(
      rect: Rect.fromCenter(
        center: Offset(
          mirrored ? width - lens.center : lens.center,
          motion.size.height / 2,
        ),
        width: size.width * lens.scaleX,
        height: size.height * lens.scaleY,
      ),
      lift: lens.lift.clamp(0.0, 1.0),
    );
  });

  late final MotionSelection<GlassFrame> body = collapse == null
      ? _body
      : MotionSelection(() {
          final frame = _body.value;
          final morph = collapse!.morph.value;
          if (morph == 0) return frame;
          final lifted = collapse!.press?.value ?? 0;
          final circle = collapse!
              .circleIn(_motion.size)
              .inflate(TabBarMinimizeMotion.pressGrowth * lifted);
          return frame.copyWith(rect: Rect.lerp(frame.rect, circle, morph));
        });

  late final MotionSelection<GlassFrame> _body = _motion.select(
    (motion) => GlassFrame(
      rect: motion.movingBounds ?? (collapse == null ? null : motion.bar),
      glow: motion.tabBar ? motion.glow.glow : null,
    ),
  );

  /// How many items the motion places, ghosts included.
  late final MotionSelection<int> placed = _motion.select(
    (motion) => motion.items.ids.length,
  );

  /// Where every item is drawn, ghosts included.
  late final MotionSelection<List<(Rect, double)?>> items = _motion.select(
    (motion) => [for (final id in motion.items.ids) motion.drawn(id)],
    equals: listEquals,
  );

  late final MotionSelection<(int?, double)> dim = _motion.select((motion) {
    final index = motion.highlight.index;
    return (index, index == null ? 1.0 : motion.highlight.opacity(index));
  });

  late final MotionSelection<Offset> drift = _motion.select((motion) {
    final chrome = motion.lens?.chrome ?? LensMotion.chromeAtRest;
    return Offset(mirrored ? -chrome.driftX : chrome.driftX, chrome.driftY);
  });

  late final MotionSelection<double> scaleX = _motion.select(
    (motion) => (motion.lens?.chrome ?? LensMotion.chromeAtRest).scaleX,
  );

  late final MotionSelection<double> scaleY = _motion.select(
    (motion) => (motion.lens?.chrome ?? LensMotion.chromeAtRest).scaleY,
  );
}

/// A selector's touch: the lens follows it from its first event, and it
/// takes the touch from the items once it moves, which holds it against a
/// scroll.
final class _SelectorInput extends Interaction {
  _SelectorInput(this._owner) : super(role: InteractionRole.control);

  final _RawGlassSelectorState _owner;
  int? _pointer;
  bool _claimed = false;

  bool get active => _pointer != null;

  @override
  bool get pressed => _pointer != null;

  @override
  bool get dragged => _pointer != null && _owner._motion.isDragging;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final update = _handle(input);
    _owner._writeTouch();
    return update;
  }

  InteractionUpdate _handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _claimed = false;
        _owner._down(input);
      case PointerMoveInput() when input.pointer == _pointer:
        _owner._move(input);
        if (!_claimed) {
          _claimed = true;
          return const InteractionUpdate(claims: true);
        }
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._up(input);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._cancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The items of a selector in their slots, each as three children, its
/// regular look and two copies of its selected look, which show inside the
/// lens, one under its glass and one over its resting platter, then the
/// items fading out, and the lens last when the look gives one; laying
/// them out publishes the slots to the selector's motion in the resolve
/// phase.
class _SelectorRow extends MultiChildRenderObjectWidget {
  const _SelectorRow({
    required this.motion,
    required this.frames,
    required this.kind,
    required this.keys,
    required this.ghosts,
    required this.itemWidths,
    required this.proportional,
    required this.collapse,
    required this.hosted,
    required this.showsLens,
    required this.hasLens,
    required this.lensShrink,
    required super.children,
  });

  final _SelectorMotion motion;
  final _SelectorFrames frames;
  final GlassSelectorMotion kind;
  final List<Object> keys;
  final List<Object> ghosts;
  final List<double?>? itemWidths;
  final bool proportional;
  final GlassSelectorCollapse? collapse;
  final bool hosted;
  final bool showsLens;

  /// Whether the last child is the lens.
  final bool hasLens;

  /// How the lens's glass shrinks what lies under it, fully lifted.
  final ValueListenable<GlassLensShrink> lensShrink;

  @override
  MultiChildRenderObjectElement createElement() => _SelectorRowElement(this);

  @override
  _RenderSelectorRow createRenderObject(BuildContext context) =>
      _RenderSelectorRow(
        motion: motion,
        frames: frames,
        kind: kind,
        keys: keys,
        ghosts: ghosts,
        itemWidths: itemWidths,
        proportional: proportional,
        collapse: collapse,
        hosted: hosted,
        showsLens: showsLens,
        hasLens: hasLens,
        lensShrink: lensShrink,
        direction: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectorRow renderObject,
  ) {
    renderObject.motion = motion;
    renderObject.frames = frames;
    renderObject.kind = kind;
    renderObject.keys = keys;
    renderObject.ghosts = ghosts;
    renderObject.itemWidths = itemWidths;
    renderObject.proportional = proportional;
    renderObject.collapse = collapse;
    renderObject.hosted = hosted;
    renderObject.showsLens = showsLens;
    renderObject.hasLens = hasLens;
    renderObject.lensShrink = lensShrink;
    renderObject.direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

// The selected copies are drawn only inside the lens; like an
// IndexedStack's hidden children, they are offstage to finders.
class _SelectorRowElement extends MultiChildRenderObjectElement {
  _SelectorRowElement(_SelectorRow super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final items = children.length - ((widget as _SelectorRow).hasLens ? 1 : 0);
    var i = 0;
    for (final child in children) {
      if (i >= items || i % 3 == 0) visitor(child);
      i++;
    }
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

/// How much a fully lifted tab bar lens grows the items it shows: the held
/// item shows at 1.218 of its resting size while the swollen bar carries
/// the others at 1.052, so the lens adds 1.158, rounded to 0.16 (NEAR)
/// (iPhone 16 Pro, tab bar passport). A segmented control's lens shows
/// its label in place (0.996).
const double _tabBarMagnification = 0.16;

class _RenderSelectorRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData>,
        MotionResolveHost {
  _RenderSelectorRow({
    required this._motion,
    required this._frames,
    required this._kind,
    required this._keys,
    required this._ghosts,
    required this._itemWidths,
    required this._proportional,
    required this._collapse,
    required this._hosted,
    required this._showsLens,
    required this._hasLens,
    required this._lensShrink,
    required this._direction,
  });

  _SelectorMotion _motion;
  _SelectorMotion get motion => _motion;
  set motion(_SelectorMotion value) {
    if (identical(value, _motion)) return;
    _motion = value;
    markNeedsLayout();
  }

  _SelectorFrames _frames;
  _SelectorFrames get frames => _frames;
  set frames(_SelectorFrames value) {
    if (identical(value, _frames)) return;
    if (attached) _unlisten();
    _frames = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  GlassSelectorMotion _kind;
  GlassSelectorMotion get kind => _kind;
  set kind(GlassSelectorMotion value) {
    if (value == _kind) return;
    _kind = value;
    markNeedsLayout();
  }

  List<Object> _keys;
  List<Object> get keys => _keys;
  set keys(List<Object> value) {
    if (listEquals(value, _keys)) return;
    _keys = value;
    markNeedsLayout();
  }

  List<Object> _ghosts;
  List<Object> get ghosts => _ghosts;
  set ghosts(List<Object> value) {
    if (listEquals(value, _ghosts)) return;
    _ghosts = value;
    markNeedsLayout();
  }

  List<double?>? _itemWidths;
  List<double?>? get itemWidths => _itemWidths;
  set itemWidths(List<double?>? value) {
    if (listEquals(value, _itemWidths)) return;
    _itemWidths = value;
    markNeedsLayout();
  }

  bool _proportional;
  bool get proportional => _proportional;
  set proportional(bool value) {
    if (value == _proportional) return;
    _proportional = value;
    markNeedsLayout();
  }

  GlassSelectorCollapse? _collapse;
  GlassSelectorCollapse? get collapse => _collapse;
  set collapse(GlassSelectorCollapse? value) {
    if (identical(value, _collapse)) return;
    if (attached) _unlistenCollapse();
    final spans = (value == null) != (_collapse == null);
    _collapse = value;
    if (attached) _listenCollapse();
    if (spans) markNeedsLayout();
    markNeedsPaint();
  }

  bool _hosted;
  bool get hosted => _hosted;
  set hosted(bool value) {
    if (value == _hosted) return;
    _hosted = value;
    markNeedsLayout();
  }

  bool _showsLens;
  bool get showsLens => _showsLens;
  set showsLens(bool value) {
    if (value == _showsLens) return;
    _showsLens = value;
    markNeedsPaint();
  }

  bool _hasLens;
  bool get hasLens => _hasLens;
  set hasLens(bool value) {
    if (value == _hasLens) return;
    _hasLens = value;
    markNeedsLayout();
  }

  ValueListenable<GlassLensShrink> _lensShrink;
  ValueListenable<GlassLensShrink> get lensShrink => _lensShrink;
  set lensShrink(ValueListenable<GlassLensShrink> value) {
    if (identical(value, _lensShrink)) return;
    if (attached) _lensShrink.removeListener(markNeedsPaint);
    _lensShrink = value;
    if (attached) _lensShrink.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  // The items move in the resolve phase, after this box's layout, so only a
  // render listener hears them in the frame they move; the lens and the
  // dimming publish before build.
  void _listen() {
    _frames.lens.addListener(markNeedsPaint);
    _frames.dim.addListener(markNeedsPaint);
    _frames.items.addRenderListener(markNeedsPaint);
  }

  void _unlisten() {
    _frames.lens.removeListener(markNeedsPaint);
    _frames.dim.removeListener(markNeedsPaint);
    _frames.items.removeRenderListener(markNeedsPaint);
  }

  void _listenCollapse() {
    _collapse?.morph.addListener(_collapsed);
    _collapse?.press?.addListener(markNeedsPaint);
  }

  void _unlistenCollapse() {
    _collapse?.morph.removeListener(_collapsed);
    _collapse?.press?.removeListener(markNeedsPaint);
  }

  void _collapsed() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
    _listenCollapse();
    _lensShrink.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _unlisten();
    _unlistenCollapse();
    _lensShrink.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  RenderBox? get _lens => _hasLens ? lastChild : null;

  /// The items of the selector, without those fading out.
  Iterable<(RenderBox, RenderBox, RenderBox)> get _live =>
      _items.take(_keys.length);

  /// Every item's regular look and its selected copies under and over the
  /// lens, in order, then those of the items fading out.
  Iterable<(RenderBox, RenderBox, RenderBox)> get _items sync* {
    final lens = _lens;
    var child = firstChild;
    while (child != null && child != lens) {
      final under = childAfter(child);
      final over = under == null ? null : childAfter(under);
      if (under == null || over == null || over == lens) return;
      yield (child, under, over);
      child = childAfter(over);
    }
  }

  // UIKit sizes a tab by its regular title, not its bolder selected one.
  List<double> _itemExtents(double height) => [
    for (final (regular, _, selected) in _live)
      if (_kind == GlassSelectorMotion.tabBar)
        regular.getMaxIntrinsicWidth(height)
      else
        math.max(
          regular.getMaxIntrinsicWidth(height),
          selected.getMaxIntrinsicWidth(height),
        ),
  ];

  double get _height => _Geometry.height(_kind);

  double _natural() =>
      _Geometry.natural(_kind, _itemExtents(_height), _itemWidths);

  @override
  double computeMinIntrinsicWidth(double height) => _natural();

  @override
  double computeMaxIntrinsicWidth(double height) => _natural();

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  _Geometry _geometry(BoxConstraints constraints) => _Geometry.of(
    _kind,
    constraints,
    _itemExtents(_height),
    fixed: _itemWidths,
    proportional: _proportional,
    spans: _collapse != null,
    hosted: _hosted,
  );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _geometry(constraints).size;

  Rect _shown(Rect slot) => _direction == TextDirection.rtl
      ? Rect.fromLTRB(
          size.width - slot.right,
          slot.top,
          size.width - slot.left,
          slot.bottom,
        )
      : slot;

  // The box's offset in its box ancestors, up to the first that is not a
  // box (a sliver under a scroll, which moves without a layout).
  Offset _origin() {
    var offset = Offset.zero;
    RenderObject node = this;
    while (node.parent is RenderBox) {
      if (node.parentData case final BoxParentData data) offset += data.offset;
      node = node.parent!;
    }
    return offset;
  }

  ({_Geometry geometry, Map<Object, Rect> rects, Offset origin})? _laidOut;

  @override
  void performLayout() {
    final geometry = _geometry(constraints);
    size = geometry.size;
    final rects = <Object, Rect>{};
    var i = 0;
    for (final (regular, under, over) in _items) {
      final Rect slot;
      if (i < _keys.length) {
        slot = _shown(geometry.slots[i]);
        rects[_keys[i]] = slot;
      } else {
        final ghost = _motion.items.laidOut(_ghosts[i - _keys.length]);
        slot = Offset.zero & (ghost?.size ?? Size.zero);
      }
      // A bar given no room lays its tabs out narrower than nothing.
      final room = Size(math.max(0, slot.width), math.max(0, slot.height));
      for (final child in [regular, under, over]) {
        child.layout(BoxConstraints.tight(room));
        (child.parentData! as _RowParentData).offset = slot.topLeft;
      }
      i++;
    }
    _lens?.layout(BoxConstraints.tight(size));
    // The parents place the box after this layout: the offset read now is
    // the one it was drawn at.
    _laidOut = (geometry: geometry, rects: rects, origin: _origin());
    scheduleResolve();
  }

  @override
  void resolve() {
    final laidOut = _laidOut;
    if (laidOut == null) return;
    _laidOut = null;
    _motion.layout(
      _motion.clock.now,
      laidOut.geometry,
      laidOut.rects,
      shift: _origin() - laidOut.origin,
      mirrored: _direction == TextDirection.rtl,
      spring: layoutSpring,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final (item, _, _) in _live) {
      final hit = result.addWithPaintOffset(
        offset: (item.parentData! as _RowParentData).offset,
        position: position,
        hitTest: (result, local) => item.hitTest(result, position: local),
      );
      if (hit) return true;
    }
    return false;
  }

  // How far the selected glyph has travelled toward the circle from the tab
  // it stands on in [slot].
  Offset _glyphTravel(Rect slot, double morph) {
    final circle = _collapse!.circleIn(size);
    return (circle.center -
            Offset(slot.center.dx, TabBarMinimizeMotion.glyphCenter)) *
        morph;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final morph = _collapse?.morph.value ?? 0;
    if (morph != 0) {
      final selected = _motion.selected;
      var i = 0;
      for (final (regular, _, above) in _live) {
        if (i == selected && identical(child, above)) {
          final travel = _glyphTravel(
            (regular.parentData! as _RowParentData).offset & regular.size,
            morph,
          );
          transform.translateByDouble(travel.dx, travel.dy, 0, 1);
        }
        i++;
      }
    }
    super.applyPaintTransform(child, transform);
  }

  // UIKit draws the regular items under the lens, cut out where it sits,
  // and a selected copy of every item masked by the lens (tab bar
  // passport); the lifted lens's glass bends the copy and, at its rim, the
  // items around it.
  @override
  void paint(PaintingContext context, Offset offset) {
    final collapse = _collapse;
    final morph = collapse?.morph.value ?? 0;
    final frame = _frames.lens.value;
    final rect = frame.drawnIn(size);
    final mask = _showsLens
        ? RSuperellipse.fromRectAndRadius(
            rect,
            Radius.circular(frame.shape.radiusIn(rect)),
          )
        : null;
    final cutter = morph == 0 ? mask : null;
    final (dimmed, opacity) = _frames.dim.value;
    final slots = <Rect>[];
    var i = 0;
    for (final (regular, _, _) in _items) {
      final live = i < _keys.length;
      final drawn = _motion.drawn(
        live ? _keys[i] : _ghosts[i - _keys.length],
      );
      final laid = (regular.parentData! as _RowParentData).offset;
      final slot = Rect.fromCenter(
        center: drawn?.$1.center ?? (laid & regular.size).center,
        width: regular.size.width,
        height: regular.size.height,
      );
      if (live) slots.add(slot);
      if (!live && drawn == null) {
        i++;
        continue;
      }
      void paintRegular(PaintingContext context, Offset offset) {
        if (cutter == null || !cutter.outerRect.overlaps(slot)) {
          context.paintChild(regular, offset + slot.topLeft);
          return;
        }
        // The slot outside the lens, without a path operation each frame:
        // even-odd leaves the slot less the lens and the lens past the slot,
        // which the slot's rect clips away.
        final cut = Path();
        cut.fillType = PathFillType.evenOdd;
        cut.addRect(slot);
        cut.addRSuperellipse(cutter);
        context.pushClipRect(
          needsCompositing,
          offset,
          slot,
          (context, offset) => context.pushClipPath(
            needsCompositing,
            offset,
            slot,
            cut,
            (context, offset) =>
                context.paintChild(regular, offset + slot.topLeft),
          ),
        );
      }

      final alpha = (drawn?.$2 ?? 1) * (i == dimmed ? opacity : 1);
      if (morph != 0) {
        // Drawn together below, where they dissolve as one.
      } else if (alpha < 1) {
        context.pushOpacity(
          offset,
          Color.getAlphaFromOpacity(alpha.clamp(0.0, 1.0)),
          paintRegular,
        );
      } else {
        paintRegular(context, offset);
      }
      i++;
    }
    if (morph != 0) _paintDissolving(context, offset, slots, morph);
    final copies = frame.opacity;
    final lift = frame.lift.clamp(0.0, 1.0);
    final glass = mask == null ? 0.0 : GlassFrame.glassnessAt(lift);
    final zoom = _kind == GlassSelectorMotion.tabBar
        ? 1 + _tabBarMagnification * lift
        : 1.0;
    if (mask != null && glass > 0 && copies > 0) {
      final (:shrink, :rim) = _lensShrink.value;
      _paintCopies(
        context,
        offset,
        mask,
        slots,
        opacity: glass * copies,
        under: true,
        zoom: zoom,
        grow: 1 + (1 / (1 - shrink * lift) - 1) * glass,
        rim: rim,
      );
    }
    final lens = _lens;
    if (lens != null) context.paintChild(lens, offset);
    if (mask != null && glass < 1 && copies > 0) {
      _paintCopies(
        context,
        offset,
        mask,
        slots,
        opacity: (1 - glass) * copies,
        under: false,
        zoom: zoom,
        grow: 1,
        rim: 0,
      );
    }
    if (morph != 0) _paintGlyph(context, offset, slots, morph, lift);
  }

  // The tabs, the selected one's regular look among them, stay about where
  // they are inside the shrinking glass and dissolve as one.
  void _paintDissolving(
    PaintingContext context,
    Offset offset,
    List<Rect> slots,
    double morph,
  ) {
    final left = 1 - morph / TabBarMinimizeMotion.othersGoneAt;
    if (left <= 0) return;
    final body = _frames.body.value.drawnIn(size);
    final toward = _collapse!.circleIn(size).center.dx;
    final together = 1 - TabBarMinimizeMotion.othersDrift * morph;
    void items(PaintingContext context, Offset offset) {
      var i = 0;
      for (final (regular, _, _) in _live) {
        final slot = slots[i++];
        final x = toward + (slot.center.dx - toward) * together;
        context.paintChild(
          regular,
          offset + Offset(x - slot.width / 2, slot.top),
        );
      }
    }

    void dissolved(PaintingContext context, Offset offset) {
      final sigma = TabBarMinimizeMotion.othersBlur * morph.clamp(0.0, 1.0);
      if (sigma <= 0) return items(context, offset);
      context.pushLayer(
        ImageFilterLayer(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        ),
        items,
        offset,
      );
    }

    context.pushClipRSuperellipse(
      true,
      offset,
      body,
      RSuperellipse.fromRectAndRadius(
        body,
        Radius.circular(body.shortestSide / 2),
      ),
      (context, offset) => context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(left.clamp(0.0, 1.0)),
        dissolved,
      ),
    );
  }

  // The selected glyph travels to the circle and stands in it, lifted with
  // it under a finger. Once a finger carries the lens, the lens shows the
  // selected look, and this copy goes as it lands.
  void _paintGlyph(
    PaintingContext context,
    Offset offset,
    List<Rect> slots,
    double morph,
    double lift,
  ) {
    final selected = _motion.selected;
    if (!_showsLens || selected < 0 || selected >= slots.length) return;
    final slot = slots[selected];
    final (_, _, above) = _live.elementAt(selected);
    final travel = _glyphTravel(slot, morph);
    final scale =
        1 +
        (_collapse!.press?.value ?? 0) *
            TabBarMinimizeMotion.pressGrowth *
            2 /
            TabBarMinimizeMotion.collapsedSize;
    final center =
        Offset(slot.center.dx, TabBarMinimizeMotion.glyphCenter) + travel;
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.scaleByDouble(scale, scale, 1, 1);
    transform.translateByDouble(
      -center.dx + travel.dx,
      -center.dy + travel.dy,
      0,
      1,
    );
    void glyph(PaintingContext context, Offset offset) => context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => context.paintChild(above, offset + slot.topLeft),
    );
    final shows =
        1 -
        lift * (1 - morph / TabBarMinimizeMotion.lensGoneAt).clamp(0.0, 1.0);
    if (shows >= 1) return glyph(context, offset);
    context.pushOpacity(offset, Color.getAlphaFromOpacity(shows), glyph);
  }

  // The copy under the glass shows through it as the lifted lens takes
  // over from its platter, the one over the platter fading as it goes.
  //
  // The glass reads what lies under it [grow] times farther from the
  // nearest point of its center line (half of it is `axis`, from the lens
  // center) than it shows it: across the line beside it, radially about
  // each end beyond it. So the copy under it is grown the same way first,
  // each part exact in its own strip, and through the glass every item
  // shows on its slot while only the lens slides over it, as in UIKit.
  // Each item is magnified about its own slot by [zoom].
  void _paintCopies(
    PaintingContext context,
    Offset offset,
    RSuperellipse mask,
    List<Rect> slots, {
    required double opacity,
    required bool under,
    required double zoom,
    required double grow,
    required double rim,
  }) {
    final bounds = mask.outerRect;
    final center = bounds.center;
    final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
    final alongX = bounds.width >= bounds.height;
    final axis = grow == 1
        ? Offset.zero
        : alongX
        ? Offset(half, 0)
        : Offset(0, half);
    final start = center - axis;
    final end = center + axis;
    final strips = axis == Offset.zero
        ? [(bounds, center, grow, grow)]
        : [
            (
              alongX
                  ? Rect.fromLTRB(
                      bounds.left,
                      bounds.top,
                      start.dx,
                      bounds.bottom,
                    )
                  : Rect.fromLTRB(
                      bounds.left,
                      bounds.top,
                      bounds.right,
                      start.dy,
                    ),
              start,
              grow,
              grow,
            ),
            (
              alongX
                  ? Rect.fromLTRB(start.dx, bounds.top, end.dx, bounds.bottom)
                  : Rect.fromLTRB(bounds.left, start.dy, bounds.right, end.dy),
              center,
              alongX ? 1.0 : grow,
              alongX ? grow : 1.0,
            ),
            (
              alongX
                  ? Rect.fromLTRB(
                      end.dx,
                      bounds.top,
                      bounds.right,
                      bounds.bottom,
                    )
                  : Rect.fromLTRB(
                      bounds.left,
                      end.dy,
                      bounds.right,
                      bounds.bottom,
                    ),
              end,
              grow,
              grow,
            ),
          ];
    void paintMasked(PaintingContext context, Offset offset) =>
        context.pushClipRSuperellipse(needsCompositing, offset, bounds, mask, (
          context,
          offset,
        ) {
          for (final (strip, anchor, growX, growY) in strips) {
            if (strip.isEmpty) continue;
            context.pushClipRect(needsCompositing, offset, strip, (
              context,
              offset,
            ) {
              var i = 0;
              for (final (_, below, above) in _live) {
                final copy = under ? below : above;
                final slot = slots[i++];
                final transform = _copyTransform(
                  slot.center,
                  zoom,
                  anchor,
                  growX,
                  growY,
                );
                if (!MatrixUtils.transformRect(
                  transform,
                  slot,
                ).overlaps(strip)) {
                  continue;
                }
                context.pushTransform(
                  needsCompositing,
                  offset,
                  transform,
                  (context, offset) =>
                      context.paintChild(copy, offset + slot.topLeft),
                );
              }
            });
          }
        });
    if (opacity >= 1) {
      paintMasked(context, offset);
    } else {
      context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(opacity),
        paintMasked,
      );
    }
  }

  // An item grows about its own slot by [zoom], so it stays put while the
  // lens window slides over it, then by ([growX], [growY]) about [anchor].
  static Matrix4 _copyTransform(
    Offset slot,
    double zoom,
    Offset anchor,
    double growX,
    double growY,
  ) {
    final transform = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    transform.scaleByDouble(growX, growY, 1, 1);
    transform.translateByDouble(
      slot.dx - anchor.dx,
      slot.dy - anchor.dy,
      0,
      1,
    );
    transform.scaleByDouble(zoom, zoom, 1, 1);
    transform.translateByDouble(-slot.dx, -slot.dy, 0, 1);
    return transform;
  }
}

/// The selector's box: its semantics node, and where it takes touches,
/// inside [frame]'s body (a bar under a collapse spans its group, and what
/// is beside the bar or the circle stays free) and, for the 44 point
/// target the region below grows, past its own size.
class _SelectorBox extends SingleChildRenderObjectWidget {
  const _SelectorBox({
    required this.frame,
    required this.label,
    required super.child,
  });

  final ValueListenable<GlassFrame>? frame;
  final String? label;

  @override
  _RenderSelectorBox createRenderObject(BuildContext context) =>
      _RenderSelectorBox(
        frame: frame,
        label: label,
        direction: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectorBox renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.label = label;
    renderObject.direction = Directionality.maybeOf(context);
  }
}

class _RenderSelectorBox extends RenderProxyBox {
  _RenderSelectorBox({
    required this.frame,
    required this._label,
    required this._direction,
  });

  ValueListenable<GlassFrame>? frame;

  String? _label;
  String? get label => _label;
  set label(String? value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection? _direction;
  TextDirection? get direction => _direction;
  set direction(TextDirection? value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsSemanticsUpdate();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final rect = frame?.value.rect;
    if (rect != null && !rect.contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
    if (_label case final label?) {
      config.label = label;
      config.textDirection = _direction;
    }
  }
}
