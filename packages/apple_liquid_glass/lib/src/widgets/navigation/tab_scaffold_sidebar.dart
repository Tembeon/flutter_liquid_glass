part of 'package:apple_liquid_glass/src/widgets/navigation/tab_scaffold.dart';

// The chrome of a regular width as the tab sidebar passport measures it on
// the 11 inch iPad Pro (iOS 27.2), unless a line says otherwise.
abstract final class _Regular {
  static const double barHeight = 44;
  static const double barRadius = 22;
  static const double barPadding = 4;
  static const double buttonWidth = 56;
  static const double glyphSize = 21;
  static const double itemHeight = 36;
  static const double itemRadius = 18;
  static const double itemPadding = 15.5;

  // The search tab drawn as its magnifier alone: not measured.
  static const double iconItemWidth = 44;

  // The action's circle beside the bar: not measured.
  static const double actionGap = 8;

  // The least room a side of the bar keeps: not measured.
  static const double barMargin = 20;

  // The content's navigation bars stand 54 below the bar's top.
  static const double contentDrop = 54;

  static const double circle = 44;
  static const double circleEnd = 16;
  static const double rowsTop = 63;
  static const double rowInset = 20;
  static const double rowWidth = 244;
  static const double rowHeight = 44;
  static const double rowRadius = 22;
  static const double rowIconBox = 31;
  static const double rowIconCenter = 30;
  static const double rowTitleStart = 54;
  static const double rowIconSize = 24;
  static final double rowEndInset =
      GlassTabLayout.defaultSidebarWidth.preferred - rowInset - rowWidth;

  // The rail: its circles centered in it, the hide button's and each row's
  // pill; a row's title fades with the side's width between the sidebar's
  // minimum and the rail's, so a fold's spring dissolves it before the edge
  // cuts it, and lies on the sidebar's narrowest row's width while it does
  // (_SideWidths). The package's own.
  static const double railIconCenter = circle / 2;

  // A row's badge: not measured.
  static const double rowEnd = 16;

  // The selected row beside a list column: (116, 116, 128, 0.08).
  static const Color quietPill = Color(0x14747480);

  // Under a sidebar over the content: not measured, a sheet's dimming.
  static const Color dimming = Color(0x33000000);

  // One label read: 187 wide for a title about 147 wide.
  static const double accessoryHeight = 64;
  static const double accessoryInset = 20;
  static const double accessoryPadding = 20;

  static const TextStyle item = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle selectedItem = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle row = TextStyle(fontSize: 17);
  static const TextStyle selectedRow = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
  );

  // Not measured: the bottom bar's cap.
  static const double maxTextScale = 1.25;
}

// The chrome of a regular width: the bar at the top, or the tab sidebar
// over the content or beside it, or its rail beside it, with the content's
// safe area grown for them, and the bottom accessory over the content's
// bottom. The bar's platter and the side are one glass whose frame springs
// between them, each side's content over it, clipped to it and fading with
// it. A hand on the side's edge resizes the sidebar, folds it into the
// rail past its minimum and hides the rail past its width.
class _RegularChrome extends StatefulWidget {
  const _RegularChrome({
    required this.size,
    required this.items,
    required this.selected,
    required this.iconOnly,
    required this.onSelected,
    required this.beside,
    required this.sidebarShown,
    required this.onSidebar,
    required this.rail,
    required this.onRail,
    required this.toggle,
    required this.sidebarWidth,
    required this.minSidebarWidth,
    required this.maxSidebarWidth,
    required this.railWidth,
    required this.hides,
    required this.folds,
    required this.onSidebarWidth,
    required this.onSidebarReset,
    required this.resizable,
    required this.quiet,
    required this.look,
    required this.semanticLabel,
    required this.accessory,
    required this.action,
    required this.header,
    required this.footer,
    required this.background,
    required this.child,
  });

  // The size the scaffold lays the chrome out in.
  final Size size;
  final List<GlassTabDestination> items;
  final int? selected;
  final int? iconOnly;
  final ValueChanged<int> onSelected;
  final bool beside;
  final bool sidebarShown;
  final ValueChanged<bool> onSidebar;
  final bool rail;
  final ValueChanged<bool> onRail;
  // The sidebar's button: hides the side, or folds the sidebar into the
  // rail and back.
  final _SideToggle? toggle;
  // The sidebar's width as drawn, within its limits for [size].
  final double sidebarWidth;
  final double minSidebarWidth;
  final double maxSidebarWidth;
  final double railWidth;
  final bool hides;
  final bool folds;
  final ValueChanged<double> onSidebarWidth;
  final VoidCallback onSidebarReset;
  final bool resizable;
  final bool quiet;
  final GlassTabBarStyle? look;
  final String? semanticLabel;
  final Widget? accessory;
  final GlassTabBarAction? action;
  final Widget? header;
  final Widget? footer;
  final Color background;
  final Widget child;

  @override
  State<_RegularChrome> createState() => _RegularChromeState();
}

class _RegularChromeState extends State<_RegularChrome> {
  final _active = ValueNotifier<MotionScroll?>(null);
  late final MotionClock _clock = MotionClockScope.of(context);
  late final _hiding = GlassTabBarHiding(clock: _clock);
  // How far the glass has gone from the bar at the top to the side, 0 to
  // 1: across, its place and width; down, its top and height.
  late final _across = MotionValue<double>(
    0,
    clock: _clock,
    restDistance: () => _restOver(_acrossSpan),
  );
  late final _down = MotionValue<double>(
    0,
    clock: _clock,
    restDistance: () => _restOver(_downSpan),
  );
  // The side's width.
  late final _side = MotionValue<double>(widget.sidebarWidth, clock: _clock);
  late MotionSelection<GlassFrame> _frame;
  late final _barLift = MotionSelection(
    () => (_hiding.shown.value - 1) * _liftBy * (1 - _shareOf(_down)),
    clock: _clock,
  );
  late final _barOpacity = MotionSelection(
    () => _hiding.shown.value * (1 - _shareOf(_across)),
    clock: _clock,
  );
  late final _sidebarOpacity = MotionSelection(
    () => _shareOf(_down),
    clock: _clock,
  );
  late final _dimming = MotionSelection(
    () => _shareOf(_down) * _widths.openAt(_side.value),
    clock: _clock,
  );
  late final _dismiss = TapInteraction(onTap: (_) => widget.onSidebar(false));
  // The content's leading inset, made for whether the side stands beside
  // the content and whether the layout is beside.
  late MotionSelection<double> _inset;
  (bool, bool)? _insetFor;
  // The hand on the side's edge, through the side's forms.
  ColumnFold? _fold;
  bool? _rail;

