import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/button.dart';
import 'package:apple_liquid_glass/src/controls/search_controller.dart';
import 'package:apple_liquid_glass/src/controls/search_field.dart';
import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/controls/selector.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
import 'package:apple_liquid_glass/src/motion/tab_minimize.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
  /// `selectedImage`), or null for [icon]. Every tab is built twice, once
  /// for the bar and once for the lens; give a glyph that holds state or a
  /// `GlobalKey` a separate stateless copy here.
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
  /// ignores [thumbColor], and [backgroundColor] still tints the minimized
  /// circle and the bottom accessory. Null leaves it to the
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

/// Where a tab bar's bottom accessory stands.
///
/// UIKit: `UITabAccessory.Environment`. SwiftUI:
/// `TabViewBottomAccessoryPlacement`.
enum GlassTabAccessoryPlacement {
  /// Above the expanded bar, across the bar group.
  expanded,

  /// Beside the minimized bar's circle.
  inline,
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
///
/// With a [minimizeBehavior] that minimizes, the bar follows the scroll
/// view of its page's [GlassContentScroll] with UIKit's scroll-away
/// interaction of the floating tab bar: a user's scroll of 64 points
/// shrinks it into a 48 point circle that keeps its selected tab's glyph,
/// 7 points inside the bar's leading side, in one liquid morph (damping
/// 0.8, response 0.3); a tap on the circle, the content's top end or a
/// scroll past its far end expands it. A finger held on the circle or a
/// drag from it neither expands the bar nor starts its selection drag,
/// unlike UIKit. Put it in a `GlassTabScaffold`.
///
/// A [bottomAccessory], a mini player say, stands on its own glass 48
/// points tall, 8 points above the bar across the bar group, its content
/// inset 16 points at the sides and 8 at the top and bottom; while the bar
/// is minimized it stands level with the circle, 14 points beside it. It
/// travels there along the bar first and up after, and back up first and
/// along after, the second axis 0.05 s late. [accessoryPlacementOf] tells
/// its content which place it heads for, flipping as the transition
/// starts (read from UIKit, notes private).
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
    this.minimizeBehavior = GlassTabBarMinimizeBehavior.automatic,
    this.bottomAccessory,
    this.searchController,
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

  /// When the bar minimizes as the content under it scrolls;
  /// [GlassTabBarMinimizeBehavior.automatic] does not minimize, as an
  /// iPhone tab bar that does not opt in.
  final GlassTabBarMinimizeBehavior minimizeBehavior;

  /// The content of the glass accessory above the bar (UIKit
  /// `bottomAccessory`, SwiftUI `tabViewBottomAccessory`), or null.
  final Widget? bottomAccessory;

  /// The search of the bar's search tab, or null for a bar without one.
  ///
  /// UIKit: a `UISearchTab` that `automaticallyActivatesSearch`. SwiftUI:
  /// `Tab(role: .search)`.
  ///
  /// The search tab is a glass circle 62 points across at the trailing
  /// side, the bar at the leading one, both 21 points from the sides and
  /// the bottom. Opening the search (a tap on the circle) turns the bar
  /// into a circle 48 points across holding the selected tab's glyph and
  /// the search circle into a search field beside it, on UIKit's liquid
  /// morph (damping 0.8, response 0.3, read from UIKit; the simulator film
  /// fits 0.276 and 0.8); the field takes the focus 0.16 s after the tap
  /// and, once the keyboard starts to rise, rises above it with a close
  /// button on a critically damped spring of response 0.3, while the tab
  /// circle fades under the keyboard (device recordings). The close button
  /// or Escape clears the query and ends the focus; the field falls
  /// straight back. A tap on the tab circle closes the search, and the bar
  /// turns back, clearing the query; it takes the tap while the morph into
  /// the field still runs, which turns around with its velocity, until the
  /// close button shows. The search circle takes no tap until the morph
  /// back has settled, as UIKit's. The bar lays itself out over the
  /// screen's bottom: in a `GlassTabScaffold` it does by itself. A bar with
  /// a search tab does not minimize or carry a [bottomAccessory].
  final GlassSearchController? searchController;

  /// Where the bottom accessory around [context] stands.
  static GlassTabAccessoryPlacement accessoryPlacementOf(
    BuildContext context,
  ) =>
      context
          .dependOnInheritedWidgetOfExactType<_AccessoryScope>()
          ?.placement ??
      GlassTabAccessoryPlacement.expanded;

