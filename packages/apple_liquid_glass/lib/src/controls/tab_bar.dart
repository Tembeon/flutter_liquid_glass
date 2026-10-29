import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/selector.dart';
import 'package:apple_liquid_glass/src/motion/tab_minimize.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
/// 7 points inside the bar's leading side, on UIKit's collapse springs; a
/// tap on the circle, the content's top end or a scroll past its far end
/// expands it. A finger held on the circle does not yet expand the bar
/// under it, and a drag from the circle does not yet become the bar's
/// selection drag, as they do in UIKit. Put it in a `GlassTabScaffold`.
///
/// A [bottomAccessory], a mini player say, stands on its own glass 48
/// points tall, 8 points above the bar across the bar group, and beside
/// the circle while the bar is minimized; [accessoryPlacementOf] tells its
/// content which, flipping once the glass has arrived inline and as soon
/// as it leaves. Its height and spacings are not measured.
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
          ? TabBarMinimizeTuning.spacing + TabBarMinimizeTuning.accessoryHeight
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
    final accessory = bottomAccessory;
    if (!minimizeBehavior.minimizes && accessory == null) return bar;
    return _MinimizingBar(
      behavior: minimizeBehavior,
      accessory: accessory,
      destinations: destinations,
      selectedIndex: destinations.isEmpty
          ? -1
          : selectedIndex.clamp(0, destinations.length - 1),
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
/// as the hint scale, the glass's and the content's ways to the circle, and
/// whether the bar rests expanded.
final class _MinimizeBody implements MotionDriver {
  _MinimizeBody(GlassTabBarMinimizeBehavior behavior)
    : motion = TabBarMinimizeMotion(behavior: behavior);

  final TabBarMinimizeMotion motion;
  final hint = ValueNotifier<double>(1);
  final shape = ValueNotifier<double>(0);
  final content = ValueNotifier<double>(0);
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
    shape.value = motion.shape;
    content.value = motion.content;
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
    shape.dispose();
    content.dispose();
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
                    body: _body,
                    destinations: widget.destinations,
                    selectedIndex: widget.selectedIndex,
                    look: widget.look,
                    rtl: rtl,
                    onExpand: _expand,
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
/// moving once the glass has arrived inline and as soon as it leaves.
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

  @override
  void initState() {
    super.initState();
    widget.body.shape.addListener(_moved);
    _moved();
  }

  @override
  void didUpdateWidget(_Accessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    _moved();
  }

  @override
  void dispose() {
    widget.body.shape.removeListener(_moved);
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

  Rect get _inline {
    const inset = TabBarMinimizeTuning.collapsedInset;
    const size = TabBarMinimizeTuning.collapsedSize;
    const gap = TabBarMinimizeTuning.spacing;
    const top =
        TabBarMinimizeTuning.spacing +
        TabBarMinimizeTuning.accessoryHeight +
        inset;
    return _mirror(
      Rect.fromLTRB(
        inset + size + gap,
        top,
        widget.width - inset,
        top + TabBarMinimizeTuning.accessoryHeight,
      ),
    );
  }

  void _moved() {
    final shape = widget.body.shape.value.clamp(0.0, 1.0);
    _frame.value = GlassFrame(rect: Rect.lerp(_expanded, _inline, shape));
    _placement.value = shape >= 0.999
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
                    child: _AccessoryScope(placement: placement, child: child!),
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

/// The bar on its way into the circle and resting there: the glass's box
/// goes from the bar to the circle on [_MinimizeBody.shape], and on
/// [_MinimizeBody.content] the other tabs fade and the selected tab's glyph
/// travels to the circle's center while its title fades. The springs are
/// UIKit's; this choreography of the content is by eye, not yet compared
/// with a recording.
class _CollapsingTabs extends StatefulWidget {
  const _CollapsingTabs({
    required this.width,
    required this.barSize,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.look,
    required this.rtl,
    required this.onExpand,
  });

  final double width;
  final Size barSize;
  final _MinimizeBody body;
  final List<GlassTabDestination> destinations;
  final int selectedIndex;
  final GlassTabBarStyle look;
  final bool rtl;
  final VoidCallback onExpand;

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
    widget.body.shape.addListener(_moved);
    widget.body.content.addListener(_moved);
    _moved();
  }

  @override
  void didUpdateWidget(_CollapsingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _moved();
  }

  @override
  void dispose() {
    widget.body.shape.removeListener(_moved);
    widget.body.content.removeListener(_moved);
    _frame.dispose();
    _fade.dispose();
    _travel.dispose();
    super.dispose();
  }

  void _moved() {
    final shape = widget.body.shape.value.clamp(0.0, 1.0);
    final content = widget.body.content.value.clamp(0.0, 1.0);
    _frame.value = GlassFrame(rect: Rect.lerp(_rest, _circle, shape));
    _fade.value = (1 - 2 * content).clamp(0.0, 1.0);
    _travel.value = _glyphTravel * content;
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

  // The glyph's center before it travels: the column of glyph, gap and a
  // 10 point title line (taken as 12 points, by eye) centered in the bar.
  Offset get _glyphTravel {
    final selected = widget.selectedIndex;
    if (selected < 0) return Offset.zero;
    const column = GlassTabBar.iconSize + GlassTabBar.labelGap + _titleLine;
    final glyph = Offset(
      _slot(selected).center.dx,
      (GlassTabBar.height - column) / 2 + GlassTabBar.iconSize / 2,
    );
    return _circle.center - glyph;
  }

  static const double _sideInset = 8;
  static const double _titleLine = 12;

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
        Positioned.fromRect(
          rect: circle,
          child: Semantics(
            button: true,
            label: selected < 0 ? null : destinations[selected].semanticLabel,
            onTap: widget.onExpand,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onExpand,
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
    const column =
        GlassTabBar.iconSize +
        GlassTabBar.labelGap +
        _CollapsingTabsState._titleLine;
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
