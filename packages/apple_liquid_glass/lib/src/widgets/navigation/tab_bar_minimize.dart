part of 'tab_bar.dart';

/// What a minimizing bar reads of its motion: the hint scale, the morph to
/// the circle, the accessory's two axes and whether the bar is minimized;
/// and the collapse it gives the bar below it.
final class _MinimizeFrames implements GlassSelectorCollapse {
  _MinimizeFrames(this.motion);

  final TabBarMinimizeMotion motion;
  late final hint = motion.select((m) => m.hint);
  @override
  late final morph = motion.select((m) => m.morph);
  @override
  late final press = motion.select((m) => m.press);
  late final accessoryX = motion.select((m) => m.accessoryX);
  late final accessoryY = motion.select((m) => m.accessoryY);
  late final accessoryShown = motion.select((m) => m.accessoryShown);
  late final accessoryGone = motion.select((m) => m.accessoryGone);
  late final minimized = motion.select((m) => m.minimized);

  /// Whether the group runs right to left, which puts the circle at its
  /// right.
  bool rtl = false;

  /// The record the bar lays out by.
  TabBarMetrics metrics = TabBarMetrics.compact;

  /// Whether the bar hosts an accessory, which bounds a wide group.
  bool hosted = false;

  @override
  Rect circleIn(Size size) =>
      _circleIn(_groupIn(size, metrics, hosted: hosted), metrics, rtl: rtl);

  @override
  bool get takesFinger => motion.minimized;

  @override
  void pressDown(double t, double x) => motion.pressDown(t, x);

  @override
  bool pressMove(double t, double x) => motion.pressMove(t, x);

  @override
  void pressUp(double t) => motion.pressUp(t);

  @override
  void pressCancel(double t) => motion.pressCancel(t);

  @override
  void activate() => motion.setMinimized(motion.clock.now, minimized: false);
}

/// The bar group in a box of [size]: the box, or for a [hosted] bar whose
/// [metrics] bound its group, that bound at the middle. A wide bar that
/// hosts nothing minimizes to the box's leading end however wide its tabs,
/// as UIKit's layout record says its collapsed item follows the bar's
/// widest layout; only the hosted group is measured.
Rect _groupIn(Size size, TabBarMetrics metrics, {required bool hosted}) {
  final limit = hosted ? metrics.hostedMaximum : null;
  final width = limit == null ? size.width : math.min(size.width, limit);
  return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
}

/// The minimized bar's circle in [group]: 48 points, 7 inside its leading
/// and bottom edges, so 28 from a phone's side and bottom as the measured
/// search tab circle; a wide bar's 44, flush (tab bar minimize passport).
Rect _circleIn(Rect group, TabBarMetrics metrics, {required bool rtl}) {
  final inset = metrics.minimizedInset;
  final diameter = metrics.minimizedSize;
  return Rect.fromLTWH(
    rtl ? group.right - inset - diameter : group.left + inset,
    group.bottom - inset - diameter,
    diameter,
    diameter,
  );
}

/// A tab bar that minimizes into a circle as the followed content scrolls,
/// with its bottom accessory and search tab under the same motion.
class _MinimizingBar extends StatefulWidget {
  const _MinimizingBar({
    required this.behavior,
    required this.accessory,
    required this.search,
    required this.metrics,
    required this.look,
    required this.bar,
  });

  final GlassTabBarMinimizeBehavior behavior;
  final Widget? accessory;
  final GlassSearchController? search;
  final TabBarMetrics metrics;
  final GlassTabBarStyle look;
  final _BarBuilder bar;

  @override
  State<_MinimizingBar> createState() => _MinimizingBarState();
}

class _MinimizingBarState extends State<_MinimizingBar> {
  late final _MinimizeFrames _body = _MinimizeFrames(
    TabBarMinimizeMotion(
      behavior: widget.behavior,
      clock: MotionClockScope.of(context),
    ),
  );

  double get _now => _body.motion.clock.now;
  ValueNotifier<MotionScroll?>? _active;
  MotionScroll? _scroll;
  MotionSelection<Object?>? _scrolling;
  MotionScrollPhase _phase = MotionScrollPhase.idle;

  // The accessory the app took away, kept while it dematerializes.
  Widget? _leaving;

  @override
  void initState() {
    super.initState();
    widget.search?.addListener(_searched);
  }

  bool _hearsAccessory = false;

