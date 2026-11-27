import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_field.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_room.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/search_host.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_anchor.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar_search.dart';

/// The look of a [GlassNavigationBar].
@immutable
class GlassNavigationBarStyle extends GlassStyle<GlassNavigationBarStyle> {
  /// Creates a style.
  const GlassNavigationBarStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.titleTextStyle,
    this.largeTitleTextStyle,
    this.itemStyle,
  });

  /// The theme's [GlassNavigationBarStyle] at [context], or null without
  /// one: the look between a widget's own style and its defaults.
  static GlassNavigationBarStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassNavigationBarStyle>(context);

  /// A fill behind the bar (UIKit `backgroundColor` of the bar's
  /// appearance); none by default, as iOS 27's bar shows the content under
  /// it through its edge effect.
  final Color? backgroundColor;

  /// The color of the titles; [GlassColors.label] by default.
  final Color? foregroundColor;

  /// The inline title's style: 17 points semibold by default.
  final TextStyle? titleTextStyle;

  /// The large title's style: 34 points bold by default.
  final TextStyle? largeTitleTextStyle;

  /// The look of the bar's items; read from the theme's style only (see
  /// [GlassBarItemStyle]).
  final GlassBarItemStyle? itemStyle;

  /// This style over [other]: a null field takes [other]'s.
  @override
  GlassNavigationBarStyle merge(GlassNavigationBarStyle? other) {
    if (other == null) return this;
    return GlassNavigationBarStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      foregroundColor: foregroundColor ?? other.foregroundColor,
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      largeTitleTextStyle:
          other.largeTitleTextStyle?.merge(largeTitleTextStyle) ??
          largeTitleTextStyle,
      itemStyle: itemStyle?.merge(other.itemStyle) ?? other.itemStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassNavigationBarStyle lerp(GlassNavigationBarStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassNavigationBarStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor, t),
      foregroundColor: color(foregroundColor, other.foregroundColor, t),
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      largeTitleTextStyle: text(
        largeTitleTextStyle,
        other.largeTitleTextStyle,
        t,
      ),
      itemStyle: GlassBarItemStyle.lerp(itemStyle, other.itemStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassNavigationBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.titleTextStyle == titleTextStyle &&
      other.largeTitleTextStyle == largeTitleTextStyle &&
      other.itemStyle == itemStyle;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    titleTextStyle,
    largeTitleTextStyle,
    itemStyle,
  );
}

