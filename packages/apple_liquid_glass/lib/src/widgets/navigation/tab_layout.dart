import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/split_view.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_scaffold.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A width a hand drags between [minimum] and [maximum], [preferred] until
/// it does.
@immutable
final class GlassWidthRange {
  /// Creates a range from [minimum] to [maximum] that starts at
  /// [preferred].
  const GlassWidthRange({
    required this.minimum,
    required this.preferred,
    required this.maximum,
  }) : assert(
         minimum <= preferred && preferred <= maximum,
         'a preferred width within the range',
       );

  /// The narrowest a hand makes it.
  final double minimum;

  /// The width until a hand gives it another.
  final double preferred;

  /// The widest a hand makes it.
  final double maximum;

  @override
  bool operator ==(Object other) =>
      other is GlassWidthRange &&
      other.minimum == minimum &&
      other.preferred == preferred &&
      other.maximum == maximum;

  @override
  int get hashCode => Object.hash(minimum, preferred, maximum);

  @override
  String toString() => 'GlassWidthRange($minimum, $preferred, $maximum)';
}

/// Where a [GlassTabScaffold] puts its tabs.
enum GlassTabPlacement {
  /// A tab bar floating over the bottom of the content, each tab one stack
  /// or a list beside its pages, as on an iPhone.
  bottom,

  /// A tab sidebar, which folds into a rail of icons and hides into a bar
  /// at the top as its [GlassTabLayout] allows, as on an iPad.
  sidebar,
}

/// What a [GlassTabScaffold]'s tab sidebar stands on.
///
/// UIKit: none; its tab sidebar is glass to the window's edges. SwiftUI:
/// none. Flutter: none.
///
/// A sidebar over the content, dimmed until its button hides it, floats
/// on every panel but [glass].
enum GlassTabSidebarPanel {
  /// Glass to the window's edges, one with the bar at the top it morphs
  /// from, as UIKit draws it.
  glass,

  /// Part of the window: an opaque fill
  /// ([GlassTabSidebarStyle.backgroundColor]) and a hairline on the
  /// content's side, no glass. The bar's glass morphs into it and fades as
  /// it grows.
  flush,

  /// Glass [GlassTabLayout.sidebarMargin] from the window's edges, its
  /// corners concentric with the display's where the platform reports
  /// them and the bar's elsewhere; the content stands beside it, the
  /// margin past it.
  floating,
}

/// How a tab with a [GlassTab.detailPlaceholder] shows its root page, the
/// list, beside the pages it opens.
enum GlassTabListMode {
  /// One stack: the pages cover the list.
  stacked,

  /// Side by side, the list hidden until its button shows it.
  hidden,

  /// Side by side, the list showing.
  beside,
}

/// How a [GlassTabScaffold] lays its tabs out at one size, as a
/// [GlassTabLayoutPolicy] resolves it.
///
/// The user's choices stay in the [GlassTabController]: the sidebar's
/// width, whether it shows and whether it is a rail, each list's width and
/// whether it shows. A layout says what the hand can reach and where it
/// starts; what it does not offer is drawn as the nearest form it does,
/// and the controller keeps the choice for a layout that offers it.
@immutable
final class GlassTabLayout {
  /// A tab bar over the bottom; a list tab shows its list as [list] says,
  /// [listWidth] wide while it stands beside its pages.
  const GlassTabLayout.bottom({
    this.list = GlassTabListMode.stacked,
    this.listWidth = defaultListWidth,
  }) : placement = GlassTabPlacement.bottom,
       sidebarBeside = false,
       sidebarHides = true,
       sidebarFolds = true,
       sidebarWidth = defaultSidebarWidth,
       railWidth = defaultRailWidth,
       minimumContentWidth = defaultMinimumContentWidth,
       sidebarPanel = GlassTabSidebarPanel.glass,
       sidebarMargin = defaultSidebarMargin;

