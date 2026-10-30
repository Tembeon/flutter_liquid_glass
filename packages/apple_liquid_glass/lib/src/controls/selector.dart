import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/lens_motion.dart';
import 'package:apple_liquid_glass/src/motion/segment_highlight.dart';
import 'package:apple_liquid_glass/src/motion/touch_glow.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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

/// Builds the item at [index] of a [RawGlassSelector] for [states]: the
/// item's own states, which include [WidgetState.selected] for the selected
/// item, [WidgetState.pressed] for the item under a touch and
/// [WidgetState.hovered] for the item under the mouse.
///
/// Every item is built twice: without [WidgetState.selected] for the row
/// under the lens, and with it for the copy the lens shows wherever it is,
/// as UIKit masks a selected copy of every tab by the lens.
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
  });

  /// The frames of the track or bar, which fills the selector: the glow a
  /// finger raises on a tab bar.
  final ValueListenable<GlassFrame> body;

  /// The frames of the lens in the selector's box: where it sits, how it
  /// stretches, and how far a finger has lifted it into glass.
  final ValueListenable<GlassFrame> lens;

  final Widget Function(Widget? lens) _items;

  /// The items laid out in their slots, with [lens] filling the selector
  /// between their regular look and their selected look, which shows only
  /// inside the lens: as in UIKit, the lifted lens bends the items under
  /// its rim. The builder places this once, over the body: it gives the
  /// selector its size.
  Widget items({Widget? lens}) => _items(lens);

  /// The selected item, or null when none is and the lens is hidden.
  final int? selectedIndex;

  /// The states the selector is in.
  final Set<WidgetState> states;
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
/// motion rebuilds neither builder; [itemBuilder] runs again when the
/// pressed or hovered item changes. The arrow keys move the selection,
/// skipping [disabledItems]; Space and Enter, like a tap on the selected
/// item, report [onReselected]. In a right-to-left context the items run
/// from the right.
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
    this.itemWidths,
    this.proportionalWidth = false,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// The number of items.
  final int itemCount;

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

  /// How far outside a segmented control a finger may lift and still
  /// select: a release beyond it changes nothing, and the lens settles back
  /// as after a cancelled touch.
  ///
  /// UISegmentedControl selects on a release 60 points below its bottom
  /// edge but not 70 (iPhone 16 Pro, iOS 27.0.1; the capture is not among
  /// this package's fixtures). 70 with the bottom and right edges
  /// excluded, the way `CGRectContainsPoint` tests a point, also gives the
  /// glass button's measured edges.
  static const double segmentedReleaseSlop = 70;

  @override
  State<RawGlassSelector> createState() => _RawGlassSelectorState();
}

class _RawGlassSelectorState extends State<RawGlassSelector> {
  late final _SelectorBody _body = _SelectorBody(
    _deliver,
    kind: widget.motion,
    selected: widget.selectedIndex ?? 0,
  );
  late final _SelectorInput _input = _SelectorInput(this);
  late final List<Interaction> _interactions = [_input];
  WidgetStatesController? _ownStates;
  bool _reconcilePending = false;
  bool _rtl = false;
  // The items under a touch and under the mouse: changing them builds the
  // items, not the look.
  final _pointing = ValueNotifier<({int? pressed, int? hovered})>((
    pressed: null,
    hovered: null,
  ));
  int? _noneDown;
  int? _downSlot;
  int? _downSelected;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

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

  @override
  void initState() {
    super.initState();
    _body.isSelectable = _selectable;
    _writeStates();
    _states.addListener(_statesChanged);
    MotionClock.instance.addDriver(_body);
  }