  /// The height of the bar group: the bar and, with [accessory], the
  /// accessory above it.
  static double groupHeight({required bool accessory}) =>
      height +
      (accessory
          ? TabBarMinimizeTuning.accessoryGap +
                TabBarMinimizeTuning.accessoryHeight
          : 0);

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
    final bar = RawGlassSelector(
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
    final count = destinations.length;
    final selected = count == 0 ? -1 : selectedIndex.clamp(0, count - 1);
    if (searchController case final search?) {
      return _SearchTabBar(
        controller: search,
        destinations: destinations,
        selectedIndex: selected,
        look: look,
        bar: bar,
      );
    }
    final accessory = bottomAccessory;
    if (!minimizeBehavior.minimizes && accessory == null) return bar;
    return _MinimizingBar(
      behavior: minimizeBehavior,
      accessory: accessory,
      destinations: destinations,
      selectedIndex: selected,
      look: look,
      bar: bar,
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

/// The minimize motion of a bar, stepped on the motion clock and published
/// as the hint scale, the morph to the circle, the accessory's two axes,
/// whether the bar is minimized and whether it rests expanded.
final class _MinimizeBody implements MotionDriver {
  _MinimizeBody(GlassTabBarMinimizeBehavior behavior)
    : motion = TabBarMinimizeMotion(behavior: behavior);

  final TabBarMinimizeMotion motion;
  final hint = ValueNotifier<double>(1);
  final morph = ValueNotifier<double>(0);
  final accessoryX = ValueNotifier<double>(0);
  final accessoryY = ValueNotifier<double>(0);
  final minimized = ValueNotifier<bool>(false);
  final resting = ValueNotifier<bool>(true);
  double width = 400;

  double get _now => MotionClock.instance.now;

  @override
  bool get isActive => !motion.isSettled(extent: width);

  @override
  double? get wakeTime => motion.wakeTime(extent: width);

  @override
  void step(double time) {
    motion.advance(time);
    if (motion.isSettled(extent: width)) motion.settle(time);
    _publish();
  }

  void _publish() {
    hint.value = motion.hint;
    morph.value = motion.morph;
    accessoryX.value = motion.accessoryX;
    accessoryY.value = motion.accessoryY;
    minimized.value = motion.minimized;
    resting.value = motion.restsExpanded;
  }

  void input(void Function(double t) action) {
    final t = _now;
    motion.advance(t);
    action(t);
    _publish();
    MotionClock.instance.wake(this);
  }

  void dispose() {
    hint.dispose();
    morph.dispose();
    accessoryX.dispose();
    accessoryY.dispose();
    minimized.dispose();
    resting.dispose();
  }
}

/// A tab bar that minimizes into a circle as the followed content scrolls.
class _MinimizingBar extends StatefulWidget {
  const _MinimizingBar({
    required this.behavior,
    required this.accessory,
    required this.destinations,
    required this.selectedIndex,
    required this.look,
    required this.bar,
  });

  final GlassTabBarMinimizeBehavior behavior;
  final Widget? accessory;
  final List<GlassTabDestination> destinations;
  final int selectedIndex;
  final GlassTabBarStyle look;
  final Widget bar;

  @override
  State<_MinimizingBar> createState() => _MinimizingBarState();
}

class _MinimizingBarState extends State<_MinimizingBar> {
  late final _MinimizeBody _body = _MinimizeBody(widget.behavior);
  ValueNotifier<MotionScrollObserver?>? _active;
  MotionScrollObserver? _observer;
  MotionScrollPhase _phase = MotionScrollPhase.idle;
  Size _barSize = const Size(0, GlassTabBar.height);

  @override
  void initState() {
    super.initState();
    MotionClock.instance.addDriver(_body);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _body.motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(_MinimizingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.behavior != widget.behavior) {
      _body.input((t) => _body.motion.setBehavior(t, widget.behavior));
    }
  }

  @override
  void dispose() {
    _active?.removeListener(_follow);
    _observer?.removeListener(_scrolled);
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  void _follow() {
    final next = _active?.value;
    if (identical(next, _observer)) return;
    _observer?.removeListener(_scrolled);
    _observer = next;
    _phase = MotionScrollPhase.idle;
    next?.addListener(_scrolled);
  }

  // Turns the scroll view's phases into the scroll-away interaction's
  // inputs: a drag starts a fresh accumulation, its end and the end of
  // the glide floor it, and a scroll the user did not drive is only
  // recorded, unless it reaches the top.
  void _scrolled() {
    final observer = _observer;
    final metrics = observer?.metrics;
    if (observer == null || metrics == null || !metrics.hasContentDimensions) {
      return;
    }
    final away = _body.motion.scrollAway;
    final phase = observer.phase;
    final previous = _phase;
    _phase = phase;
    final offset = metrics.pixels;
    final min = metrics.minScrollExtent;
    final max = metrics.maxScrollExtent;
    if (!_body.motion.behavior.minimizes) {
      away.last = offset;
      return;
    }
    _body.input((t) {
      if (phase == MotionScrollPhase.dragging &&
          previous != MotionScrollPhase.dragging) {
        away.beginDrag();
      }
      if (previous == MotionScrollPhase.dragging &&
          phase != MotionScrollPhase.dragging) {
        away.endDrag(decelerates: phase == MotionScrollPhase.decelerating);
      }
      switch (phase) {
        case MotionScrollPhase.dragging || MotionScrollPhase.decelerating:
          away.scroll(
            offset,
            min: min,
            max: max,
            tracking: phase == MotionScrollPhase.dragging,
          );
        case MotionScrollPhase.programmatic || MotionScrollPhase.idle:
          away.last = offset;
          if (previous == MotionScrollPhase.decelerating) {
            away.endDeceleration();
          }
          if (_body.motion.minimized && offset <= min + 0.5) {
            away.scrollToTop();
          }
      }
    });
  }

  void _expand() {
    if (!_body.motion.minimized) return;
    _body.input((t) => _body.motion.setMinimized(t, minimized: false));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : _barSize.width;
      _body.width = width;
      final accessory = widget.accessory;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final bar = SizedBox(
        width: width,
        height: GlassTabBar.height,
        child: ValueListenableBuilder<bool>(
          valueListenable: _body.resting,
          builder: (context, resting, _) => resting
              ? Align(
                  child: MotionTransition(
                    scale: _body.hint,
                    child: _SizeNote(
                      onSize: (size) => _barSize = size,
                      child: widget.bar,
                    ),
                  ),
                )
              : MotionTransition(
                  scale: _body.hint,
                  child: _CollapsingTabs(
                    width: width,
                    barSize: _barSize,
                    morph: _body.morph,
                    destinations: widget.destinations,
                    selectedIndex: widget.selectedIndex,
                    look: widget.look,
                    rtl: rtl,
                    onTap: _expand,
                  ),
                ),
        ),
      );
      if (accessory == null) return bar;
      return SizedBox(
        width: width,
        height: GlassTabBar.groupHeight(accessory: true),
        child: Stack(
          children: [
            Positioned.fill(
              child: _Accessory(
                body: _body,
                width: width,
                rtl: rtl,
                look: widget.look,
                child: accessory,
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: bar),
          ],
        ),
      );
    },
  );
}

class _AccessoryScope extends InheritedWidget {
  const _AccessoryScope({required this.placement, required super.child});

  final GlassTabAccessoryPlacement placement;

  @override
  bool updateShouldNotify(_AccessoryScope oldWidget) =>
      placement != oldWidget.placement;
}

/// The bottom accessory: its glass goes from above the bar to beside the
/// circle with the bar's glass, and its content stands in either place,
/// switching as the transition starts, clipped to the moving glass.
class _Accessory extends StatefulWidget {
  const _Accessory({
    required this.body,
    required this.width,
    required this.rtl,
    required this.look,
    required this.child,
  });

  final _MinimizeBody body;
  final double width;
  final bool rtl;
  final GlassTabBarStyle look;
  final Widget child;

  @override
  State<_Accessory> createState() => _AccessoryState();
}

class _AccessoryState extends State<_Accessory> {
  final _frame = ValueNotifier(const GlassFrame());
  final _placement = ValueNotifier(GlassTabAccessoryPlacement.expanded);

  List<Listenable> get _sources => [
    widget.body.accessoryX,
    widget.body.accessoryY,
    widget.body.minimized,
  ];

  @override
  void initState() {
    super.initState();
    for (final source in _sources) {
      source.addListener(_moved);
    }
    _moved();
  }

  @override
  void didUpdateWidget(_Accessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    _moved();
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(_moved);
    }
    _frame.dispose();
    _placement.dispose();
    super.dispose();
  }

  Rect _mirror(Rect rect) => widget.rtl
      ? Rect.fromLTRB(
          widget.width - rect.right,
          rect.top,
          widget.width - rect.left,
          rect.bottom,
        )
      : rect;

  Rect get _expanded => Rect.fromLTWH(
    0,
    0,
    widget.width,
    TabBarMinimizeTuning.accessoryHeight,
  );

  // Beside the circle, as tall as it and level with it, reaching to the
  // bar group's trailing side.
  Rect get _inline {
    const inset = TabBarMinimizeTuning.collapsedInset;
    const top =
        TabBarMinimizeTuning.accessoryGap +
        TabBarMinimizeTuning.accessoryHeight +
        inset;
    return _mirror(
      Rect.fromLTRB(
        inset +
            TabBarMinimizeTuning.collapsedSize +
            TabBarMinimizeTuning.inlineGap,
        top,
        widget.width,
        top + TabBarMinimizeTuning.accessoryHeight,
      ),
    );
  }

  // The position and width move along one axis, the position and height
  // along the other, each on its own spring.
  void _moved() {
    final x = widget.body.accessoryX.value;
    final y = widget.body.accessoryY.value;
    final from = _expanded;
    final to = _inline;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    _frame.value = GlassFrame(
      rect: Rect.fromLTRB(
        lerp(from.left, to.left, x),
        lerp(from.top, to.top, y),
        lerp(from.right, to.right, x),
        lerp(from.bottom, to.bottom, y),
      ),
    );
    _placement.value = widget.body.minimized.value
        ? GlassTabAccessoryPlacement.inline
        : GlassTabAccessoryPlacement.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.look.backgroundColor?.resolve(const {});
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.bar,
            glass: Glass.regular(
              tint: background == null
                  ? null
                  : GlassDynamicColor.resolve(background, context),
            ),
            frame: _frame,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: ClipPath(
            clipper: _CapsuleClip(_frame),
            child: ValueListenableBuilder<GlassTabAccessoryPlacement>(
              valueListenable: _placement,
              builder: (context, placement, child) => Stack(
                children: [
                  Positioned.fromRect(
                    rect: placement == GlassTabAccessoryPlacement.inline
                        ? _inline
                        : _expanded,
                    child: _AccessoryScope(
                      placement: placement,
                      child: Padding(padding: _accessoryPadding, child: child),
                    ),
                  ),
                ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

/// Notes its child's size after each layout.
class _SizeNote extends SingleChildRenderObjectWidget {
  const _SizeNote({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  _RenderSizeNote createRenderObject(BuildContext context) =>
      _RenderSizeNote(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeNote renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeNote extends RenderProxyBox {
  _RenderSizeNote(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}

/// The bar on its way into the circle and resting there, one liquid morph
/// on [morph] as UIKit runs it for a minimize and for a search tab alike:
/// the glass's box goes from the bar to the circle, the selected tab's
/// glyph travels to the circle's center, and its title and the other tabs
/// dissolve (read from UIKit, notes private; whether the dissolve also
/// blurs is not read).
class _CollapsingTabs extends StatefulWidget {
  const _CollapsingTabs({
    required this.width,
    required this.barSize,
    required this.morph,
    required this.destinations,
    required this.selectedIndex,
    required this.look,
    required this.rtl,
    required this.onTap,
    this.takesTaps = true,
  });

  final double width;
  final Size barSize;
  final ValueListenable<double> morph;
  final List<GlassTabDestination> destinations;
  final int selectedIndex;
  final GlassTabBarStyle look;
  final bool rtl;
  final VoidCallback onTap;
  final bool takesTaps;

  @override
  State<_CollapsingTabs> createState() => _CollapsingTabsState();
}

class _CollapsingTabsState extends State<_CollapsingTabs> {
  final _frame = ValueNotifier(const GlassFrame());
  final _fade = ValueNotifier<double>(1);
  final _travel = ValueNotifier(Offset.zero);

  @override
  void initState() {
    super.initState();
    widget.morph.addListener(_moved);
    _moved();
  }

  @override
  void didUpdateWidget(_CollapsingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.morph, widget.morph)) {
      oldWidget.morph.removeListener(_moved);
      widget.morph.addListener(_moved);
    }
    _moved();
  }

  @override
  void dispose() {
    widget.morph.removeListener(_moved);
    _frame.dispose();
    _fade.dispose();
    _travel.dispose();
    super.dispose();
  }

  void _moved() {
    final morph = widget.morph.value;
    _frame.value = GlassFrame(rect: Rect.lerp(_rest, _circle, morph));
    _fade.value = (1 - morph).clamp(0.0, 1.0);
    _travel.value = _glyphTravel * morph;
  }

  Rect get _rest => Rect.fromLTWH(
    (widget.width - widget.barSize.width) / 2,
    0,
    widget.barSize.width,
    GlassTabBar.height,
  );

  Rect get _circle {
    const inset = TabBarMinimizeTuning.collapsedInset;
    const size = TabBarMinimizeTuning.collapsedSize;
    return Rect.fromLTWH(
      widget.rtl ? widget.width - inset - size : inset,
      inset,
      size,
      size,
    );
  }

  double get _pitch => widget.destinations.isEmpty
      ? 0
      : math.max(0, widget.barSize.width - 2 * _sideInset) /
            widget.destinations.length;

  Rect _slot(int index) {
    final count = widget.destinations.length;
    final at = widget.rtl ? count - 1 - index : index;
    return Rect.fromLTWH(
      _rest.left + _sideInset + _pitch * at,
      0,
      _pitch,
      GlassTabBar.height,
    );
  }

  // How far the selected glyph travels to the circle's center; it starts
  // centered in [_column].
  Offset get _glyphTravel {
    final selected = widget.selectedIndex;
    if (selected < 0) return Offset.zero;
    const column = _column;
    final glyph = Offset(
      _slot(selected).center.dx,
      (GlassTabBar.height - column) / 2 + GlassTabBar.iconSize / 2,
    );
    return _circle.center - glyph;
  }

  static const double _sideInset = 8;

  // The column of glyph, gap and a 10 point title line, the line taken as
  // 12 points (by eye), centered in the bar.
  static const double _column =
      GlassTabBar.iconSize + GlassTabBar.labelGap + 12;

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final selected = widget.selectedIndex;
    final background = widget.look.backgroundColor?.resolve(const {});
    Widget tab(int index, Set<WidgetState> states) => _TabContent(
      destination: destinations[index],
      look: widget.look,
      states: states,
    );
    final circle = _circle;
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.bar,
            glass: Glass.regular(
              tint: background == null
                  ? null
                  : GlassDynamicColor.resolve(background, context),
            ),
            frame: _frame,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: _CapsuleClip(_frame),
              child: Stack(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Positioned.fromRect(
                      rect: _slot(i),
                      child: i == selected
                          ? MotionTransition(
                              offset: _travel,
                              child: _TitleFade(
                                fade: _fade,
                                child: tab(i, const {WidgetState.selected}),
                              ),
                            )
                          : MotionTransition(
                              opacity: _fade,
                              child: tab(i, const {}),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.takesTaps)
          Positioned.fromRect(
            rect: circle,
            child: Semantics(
              button: true,
              label: selected < 0 ? null : destinations[selected].semanticLabel,
              onTap: widget.onTap,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
              ),
            ),
          ),
      ],
    );
  }
}

/// Fades the part of a tab below its glyph, the title, by [fade].
class _TitleFade extends SingleChildRenderObjectWidget {
  const _TitleFade({required this.fade, required super.child});

  final ValueListenable<double> fade;

  @override
  _RenderTitleFade createRenderObject(BuildContext context) =>
      _RenderTitleFade(fade);

  @override
  void updateRenderObject(BuildContext context, _RenderTitleFade renderObject) {
    renderObject.fade = fade;
  }
}

class _RenderTitleFade extends RenderProxyBox {
  _RenderTitleFade(this._fade);

  ValueListenable<double> _fade;
  set fade(ValueListenable<double> value) {
    if (identical(value, _fade)) return;
    if (attached) _fade.removeListener(markNeedsPaint);
    _fade = value;
    if (attached) _fade.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ValueListenable<double> get fade => _fade;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fade.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _fade.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    const column = _CollapsingTabsState._column;
    final split = (size.height - column) / 2 + GlassTabBar.iconSize;
    context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, 0, size.width, split),
      (context, offset) => context.paintChild(child, offset),
    );
    final alpha = Color.getAlphaFromOpacity(_fade.value.clamp(0.0, 1.0));
    if (alpha == 0) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(0, split, size.width, size.height),
      (context, offset) => context.pushOpacity(
        offset,
        alpha,
        (context, offset) => context.paintChild(child, offset),
      ),
    );
  }
}

/// The capsule of the glass's box in each frame.
class _CapsuleClip extends CustomClipper<Path> {
  _CapsuleClip(this.frame) : super(reclip: frame);

  final ValueListenable<GlassFrame> frame;

  @override
  Path getClip(Size size) {
    final rect = frame.value.rect ?? Offset.zero & size;
    final path = Path();
    path.addRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.min(rect.width, rect.height) / 2),
      ),
    );
    return path;
  }

  @override
  bool shouldReclip(_CapsuleClip oldClipper) => oldClipper.frame != frame;
}

/// The space between the bottom accessory's glass and its content (top 8,
/// leading 16, bottom 8, trailing 16; read from UIKit).
const _accessoryPadding = EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8);

/// What a search tab bar shows and which parts take touches, rebuilt only
/// when one of them changes.
@immutable
class _SearchState {
  const _SearchState({
    required this.resting,
    required this.settled,
    required this.focused,
    required this.closeShown,
    required this.tabTakesTaps,
  });

  /// The bar rests as a bar and the search circle takes taps.
  final bool resting;

  /// The search is open and the morph into the field has settled: the
  /// field itself shows.
  final bool settled;

  /// The field has the focus or heads there.
  final bool focused;

  final bool closeShown;
  final bool tabTakesTaps;

  @override
  bool operator ==(Object other) =>
      other is _SearchState &&
      other.resting == resting &&
      other.settled == settled &&
      other.focused == focused &&
      other.closeShown == closeShown &&
      other.tabTakesTaps == tabTakesTaps;

  @override
  int get hashCode =>
      Object.hash(resting, settled, focused, closeShown, tabTakesTaps);
}

enum _SearchSlot { bar, tabs, circle, field, close }

/// A tab bar and its search tab, laid out over the screen's bottom.
class _SearchTabBar extends StatefulWidget {
  const _SearchTabBar({
    required this.controller,
    required this.destinations,
    required this.selectedIndex,
    required this.look,
    required this.bar,
  });

  final GlassSearchController controller;
  final List<GlassTabDestination> destinations;
  final int selectedIndex;
  final GlassTabBarStyle look;
  final Widget bar;

  @override
  State<_SearchTabBar> createState() => _SearchTabBarState();
}

class _SearchTabBarState extends State<_SearchTabBar> implements MotionDriver {
  late final _morph = MotionValue<double>(
    _open ? 1 : 0,
    spring: SearchTuning.tabSpring,
  );
  final _focusMotion = SearchMotion(spring: SearchTuning.tabFocusSpring);
  final _focus = FocusNode(debugLabel: 'GlassTabBar search');
  final _q = ValueNotifier<double>(0);
  final _p = ValueNotifier<double>(0);
  final _tabFade = ValueNotifier<double>(1);
  final _placeholder = ValueNotifier<double>(0);
  final _closeScale = ValueNotifier<double>(SearchTuning.appearScale);
  late final _state = ValueNotifier<_SearchState>(_stateNow());
  late bool _open = widget.controller.isOpen;
  double? _keyboardWait;
  double? _frozenKeyboard;
  double? _activateAt;
  double _keyboard = 0;
  double _barWidth = 0;

  // The swing of the morph at which it lands. NEAR: the shapes land by up
  // to 0.001 of their travel.
  static const double _morphRest = 1e-3;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_focusChanged);
    MotionClock.instance.addDriver(this);
    _publish(_now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focusMotion.reducedMotion = GlassTraits.of(context).reduceMotion;
    _keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (_keyboardWait != null && _keyboard > 0) {
      _keyboardWait = null;
      _focusMotion.focus(_now, delay: SearchTuning.tabKeyboardLag);
      MotionClock.instance.wake(this);
    }
  }

  @override
  void didUpdateWidget(_SearchTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_focusChanged);
    MotionClock.instance.removeDriver(this);
    _focus.dispose();
    _q.dispose();
    _p.dispose();
    _tabFade.dispose();
    _placeholder.dispose();
    _closeScale.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  bool get isActive =>
      !_morph.isWithin(_now, _morphRest) ||
      !_focusMotion.isSettled ||
      _keyboardWait != null ||
      _activateAt != null;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _focusMotion.advance(time);
    final wait = _keyboardWait;
    if (wait != null && time - wait >= SearchTuning.keyboardWaitLimit) {
      _keyboardWait = null;
      _focusMotion.focus(time, delay: 0);
    }
    _focusMotion.land(time);
    if (_morph.valueAt(time) != _morph.target &&
        _morph.isWithin(time, _morphRest)) {
      _morph.snap(time, _morph.target);
    }
    final activate = _activateAt;
    if (activate != null && time >= activate) {
      _activateAt = null;
      if (_open && !_focus.hasFocus) _focus.requestFocus();
    }
    _publish(time);
  }

  void _publish(double time) {
    final q = _morph.valueAt(time);
    final p = _focusMotion.progress;
    _q.value = q;
    _p.value = p;
    _tabFade.value = (1 - p).clamp(0.0, 1.0);
    _placeholder.value = ((q - 0.4) / 0.6).clamp(0.0, 1.0);
    _closeScale.value = SearchMotion.appearScaleFor(p);
    _state.value = _stateNow();
  }

  _SearchState _stateNow() {
    final q = _q.value;
    final p = _p.value;
    final focused = _focusMotion.isFocused;
    final settled = _open && (q - 1).abs() < 0.001;
    return _SearchState(
      resting: !_open && q.abs() < 0.001,
      settled: settled,
      focused: focused,
      closeShown: settled && (p > 0.001 || focused),
      tabTakesTaps: _open && p < 0.5,
    );
  }

  void _wake() {
    _publish(_now);
    MotionClock.instance.wake(this);
  }

  void _changed() {
    final open = widget.controller.isOpen;
    if (open == _open) return;
    _open = open;
    final t = _now;
    _morph.retarget(t, open ? 1 : 0);
    _activateAt = open ? t + SearchTuning.tabActivationDelay : null;
    if (!open) {
      _focus.unfocus();
      // The query clears after the frame that closed the search, as the
      // field turns back.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_open) widget.controller.clear();
      });
    }
    _wake();
  }

  void _focusChanged() {
    final t = _now;
    if (_focus.hasFocus && !_focusMotion.isFocused && _keyboardWait == null) {
      _frozenKeyboard = null;
      if (_keyboard > 0) {
        _focusMotion.focus(t, delay: SearchTuning.tabKeyboardLag);
      } else {
        _keyboardWait = t;
      }
    } else if (!_focus.hasFocus &&
        (_focusMotion.isFocused || _keyboardWait != null)) {
      _keyboardWait = null;
      _frozenKeyboard = _keyboard;
      _focusMotion.unfocus(t, delay: SearchTuning.tabUnfocusDelay);
    }
    _wake();
  }

  void _end() {
    widget.controller.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    final glyph = GlassDynamicColor.resolve(label, context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _end},
      child: ValueListenableBuilder<_SearchState>(
        valueListenable: _state,
        builder: (context, state, _) => CustomMultiChildLayout(
          delegate: _SearchTabLayout(
            q: _q,
            p: _p,
            keyboard: state.focused ? _keyboard : _frozenKeyboard ?? _keyboard,
            rtl: rtl,
            onBarWidth: (width) => _barWidth = width,
          ),
          children: [
            LayoutId(
              id: _SearchSlot.bar,
              child: Visibility(
                visible: state.resting,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: widget.bar,
              ),
            ),
            if (!state.resting && widget.destinations.isNotEmpty)
              LayoutId(
                id: _SearchSlot.tabs,
                child: MotionTransition(
                  opacity: _tabFade,
                  child: _CollapsingTabs(
                    width: _barWidth,
                    barSize: Size(_barWidth, GlassTabBar.height),
                    morph: _q,
                    destinations: widget.destinations,
                    selectedIndex: widget.selectedIndex,
                    look: widget.look,
                    rtl: rtl,
                    onTap: widget.controller.closeView,
                    takesTaps: state.tabTakesTaps,
                  ),
                ),
              ),
            if (!state.settled)
              LayoutId(
                id: _SearchSlot.circle,
                child: IgnorePointer(
                  ignoring: !state.resting,
                  child: _SearchCircle(
                    q: _q,
                    placeholder: _placeholder,
                    glyph: glyph,
                    rtl: rtl,
                    onTap: widget.controller.openView,
                  ),
                ),
              ),
            if (_open || state.settled)
              LayoutId(
                id: _SearchSlot.field,
                child: IgnorePointer(
                  ignoring: !state.settled,
                  child: Opacity(
                    opacity: state.settled ? 1 : 0,
                    alwaysIncludeSemantics: true,
                    child: GlassSearchField(
                      controller: widget.controller,
                      focusNode: _focus,
                    ),
                  ),
                ),
              ),
            if (state.closeShown)
              LayoutId(
                id: _SearchSlot.close,
                child: IgnorePointer(
                  ignoring: !state.focused,
                  child: MotionTransition(
                    opacity: _p,
                    scale: _closeScale,
                    child: GlassButton(
                      onPressed: _end,
                      child: Semantics(
                        label: 'Close',
                        child: SizedBox.fromSize(
                          size: SearchTuning.closeGlyphSize,
                          child: CustomPaint(
                            painter: SearchCrossPainter(glyph),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Places a search tab bar's parts from the morph [q] and the focus [p],
/// laid out again on every change of either without a rebuild.
class _SearchTabLayout extends MultiChildLayoutDelegate {
  _SearchTabLayout({
    required this.q,
    required this.p,
    required this.keyboard,
    required this.rtl,
    required this.onBarWidth,
  }) : super(relayout: Listenable.merge([q, p]));

  final ValueListenable<double> q;
  final ValueListenable<double> p;
  final double keyboard;
  final bool rtl;
  final ValueChanged<double> onBarWidth;

  @override
  void performLayout(Size size) {
    final bar = layoutChild(_SearchSlot.bar, BoxConstraints.loose(size));
    onBarWidth(bar.width);
    final g = searchTabLayout(
      size: size,
      barWidth: bar.width,
      keyboard: keyboard,
      rtl: rtl,
    );
    positionChild(_SearchSlot.bar, g.bar.topLeft);
    void place(_SearchSlot slot, Rect rect) {
      if (!hasChild(slot)) return;
      final box = Rect.fromLTWH(
        rect.left,
        rect.top,
        math.max(0, rect.width),
        math.max(0, rect.height),
      );
      layoutChild(slot, BoxConstraints.tight(box.size));
      positionChild(slot, box.topLeft);
    }

    final morph = q.value;
    final focus = p.value;
    place(_SearchSlot.tabs, g.bar);
    place(_SearchSlot.circle, Rect.lerp(g.search, g.field, morph)!);
    final settled = !hasChild(_SearchSlot.circle);
    place(
      _SearchSlot.field,
      settled ? lerpRect(g.field, g.focusedField, focus) : g.field,
    );
    final closeFrom = Rect.fromLTWH(
      rtl ? g.field.left : g.field.right - SearchTuning.height,
      g.field.top,
      SearchTuning.height,
      SearchTuning.height,
    );
    place(_SearchSlot.close, Rect.lerp(closeFrom, g.close, focus)!);
  }

  @override
  bool shouldRelayout(_SearchTabLayout oldDelegate) =>
      keyboard != oldDelegate.keyboard ||
      rtl != oldDelegate.rtl ||
      !identical(q, oldDelegate.q) ||
      !identical(p, oldDelegate.p);
}

/// The search tab's circle on its way into the field: its glass, the
/// magnifier travelling from the circle's center to the field's glyph and
/// the placeholder fading in over the morph's last 60 percent (matched to
/// a simulator film by eye).
class _SearchCircle extends StatelessWidget {
  const _SearchCircle({
    required this.q,
    required this.placeholder,
    required this.glyph,
    required this.rtl,
    required this.onTap,
  });

  final ValueListenable<double> q;
  final ValueListenable<double> placeholder;
  final Color glyph;
  final bool rtl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Search',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassSurface(
        child: CustomMultiChildLayout(
          delegate: _CircleLayout(q: q, rtl: rtl),
          children: [
            LayoutId(
              id: 0,
              child: CustomPaint(painter: SearchMagnifierPainter(glyph)),
            ),
            LayoutId(
              id: 1,
              child: MotionTransition(
                opacity: placeholder,
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DefaultTextStyle(
                      style: resolveGlassText(
                        const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ).copyWith(
                          color: GlassDynamicColor.resolve(
                            GlassSearchField.placeholderColors.resolve(
                                  const {},
                                ) ??
                                GlassColors.secondaryLabel,
                            context,
                          ),
                        ),
                        context,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      child: const Text('Search'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CircleLayout extends MultiChildLayoutDelegate {
  _CircleLayout({required this.q, required this.rtl}) : super(relayout: q);

  final ValueListenable<double> q;
  final bool rtl;

  @override
  void performLayout(Size size) {
    const glyph = SearchTuning.glyphSize;
    final t = q.value.clamp(0.0, 1.0);
    final grown = 1 + 0.15 * (1 - t);
    final box = Size(glyph.width * grown, glyph.height * grown);
    final start = Offset(
      rtl
          ? size.width - SearchTuning.glyphInset - glyph.width / 2
          : SearchTuning.glyphInset + glyph.width / 2,
      size.height / 2,
    );
    final center = Offset.lerp(size.center(Offset.zero), start, t)!;
    layoutChild(0, BoxConstraints.tight(box));
    positionChild(0, center - Offset(box.width / 2, box.height / 2));
    final text = Rect.fromLTRB(
      rtl ? 8 : SearchTuning.textInset,
      0,
      rtl ? size.width - SearchTuning.textInset : size.width - 8,
      size.height,
    );
    layoutChild(
      1,
      BoxConstraints.tight(
        Size(math.max(0, text.width), math.max(0, text.height)),
      ),
    );
    positionChild(1, text.topLeft);
  }

  @override
  bool shouldRelayout(_CircleLayout oldDelegate) =>
      rtl != oldDelegate.rtl || !identical(q, oldDelegate.q);
}