/// An iOS 27 navigation bar: a title and glass capsules of buttons at the
/// top of a page, with an optional large title.
///
/// UIKit: `UINavigationBar` with a `UINavigationItem`. SwiftUI: the bar of
/// a `NavigationStack`. Flutter: `CupertinoNavigationBar`,
/// `CupertinoSliverNavigationBar`.
///
/// Pass a [title] or a [largeTitle], and bar items such as `GlassBarButton`
/// in [leading] and [trailing]; items side by side share a capsule. A page
/// pushed as a `GlassPageRoute` gets a back button by itself. Put the bar
/// in a [GlassPageScaffold] as its `navigationBar`, and wrap the page's
/// scroll view in a [GlassContentScroll] so the large title and the scroll
/// edge effect follow it. [searchField] stacks a [GlassSearchField] under
/// the titles.
///
/// ```dart
/// GlassPageScaffold(
///   navigationBar: GlassNavigationBar(
///     largeTitle: const Text('Inbox'),
///     trailing: [
///       GlassBarButton(
///         icon: const Icon(CupertinoIcons.square_pencil),
///         onPressed: () => debugPrint('compose'),
///       ),
///     ],
///   ),
///   child: GlassContentScroll(
///     child: ListView(children: const [Text('No mail')]),
///   ),
/// )
/// ```
///
/// The capsules are `GlassSurface`s in one `GlassGroup`. The liquid
/// renderer draws them as liquid glass in one shared layer, so capsules
/// that come close flow together; the fake renderer does the same with
/// blurred and lit glass; the flat renderer, which also draws when no
/// `GlassScope` is above, draws each as a translucent fill with a hairline
/// rim and a soft shadow. The bar puts no glass behind its titles: the
/// page's scroll edge effect separates the content there.
///
/// The bar is a row 54 points tall under the status bar: [leading] and
/// [trailing] capsules 16 points in from the sides, centered 22 points
/// below the status bar, and [title] centered on the bar when it fits
/// between them, else from the leading side, truncated. With a
/// [largeTitle] the bar is 52 points taller: the large title sits under
/// the row and scrolls away with the content of the page's
/// [GlassContentScroll], after which the inline title rises in, 0.45 s in
/// and 0.7 s out, from 15 points below and blurred; a jump of the content
/// switches it at once. A finger's release that leaves the large title
/// partly away springs to the nearer end.
///
/// The pages of one navigator pushed as `GlassPageRoute`s share one bar,
/// as UIKit's navigation controller does: on a push, a pop and an edge
/// swipe its glass stays in place and the capsules change into the next
/// page's, each side into itself, groups growing out of a capsule of
/// their side or appearing in place with a swell, items travelling,
/// timed from the push or pop call; during a swipe the capsules the page
/// below also has lean halfway toward their places there at most. The
/// titles belong to the page and move with it. A page with a glass page
/// below gets a back button, named after that page's title, as the first
/// leading capsule; [leading] replaces it, or follows it with
/// [leadingSupplementsBackButton], and [automaticallyImplyLeading] false
/// removes it. Elsewhere, the bar draws its capsules for its page
/// alone.
///
/// Fidelity. The row's layout is measured on iOS 27: 46 bars match within
/// 1 point. The inline title's timing is fitted on the device and read
/// from UIKit. The capsules' change on a push and a pop is checked against
/// device recordings.
class GlassNavigationBar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates a navigation bar.
  const GlassNavigationBar({
    this.leading = const [],
    this.title,
    this.subtitle,
    this.titleMenu,
    this.largeTitle,
    this.largeTitleInBar = false,
    this.largeSubtitle,
    this.trailing = const [],
    this.automaticallyImplyLeading = true,
    this.leadingSupplementsBackButton = false,
    this.previousPageTitle,
    this.backButtonDisplayMode = GlassBackButtonDisplayMode.title,
    this.searchField,
    this.style,
    super.key,
  });

  /// The capsules at the leading edge; when not empty they replace the
  /// back button (UIKit `leftBarButtonItems`).
  final List<GlassBarEntry> leading;

  /// The inline title; [largeTitle] when null.
  final Widget? title;

  /// The line under the inline title, or null for none (UIKit
  /// `UINavigationItem.subtitle`): the title turns 15 points semibold over
  /// the subtitle in 12 points regular secondary label, the two lines
  /// touching and centered as one block where the title alone stands
  /// (bars passport, 27.2). It goes with the inline title, so under a
  /// [largeTitle] it shows once the large title has scrolled away; UIKit's
  /// `largeSubtitle` under the large title is not built. Where the block
  /// does not fit centered it stands at the leading side with its lines
  /// centered on each other, where UIKit aligns them leading (not
  /// reproduced).
  final Widget? subtitle;

  /// The menu the inline title opens, or null for none (UIKit
  /// `titleMenuProvider`, SwiftUI `toolbarTitleMenu`): a 20 point circle
  /// of secondarySystemFill with a chevron down in the secondary label
  /// color stands 6 points after the title, the two centered as one block,
  /// and a tap on either opens a [GlassMenuAnchor] menu of these entries
  /// (bars passport and a tree dump and screenshot of the iOS 27.2
  /// simulator: the chevron 8.67 by 5 in a 17.67 point circle). Under a
  /// [largeTitle] it opens from the inline title once the large title has
  /// scrolled away; a menu from the large title at rest is not built.
  final List<GlassMenuEntry>? titleMenu;

  /// The large title under the row, or null for an inline title only.
  final Widget? largeTitle;

  /// Whether the [largeTitle] stands in the row itself, as UIKit's
  /// `largeTitleDisplayMode = .inline` draws it: 34 points bold from the
  /// leading side, past the leading items, its top 11.67 below the row's,
  /// with no large title area under the row and nothing that scrolls away;
  /// at the accessibility text sizes it grows to 38 points at most (bars
  /// passport, iOS 27.2 simulator). [largeSubtitle] and [titleMenu] do not
  /// show with it.
  final bool largeTitleInBar;

  /// The line under the [largeTitle], or null for none (UIKit
  /// `UINavigationItem.largeSubtitle`): 11 points medium in the secondary
  /// label color, its top 38.33 below the large title's, which keeps its 34
  /// points; the bar grows by [largeSubtitleHeight] more (bars passport,
  /// iOS 27.2 simulator, a bar of 125.33).
  final Widget? largeSubtitle;

  /// The capsules at the trailing edge (UIKit `rightBarButtonItems`).
  final List<GlassBarEntry> trailing;

  /// Whether the page gets a back button when [leading] is empty and a
  /// glass page lies below (UIKit `hidesBackButton` false).
  final bool automaticallyImplyLeading;

  /// Whether [leading] stands after the back button, in capsules of its
  /// own, rather than in its place (UIKit
  /// `leftItemsSupplementBackButton`, false by default).
  final bool leadingSupplementsBackButton;

  /// The back button's name for the page below, shown beside its chevron
  /// in the [GlassBackButtonDisplayMode.title] mode; without it the chevron
  /// shows alone and assistive technology reads the page below's title.
  final String? previousPageTitle;

  /// How the back button names the page below.
  final GlassBackButtonDisplayMode backButtonDisplayMode;

  /// A [GlassSearchField] stacked under the titles, or null for none.
  ///
  /// UIKit: `UINavigationItem.searchController` with the stacked placement.
  /// SwiftUI: `searchable` in a `NavigationStack`. Flutter:
  /// `CupertinoSliverNavigationBar.search`.
  ///
  /// At rest the field is 44 points tall on a plain fill, 16 points from
  /// the sides and 10 above the content. Scrolling the content first folds
  /// the field away, its height shrinking with the scroll, its text gone
  /// by a fifth of the way and its fill fading out between 80 and 95
  /// percent of it, then the large title goes (read from UIKit, notes
  /// private). Focusing the field presents the search on one spring
  /// (damping 0.8, response 0.34, read from UIKit): the page, the large
  /// title and the field rise until the field sits under the status bar,
  /// the field narrows for a close button that slides in 40 points from the
  /// side, and its plain fill turns to glass on a critically damped spring
  /// of response 0.32 (read from UIKit). The large title, the inline title
  /// and the bar's capsules fade in time while this happens, the capsules
  /// and the inline title where they stand; nothing is cut (an iPhone 16
  /// Pro's layers). The close button clears the field and ends the search;
  /// the page comes back down. A field folded away by a scroll
  /// presents from where it rests: the rise is not shortened (an
  /// approximation).
  final Widget? searchField;

  /// The look, over the theme's.
  final GlassNavigationBarStyle? style;

  /// The height of the row under the status bar (navigation bar passport).
  static const double height = 54;

  /// The space between a bar's box and its outer items: 16 on a 402 point
  /// screen (bars passport).
  static const double sideInset = navigationSideInset;

  /// How far in from the sides of the box of [context] a navigation bar's
  /// outer items stand on its row: [sideInset] from the box's sides, past
  /// a side's safe area but 24 points of it, past a tab sidebar over the
  /// box, past the window buttons whose line runs through the row, and
  /// clear of what the hardware covers beside it. An app's own control on
  /// the row stands inside it to line up with the bar's items, after the
  /// window buttons on the same gap.
  static EdgeInsets itemPaddingOf(BuildContext context) {
    final sides = BarRoom.sidesOf(
      context,
      inset: sideInset,
      top: BarRoom.rowTopOf(context),
      height: height,
    );
    return EdgeInsets.only(left: sides.left, right: sides.right);
  }

  /// The height a large title adds under the row (navigation bar
  /// passport).
  static const double largeTitleHeight = 52;

  /// The height a [largeSubtitle] adds under a large title.
  static const double largeSubtitleHeight = 71.33 - largeTitleHeight;

  double get _large => largeTitle == null || largeTitleInBar
      ? 0
      : largeTitleHeight + (largeSubtitle == null ? 0 : largeSubtitleHeight);

  /// The height a stacked search field adds under the titles: the field
  /// and the space below it.
  static const double searchFieldHeight =
      _StackedMetrics.fieldHeight + _StackedMetrics.bottomGap;

  double get _search => searchField == null ? 0 : searchFieldHeight;

  @override
  Size get preferredSize => Size.fromHeight(height + scrolledUnderAfter);

  /// This bar with [field] stacked under its titles.
  @internal
  GlassNavigationBar withSearchField(Widget field) => GlassNavigationBar(
    leading: leading,
    title: title,
    subtitle: subtitle,
    titleMenu: titleMenu,
    largeTitle: largeTitle,
    largeTitleInBar: largeTitleInBar,
    largeSubtitle: largeSubtitle,
    trailing: trailing,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leadingSupplementsBackButton: leadingSupplementsBackButton,
    previousPageTitle: previousPageTitle,
    backButtonDisplayMode: backButtonDisplayMode,
    searchField: field,
    style: style,
    key: key,
  );

  /// How far the content scrolls before it passes under the bar: the
  /// large title and the search field it scrolls away first.
  @internal
  double get scrolledUnderAfter => _large + _search;

  @override
  State<GlassNavigationBar> createState() => _GlassNavigationBarState();
}