  /// A tab sidebar [sidebarWidth] wide, standing [beside] the content and
  /// showing by itself, or else over it, dimmed, while a button shows it.
  ///
  /// With [folds], a drag of its edge past its minimum folds it into a
  /// rail of icons [railWidth] wide; with [hides], the rail or the sidebar
  /// hides into a bar at the top. A sidebar that cannot hide stands beside
  /// the content. It leaves the content [minimumContentWidth] beside it.
  /// It stands on [sidebarPanel], a floating one [sidebarMargin] from the
  /// window's edges.
  const GlassTabLayout.sidebar({
    bool beside = false,
    bool hides = true,
    bool folds = true,
    this.sidebarWidth = defaultSidebarWidth,
    this.railWidth = defaultRailWidth,
    this.minimumContentWidth = defaultMinimumContentWidth,
    this.sidebarPanel = GlassTabSidebarPanel.glass,
    this.sidebarMargin = defaultSidebarMargin,
    this.list = GlassTabListMode.beside,
    this.listWidth = defaultListWidth,
  }) : assert(beside || hides, 'a sidebar over the content hides'),
       placement = GlassTabPlacement.sidebar,
       sidebarBeside = beside,
       sidebarHides = hides,
       sidebarFolds = folds;

  /// The tab sidebar's widths until a layout gives others: 280 points as
  /// UIKit's (tab sidebar passport), a hand dragging it between the
  /// package's own 200 and 400.
  static const defaultSidebarWidth = GlassWidthRange(
    minimum: 200,
    preferred: 280,
    maximum: 400,
  );

  /// The width of the sidebar folded into a rail: Flutter's
  /// `NavigationRail`'s.
  static const double defaultRailWidth = 72;

  /// The width the sidebar leaves the content beside it at the least: the
  /// package's own.
  static const double defaultMinimumContentWidth = 320;

  /// The room between a floating sidebar and the window's edges: the
  /// package's own.
  static const double defaultSidebarMargin = 8;

  /// A list's widths beside its pages: 320 points as UIKit's split view
  /// (split view passport), a hand dragging it between the package's own
  /// 240 and 400.
  static const defaultListWidth = GlassWidthRange(
    minimum: 240,
    preferred: GlassSplitView.defaultPrimaryWidth,
    maximum: 400,
  );

  /// Where the tabs go.
  final GlassTabPlacement placement;

  /// Whether the sidebar stands beside the content and shows by itself,
  /// where [placement] is [GlassTabPlacement.sidebar].
  final bool sidebarBeside;

  /// Whether the sidebar hides into a bar at the top.
  final bool sidebarHides;

  /// Whether the sidebar folds into a rail of icons.
  final bool sidebarFolds;

  /// The sidebar's widths.
  final GlassWidthRange sidebarWidth;

  /// The width of the sidebar folded into a rail.
  final double railWidth;

  /// The width the sidebar leaves the content beside it at the least.
  final double minimumContentWidth;

  /// What the sidebar stands on.
  final GlassTabSidebarPanel sidebarPanel;

  /// The room between a floating sidebar and the window's edges, and
  /// between it and the content beside it.
  final double sidebarMargin;

  /// How a list tab shows its list beside its pages.
  final GlassTabListMode list;

  /// A list's widths beside its pages.
  final GlassWidthRange listWidth;

  @override
  bool operator ==(Object other) =>
      other is GlassTabLayout &&
      other.placement == placement &&
      other.sidebarBeside == sidebarBeside &&
      other.sidebarHides == sidebarHides &&
      other.sidebarFolds == sidebarFolds &&
      other.sidebarWidth == sidebarWidth &&
      other.railWidth == railWidth &&
      other.minimumContentWidth == minimumContentWidth &&
      other.sidebarPanel == sidebarPanel &&
      other.sidebarMargin == sidebarMargin &&
      other.list == list &&
      other.listWidth == listWidth;

  @override
  int get hashCode => Object.hash(
    placement,
    sidebarBeside,
    sidebarHides,
    sidebarFolds,
    sidebarWidth,
    railWidth,
    minimumContentWidth,
    sidebarPanel,
    sidebarMargin,
    list,
    listWidth,
  );

