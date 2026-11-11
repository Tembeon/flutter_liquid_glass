import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_values.dart';
import 'package:apple_liquid_glass/src/motions/segment_highlight.dart';
import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured UIKit control whose motion and geometry a selector takes.
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

/// The geometry a selector lays its items out in.
@immutable
final class SelectorGeometry {
  const SelectorGeometry({
    required this.size,
    required this.slots,
    required this.lenses,
    this.drawn,
  });

  factory SelectorGeometry.of(
    GlassSelectorMotion kind,
    double maxWidth,
    Size Function(Size) constrain,
    List<double> items, {
    required List<double?>? fixed,
    required bool proportional,
    required bool spans,
    required bool hosted,
  }) {
    final h = height(kind);
    switch (kind) {
      case GlassSelectorMotion.segmented:
        final width = maxWidth < double.infinity
            ? maxWidth
            : natural(kind, items, fixed);
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
        return SelectorGeometry(size: size, slots: slots, lenses: lenses);
      case GlassSelectorMotion.tabBar:
        final box = maxWidth < double.infinity ? maxWidth : tabBarWidth;
        final bar = TabBarLayout.of(
          items,
          available: box < TabBarLayout.phoneBelow ? box : tabBarWidth,
          hosted: hosted,
        );
        final size = constrain(Size(spans ? box : bar.width, h));
        final left = (size.width - bar.width) / 2;
        return SelectorGeometry(
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

  /// Where a tab bar under a `GlassSelectorCollapse` draws in its box,
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
final class SelectorMotion extends Motion {
  SelectorMotion({
    required this.kind,
    required int selected,
    required this.isSelectable,
    required this.onEvent,
  }) : _pending = selected;

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

  // The selection the next layout gives the lens: the one it is made at,
  // or the selected item's index among items that changed. Null once the
  // lens holds it.
  int? _pending;
  List<LensSlot> _lenses = const [];

  /// The size of the control at its last layout.
  Size size = Size.zero;

  /// Where the control draws its track or bar at its last layout.
  Rect bar = Rect.zero;

  bool get tabBar => kind == GlassSelectorMotion.tabBar;

  LensMotion? get lens => _lens;

  /// The item the selector shows selected.
  int get selected => _pending ?? _lens!.selected;

  /// Selects an item of those laid out next, without travel: where the
  /// selected item went in a change of the items.
  set selected(int index) => _pending = index;

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

  /// Lays the items out at [rects] in the selector's box at time [t], on
  /// [spring] when it is not null; [shift] is how far the box moved in
  /// its parents in this layout, which the items and the lens keep their
  /// place on screen through.
  void layout(
    double t,
    SelectorGeometry geometry,
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
        !_sameSlots(geometry.lenses, _lenses) || geometry.size != size;
    size = geometry.size;
    bar = geometry.bar;
    _lenses = geometry.lenses;
    final pending = _pending;
    _pending = null;
    final lens = _lens;
    if (lens == null) {
      final created = switch (kind) {
        GlassSelectorMotion.segmented => LensMotion.segmented(
          slots: geometry.lenses,
          selected: pending!,
          height: SelectorGeometry.lensHeight(kind),
          frameRate: clock.frameRate,
          chromeSize: geometry.bar.size,
          onEvent: onEvent,
        ),
        GlassSelectorMotion.tabBar => LensMotion.tabBar(
          slots: geometry.lenses,
          selected: pending!,
          height: SelectorGeometry.lensHeight(kind),
          frameRate: clock.frameRate,
          chromeSize: geometry.bar.size,
          onEvent: onEvent,
        ),
      };
      created.isSelectable = isSelectable;
      _lens = own(created);
    } else if (changed || pending != null) {
      lens.reslot(
        t,
        geometry.lenses,
        pending ?? lens.selected,
        spring: moves,
        shift: mirrored
            ? shift.dx + geometry.size.width - before.width
            : -shift.dx,
      );
      lens.chromeSize = geometry.bar.size;
    }
  }

  void choose(double t, int index, {bool notify = true}) {
    final lens = _lens;
    if (lens == null) {
      _pending = index;
      return;
    }
    _pending = null;
    lens.select(t, index, notify: notify);
  }

  void place(double t, int index) {
    final lens = _lens;
    if (lens == null) {
      _pending = index;
      return;
    }
    _pending = null;
    lens.place(t, index);
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

bool _sameSlots(List<LensSlot> a, List<LensSlot> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
