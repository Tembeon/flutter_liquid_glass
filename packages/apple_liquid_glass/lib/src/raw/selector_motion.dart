part of 'selector.dart';

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