  @override
  String toString() => switch (placement) {
    GlassTabPlacement.bottom => 'GlassTabLayout.bottom(list: ${list.name})',
    GlassTabPlacement.sidebar =>
      'GlassTabLayout.sidebar(beside: $sidebarBeside, hides: $sidebarHides, '
          'folds: $sidebarFolds, panel: ${sidebarPanel.name}, '
          'list: ${list.name})',
  };
}

/// Decides how a [GlassTabScaffold] lays its tabs out for the environment
/// and the size it is given.
///
/// [GlassTabLayoutPolicy.automatic] follows UIKit on every device;
/// [GlassTabLayoutPolicy.desktop] keeps a sidebar beside the content of any
/// window wide enough for it; [GlassTabLayoutPolicy.custom] takes a
/// function. A subclass overrides [resolve].
///
/// The policy reads the [GlassEnvironment], never the platform, so a window
/// of one size lays out alike on every desktop and in a browser.
abstract class GlassTabLayoutPolicy {
  /// Lets a subclass be constant.
  const GlassTabLayoutPolicy();

  /// UIKit's layout on Apple devices, and an iPad window's rules elsewhere.
  ///
  /// A phone keeps the tab bar at the bottom, and a list tab stands its
  /// list beside its pages where the phone is regular across, as the Pro
  /// Max and the iPhone Duo's inner display are. A tablet or a desktop
  /// window keeps the bar at the bottom while it is compact across, under
  /// 668 points; wider, the tabs are a sidebar, standing beside the content
  /// from `sidebarBesideFrom` points wide in landscape and over it,
  /// hidden into a bar at the top, otherwise. Its list stands beside its
  /// pages from `listBesideFrom` points wide and hides narrower, where its
  /// button shows it.
  ///
  /// A sidebar the buttons showed or hid follows the width again on a change
  /// between over and beside, as UIKit's does on a rotation.
  ///
  /// `sidebarWidth`, `railWidth`, `minimumContentWidth`, `sidebarPanel`,
  /// `sidebarMargin` and `listWidth` are [GlassTabLayout]'s defaults unless
  /// given.
  const factory GlassTabLayoutPolicy.automatic({
    double sidebarBesideFrom,
    double listBesideFrom,
    GlassWidthRange sidebarWidth,
    double railWidth,
    double minimumContentWidth,
    GlassTabSidebarPanel sidebarPanel,
    double sidebarMargin,
    GlassWidthRange listWidth,
  }) = _AutomaticTabLayoutPolicy;

  /// A sidebar beside the content from `sidebarFrom` points wide, 668 by
  /// default, folding into a rail, and the tab bar at the bottom narrower.
  /// With `hides` the sidebar also hides into a bar at the top. A list
  /// stands beside its pages from `listBesideFrom` points wide, by default
  /// where the sidebar at its preferred width, the list at its minimum and
  /// the 448 points a split view's detail keeps fit, and is one stack with
  /// its pages narrower.
  ///
  /// The sidebar keeps what the user chose across every change of layout.
  /// It stands on `sidebarPanel`, [GlassTabSidebarPanel.glass] by default.
  const factory GlassTabLayoutPolicy.desktop({
    double sidebarFrom,
    bool hides,
    double? listBesideFrom,
    GlassWidthRange sidebarWidth,
    double railWidth,
    double minimumContentWidth,
    GlassTabSidebarPanel sidebarPanel,
    double sidebarMargin,
    GlassWidthRange listWidth,
  }) = _DesktopTabLayoutPolicy;

  /// The layout [resolve] gives; with [remembersSidebar] the sidebar keeps
  /// what the user chose across a change of layout.
  const factory GlassTabLayoutPolicy.custom(
    GlassTabLayout Function(GlassEnvironment environment, Size size) resolve, {
    bool remembersSidebar,
  }) = _CustomTabLayoutPolicy;

  /// The layout of a scaffold [size] big in [environment].
  GlassTabLayout resolve(GlassEnvironment environment, Size size);