  void _accessoryGone() {
    if (!_body.accessoryGone.value || _leaving == null || !mounted) return;
    setState(() => _leaving = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hearsAccessory) {
      _hearsAccessory = true;
      _body.accessoryGone.addListener(_accessoryGone);
      if (widget.accessory == null) {
        _body.motion.showAccessory(_now, shown: false, animated: false);
      }
    }
    _body.motion.crossFades = GlassTraits.of(context).prefersCrossFade;
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(_MinimizingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final had = oldWidget.accessory;
    final has = widget.accessory;
    if ((had == null) != (has == null)) {
      _leaving = has == null ? had : null;
      _body.motion.showAccessory(_now, shown: has != null, animated: true);
    }
    if (oldWidget.behavior != widget.behavior) {
      _body.motion.setBehavior(_now, widget.behavior);
    }
    if (!identical(oldWidget.search, widget.search)) {
      oldWidget.search?.removeListener(_searched);
      widget.search?.addListener(_searched);
    }
  }

  @override
  void dispose() {
    _body.accessoryGone.removeListener(_accessoryGone);
    widget.search?.removeListener(_searched);
    _active?.removeListener(_follow);
    _scrolling?.removeRenderListener(_scrolled);
    super.dispose();
  }

  bool get _searching => widget.search?.isOpen ?? false;

  // An open search takes the bar from the scroll: the scroll-away starts
  // over from where the bar stands.
  void _searched() {
    if (_searching) {
      _body.motion.scrollAway.reset(_body.motion.minimized ? 1 : 0);
    }
  }

  void _follow() {
    final next = _active?.value;
    if (identical(next, _scroll)) return;
    _scrolling?.removeRenderListener(_scrolled);
    _scroll = next;
    _phase = MotionScrollPhase.idle;
    final scrolling = _scrolling = next?.select((s) => (s.phase, s.metrics));
    scrolling?.addRenderListener(_scrolled);
  }

  void _scrolled() {
    final scroll = _scroll;
    final metrics = scroll?.metrics;
    if (scroll == null || metrics == null || !metrics.hasContentDimensions) {
      return;
    }
    final away = _body.motion.scrollAway;
    final phase = scroll.phase;
    final previous = _phase;
    _phase = phase;
    final offset = metrics.pixels;
    final min = metrics.minScrollExtent;
    final max = metrics.maxScrollExtent;
    if (!_body.motion.behavior.minimizes || _searching) {
      away.last = offset;
      return;
    }
    _body.motion.advance(_now);
    if (phase == MotionScrollPhase.dragging &&
        previous != MotionScrollPhase.dragging) {
      away.beginDrag();
    }
    // A drag that began and went into its glide within one frame is heard
    // only as its glide.
    if (phase == MotionScrollPhase.decelerating && !previous.byUser) {
      away.beginDrag();
      away.endDrag(decelerates: true);
    }
    if (previous == MotionScrollPhase.dragging &&
        phase != MotionScrollPhase.dragging) {
      away.endDrag(decelerates: phase == MotionScrollPhase.decelerating);
    }
    switch (phase) {
      case MotionScrollPhase.dragging || MotionScrollPhase.decelerating:
        away.scroll(
          phase == MotionScrollPhase.decelerating
              ? scroll.glideTarget ?? offset
              : offset,
          min: min,
          max: max,
          tracking: phase == MotionScrollPhase.dragging,
        );
      case MotionScrollPhase.programmatic || MotionScrollPhase.idle:
        away.last = offset;
        if (previous == MotionScrollPhase.decelerating) {
          away.endDeceleration();
        }
        if (_body.motion.minimized && offset <= min + 0.5) {
          away.scrollToTop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessory = widget.accessory ?? _leaving;
    final metrics = widget.metrics;
    final rtl = context.isRightToLeft;
    _body
      ..rtl = rtl
      ..metrics = metrics
      ..hosted = accessory != null;
    if (widget.search case final search?) {
      return MotionScope(
        motion: _body.motion,
        child: _SearchTabBar(
          controller: search,
          metrics: metrics,
          minimize: _body,
          accessory: accessory,
          look: widget.look,
          bar: widget.bar,
        ),
      );
    }
    return MotionScope(
      motion: _body.motion,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          _body.motion.extent = width;
          final bar = SizedBox(
            width: width,
            height: metrics.height,
            child: widget.bar(
              _body,
              host: accessory == null ? TabBarHost.none : TabBarHost.accessory,
            ),
          );
          if (accessory == null) {
            return MotionTransition(scale: _body.hint, child: bar);
          }
          final size = Size(
            width,
            GlassTabBar.groupHeight(metrics, accessory: true),
          );
          return SizedBox.fromSize(
            size: size,
            child: MotionTransition(
              scale: _body.hint,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _Accessory(
                      body: _body,
                      places: _accessoryPlaces(size, metrics, rtl: rtl),
                      look: widget.look,
                      child: accessory,
                    ),
                  ),
                  Positioned(left: 0, right: 0, bottom: 0, child: bar),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The accessory's places in a bar group of [size]: across the group above
/// the bar, and level with the minimized circle, 14 after it, to the
/// group's trailing end less the circle's inset.
_AccessoryPlaces _accessoryPlaces(
  Size size,
  TabBarMetrics metrics, {
  required bool rtl,
}) {
  final group = _groupIn(size, metrics, hosted: true);
  final circle = _circleIn(group, metrics, rtl: false);
  Rect mirror(Rect rect) => rtl
      ? Rect.fromLTRB(
          size.width - rect.right,
          rect.top,
          size.width - rect.left,
          rect.bottom,
        )
      : rect;
  return (
    expanded: Rect.fromLTWH(
      group.left,
      0,
      group.width,
      TabBarLayout.accessoryHeight,
    ),
    inline: mirror(
      Rect.fromLTRB(
        circle.right + TabBarLayout.inlineGap,
        circle.top,
        group.right - metrics.minimizedInset,
        circle.top + metrics.inlineAccessoryHeight,
      ),
    ),
    searching: null,
  );
}
