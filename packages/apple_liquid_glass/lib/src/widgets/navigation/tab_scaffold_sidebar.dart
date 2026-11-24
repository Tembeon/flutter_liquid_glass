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
// over the content or beside it, with the content's safe area grown for
// them, and the bottom accessory over the content's bottom. The bar's
// platter and the sidebar are one glass whose frame springs between them,
// each side's content over it, clipped to it and fading with it.
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
  late final _dismiss = TapInteraction(onTap: (_) => widget.onSidebar(false));

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
    final sized = _sized || _side.settledAt(now);
    if (morphed == _morphed && sized == _sized) return;
    setState(() {
      _morphed = morphed;
      _sized = sized;
    });
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
    final beside = widget.beside;
    final besideShown = beside && shown;
    final inset = besideShown ? GlassTabScaffold.sidebarWidth : 0.0;
    final top = media.padding.top + (besideShown ? 0 : _Regular.contentDrop);
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
    final side = Rect.fromLTWH(
      rtl ? size.width - GlassTabScaffold.sidebarWidth : 0,
      0,
      GlassTabScaffold.sidebarWidth,
      size.height,
    );
    final place = (bar: bar, size: size, rtl: rtl);
    if (place != _place) {
      _place = place;
      _frame = _frameAt(place);
    }
    _aim(toSidebar: shown, beside: beside);
    final withBar = !shown || !_morphed;
    final withSidebar = shown || !_morphed;
    return GlassChrome(
      edges: ChromeEdges(
        top: besideShown ? ChromeBar.none : ChromeBar.floating,
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
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(top: top, bottom: bottom),
            ),
            child: widget.child,
          ),
          if (accessory != null)
            PositionedDirectional(
              key: const ValueKey('accessory'),
              start: inset,
              end: 0,
              bottom: _Regular.accessoryInset,
              height: _Regular.accessoryHeight,
              child: Center(child: _RegularAccessory(child: accessory)),
            ),
          if (!beside && withSidebar)
            Positioned.fill(
              key: const ValueKey('dimming'),
              child: _leaving(
                !shown,
                MotionTransition(
                  opacity: _sidebarOpacity,
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
                    Positioned.fromRect(
                      key: const ValueKey('sidebar'),
                      rect: side,
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
        ],
      ),
    );
  }
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
// column ([quiet]).
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
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final tint = GlassDynamicColor.resolve(
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
      context,
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
              _Regular.rowInset,
              media.padding.top + _Regular.rowsTop,
              GlassTabScaffold.sidebarWidth -
                  _Regular.rowInset -
                  _Regular.rowWidth,
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
                  onPressed: action.onPressed,
                ),
            ],
          ),
        ),
        PositionedDirectional(
          top: media.padding.top,
          end: _Regular.circleEnd,
          child: _circle(
            onPressed: onHide,
            semanticLabel: GlassLocalizations.of(context).hideSidebarLabel,
            color: tint,
            child: const GlassSidebarGlyph(),
          ),
        ),
      ],
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.destination,
    required this.selected,
    required this.quiet,
    required this.tint,
    required this.onPressed,
  });

  final GlassTabDestination destination;
  final bool selected;
  final bool quiet;
  final Color tint;
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
    const iconStart = _Regular.rowIconCenter - _Regular.rowIconBox / 2;
    const titleGap =
        _Regular.rowTitleStart -
        _Regular.rowIconCenter -
        _Regular.rowIconBox / 2;
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
        child: Row(
          children: [
            const SizedBox(width: iconStart),
            SizedBox(
              width: _Regular.rowIconBox,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: loud ? white : tint,
                    size: _Regular.rowIconSize,
                  ),
                  child: ExcludeSemantics(child: icon),
                ),
              ),
            ),
            const SizedBox(width: titleGap),
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
