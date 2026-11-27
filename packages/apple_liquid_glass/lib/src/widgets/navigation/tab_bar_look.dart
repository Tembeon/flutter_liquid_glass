part of 'tab_bar.dart';

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.destination,
    required this.metrics,
    required this.look,
    required this.states,
    required this.morph,
  });

  final GlassTabDestination destination;
  final TabBarMetrics metrics;
  final GlassTabBarStyle look;
  final Set<WidgetState> states;
  final MotionSelection<double>? morph;

  @override
  Widget build(BuildContext context) {
    final color = StateColors(context, states)(look.foregroundColor);
    final selected = states.contains(WidgetState.selected);
    final badge = destination.badge;
    final scale = GlassTextScale.fixed(context, followsBoldText: false);
    final content = scale.apply(
      _TabItem(
        morph: morph,
        titleGoneAt: selected ? TabBarMinimizeMotion.lensGoneAt : null,
        circleBadge: selected,
        metrics: metrics,
        children: [
          IconTheme.merge(
            data: IconThemeData(color: color, size: metrics.glyphSize),
            child: selected
                ? destination.selectedIcon ?? destination.icon
                : destination.icon,
          ),
          DefaultTextStyle.merge(
            style: scale.resolve(
              look.textStyle!.resolve(states)!.copyWith(color: color),
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: destination.label,
          ),
          ?badge,
        ],
      ),
    );
    return GlassHighlightPaint.of(
      context,
      heldStates: states,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      inside: true,
      wash: true,
      child: SizedBox.expand(child: Center(child: content)),
    );
  }
}
