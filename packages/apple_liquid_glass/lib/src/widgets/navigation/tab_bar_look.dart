part of 'tab_bar.dart';

class _TabBarLook extends StatelessWidget {
  const _TabBarLook({required this.details, required this.look});

  final GlassSelectorDetails details;
  final GlassTabBarStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color? resolve(WidgetStateProperty<Color?>? property) {
      final color = property?.resolve(states);
      return color == null ? null : GlassDynamicColor.resolve(color, context);
    }

    Widget surface(
      GlassRole role,
      MotionSelection<GlassFrame> frame,
      Color? tint, {
      GlassLens lens = const GlassLens(),
      ValueNotifier<GlassLensContent?>? lensContent,
    }) => GlassSurface.live(
      role: role,
      lens: lens,
      lensContent: lensContent,
      glass: Glass.regular(tint: tint),
      frame: frame,
      child: const SizedBox.expand(),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: surface(
            GlassRole.bar,
            details.body,
            resolve(look.backgroundColor),
          ),
        ),
        details.items(
          lens: surface(
            GlassRole.lens,
            details.lens,
            resolve(look.thumbColor),
            lens: _lens,
            lensContent: details.lensContent,
          ),
        ),
      ],
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.destination,
    required this.look,
    required this.states,
    required this.morph,
  });

  final GlassTabDestination destination;
  final GlassTabBarStyle look;
  final Set<WidgetState> states;
  final MotionSelection<double>? morph;

  @override
  Widget build(BuildContext context) {
    final color = GlassDynamicColor.resolve(
      look.foregroundColor!.resolve(states)!,
      context,
    );
    final selected = states.contains(WidgetState.selected);
    final badge = destination.badge;
    final icon = IconTheme.merge(
      data: IconThemeData(color: color, size: GlassTabBar.iconSize),
      child: selected
          ? destination.selectedIcon ?? destination.icon
          : destination.icon,
    );
    final glyph = badge == null ? icon : _Badged(badge: badge, child: icon);
    final content = MediaQuery.withClampedTextScaling(
      maxScaleFactor: GlassTabBar.maxTextScale,
      child: Builder(
        builder: (context) => _TabItem(
          morph: morph,
          titleGoneAt: selected
              ? TabBarMinimizeMotion.lensGoneAt
              : TabBarMinimizeMotion.titlesGoneAt,
          children: [
            glyph,
            DefaultTextStyle.merge(
              style: resolveGlassText(
                look.textStyle!.resolve(states)!.copyWith(color: color),
                context,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              child: destination.label,
            ),
          ],
        ),
      ),
    );
    return GlassHighlightPaint.of(
      context,
      heldStates: states,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      inside: true,
      wash: true,
      child: SizedBox.expand(
        child: Center(
          child: destination.enabled
              ? content
              : Opacity(opacity: 0.5, child: content),
        ),
      ),
    );
  }
}

/// A badge at the top trailing corner of a tab's glyph: its leading edge 5
/// points inside the glyph's trailing edge and its top 6 points above the
/// glyph's, by eye (UIKit places it 2 points below the tab button's top).
class _Badged extends StatelessWidget {
  const _Badged({required this.badge, required this.child});

  final Widget badge;
  final Widget child;

  static const double _inset = 5;
  static const double _rise = 6;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      PositionedDirectional(
        start: GlassTabBar.iconSize - _inset,
        top: -_rise,
        child: badge,
      ),
    ],
  );
}