  double _liftBy = 0;
  _Place? _place;
  bool? _toSidebar;
  bool _beside = false;
  // Whether the glass rests at the bar or the side, and whether the side's
  // width rests.
  bool _morphed = true;
  bool _sized = true;
  bool _aiming = false;

  List<MotionValue<double>> get _values => [_across, _down, _side];

  static double _shareOf(MotionValue<double> value) =>
      value.value.clamp(0.0, 1.0);

  // A progress rests where the glass it moves over [span] stops moving.
  static double _restOver(double span) => MotionRest.scale(span);

  double get _acrossSpan {
    final place = _place;
    if (place == null) return 0;
    final width = _side.target;
    final left = place.rtl ? place.size.width - width : 0.0;
    return math.max(
      (left - place.bar.left).abs(),
      (width - place.bar.width).abs(),
    );
  }

  double get _downSpan {
    final place = _place;
    if (place == null) return 0;
    return math.max(
      place.bar.top,
      (place.size.height - place.bar.height).abs(),
    );
  }

  // The glass at the progress of [_across] and [_down] between the bar
  // and the side of [place].
  MotionSelection<GlassFrame> _frameAt(_Place place) => MotionSelection(() {
    final bar = place.bar;
    final size = place.size;
    final across = _across.value;
    final down = _down.value;
    final side = _side.value;
    final width = bar.width + (side - bar.width) * across;
    final height = bar.height + (size.height - bar.height) * down;
    final left =
        bar.left + ((place.rtl ? size.width - side : 0) - bar.left) * across;
    final grown = _shareOf(_down);
    final shown = _hiding.shown.value;
    return GlassFrame(
      shape: LiquidRoundedSuperellipse(
        radius: math.min(
          _Regular.barRadius * (1 - grown),
          math.min(width, height) / 2,
        ),
      ),
      rect: Rect.fromLTWH(
        left,
        bar.top * (1 - down) + (shown - 1) * _liftBy * (1 - grown),
        width,
        height,
      ),
      opacity: shown + (1 - shown) * grown,
    );
  }, clock: _clock);

  // Sends the glass to the side or the bar: at once on the first build and
  // on a change between over and beside (a rotated window is laid out
  // anew), else on the morph's springs.
  void _aim({required bool toSidebar, required bool beside}) {
    final first = _toSidebar == null;
    if (first) {
      for (final value in _values) {
        value.addListener(_rest);
      }
    }
    final turned = _toSidebar != toSidebar;
    final jump = first || beside != _beside;
    _toSidebar = toSidebar;
    _beside = beside;
    _aiming = true;
    if (jump) {
      final to = toSidebar ? 1.0 : 0.0;
      _across.target = to;
      _down.target = to;
      _morphed = true;
    } else if (turned) {
      TabSidebarMotion.morph(_across, _down, toSidebar: toSidebar);
      final now = _clock.now;
      _morphed = _across.settledAt(now) && _down.settledAt(now);
    }
    _aiming = false;
  }

  void _rest() {
    if (_aiming) return;
    final now = _clock.now;
    final morphed =
        _morphed || (_across.settledAt(now) && _down.settledAt(now));
    final sized = _sized || (_fold == null && _side.settledAt(now));
    if (morphed == _morphed && sized == _sized) return;
    setState(() {
      _morphed = morphed;
      _sized = sized;
    });
  }

  // The content's leading inset: the side's width beside the content, and
  // no more than the rail's where the sidebar would cover the content.
  MotionSelection<double> _insetAt({
    required bool placed,
    required bool beside,
  }) => MotionSelection(() {
    if (!placed) return 0.0;
    final side = _side.value;
    return beside ? side : math.min(side, widget.railWidth);
  }, clock: _clock);

  // Sends the side to the rail's width or the sidebar's: on the fold's
  // spring when the form turns, at once otherwise. A hand on the edge
  // moves it alone.
  void _aimSide({required bool rail, required double width}) {
    final to = rail ? widget.railWidth : width;
    final turned = _rail != null && _rail != rail;
    _rail = rail;
    if (_fold != null || _side.target == to) return;
    _aiming = true;
    if (turned) {
      TabSidebarMotion.fold(_side, to: to);
      _sized = false;
    } else {
      _side.target = to;
    }
    _aiming = false;
  }

  _SideWidths get _widths =>
      _SideWidths(rail: widget.railWidth, minimum: widget.minSidebarWidth);

  // The side's forms the layout offers, narrowest first: hidden (the bar at
  // the top), the rail and the sidebar.
  List<_SideForm> get _kinds => [
    if (widget.hides) _SideForm.hidden,
    if (widget.folds) _SideForm.rail,
    _SideForm.sidebar,
  ];

  List<ColumnForm> get _forms => [
    for (final kind in _kinds)
      switch (kind) {
        _SideForm.hidden => const ColumnForm(width: 0),
        _SideForm.rail => ColumnForm(width: widget.railWidth),
        _SideForm.sidebar => ColumnForm(
          width: widget.sidebarWidth,
          min: widget.minSidebarWidth,
          max: widget.maxSidebarWidth,
        ),
      },
  ];

  // The form the side is drawn in; the scaffold draws only a form the
  // layout offers.
  _SideForm get _kind => !widget.sidebarShown
      ? _SideForm.hidden
      : widget.rail
      ? _SideForm.rail
      : _SideForm.sidebar;

  int get _form => _kinds.indexOf(_kind);

  double get _formWidth => switch (_kind) {
    _SideForm.hidden => 0,
    _SideForm.rail => widget.railWidth,
    _SideForm.sidebar => widget.sidebarWidth,
  };

  // Writes a change of the side's form, or of the sidebar's width, between
  // the forms at [from] and [to] of [_kinds].
  void _go(int from, int to, double width) {
    final kinds = _kinds;
    final was = kinds[from];
    final now = kinds[to];
    if (now == was) {
      if (now == _SideForm.sidebar && width != widget.sidebarWidth) {
        widget.onSidebarWidth(width);
      }
    } else if (now == _SideForm.hidden) {
      widget.onSidebar(false);
    } else if (was == _SideForm.hidden) {
      widget.onSidebar(true);
    } else {
      widget.onRail(now == _SideForm.rail);
    }
  }