/// An item a container adds at an end of the navigation bar of the first
/// page of its content, the page with no glass page below it, such as a
/// split view's sidebar button in its primary column; it stands in a
/// capsule of its own, at the end, beside the page's own items. An item
/// [beforeBack] stands on every page's bar.
@internal
class GlassBarSupplement extends InheritedWidget {
  /// Adds [leading] and [trailing] to the bar of the first page of [child],
  /// and [beforeBack] to the bar of every page of it.
  const GlassBarSupplement({
    required super.child,
    this.leading,
    this.trailing,
    this.back,
    this.beforeBack,
    super.key,
  });

  /// The item at the leading end, or null for none.
  final GlassBarItem? leading;

  /// The item at the trailing end, or null for none.
  final GlassBarItem? trailing;

  /// Goes back from the first page of [child], which gets a back button
  /// for it, such as a tab scaffold pushed as a page gives the first pages
  /// of its tabs; null for none.
  final VoidCallback? back;

  /// The item at the leading end of every page's bar, before its back
  /// button or its own leading items, as UIKit's split view keeps its
  /// sidebar button there at every depth of the secondary column while the
  /// primary column is hidden (split view passport); null for none.
  final GlassBarItem? beforeBack;

  /// The supplement around [context], or null for none.
  static GlassBarSupplement? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassBarSupplement>();

