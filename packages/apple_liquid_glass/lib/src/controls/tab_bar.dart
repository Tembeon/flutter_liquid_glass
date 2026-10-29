import 'package:apple_liquid_glass/src/controls/selector.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// One tab of a [GlassTabBar].
///
/// UIKit: `UITabBarItem`, `UITab`. SwiftUI: `Tab`. Flutter:
/// `NavigationDestination`.
@immutable
final class GlassTabDestination {
  /// Creates a tab showing [icon] over [label].
  const GlassTabDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badge,
    this.enabled = true,
    this.semanticLabel,
  });

  /// The tab's glyph, 24 points by default.
  final Widget icon;

  /// The tab's title.
  final Widget label;

  /// The glyph the tab shows inside the selection lens (UIKit
  /// `selectedImage`), or null for [icon]. The lens shows a selected copy
  /// of every tab, so a glyph that holds state or a key gives a stateless
  /// copy here.
  final Widget? selectedIcon;

  /// A mark at the top trailing corner of the glyph, such as a count; its
  /// placement is by eye, not measured (tab bar passport).
  final Widget? badge;

  /// Whether the tab can be selected. A disabled tab draws at half opacity
  /// (not measured).
  final bool enabled;

  /// What accessibility reads for the tab; null lets its label speak.
  final String? semanticLabel;
}

/// The look of a [GlassTabBar], like Flutter's `ButtonStyle`.
///
/// [backgroundColor] and [thumbColor] are resolved against the bar's
/// states, [foregroundColor] and [textStyle] against each tab's, which
/// include [WidgetState.selected] inside the lens. A bar looks a field up
/// in its own style, then in the theme's, then in its defaults, state by
/// state: a property that gives null for a state leaves that state to the
/// next one.
@immutable
class GlassTabBarStyle {
  /// Creates a style.
  const GlassTabBarStyle({
    this.backgroundColor,
    this.thumbColor,
    this.foregroundColor,
    this.textStyle,
    this.builder,
  });

  /// A tint over the bar's glass (UIKit `barTintColor`); none by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The resting lens under the selected tab; [GlassTabBar.thumb] by
  /// default.
  final WidgetStateProperty<Color?>? thumbColor;

  /// The color of a tab's glyph and title: the theme's primary color inside
  /// the lens and [GlassTabBar.unselected] outside it, by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The text style of a tab's title: 10 points, medium, and semibold
  /// inside the lens, by default (tab bar passport).
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// Builds the bar's look in place of the default one; the bar then
  /// ignores [backgroundColor] and [thumbColor]. Null leaves it to the
  /// theme's builder, then the default look.
  final GlassSelectorBuilder? builder;

  /// This style over [other], state by state.
  GlassTabBarStyle merge(GlassTabBarStyle? other) {
    if (other == null) return this;
    return GlassTabBarStyle(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      textStyle: fallThrough(textStyle, other.textStyle),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassTabBarStyle? lerp(
    GlassTabBarStyle? a,
    GlassTabBarStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassTabBarStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor),
      thumbColor: color(a.thumbColor, b.thumbColor),
      foregroundColor: color(a.foregroundColor, b.foregroundColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        a.textStyle,
        b.textStyle,
        t,
        snapNull(TextStyle.lerp),
      ),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTabBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.thumbColor == thumbColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    thumbColor,
    foregroundColor,
    textStyle,
    builder,
  );
}

/// An iOS 27 tab bar.
///
/// UIKit: `UITabBar`. SwiftUI: `TabView`. Flutter: `NavigationBar`,
/// `CupertinoTabBar`.
///
/// A glass bar 62 points tall, as wide as its tabs: 86 points a tab for
/// two to four tabs and 68 for five, widened when a title needs it (tab bar
/// passport). Its motion is [RawGlassSelector]'s with
/// [GlassSelectorMotion.tabBar]: the bar swells and drifts under the
/// finger, a glow follows it, and a dragged lens carries a selected copy of
/// the tabs under it. Titles follow the text scale up to [maxTextScale].
/// [onDestinationSelected] runs on every selection, the selected tab's
/// included: a tap on it, Space, Enter or an accessibility tap reselects it,
/// where an app scrolls the tab's content to the top.
class GlassTabBar extends StatelessWidget {
  /// Creates a tab bar showing [selectedIndex] selected.
  const GlassTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// The tabs, two to five.
  final List<GlassTabDestination> destinations;

  /// The selected tab, clamped to [destinations].
  final int selectedIndex;

  /// Called with the tab the user selects or reselects; null disables the
  /// bar. A bar whose [selectedIndex] does not follow returns to it.
  final ValueChanged<int>? onDestinationSelected;

  /// The look, over the theme's and the bar's defaults.
  final GlassTabBarStyle? style;