  void _dragStarted() {
    final form = _form;
    setState(() {
      _fold = ColumnFold(_forms, form: form, width: _formWidth);
      _sized = false;
    });
  }

  // The side follows the hand 1:1 while it rests, and a fold springs it to
  // its new form's width; a hand that moves on while the spring runs aims
  // the spring again.
  void _dragged(double travel) {
    final fold = _fold;
    if (fold == null) return;
    final from = fold.form;
    final folded = fold.update(travel);
    final to = fold.form;
    if (_kinds[to] != _SideForm.hidden) {
      _aiming = true;
      if (folded || !_side.settledAt(_clock.now)) {
        TabSidebarMotion.fold(_side, to: fold.width);
      } else {
        _side.target = fold.width;
      }
      _aiming = false;
    }
    if (folded) _go(from, to, fold.width);
  }

  // Writes the sidebar's width where the hand let it go, unless it came
  // back to the width it had.
  void _released() {
    final fold = _fold;
    if (fold == null) return;
    setState(() {
      _fold = null;
      _sized = _side.settledAt(_clock.now);
    });
    if (fold.form == fold.forms.length - 1 &&
        fold.width != fold.forms.last.width) {
      widget.onSidebarWidth(fold.width);
    }
  }

  (int, double) _stepped(double by) =>
      ColumnFold.step(_forms, form: _form, width: _formWidth, by: by);

  double get _stepSize => math.max(1, (widget.size.width / 20).roundToDouble());

  void _step(ValueCommand command) {
    final form = _form;
    final shape = _forms[form];
    final from = _formWidth;
    final step = _stepSize;
    final by = switch (command) {
      ValueCommand.increase => step,
      ValueCommand.decrease => -step,
      ValueCommand.increaseLarge => 5 * step,
      ValueCommand.decreaseLarge => -5 * step,
      ValueCommand.toMaximum => shape.max - from,
      ValueCommand.toMinimum => shape.min - from,
    };
    if (by == 0) return;
    final (to, width) = _stepped(by);
    _go(form, to, width);
  }

