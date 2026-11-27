import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:apple_liquid_glass/src/motions/lens_values.dart';
import 'package:apple_liquid_glass/src/motions/segment_highlight.dart';
import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';

/// The measured UIKit control whose motion and geometry a selector takes.
enum GlassSelectorMotion {
  /// `UISegmentedControl`: a track 32 points tall with a lens inset 2
  /// points in it. A touch dims the label of a segment that is not
  /// selected, a drag lifts the lens into glass and carries it, and a
  /// release outside 70 points of the control selects nothing.
  segmented,

  /// `UITabBar`: a bar 62 points tall with a lens 54 points tall, or 44
  /// and 36 where it lays out wide ([TabBarMetrics]). The bar swells and
  /// drifts under the finger and a glow follows it, and inside the lens
  /// every item shows its selected look.
  tabBar,
}

/// The measured layout of a selector's row: its size, where each item's slot
/// lies, where the lens rests at each item and where the track or bar is
/// drawn, for a [GlassSelectorMotion] in the room it is given.
@immutable
final class SelectorGeometry {
  /// A layout of [size] with the given [slots], resting [lenses] [lensHeight]
  /// tall and, for a bar that does not fill its box, the [drawn] rect.
  @internal
  const SelectorGeometry({
    required this.size,
    required this.slots,
    required this.lenses,
    required this.lensHeight,
    this.drawn,
  });

