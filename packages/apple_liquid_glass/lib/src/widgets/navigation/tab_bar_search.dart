part of 'tab_bar.dart';

enum _SearchSlot { accessory, bar, circle, field, close }

/// Builds a tab bar's selector under [collapse], hosting [host].
typedef _BarBuilder = Widget Function(
  GlassSelectorCollapse collapse, {
  required TabBarHost host,
});

/// A tab bar and its search tab, laid out over the screen's bottom, with
/// the bottom accessory and the minimizing of the bar it carries under
/// [minimize].
class _SearchTabBar extends StatefulWidget {
  const _SearchTabBar({
    required this.controller,
    required this.metrics,
    required this.minimize,
    required this.accessory,
    required this.look,
    required this.bar,
  });

  final GlassSearchController controller;
  final TabBarMetrics metrics;
  final _MinimizeFrames minimize;
  final Widget? accessory;
  final GlassTabBarStyle look;
  final _BarBuilder bar;

  @override
  State<_SearchTabBar> createState() => _SearchTabBarState();
}

/// The collapse a search tab bar gives its bar: the bar turns into the tab
/// circle while searching or minimized, whichever asks more, so a search
/// opened from the minimized bar leaves the circle in place. While the
/// search is open a tap on the circle closes it; otherwise the circle is
/// the minimized bar's.
final class _SearchCollapse implements GlassSelectorCollapse {
  _SearchCollapse(this.motion, this.search, this.minimize, this.onClose);

  final SearchTabMotion motion;
  final MotionSelection<double> search;
  final _MinimizeFrames minimize;
  final VoidCallback onClose;

  @override
  late final MotionSelection<double> morph = MotionSelection(
    clock: search.clock,
    () => math.max(
      minimize.minimized.value ? math.min(search.value, 1) : search.value,
      minimize.morph.value,
    ),
  );

  @override
  late final MotionSelection<double> press = MotionSelection(
    clock: search.clock,
    () => motion.isOpen ? 0.0 : (minimize.press?.value ?? 0),
  );

  /// Whether the bar runs right to left.
  bool rtl = false;

  /// The record the bar lays out by.
  TabBarMetrics metrics = TabBarMetrics.compact;

  @override
  Rect circleIn(Size size) => _circleIn(Offset.zero & size, metrics, rtl: rtl);

  @override
  bool get takesFinger => motion.isOpen || minimize.takesFinger;

  @override
  void pressDown(double t, double x) {
    if (!motion.isOpen) minimize.pressDown(t, x);
  }

  @override
  bool pressMove(double t, double x) =>
      !motion.isOpen && minimize.pressMove(t, x);

  @override
  void pressUp(double t) {
    if (!motion.isOpen) {
      minimize.pressUp(t);
    } else if (motion.tabTakesTaps) {
      onClose();
    }
  }

  @override
  void pressCancel(double t) {
    if (!motion.isOpen) minimize.pressCancel(t);
  }

  @override
  void activate() {
    if (motion.isOpen) {
      onClose();
    } else {
      minimize.activate();
    }
  }
}

class _SearchTabBarState extends State<_SearchTabBar> with SearchLaw {
  late final _motion = SearchTabMotion(
    open: widget.controller.isOpen,
    clock: MotionClockScope.of(context),
  );
  late final _activated = _motion.select((m) => m.activated);
  final _focus = FocusNode(debugLabel: 'GlassTabBar search');
  late final _q = _motion.select((m) => m.morph);
  late final _p = _motion.select((m) => m.focus.progress);
  late final _tabFade = _motion.select(
    (m) => (1 - m.focus.progress).clamp(0.0, 1.0),
  );
  late final _placeholder = _motion.select(
    (m) => ((m.morph - 0.4) / 0.6).clamp(0.0, 1.0),
  );
  late final _closeScale = _motion.select(
    (m) => SearchMotion.appearScaleFor(m.focus.progress),
  );
  late final _resting = _motion.select((m) => m.resting);
  late final _settled = _motion.select((m) => m.settled);
  late final _travelling = _motion.select((m) => !m.settled);
  late final _closeShown = _motion.select((m) => m.closeShown);
  late final _returned = _motion.select((m) => m.focus.progress == 0);
  late final _open = _motion.select((m) => m.isOpen);
  late final _collapse = _SearchCollapse(_motion, _q, widget.minimize, () {
    widget.controller.closeView();
  });

