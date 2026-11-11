part of 'tab_bar.dart';

enum _SearchSlot { bar, circle, field, close }

/// Builds a tab bar's selector under [collapse]; [hosted] when it hosts an
/// accessory or a search.
typedef _BarBuilder = Widget Function(
  GlassSelectorCollapse collapse, {
  required bool hosted,
});

/// A tab bar and its search tab, laid out over the screen's bottom.
class _SearchTabBar extends StatefulWidget {
  const _SearchTabBar({required this.controller, required this.bar});

  final GlassSearchController controller;
  final _BarBuilder bar;

  @override
  State<_SearchTabBar> createState() => _SearchTabBarState();
}

/// The motion of a tab bar with a search tab: the morph of the bar into
/// the field and back, the field's focus, and the focus the search takes
/// [SearchMotion.tabActivationDelay] after it opens.
final class _SearchTabMotion extends Motion {
  _SearchTabMotion({required bool open, required this.onActivate})
    : _open = open {
    _morph = own(
      MotionValue<double>(open ? 1 : 0, spring: SearchMotion.tabSpring),
      rest: _morphRest,
    );
    focus = own(SearchMotion.tabBar());
  }

  /// Gives the field the focus once the opened search activates.
  final VoidCallback onActivate;

  late final MotionValue<double> _morph;

  /// The field's focus transition.
  late final SearchMotion focus;

  bool _open;

  // NEAR: the shapes land by up to 0.001 of their travel.
  static double _morphRest() => 1e-3;

  static const _activation = #activation;

  /// Whether the search is open or heading there.
  bool get isOpen => _open;

  /// Runs [action] in the first frame after time [t], on the motion's
  /// timeline.
  void afterFrame(double t, VoidCallback action) =>
      at(t + 1e-6, (_) => action(), slot: #afterFrame);

  /// The morph: 0 a tab bar, 1 a search field.
  double get morph => _morph.valueAt(now);

  /// Opens or closes the search at time [t].
  void turn(double t, {required bool open}) {
    advance(t);
    if (open == _open) return;
    _open = open;
    _morph.retarget(t, open ? 1 : 0);
    if (open) {
      at(
        t + SearchMotion.tabActivationDelay,
        (_) => onActivate(),
        slot: _activation,
      );
    } else {
      unschedule(_activation);
    }
  }

  /// The bar rests as a bar and the search circle takes taps.
  bool get resting => !_open && morph.abs() < 0.001;

  /// The search is open and the morph into the field has settled: the
  /// field itself shows.
  bool get settled => _open && (morph - 1).abs() < 0.001;

  /// The close button shows: the field settled and focused or on its way.
  bool get closeShown =>
      settled &&
      (focus.progress > 0.001 || (focus.isFocused && !focus.waitsForKeyboard));

  /// A tap on the tab circle closes the search.
  bool get tabTakesTaps => _open && focus.progress < 0.5;
}

/// The collapse a search tab bar gives its bar: the bar turns into the tab
/// circle while searching, and a tap on the circle closes the search.
final class _SearchCollapse implements GlassSelectorCollapse {
  _SearchCollapse(this.motion, this.morph, this.onClose);

  final _SearchTabMotion motion;
  final VoidCallback onClose;

  @override
  final MotionSelection<double> morph;

  @override
  MotionSelection<double>? get press => null;

  /// Whether the bar runs right to left.
  bool rtl = false;

  @override
  Rect circleIn(Size size) => _circleIn(size, rtl: rtl);

  @override
  bool get takesFinger => motion.isOpen;

  @override
  void pressDown(double t, double x) {}

  @override
  bool pressMove(double t, double x) => false;

  @override
  void pressUp(double t) {
    if (motion.tabTakesTaps) onClose();
  }

  @override
  void pressCancel(double t) {}

  @override
  void activate() => onClose();
}

class _SearchTabBarState extends State<_SearchTabBar> with SearchLaw {
  late final _motion = _SearchTabMotion(
    open: widget.controller.isOpen,
    onActivate: _activate,
  );
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
  late final _collapse = _SearchCollapse(_motion, _q, () {
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
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted && _motion.isOpen && !_focus.hasFocus) _focus.requestFocus();
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
    final focus = _motion.focus;
    if (focus.isFocused) return;
    if (keyboard > 0) {
      focus.focus(t, delay: SearchMotion.tabKeyboardLag);
    } else {
      focus.focusAfterKeyboard(t);
    }
  }

  @override
  void end(double t) {
    if (_motion.focus.isFocused) {
      _motion.focus.unfocus(t, delay: SearchMotion.tabUnfocusDelay);
    }
  }

  @override
  void keyboardRose(double t) =>
      _motion.focus.keyboardRose(t, lag: SearchMotion.tabKeyboardLag);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _collapse.rtl = rtl;
    final glyph = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    final open = _motion.isOpen;
    return MotionScope(
      motion: _motion,
      child: SearchHost(
        law: this,
        field: GlassSearchField(
          controller: widget.controller,
          focusNode: _focus,
        ),
        builder: (context, parts) => CustomMultiChildLayout(
          delegate: _SearchTabLayout(
            q: _q,
            p: _p,
            settled: _settled,
            keyboard: parts.keyboard,
            rtl: rtl,
          ),
          children: [
            LayoutId(
              id: _SearchSlot.bar,
              child: MotionTransition(
                opacity: _tabFade,
                child: widget.bar(_collapse, hosted: true),
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
    );
  }
}

/// Places a search tab bar's parts from the morph [q], the focus [p] and
/// the keyboard, laid out again on every change of any without a rebuild.
class _SearchTabLayout extends MultiChildLayoutDelegate {
  _SearchTabLayout({
    required this.q,
    required this.p,
    required this.settled,
    required this.keyboard,
    required this.rtl,
  }) : super(relayout: Listenable.merge([q, p, settled, keyboard]));

  final ValueListenable<double> q;
  final ValueListenable<double> p;
  final ValueListenable<bool> settled;
  final ValueListenable<double> keyboard;
  final bool rtl;

  @override
  void performLayout(Size size) {
    final room =
        size.width -
        2 * SearchTabGeometry.barInset -
        SearchTabGeometry.circleSize -
        SearchBarGeometry.gap;
    final bar = layoutChild(
      _SearchSlot.bar,
      BoxConstraints.loose(Size(math.max(0, room), size.height)),
    );
    final g = searchTabLayout(
      size: size,
      barWidth: bar.width,
      keyboard: keyboard.value,
      rtl: rtl,
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
    place(_SearchSlot.circle, Rect.lerp(g.search, g.field, q.value)!);
    place(
      _SearchSlot.field,
      settled.value ? lerpRect(g.field, g.focusedField, focus) : g.field,
    );
    final closeFrom = Rect.fromLTWH(
      rtl ? g.field.left : g.field.right - RawGlassSearchField.height,
      g.field.top,
      RawGlassSearchField.height,
      RawGlassSearchField.height,
    );
    place(_SearchSlot.close, Rect.lerp(closeFrom, g.close, focus)!);
  }

  @override
  bool shouldRelayout(_SearchTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl ||
      !identical(q, oldDelegate.q) ||
      !identical(p, oldDelegate.p) ||
      !identical(settled, oldDelegate.settled) ||
      !identical(keyboard, oldDelegate.keyboard);
}