  /// Lays out items of the given natural widths for [kind] in a box at most
  /// [maxWidth] wide (infinity when unbounded), whose size is [constrain] of
  /// the size the control asks for.
  ///
  /// A [fixed] width keeps a segment at that width; with [proportional] the
  /// rest of a segmented control is shared by what each item claims. With
  /// [spans] a tab bar's box fills [maxWidth] while the bar draws in it,
  /// centered unless [host] stands it at the leading side, and [host] lays
  /// the bar out as a host of other chrome, by [tabBarMetrics].
  @internal
  factory SelectorGeometry.of(
    GlassSelectorMotion kind,
    double maxWidth,
    Size Function(Size) constrain,
    List<double> items, {
    required List<double?>? fixed,
    required bool proportional,
    required bool spans,
    required TabBarHost host,
    required TabBarMetrics tabBarMetrics,
  }) {
    final h = height(kind, tabBarMetrics);
    switch (kind) {
      case GlassSelectorMotion.segmented:
        final width = maxWidth < double.infinity
            ? maxWidth
            : natural(kind, items, fixed, tabBarMetrics);
        final size = constrain(Size(width, h));
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
        return SelectorGeometry(
          size: size,
          slots: slots,
          lenses: lenses,
          lensHeight: segmentedHeight - 2 * segmentedInset,
        );
      case GlassSelectorMotion.tabBar:
        final box = maxWidth < double.infinity
            ? maxWidth
            : tabBarMetrics.unboundWidth;
        final bar = TabBarLayout.of(
          items,
          available: box,
          host: host,
          metrics: tabBarMetrics,
        );
        final size = constrain(Size(spans ? box : bar.width, h));
        final left = host == TabBarHost.circle
            ? 0.0
            : (size.width - bar.width) / 2;
        return SelectorGeometry(
          size: size,
          lensHeight: tabBarMetrics.buttonHeight,
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

  /// The size of the control's box.
  final Size size;

  /// Where a tab bar under a `GlassSelectorCollapse` draws in its box,
  /// which spans the whole group.
  final Rect? drawn;

  /// Where the control draws its track or bar in its box.
  Rect get bar => drawn ?? Offset.zero & size;

  /// Each item's box, left to right.
  final List<Rect> slots;

  /// Each item's resting lens along the track, left to right.
  final List<LensSlot> lenses;

  /// The height of the resting lens.
  final double lensHeight;

  /// The height of a segmented control.
  static const double segmentedHeight = 32;

  /// The gap between a segmented track and its resting lens.
  static const double segmentedInset = 2;

  /// The padding on each side of a segment's item when segments size by
  /// content: UIKit pads a label by 9 points a side (read from UIKit, notes
  /// private), and with Flutter's label widths the device's content rows
  /// fit 9.13 - 9.18.
  static const double segmentedPadding = 9.15;

  /// The height of the control for [kind], a tab bar's by [tabBarMetrics].
  @internal
  static double height(
    GlassSelectorMotion kind,
    TabBarMetrics tabBarMetrics,
  ) => switch (kind) {
    GlassSelectorMotion.segmented => segmentedHeight,
    GlassSelectorMotion.tabBar => tabBarMetrics.height,
  };

  /// The width the items claim without a bound.
  @internal
  static double natural(
    GlassSelectorMotion kind,
    List<double> items,
    List<double?>? fixed,
    TabBarMetrics tabBarMetrics,
  ) {
    switch (kind) {
      case GlassSelectorMotion.segmented:
        var total = 0.0;
        for (var i = 0; i < items.length; i++) {
          total += _fixed(fixed, i) ?? _claim(items[i]);
        }
        return total;
      case GlassSelectorMotion.tabBar:
        return TabBarLayout.of(
          items,
          available: tabBarMetrics.unboundWidth,
          metrics: tabBarMetrics,
        ).width;
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
final class SelectorMotion extends Motion {
  /// A motion for [kind], with [selected] chosen at its first layout.
  /// [isSelectable] says whether an item can take the selection and
  /// [onEvent] hears what the lens decides.
  @internal
  SelectorMotion({
    required this.kind,
    required int selected,
    required this.isSelectable,
    required this.onEvent,
    super.clock,
  }) : _pending = selected;

  /// The measured control this motion follows.
  final GlassSelectorMotion kind;

  /// Whether the item at an index can be selected.
  final bool Function(int index) isSelectable;

  /// Hears the lens's events: a selection, a lift, a cancelled touch.
  final void Function(LensEvent event) onEvent;

  /// The dimming of a pressed segment.
  late final highlight = own(SegmentHighlight());

  /// The glow a finger raises on a tab bar.
  late final glow = own(TouchGlowMotion.tabBar());

  /// The items by key, and the control's bounds, in the selector's box
  /// moved by the anchor.
  late final items = own(LayoutMotion());
  static final Object _bounds = Object();
  Offset _anchor = Offset.zero;
  LensMotion? _lens;

  // The selection the next layout gives the lens: the one it is made at,
  // or the selected item's index among items that changed. Null once the
  // lens holds it.
  int? _pending;
  List<LensSlot> _lenses = const [];

  /// The size of the control at its last layout.
  Size size = Size.zero;

  /// Where the control draws its track or bar at its last layout.
  Rect bar = Rect.zero;

  /// Whether [kind] is the tab bar.
  bool get tabBar => kind == GlassSelectorMotion.tabBar;

  /// The selection lens, or null before the first layout.
  LensMotion? get lens => _lens;

  /// How much a tab bar's lens shows: it fades out over 0.25 s, easing in
  /// and out, when the selection leaves the bar for its prominent tab, and
  /// back when it returns, as UIKit fades its lens (a CA animation, iOS
  /// 27.2 simulator).
  double get lensShown => _lensShown.valueAt(now).clamp(0.0, 1.0);
  late final _lensShown = own(MotionValue<double>(1));
  static const _lensFade = TimingCurve(0.25);

  /// The lens shows or goes at time [t]: over [_lensFade] when [animated].
  void showLens(double t, {required bool shown, required bool animated}) {
    advance(t);
    final target = shown ? 1.0 : 0.0;
    if (_lensShown.target == target) return;
    if (animated) {
      _lensShown.animate(t, target, animation: _lensFade);
    } else {
      _lensShown.snap(t, target);
    }
  }

  /// The item the selector shows selected.
  int get selected => _pending ?? _lens!.selected;

  /// Selects an item of those laid out next, without travel: where the
  /// selected item went in a change of the items.
  set selected(int index) => _pending = index;

  /// Whether a finger is carrying the lens.
  bool get isDragging => _lens?.isDragging ?? false;

  /// The slot under [x] along the track, or -1 before the first layout.
  int slotAt(double x) => _lens?.slotAt(x) ?? -1;

  /// Where [key] is drawn in the selector's box and its opacity, or null
  /// once it is gone.
  (Rect, double)? drawn(Object key) {
    if (!items.contains(key)) return null;
    final item = items.itemAt(key);
    return (item.rect.shift(-_anchor), item.pose.opacity);
  }

  /// Where the bounds are drawn while they move to a new size, or null at
  /// rest.
  Rect? get movingBounds => items.contains(_bounds) && !items.itemRests(_bounds)
      ? items.itemAt(_bounds).rect.shift(-_anchor)
      : null;

  /// Lays the items out at [rects] in the selector's box at time [t], on
  /// [spring] when it is not null; [shift] is how far the box moved in
  /// its parents in this layout, which the items and the lens keep their
  /// place on screen through.
  @internal
  void layout(
    double t,
    SelectorGeometry geometry,
    Map<Object, Rect> rects, {
    required Offset shift,
    required bool mirrored,
    Spring? spring,
  }) {
    final before = size;
    _anchor += shift;
    items.planner = tabBar
        ? _TabChangePlanner(_bounds, mirrored: mirrored)
        : _SegmentChangePlanner(_bounds, mirrored: mirrored);
    final change = items.layout(
      t,
      {
        for (final MapEntry(:key, :value) in rects.entries)
          key: value.shift(_anchor),
        _bounds: geometry.bar.shift(_anchor),
      },
      spring: spring,
    );
    final changed =
        !listEquals(geometry.lenses, _lenses) ||
        geometry.size != size ||
        geometry.lensHeight != _lens?.height;
    if (tabBar && geometry.bar.size != bar.size) {
      glow.flex = FlexSpec.forSize(geometry.bar.size);
    }
    size = geometry.size;
    bar = geometry.bar;
    _lenses = geometry.lenses;
    final pending = _pending;
    _pending = null;
    final lens = _lens;
    if (lens == null) {
      final created = LensMotion(
        tuning: switch (kind) {
          GlassSelectorMotion.segmented => LensTuning.segmented,
          GlassSelectorMotion.tabBar => LensTuning.tabBar,
        },
        slots: geometry.lenses,
        selected: pending!,
        height: geometry.lensHeight,
        chromeSize: geometry.bar.size,
        onEvent: onEvent,
      );
      created.isSelectable = isSelectable;
      _lens = own(created);
    } else if (changed || pending != null) {
      lens.height = geometry.lensHeight;
      lens.reslot(
        t,
        geometry.lenses,
        pending ?? lens.selected,
        animation: switch (change?.spring) {
          null => spring,
          _ when tabBar => _TabChangePlanner.slots,
          _ when _SegmentChangePlanner.inserts(change!) =>
            _SegmentChangePlanner.curve,
          _ => spring,
        },
        shift: mirrored
            ? shift.dx + geometry.size.width - before.width
            : -shift.dx,
      );
      lens.chromeSize = geometry.bar.size;
    }
  }

  /// Selects the item at [index] with travel at [t]; [notify] says whether the
  /// app hears it.
  @internal
  void choose(double t, int index, {bool notify = true}) {
    final lens = _lens;
    if (lens == null) {
      _pending = index;
      return;
    }
    _pending = null;
    lens.select(t, index, notify: notify);
  }

  /// Puts the lens at [index] at [t] without travel.
  @internal
  void place(double t, int index) {
    final lens = _lens;
    if (lens == null) {
      _pending = index;
      return;
    }
    _pending = null;
    lens.place(t, index);
  }

  /// A finger went down at [x] along the track, at [position] in the box;
  /// [glows] lets a tab bar raise its glow.
  @internal
  void down(double t, double x, Offset position, {required bool glows}) {
    final lens = _lens;
    if (lens == null) return;
    lens.pointerDown(t, x, y: position.dy);
    if (glows && tabBar) glow.pointerDown(t, position);
  }

  /// A finger that slid off a minimized bar's circle takes the lens.
  @internal
  void drag(double t, double x, Offset position) {
    _lens?.pointerDrag(t, x, y: position.dy);
    if (tabBar) glow.pointerDown(t, position);
  }

  /// The finger moved to [x] along the track, at [position] in the box.
  @internal
  void move(double t, double x, Offset position) {
    _lens?.pointerMove(t, x, y: position.dy);
    if (tabBar) glow.pointerMove(t, position);
  }

  /// The finger lifted at [x] along the track.
  @internal
  void up(double t, double x) {
    _lens?.pointerUp(t, x);
    _release(t);
  }

  /// The touch was taken away.
  @internal
  void cancel(double t) {
    _lens?.pointerCancel(t);
    _release(t);
  }

  void _release(double t) {
    highlight.release(t);
    glow.pointerUp(t);
  }
}

/// A segmented control's insert or remove as UIKit's
/// `insertSegment(...animated:)` and `removeSegment(at:animated:)` run it:
/// one UIView animation of 0.25 s, easing in and out, moves every segment,
/// the lens and the labels; a new segment starts at its predecessor's
/// trailing edge at its own width and fades in; a removed one fades out
/// while it slides its center onto the new trailing edge of the segment
/// before it, the first one half its width less 5 toward the leading side
/// (UIKit's code and CA animations, iOS 27.2 simulator). Any other change
/// moves on the change's spring; a change outside a transaction jumps.
final class _SegmentChangePlanner extends LayoutPlanner {
  const _SegmentChangePlanner(this._bounds, {required this.mirrored});

  final Object _bounds;

  /// Whether the segments run right to left.
  final bool mirrored;

  static const curve = TimingCurve(0.25);
  static const _firstInset = 5.0;
  static const _fade = MotionPose(opacity: 0);

  /// Whether [change] inserts or removes a segment.
  static bool inserts(LayoutChange change) =>
      change.entries.values.any((entry) => entry is! LayoutStaying);

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) {
    final spring = change.spring;
    if (spring == null || !inserts(change)) {
      return {
        for (final key in change.entries.keys) key: LayoutPlan(spring: spring),
      };
    }
    final kept = [
      for (final MapEntry(:key, :value) in change.entries.entries)
        if (key != _bounds)
          if (value case LayoutStaying(:final from, :final to)) (from, to),
    ];
    double order(Rect rect) => mirrored ? -rect.center.dx : rect.center.dx;
    double trailing(Rect rect) => mirrored ? rect.left : rect.right;
    (Rect, Rect)? previous(Rect rect, Rect Function((Rect, Rect)) side) {
      (Rect, Rect)? best;
      for (final segment in kept) {
        if (order(side(segment)) < order(rect) &&
            (best == null || order(side(segment)) > order(side(best)))) {
          best = segment;
        }
      }
      return best;
    }

    final bounds = switch (change.entries[_bounds]) {
      LayoutStaying(:final from) => from,
      _ => null,
    };
    Rect enter(Rect to) {
      final edge = switch (previous(to, (segment) => segment.$2)) {
        (final from, _) => trailing(from),
        null => mirrored ? bounds?.right ?? to.right : bounds?.left ?? to.left,
      };
      return Rect.fromLTWH(
        mirrored ? edge - to.width : edge,
        to.top,
        to.width,
        to.height,
      );
    }

    Rect leave(Rect from) {
      final center = switch (previous(from, (segment) => segment.$1)) {
        (_, final to) => trailing(to),
        null => mirrored ? from.right - _firstInset : from.left + _firstInset,
      };
      return Rect.fromCenter(
        center: Offset(center, from.center.dy),
        width: from.width,
        height: from.height,
      );
    }

    return {
      for (final MapEntry(:key, :value) in change.entries.entries)
        key: switch (value) {
          LayoutStaying() => const LayoutPlan(curve: curve),
          LayoutEntering(:final to) => LayoutPlan(
            curve: curve,
            origin: enter(to),
            absent: _fade,
          ),
          LayoutLeaving(:final from) => LayoutPlan(
            curve: curve,
            destination: leave(from),
            absent: _fade,
          ),
        },
    };
  }
}

/// A tab bar's change of tabs as UIKit's `setTabs(_:animated:)` runs it:
/// the platter and every tab move on a critically damped 0.3 s spring; a
/// new tab grows out of where the tab before it stood and fades in on the
/// same progress; a removed tab fades out on a critically damped 0.2 s
/// spring while it moves onto the place of the tab after it (fitted to
/// UIKit's live layers, iOS 27.2 simulator: 2e-6 and 1e-5 rms). A change
/// outside a transaction jumps.
final class _TabChangePlanner extends LayoutPlanner {
  const _TabChangePlanner(this._bounds, {required this.mirrored});

  final Object _bounds;

  /// Whether the tabs run right to left.
  final bool mirrored;

  static const slots = Spring.response(0.3);
  static const _leave = Spring.response(0.2);
  static const _fade = MotionPose(opacity: 0);

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) {
    if (change.spring == null) {
      return {for (final key in change.entries.keys) key: const LayoutPlan()};
    }
    final kept = [
      for (final MapEntry(:key, :value) in change.entries.entries)
        if (key != _bounds)
          if (value case LayoutStaying(:final from, :final to)) (from, to),
    ];
    double order(Rect rect) => mirrored ? -rect.center.dx : rect.center.dx;
    // Where the tab that now stands before [to] stood.
    Rect? before(Rect to) {
      (Rect, Rect)? best;
      for (final tab in kept) {
        if (order(tab.$2) < order(to) &&
            (best == null || order(tab.$2) > order(best.$2))) {
          best = tab;
        }
      }
      return best?.$1;
    }

    // Where the tab that stood after [from] now stands.
    Rect? after(Rect from) {
      (Rect, Rect)? best;
      for (final tab in kept) {
        if (order(tab.$1) > order(from) &&
            (best == null || order(tab.$1) < order(best.$1))) {
          best = tab;
        }
      }
      return best?.$2;
    }

    return {
      for (final MapEntry(:key, :value) in change.entries.entries)
        key: switch (value) {
          _ when key == _bounds => const LayoutPlan(spring: slots),
          LayoutStaying() => const LayoutPlan(spring: slots),
          LayoutEntering(:final to) => LayoutPlan(
            spring: slots,
            origin: before(to),
            absent: _fade,
          ),
          LayoutLeaving(:final from) => LayoutPlan(
            spring: _leave,
            springs: const RectSprings.all(slots),
            destination: after(from),
            absent: _fade,
          ),
        },
    };
  }
}