  /// Whether a sidebar the user showed or hid stays so across a change of
  /// layout, such as from over the content to beside it.
  ///
  /// Where it does not, the change gives the sidebar back to the layout
  /// and [GlassTabController.layoutState] leaves it out, so a launch starts
  /// from what the layout shows.
  bool get remembersSidebar => false;
}

final class _AutomaticTabLayoutPolicy extends GlassTabLayoutPolicy {
  const _AutomaticTabLayoutPolicy({
    this.sidebarBesideFrom = 1024,
    this.listBesideFrom = 728,
    this.sidebarWidth = GlassTabLayout.defaultSidebarWidth,
    this.railWidth = GlassTabLayout.defaultRailWidth,
    this.minimumContentWidth = GlassTabLayout.defaultMinimumContentWidth,
    this.sidebarPanel = GlassTabSidebarPanel.glass,
    this.sidebarMargin = GlassTabLayout.defaultSidebarMargin,
    this.listWidth = GlassTabLayout.defaultListWidth,
  });

  final double sidebarBesideFrom;
  final double listBesideFrom;
  final GlassWidthRange sidebarWidth;
  final double railWidth;
  final double minimumContentWidth;
  final GlassTabSidebarPanel sidebarPanel;
  final double sidebarMargin;
  final GlassWidthRange listWidth;

  @override
  GlassTabLayout resolve(GlassEnvironment environment, Size size) {
    final regular = environment.isRegularWidth;
    if (environment.formFactor == GlassFormFactor.phone || !regular) {
      return GlassTabLayout.bottom(
        list: regular ? GlassTabListMode.beside : GlassTabListMode.stacked,
        listWidth: listWidth,
      );
    }
    return GlassTabLayout.sidebar(
      beside: size.width >= sidebarBesideFrom && size.width >= size.height,
      sidebarWidth: sidebarWidth,
      railWidth: railWidth,
      minimumContentWidth: minimumContentWidth,
      sidebarPanel: sidebarPanel,
      sidebarMargin: sidebarMargin,
      list: size.width >= listBesideFrom
          ? GlassTabListMode.beside
          : GlassTabListMode.hidden,
      listWidth: listWidth,
    );
  }
}

final class _DesktopTabLayoutPolicy extends GlassTabLayoutPolicy {
  const _DesktopTabLayoutPolicy({
    this.sidebarFrom = GlassEnvironment.regularWidthFrom,
    this.hides = false,
    this.listBesideFrom,
    this.sidebarWidth = GlassTabLayout.defaultSidebarWidth,
    this.railWidth = GlassTabLayout.defaultRailWidth,
    this.minimumContentWidth = GlassTabLayout.defaultMinimumContentWidth,
    this.sidebarPanel = GlassTabSidebarPanel.glass,
    this.sidebarMargin = GlassTabLayout.defaultSidebarMargin,
    this.listWidth = GlassTabLayout.defaultListWidth,
  });

  final double sidebarFrom;
  final bool hides;
  final double? listBesideFrom;
  final GlassWidthRange sidebarWidth;
  final double railWidth;
  final double minimumContentWidth;
  final GlassTabSidebarPanel sidebarPanel;
  final double sidebarMargin;
  final GlassWidthRange listWidth;

  @override
  bool get remembersSidebar => true;

  @override
  GlassTabLayout resolve(GlassEnvironment environment, Size size) {
    if (size.width < sidebarFrom) {
      return GlassTabLayout.bottom(listWidth: listWidth);
    }
    final listFrom =
        listBesideFrom ??
        sidebarWidth.preferred +
            listWidth.minimum +
            GlassSplitView.defaultMinimumSecondaryWidth;
    return GlassTabLayout.sidebar(
      beside: true,
      hides: hides,
      sidebarWidth: sidebarWidth,
      railWidth: railWidth,
      minimumContentWidth: minimumContentWidth,
      sidebarPanel: sidebarPanel,
      sidebarMargin: sidebarMargin,
      list: size.width >= listFrom
          ? GlassTabListMode.beside
          : GlassTabListMode.stacked,
      listWidth: listWidth,
    );
  }
}

