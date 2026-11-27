part of 'tab_bar.dart';

/// A glass circle at the trailing end of a [GlassTabBar] that runs an
/// action, where a search tab's circle stands.
///
/// UIKit has no public counterpart; the nearest is `UISearchTab`'s circle.
@immutable
final class GlassTabBarAction {
  /// Creates an action showing [icon] that calls [onPressed].
  const GlassTabBarAction({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.atSidebarStart = false,
  });

  /// The circle's glyph, a tab's size (24 points, 20 beside a wide bar) and
  /// in the label color by default.
  final Widget icon;

  /// What accessibility reads for the circle.
  final String semanticLabel;

  /// Called when the circle is pressed; null disables it.
  final VoidCallback? onPressed;

  /// Whether a tab sidebar stands the action's row first, above the tabs,
  /// as a compose row stands; false stands it after the tabs. A tab bar
  /// keeps the action in its circle.
  final bool atSidebarStart;
}

enum _ActionSlot { bar, circle }

/// A tab bar and its circle, an action's or a prominent tab's, on one
/// glass group, or the bar alone. A circle that comes or goes after the
/// first build slides and fades as [TabCircleMotion] says while the bar
/// takes or gives back its room, its tabs moving inside an animation as a
/// change of tabs does; the bar keeps its state throughout.
class _CircleTabBar extends StatefulWidget {
  const _CircleTabBar({
    required this.circle,
    required this.metrics,
    required this.bar,
  });

  final Widget? circle;
  final TabBarMetrics metrics;
  final Widget bar;

  @override
  State<_CircleTabBar> createState() => _CircleTabBarState();
}

class _CircleTabBarState extends State<_CircleTabBar> {
  final _bar = GlobalKey(debugLabel: 'GlassTabBar bar');
  late final _motion = TabCircleMotion(
    shown: widget.circle != null,
    clock: MotionClockScope.of(context),
  );
  late final _gone = _motion.select((motion) => motion.isGone);
  // The circle shown, or the one going.
  late Widget? _circle = widget.circle;

  @override
  void initState() {
    super.initState();
    _gone.addListener(_drop);
  }

  @override
  void didUpdateWidget(_CircleTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final circle = widget.circle;
    if (circle != null) _circle = circle;
    if ((circle == null) == (oldWidget.circle == null)) return;
    _motion.show(
      _motion.clock.now,
      shown: circle != null,
      away: widget.metrics.circleSize / 2 * (context.isRightToLeft ? -1 : 1),
    );
  }

  @override
  void dispose() {
    _gone.removeListener(_drop);
    super.dispose();
  }

  void _drop() {
    if (_gone.value && widget.circle == null && _circle != null) {
      setState(() => _circle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bar = KeyedSubtree(key: _bar, child: widget.bar);
    final circle = _circle;
    if (circle == null) {
      return Align(widthFactor: 1, heightFactor: 1, child: bar);
    }
    return GlassGroup(
      child: CustomMultiChildLayout(
        delegate: _ActionTabLayout(
          rtl: context.isRightToLeft,
          metrics: widget.metrics,
          hosts: widget.circle != null,
        ),
        children: [
          LayoutId(id: _ActionSlot.bar, child: bar),
          LayoutId(
            id: _ActionSlot.circle,
            child: IgnorePointer(
              ignoring: widget.circle == null,
              child: MotionTransition(
                opacity: _motion.shown,
                translateX: _motion.slide,
                child: circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays a tab bar out at the leading side and its action circle at the
/// trailing one, [TabBarLayout.circleGap] apart at the least, as a search
/// tab bar rests: across the width it is given, a wide group at most 640
/// at the middle. A bar whose circle is going stands at the middle, as it
/// will alone.
class _ActionTabLayout extends MultiChildLayoutDelegate {
  _ActionTabLayout({
    required this.rtl,
    required this.metrics,
    required this.hosts,
  });

  final bool rtl;
  final TabBarMetrics metrics;

  /// Whether the bar makes room for the circle.
  final bool hosts;

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : metrics.unboundWidth,
      metrics.height,
    ),
  );

  @override
  void performLayout(Size size) {
    final circle = metrics.circleSize;
    final width = math.min(
      size.width,
      metrics.hostedMaximum ?? double.infinity,
    );
    final start = (size.width - width) / 2;
    final top = (size.height - circle) / 2;
    final room = hosts
        ? math.max<double>(0, width - circle - TabBarLayout.circleGap)
        : size.width;
    final bar = layoutChild(
      _ActionSlot.bar,
      BoxConstraints.loose(Size(room, size.height)),
    );
    layoutChild(_ActionSlot.circle, BoxConstraints.tight(Size.square(circle)));
    final barTop = (size.height - bar.height) / 2;
    final barStart = !hosts
        ? (size.width - bar.width) / 2
        : rtl
        ? start + width - bar.width
        : start;
    positionChild(_ActionSlot.bar, Offset(barStart, barTop));
    positionChild(
      _ActionSlot.circle,
      Offset(rtl ? start : start + width - circle, top),
    );
  }

  @override
  bool shouldRelayout(_ActionTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl ||
      metrics != oldDelegate.metrics ||
      hosts != oldDelegate.hosts;
}

/// An action's glass circle: a glass button with the action's glyph.
class _ActionCircle extends StatelessWidget {
  const _ActionCircle({required this.action, required this.metrics});

  final GlassTabBarAction action;
  final TabBarMetrics metrics;

  @override
  Widget build(BuildContext context) => RawGlassButton(
    onPressed: action.onPressed,
    semanticLabel: action.semanticLabel,
    builder: (context, details) => GlassSurface.live(
      frame: details.body,
      states: details.statesListenable,
      child: details.label,
    ),
    child: Builder(
      builder: (context) => IconTheme.merge(
        data: IconThemeData(
          size: metrics.glyphSize,
          color:
              StateColors(
                context,
                {if (action.onPressed == null) WidgetState.disabled},
              )(
                WidgetStateMapper<Color?>({
                  WidgetState.disabled: GlassColors.tertiaryLabel,
                  WidgetState.any: GlassTheme.labelColorOf(context),
                }),
              ),
        ),
        child: Center(child: action.icon),
      ),
    ),
  );
}

/// A prominent tab's glass circle: a glass button with the tab's glyph,
/// tinted while the tab is selected and in the label color otherwise, as
/// UIKit 27.2 draws it.
class _ProminentCircle extends StatelessWidget {
  const _ProminentCircle({
    required this.destination,
    required this.selected,
    required this.metrics,
    required this.onPressed,
  });

  final GlassTabDestination destination;
  final bool selected;
  final TabBarMetrics metrics;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: RawGlassButton(
      onPressed: destination.enabled ? onPressed : null,
      semanticLabel:
          destination.semanticLabel ?? glassLabelTextOf(destination.label),
      builder: (context, details) => GlassSurface.live(
        frame: details.body,
        states: details.statesListenable,
        child: details.label,
      ),
      child: Builder(
        builder: (context) => IconTheme.merge(
          data: IconThemeData(
            size: metrics.glyphSize,
            color: !destination.enabled
                ? GlassDynamicColor.resolve(GlassColors.tertiaryLabel, context)
                : selected
                ? GlassTheme.primaryColorOf(context) ??
                      GlassDynamicColor.resolve(GlassColors.systemBlue, context)
                : GlassTheme.labelColorOf(context),
          ),
          child: Center(
            child: selected
                ? destination.selectedIcon ?? destination.icon
                : destination.icon,
          ),
        ),
      ),
    ),
  );
}