  @override
  bool updateShouldNotify(GlassBarSupplement oldWidget) =>
      leading != oldWidget.leading ||
      trailing != oldWidget.trailing ||
      back != oldWidget.back ||
      beforeBack != oldWidget.beforeBack;
}

/// A search field a container gives the pages of [child]: a tab scaffold's
/// search page beside its tab sidebar, where UIKit's search tab leaves the
/// field to the page's navigation bar (search tab bar passport, iPad).
/// A page's [GlassNavigationBar] with no field of its own stacks it. The
/// container keeps the supplement in place with a null [field] where its
/// own bar holds the field, so its pages keep their state.
@internal
class GlassSearchSupplement extends InheritedWidget {
  /// Gives [field] to the pages of [child].
  const GlassSearchSupplement({
    required this.field,
    required super.child,
    super.key,
  });

  /// The field, usually a [GlassSearchField], or null for none.
  final Widget? field;

  /// The field around [context], or null for none.
  static Widget? fieldOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassSearchSupplement>()
      ?.field;

  @override
  bool updateShouldNotify(GlassSearchSupplement oldWidget) =>
      field != oldWidget.field;
}

class _GlassNavigationBarState extends State<GlassNavigationBar> {
  late final MotionClock _clock;
  late final _title = PartPresence.inlineTitle(
    shown: widget.largeTitle == null,
    clock: _clock,
  );
  late final _titleLook = MotionSelection(() {
    final opacity = _title.progressListenable.value.clamp(0.0, 1.0);
    return MotionPose(
      offset: Offset(0, _Metrics.hiddenOffset * (1 - opacity)),
      opacity: opacity,
      blur: _Metrics.hiddenBlur * (1 - opacity),
    ).wornUnder(_title.traits);
  }, clock: _clock);
  ValueNotifier<MotionScroll?>? _active;
  MotionScroll? _scroll;
  MotionSelection<ScrollMetrics?>? _metrics;
  MotionSelection<double>? _scrolledBy;
  late final _offset = MotionSignal<double>(0, clock: _clock);
  MotionSelection<double>? _away;
  double? _awayDelay;
  bool _laidOut = false;
  late final _bar = GlassBarClient(this);
  late final _fade = MotionValue<double>(
    1,
    restDistance: () => MotionRest.opacity,
    clock: _clock,
  );

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bar.resolve(context);
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(GlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.largeTitle == null) != (widget.largeTitle == null)) {
      _laidOut = false;
      _scrolled();
    }
  }

  @override
  void dispose() {
    if (_bar.link case final link?) link.host.dropFade(link, _fade);
    _bar.dispose(fade: _fade);
    _active?.removeListener(_follow);
    _metrics?.removeRenderListener(_scrolled);
    _scrolledBy?.removeRenderListener(_moved);
    super.dispose();
  }

  static double _offsetIn(ScrollMetrics? metrics) {
    if (metrics == null || !metrics.hasContentDimensions) return 0;
    return metrics.pixels - metrics.minScrollExtent;
  }

  // The scroll view the bar follows changes during a build, so the bar
  // follows it without building: its offset feeds the bar's own.
  void _follow() {
    final next = _active?.value;
    if (identical(next, _scroll)) return;
    _metrics?.removeRenderListener(_scrolled);
    _scrolledBy?.removeRenderListener(_moved);
    _scroll = next;
    final metrics = _metrics = next?.select((s) => s.metrics);
    metrics?.addRenderListener(_scrolled);
    final scrolledBy = _scrolledBy = next?.select((s) => _offsetIn(s.metrics));
    scrolledBy?.addRenderListener(_moved);
    _moved();
    _laidOut = false;
    _scrolled();
  }

  void _moved() => _offset.write(_clock.now, _scrolledBy?.value ?? 0);

  // The large title moves with the content once a stacked search field
  // has folded away.
  MotionSelection<double> _awayAfter(double delay) {
    final away = _away;
    if (away != null && delay == _awayDelay) return away;
    _awayDelay = delay;
    return _away = MotionSelection(() {
      final o = _offset.value;
      return o < 0 ? -o : -math.max<double>(0, o - delay);
    }, clock: _clock);
  }

  void _scrolled() {
    final metrics = _scroll?.metrics;
    final laidOut = metrics != null && metrics.hasContentDimensions;
    final shown =
        widget.largeTitle == null ||
        (laidOut &&
            metrics.pixels - metrics.minScrollExtent >=
                widget.scrolledUnderAfter - 0.5);
    final appears = !_laidOut;
    _laidOut = laidOut;
    // A jump of the content switches the title at once, as UIKit does.
    final moving = _scroll?.position?.isScrollingNotifier.value ?? false;
    _title.turn(
      _clock.now,
      shown: shown,
      animated: !appears && moving,
    );
  }

  Widget _inBarTitle(
    Widget title,
    GlassNavigationBarStyle look,
    Color color,
    BuildContext context,
  ) {
    final scale = GlassTextScale.of(
      context,
      max: _Metrics.inBarTitleMax / _Metrics.largeTitle.fontSize!,
    );
    return scale.apply(
      DefaultTextStyle(
        style: scale.resolve(
          _Metrics.largeTitle
              .merge(look.largeTitleTextStyle)
              .copyWith(color: color),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: Semantics(header: true, child: title),
      ),
    );
  }

  Widget _titleBlock(
    Widget title,
    GlassTextScale scale,
    GlassNavigationBarStyle look,
    Color color,
    BuildContext context,
  ) {
    final subtitle = widget.subtitle;
    Widget line(Widget child, TextStyle style) => DefaultTextStyle(
      style: scale.resolve(style),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: child,
    );
    final menu = widget.titleMenu;
    if (menu != null) {
      final block = subtitle == null
          ? line(
              title,
              _Metrics.title.merge(look.titleTextStyle).copyWith(color: color),
            )
          : _subtitled(title, subtitle, line, look, color, context);
      return GlassMenuAnchor(
        menuChildren: menu,
        builder: (context, controller, _) => RawGlassButton(
          onPressed: controller.open,
          builder: (context, details) => details.label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: block),
              const SizedBox(width: _TitleMenuGlyph.gap),
              const _TitleMenuGlyph(),
            ],
          ),
        ),
      );
    }
    if (subtitle == null) {
      return line(
        title,
        _Metrics.title.merge(look.titleTextStyle).copyWith(color: color),
      );
    }
    return _subtitled(title, subtitle, line, look, color, context);
  }

  Widget _subtitled(
    Widget title,
    Widget subtitle,
    Widget Function(Widget, TextStyle) line,
    GlassNavigationBarStyle look,
    Color color,
    BuildContext context,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line(
          title,
          _Metrics.subtitledTitle
              .merge(look.titleTextStyle)
              .copyWith(color: color),
        ),
        line(
          subtitle,
          _Metrics.subtitle.copyWith(
            color: GlassDynamicColor.resolve(
              GlassColors.secondaryLabel,
              context,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = (widget.style ?? const GlassNavigationBarStyle()).merge(
      GlassNavigationBarStyle.maybeOf(context),
    );
    final color = GlassDynamicColor.resolve(
      look.foregroundColor ?? GlassTheme.labelColorOf(context),
      context,
    );
    final inBar = widget.largeTitleInBar ? widget.largeTitle : null;
    final title = widget.title ?? widget.largeTitle;
    final largeTitle = inBar == null ? widget.largeTitle : null;
    final titleScale = GlassTextScale.of(context, max: _Metrics.maxTextScale);
    final largeScale = GlassTextScale.of(context, max: 1);
    final background = look.backgroundColor;
    final link = _bar.target;
    final around = GlassBarSupplement.maybeOf(context);
    final supplement = (_bar.link?.hasPageBelow ?? false) ? null : around;
    if (GlassTabShown.of(context)) {
      link.host.declare(
        link,
        GlassBarDeclaration(
          beforeBack: around?.beforeBack,
          leading: [
            if (supplement?.leading case final item?) ...[
              item,
              if (widget.leading.isNotEmpty) const GlassBarSpacer(),
            ],
            ...widget.leading,
          ],
          trailing: [
            ...widget.trailing,
            if (supplement?.trailing case final item?) ...[
              if (widget.trailing.isNotEmpty) const GlassBarSpacer(),
              item,
            ],
          ],
          automaticallyImplyLeading: widget.automaticallyImplyLeading,
          leadingSupplementsBack: widget.leadingSupplementsBackButton,
          previousPageTitle: widget.previousPageTitle,
          backButtonDisplayMode: widget.backButtonDisplayMode,
          back: supplement?.back,
          title: switch (title) {
            Text(:final data?) => data,
            _ => null,
          },
        ),
        by: this,
      );
      link.host.fadedBy(link, _fade);
    } else {
      _bar.withdraw(fade: _fade);
    }
    final standalone = _bar.standalone;
    final rowTop = BarRoom.rowTopOf(context);
    final sides = BarRoom.sidesOf(
      context,
      inset: navigationSideInset,
      top: rowTop,
      height: GlassNavigationBar.height,
    );
    final below = BarRoom.sidesOf(context, inset: navigationSideInset);
    final row = SizedBox(
      height: GlassNavigationBar.height,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          if (standalone != null)
            MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: GlassBarView(
                host: standalone,
                only: GlassBarKind.navigation,
                sides: sides,
              ),
            ),
          if (inBar != null)
            MotionTransition(
              opacity: _fade,
              child: CustomSingleChildLayout(
                delegate: _TitleLayout(
                  link.titleRoom,
                  Directionality.of(context),
                  sides: sides,
                  covered: GlassBarInset.of(context),
                  leading: true,
                ),
                child: _inBarTitle(inBar, look, color, context),
              ),
            )
          else if (title != null)
            MotionScope(
              motion: _title,
              child: MotionTransition(
                opacity: _fade,
                child: CustomSingleChildLayout(
                  delegate: _TitleLayout(
                    link.titleRoom,
                    Directionality.of(context),
                    sides: sides,
                    covered: GlassBarInset.of(context),
                  ),
                  child: _CrampedTitleDrops(
                    opensMenu: widget.titleMenu != null,
                    shown: _title.progressListenable,
                    child: MotionTransition(
                      pose: _titleLook,
                      child: titleScale.apply(
                        _titleBlock(
                          title,
                          titleScale,
                          look,
                          color,
                          context,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final lift = PageLift.maybeOf(context);
    final filled = background == null
        ? null
        : GlassDynamicColor.resolve(background, context);
    Widget fill(Widget child) =>
        filled == null ? child : ColoredBox(color: filled, child: child);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fill(row),
        if (largeTitle != null || widget.searchField != null)
          MotionTransition(
            translateY: lift,
            child: fill(
              Padding(
                padding: EdgeInsets.only(
                  left: below.left - navigationSideInset,
                  right: below.right - navigationSideInset,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (largeTitle != null)
                      SizedBox(
                        height: widget._large,
                        child: _ScrollAway(
                          shift: _awayAfter(widget._search),
                          opacity: _fade,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: _Metrics.largeTitleInset,
                              end: _Metrics.largeTitleInset,
                              top: _Metrics.largeTitleTop,
                            ),
                            child: Stack(
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.topStart,
                                  child: largeScale.apply(
                                    DefaultTextStyle(
                                      style: largeScale.resolve(
                                        _Metrics.largeTitle
                                            .merge(look.largeTitleTextStyle)
                                            .copyWith(color: color),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      child: Semantics(
                                        header: true,
                                        child: largeTitle,
                                      ),
                                    ),
                                  ),
                                ),
                                if (widget.largeSubtitle case final line?)
                                  PositionedDirectional(
                                    top: _Metrics.largeSubtitleTop,
                                    start: 0,
                                    end: 0,
                                    child: DefaultTextStyle(
                                      style: largeScale.resolve(
                                        _Metrics.largeSubtitle.copyWith(
                                          color: GlassDynamicColor.resolve(
                                            GlassColors.secondaryLabel,
                                            context,
                                          ),
                                        ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      child: line,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (widget.searchField case final field?)
                      _StackedSearch(
                        field: field,
                        offset: _offset,
                        travel: GlassNavigationBar.height + widget._large,
                        lift: lift,
                        fade: _fade,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

abstract final class _Metrics {
  /// How far below the status bar the capsules and the inline title are
  /// centered: the capsules sit at the row's top (device recordings).
  static const double capsuleCenter = 22;

  /// The inset of the large title from the bar's sides.
  static const double largeTitleInset = navigationSideInset;

  /// The space between the top of the large title area and its text.
  static const double largeTitleTop = 3.67;

  // A large title in the bar (UIKit `.inline`, bars passport recheck): its
  // top below the row's top, and its size at the accessibility sizes.
  static const double inBarTitleTop = 11.67;
  static const double inBarTitleMax = 38;

  /// The largest text scale the inline title follows.
  static const double maxTextScale = 1.25;

  /// The room at or under which an inline title that would truncate is
  /// dropped: about 57 points (bars passport, iOS 27.2 simulator: five
  /// icons at AX3 drop it, 86.67 points keep it truncated). A title that
  /// fits stays, as a short one did in 49.33 points on an iOS 27.0
  /// device.
  static const double titleDropRoom = 57;

  /// How far below its place the hidden inline title sits.
  static const double hiddenOffset = 15;

  /// The blur of the hidden inline title.
  static const double hiddenBlur = 4;

  /// The inline title: UIKit's title role, 17 points semibold, in the
  /// line box UIKit's bar labels lay out in.
  static const title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// The inline title over a subtitle: 15 points semibold, and the
  /// subtitle 12 points regular (bars passport, 27.2).
  static const subtitledTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 18.33 / 15,
  );
  static const subtitle = TextStyle(
    fontSize: 12,
    height: 14.67 / 12,
  );

  /// The large subtitle: 11 points medium, 13.33 tall, its top 38.33 below
  /// the large title's (bars passport, iOS 27.2 simulator).
  static const largeSubtitle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 13.33 / 11,
  );
  static const double largeSubtitleTop = 38.33;

  /// The large title: 34 points bold.
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// Lays the inline title out as UIKit does: on the bar's center, 22
/// points below the status bar like the capsules, when it fits in the
/// [room] between the page's capsules; else from the room's leading end,
/// truncated at the other.
class _TitleLayout extends SingleChildLayoutDelegate {
  _TitleLayout(
    this.room,
    this.direction, {
    required this.sides,
    required this.covered,
    this.leading = false,
  }) : super(relayout: room);

  /// Whether the title stands at the leading side, its top
  /// [_Metrics.inBarTitleTop] below the row's, as a large title in the bar
  /// does, rather than centered.
  final bool leading;

  final ValueListenable<GlassTitleRoom?> room;
  final TextDirection direction;

  /// Where the bar's items stand in the row.
  final BarSides sides;

  /// How much of the row's sides a sidebar or a hinge's band covers: the
  /// title centers on the rest, where the window buttons and the safe area
  /// leave it on the window's center.
  final BarSides covered;

  ({double left, double right}) _boxIn(Size size) =>
      (left: covered.left, right: size.width - covered.right);

  GlassTitleRoom _roomIn(Size size) {
    final bandLeft = sides.left - navigationSideInset;
    final room = this.room.value;
    if (room == null) {
      return (start: sides.left, end: size.width - sides.right);
    }
    return (start: bandLeft + room.start, end: bandLeft + room.end);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = _roomIn(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.max(0, room.end - room.start),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = _roomIn(size);
    if (leading) {
      return Offset(
        direction == TextDirection.rtl
            ? room.end - childSize.width
            : room.start,
        _Metrics.inBarTitleTop,
      );
    }
    final box = _boxIn(size);
    final center = (box.left + box.right) / 2;
    final half = childSize.width / 2;
    final fits =
        center - half >= room.start - 0.01 && center + half <= room.end + 0.01;
    final left = fits
        ? center - half
        : direction == TextDirection.rtl
        ? room.end - childSize.width
        : room.start;
    return Offset(left, _Metrics.capsuleCenter - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_TitleLayout oldDelegate) =>
      leading != oldDelegate.leading ||
      !identical(room, oldDelegate.room) ||
      direction != oldDelegate.direction ||
      sides != oldDelegate.sides ||
      covered != oldDelegate.covered;
}

/// An inline title in the room the bar gives it, drawn, hit and read
/// only while it fits, or while the room is wider than
/// [_Metrics.titleDropRoom] to truncate it in. It is read as a heading of
/// its own, so a screen reader reads the bar's buttons before the page.
/// Like a label in UIKit, a title takes a hit only where something in it
/// takes input (a listener, a mouse region, an editable), so a window is
/// dragged by a title of text as by the rest of the bar.
class _CrampedTitleDrops extends SingleChildRenderObjectWidget {
  const _CrampedTitleDrops({
    required this.opensMenu,
    required this.shown,
    required super.child,
  });

  // Whether the title opens a menu, and so takes every hit on it while it
  // shows more than half: not under a large title at rest.
  final bool opensMenu;
  final ValueListenable<double> shown;

  @override
  _RenderCrampedTitleDrops createRenderObject(BuildContext context) =>
      _RenderCrampedTitleDrops()
        ..opensMenu = opensMenu
        ..shown = shown;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCrampedTitleDrops renderObject,
  ) {
    renderObject
      ..opensMenu = opensMenu
      ..shown = shown;
  }
}

class _RenderCrampedTitleDrops extends RenderProxyBox {
  bool _dropped = false;
  bool opensMenu = false;
  ValueListenable<double>? shown;

  @override
  void performLayout() {
    super.performLayout();
    final child = this.child;
    final room = constraints.maxWidth;
    final dropped =
        child != null &&
        room <= _Metrics.titleDropRoom &&
        child.getMaxIntrinsicWidth(constraints.maxHeight) > room + 0.01;
    if (dropped == _dropped) return;
    _dropped = dropped;
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_dropped) super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_dropped) return false;
    if (opensMenu) {
      if ((shown?.value ?? 1) <= 0.5) return false;
      return super.hitTestChildren(result, position: position);
    }
    final probe = BoxHitTestResult();
    if (!super.hitTestChildren(probe, position: position)) return false;
    if (!probe.path.any((entry) => _takesInput(entry.target))) return false;
    return super.hitTestChildren(result, position: position);
  }

  static bool _takesInput(Object target) => switch (target) {
    TextSpan(:final recognizer, :final onEnter, :final onExit) =>
      recognizer != null || onEnter != null || onExit != null,
    RenderPointerListener() ||
    MouseTrackerAnnotation() ||
    RenderEditable() => true,
    _ => false,
  };

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_dropped) return;
    config
      ..isSemanticBoundary = true
      ..isHeader = true;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_dropped) super.visitChildrenForSemantics(visitor);
  }
}

/// A large title that scrolls away with the content: it paints its child
/// moved by the content's offset and cut off at its own top, following the
/// scroll view without building or laying out.
class _ScrollAway extends StatelessWidget {
  const _ScrollAway({
    required this.shift,
    required this.opacity,
    required this.child,
  });

  final ValueListenable<double> shift;
  final ValueListenable<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      clipper: const BelowTop(),
      child: MotionTransition(
        translateY: shift,
        opacity: opacity,
        child: child,
      ),
    ),
  );
}

/// The circle a title menu shows after the title: 20 points, a 17.67 point
/// disc of secondarySystemFill with a chevron down 8.67 by 5 in the
/// secondary label color, its middle half a point below the disc's
/// (screenshot of the iOS 27.2 simulator at 3x).
class _TitleMenuGlyph extends StatelessWidget {
  const _TitleMenuGlyph();

  static const double gap = 6;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(20),
      painter: _TitleMenuPainter(
        disc: GlassDynamicColor.resolve(
          GlassColors.secondarySystemFill,
          context,
        ),
        chevron: GlassDynamicColor.resolve(GlassColors.secondaryLabel, context),
      ),
    ),
  );
}

class _TitleMenuPainter extends CustomPainter {
  _TitleMenuPainter({required this.disc, required this.chevron});

  final Color disc;
  final Color chevron;

  static const double _stroke = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    const half = _stroke / 2;
    canvas
      ..drawCircle(const Offset(10, 10), 17.67 / 2, Paint()..color = disc)
      ..drawPath(
        Path()
          ..moveTo(5.67 + half, 8 + half)
          ..lineTo(10, 13 - half)
          ..lineTo(5.67 + 8.67 - half, 8 + half),
        Paint()
          ..color = chevron
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_TitleMenuPainter oldDelegate) =>
      oldDelegate.disc != disc || oldDelegate.chevron != chevron;
}