  @override
  void didUpdateWidget(RawGlassSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
    _body.kind = widget.motion;
    _sync(oldWidget.selectedIndex == null);
    final pressed = _pointing.value.pressed;
    if (pressed != null && !_selectable(pressed)) {
      _pointing.value = (pressed: null, hovered: _pointing.value.hovered);
    }
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownStates?.dispose();
    _pointing.dispose();
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  // The region writes disabled too, and ends a touch when disabled;
  // writing both first makes its writes no-ops, so it never asks this
  // ancestor to rebuild while it builds.
  void _writeStates() {
    final disabled = !_enabled;
    _states.update(WidgetState.disabled, disabled);
    if (disabled) {
      _states.update(WidgetState.pressed, false);
      _states.update(WidgetState.dragged, false);
    }
  }

  void _statesChanged() => setState(() {});

  void _sync(bool wasNone) {
    final selected = _selected;
    if (selected == null) return;
    if (wasNone) {
      _body.place(selected);
    } else if (_body.selected != selected) {
      _body.select(selected, notify: false);
    }
  }

  // Callbacks may rebuild ancestors: a cancel from the region's own update
  // or dispose arrives while the framework builds or finalizes the tree,
  // so they wait for the end of the frame there.
  void _later(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });
      return;
    }
    callback();
  }

  void _deliver(LensEvent event) => _later(() {
    switch (event) {
      case LensSelected(:final index):
        _chosen(index);
    }
  });

  void _chosen(int index) {
    if (index != widget.selectedIndex) widget.onChanged?.call(index);
    _reconcileLater();
  }

  // One pending check, re-armed while a touch leads the lens.
  void _reconcileLater() {
    if (_reconcilePending) return;
    _reconcilePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reconcilePending = false;
      if (!mounted) return;
      if (_input.active) {
        _reconcileLater();
        return;
      }
      final selected = _selected;
      if (selected != null && _body.selected != selected) {
        _body.select(selected, notify: false);
      }
    });
  }

  void _select(int index) {
    if (!_selectable(index)) return;
    final selected = _selected;
    if (selected == null) {
      _body.place(index);
      _chosen(index);
    } else if (index == selected) {
      widget.onReselected?.call(index);
    } else {
      _body.select(index);
    }
  }

  void _step(int delta) {
    final count = widget.itemCount;
    if (count == 0) return;
    final direction = _rtl ? -delta : delta;
    final selected = _selected;
    var next = selected == null
        ? (direction > 0 ? 0 : count - 1)
        : selected + direction;
    while (next >= 0 && next < count && !_selectable(next)) {
      next += direction;
    }
    if (next >= 0 && next < count && next != selected) _select(next);
  }

  void _reselect() {
    final selected = _selected;
    if (selected != null && _selectable(selected)) {
      widget.onReselected?.call(selected);
    }
  }

  double _x(Offset position) =>
      _rtl ? _body.size.width - position.dx : position.dx;

  bool _within(Offset position) {
    if (!_segmented) return true;
    return (Offset.zero & _body.size)
        .inflate(RawGlassSelector.segmentedReleaseSlop)
        .contains(position);
  }

  void _setPreview(Offset? position) {
    int? next;
    if (position != null && _within(position)) {
      final slot = _body.slotAt(_x(position));
      if (_selectable(slot)) next = slot;
    }
    if (next == _pointing.value.pressed) return;
    _later(
      () => _pointing.value = (pressed: next, hovered: _pointing.value.hovered),
    );
  }

  void _hover(Offset? position) {
    final next = position == null ? null : _body.slotAt(_x(position));
    if (next == _pointing.value.hovered) return;
    _later(
      () => _pointing.value = (pressed: _pointing.value.pressed, hovered: next),
    );
  }

  void _down(PointerDownInput input) {
    final x = _x(input.position);
    _setPreview(input.position);
    final slot = _body.slotAt(x);
    final selected = _selected;
    if (_segmented && _selectable(slot) && slot != selected) {
      _body.press(input.time, slot);
    }
    if (selected == null) {
      _noneDown = slot;
      return;
    }
    _downSlot = slot;
    _downSelected = _body.selected;
    _body.down(input.time, x, input.position, glows: _selectable(slot));
  }

  void _move(PointerMoveInput input) {
    _setPreview(input.position);
    if (_noneDown != null) return;
    _body.move(input.time, _x(input.position), input.position);
  }

  void _up(PointerUpInput input) {
    _setPreview(null);
    final x = _x(input.position);
    final slot = _body.slotAt(x);
    final before = _downSelected;
    final down = _downSlot;
    _downSlot = null;
    _downSelected = null;
    if (_noneDown != null) {
      _noneDown = null;
      _body.cancel(input.time);
      if (_within(input.position)) _select(slot);
      return;
    }
    if (!_within(input.position)) {
      _body.cancel(input.time);
      return;
    }
    _body.up(input.time, x);
    final reselected =
        before != null &&
        slot == before &&
        _body.selected == before &&
        (_segmented || down == before);
    if (reselected && _selectable(before)) {
      _later(() => widget.onReselected?.call(before));
    }
  }

  void _cancel(double time) {
    _setPreview(null);
    _noneDown = null;
    _downSlot = null;
    _downSelected = null;
    _body.cancel(time);
  }

  Set<WidgetState> _itemStates(int index, {required bool selected}) => {
    if (selected) WidgetState.selected,
    if (!_selectable(index)) WidgetState.disabled,
    if (_pointing.value.pressed == index) WidgetState.pressed,
    if (_pointing.value.hovered == index) WidgetState.hovered,
    if (selected && _states.value.contains(WidgetState.focused))
      WidgetState.focused,
  };

  Widget _item(BuildContext context, int index) {
    final selected = index == _selected;
    final enabled = _selectable(index);
    return Semantics(
      container: true,
      button: _segmented,
      inMutuallyExclusiveGroup: _segmented,
      role: _segmented ? null : SemanticsRole.tab,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? () => _select(index) : null,
      child: Center(
        child: widget.itemBuilder(
          context,
          index,
          _itemStates(index, selected: false),
        ),
      ),
    );
  }

  Widget _items(BuildContext context, Widget? lens) {
    final count = widget.itemCount;
    return ValueListenableBuilder(
      valueListenable: _pointing,
      builder: (context, _, _) {
        final row = _SelectorRow(
          body: _body,
          kind: widget.motion,
          itemWidths: widget.itemWidths,
          proportional: widget.proportionalWidth,
          showsLens: _selected != null,
          hasLens: lens != null,
          children: [
            for (var i = 0; i < count; i++) ...[
              RepaintBoundary(child: _item(context, i)),
              ExcludeSemantics(
                child: RepaintBoundary(
                  child: Center(
                    child: widget.itemBuilder(
                      context,
                      i,
                      _itemStates(i, selected: true),
                    ),
                  ),
                ),
              ),
            ],
            ?lens,
          ],
        );
        if (_segmented) return row;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          role: SemanticsRole.tabBar,
          child: row,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion = GlassTraits.of(context).reduceMotion;
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _body.mirrored = _rtl;
    final look = widget.builder(
      context,
      GlassSelectorDetails(
        body: _body.body,
        lens: _body.lens,
        items: (lens) => _items(context, lens),
        selectedIndex: _selected,
        states: {..._states.value},
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.enter): _reselect,
        const SingleActivator(LogicalKeyboardKey.space): _reselect,
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: InputRegion(
          interactions: _interactions,
          enabled: _enabled && widget.itemCount > 0,
          statesController: _states,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          semanticLabel: widget.semanticLabel,
          child: _segmented
              ? look
              : MotionTransition(
                  offset: _body.drift,
                  scaleX: _body.scaleX,
                  scaleY: _body.scaleY,
                  child: look,
                ),
        ),
      ),
    );
  }
}