  double get _now => _motion.clock.now;

  @override
  bool get blurEnds => true;

  @override
  ValueListenable<bool> get returned => _returned;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _activated.addListener(_activate);
  }

  @override
  void didUpdateWidget(_SearchTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _activated.removeListener(_activate);
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted && _motion.activated && !_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  void _changed() {
    final open = widget.controller.isOpen;
    if (open == _motion.isOpen) return;
    setState(() => _motion.turn(_now, open: open));
    if (!open) {
      _focus.unfocus();
      // The query clears after the frame that closed the search, as the
      // field turns back.
      _motion.afterFrame(_now, () {
        if (mounted && !_motion.isOpen) widget.controller.clear();
      });
    }
  }

  @override
  void begin(double t, {required double keyboard}) {
    _motion.focused(t, keyboard: keyboard);
  }

  @override
  void end(double t) {
    _motion.unfocused(t);
  }

  @override
  void keyboardRose(double t) => _motion.keyboardRose(t);

  @override
  Widget build(BuildContext context) {
    final rtl = context.isRightToLeft;
    _collapse
      ..rtl = rtl
      ..metrics = widget.metrics;
    final glyph = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    final open = _motion.isOpen;
    final metrics = widget.metrics;
    final minimize = widget.minimize;
    final accessory = widget.accessory;
    return MotionScope(
      motion: _motion,
      child: SearchHost(
        law: this,
        field: GlassSearchField(
          controller: widget.controller,
          focusNode: _focus,
        ),
        builder: (context, parts) => LayoutBuilder(
          builder: (context, constraints) => MotionTransition(
            scale: minimize.hint,
            alignment: _groupCenter(constraints.biggest.height),
            child: CustomMultiChildLayout(
              delegate: _SearchTabLayout(
                q: _q,
                p: _p,
                minimized: minimize.morph,
                settled: _settled,
                keyboard: parts.keyboard,
                rtl: rtl,
                metrics: metrics,
                onGroup: (width) => minimize.motion.extent = width,
              ),
              children: [
                if (accessory != null)
                  LayoutId(
                    id: _SearchSlot.accessory,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final g = searchTabLayout(
                          size: constraints.biggest,
                          barWidth: 0,
                          rtl: rtl,
                          metrics: metrics,
                        );
                        return _Accessory(
                          body: minimize,
                          places: (
                            expanded: g.accessory,
                            inline: g.inlineAccessory,
                            searching: g.searchingAccessory,
                          ),
                          search: (morph: _q, open: _open),
                          look: widget.look,
                          child: accessory,
                        );
                      },
                    ),
                  ),
                LayoutId(
                  id: _SearchSlot.bar,
                  child: MotionTransition(
                    opacity: _tabFade,
                    child: widget.bar(_collapse, host: TabBarHost.circle),
                  ),
                ),
                LayoutId(
                  id: _SearchSlot.circle,
                  child: MotionVisibility(
                    visible: _travelling,
                    child: MotionVisibility(
                      visible: _resting,
                      maintainPaint: true,
                      maintainSemantics: true,
                      child: ExcludeFocus(
                        excluding: open,
                        child: _SearchCircle(
                          q: _q,
                          placeholder: _placeholder,
                          glyph: glyph,
                          rtl: rtl,
                          onTap: widget.controller.openView,
                        ),
                      ),
                    ),
                  ),
                ),
                if (open)
                  LayoutId(
                    id: _SearchSlot.field,
                    child: MotionVisibility(
                      visible: _settled,
                      maintainSemantics: true,
                      child: parts.field,
                    ),
                  ),
                if (open)
                  LayoutId(
                    id: _SearchSlot.close,
                    child: MotionVisibility(
                      visible: _closeShown,
                      child: MotionTransition(
                        opacity: _p,
                        scale: _closeScale,
                        child: parts.close,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The middle of the bar group, the accessory above the bar included, in a
  // box [height] tall whose bottom the group stands over: where the hint
  // scales it about.
  Alignment _groupCenter(double height) {
    final metrics = widget.metrics;
    final bottom = height - metrics.bottomInset;
    final group = GlassTabBar.groupHeight(
      metrics,
      accessory: widget.accessory != null,
    );
    if (height <= 0) return Alignment.center;
    return Alignment(0, (bottom - group / 2) / height * 2 - 1);
  }
}

/// Places a search tab bar's parts from the morph [q], the focus [p] and
/// the keyboard, laid out again on every change of any without a rebuild.
class _SearchTabLayout extends MultiChildLayoutDelegate {
  _SearchTabLayout({
    required this.q,
    required this.p,
    required this.minimized,
    required this.settled,
    required this.keyboard,
    required this.rtl,
    required this.metrics,
    required this.onGroup,
  }) : super(relayout: Listenable.merge([q, p, minimized, settled, keyboard]));

  final ValueListenable<double> q;
  final ValueListenable<double> p;

  /// How far the bar has minimized, which shrinks the search circle too.
  final ValueListenable<double> minimized;

  /// Hears the bar group's width at each layout.
  final ValueChanged<double> onGroup;
  final ValueListenable<bool> settled;
  final ValueListenable<double> keyboard;
  final bool rtl;
  final TabBarMetrics metrics;

  @override
  void performLayout(Size size) {
    final group = SearchTabGeometry.groupIn(size.width, metrics).width;
    onGroup(group);
    final room = group - metrics.circleSize - TabBarLayout.circleGap;
    final bar = layoutChild(
      _SearchSlot.bar,
      BoxConstraints.loose(Size(math.max(0, room), size.height)),
    );
    final g = searchTabLayout(
      size: size,
      barWidth: bar.width,
      keyboard: keyboard.value,
      rtl: rtl,
      metrics: metrics,
    );
    positionChild(_SearchSlot.bar, g.bar.topLeft);
    void place(_SearchSlot slot, Rect rect) {
      if (!hasChild(slot)) return;
      final box = Rect.fromLTWH(
        rect.left,
        rect.top,
        math.max(0, rect.width),
        math.max(0, rect.height),
      );
      layoutChild(slot, BoxConstraints.tight(box.size));
      positionChild(slot, box.topLeft);
    }

    final focus = p.value;
    place(_SearchSlot.accessory, Offset.zero & size);
    final search = Rect.lerp(g.search, g.minimizedSearch, minimized.value)!;
    place(_SearchSlot.circle, Rect.lerp(search, g.field, q.value)!);
    place(
      _SearchSlot.field,
      settled.value ? lerpRect(g.field, g.focusedField, focus) : g.field,
    );
    final closeFrom = Rect.fromLTWH(
      rtl ? g.field.left : g.field.right - g.field.height,
      g.field.top,
      g.field.height,
      g.field.height,
    );
    place(_SearchSlot.close, Rect.lerp(closeFrom, g.close, focus)!);
  }

  @override
  bool shouldRelayout(_SearchTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl ||
      metrics != oldDelegate.metrics ||
      !identical(minimized, oldDelegate.minimized) ||
      !identical(q, oldDelegate.q) ||
      !identical(p, oldDelegate.p) ||
      !identical(settled, oldDelegate.settled) ||
      !identical(keyboard, oldDelegate.keyboard);
}
