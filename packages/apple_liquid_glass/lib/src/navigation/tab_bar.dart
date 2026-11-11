import 'dart:math' as math;

import 'package:apple_liquid_glass/controls.dart';
import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/navigation/toolbar.dart';
import 'package:apple_liquid_glass/src/raw/selector.dart';
import 'package:apple_liquid_glass/surfaces.dart';
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
    this.id,
  });

  /// What tells the tab apart across changes of the destinations, or null
  /// to tell it by its position: a change inside `withSpring` slides the
  /// tabs that stay, fades new ones in and old ones out, and the lens
  /// moves with its tab ([RawGlassSelector.itemKeys]). Not measured: UIKit's
  /// animated setItems was not captured.
  final Object? id;

  /// The tab's glyph, 24 points by default.
  final Widget icon;

  /// The tab's title.
  final Widget label;

  /// The glyph the tab shows inside the selection lens (UIKit
  /// `selectedImage`), or null for [icon]. The bar builds each tab several
  /// times at once, so neither glyph may carry a `GlobalKey` or state that
  /// has to be unique.
  final Widget? selectedIcon;

  /// A mark at the top trailing corner of the glyph, usually a
  /// [GlassBadge]; its placement is by eye, not measured (tab bar
  /// passport).
  final Widget? badge;

  /// Whether the tab can be selected. A disabled tab draws at half opacity
  /// (not measured).
  final bool enabled;

  /// What accessibility reads for the tab; null reads the text of its
  /// label: a [Text]'s, or an `Icon`'s semantic label.
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
class GlassTabBarStyle extends GlassStyle<GlassTabBarStyle> {
  /// Creates a style.
  const GlassTabBarStyle({
    this.backgroundColor,
    this.thumbColor,
    this.foregroundColor,
    this.textStyle,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassTabBarStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassTabBarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassTabBarStyle>(context);

  /// A tint over the bar's glass (UIKit `barTintColor`); none by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The resting lens under the selected tab; [GlassTabBar.thumb] by
  /// default.
  final WidgetStateProperty<Color?>? thumbColor;

  /// The color of a tab's glyph and title: inside the lens the theme's
  /// primary color, else [GlassTabBar.selected]; outside it
  /// [GlassTabBar.unselected]; by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The text style of a tab's title: 10 points, medium, and semibold
  /// inside the lens, by default (tab bar passport).
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The ring inside a tab focused from the keyboard; null derives it from
  /// systemBlue as Flutter's Cupertino controls do, and a transparent color
  /// draws none.
  final Color? focusColor;

  /// What a mouse over a tab adds to its colors; null for the wash of a
  /// glass body at half a press's strength, and a transparent color shows
  /// none.
  final Color? hoverColor;

  /// Builds the bar's look in place of the default one; the bar then
  /// ignores [thumbColor], and [backgroundColor] still tints the minimized
  /// circle and the bottom accessory. Null leaves it to the
  /// theme's builder, then the default look.
  final GlassSelectorBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassTabBarStyle merge(GlassTabBarStyle? other) {
    if (other == null) return this;
    return GlassTabBarStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassTabBarStyle lerp(GlassTabBarStyle other, double t) {
    if (identical(this, other)) return this;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      GlassStyle.lerpNullable(GlassDynamicColor.lerp),
    );
    return GlassTabBarStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      thumbColor: color(thumbColor, other.thumbColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTabBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.thumbColor == thumbColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    thumbColor,
    foregroundColor,
    textStyle,
    focusColor,
    hoverColor,
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
/// A glass bar 62 points tall whatever its titles say. A bar of four or more
/// tabs, or one with a [bottomAccessory] or a [searchController], spans the
/// width it is given and its tabs adapt inside it: to the iPhone's even
/// slots while the titles fit, then to slots as wide as each title asks. A
/// bar of two or three tabs is as wide as its widest title asks, up to the
/// width it is given; UIKit's does the same. Given 568 points or more, where
/// UIKit's metrics are not measured, a bar takes 360 points at most. A title
/// stays on one line at
/// its size and ends in an ellipsis where it does not fit; UIKit first
/// tightens its tracking by up to 1.2 points, which this bar does not (NEAR).
/// Its motion is [RawGlassSelector]'s with
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
/// 0.8, response 0.3); the circle stays the same bar throughout, so the
/// morph turns around from wherever it is. A finger on the circle lifts it to
/// 64 points; lifted in place, however late, the finger expands the bar and
/// selects nothing; moved 4 points along the bar, it expands the bar and
/// carries the lens, and the tab under it on the lift is selected, as on
/// the expanded bar. The content's top end or a scroll past its far end also
/// expands it. Put it in a `GlassTabScaffold`.
///
/// A [bottomAccessory], a mini player say, stands on its own glass 48
/// points tall, 8 points above the bar across the bar group, its content
/// inset 16 points at the sides and 8 at the top and bottom; while the bar
/// is minimized it stands level with the circle, 14 points beside it. It
/// travels there along the bar first and up after, and back up first and
/// along after, the second axis 0.05 s late. [accessoryPlacementOf] tells
/// its content which place it heads for, flipping as the transition
/// starts (read from UIKit, notes private).
///
/// Focused from the keyboard, a tab draws Flutter's Cupertino focus ring
/// inside its slot, and a mouse over a tab washes its slot as a glass
/// body's hover does; the search circle shows both on its glass, as a glass
/// button does (the rule of the glass controls; an approximation, not
/// measured).
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
          ?.notifier
          ?.value ??
      GlassTabAccessoryPlacement.expanded;

  /// The height of the bar group: the bar and, with [accessory], the
  /// accessory above it.
  static double groupHeight({required bool accessory}) =>
      height +
      (accessory ? _Minimized.accessoryGap + _Minimized.accessoryHeight : 0);

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
    backgroundColor: GlassStyle.allOrNull(backgroundColor),
    thumbColor: GlassStyle.allOrNull(thumbColor),
    foregroundColor: foregroundColor == null && selectedForegroundColor == null
        ? null
        : WidgetStateMapper<Color?>({
            WidgetState.selected: selectedForegroundColor,
            WidgetState.any: foregroundColor,
          }),
    textStyle: textStyle == null && selectedTextStyle == null
        ? null
        : WidgetStateMapper<TextStyle?>({
            WidgetState.selected: selectedTextStyle,
            WidgetState.any: textStyle,
          }),
  );

  GlassTabBarStyle _defaults(BuildContext context) => GlassTabBarStyle(
    thumbColor: const WidgetStatePropertyAll(thumb),
    foregroundColor: WidgetStateMapper<Color?>({
      WidgetState.selected: GlassTheme.primaryColorOf(context) ?? selected,
      WidgetState.any: unselected,
    }),
    textStyle: const WidgetStateMapper<TextStyle?>({
      WidgetState.selected: _selectedTitle,
      WidgetState.any: _title,
    }),
  );

  @override
  Widget build(BuildContext context) {
    final themed = GlassTabBarStyle.maybeOf(context);
    final look = (style ?? const GlassTabBarStyle())
        .merge(themed)
        .merge(_defaults(context));
    final onSelected = onDestinationSelected;
    Widget bar(GlassSelectorCollapse? collapse, {required bool hosted}) =>
        RawGlassSelector(
          motion: GlassSelectorMotion.tabBar,
          collapse: collapse,
          hosted: hosted,
          itemCount: destinations.length,
          itemKeys: [
            for (final (i, destination) in destinations.indexed)
              if (destination.id == null) (null, i) else (destination.id, null),
          ],
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
          itemLabels: [
            for (final destination in destinations)
              destination.semanticLabel ??
                  glassSelectorLabelOf(destination.label),
          ],
          itemBuilder: (context, index, states) => _TabContent(
            destination: destinations[index],
            look: look,
            states: states,
            morph: collapse?.morph,
          ),
          builder:
              style?.builder ??
              themed?.builder ??
              (context, details) => _TabBarLook(details: details, look: look),
        );
    if (searchController case final search?) {
      return _SearchTabBar(controller: search, bar: bar);
    }
    final accessory = bottomAccessory;
    if (!minimizeBehavior.minimizes && accessory == null) {
      return bar(null, hosted: false);
    }
    return _MinimizingBar(
      behavior: minimizeBehavior,
      accessory: accessory,
      look: look,
      bar: bar,
    );
  }
}

/// The lifted lens shows the swollen bar's edges 0.890 of its height apart
/// (iPhone 16 Pro references): a shrink of 0.16 toward three quarters of
/// the center line, 0.897 on the liquid renderer.
const _lens = GlassLens(shrink: 0.16, shrinkRim: 0.75);

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
      ValueNotifier<GlassLensShrink>? lensShrink,
    }) => GlassSurface.live(
      role: role,
      lens: lens,
      lensShrink: lensShrink,
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
            lensShrink: details.lensShrink,
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

/// A tab's glyph and title where UIKit places them in a bar 62 points tall,
/// not as a column: the glyph's center 24 points from the top, the title's
/// bottom at 51, so a title in a taller script grows upward and moves
/// nothing. [morph] takes the title away as the bar turns into its circle.
class _TabItem extends MultiChildRenderObjectWidget {
  const _TabItem({
    required this.morph,
    required this.titleGoneAt,
    required super.children,
  });

  final ValueListenable<double>? morph;
  final double titleGoneAt;

  @override
  _RenderTabItem createRenderObject(BuildContext context) =>
      _RenderTabItem(morph, titleGoneAt);

  @override
  void updateRenderObject(BuildContext context, _RenderTabItem renderObject) {
    renderObject.morph = morph;
    renderObject.titleGoneAt = titleGoneAt;
  }
}

class _TabItemParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTabItem extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabItemParentData> {
  _RenderTabItem(this._morph, this._titleGoneAt);

  static const double _titleBottom = 51;

  ValueListenable<double>? _morph;
  ValueListenable<double>? get morph => _morph;
  set morph(ValueListenable<double>? value) {
    if (identical(value, _morph)) return;
    if (attached) _morph?.removeListener(markNeedsPaint);
    _morph = value;
    if (attached) _morph?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _titleGoneAt;
  double get titleGoneAt => _titleGoneAt;
  set titleGoneAt(double value) {
    if (value == _titleGoneAt) return;
    _titleGoneAt = value;
    markNeedsPaint();
  }

  RenderBox get _glyph => firstChild!;
  RenderBox get _title => lastChild!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _morph?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _morph?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabItemParentData) {
      child.parentData = _TabItemParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    _glyph.getMaxIntrinsicWidth(double.infinity),
    _title.getMaxIntrinsicWidth(double.infinity),
  );

  @override
  double computeMinIntrinsicHeight(double width) => GlassTabBar.height;

  @override
  double computeMaxIntrinsicHeight(double width) => GlassTabBar.height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : computeMaxIntrinsicWidth(GlassTabBar.height),
          GlassTabBar.height,
        ),
      );

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    _glyph.layout(const BoxConstraints(), parentUsesSize: true);
    (_glyph.parentData! as _TabItemParentData).offset = Offset(
      (size.width - _glyph.size.width) / 2,
      TabBarMinimizeMotion.glyphCenter - _glyph.size.height / 2,
    );
    _title.layout(
      BoxConstraints(
        maxWidth: math.max(0, size.width - TabBarLayout.titleMargin),
      ),
      parentUsesSize: true,
    );
    (_title.parentData! as _TabItemParentData).offset = Offset(
      (size.width - _title.size.width) / 2,
      _titleBottom - _title.size.height,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(
      _glyph,
      offset + (_glyph.parentData! as _TabItemParentData).offset,
    );
    final title = offset + (_title.parentData! as _TabItemParentData).offset;
    final morph = _morph?.value ?? 0;
    if (morph == 0) {
      context.paintChild(_title, title);
      return;
    }
    final left = 1 - morph / _titleGoneAt;
    if (left <= 0) return;
    context.pushOpacity(
      title,
      Color.getAlphaFromOpacity(left.clamp(0.0, 1.0)),
      (context, offset) => context.paintChild(_title, offset),
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

/// What a minimizing bar reads of its motion: the hint scale, the morph to
/// the circle, the accessory's two axes and whether the bar is minimized;
/// and the collapse it gives the bar below it.
final class _MinimizeFrames implements GlassSelectorCollapse {
  _MinimizeFrames(this.motion);

  final TabBarMinimizeMotion motion;
  late final hint = motion.select((m) => m.hint);
  @override
  late final morph = motion.select((m) => m.morph);
  @override
  late final press = motion.select((m) => m.press);
  late final accessoryX = motion.select((m) => m.accessoryX);
  late final accessoryY = motion.select((m) => m.accessoryY);
  late final minimized = motion.select((m) => m.minimized);

  /// Whether the group runs right to left, which puts the circle at its
  /// right.
  bool rtl = false;

  @override
  Rect circleIn(Size size) => _circleIn(size, rtl: rtl);

  @override
  bool get takesFinger => motion.minimized;

  @override
  void pressDown(double t, double x) => motion.pressDown(t, x);

  @override
  bool pressMove(double t, double x) => motion.pressMove(t, x);

  @override
  void pressUp(double t) => motion.pressUp(t);

  @override
  void pressCancel(double t) => motion.pressCancel(t);

  @override
  void activate() => motion.setMinimized(motion.clock.now, minimized: false);
}

/// The layout numbers of the minimized bar's circle and the bottom
/// accessory around it, read from UIKit's layout record on iOS 27.
abstract final class _Minimized {
  /// The space between the minimized bar and the expanded bar's edges:
  /// (62 - 48) / 2 = 7, read from UIKit's layout record; with the bar 21
  /// from the screen's side and bottom, the circle sits 28 from both, as
  /// the measured search tab circle does.
  static const double collapsedInset = 7;

  /// The space between the expanded bar and the accessory above it: the
  /// accessory's bottom stands 8 above the bar's top (read from UIKit).
  static const double accessoryGap = 8;

  /// The space between the minimized circle and the inline accessory, and
  /// between the accessory and a minimized search circle (read from
  /// UIKit).
  static const double inlineGap = 14;

  /// The height of the bottom accessory, expanded and inline (read from
  /// UIKit; content may opt into 48 - 64 there, which this package does
  /// not offer).
  static const double accessoryHeight = 48;
}

/// The minimized circle in a bar's box of [size], 7 points inside its
/// leading and bottom edges (read from UIKit).
Rect _circleIn(Size size, {required bool rtl}) {
  const inset = _Minimized.collapsedInset;
  const diameter = TabBarMinimizeMotion.collapsedSize;
  return Rect.fromLTWH(
    rtl ? size.width - inset - diameter : inset,
    size.height - inset - diameter,
    diameter,
    diameter,
  );
}

/// A tab bar that minimizes into a circle as the followed content scrolls.
class _MinimizingBar extends StatefulWidget {
  const _MinimizingBar({
    required this.behavior,
    required this.accessory,
    required this.look,
    required this.bar,
  });

  final GlassTabBarMinimizeBehavior behavior;
  final Widget? accessory;
  final GlassTabBarStyle look;
  final _BarBuilder bar;

  @override
  State<_MinimizingBar> createState() => _MinimizingBarState();
}

class _MinimizingBarState extends State<_MinimizingBar> {
  late final _MinimizeFrames _body = _MinimizeFrames(
    TabBarMinimizeMotion(behavior: widget.behavior),
  );

  double get _now => _body.motion.clock.now;
  ValueNotifier<MotionScroll?>? _active;
  MotionScroll? _scroll;
  MotionSelection<Object?>? _scrolling;
  MotionScrollPhase _phase = MotionScrollPhase.idle;

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
      _body.motion.setBehavior(_now, widget.behavior);
    }
  }

  @override
  void dispose() {
    _active?.removeListener(_follow);
    _scrolling?.removeRenderListener(_scrolled);
    super.dispose();
  }

  void _follow() {
    final next = _active?.value;
    if (identical(next, _scroll)) return;
    _scrolling?.removeRenderListener(_scrolled);
    _scroll = next;
    _phase = MotionScrollPhase.idle;
    final scrolling = _scrolling = next?.select((s) => (s.phase, s.metrics));
    scrolling?.addRenderListener(_scrolled);
  }

  void _scrolled() {
    final scroll = _scroll;
    final metrics = scroll?.metrics;
    if (scroll == null || metrics == null || !metrics.hasContentDimensions) {
      return;
    }
    final away = _body.motion.scrollAway;
    final phase = scroll.phase;
    final previous = _phase;
    _phase = phase;
    final offset = metrics.pixels;
    final min = metrics.minScrollExtent;
    final max = metrics.maxScrollExtent;
    if (!_body.motion.behavior.minimizes) {
      away.last = offset;
      return;
    }
    _body.motion.advance(_now);
    final user =
        previous == MotionScrollPhase.dragging ||
        previous == MotionScrollPhase.decelerating;
    if (phase == MotionScrollPhase.dragging &&
        previous != MotionScrollPhase.dragging) {
      away.beginDrag();
    }
    // A drag that began and went into its glide within one frame is heard
    // only as its glide.
    if (phase == MotionScrollPhase.decelerating && !user) {
      away.beginDrag();
      away.endDrag(decelerates: true);
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
  }

  @override
  Widget build(BuildContext context) => MotionScope(
    motion: _body.motion,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _body.motion.extent = width;
        final accessory = widget.accessory;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        _body.rtl = rtl;
        final bar = SizedBox(
          width: width,
          height: GlassTabBar.height,
          child: MotionTransition(
            scale: _body.hint,
            child: widget.bar(_body, hosted: accessory != null),
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
    ),
  );
}

class _AccessoryScope
    extends InheritedNotifier<ValueNotifier<GlassTabAccessoryPlacement>> {
  const _AccessoryScope({required super.notifier, required super.child});
}

/// Lays the accessory's content out in the rect of its placement, laid out
/// again when the placement changes, without a rebuild.
class _AccessoryLayout extends SingleChildLayoutDelegate {
  _AccessoryLayout({
    required this.placement,
    required this.inline,
    required this.expanded,
  }) : super(relayout: placement);

  final ValueListenable<GlassTabAccessoryPlacement> placement;
  final Rect inline;
  final Rect expanded;

  Rect get _rect =>
      placement.value == GlassTabAccessoryPlacement.inline ? inline : expanded;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(_rect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => _rect.topLeft;

  @override
  bool shouldRelayout(_AccessoryLayout oldDelegate) =>
      !identical(oldDelegate.placement, placement) ||
      oldDelegate.inline != inline ||
      oldDelegate.expanded != expanded;
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

  final _MinimizeFrames body;
  final double width;
  final bool rtl;
  final GlassTabBarStyle look;
  final Widget child;

  @override
  State<_Accessory> createState() => _AccessoryState();
}

class _AccessoryState extends State<_Accessory> {
  late MotionSelection<GlassFrame> _frame = _frameNow();
  late MotionSelection<Offset> _carried = _carriedNow();
  final _placement = ValueNotifier(GlassTabAccessoryPlacement.expanded);

  @override
  void initState() {
    super.initState();
    widget.body.minimized.addListener(_placed);
    _placed();
  }

  @override
  void didUpdateWidget(_Accessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.body, widget.body)) {
      oldWidget.body.minimized.removeListener(_placed);
      widget.body.minimized.addListener(_placed);
    }
    if (!identical(oldWidget.body, widget.body) ||
        oldWidget.width != widget.width ||
        oldWidget.rtl != widget.rtl) {
      _frame = _frameNow();
      _carried = _carriedNow();
    }
    _placed();
  }

  @override
  void dispose() {
    widget.body.minimized.removeListener(_placed);
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
    _Minimized.accessoryHeight,
  );

  Rect get _inline {
    const inset = _Minimized.collapsedInset;
    const circleTop =
        _Minimized.accessoryGap + _Minimized.accessoryHeight + inset;
    const circleEnd = inset + TabBarMinimizeMotion.collapsedSize;
    return _mirror(
      Rect.fromLTRB(
        circleEnd + _Minimized.inlineGap,
        circleTop,
        widget.width - inset,
        circleTop + _Minimized.accessoryHeight,
      ),
    );
  }

  MotionSelection<GlassFrame> _frameNow() {
    final body = widget.body;
    final from = _expanded;
    final to = _inline;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    return MotionSelection(() {
      final x = body.accessoryX.value;
      final y = body.accessoryY.value;
      return GlassFrame(
        rect: Rect.fromLTRB(
          lerp(from.left, to.left, x),
          lerp(from.top, to.top, y),
          lerp(from.right, to.right, x),
          lerp(from.bottom, to.bottom, y),
        ),
      );
    });
  }

  // The content stands laid out where it heads and travels there with the
  // glass's center.
  MotionSelection<Offset> _carriedNow() => MotionSelection(() {
    final end = widget.body.minimized.value ? _inline : _expanded;
    return _frame.value.rect!.center - end.center;
  });

  void _placed() {
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
          child: GlassClip.live(
            frame: _frame,
            child: CustomSingleChildLayout(
              delegate: _AccessoryLayout(
                placement: _placement,
                inline: _inline,
                expanded: _expanded,
              ),
              child: MotionTransition(
                offset: _carried,
                child: _AccessoryScope(
                  notifier: _placement,
                  child: Padding(
                    padding: _accessoryPadding,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The space between the bottom accessory's glass and its content (top 8,
/// leading 16, bottom 8, trailing 16; read from UIKit).
const _accessoryPadding = EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8);

enum _SearchSlot { bar, circle, field, close }

/// Builds a tab bar's selector under [collapse]; [hosted] when it hosts an
/// accessory or a search.
typedef _BarBuilder = Widget Function(
  GlassSelectorCollapse collapse, {
  required bool hosted,
});

/// A tab bar and its search tab, laid out over the screen's bottom.
class _SearchTabBar extends StatefulWidget {
  const _SearchTabBar({required this.controller, required this.bar});

  final GlassSearchController controller;
  final _BarBuilder bar;

  @override
  State<_SearchTabBar> createState() => _SearchTabBarState();
}

/// The motion of a tab bar with a search tab: the morph of the bar into
/// the field and back, the field's focus, and the focus the search takes
/// [SearchMotion.tabActivationDelay] after it opens.
final class _SearchTabMotion extends Motion {
  _SearchTabMotion({required bool open, required this.onActivate})
    : _open = open {
    _morph = own(
      MotionValue<double>(open ? 1 : 0, spring: SearchMotion.tabSpring),
      rest: _morphRest,
    );
    focus = own(SearchMotion.tabBar());
  }

  /// Gives the field the focus once the opened search activates.
  final VoidCallback onActivate;

  late final MotionValue<double> _morph;

  /// The field's focus transition.
  late final SearchMotion focus;

  bool _open;

  // NEAR: the shapes land by up to 0.001 of their travel.
  static double _morphRest() => 1e-3;

  static const _activation = #activation;

  /// Whether the search is open or heading there.
  bool get isOpen => _open;

  /// Runs [action] in the first frame after time [t], on the motion's
  /// timeline.
  void afterFrame(double t, VoidCallback action) =>
      at(t + 1e-6, (_) => action(), slot: #afterFrame);

  /// The morph: 0 a tab bar, 1 a search field.
  double get morph => _morph.valueAt(now);

  /// Opens or closes the search at time [t].
  void turn(double t, {required bool open}) {
    advance(t);
    if (open == _open) return;
    _open = open;
    _morph.retarget(t, open ? 1 : 0);
    if (open) {
      at(
        t + SearchMotion.tabActivationDelay,
        (_) => onActivate(),
        slot: _activation,
      );
    } else {
      unschedule(_activation);
    }
  }

  /// The bar rests as a bar and the search circle takes taps.
  bool get resting => !_open && morph.abs() < 0.001;

  /// The search is open and the morph into the field has settled: the
  /// field itself shows.
  bool get settled => _open && (morph - 1).abs() < 0.001;

  /// The close button shows: the field settled and focused or on its way.
  bool get closeShown =>
      settled &&
      (focus.progress > 0.001 || (focus.isFocused && !focus.waitsForKeyboard));

  /// A tap on the tab circle closes the search.
  bool get tabTakesTaps => _open && focus.progress < 0.5;
}

/// The collapse a search tab bar gives its bar: the bar turns into the tab
/// circle while searching, and a tap on the circle closes the search.
final class _SearchCollapse implements GlassSelectorCollapse {
  _SearchCollapse(this.motion, this.morph, this.onClose);

  final _SearchTabMotion motion;
  final VoidCallback onClose;

  @override
  final MotionSelection<double> morph;

  @override
  MotionSelection<double>? get press => null;

  /// Whether the bar runs right to left.
  bool rtl = false;

  @override
  Rect circleIn(Size size) => _circleIn(size, rtl: rtl);

  @override
  bool get takesFinger => motion.isOpen;

  @override
  void pressDown(double t, double x) {}

  @override
  bool pressMove(double t, double x) => false;

  @override
  void pressUp(double t) {
    if (motion.tabTakesTaps) onClose();
  }

  @override
  void pressCancel(double t) {}

  @override
  void activate() => onClose();
}

class _SearchTabBarState extends State<_SearchTabBar> with SearchLaw {
  late final _motion = _SearchTabMotion(
    open: widget.controller.isOpen,
    onActivate: _activate,
  );
  final _focus = FocusNode(debugLabel: 'GlassTabBar search');
  late final _q = _motion.select((m) => m.morph);
  late final _p = _motion.select((m) => m.focus.progress);
  late final _tabFade = _motion.select(
    (m) => (1 - m.focus.progress).clamp(0.0, 1.0),
  );
  late final _placeholder = _motion.select(
    (m) => ((m.morph - 0.4) / 0.6).clamp(0.0, 1.0),
  );
  late final _closeScale = _motion.select(
    (m) => SearchMotion.appearScaleFor(m.focus.progress),
  );
  late final _resting = _motion.select((m) => m.resting);
  late final _settled = _motion.select((m) => m.settled);
  late final _travelling = _motion.select((m) => !m.settled);
  late final _closeShown = _motion.select((m) => m.closeShown);
  late final _returned = _motion.select((m) => m.focus.progress == 0);
  late final _collapse = _SearchCollapse(_motion, _q, () {
    widget.controller.closeView();
  });

  double get _now => _motion.clock.now;

  @override
  bool get blurEnds => true;

  @override
  ValueListenable<bool> get returned => _returned;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
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
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted && _motion.isOpen && !_focus.hasFocus) _focus.requestFocus();
  }

  void _changed() {
    final open = widget.controller.isOpen;
    if (open == _motion.isOpen) return;
    setState(() => _motion.turn(_now, open: open));
    if (!open) {
      _focus.unfocus();
      // The query clears after the frame that closed the search, as the
      // field turns back.
      _motion.afterFrame(_now, () {
        if (mounted && !_motion.isOpen) widget.controller.clear();
      });
    }
  }

  @override
  void begin(double t, {required double keyboard}) {
    final focus = _motion.focus;
    if (focus.isFocused) return;
    if (keyboard > 0) {
      focus.focus(t, delay: SearchMotion.tabKeyboardLag);
    } else {
      focus.focusAfterKeyboard(t);
    }
  }

  @override
  void end(double t) {
    if (_motion.focus.isFocused) {
      _motion.focus.unfocus(t, delay: SearchMotion.tabUnfocusDelay);
    }
  }

  @override
  void keyboardRose(double t) =>
      _motion.focus.keyboardRose(t, lag: SearchMotion.tabKeyboardLag);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _collapse.rtl = rtl;
    final glyph = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    final open = _motion.isOpen;
    return MotionScope(
      motion: _motion,
      child: SearchHost(
        law: this,
        field: GlassSearchField(
          controller: widget.controller,
          focusNode: _focus,
        ),
        builder: (context, parts) => CustomMultiChildLayout(
          delegate: _SearchTabLayout(
            q: _q,
            p: _p,
            settled: _settled,
            keyboard: parts.keyboard,
            rtl: rtl,
          ),
          children: [
            LayoutId(
              id: _SearchSlot.bar,
              child: MotionTransition(
                opacity: _tabFade,
                child: widget.bar(_collapse, hosted: true),
              ),
            ),
            LayoutId(
              id: _SearchSlot.circle,
              child: MotionVisibility(
                visible: _travelling,
                child: MotionVisibility(
                  visible: _resting,
                  maintainPaint: true,
                  maintainSemantics: true,
                  child: ExcludeFocus(
                    excluding: open,
                    child: _SearchCircle(
                      q: _q,
                      placeholder: _placeholder,
                      glyph: glyph,
                      rtl: rtl,
                      onTap: widget.controller.openView,
                    ),
                  ),
                ),
              ),
            ),
            if (open)
              LayoutId(
                id: _SearchSlot.field,
                child: MotionVisibility(
                  visible: _settled,
                  maintainSemantics: true,
                  child: parts.field,
                ),
              ),
            if (open)
              LayoutId(
                id: _SearchSlot.close,
                child: MotionVisibility(
                  visible: _closeShown,
                  child: MotionTransition(
                    opacity: _p,
                    scale: _closeScale,
                    child: parts.close,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Places a search tab bar's parts from the morph [q], the focus [p] and
/// the keyboard, laid out again on every change of any without a rebuild.
class _SearchTabLayout extends MultiChildLayoutDelegate {
  _SearchTabLayout({
    required this.q,
    required this.p,
    required this.settled,
    required this.keyboard,
    required this.rtl,
  }) : super(relayout: Listenable.merge([q, p, settled, keyboard]));

  final ValueListenable<double> q;
  final ValueListenable<double> p;
  final ValueListenable<bool> settled;
  final ValueListenable<double> keyboard;
  final bool rtl;

  @override
  void performLayout(Size size) {
    final room =
        size.width -
        2 * SearchTabGeometry.barInset -
        SearchTabGeometry.circleSize -
        SearchBarGeometry.gap;
    final bar = layoutChild(
      _SearchSlot.bar,
      BoxConstraints.loose(Size(math.max(0, room), size.height)),
    );
    final g = searchTabLayout(
      size: size,
      barWidth: bar.width,
      keyboard: keyboard.value,
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

    final focus = p.value;
    place(_SearchSlot.circle, Rect.lerp(g.search, g.field, q.value)!);
    place(
      _SearchSlot.field,
      settled.value ? lerpRect(g.field, g.focusedField, focus) : g.field,
    );
    final closeFrom = Rect.fromLTWH(
      rtl ? g.field.left : g.field.right - RawGlassSearchField.height,
      g.field.top,
      RawGlassSearchField.height,
      RawGlassSearchField.height,
    );
    place(_SearchSlot.close, Rect.lerp(closeFrom, g.close, focus)!);
  }

  @override
  bool shouldRelayout(_SearchTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl ||
      !identical(q, oldDelegate.q) ||
      !identical(p, oldDelegate.p) ||
      !identical(settled, oldDelegate.settled) ||
      !identical(keyboard, oldDelegate.keyboard);
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
    child: RawGlassButton(
      onPressed: onTap,
      builder: (context, details) => GlassSurface.live(
        frame: details.body,
        states: details.statesListenable,
        child: details.label,
      ),
      child: CustomMultiChildLayout(
        delegate: _CircleLayout(q: q, rtl: rtl),
        children: [
          LayoutId(
            id: 0,
            child: GlassSearchIcon(color: glyph),
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
  );
}

class _CircleLayout extends MultiChildLayoutDelegate {
  _CircleLayout({required this.q, required this.rtl}) : super(relayout: q);

  final ValueListenable<double> q;
  final bool rtl;

  @override
  void performLayout(Size size) {
    const glyph = GlassSearchIcon.defaultSize;
    final t = q.value.clamp(0.0, 1.0);
    final grown = 1 + 0.15 * (1 - t);
    final box = Size(glyph.width * grown, glyph.height * grown);
    final start = Offset(
      rtl
          ? size.width - GlassSearchField.glyphInset - glyph.width / 2
          : GlassSearchField.glyphInset + glyph.width / 2,
      size.height / 2,
    );
    final center = Offset.lerp(size.center(Offset.zero), start, t)!;
    layoutChild(0, BoxConstraints.tight(box));
    positionChild(0, center - Offset(box.width / 2, box.height / 2));
    final text = Rect.fromLTRB(
      rtl ? 8 : GlassSearchField.textInset,
      0,
      rtl ? size.width - GlassSearchField.textInset : size.width - 8,
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