/// The geometry a selector lays its items out in.
@immutable
final class _Geometry {
  const _Geometry({
    required this.size,
    required this.slots,
    required this.lenses,
  });

  factory _Geometry.of(
    GlassSelectorMotion kind,
    BoxConstraints constraints,
    List<double> items, {
    required List<double?>? fixed,
    required bool proportional,
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
        final bar = _tabBar(items, room: constraints.maxWidth);
        final size = constraints.constrain(Size(bar.width, h));
        return _Geometry(
          size: size,
          slots: [
            for (var i = 0; i < items.length; i++)
              Rect.fromLTWH(
                tabBarSideInset + bar.pitch * i,
                0,
                bar.pitch,
                size.height,
              ),
          ],
          lenses: [
            for (var i = 0; i < items.length; i++)
              (
                center: tabBarSideInset + bar.pitch * (i + 0.5),
                width: bar.lens,
              ),
          ],
        );
    }
  }

  final Size size;

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

  /// The inset of a tab bar's items from its sides (tab bar passport).
  static const double tabBarSideInset = 8;

  /// The room a tab bar's item keeps on each side before the bar widens
  /// for it (tab bar passport).
  static const double tabBarItemPadding = 12;

  /// The slot pitch of a tab bar of [count] tabs (tab bar passport).
  static double tabBarPitch(int count) => count <= 4 ? 86 : 68;

