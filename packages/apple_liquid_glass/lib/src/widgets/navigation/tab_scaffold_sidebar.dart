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
  static const double rowEndInset =
      GlassTabScaffold.sidebarWidth - rowInset - rowWidth;

  // The rail: its circles centered in it, the hide button's and each row's
  // pill; a row's title fades with the side's width between the sidebar's
  // minimum and the rail's, so a fold's spring dissolves it before the edge
  // cuts it, and lies on the sidebar's narrowest row's width while it does.
  // The package's own.
  static const double railInset = (GlassTabScaffold.railWidth - circle) / 2;
  static const double railIconCenter = circle / 2;
  static const double narrowestRow =
      GlassTabScaffold.minimumSidebarWidth - rowInset - rowEndInset;

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
    required this.sidebarWidth,
    required this.maxSidebarWidth,
    required this.onSidebarWidth,
    required this.onSidebarReset,
    required this.resizable,
    required this.quiet,
    required this.look,
    required this.semanticLabel,
    required this.accessory,
    required this.action,
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
  // The sidebar's width as drawn, within its limits for [size].
  final double sidebarWidth;
  final double maxSidebarWidth;
  final ValueChanged<double> onSidebarWidth;
  final VoidCallback onSidebarReset;
  final bool resizable;
  final bool quiet;
  final GlassTabBarStyle? look;
  final String? semanticLabel;
  final Widget? accessory;
  final GlassTabBarAction? action;
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
  late final _side = MotionValue<double>(
    GlassTabScaffold.sidebarWidth,
    clock: _clock,
  );
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
    () => _shareOf(_down) * _openOf(_side.value),
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
    return beside ? side : math.min(side, GlassTabScaffold.railWidth);
  }, clock: _clock);

  // Sends the side to the rail's width or the sidebar's: on the fold's
  // spring when the form turns, at once otherwise. A hand on the edge
  // moves it alone.
  void _aimSide({required bool rail, required double width}) {
    final to = rail ? GlassTabScaffold.railWidth : width;
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

  // The side's forms, narrowest first: hidden (the bar at the top), the
  // rail and the sidebar.
  List<ColumnForm> get _forms => [
    const ColumnForm(width: 0),
    const ColumnForm(width: GlassTabScaffold.railWidth),
    ColumnForm(
      width: widget.sidebarWidth,
      min: GlassTabScaffold.minimumSidebarWidth,
      max: widget.maxSidebarWidth,
    ),
  ];

  int get _form => !widget.sidebarShown
      ? 0
      : widget.rail
      ? 1
      : 2;

  double get _formWidth => switch (_form) {
    0 => 0,
    1 => GlassTabScaffold.railWidth,
    _ => widget.sidebarWidth,
  };

  // Writes a change of the side's form, or of the sidebar's width.
  void _go(int from, int to, double width) {
    if (to == from) {
      if (to == 2 && width != widget.sidebarWidth) widget.onSidebarWidth(width);
    } else if (to == 0) {
      widget.onSidebar(false);
    } else if (from == 0) {
      widget.onSidebar(true);
    } else {
      widget.onRail(to == 1);
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
    if (to > 0) {
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
    if (fold.form == 2 && fold.width != fold.forms.last.width) {
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
            min: 0,
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
    final layout = _BarLayout(
      context,
      items: widget.items,
      iconOnly: widget.iconOnly,
      selected: widget.selected,
      maxWidth: size.width - 2 * _Regular.barMargin - besideBar,
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
              child: widget.child,
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
                            _Sidebar(
                              items: widget.items,
                              selected: widget.selected,
                              quiet: widget.quiet,
                              onSelected: widget.onSelected,
                              onHide: () => widget.onSidebar(false),
                              action: action,
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

// How far the side has opened from the rail to the sidebar's narrowest, 0
// to 1, at [width].
double _openOf(double width) =>
    ((width - GlassTabScaffold.railWidth) /
            (GlassTabScaffold.minimumSidebarWidth - GlassTabScaffold.railWidth))
        .clamp(0.0, 1.0);

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

// The content of the tab sidebar: its button at the top, then a row per
// tab, the selected one a tint pill with white content, or a gray pill with
// the content in its own colors while the selected tab shows its list
// column ([quiet]). As wide as the rail, the button and each row's pill are
// circles around their glyphs, and the titles are gone; between the rail
// and the sidebar they open.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.quiet,
    required this.onSelected,
    required this.onHide,
    required this.action,
  });

  final List<GlassTabDestination> items;
  final int? selected;
  final bool quiet;
  final ValueChanged<int> onSelected;
  final VoidCallback onHide;
  final GlassTabBarAction? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final tint = GlassDynamicColor.resolve(
        GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
        context,
      );
      final width = constraints.maxWidth;
      final open = _openOf(width);
      final start = _lerp(_Regular.railInset, _Regular.rowInset, open);
      final end = _lerp(_Regular.railInset, _Regular.rowEndInset, open);
      final row = (
        width: math.max<double>(0, width - start - end),
        iconCenter: _lerp(
          _Regular.railIconCenter,
          _Regular.rowIconCenter,
          open,
        ),
        titles: open,
      );
      final action = this.action;
      return Stack(
        children: [
          // The sidebar's scroll is not the content's: the chrome's edges
          // follow the content alone.
          NotificationListener<Notification>(
            onNotification: (notification) =>
                notification is ScrollNotification ||
                notification is ScrollMetricsNotification,
            child: ListView(
              primary: false,
              padding: EdgeInsetsDirectional.fromSTEB(
                start,
                media.padding.top + _Regular.rowsTop,
                end,
                media.padding.bottom + _Regular.rowInset,
              ),
              itemExtent: _Regular.rowHeight,
              children: [
                for (final (index, destination) in items.indexed)
                  _SidebarRow(
                    destination: destination,
                    selected: index == selected,
                    quiet: quiet,
                    tint: tint,
                    shape: row,
                    onPressed: () => onSelected(index),
                  ),
                if (action != null)
                  _SidebarRow(
                    destination: GlassTabDestination(
                      icon: action.icon,
                      label: Text(action.semanticLabel),
                    ),
                    selected: false,
                    quiet: quiet,
                    tint: tint,
                    shape: row,
                    onPressed: action.onPressed,
                  ),
              ],
            ),
          ),
          PositionedDirectional(
            top: media.padding.top,
            end: _lerp(_Regular.railInset, _Regular.circleEnd, open),
            child: _circle(
              onPressed: onHide,
              semanticLabel: GlassLocalizations.of(context).hideSidebarLabel,
              color: tint,
              child: const GlassSidebarGlyph(),
            ),
          ),
        ],
      );
    },
  );
}

// Where a row of the side lays its glyph and title out at the side's
// width: its [width], the center of its glyph, and how much its title
// shows, 0 on the rail.
typedef _RowShape = ({double width, double iconCenter, double titles});

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.destination,
    required this.selected,
    required this.quiet,
    required this.tint,
    required this.shape,
    required this.onPressed,
  });

  final GlassTabDestination destination;
  final bool selected;
  final bool quiet;
  final Color tint;
  final _RowShape shape;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final loud = selected && !quiet;
    const white = Color(0xFFFFFFFF);
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final style = scale
        .resolve(selected ? _Regular.selectedRow : _Regular.row)
        .copyWith(
          color: loud
              ? white
              : GlassDynamicColor.resolve(
                  GlassTheme.labelColorOf(context),
                  context,
                ),
        );
    final pill = !selected
        ? null
        : quiet
        ? _Regular.quietPill
        : tint;
    final icon = selected
        ? destination.selectedIcon ?? destination.icon
        : destination.icon;
    final titles = shape.titles;
    final titleStart =
        shape.iconCenter + _Regular.rowTitleStart - _Regular.rowIconCenter;
    final badge = destination.badge;
    return RawGlassButton(
      onPressed: destination.enabled ? onPressed : null,
      builder: (context, details) => DecoratedBox(
        decoration: ShapeDecoration(
          color: pill,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(_Regular.rowRadius),
          ),
        ),
        child: details.label,
      ),
      child: _tabSemantics(
        destination,
        selected: selected,
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
                        color: loud ? white : tint,
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
                width:
                    math.max(shape.width, _Regular.narrowestRow) - titleStart,
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