final class _CustomTabLayoutPolicy extends GlassTabLayoutPolicy {
  const _CustomTabLayoutPolicy(this._resolve, {this.remembersSidebar = false});

  final GlassTabLayout Function(GlassEnvironment environment, Size size)
  _resolve;

  @override
  final bool remembersSidebar;

  @override
  GlassTabLayout resolve(GlassEnvironment environment, Size size) =>
      _resolve(environment, size);
}

/// What the user chose of a [GlassTabScaffold]'s layout, as
/// [GlassTabController.layoutState] keeps it across launches.
@immutable
final class GlassTabLayoutState {
  /// Creates a state of the given choices; null leaves a choice to the
  /// layout.
  const GlassTabLayoutState({
    this.sidebarShown,
    this.sidebarWidth,
    this.sidebarRail = false,
    this.lists = const {},
  });

  /// Reads a state [toJson] wrote, leaving out what it does not recognize.
  factory GlassTabLayoutState.fromJson(Map<String, Object?> json) {
    final lists = json['lists'];
    return GlassTabLayoutState(
      sidebarShown: _bool(json['sidebarShown']),
      sidebarWidth: _width(json['sidebarWidth']),
      sidebarRail: _bool(json['sidebarRail']) ?? false,
      lists: {
        if (lists is Map<String, Object?>)
          for (final MapEntry(:key, :value) in lists.entries)
            if ((int.tryParse(key), value)
                case (
                  final int tab,
                  final Map<String, Object?> list,
                )
                when tab >= 0)
              tab: GlassTabListState(
                width: _width(list['width']),
                shown: _bool(list['shown']),
              ),
      },
    );
  }

  static bool? _bool(Object? value) => value is bool ? value : null;

  static double? _width(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

  /// See [GlassTabController.sidebarShown].
  final bool? sidebarShown;

  /// See [GlassTabController.sidebarWidth].
  final double? sidebarWidth;

  /// See [GlassTabController.sidebarRail].
  final bool sidebarRail;

  /// The list of each tab that has one, by the tab's index
  /// ([GlassTabController.splitOf]).
  final Map<int, GlassTabListState> lists;

  /// The state as JSON values.
  Map<String, Object?> toJson() => {
    if (sidebarShown case final shown?) 'sidebarShown': shown,
    if (sidebarWidth case final width?) 'sidebarWidth': width,
    if (sidebarRail) 'sidebarRail': true,
    if (lists.isNotEmpty)
      'lists': {
        for (final MapEntry(:key, :value) in lists.entries)
          '$key': value.toJson(),
      },
  };

  @override
  bool operator ==(Object other) =>
      other is GlassTabLayoutState &&
      other.sidebarShown == sidebarShown &&
      other.sidebarWidth == sidebarWidth &&
      other.sidebarRail == sidebarRail &&
      mapEquals(other.lists, lists);

  @override
  int get hashCode => Object.hash(
    sidebarShown,
    sidebarWidth,
    sidebarRail,
    Object.hashAllUnordered(
      lists.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'GlassTabLayoutState(sidebarShown: $sidebarShown, '
      'sidebarWidth: $sidebarWidth, sidebarRail: $sidebarRail, '
      'lists: $lists)';
}

/// What the user chose of a list tab's list beside its pages.
@immutable
final class GlassTabListState {
  /// Creates a state of the given choices; null leaves a choice to the
  /// layout.
  const GlassTabListState({this.width, this.shown});

  /// See [GlassSplitViewController.primaryWidth].
  final double? width;

  /// See [GlassSplitViewController.showsPrimary].
  final bool? shown;

  /// The state as JSON values.
  Map<String, Object?> toJson() => {
    if (width case final width?) 'width': width,
    if (shown case final shown?) 'shown': shown,
  };

  @override
  bool operator ==(Object other) =>
      other is GlassTabListState &&
      other.width == width &&
      other.shown == shown;

  @override
  int get hashCode => Object.hash(width, shown);

  @override
  String toString() => 'GlassTabListState(width: $width, shown: $shown)';
}