  /// The resting lens width of a tab bar of [count] tabs (tab bar
  /// passport).
  static double tabBarLensWidth(int count) => switch (count) {
    <= 3 => 94,
    4 => 98,
    _ => 77,
  };

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
        return _tabBar(items).width;
    }
  }

  static double? _fixed(List<double?>? fixed, int i) =>
      fixed == null || i >= fixed.length ? null : fixed[i];

  static double _claim(double item) =>
      math.max(segmentedHeight, item + 2 * segmentedPadding);

  /// The slots of a tab bar of [items]: the measured pitch, widened for a
  /// wide item and narrowed to fit [room], as UIKit narrows the tabs beside
  /// a search tab.
  static ({double pitch, double lens, double width}) _tabBar(
    List<double> items, {
    double room = double.infinity,
  }) {
    final count = items.length;
    final measured = tabBarPitch(count);
    final widest = items.fold<double>(0, math.max);
    final pitch = math.min(
      math.max(measured, widest + 2 * tabBarItemPadding),
      count == 0 ? double.infinity : (room - 2 * tabBarSideInset) / count,
    );
    return (
      pitch: pitch,
      lens: tabBarLensWidth(count) + pitch - measured,
      width: pitch * count + 2 * tabBarSideInset,
    );
  }

  /// The widths of segments in a control [width] wide. Sized by content,
  /// as UIKit apportions them: a segment with a fixed width keeps it, and
  /// the others share the rest by what each claims, its item plus the
  /// padding a side and at least the height, every share rounded down to a
  /// point; the remainder stays at the trailing end.
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

/// The motion of a selector, stepped on the motion clock and published as
/// the frames of its body and lens.
final class _SelectorBody implements MotionDriver {
  _SelectorBody(
    this._deliver, {
    required this._kind,
    required this._selected,
  });

  final void Function(LensEvent event) _deliver;

  GlassSelectorMotion get kind => _kind;
  GlassSelectorMotion _kind;
  set kind(GlassSelectorMotion value) {
    if (value == _kind) return;
    _kind = value;
    _motion = null;
    _lenses = const [];
  }

  final body = ValueNotifier(const GlassFrame());
  final lens = ValueNotifier(const GlassFrame());
  final dim = ValueNotifier<(int?, double)>((null, 1));
  final drift = ValueNotifier(Offset.zero);
  final scaleX = ValueNotifier<double>(1);
  final scaleY = ValueNotifier<double>(1);
  late bool Function(int index) isSelectable;
  bool reducedMotion = false;
  bool mirrored = false;

  LensMotion? _motion;
  int _selected;
  List<LensSlot> _lenses = const [];
  Size size = Size.zero;
  final SegmentHighlight _highlight = SegmentHighlight();
  final TouchGlowMotion _glow = _tabBarGlow();