  /// Where the bar writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The bar's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the bar takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the bar as a whole.
  final String? semanticLabel;

  /// The height of the bar (tab bar passport).
  static const double height = 62;

  /// The largest text scale the titles follow (tab bar passport).
  static const double maxTextScale = 1.25;

  /// The size of a tab's glyph (tab bar passport).
  static const double iconSize = 24;

  /// The gap between a tab's glyph and title.
  static const double labelGap = 2;

  /// UITabBar's resting lens: what UIKit's color matrices make of the
  /// measured bar under the selection, over a plain page.
  static const thumb = GlassDynamicColor.withBrightness(
    color: Color(0x13000000),
    darkColor: Color(0xAF000000),
  );

  /// The tabs outside the lens: UIKit's vibrant glyph color over the
  /// measured bar (tab bar passport, layout and device).
  static const unselected = GlassDynamicColor.withBrightness(
    color: Color(0xFF0D0D0D),
    darkColor: Color(0xFFFAFAFA),
  );

  /// The tabs inside the lens without a primary color: UIKit's tint over
  /// the measured bar (tab bar passport, layout and device).
  static const selected = GlassDynamicColor.withBrightness(
    color: Color(0xFF0082FC),
    darkColor: Color(0xFF0397FF),
  );

  static const _title = TextStyle(fontSize: 10, fontWeight: FontWeight.w500);
  static const _selectedTitle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  /// A style from plain colors and text styles; a null value leaves the
  /// field to the theme, then the default.
  static GlassTabBarStyle styleFrom({
    Color? backgroundColor,
    Color? thumbColor,
    Color? foregroundColor,
    Color? selectedForegroundColor,
    TextStyle? textStyle,
    TextStyle? selectedTextStyle,
  }) => GlassTabBarStyle(
    backgroundColor: allStates(backgroundColor),
    thumbColor: allStates(thumbColor),
    foregroundColor: foregroundColor == null && selectedForegroundColor == null
        ? null
        : BySelection(foregroundColor, selectedForegroundColor),
    textStyle: textStyle == null && selectedTextStyle == null
        ? null
        : BySelection(textStyle, selectedTextStyle),
  );

  GlassTabBarStyle _defaults(BuildContext context) => GlassTabBarStyle(
    thumbColor: const WidgetStatePropertyAll(thumb),
    foregroundColor: BySelection(
      unselected,
      GlassTheme.of(context).primaryColor ?? selected,
    ),
    textStyle: const BySelection(_title, _selectedTitle),
  );

  @override
  Widget build(BuildContext context) {
    final themed = GlassTheme.of(context).tabBarStyle;
    final look = (style ?? const GlassTabBarStyle())
        .merge(themed)
        .merge(_defaults(context));
    final onSelected = onDestinationSelected;
    return RawGlassSelector(
      motion: GlassSelectorMotion.tabBar,
      itemCount: destinations.length,
      selectedIndex: selectedIndex,
      onChanged: onSelected,
      onReselected: onSelected,
      disabledItems: {
        for (var i = 0; i < destinations.length; i++)
          if (!destinations[i].enabled) i,
      },
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      itemBuilder: (context, index, states) => _TabContent(
        destination: destinations[index],
        look: look,
        states: states,
      ),
      builder:
          style?.builder ??
          themed?.builder ??
          (context, details) => _TabBarLook(details: details, look: look),
    );
  }
}

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
      ValueListenable<GlassFrame> frame,
      Color? tint,
    ) => Positioned.fill(
      child: GlassSurface.live(
        role: role,
        glass: Glass.regular(tint: tint),
        frame: frame,
        child: const SizedBox.expand(),
      ),
    );
    return Stack(
      children: [
        surface(GlassRole.bar, details.body, resolve(look.backgroundColor)),
        surface(GlassRole.lens, details.lens, resolve(look.thumbColor)),
        details.items,
      ],
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.destination,
    required this.look,
    required this.states,
  });

  final GlassTabDestination destination;
  final GlassTabBarStyle look;
  final Set<WidgetState> states;

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
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph,
            const SizedBox(height: GlassTabBar.labelGap),
            DefaultTextStyle.merge(
              style: resolveGlassText(
                look.textStyle!.resolve(states)!.copyWith(color: color),
                context,
              ),
              maxLines: 1,
              softWrap: false,
              child: destination.label,
            ),
          ],
        ),
      ),
    );
    final semanticLabel = destination.semanticLabel;
    final labelled = semanticLabel == null
        ? content
        : Semantics(
            label: semanticLabel,
            child: ExcludeSemantics(child: content),
          );
    return destination.enabled
        ? labelled
        : Opacity(opacity: 0.5, child: labelled);
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
