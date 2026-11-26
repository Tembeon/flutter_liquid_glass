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

/// A tab bar and its action circle on one glass group.
class _ActionTabBar extends StatelessWidget {
  const _ActionTabBar({
    required this.action,
    required this.metrics,
    required this.bar,
  });

  final GlassTabBarAction action;
  final TabBarMetrics metrics;
  final Widget bar;

  @override
  Widget build(BuildContext context) => GlassGroup(
    child: CustomMultiChildLayout(
      delegate: _ActionTabLayout(rtl: context.isRightToLeft, metrics: metrics),
      children: [
        LayoutId(id: _ActionSlot.bar, child: bar),
        LayoutId(
          id: _ActionSlot.circle,
          child: _ActionCircle(action: action, metrics: metrics),
        ),
      ],
    ),
  );
}

/// Lays a tab bar out at the leading side and its action circle at the
/// trailing one, [TabBarLayout.circleGap] apart at the least, as a search
/// tab bar rests: across the width it is given, a wide group at most 640
/// at the middle.
class _ActionTabLayout extends MultiChildLayoutDelegate {
  _ActionTabLayout({required this.rtl, required this.metrics});

  final bool rtl;
  final TabBarMetrics metrics;

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
    final double room = math.max(0, width - circle - TabBarLayout.circleGap);
    final bar = layoutChild(
      _ActionSlot.bar,
      BoxConstraints.loose(Size(room, size.height)),
    );
    layoutChild(_ActionSlot.circle, BoxConstraints.tight(Size.square(circle)));
    final barTop = (size.height - bar.height) / 2;
    if (rtl) {
      positionChild(_ActionSlot.bar, Offset(start + width - bar.width, barTop));
      positionChild(_ActionSlot.circle, Offset(start, top));
    } else {
      positionChild(_ActionSlot.bar, Offset(start, barTop));
      positionChild(_ActionSlot.circle, Offset(start + width - circle, top));
    }
  }

  @override
  bool shouldRelayout(_ActionTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl || metrics != oldDelegate.metrics;
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