  static TouchGlowMotion _tabBarGlow() {
    // The glow's peaks are the flex spec of the measured 274 point bar
    // (tab bar passport).
    final spec = FlexSpec.forSize(const Size(274, _Geometry.tabBarHeight));
    return TouchGlowMotion(
      washPeak: spec.bigGlowOpacity,
      spotPeak: spec.littleGlowOpacity,
      diameter: TouchGlowMotion.tabBarDiameter,
      riseLag: TouchGlowMotion.tabBarRiseLag,
    );
  }

  int get selected => _motion?.selected ?? _selected;

  bool get isDragging => _motion?.isDragging ?? false;

  int slotAt(double x) => _motion?.slotAt(x) ?? -1;

  double get _now => MotionClock.instance.now;

  void layout(_Geometry geometry) {
    final changed =
        !listEquals(geometry.lenses, _lenses) || geometry.size != size;
    size = geometry.size;
    _lenses = geometry.lenses;
    final motion = _motion;
    if (motion == null) {
      final created = LensMotion(
        tuning: kind == GlassSelectorMotion.segmented
            ? LensTuning.segmented
            : LensTuning.tabBar,
        slots: geometry.lenses,
        selected: _selected,
        height: _Geometry.lensHeight(kind),
        frameRate: MotionClock.instance.frameRate,
        chromeSize: geometry.size,
      );
      created.isSelectable = isSelectable;
      _motion = created;
    } else if (changed) {
      motion.slots = geometry.lenses;
      motion.chromeSize = geometry.size;
    }
    _publish();
  }

  void select(int index, {bool notify = true}) {
    _selected = index;
    final motion = _motion;
    if (motion == null) return;
    motion.reducedMotion = reducedMotion;
    motion.select(_now, index, notify: notify);
    _drain();
    _wake();
  }

  void place(int index) {
    _selected = index;
    _motion?.place(_now, index);
    _publish();
    _wake();
  }

  void press(double t, int slot) {
    _highlight.press(t, slot);
    _publish();
    _wake();
  }

  void down(double t, double x, Offset position, {required bool glows}) {
    final motion = _motion;
    if (motion == null) return;
    motion.reducedMotion = reducedMotion;
    motion.pointerDown(t, x, y: position.dy);
    if (glows && kind == GlassSelectorMotion.tabBar) {
      _glow.pointerDown(t, position);
    }
    _drain();
    _wake();
  }

  void move(double t, double x, Offset position) {
    _motion?.pointerMove(t, x, y: position.dy);
    if (kind == GlassSelectorMotion.tabBar) _glow.pointerMove(t, position);
    _drain();
    _wake();
  }

  void up(double t, double x) {
    _motion?.pointerUp(t, x);
    _release(t);
  }

  void cancel(double t) {
    _motion?.pointerCancel(t);
    _release(t);
  }

  void _release(double t) {
    _highlight.release(t);
    _glow.pointerUp(t);
    _drain();
    _wake();
  }