  Widget _edge({required bool rtl}) {
    final strings = GlassLocalizations.of(context);
    final room = widget.size.width;
    String value(double width) =>
        strings.percentValue(room > 0 ? width / room : 0);
    final step = _stepSize;
    return Positioned.fill(
      key: const ValueKey('edge'),
      child: CustomSingleChildLayout(
        delegate: _SideLayout(_side, rtl: rtl, edge: true),
        child: GlassColumnDivider(
          range: AdjustRange.of(
            _formWidth,
            min: _forms.first.min,
            max: widget.maxSidebarWidth,
          ),
          value: value(_formWidth),
          increasedValue: value(_stepped(step).$2),
          decreasedValue: value(_stepped(-step).$2),
          onDragStart: _dragStarted,
          onDragUpdate: _dragged,
          onDragEnd: _released,
          onStep: _step,
          onReset: widget.onSidebarReset,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_toSidebar != null) {
      for (final value in _values) {
        value.removeListener(_rest);
      }
    }
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = widget.size;
    final shown = widget.sidebarShown;
    final rail = widget.rail;
    final beside = widget.beside;
    final placed = shown && (beside || rail);
    final top = media.padding.top + (placed ? 0 : _Regular.contentDrop);
    final accessory = widget.accessory;
    final bottom = accessory == null
        ? media.padding.bottom
        : math.max(
            media.padding.bottom,
            _Regular.accessoryInset + _Regular.accessoryHeight,
          );
    _liftBy = media.padding.top + _Regular.barHeight;
    final action = widget.action;
    final besideBar = action == null
        ? 0.0
        : _Regular.actionGap + _Regular.circle;
    final sides = BarRoom.sidesOf(context, inset: _Regular.barMargin);
    final layout = _BarLayout(
      context,
      items: widget.items,
      iconOnly: widget.iconOnly,
      selected: widget.selected,
      maxWidth: size.width - 2 * math.max(sides.left, sides.right) - besideBar,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final start = (size.width - layout.width - besideBar) / 2;
    final bar = Rect.fromLTWH(
      rtl ? size.width - start - layout.width : start,
      media.padding.top,
      layout.width,
      _Regular.barHeight,
    );
    final place = (bar: bar, size: size, rtl: rtl);
    if (place != _place) {
      _place = place;
      _frame = _frameAt(place);
    }
    if ((placed, beside) != _insetFor) {
      _insetFor = (placed, beside);
      _inset = _insetAt(placed: placed, beside: beside);
    }
    _aimSide(rail: rail, width: widget.sidebarWidth);
    _aim(toSidebar: shown, beside: beside);
    final withBar = !shown || !_morphed;
    final withSidebar = shown || !_morphed;
    final over = !beside && withSidebar && (!rail || !_sized);
    return GlassChrome(
      edges: ChromeEdges(
        top: placed ? ChromeBar.none : ChromeBar.floating,
        topExtent: top,
        scrolledUnderAfter: 0,
        bottom: ChromeBar.none,
        bottomExtent: bottom,
        background: widget.background,
      ),
      active: _active,
      outer: GlassChrome.maybeOf(context),
      tabBar: _hiding,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SideInset(
            inset: _inset,
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(top: top, bottom: bottom),
              ),
              // Under the top bar the content's rows are not the window's
              // first: the window buttons stand in the bar's row.
              child: GlassEnvironmentOverride(
                windowControls: placed ? null : GlassWindowControls.none,
                child: widget.child,
              ),
            ),
          ),
          if (accessory != null)
            PositionedDirectional(
              key: const ValueKey('accessory'),
              start: 0,
              end: 0,
              bottom: _Regular.accessoryInset,
              height: _Regular.accessoryHeight,
              child: CustomSingleChildLayout(
                delegate: _InsetShift(_inset, settled: 0, rtl: rtl),
                child: Center(child: _RegularAccessory(child: accessory)),
              ),
            ),
          if (over)
            Positioned.fill(
              key: const ValueKey('dimming'),
              child: _leaving(
                !shown || rail,
                MotionTransition(
                  opacity: _dimming,
                  child: InputRegion(
                    interactions: [_dismiss],
                    semantics: SemanticsProperties(
                      label: GlassLocalizations.of(context).hideSidebarLabel,
                      button: true,
                    ),
                    child: const ColoredBox(color: _Regular.dimming),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            key: const ValueKey('glass'),
            child: GlassSurface.live(
              role: GlassRole.bar,
              frame: _frame,
              glass: Glass.regular(
                tint: widget.look?.backgroundColor?.resolve(const {}),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            key: const ValueKey('content'),
            child: ClipRect(
              clipper: _FrameClip(_frame),
              clipBehavior: _morphed && _sized ? Clip.none : Clip.hardEdge,
              child: Stack(
                children: [
                  if (withBar)
                    Positioned.fromRect(
                      key: const ValueKey('bar'),
                      rect: bar,
                      child: MotionTransition(
                        translateY: _barLift,
                        opacity: _barOpacity,
                        child: _leaving(
                          shown,
                          _TopBar(
                            layout: layout,
                            items: widget.items,
                            selected: widget.selected,
                            iconOnly: widget.iconOnly,
                            onSelected: widget.onSelected,
                            onSidebar: () => widget.onSidebar(true),
                            look: widget.look,
                            semanticLabel: widget.semanticLabel,
                          ),
                        ),
                      ),
                    ),
                  if (withSidebar)
                    Positioned.fill(
                      key: const ValueKey('sidebar'),
                      child: CustomSingleChildLayout(
                        delegate: _SideLayout(_side, rtl: rtl),
                        child: MotionTransition(
                          opacity: _sidebarOpacity,
                          child: _leaving(
                            !shown,
                            GlassTabSidebar(
                              destinations: widget.items,
                              selectedIndex: widget.selected,
                              onDestinationSelected: widget.onSelected,
                              quietSelection: widget.quiet,
                              header: widget.header,
                              footer: widget.footer,
                              action: action,
                              onToggle: widget.toggle?.onPressed,
                              toggleSemanticLabel: widget.toggle?.semanticLabel,
                              railWidth: widget.railWidth,
                              minimumWidth: widget.minSidebarWidth,
                              glass: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (action != null && withBar)
            Positioned(
              key: const ValueKey('action'),
              left: rtl
                  ? bar.left - _Regular.actionGap - _Regular.circle
                  : bar.right + _Regular.actionGap,
              top: bar.top,
              child: MotionTransition(
                translateY: _barLift,
                opacity: _barOpacity,
                child: _leaving(
                  shown,
                  _circle(
                    onPressed: action.onPressed,
                    semanticLabel: action.semanticLabel,
                    child: action.icon,
                  ),
                ),
              ),
            ),
          if (widget.resizable && (shown || _fold != null)) _edge(rtl: rtl),
        ],
      ),
    );
  }
}

enum _SideForm { hidden, rail, sidebar }

// The rail's width and the sidebar's narrowest, between which the side's
// content changes from the rail's to the sidebar's.
@immutable
final class _SideWidths {
  const _SideWidths({required this.rail, required this.minimum});

  final double rail;
  final double minimum;

  // How far the side has opened from the rail to the sidebar's narrowest,
  // 0 to 1, at [width].
  double openAt(double width) => minimum <= rail
      ? (width > rail ? 1.0 : 0.0)
      : ((width - rail) / (minimum - rail)).clamp(0.0, 1.0);

  // The rail's circles and pills centered in it.
  double get railInset => (rail - _Regular.circle) / 2;

  // The width a row's title lies on while it fades.
  double get narrowestRow => minimum - _Regular.rowInset - _Regular.rowEndInset;
}

typedef _SideToggle = ({VoidCallback onPressed, String semanticLabel});

double _lerp(double a, double b, double t) => a + (b - a) * t;

// Lays the side's content out at the side's [width], at the edge it stands
// at, or with [edge] the divider centered on the side's trailing edge.
class _SideLayout extends SingleChildLayoutDelegate {
  _SideLayout(this.width, {required this.rtl, this.edge = false})
    : super(relayout: width);

  final ValueListenable<double> width;
  final bool rtl;
  final bool edge;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: edge ? GlassColumnDivider.width : math.max(0, width.value),
        height: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final start = edge ? width.value - childSize.width / 2 : 0.0;
    return Offset(rtl ? size.width - start - childSize.width : start, 0);
  }

  @override
  bool shouldRelayout(_SideLayout oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.rtl != rtl ||
      oldDelegate.edge != edge;
}

// Where the chrome lays the glass out: the bar's rect, the room the side
// fills the height of, and the edge the side stands at.
typedef _Place = ({Rect bar, Size size, bool rtl});

// Clips the chrome's content to the glass it lies on while the glass
// morphs.
class _FrameClip extends CustomClipper<Rect> {
  _FrameClip(this.frame) : super(reclip: frame);

  final ValueListenable<GlassFrame> frame;

  @override
  Rect getClip(Size size) => frame.value.rect ?? Offset.zero & size;

  @override
  bool shouldReclip(_FrameClip oldClipper) => oldClipper.frame != frame;
}

// The side of the chrome the glass is leaving: it takes no touches and
// reads to no screen reader while it fades.
Widget _leaving(bool leaving, Widget child) => IgnorePointer(
  ignoring: leaving,
  child: ExcludeSemantics(excluding: leaving, child: child),
);

Widget _circle({
  required VoidCallback? onPressed,
  required String semanticLabel,
  required Widget child,
  Color? color,
}) => SizedBox.square(
  dimension: _Regular.circle,
  child: GlassButton(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    style: GlassButton.styleFrom(
      minimumSize: const Size.square(_Regular.circle),
      padding: EdgeInsets.zero,
      iconColor: color,
      iconSize: _Regular.glyphSize,
    ),
    child: child,
  ),
);

Color _foreground(
  BuildContext context,
  GlassTabBarStyle? look, {
  required bool selected,
}) => GlassDynamicColor.resolve(
  look?.foregroundColor?.resolve({if (selected) WidgetState.selected}) ??
      (selected
          ? GlassTheme.primaryColorOf(context) ?? GlassTabBar.selected
          : GlassTabBar.unselected),
  context,
);

// A tab's button as accessibility reads it, in the button's own node: the
// tab's name, whether it is the one selected, and its badge.
Widget _tabSemantics(
  GlassTabDestination destination, {
  required bool selected,
  required Widget child,
}) => Semantics(
  selected: selected,
  label: destination.semanticLabel ?? glassLabelTextOf(destination.label),
  child: child,
);

// What the bar at the top holds: the width of every tab, as wide as its
// title at either weight and 15.5 a side, and the tabs that fit in
// [maxWidth], in order: the leading ones that fit, the selected one in
// place of the last of them when it does not, and the search tab at the
// end; the sidebar holds them all.
final class _BarLayout {
  factory _BarLayout(
    BuildContext context, {
    required List<GlassTabDestination> items,
    required int? iconOnly,
    required int? selected,
    required double maxWidth,
  }) {
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final direction = Directionality.of(context);
    double widthOf(int index) {
      if (index == iconOnly) return _Regular.iconItemWidth;
      final text = glassLabelTextOf(items[index].label) ?? '';
      double drawn(TextStyle style) => scale
          .measure(text, style, textDirection: direction, maxLines: 1)
          .size
          .width;
      return math.max(drawn(_Regular.item), drawn(_Regular.selectedItem)) +
          2 * _Regular.itemPadding;
    }

    final widths = [for (var i = 0; i < items.length; i++) widthOf(i)];
    var room =
        maxWidth -
        2 * _Regular.barPadding -
        _Regular.buttonWidth -
        (iconOnly == null ? 0 : widths[iconOnly]);
    final fits = <int>[];
    for (var i = 0; i < widths.length; i++) {
      if (i == iconOnly) continue;
      if (widths[i] > room) break;
      fits.add(i);
      room -= widths[i];
    }
    if (selected != null && selected != iconOnly && !fits.contains(selected)) {
      while (fits.isNotEmpty && widths[selected] > room) {
        room += widths[fits.removeLast()];
      }
      fits.add(selected);
    }
    return _BarLayout._(widths, [...fits, ?iconOnly]);
  }

  const _BarLayout._(this.widths, this.shown);

  final List<double> widths;
  final List<int> shown;

  // The row inside the platter: the sidebar button and the tabs shown.
  double get row =>
      shown.fold(_Regular.buttonWidth, (sum, index) => sum + widths[index]);

  double get width => row + 2 * _Regular.barPadding;
}

// The content of the bar at the top: the sidebar button and the tabs
// [layout] shows, and the selection lens on the selected one.
class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.layout,
    required this.items,
    required this.selected,
    required this.iconOnly,
    required this.onSelected,
    required this.onSidebar,
    required this.look,
    required this.semanticLabel,
  });

  final _BarLayout layout;
  final List<GlassTabDestination> items;
  final int? selected;
  final int? iconOnly;
  final ValueChanged<int> onSelected;
  final VoidCallback onSidebar;
  final GlassTabBarStyle? look;
  final String? semanticLabel;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final _left = MotionValue<double>(0, clock: _clock);
  late final _width = MotionValue<double>(0, clock: _clock);
  late final _lens = MotionSelection(
    () => GlassFrame(
      shape: const LiquidRoundedSuperellipse(radius: _Regular.itemRadius),
      rect: Rect.fromLTWH(_left.value, 0, _width.value, _Regular.itemHeight),
      opacity: _width.value > 0 ? 1 : 0,
    ),
    clock: _clock,
  );
  bool _placed = false;

  void _place(double left, double width) {
    if (!_placed) {
      _placed = true;
      _left.target = left;
      _width.target = width;
    } else if (_left.target != left || _width.target != width) {
      TabSidebarMotion.select(_left, _width, toStart: left, toWidth: width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final items = widget.items;
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final direction = Directionality.of(context);
    final layout = widget.layout;
    final widths = layout.widths;
    final shown = layout.shown;
    final row = layout.row;
    final selected = widget.selected;
    if (selected == null || !shown.contains(selected)) {
      _width.target = 0;
      _placed = false;
    } else {
      var start = _Regular.buttonWidth;
      for (final index in shown.takeWhile((index) => index != selected)) {
        start += widths[index];
      }
      final width = widths[selected];
      _place(
        direction == TextDirection.rtl ? row - start - width : start,
        width,
      );
    }
    final strings = GlassLocalizations.of(context);
    final thumb = look?.thumbColor?.resolve(const {}) ?? GlassTabBar.thumb;

    Widget item(int index) {
      final destination = items[index];
      final chosen = index == selected;
      final color = _foreground(context, look, selected: chosen);
      final icon = chosen
          ? destination.selectedIcon ?? destination.icon
          : destination.icon;
      final label = index == widget.iconOnly
          ? IconTheme.merge(
              data: IconThemeData(color: color, size: _Regular.glyphSize),
              child: icon,
            )
          : DefaultTextStyle(
              style: scale
                  .resolve(chosen ? _Regular.selectedItem : _Regular.item)
                  .copyWith(color: color),
              maxLines: 1,
              child: destination.label,
            );
      final badge = destination.badge;
      return SizedBox(
        width: widths[index],
        height: _Regular.itemHeight,
        child: RawGlassButton(
          onPressed: destination.enabled
              ? () => widget.onSelected(index)
              : null,
          builder: (context, details) => details.label,
          child: _tabSemantics(
            destination,
            selected: chosen,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                Center(child: ExcludeSemantics(child: scale.apply(label))),
                if (badge != null)
                  PositionedDirectional(top: 0, end: 0, child: badge),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Padding(
        padding: const EdgeInsets.all(_Regular.barPadding),
        child: SizedBox(
          width: row,
          height: _Regular.itemHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: GlassSurface.live(
                  role: GlassRole.lens,
                  frame: _lens,
                  glass: Glass.regular(tint: thumb),
                  child: const SizedBox.expand(),
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: _Regular.buttonWidth,
                    height: _Regular.itemHeight,
                    child: RawGlassButton(
                      onPressed: widget.onSidebar,
                      semanticLabel: strings.showSidebarLabel,
                      builder: (context, details) =>
                          Center(child: details.label),
                      child: IconTheme.merge(
                        data: IconThemeData(
                          color: _foreground(context, look, selected: false),
                          size: _Regular.glyphSize,
                        ),
                        child: const GlassSidebarGlyph(),
                      ),
                    ),
                  ),
                  for (final index in shown) item(index),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tab sidebar of a [GlassTabScaffold] as a block of its own, for an
/// app that lays out its own shell: its button at the top, then a row per
/// destination, the selected one a tint pill with its content in the color
/// that reads on it ([GlassThemeData.primaryContrastingColor]).
///
/// UIKit: the sidebar of `UITabBarController` with the `sidebarAdaptable`
/// mode. SwiftUI: `TabView` with `.sidebarAdaptable`. Flutter: an extended
/// `NavigationRail`.
///
/// ```dart
/// GlassTabSidebar(
///   destinations: const [
///     GlassTabDestination(
///       icon: Icon(CupertinoIcons.house),
///       label: Text('Home'),
///     ),
///     GlassTabDestination(
///       icon: Icon(CupertinoIcons.person),
///       label: Text('Profile'),
///       atSidebarEnd: true,
///     ),
///   ],
///   selectedIndex: tab,
///   onDestinationSelected: (index) => setState(() => tab = index),
/// )
/// ```
///
/// The sidebar lays its rows out for the width it is given and fills the
/// height. As wide as [railWidth] or narrower it is a rail: the button and
/// each row's pill are circles around their glyphs, and the titles are
/// gone. From [minimumWidth] it is the sidebar, and between the two the
/// titles open, so a shell that springs the width between them folds the
/// sidebar into its rail as [GlassTabScaffold] does; the scaffold's
/// [GlassColumnDivider] is the edge a hand drags. The rows start below the
/// safe area, a rail's below the window buttons on its side too
/// ([GlassWindowControls]), and scroll where the sidebar is too short for
/// them.
///
/// [header] stands above the rows and [footer] at the bottom, under the
/// destinations with [GlassTabDestination.atSidebarEnd]; both are as wide
/// as the rows, and fade and fold away toward the rail. The [action] is a
/// row after the tabs, or before them with
/// [GlassTabBarAction.atSidebarStart], its
/// [GlassTabBarAction.semanticLabel] for a title. With [quietSelection],
/// the selected row is a gray pill with its content in its own colors, as
/// UIKit draws it while the tab shows its list beside its pages.
///
/// With [glass], the sidebar draws a bar's glass filling its box; without,
/// the rows stand on what the shell draws under them, as the scaffold's
/// stand on the glass that morphs from its bar.
///
/// The tabs' rows are one Tab stop, entered at the selected row; the up
/// and down arrows move the focus to the row above or below and select its
/// tab, skipping disabled ones, Home and End to the first and the last,
/// and the focused row scrolls into view. Accessibility reads each row as
/// a button of one choice. The [action] and the button at the top are
/// stops of their own. UIKit's sidebar under a keyboard is not measured,
/// nor is its selected row on a light tint, which takes the prominent glass
/// button's rule for white or black content.
class GlassTabSidebar extends StatefulWidget {
  /// Creates a sidebar of [destinations].
  const GlassTabSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.quietSelection = false,
    this.header,
    this.footer,
    this.action,
    this.onToggle,
    this.toggleSemanticLabel,
    this.railWidth = GlassTabLayout.defaultRailWidth,
    this.minimumWidth,
    this.glass = true,
    super.key,
  });

  /// The tabs, each a row.
  final List<GlassTabDestination> destinations;

  /// The position of the selected tab in [destinations], or null for none.
  final int? selectedIndex;

  /// Called with the position of the tab a row selects, the selected one
  /// too; null disables the rows.
  final ValueChanged<int>? onDestinationSelected;

  /// Whether the selected row is a gray pill with its content in its own
  /// colors rather than a tint pill with content that reads on the tint.
  final bool quietSelection;

  /// What stands above the rows, such as the app's name, or null.
  final Widget? header;

  /// What stands at the bottom, such as the account, or null.
  final Widget? footer;

  /// The action of a row of its own, or null.
  final GlassTabBarAction? action;

  /// Called when the sidebar's button at the top is pressed, which hides
  /// the sidebar or folds it into the rail; null leaves the button out.
  final VoidCallback? onToggle;

  /// What accessibility reads for the sidebar's button; null reads Show
  /// Sidebar on the rail and Hide Sidebar elsewhere.
  final String? toggleSemanticLabel;

  /// The width at which, and below which, the sidebar is a rail.
  final double railWidth;

  /// The width from which the sidebar shows its titles, or null for the
  /// narrowest of [GlassTabLayout.defaultSidebarWidth].
  final double? minimumWidth;

  /// Whether the sidebar draws its own glass.
  final bool glass;

  // How far the rail's items drop below the window buttons on its side: the
  // rail is too narrow for its first item beside them, so it starts below
  // their row.
  static double _railDrop(BuildContext context) {
    final buttons = GlassEnvironment.of(context).windowControls;
    final reach = Directionality.of(context) == TextDirection.rtl
        ? buttons.right
        : buttons.left;
    if (reach == null) return 0;
    final top = MediaQuery.paddingOf(context).top;
    const center = GlassWindowControls.rowCenter;
    return math.max(0, (buttons.lineCenter ?? top + center) + center - top);
  }

  @override
  State<GlassTabSidebar> createState() => _GlassTabSidebarState();
}

class _GlassTabSidebarState extends State<GlassTabSidebar> {
  final _zones = InputZonesController<int>();
  final _scroll = ScrollController();
  final _layouts = ValueNotifier<int>(0);
  late final _frames = Listenable.merge([_scroll, _layouts]);
  final _host = GlobalKey(debugLabel: 'sidebar rows');
  final _rows = <int, GlobalKey>{};
  final _presses = <int, List<Interaction>>{};
  int? _revealed;

  @override
  void initState() {
    super.initState();
    _zones.addListener(_reveal);
  }

  @override
  void dispose() {
    _zones.dispose();
    _scroll.dispose();
    _layouts.dispose();
    super.dispose();
  }

  GlobalKey _rowKey(int index) => _rows.putIfAbsent(index, GlobalKey.new);

  // The rows' zones lie over the scroll view, not in it, so the focus does
  // not scroll a row into view by itself.
  void _reveal() {
    final zone = _zones.focusedZone;
    if (zone == _revealed) return;
    _revealed = zone;
    final row = zone == null ? null : _rows[zone]?.currentContext;
    if (row == null) return;
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      unawaited(Scrollable.ensureVisible(row, alignmentPolicy: policy));
    }
  }

  void _measured(double t, Size size) => _layouts.value++;

  InputZoneFrame? _frameOf(int index) {
    final host = _host.currentContext?.findRenderObject();
    final row = _rows[index]?.currentContext?.findRenderObject();
    if (host is! RenderBox ||
        row is! RenderBox ||
        !host.hasSize ||
        !row.hasSize ||
        !row.attached) {
      return null;
    }
    return InputZoneFrame(
      MatrixUtils.transformRect(
        row.getTransformTo(host),
        Offset.zero & row.size,
      ),
      borderRadius: BorderRadius.circular(_Regular.rowRadius),
    );
  }

  InputZone<int> _zone(int index) {
    final destination = widget.destinations[index];
    return InputZone<int>(
      id: index,
      interactions: _presses[index] ??= [
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => widget.onDestinationSelected?.call(index),
        ),
      ],
      enabled: widget.onDestinationSelected != null && destination.enabled,
      semantics: SemanticsProperties(
        label: destination.semanticLabel ?? glassLabelTextOf(destination.label),
        button: true,
        selected: index == widget.selectedIndex,
        inMutuallyExclusiveGroup: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = LayoutBuilder(builder: _build);
    if (!widget.glass) return rows;
    return GlassSurface(
      role: GlassRole.bar,
      shape: const LiquidRoundedSuperellipse(radius: 0),
      child: rows,
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    final tint = GlassDynamicColor.resolve(
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
      context,
    );
    final widths = _SideWidths(
      rail: widget.railWidth,
      minimum:
          widget.minimumWidth ?? GlassTabLayout.defaultSidebarWidth.minimum,
    );
    final width = constraints.maxWidth;
    final open = widths.openAt(width);
    final railInset = widths.railInset;
    final top =
        media.padding.top + GlassTabSidebar._railDrop(context) * (1 - open);
    final start = _lerp(railInset, _Regular.rowInset, open);
    final end = _lerp(railInset, _Regular.rowEndInset, open);
    final shape = (
      width: math.max<double>(0, width - start - end),
      iconCenter: _lerp(_Regular.railIconCenter, _Regular.rowIconCenter, open),
      titles: open,
      narrowest: widths.narrowestRow,
    );
    final destinations = widget.destinations;
    Widget tab(int index) {
      final selected = index == widget.selectedIndex;
      return SizedBox(
        key: _rowKey(index),
        height: _Regular.rowHeight,
        child: _rowLook(
          context,
          pill: _pillOf(
            selected: selected,
            tint: tint,
            quiet: widget.quietSelection,
          ),
          states: _zones.states(index),
          child: _SidebarRow(
            destination: destinations[index],
            selected: selected,
            quiet: widget.quietSelection,
            tint: tint,
            shape: shape,
          ),
        ),
      );
    }

    Widget slot(Widget child) => _SideSlot(
      open: open,
      width: math.max(shape.width, shape.narrowest),
      child: child,
    );
    final action = widget.action;
    final actionRow = action == null
        ? null
        : SizedBox(
            height: _Regular.rowHeight,
            child: RawGlassButton(
              onPressed: action.onPressed,
              semanticLabel: action.semanticLabel,
              builder: (context, details) => _rowLook(
                context,
                pill: null,
                states: details.statesListenable,
                heldStates: details.statesListenable == null
                    ? details.states
                    : const {},
                child: details.label,
              ),
              child: _SidebarRow(
                destination: GlassTabDestination(
                  icon: action.icon,
                  label: Text(action.semanticLabel),
                ),
                selected: false,
                quiet: widget.quietSelection,
                tint: tint,
                shape: shape,
              ),
            ),
          );
    final first = action?.atSidebarStart ?? false;
    final ends = [
      for (final (index, destination) in destinations.indexed)
        if (destination.atSidebarEnd) index,
    ];
    final leads = [
      for (final (index, destination) in destinations.indexed)
        if (!destination.atSidebarEnd) index,
    ];
    final header = widget.header;
    final footer = widget.footer;
    final onToggle = widget.onToggle;
    final strings = GlassLocalizations.of(context);
    final list = InputZones<int>(
      zones: [
        for (final index in [...leads, ...ends]) _zone(index),
      ],
      frameOf: _frameOf,
      frames: _frames,
      controller: _zones,
      arrows: InputZoneArrows.vertical,
      stops: InputZoneStops.one,
      current: widget.selectedIndex,
      activatesOnMove: true,
      excludeChildSemantics: false,
      child: KeyedSubtree(
        key: _host,
        // The sidebar's scroll is not the content's: the chrome's edges
        // follow the content alone.
        child: NotificationListener<Notification>(
          onNotification: (notification) {
            if (notification is ScrollMetricsNotification) _layouts.value++;
            return notification is ScrollNotification ||
                notification is ScrollMetricsNotification;
          },
          child: CustomScrollView(
            controller: _scroll,
            primary: false,
            slivers: [
              SliverPadding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  start,
                  top + _Regular.rowsTop,
                  end,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: MotionMeasure(
                    onSize: _measured,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (header != null) slot(header),
                        if (first) ?actionRow,
                        for (final index in leads) tab(index),
                        if (!first) ?actionRow,
                      ],
                    ),
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    start,
                    0,
                    end,
                    media.padding.bottom + _Regular.rowInset,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MotionMeasure(
                        onSize: _measured,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final index in ends) tab(index),
                            if (footer != null) slot(footer),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        list,
        if (onToggle != null)
          PositionedDirectional(
            top: top,
            end: _lerp(railInset, _Regular.circleEnd, open),
            child: _circle(
              onPressed: onToggle,
              semanticLabel:
                  widget.toggleSemanticLabel ??
                  (open == 0
                      ? strings.showSidebarLabel
                      : strings.hideSidebarLabel),
              color: tint,
              child: const GlassSidebarGlyph(),
            ),
          ),
      ],
    );
  }
}

// A header or footer of the sidebar: laid out no narrower than [width] and
// cut to the side, it fades and folds away with the titles toward the
// rail, where it is gone.
class _SideSlot extends StatelessWidget {
  const _SideSlot({
    required this.open,
    required this.width,
    required this.child,
  });

  final double open;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: open == 0,
    child: Opacity(
      opacity: open,
      child: ClipRect(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          heightFactor: open,
          child: OverflowBox(
            alignment: AlignmentDirectional.topStart,
            fit: OverflowBoxFit.deferToChild,
            minWidth: width,
            maxWidth: width,
            child: child,
          ),
        ),
      ),
    ),
  );
}

// Where a row of the side lays its glyph and title out at the side's
// width: its [width], the center of its glyph, how much its title shows,
// 0 on the rail, and the width the title lies on while it fades.
typedef _RowShape = ({
  double width,
  double iconCenter,
  double titles,
  double narrowest,
});

// A row's pill: the tint under the selected row, gray where the selection
// is quiet, nothing under the others.
Color? _pillOf({
  required bool selected,
  required Color tint,
  bool quiet = false,
}) => !selected
    ? null
    : quiet
    ? _Regular.quietPill
    : tint;

// A row of the side as it stands on the sidebar: its pill, and the press,
// hover and focus ring of [states], or of [heldStates] where its owner
// builds it again as they change.
Widget _rowLook(
  BuildContext context, {
  required Color? pill,
  required ValueListenable<Set<WidgetState>>? states,
  required Widget child,
  Set<WidgetState> heldStates = const {},
}) => GlassHighlightPaint.of(
  context,
  states: states,
  heldStates: heldStates,
  pressColor: _Regular.quietPill,
  shape: const LiquidRoundedSuperellipse(radius: _Regular.rowRadius),
  child: DecoratedBox(
    decoration: ShapeDecoration(
      color: pill,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(_Regular.rowRadius),
      ),
    ),
    child: child,
  ),
);

// What a row of the side shows over its pill: its glyph, its badge and
// its title as far as [shape] opens it. Accessibility reads the row from
// what holds it.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.destination,
    required this.selected,
    required this.quiet,
    required this.tint,
    required this.shape,
  });

  final GlassTabDestination destination;
  final bool selected;
  final bool quiet;
  final Color tint;
  final _RowShape shape;

  @override
  Widget build(BuildContext context) {
    final loud = selected && !quiet;
    final onTint = GlassTheme.contentColorOf(context)(tint);
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final style = scale
        .resolve(selected ? _Regular.selectedRow : _Regular.row)
        .copyWith(
          color: loud
              ? onTint
              : GlassDynamicColor.resolve(
                  GlassTheme.labelColorOf(context),
                  context,
                ),
        );
    final icon = selected
        ? destination.selectedIcon ?? destination.icon
        : destination.icon;
    final titles = shape.titles;
    final titleStart =
        shape.iconCenter + _Regular.rowTitleStart - _Regular.rowIconCenter;
    final badge = destination.badge;
    return ExcludeSemantics(
      child: Stack(
        children: [
          PositionedDirectional(
            start: shape.iconCenter - _Regular.rowIconBox / 2,
            top: (_Regular.rowHeight - _Regular.rowIconBox) / 2,
            width: _Regular.rowIconBox,
            height: _Regular.rowIconBox,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: loud ? onTint : tint,
                      size: _Regular.rowIconSize,
                    ),
                    child: ExcludeSemantics(child: icon),
                  ),
                ),
                if (badge != null && titles < 1)
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: ExcludeSemantics(
                      excluding: titles > 0,
                      child: Opacity(opacity: 1 - titles, child: badge),
                    ),
                  ),
              ],
            ),
          ),
          if (titles > 0)
            PositionedDirectional(
              start: titleStart,
              top: 0,
              bottom: 0,
              width: math.max(shape.width, shape.narrowest) - titleStart,
              child: Opacity(
                opacity: titles,
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: scale.apply(
                          DefaultTextStyle(
                            style: style,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: destination.label,
                          ),
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      badge,
                      const SizedBox(width: _Regular.rowEnd),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// The bottom accessory over the content on a regular width: its own glass
// capsule, as wide as its content and 20 a side.
class _RegularAccessory extends StatelessWidget {
  const _RegularAccessory({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
    role: GlassRole.bar,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _Regular.accessoryPadding,
      ),
      child: Center(widthFactor: 1, child: child),
    ),
  );
}

// The leading inset the chrome gives the tab shown: the side's width while
// it stands beside the content, moving with a hand on its edge or a fold.
class _SideInset extends InheritedWidget {
  const _SideInset({required this.inset, required super.child});

  final ValueListenable<double> inset;

  static ValueListenable<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SideInset>()?.inset;

  @override
  bool updateShouldNotify(_SideInset oldWidget) => inset != oldWidget.inset;
}

// A tab beside the side: its safe area takes the [settled] inset, and the
// tab shown is laid out as far toward the trailing side again as the
// side's live edge has gone past it, so its content follows the edge
// without a rebuild while a hand or a fold moves it.
class _TabInset extends StatelessWidget {
  const _TabInset({
    required this.settled,
    required this.live,
    required this.child,
  });

  final double settled;
  final bool live;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _InsetShift(
      live ? _SideInset.maybeOf(context) : null,
      settled: settled,
      rtl: Directionality.of(context) == TextDirection.rtl,
    ),
    child: child,
  );
}

// Lays a child out as far toward the trailing side as [live] stands past
// [settled], and that much narrower.
class _InsetShift extends SingleChildLayoutDelegate {
  _InsetShift(this.live, {required this.settled, required this.rtl})
    : super(relayout: live);

  final ValueListenable<double>? live;
  final double settled;
  final bool rtl;

  double get _shift => (live?.value ?? settled) - settled;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.max(0, constraints.maxWidth - _shift),
        height: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(rtl ? 0 : _shift, 0);

  @override
  bool shouldRelayout(_InsetShift oldDelegate) =>
      oldDelegate.live != live ||
      oldDelegate.settled != settled ||
      oldDelegate.rtl != rtl;
}

// A plain tab beside the sidebar: its leading safe area and its bars start
// past the sidebar, as UIKit's content beside a tab sidebar gets the
// sidebar's width as its leading safe area.
class _Beside extends StatelessWidget {
  const _Beside({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return MediaQuery(
      data: inset == 0
          ? media
          : media.copyWith(
              padding: padding.copyWith(
                left: ltr ? math.max(padding.left, inset) : null,
                right: ltr ? null : math.max(padding.right, inset),
              ),
            ),
      child: GlassBarInset(leading: inset, child: child),
    );
  }
}
