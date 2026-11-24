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
// them, and the bottom accessory over the content's bottom.
class _RegularChrome extends StatefulWidget {
  const _RegularChrome({
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
  late final _hiding = GlassTabBarHiding(clock: MotionClockScope.of(context));
  late final _lift = MotionSelection(
    () => (_hiding.shown.value - 1) * _liftBy,
    clock: MotionClockScope.of(context),
  );
  double _liftBy = 0;
  late final _dismiss = TapInteraction(onTap: (_) => widget.onSidebar(false));

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
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
    final besideBar = action == null ? 0 : _Regular.actionGap + _Regular.circle;
    Widget bar(double width) => _TopBar(
      items: widget.items,
      selected: widget.selected,
      iconOnly: widget.iconOnly,
      onSelected: widget.onSelected,
      onSidebar: () => widget.onSidebar(true),
      look: widget.look,
      semanticLabel: widget.semanticLabel,
      maxWidth: width - 2 * _Regular.barMargin - besideBar,
    );
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
              start: inset,
              end: 0,
              bottom: _Regular.accessoryInset,
              height: _Regular.accessoryHeight,
              child: Center(child: _RegularAccessory(child: accessory)),
            ),
          if (shown && !beside)
            Positioned.fill(
              child: InputRegion(
                interactions: [_dismiss],
                semantics: SemanticsProperties(
                  label: GlassLocalizations.of(context).hideSidebarLabel,
                  button: true,
                ),
                child: const ColoredBox(color: _Regular.dimming),
              ),
            ),
          if (!shown)
            Positioned(
              top: media.padding.top,
              left: 0,
              right: 0,
              height: _Regular.barHeight,
              child: MotionTransition(
                translateY: _lift,
                opacity: _hiding.shown,
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: action == null
                        ? bar(constraints.maxWidth)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              bar(constraints.maxWidth),
                              const SizedBox(width: _Regular.actionGap),
                              _circle(
                                onPressed: action.onPressed,
                                semanticLabel: action.semanticLabel,
                                child: action.icon,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          if (shown)
            PositionedDirectional(
              top: 0,
              bottom: 0,
              start: 0,
              width: GlassTabScaffold.sidebarWidth,
              child: _Sidebar(
                items: widget.items,
                selected: widget.selected,
                quiet: widget.quiet,
                onSelected: widget.onSelected,
                onHide: () => widget.onSidebar(false),
                action: action,
                look: widget.look,
              ),
            ),
        ],
      ),
    );
  }
}

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

// The bar at the top: one platter holding the sidebar button and the
// tabs, each as wide as its title at either weight and 15.5 a side, and
// the selection lens on the selected one.
class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.items,
    required this.selected,
    required this.iconOnly,
    required this.onSelected,
    required this.onSidebar,
    required this.look,
    required this.semanticLabel,
    required this.maxWidth,
  });

  final List<GlassTabDestination> items;
  final int? selected;
  final int? iconOnly;
  final ValueChanged<int> onSelected;
  final VoidCallback onSidebar;
  final GlassTabBarStyle? look;
  final String? semanticLabel;

  // The widest the platter may be.
  final double maxWidth;

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

  // The tabs the platter holds, in order: the leading ones that fit, the
  // selected one in place of the last of them when it does not, and the
  // search tab at the end; the sidebar holds them all.
  List<int> _fitting(List<double> widths, int? selected) {
    final search = widget.iconOnly;
    var room =
        widget.maxWidth -
        2 * _Regular.barPadding -
        _Regular.buttonWidth -
        (search == null ? 0 : widths[search]);
    final fits = <int>[];
    for (var i = 0; i < widths.length; i++) {
      if (i == search) continue;
      if (widths[i] > room) break;
      fits.add(i);
      room -= widths[i];
    }
    if (selected != null && selected != search && !fits.contains(selected)) {
      while (fits.isNotEmpty && widths[selected] > room) {
        room += widths[fits.removeLast()];
      }
      fits.add(selected);
    }
    return [...fits, ?search];
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final items = widget.items;
    final scale = GlassTextScale.of(context, max: _Regular.maxTextScale);
    final direction = Directionality.of(context);
    double widthOf(int index) {
      if (index == widget.iconOnly) return _Regular.iconItemWidth;
      final text = glassLabelTextOf(items[index].label) ?? '';
      double drawn(TextStyle style) => scale
          .measure(text, style, textDirection: direction, maxLines: 1)
          .size
          .width;
      return math.max(drawn(_Regular.item), drawn(_Regular.selectedItem)) +
          2 * _Regular.itemPadding;
    }

    final widths = [for (var i = 0; i < items.length; i++) widthOf(i)];
    final selected = widget.selected;
    final shown = _fitting(widths, selected);
    final row = shown.fold(
      _Regular.buttonWidth,
      (sum, index) => sum + widths[index],
    );
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
    final background = look?.backgroundColor?.resolve(const {});
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
      child: GlassSurface(
        role: GlassRole.bar,
        shape: const LiquidRoundedSuperellipse(radius: _Regular.barRadius),
        glass: Glass.regular(tint: background),
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
      ),
    );
  }
}

// The tab sidebar: its button at the top, then a row per tab, the selected
// one a tint pill with white content, or a gray pill with the content in
// its own colors while the selected tab shows its list column ([quiet]).
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.quiet,
    required this.onSelected,
    required this.onHide,
    required this.action,
    required this.look,
  });

  final List<GlassTabDestination> items;
  final int? selected;
  final bool quiet;
  final ValueChanged<int> onSelected;
  final VoidCallback onHide;
  final GlassTabBarAction? action;
  final GlassTabBarStyle? look;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final tint = GlassDynamicColor.resolve(
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
      context,
    );
    final background = look?.backgroundColor?.resolve(const {});
    final action = this.action;
    return GlassSurface(
      role: GlassRole.bar,
      shape: const LiquidRoundedSuperellipse(radius: 0),
      glass: Glass.regular(tint: background),
      child: Stack(
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
      ),
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