  @override
  bool get isActive {
    final motion = _motion;
    final t = _now;
    return (motion != null && !motion.isSettled) ||
        !_highlight.isSettled(t) ||
        !_glow.isSettled(t);
  }

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    final motion = _motion;
    if (motion != null) {
      motion.advance(time);
      if (motion.isSettled) motion.settle();
    }
    _highlight.advance(time);
    _glow.advance(time);
    _publish();
    _drain();
  }

  void _publish() {
    final motion = _motion;
    if (motion == null) return;
    final lensSize = motion.size;
    final center = mirrored ? size.width - motion.center : motion.center;
    lens.value = GlassFrame(
      rect: Rect.fromCenter(
        center: Offset(center, size.height / 2),
        width: lensSize.width * motion.scaleX,
        height: lensSize.height * motion.scaleY,
      ),
      lift: motion.lift.clamp(0.0, 1.0),
    );
    final t = motion.time;
    final index = _highlight.index;
    dim.value = (index, index == null ? 1.0 : _highlight.opacity(t, index));
    if (kind == GlassSelectorMotion.tabBar) {
      body.value = GlassFrame(glow: _glow.glowAt(t));
      final chrome = motion.chrome;
      scaleX.value = chrome.scaleX;
      scaleY.value = chrome.scaleY;
      drift.value = Offset(
        mirrored ? -chrome.driftX : chrome.driftX,
        chrome.driftY,
      );
    }
  }

  void _drain() {
    final motion = _motion;
    if (motion == null) return;
    for (final event in motion.drainEvents()) {
      _deliver(event);
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  void dispose() {
    body.dispose();
    lens.dispose();
    dim.dispose();
    drift.dispose();
    scaleX.dispose();
    scaleY.dispose();
  }
}

/// A selector's touch, which it holds against a scroll.
final class _SelectorInput extends Interaction {
  _SelectorInput(this._owner) : super(role: InteractionRole.control);

  final _RawGlassSelectorState _owner;
  int? _pointer;

  bool get active => _pointer != null;

  @override
  bool get pressed => _pointer != null;

  @override
  bool get dragged => _pointer != null && _owner._body.isDragging;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _owner._down(input);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        _owner._move(input);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._up(input);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._cancel(input.time);
        return const InteractionUpdate(fails: true);
      case PointerHoverInput(:final position, :final inside):
        _owner._hover(inside ? position : null);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The items of a selector in their slots, each as two children, its
/// regular look and its selected look, which shows inside the lens, and the
/// lens last when the look gives one; laying them out publishes the slots
/// to the selector's motion.
class _SelectorRow extends MultiChildRenderObjectWidget {
  const _SelectorRow({
    required this.body,
    required this.kind,
    required this.itemWidths,
    required this.proportional,
    required this.showsLens,
    required this.hasLens,
    required super.children,
  });

  final _SelectorBody body;
  final GlassSelectorMotion kind;
  final List<double?>? itemWidths;
  final bool proportional;
  final bool showsLens;

  /// Whether the last child is the lens.
  final bool hasLens;

  @override
  MultiChildRenderObjectElement createElement() => _SelectorRowElement(this);

  @override
  _RenderSelectorRow createRenderObject(BuildContext context) =>
      _RenderSelectorRow(
        body: body,
        kind: kind,
        itemWidths: itemWidths,
        proportional: proportional,
        showsLens: showsLens,
        hasLens: hasLens,
        direction: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectorRow renderObject,
  ) {
    renderObject.body = body;
    renderObject.kind = kind;
    renderObject.itemWidths = itemWidths;
    renderObject.proportional = proportional;
    renderObject.showsLens = showsLens;
    renderObject.hasLens = hasLens;
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
      if (i >= items || i.isEven) visitor(child);
      i++;
    }
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

/// How much a fully lifted tab bar lens grows the items it shows: the held
/// item shows at 1.218 of its resting size while the swollen bar carries
/// the others at 1.052, so the lens adds 1.158 (iPhone 16 Pro, tab bar
/// passport). A segmented control's lens shows its label in place (0.996).
const double _tabBarMagnification = 0.16;

class _RenderSelectorRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderSelectorRow({
    required this._body,
    required this._kind,
    required this._itemWidths,
    required this._proportional,
    required this._showsLens,
    required this._hasLens,
    required this._direction,
  });

  _SelectorBody _body;
  _SelectorBody get body => _body;
  set body(_SelectorBody value) {
    if (identical(value, _body)) return;
    if (attached) _unlisten();
    _body = value;
    if (attached) _listen();
    markNeedsLayout();
  }

  GlassSelectorMotion _kind;
  GlassSelectorMotion get kind => _kind;
  set kind(GlassSelectorMotion value) {
    if (value == _kind) return;
    _kind = value;
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

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  // The lens masks the selected looks; the dimming fades a segment's item.
  void _listen() {
    _body.lens.addListener(markNeedsPaint);
    _body.dim.addListener(markNeedsPaint);
  }

  void _unlisten() {
    _body.lens.removeListener(markNeedsPaint);
    _body.dim.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  RenderBox? get _lens => _hasLens ? lastChild : null;

  /// Every item's regular and selected look, in order.
  Iterable<(RenderBox, RenderBox)> get _pairs sync* {
    final lens = _lens;
    var child = firstChild;
    while (child != null && child != lens) {
      final selected = childAfter(child);
      if (selected == null || selected == lens) return;
      yield (child, selected);
      child = childAfter(selected);
    }
  }

  List<double> _itemExtents(double height) => [
    for (final (regular, selected) in _pairs)
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

  @override
  void performLayout() {
    final geometry = _geometry(constraints);
    size = geometry.size;
    var i = 0;
    for (final (regular, selected) in _pairs) {
      final slot = _shown(geometry.slots[i]);
      for (final child in [regular, selected]) {
        child.layout(BoxConstraints.tight(slot.size));
        (child.parentData! as _RowParentData).offset = slot.topLeft;
      }
      i++;
    }
    _lens?.layout(BoxConstraints.tight(size));
    _body.layout(geometry);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final (item, _) in _pairs) {
      final hit = result.addWithPaintOffset(
        offset: (item.parentData! as _RowParentData).offset,
        position: position,
        hitTest: (result, local) => item.hitTest(result, position: local),
      );
      if (hit) return true;
    }
    return false;
  }

  // UIKit draws the regular items under the lens, cut out where it sits,
  // and a selected copy of every item masked by the lens over it (tab bar
  // passport), so the lifted lens's rim bends the items around it.
  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _body.lens.value;
    final rect = frame.drawnIn(size);
    final mask = _showsLens
        ? RRect.fromRectAndRadius(
            rect,
            Radius.circular(math.min(rect.width, rect.height) / 2),
          )
        : null;
    final (dimmed, opacity) = _body.dim.value;
    var i = 0;
    for (final (regular, _) in _pairs) {
      final slot =
          (regular.parentData! as _RowParentData).offset & regular.size;
      void paintRegular(PaintingContext context, Offset offset) {
        if (mask == null || !mask.outerRect.overlaps(slot)) {
          context.paintChild(regular, offset + slot.topLeft);
          return;
        }
        final box = Path();
        box.addRect(slot);
        final cut = Path();
        cut.addRRect(mask);
        context.pushClipPath(
          needsCompositing,
          offset,
          slot,
          Path.combine(PathOperation.difference, box, cut),
          (context, offset) =>
              context.paintChild(regular, offset + slot.topLeft),
        );
      }

      if (i == dimmed && opacity < 1) {
        context.pushOpacity(
          offset,
          Color.getAlphaFromOpacity(opacity),
          paintRegular,
        );
      } else {
        paintRegular(context, offset);
      }
      i++;
    }
    final lens = _lens;
    if (lens != null) context.paintChild(lens, offset);
    if (mask == null) return;
    final zoom = _kind == GlassSelectorMotion.tabBar
        ? 1 + _tabBarMagnification * frame.lift.clamp(0.0, 1.0)
        : 1.0;
    for (final (_, selected) in _pairs) {
      final slot =
          (selected.parentData! as _RowParentData).offset & selected.size;
      if (!mask.outerRect.overlaps(slot)) continue;
      void paintSelected(PaintingContext context, Offset offset) =>
          context.paintChild(selected, offset + slot.topLeft);
      context.pushClipRRect(
        needsCompositing,
        offset,
        mask.outerRect,
        mask,
        zoom == 1
            ? paintSelected
            : (context, offset) => context.pushTransform(
                needsCompositing,
                offset,
                _scaleAbout(slot.center, zoom),
                paintSelected,
              ),
      );
    }
  }

  // An item grows about its own slot, so it stays put while the lens
  // window slides over it, as in UIKit.
  static Matrix4 _scaleAbout(Offset center, double scale) {
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.scaleByDouble(scale, scale, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final (item, _) in _pairs) {
      visitor(item);
    }
  }
}
