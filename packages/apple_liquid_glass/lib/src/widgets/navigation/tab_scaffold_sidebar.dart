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
  static const double rowIconBox = 31;
  static const double rowIconCenter = 30;
  static const double rowTitleStart = 54;
  static const double rowIconSize = 24;
  static final double rowEndInset =
      GlassTabLayout.defaultSidebarWidth.preferred - rowInset - rowWidth;
  static final rowsPadding = EdgeInsetsDirectional.fromSTEB(
    rowInset,
    rowsTop,
    rowEndInset,
    rowInset,
  );

  // The rail centers its circles, the hide button's and each row's pill; a
  // row's title fades with the side's width between the sidebar's minimum
  // and the rail's, so a fold's spring dissolves it before the edge cuts
  // it, and lies on the sidebar's narrowest row's width while it does
  // (_SideWidths). The package's own.

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
    required this.button,
    required this.onSidebarWidth,
    required this.onSidebarReset,
    required this.resizable,
    required this.margin,
    required this.opaque,
    required this.quiet,
    required this.look,
    required this.semanticLabel,
    required this.accessory,
    required this.action,
    required this.header,
    required this.footer,
    required this.rowBuilder,
    required this.sidebarStyle,
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
  // Whether the hidden side leaves its button alone on the content's top
  // line, where the bar at the top would stand.
  final bool button;
  final ValueChanged<double> onSidebarWidth;
  final VoidCallback onSidebarReset;
  final bool resizable;
  // How far a floating side stands from the window's edges and the
  // content, 0 where it touches them.
  final double margin;
  // Whether the side is a flush panel, an opaque fill the glass fades into.
  final bool opaque;
  final bool quiet;
  final GlassTabBarStyle? look;
  final String? semanticLabel;
  final Widget? accessory;
  final GlassTabBarAction? action;
  final Widget? header;
  final Widget? footer;
  final GlassTabSidebarRowBuilder? rowBuilder;
  final GlassTabSidebarStyle? sidebarStyle;
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
  late MotionSelection<double> _barLift;
  late MotionSelection<double> _barOpacity;
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
  (bool, bool, double)? _insetFor;
  // The hand on the side's edge, through the side's forms.
  ColumnFold? _fold;
  bool? _rail;

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
    final left = place.rtl
        ? place.size.width - place.margin - width
        : place.margin;
    return math.max(
      (left - place.bar.left).abs(),
      (width - place.bar.width).abs(),
    );
  }

  double get _downSpan {
    final place = _place;
    if (place == null) return 0;
    return math.max(
      (place.bar.top - place.margin).abs(),
      (place.size.height - 2 * place.margin - place.bar.height).abs(),
    );
  }

  // How far the bar of [place] shows: a page that hides the tab bar lifts
  // the bar away, and leaves a button alone in place.
  double _barShown(_Place place) => place.button ? 1 : _hiding.shown.value;

  // How far up the bar of [place] goes to hide: out of the window.
  static double _liftOf(_Place place) =>
      place.button ? 0 : place.bar.top + place.bar.height;

  // The glass at the progress of [_across] and [_down] between the bar
  // and the side of [place].
  MotionSelection<GlassFrame> _frameAt(_Place place) => MotionSelection(() {
    final bar = place.bar;
    final size = place.size;
    final margin = place.margin;
    final across = _across.value;
    final down = _down.value;
    final side = _side.value;
    final width = bar.width + (side - bar.width) * across;
    final height = bar.height + (size.height - 2 * margin - bar.height) * down;
    final start = place.rtl ? size.width - margin - side : margin;
    final left = bar.left + (start - bar.left) * across;
    final grown = _shareOf(_down);
    final shown = _barShown(place);
    final tint = place.tint;
    return GlassFrame(
      shape: LiquidRoundedSuperellipse(
        radius: math.min(
          _lerp(_Regular.barRadius, place.radius, grown),
          math.min(width, height) / 2,
        ),
      ),
      rect: Rect.fromLTWH(
        left,
        bar.top +
            (margin - bar.top) * down +
            (shown - 1) * _liftOf(place) * (1 - grown),
        width,
        height,
      ),
      tint: tint,
      tintAmount: tint == null ? 1 : grown,
      opacity: (shown + (1 - shown) * grown) * (place.opaque ? 1 - grown : 1),
    );
  }, clock: _clock);

  MotionSelection<double> _barLiftAt(_Place place) => MotionSelection(
    () => (_barShown(place) - 1) * _liftOf(place) * (1 - _shareOf(_down)),
    clock: _clock,
  );

  MotionSelection<double> _barOpacityAt(_Place place) => MotionSelection(
    () => _barShown(place) * (1 - _shareOf(_across)),
    clock: _clock,
  );

  // The window buttons the content's bars start past while the side leaves
  // its button at [button] on their row: the button, at the edge it stands
  // at, and the window's own at the other edge where their line runs
  // through the row.
  GlassWindowControls _buttonReserve(Rect button, {required bool rtl}) {
    final controls = GlassEnvironment.of(context).windowControls;
    final line =
        controls.lineCenter ??
        MediaQuery.paddingOf(context).top + GlassWindowControls.rowCenter;
    final onRow =
        line >= button.top && line <= button.top + GlassNavigationBar.height;
    return GlassWindowControls(
      left: rtl ? (onRow ? controls.left : null) : button.right,
      right: rtl
          ? widget.size.width - button.left
          : (onRow ? controls.right : null),
      lineCenter: button.center.dy,
    );
  }

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
    required double margin,
  }) => MotionSelection(() {
    if (!placed) return 0.0;
    final side = _side.value;
    return (beside ? side : math.min(side, widget.railWidth)) + 2 * margin;
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
        delegate: _SideLayout(
          _side,
          rtl: rtl,
          margin: widget.margin,
          edge: true,
        ),
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
    final button = widget.button;
    final top =
        media.padding.top + (placed || button ? 0 : _Regular.contentDrop);
    final accessory = widget.accessory;
    final bottom = accessory == null
        ? media.padding.bottom
        : math.max(
            media.padding.bottom,
            _Regular.accessoryInset + _Regular.accessoryHeight,
          );
    final action = widget.action;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final _BarLayout? layout;
    final Rect bar;
    if (button) {
      layout = null;
      final rowTop = BarRoom.rowTopOf(context);
      final sides = BarRoom.sidesOf(
        context,
        inset: navigationSideInset,
        top: rowTop,
        height: GlassNavigationBar.height,
      );
      bar = Rect.fromLTWH(
        rtl ? size.width - sides.right - _Regular.circle : sides.left,
        rowTop,
        _Regular.circle,
        _Regular.circle,
      );
    } else {
      final besideBar = action == null
          ? 0.0
          : _Regular.actionGap + _Regular.circle;
      final sides = BarRoom.sidesOf(context, inset: _Regular.barMargin);
      final row = _BarLayout(
        context,
        items: widget.items,
        iconOnly: widget.iconOnly,
        selected: widget.selected,
        maxWidth:
            size.width - 2 * math.max(sides.left, sides.right) - besideBar,
      );
      layout = row;
      final start = (size.width - row.width - besideBar) / 2;
      bar = Rect.fromLTWH(
        rtl ? size.width - start - row.width : start,
        media.padding.top,
        row.width,
        _Regular.barHeight,
      );
    }
    final sideLook = (widget.sidebarStyle ?? const GlassTabSidebarStyle())
        .merge(GlassTabSidebarStyle.maybeOf(context));
    final place = (
      bar: bar,
      size: size,
      rtl: rtl,
      margin: widget.margin,
      radius: widget.margin > 0 ? _floatingRadius(context, widget.margin) : 0.0,
      opaque: widget.opaque,
      tint: widget.opaque || sideLook.backgroundColor == null
          ? null
          : GlassDynamicColor.resolve(sideLook.backgroundColor!, context),
      button: button,
    );
    if (place != _place) {
      _place = place;
      _frame = _frameAt(place);
      _barLift = _barLiftAt(place);
      _barOpacity = _barOpacityAt(place);
    }
    final margin = widget.margin;
    if ((placed, beside, margin) != _insetFor) {
      _insetFor = (placed, beside, margin);
      _inset = _insetAt(placed: placed, beside: beside, margin: margin);
    }
    _aimSide(rail: rail, width: widget.sidebarWidth);
    _aim(toSidebar: shown, beside: beside);
    final withBar = !shown || !_morphed;
    final withSidebar = shown || !_morphed;
    final over = !beside && withSidebar && (!rail || !_sized);
    return GlassChrome(
      edges: ChromeEdges(
        top: placed || button ? ChromeBar.none : ChromeBar.floating,
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
              // first: the window buttons stand in the bar's row. Beside
              // the side's button alone they start past it.
              child: GlassEnvironmentOverride(
                windowControls: placed
                    ? null
                    : button
                    ? _buttonReserve(bar, rtl: rtl)
                    : GlassWindowControls.none,
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
          if (widget.opaque)
            Positioned.fill(
              key: const ValueKey('panel'),
              child: CustomPaint(
                painter: _FlushPanel(
                  _frame,
                  _sidebarOpacity,
                  fill: GlassDynamicColor.resolve(
                    sideLook.backgroundColor ?? widget.background,
                    context,
                  ),
                  line: GlassDynamicColor.resolve(
                    sideLook.separatorColor ?? GlassColors.separator,
                    context,
                  ),
                  hairline: 1 / GlassTraits.of(context).viewPixelRatio,
                  rtl: rtl,
                ),
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
                          layout == null
                              ? _SidebarButton(
                                  onPressed: () => widget.onSidebar(true),
                                  look: widget.look,
                                )
                              : _TopBar(
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
                        delegate: _SideLayout(
                          _side,
                          rtl: rtl,
                          margin: widget.margin,
                        ),
                        child: MotionTransition(
                          opacity: _sidebarOpacity,
                          child: _leaving(
                            !shown,
                            GlassTabSidebar(
                              destinations: widget.items,
                              selectedIndex: widget.selected,
                              onDestinationSelected: widget.onSelected,
                              quietSelection: widget.quiet,
                              style: widget.sidebarStyle,
                              header: widget.header,
                              footer: widget.footer,
                              rowBuilder: widget.rowBuilder,
                              action: action,
                              onToggle: widget.toggle?.onPressed,
                              toggleSemanticLabel: widget.toggle?.semanticLabel,
                              railWidth: widget.railWidth,
                              minimumWidth: widget.minSidebarWidth,
                              panel: null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (action != null && layout != null && withBar)
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

  // How far a circle [extent] wide stands from the rail's sides.
  double railInset(double extent) => (rail - extent) / 2;

  // The width a row's title lies on while it fades, in [room].
  double narrowestRow(EdgeInsetsDirectional room) =>
      minimum - room.start - room.end;
}

typedef _SideToggle = ({VoidCallback onPressed, String semanticLabel});

double _lerp(double a, double b, double t) => a + (b - a) * t;

// Lays the side's content out at the side's [width], at the edge it stands
// at, or with [edge] the divider centered on the side's trailing edge.
class _SideLayout extends SingleChildLayoutDelegate {
  _SideLayout(
    this.width, {
    required this.rtl,
    required this.margin,
    this.edge = false,
  }) : super(relayout: width);

  final ValueListenable<double> width;
  final bool rtl;
  final double margin;
  final bool edge;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: edge ? GlassColumnDivider.width : math.max(0, width.value),
        height: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final start = margin + (edge ? width.value - childSize.width / 2 : 0.0);
    return Offset(rtl ? size.width - start - childSize.width : start, 0);
  }

  @override
  bool shouldRelayout(_SideLayout oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.rtl != rtl ||
      oldDelegate.margin != margin ||
      oldDelegate.edge != edge;
}

// Where the chrome lays the glass out: the bar's rect, the room the side
// fills the height of less its margin, the edge the side stands at, the
// side's corner radius, whether the glass fades into a flush panel's fill,
// the tint the glass takes on as it grows into the side, and whether the
// bar is the side's button alone.
typedef _Place = ({
  Rect bar,
  Size size,
  bool rtl,
  double margin,
  double radius,
  bool opaque,
  Color? tint,
  bool button,
});

// The corner radius of a side [margin] from the window's edges: concentric
// with the window's where they are known, the bar's elsewhere.
double _floatingRadius(BuildContext context, double margin) {
  final window = GlassEnvironment.of(context).windowCornerRadius;
  return window == null ? _Regular.barRadius : math.max(0, window - margin);
}

// A flush side: its opaque fill over the glass's frame and a hairline on
// the content's side, both as present as the side has grown.
class _FlushPanel extends CustomPainter {
  _FlushPanel(
    this.frame,
    this.grown, {
    required this.fill,
    required this.line,
    required this.hairline,
    required this.rtl,
  }) : super(repaint: Listenable.merge([frame, grown]));

  final ValueListenable<GlassFrame> frame;
  final ValueListenable<double> grown;
  final Color fill;
  final Color line;
  final double hairline;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = frame.value.rect;
    final present = grown.value;
    if (rect == null || present <= 0) return;
    Paint paint(Color color) =>
        Paint()..color = color.withValues(alpha: color.a * present);
    canvas
      ..drawRect(rect, paint(fill))
      ..drawRect(
        Rect.fromLTWH(
          rtl ? rect.left : rect.right - hairline,
          rect.top,
          hairline,
          rect.height,
        ),
        paint(line),
      );
  }

  @override
  bool shouldRepaint(_FlushPanel oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.grown != grown ||
      oldDelegate.fill != fill ||
      oldDelegate.line != line ||
      oldDelegate.hairline != hairline ||
      oldDelegate.rtl != rtl;
}

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

// The sidebar's button standing alone for the hidden side, on the glass
// circle the side morphs from.
class _SidebarButton extends StatelessWidget {
  const _SidebarButton({required this.onPressed, required this.look});

  final VoidCallback onPressed;
  final GlassTabBarStyle? look;

  @override
  Widget build(BuildContext context) => RawGlassButton(
    onPressed: onPressed,
    semanticLabel: GlassLocalizations.of(context).showSidebarLabel,
    builder: (context, details) => Center(child: details.label),
    child: IconTheme.merge(
      data: IconThemeData(
        color: _foreground(context, look, selected: false),
        size: _Regular.glyphSize,
      ),
      child: const GlassSidebarGlyph(),
    ),
  );
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
/// The rows are [GlassTabSidebarRow]s unless [rowBuilder] draws them an
/// app's own way: the sidebar keeps laying them out, folding them into the
/// rail and taking their input, and the builder draws what stands in each.
///
/// The sidebar stands on its [panel], which fills its box: glass by
/// default, an opaque fill with a hairline on its trailing side
/// ([GlassTabSidebarPanel.flush]), or glass with rounded corners that a
/// shell stands away from the window's edges
/// ([GlassTabSidebarPanel.floating]). Without one the rows stand on what
/// the shell draws under them, as the scaffold's stand on the glass that
/// morphs from its bar.
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
    this.style,
    this.rowBuilder,
    this.header,
    this.footer,
    this.action,
    this.onToggle,
    this.toggleSemanticLabel,
    this.railWidth = GlassTabLayout.defaultRailWidth,
    this.minimumWidth,
    this.panel = GlassTabSidebarPanel.glass,
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

  /// The look of the rows, over the theme's [GlassTabSidebarStyle] and the
  /// defaults; the sidebar lays its rows out by its row height and padding.
  final GlassTabSidebarStyle? style;

  /// Builds each row, the action's too, in place of a [GlassTabSidebarRow];
  /// null for that row.
  ///
  /// A row is as tall as the builder makes it and as wide as the sidebar
  /// within its insets, a circle's width on the rail. The sidebar makes it
  /// one button: a tap or the keys select its tab, and accessibility reads
  /// it as the tab. The builder draws the selection, the press, hover and
  /// focus of [GlassTabSidebarRowDetails.states], and the fold of
  /// [GlassTabSidebarRowDetails.open]; what it draws is read too unless it
  /// is excluded from semantics, as [GlassTabSidebarRow] excludes the title
  /// the tab is read by. A control of this package inside a row takes its
  /// own touches and leaves the tab unselected, as a button in a UIKit cell
  /// does; a Flutter gesture detector sees a touch as the row does.
  final GlassTabSidebarRowBuilder? rowBuilder;

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

  /// What the sidebar stands on, filling its box, or null for nothing: a
  /// floating panel's corners are concentric with the window's
  /// ([GlassEnvironment.windowCornerRadius]) at
  /// [GlassTabLayout.defaultSidebarMargin] from its edges, where they are
  /// known. [GlassTabSidebarStyle.backgroundColor] fills a
  /// flush panel, the system background by default, and tints a glass one.
  final GlassTabSidebarPanel? panel;

  /// A style from plain values; a null value leaves the field to the theme,
  /// then the default.
  static GlassTabSidebarStyle styleFrom({
    Color? backgroundColor,
    Color? separatorColor,
    Color? indicatorColor,
    Color? quietIndicatorColor,
    Color? foregroundColor,
    Color? selectedForegroundColor,
    Color? iconColor,
    Color? selectedIconColor,
    TextStyle? textStyle,
    TextStyle? selectedTextStyle,
    double? iconSize,
    double? rowHeight,
    EdgeInsetsDirectional? padding,
  }) {
    WidgetStateProperty<T?>? selectable<T>(T? any, T? selected) =>
        any == null && selected == null
        ? null
        : WidgetStateMapper<T?>({
            WidgetState.selected: selected,
            WidgetState.any: any,
          });
    return GlassTabSidebarStyle(
      backgroundColor: backgroundColor,
      separatorColor: separatorColor,
      indicatorColor: indicatorColor,
      quietIndicatorColor: quietIndicatorColor,
      foregroundColor: selectable(foregroundColor, selectedForegroundColor),
      iconColor: selectable(iconColor, selectedIconColor),
      textStyle: selectable(textStyle, selectedTextStyle),
      iconSize: iconSize,
      rowHeight: rowHeight,
      padding: padding,
    );
  }

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
  final _actionStates = WidgetStatesController();
  int? _revealed;
  double _rowRadius = _Regular.rowHeight / 2;

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
    _actionStates.dispose();
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
      borderRadius: BorderRadius.circular(_rowRadius),
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
    final panel = widget.panel;
    if (panel == null) return rows;
    final look = (widget.style ?? const GlassTabSidebarStyle()).merge(
      GlassTabSidebarStyle.maybeOf(context),
    );
    final fill = look.backgroundColor;
    if (panel == GlassTabSidebarPanel.flush) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: GlassDynamicColor.resolve(
            fill ?? GlassColors.systemBackground,
            context,
          ),
        ),
        child: CustomPaint(
          foregroundPainter: _Hairline(
            color: GlassDynamicColor.resolve(
              look.separatorColor ?? GlassColors.separator,
              context,
            ),
            width: 1 / GlassTraits.of(context).viewPixelRatio,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
          child: rows,
        ),
      );
    }
    return GlassSurface(
      role: GlassRole.bar,
      shape: LiquidRoundedSuperellipse(
        radius: panel == GlassTabSidebarPanel.floating
            ? _floatingRadius(context, GlassTabLayout.defaultSidebarMargin)
            : 0,
      ),
      glass: Glass.regular(
        tint: fill == null ? null : GlassDynamicColor.resolve(fill, context),
      ),
      child: rows,
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    final tint = GlassDynamicColor.resolve(
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
      context,
    );
    final look = (widget.style ?? const GlassTabSidebarStyle()).merge(
      GlassTabSidebarStyle.maybeOf(context),
    );
    final room = look.room;
    _rowRadius = look.height / 2;
    final widths = _SideWidths(
      rail: widget.railWidth,
      minimum:
          widget.minimumWidth ?? GlassTabLayout.defaultSidebarWidth.minimum,
    );
    final width = constraints.maxWidth;
    final open = widths.openAt(width);
    final railInset = widths.railInset(look.height);
    final top =
        media.padding.top + GlassTabSidebar._railDrop(context) * (1 - open);
    final start = _lerp(railInset, room.start, open);
    final end = _lerp(railInset, room.end, open);
    final openWidth = widths.narrowestRow(room);
    final destinations = widget.destinations;
    final rowBuilder = widget.rowBuilder ?? _defaultRow;
    Widget tab(int index) => KeyedSubtree(
      key: _rowKey(index),
      child: rowBuilder(
        context,
        GlassTabSidebarRowDetails(
          destination: destinations[index],
          index: index,
          selected: index == widget.selectedIndex,
          quietSelection: widget.quietSelection,
          states: _zones.states(index),
          open: open,
          openWidth: openWidth,
          style: look,
        ),
      ),
    );

    Widget slot(Widget child) => _SideSlot(
      open: open,
      width: math.max(width - start - end, openWidth),
      child: child,
    );
    final action = widget.action;
    final actionRow = action == null
        ? null
        : RawGlassButton(
            onPressed: action.onPressed,
            semanticLabel: action.semanticLabel,
            statesController: _actionStates,
            builder: (context, details) => details.label,
            child: rowBuilder(
              context,
              GlassTabSidebarRowDetails(
                destination: GlassTabDestination(
                  icon: action.icon,
                  label: Text(action.semanticLabel),
                ),
                index: null,
                selected: false,
                quietSelection: widget.quietSelection,
                states: _actionStates,
                open: open,
                openWidth: openWidth,
                style: look,
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
    final rowsTop = top + room.top;
    final rowsBottom = media.padding.bottom + room.bottom;
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
                  rowsTop,
                  end,
                  rowsBottom,
                ),
                // The end group stands at the bottom of a sidebar tall
                // enough for both groups: the column is at least as tall as
                // the room between the paddings, and asks its rows for no
                // intrinsic height.
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight.isFinite
                          ? math.max(
                              0,
                              constraints.maxHeight - rowsTop - rowsBottom,
                            )
                          : 0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MotionMeasure(
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
            end: _lerp(
              widths.railInset(_Regular.circle),
              _Regular.circleEnd,
              open,
            ),
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

// A flush sidebar's hairline along its trailing side.
class _Hairline extends CustomPainter {
  const _Hairline({
    required this.color,
    required this.width,
    required this.rtl,
  });

  final Color color;
  final double width;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromLTWH(rtl ? 0 : size.width - width, 0, width, size.height),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_Hairline oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.rtl != rtl;
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

Widget _defaultRow(
  BuildContext context,
  GlassTabSidebarRowDetails details,
) => GlassTabSidebarRow(details: details);

/// Builds a row of a [GlassTabSidebar] from its [details].
typedef GlassTabSidebarRowBuilder = Widget Function(
  BuildContext context,
  GlassTabSidebarRowDetails details,
);

/// A row of a [GlassTabSidebar] as its [GlassTabSidebar.rowBuilder] draws
/// it.
@immutable
final class GlassTabSidebarRowDetails {
  /// Describes a row.
  const GlassTabSidebarRowDetails({
    required this.destination,
    required this.index,
    required this.selected,
    required this.quietSelection,
    required this.states,
    required this.open,
    required this.openWidth,
    this.style = const GlassTabSidebarStyle(),
  });

  /// The tab the row shows; on the action's row, the action's icon with its
  /// semantic label for a title.
  final GlassTabDestination destination;

  /// The tab's position in [GlassTabSidebar.destinations], or null on the
  /// action's row.
  final int? index;

  /// Whether the row's tab is the selected one.
  final bool selected;

  /// Whether the selection is quiet ([GlassTabSidebar.quietSelection]).
  final bool quietSelection;

  /// The row's states as they change: pressed, hovered, focused, disabled.
  /// The sidebar does not build the row again as they change, so what
  /// follows them listens to them.
  final ValueListenable<Set<WidgetState>> states;

  /// How far the sidebar stands open: 0 on the rail, where the row is a
  /// circle's width, 1 from [GlassTabSidebar.minimumWidth] up, and between
  /// them while a fold springs the sidebar's width.
  final double open;

  /// The row's width at the narrowest sidebar with titles: content laid out
  /// at it and clipped by the row folds into the rail without reflowing, as
  /// the default row's title does.
  final double openWidth;

  /// The sidebar's style, its own over the theme's and the defaults, which
  /// a [GlassTabSidebarRow] draws the row in.
  final GlassTabSidebarStyle style;
}

/// The look of a [GlassTabSidebar]'s panel and rows, like Flutter's
/// `ButtonStyle`.
///
/// UIKit: the sidebar's `UIListContentConfiguration`s. SwiftUI: none.
/// Flutter: `NavigationRailThemeData`, `NavigationDrawerThemeData`.
///
/// A sidebar looks a field up in its own style, then in the theme's, then
/// in its defaults; [foregroundColor], [iconColor] and [textStyle] are
/// resolved per row, with [WidgetState.selected] on the selected one and
/// [WidgetState.disabled] on a disabled one, and a property that gives null
/// for a state leaves that state to the next one.
///
/// The defaults are UIKit's (tab sidebar passport): rows 44 tall, their
/// glyphs 24 in the accent, titles 17 points, medium where selected, the
/// selected row a pill of the accent, or a gray one while quiet. The
/// sidebar lays its rows out by the [rowHeight] and [padding] of its own
/// style: the rail centers its rows as circles [rowHeight] wide.
@immutable
class GlassTabSidebarStyle extends GlassStyle<GlassTabSidebarStyle> {
  /// Creates a style.
  const GlassTabSidebarStyle({
    this.backgroundColor,
    this.separatorColor,
    this.indicatorColor,
    this.quietIndicatorColor,
    this.foregroundColor,
    this.iconColor,
    this.textStyle,
    this.iconSize,
    this.rowHeight,
    this.padding,
  });

  /// The theme's [GlassTabSidebarStyle] at [context], or null without one:
  /// the look between a sidebar's own style and its defaults.
  static GlassTabSidebarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassTabSidebarStyle>(context);

  /// What the sidebar's panel is filled with: the opaque fill of a
  /// [GlassTabSidebarPanel.flush] panel, the scaffold's background by
  /// default, and a tint over a glass one, which the bar's glass crosses
  /// into as it morphs into the sidebar, none by default.
  final Color? backgroundColor;

  /// The hairline a [GlassTabSidebarPanel.flush] panel draws on the
  /// content's side; [GlassColors.separator] by default.
  final Color? separatorColor;

  /// The pill of the selected row; the accent by default.
  ///
  /// On an opaque pill the row's content takes the color that reads on it
  /// ([GlassThemeData.primaryContrastingColor] on the accent); on a
  /// translucent one, a wash, it keeps its own colors, as on the quiet
  /// pill.
  final Color? indicatorColor;

  /// The pill of the selected row while the selection is quiet
  /// ([GlassTabSidebar.quietSelection]); UIKit's gray by default.
  final Color? quietIndicatorColor;

  /// The color of a row's title: [GlassColors.label] by default, and on an
  /// opaque pill of the selected row the color that reads on it.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The color of a row's glyph: the accent by default, and on an opaque
  /// pill of the selected row the color that reads on it.
  final WidgetStateProperty<Color?>? iconColor;

  /// The text style of a row's title: 17 points, medium on the selected
  /// row, by default.
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The size of a row's glyph: 24 by default.
  final double? iconSize;

  /// The height of a row, and the width of its circle on the rail: 44 by
  /// default.
  final double? rowHeight;

  /// The room around the rows inside the sidebar: from its leading and
  /// trailing sides, from the top of its safe area, which leaves the
  /// sidebar's button its row, and from the bottom of it. 20, 63, 16 and 20
  /// by default; the rail centers its rows instead of [padding]'s sides.
  final EdgeInsetsDirectional? padding;

  /// This style over [other], state by state.
  @override
  GlassTabSidebarStyle merge(GlassTabSidebarStyle? other) {
    if (other == null) return this;
    return GlassTabSidebarStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      separatorColor: separatorColor ?? other.separatorColor,
      indicatorColor: indicatorColor ?? other.indicatorColor,
      quietIndicatorColor: quietIndicatorColor ?? other.quietIndicatorColor,
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      iconColor: GlassStyle.mergeStates(iconColor, other.iconColor),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      iconSize: iconSize ?? other.iconSize,
      rowHeight: rowHeight ?? other.rowHeight,
      padding: padding ?? other.padding,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassTabSidebarStyle lerp(GlassTabSidebarStyle other, double t) {
    if (identical(this, other)) return this;
    final colors = GlassStyle.lerpStateColors(t);
    final number = GlassStyle.lerpNullable<double>(lerpDouble);
    return GlassTabSidebarStyle(
      backgroundColor: GlassDynamicColor.lerp(
        backgroundColor,
        other.backgroundColor,
        t,
      ),
      separatorColor: GlassDynamicColor.lerp(
        separatorColor,
        other.separatorColor,
        t,
      ),
      indicatorColor: GlassDynamicColor.lerp(
        indicatorColor,
        other.indicatorColor,
        t,
      ),
      quietIndicatorColor: GlassDynamicColor.lerp(
        quietIndicatorColor,
        other.quietIndicatorColor,
        t,
      ),
      foregroundColor: colors(foregroundColor, other.foregroundColor),
      iconColor: colors(iconColor, other.iconColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      iconSize: number(iconSize, other.iconSize, t),
      rowHeight: number(rowHeight, other.rowHeight, t),
      padding: GlassStyle.lerpNullable<EdgeInsetsDirectional>(
        EdgeInsetsDirectional.lerp,
      )(padding, other.padding, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTabSidebarStyle &&
      other.backgroundColor == backgroundColor &&
      other.separatorColor == separatorColor &&
      other.indicatorColor == indicatorColor &&
      other.quietIndicatorColor == quietIndicatorColor &&
      other.foregroundColor == foregroundColor &&
      other.iconColor == iconColor &&
      other.textStyle == textStyle &&
      other.iconSize == iconSize &&
      other.rowHeight == rowHeight &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    separatorColor,
    indicatorColor,
    quietIndicatorColor,
    foregroundColor,
    iconColor,
    textStyle,
    iconSize,
    rowHeight,
    padding,
  );
}

// A tab sidebar's style with every field the rows are laid out by: the
// metrics the sidebar and its rows share.
extension on GlassTabSidebarStyle {
  double get height => rowHeight ?? _Regular.rowHeight;

  double get glyph => iconSize ?? _Regular.rowIconSize;

  EdgeInsetsDirectional get room => padding ?? _Regular.rowsPadding;

  // The glyph's center from the row's start on the open row: 30 on a row
  // 44 tall (tab sidebar passport), as far past the rail's center on any
  // other.
  double get openIconCenter =>
      height / 2 + _Regular.rowIconCenter - _Regular.rowHeight / 2;

  // The title's start from the glyph's center: 24 past a glyph 24 wide
  // (title at 54), as far past half the glyph on any other.
  double get titleFromIcon =>
      glyph / 2 +
      _Regular.rowTitleStart -
      _Regular.rowIconCenter -
      _Regular.rowIconSize / 2;
}

/// The row a [GlassTabSidebar] draws by default for [details].
///
/// It draws the glyph and the title in the sidebar's style
/// ([GlassTabSidebarRowDetails.style]), with [style] over it: by default 44
/// points tall, on a pill of the accent where the row's tab is selected,
/// its content in the color that reads on it
/// ([GlassThemeData.primaryContrastingColor]), or on a gray pill with its
/// content in its own colors where the selection is quiet. The badge
/// follows the title. Toward the rail the title fades and folds away on
/// [GlassTabSidebarRowDetails.openWidth], the badge moves to the glyph's
/// corner, and the pill becomes a circle around the glyph. It draws the
/// press, hover and focus ring of [GlassTabSidebarRowDetails.states].
/// Accessibility reads the row from the sidebar, so the row excludes what
/// it draws from semantics.
///
/// A [GlassTabSidebar.rowBuilder] can stack its own parts over it, or
/// give one row a look of its own with [style]; the sidebar's rail stays
/// laid out by the sidebar's row height.
class GlassTabSidebarRow extends StatelessWidget {
  /// Creates the default row for [details].
  const GlassTabSidebarRow({required this.details, this.style, super.key});

  /// The row it draws.
  final GlassTabSidebarRowDetails details;

  /// The row's own look over the sidebar's, or null for the sidebar's.
  final GlassTabSidebarStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = style?.merge(details.style) ?? details.style;
    final destination = details.destination;
    final selected = details.selected;
    final quiet = details.quietSelection;
    final open = details.open;
    final tint = GlassDynamicColor.resolve(
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
      context,
    );
    final states = {
      if (selected) WidgetState.selected,
      if (!destination.enabled) WidgetState.disabled,
    };
    final fill = !selected
        ? null
        : GlassDynamicColor.resolve(
            quiet
                ? look.quietIndicatorColor ?? _Regular.quietPill
                : look.indicatorColor ?? tint,
            context,
          );
    final onFill = fill != null && !quiet && fill.a == 1
        ? GlassTheme.contentColorOf(context)(fill)
        : null;
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final text =
        look.textStyle?.resolve(states) ??
        (selected ? _Regular.selectedRow : _Regular.row);
    final titleStyle = scale
        .resolve(text)
        .copyWith(
          color: GlassDynamicColor.resolve(
            look.foregroundColor?.resolve(states) ??
                onFill ??
                text.color ??
                GlassTheme.labelColorOf(context),
            context,
          ),
        );
    final glyphColor = GlassDynamicColor.resolve(
      look.iconColor?.resolve(states) ?? onFill ?? tint,
      context,
    );
    final icon = selected
        ? destination.selectedIcon ?? destination.icon
        : destination.icon;
    final badge = destination.badge;
    final height = look.height;
    final radius = height / 2;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: GlassHighlightPaint.of(
          context,
          states: details.states,
          pressColor: _Regular.quietPill,
          shape: LiquidRoundedSuperellipse(radius: radius),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: fill,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            child: ClipRect(
              child: CustomMultiChildLayout(
                delegate: _RowLayout(
                  open: open,
                  openWidth: details.openWidth,
                  direction: Directionality.of(context),
                  look: look,
                ),
                children: [
                  LayoutId(
                    id: _RowPart.glyph,
                    child: Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: IconTheme.merge(
                            data: IconThemeData(
                              color: glyphColor,
                              size: look.glyph,
                            ),
                            child: icon,
                          ),
                        ),
                        if (badge != null && open < 1)
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: Opacity(opacity: 1 - open, child: badge),
                          ),
                      ],
                    ),
                  ),
                  if (open > 0)
                    LayoutId(
                      id: _RowPart.title,
                      child: Opacity(
                        opacity: open,
                        child: Row(
                          children: [
                            Expanded(
                              child: scale.apply(
                                DefaultTextStyle(
                                  style: titleStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  child: destination.label,
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
          ),
        ),
      ),
    );
  }
}

enum _RowPart { glyph, title }

// A default row: its glyph centered where the fold has carried it, and its
// title after it, laid out on the open row's width at least so it folds
// under the row's clip instead of reflowing.
class _RowLayout extends MultiChildLayoutDelegate {
  _RowLayout({
    required this.open,
    required this.openWidth,
    required this.direction,
    required this.look,
  });

  final double open;
  final double openWidth;
  final TextDirection direction;
  final GlassTabSidebarStyle look;

  @override
  void performLayout(Size size) {
    double from(double start, double extent) =>
        direction == TextDirection.rtl ? size.width - start - extent : start;
    final center = _lerp(look.height / 2, look.openIconCenter, open);
    final box = look.glyph + _Regular.rowIconBox - _Regular.rowIconSize;
    layoutChild(_RowPart.glyph, BoxConstraints.tight(Size.square(box)));
    positionChild(
      _RowPart.glyph,
      Offset(from(center - box / 2, box), (size.height - box) / 2),
    );
    if (!hasChild(_RowPart.title)) return;
    final start = center + look.titleFromIcon;
    final width = math.max<double>(0, math.max(size.width, openWidth) - start);
    layoutChild(
      _RowPart.title,
      BoxConstraints.tight(Size(width, size.height)),
    );
    positionChild(_RowPart.title, Offset(from(start, width), 0));
  }

  @override
  bool shouldRelayout(_RowLayout oldDelegate) =>
      open != oldDelegate.open ||
      openWidth != oldDelegate.openWidth ||
      direction != oldDelegate.direction ||
      look.height != oldDelegate.look.height ||
      look.glyph != oldDelegate.look.glyph;
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
