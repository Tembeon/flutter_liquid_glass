import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/badge.dart';
import 'package:apple_liquid_glass/src/widgets/controls/button.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/floating_tab_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/page_route.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/sidebar_glyph.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/split_view.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_bar.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/navigation/tab_scaffold_sidebar.dart';
part 'package:apple_liquid_glass/src/widgets/navigation/tab_scaffold_stack.dart';

/// An iOS 27 app of tabs: a tab bar over the selected tab's stack of
/// pages, which lays itself out for the width it is given.
///
/// UIKit: `UITabBarController` whose tabs are navigation controllers, with
/// a split view controller for a tab that is a list and its detail.
/// SwiftUI: `TabView` of `NavigationStack`s and `NavigationSplitView`s.
/// Flutter: `CupertinoTabScaffold` with a `CupertinoTabView` per tab.
///
/// ```dart
/// GlassTabScaffold(
///   tabs: [
///     GlassTab(
///       icon: const Icon(CupertinoIcons.house),
///       label: const Text('Home'),
///       builder: (context) => const HomePage(),
///     ),
///     GlassTab(
///       icon: const Icon(CupertinoIcons.tray),
///       label: const Text('Inbox'),
///       builder: (context) => const InboxList(),
///       detailPlaceholder: (context) => const NoMessageSelected(),
///     ),
///   ],
/// )
/// ```
///
/// Each tab is a stack: [GlassTab.builder] builds its root page, and a page
/// opens the next with `GlassTabStack.of(context).push(page)`. Pages are
/// [GlassPageRoute]s, so they slide in, share their navigation bar and go
/// back with a swipe from the leading edge. The stacks live in a
/// [GlassTabController], above any layout: a page keeps its state when the
/// width changes and the scaffold shows it differently.
///
/// Narrower than [compactBelow] every tab is one stack of pages under a
/// tab bar floating over the bottom, as a [GlassFloatingTabBar] floats it:
/// 21 points from the screen's sides and bottom, with the media query
/// padding of the pages grown to clear it. From [compactBelow] on, a tab
/// with a [GlassTab.detailPlaceholder] shows its root page as a column
/// beside the page pushed on it, as a [GlassSplitView] lays out its
/// columns; a page pushed from the root takes the place of the one beside
/// it, and a page pushed from that page goes on top of it in the detail
/// column. The root's column has a navigator of its own, so a route pushed
/// with `Navigator.of(context)` from it stays in the column, and the split
/// view's sidebar button hides and shows it; a hidden column stays hidden
/// across a change of width and a change of tab.
///
/// [GlassTab.builder] builds a tab the first time it is selected; a tab
/// left keeps its state, offstage, with its tickers muted and its focus
/// kept apart. Selecting the selected tab again takes its pages off, down
/// to the root, as UIKit's tab bar controller does. A scaffold pushed as a
/// page gives the first page of each tab a back button to the page under
/// it. While the search of a
/// [searchController] is open, [searchBuilder]'s page shows instead of the
/// selected tab, kept the same way once built.
///
/// The scaffold draws no glass of its own: it fills the background with
/// [backgroundColor] on every renderer. The bar draws as [GlassTabBar]
/// says, as glass on the liquid and fake renderers and flat on the flat
/// renderer and with no `GlassScope` above.
///
/// From [compactBelow] wide and [compactHeightBelow] tall, as on an iPad,
/// the tabs are a bar at the top or a tab sidebar
/// [sidebarWidth] wide: the bar's button shows the sidebar, the sidebar's
/// hides it. From [sidebarBesideFrom] wide the sidebar shows by itself and
/// stands beside the content, which gets its width as its leading safe
/// area, and a list tab's column runs under it, the sidebar's width wider;
/// narrower it covers the content, dimmed, until a tap on the content or
/// its button hides it. While the bar shows, the content's top safe area
/// grows by the bar's room. [GlassTabController.sidebarShown] keeps what
/// the buttons chose. The search tab is a tab of the bar and a row of the
/// sidebar; the bottom accessory floats in its own glass at the bottom of
/// the content; the action is a circle beside the bar and a row at the end
/// of the sidebar, its [GlassTabBarAction.semanticLabel] for a title.
///
/// Fidelity. The bar's 21 point inset is measured on iOS 27, the bar at the
/// top and the sidebar on the 11 inch iPad Pro (iOS 27.2 simulator,
/// tab sidebar passport); 834 and 1032 point wide portraits put the sidebar
/// over the content and a 1210 wide landscape beside it, and
/// [sidebarBesideFrom] is a width between them. Not measured: the bar's
/// selection lens's motion, its search tab and action, a badge's place in
/// either, the dimming, how the bar's and the sidebar's content fade as
/// the glass morphs, the press of a row, and the bar going away for a
/// page with [GlassPageScaffold.hidesTabBar] (it slides up), and which tabs
/// a bar too narrow for them all keeps (here the leading tabs that fit and
/// the selected one, the sidebar holding them all). The bar at the
/// top does not minimize, and the sidebar has no Edit mode, groups, swipes
/// or menus. The bar's glass morphs into the sidebar's on springs fitted
/// to that passport's frames; the content's safe area takes the sidebar's
/// width at once, where UIKit moves the content beside it with the
/// sidebar. An iPhone Duo keeps the bottom bar here
/// where UIKit stands its bars along the trailing edge (fold passport).
class GlassTabScaffold extends StatefulWidget {
  /// Creates an app of [tabs].
  const GlassTabScaffold({
    required this.tabs,
    this.controller,
    this.searchController,
    this.searchBuilder,
    this.bottomAccessory,
    this.action,
    this.minimizeBehavior = GlassTabBarMinimizeBehavior.automatic,
    this.style,
    this.semanticLabel,
    this.backgroundColor,
    super.key,
  });

  /// The tabs, two to five on a compact width.
  final List<GlassTab> tabs;

  /// The selected tab and the pages on each tab, or null for the
  /// scaffold's own.
  final GlassTabController? controller;

  /// The search of the bar's search tab, or null for a bar without one
  /// ([GlassTabBar.searchController]).
  final GlassSearchController? searchController;

  /// Builds the page of the search tab, shown while the search is open.
  final WidgetBuilder? searchBuilder;

  /// The content of the glass accessory above the bar
  /// ([GlassTabBar.bottomAccessory]), or null.
  final Widget? bottomAccessory;

  /// The action of a glass circle beside the bar ([GlassTabBar.action]),
  /// or null.
  final GlassTabBarAction? action;

  /// When the bar minimizes as the content under it scrolls
  /// ([GlassTabBar.minimizeBehavior]).
  final GlassTabBarMinimizeBehavior minimizeBehavior;

  /// The bar's look, over the theme's and the bar's defaults.
  final GlassTabBarStyle? style;

  /// What accessibility reads for the bar as a whole.
  final String? semanticLabel;

  /// The background behind the tabs; [GlassColors.systemBackground] by
  /// default.
  final Color? backgroundColor;

  /// The space between the screen's sides and bottom and the bar.
  static const double inset = GlassFloatingTabBar.inset;

  /// The width below which every tab is one stack: where UIKit stops using
  /// a phone's metrics ([TabBarLayout.phoneBelow]).
  static const double compactBelow = TabBarLayout.phoneBelow;

  /// The height below which the bar stays at the bottom at any width,
  /// where UIKit's vertical size class is compact: an iPhone in landscape
  /// is 402 points tall, an iPad mini in landscape 744. The iPhone Duo,
  /// 669 tall unfolded, keeps the bottom bar here too.
  static const double compactHeightBelow = 700;

  /// The width of the tab sidebar.
  static const double sidebarWidth = 280;

  /// The width from which the tab sidebar stands beside the content and
  /// shows by itself: UIKit stands it over the content at 834 and 1032
  /// points wide and beside it at 1210.
  static const double sidebarBesideFrom = 1100;

  @override
  State<GlassTabScaffold> createState() => _GlassTabScaffoldState();
}

class _GlassTabScaffoldState extends State<GlassTabScaffold> {
  GlassTabController? _own;
  final _built = <int>{};
  final _focus = <FocusScopeNode>[];
  final _roots = <GlobalKey>[];
  final _stacks = <GlobalKey<NavigatorState>>[];
  final _columns = <GlobalKey<NavigatorState>>[];
  final _details = <GlobalKey<NavigatorState>>[];
  final _splits = <GlassSplitViewController>[];
  final _content = GlobalKey(debugLabel: 'GlassTabScaffold tabs');
  bool? _beside;
  final _searchFocus = FocusScopeNode(debugLabel: 'GlassTabScaffold search');
  bool _searchBuilt = false;
  bool _searching = false;

  GlassTabController get _controller =>
      widget.controller ?? (_own ??= GlassTabController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    widget.searchController?.addListener(_searchChanged);
    _searching = widget.searchController?.isOpen ?? false;
  }

  @override
  void didUpdateWidget(GlassTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.controller ?? _own;
    if (!identical(oldController, _controller)) {
      oldController?.removeListener(_changed);
      _controller.addListener(_changed);
    }
    if (widget.controller != null && _own != null) {
      _own!.dispose();
      _own = null;
    }
    final old = oldWidget.searchController;
    final search = widget.searchController;
    if (!identical(old, search)) {
      old?.removeListener(_searchChanged);
      search?.addListener(_searchChanged);
      _searching = search?.isOpen ?? false;
    }
    final count = widget.tabs.length;
    if (count < oldWidget.tabs.length) {
      _controller._forgetFrom(count);
      if (_splits.length > count) {
        final gone = _splits.sublist(count);
        _splits.removeRange(count, _splits.length);
        // After the frame: the split views of the removed tabs listen to
        // their controllers until they unmount in it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final split in gone) {
            split.dispose();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    widget.searchController?.removeListener(_searchChanged);
    _searchFocus.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    for (final split in _splits) {
      split.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  void _leave() => Navigator.maybeOf(context)?.maybePop();

  void _searchChanged() {
    final open = widget.searchController?.isOpen ?? false;
    if (open != _searching) setState(() => _searching = open);
  }

  void _select(int index) {
    final controller = _controller;
    if (index == controller.index) {
      controller.popToRoot(index);
    } else {
      controller.index = index;
    }
  }

  FocusScopeNode _focusOf(int index) {
    while (_focus.length <= index) {
      _focus.add(FocusScopeNode(debugLabel: 'GlassTabScaffold tab $index'));
    }
    return _focus[index];
  }

  T _keyOf<T extends GlobalKey>(List<T> keys, int index, T Function() make) {
    while (keys.length <= index) {
      keys.add(make());
    }
    return keys[index];
  }

  GlassSplitViewController _splitOf(int index) {
    while (_splits.length <= index) {
      _splits.add(GlassSplitViewController()..addListener(_changed));
    }
    return _splits[index];
  }

  Widget _tab(int index, {required bool regular, required double inset}) {
    final tab = widget.tabs[index];
    final controller = _controller;
    final pages = controller.pagesOf(index);
    final root = KeyedSubtree(
      key: _keyOf(_roots, index, () => GlobalKey(debugLabel: 'tab $index')),
      child: _GlassTabStackScope(
        controller: controller,
        tab: index,
        depth: 0,
        child: Builder(builder: tab.builder),
      ),
    );
    final entries = [
      for (var i = 0; i < pages.length; i++)
        _EntryPage(
          entry: pages[i],
          child: KeyedSubtree(
            key: pages[i]._key,
            child: _GlassTabStackScope(
              controller: controller,
              tab: index,
              depth: i + 1,
              child: pages[i].child,
            ),
          ),
        ),
    ];
    void removed(Page<Object?> page) {
      if (page is _EntryPage) controller._remove(index, page.entry);
    }

    final placeholder = tab.detailPlaceholder;
    if (!regular || placeholder == null) {
      final stack = _keyOf(
        _stacks,
        index,
        () => GlobalKey<NavigatorState>(debugLabel: 'tab $index stack'),
      );
      return _Beside(
        inset: inset,
        child: GlassNestedPop(
          navigator: stack,
          child: Navigator(
            key: stack,
            pages: [
              _RootPage(child: root),
              ...entries,
            ],
            onDidRemovePage: removed,
          ),
        ),
      );
    }
    final column = _keyOf(
      _columns,
      index,
      () => GlobalKey<NavigatorState>(debugLabel: 'tab $index column'),
    );
    final detail = _keyOf(
      _details,
      index,
      () => GlobalKey<NavigatorState>(debugLabel: 'tab $index detail'),
    );
    return GlassSplitView(
      controller: _splitOf(index),
      collapsed: false,
      leadingInset: inset,
      primary: GlassNestedPop(
        navigator: column,
        active: entries.isEmpty,
        child: Navigator(
          key: column,
          pages: [_RootPage(child: root)],
          onDidRemovePage: removed,
        ),
      ),
      secondary: entries.isEmpty
          ? GlassPageScaffold(
              navigationBar: const GlassNavigationBar(),
              child: Builder(builder: placeholder),
            )
          : GlassNestedPop(
              navigator: detail,
              child: Navigator(
                key: detail,
                pages: entries,
                transitionDelegate: const _DetailTransitions(),
                onDidRemovePage: removed,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.tabs.length;
    final selected = count == 0 ? -1 : _controller.index.clamp(0, count - 1);
    final searchBuilder = widget.searchBuilder;
    final searching = _searching && searchBuilder != null;
    if (selected >= 0 && !searching) _built.add(selected);
    _built.removeWhere((index) => index >= count);
    if (searching) _searchBuilt = true;
    final background = GlassDynamicColor.resolve(
      widget.backgroundColor ?? GlassColors.systemBackground,
      context,
    );
    final bar = GlassTabBar(
      destinations: [for (final tab in widget.tabs) tab.destination],
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: _select,
      style: widget.style,
      semanticLabel: widget.semanticLabel,
      minimizeBehavior: widget.minimizeBehavior,
      bottomAccessory: widget.bottomAccessory,
      searchController: widget.searchController,
      action: widget.action,
    );
    final outer = GlassBarSupplement.maybeOf(context);
    final pushed = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    Widget tabs({required bool regular, required double inset}) =>
        GlassBarSupplement(
          leading: outer?.leading,
          trailing: outer?.trailing,
          back: pushed ? _leave : outer?.back,
          child: KeyedSubtree(
            key: _content,
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < count; i++)
                  if (_built.contains(i))
                    Offstage(
                      key: ValueKey(i),
                      offstage: searching || i != selected,
                      child: TickerMode(
                        enabled: !searching && i == selected,
                        child: GlassTabShown(
                          shown: !searching && i == selected,
                          child: FocusScope(
                            node: _focusOf(i),
                            child: _tab(i, regular: regular, inset: inset),
                          ),
                        ),
                      ),
                    ),
                if (_searchBuilt && searchBuilder != null)
                  Offstage(
                    key: const ValueKey('search'),
                    offstage: !searching,
                    child: TickerMode(
                      enabled: searching,
                      child: GlassTabShown(
                        shown: searching,
                        child: FocusScope(
                          node: _searchFocus,
                          child: Builder(builder: searchBuilder),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final regular = constraints.maxWidth >= GlassTabScaffold.compactBelow;
          if (!regular ||
              constraints.maxHeight < GlassTabScaffold.compactHeightBelow) {
            return GlassFloatingTabBar(
              tabBar: bar,
              backgroundColor: background,
              child: tabs(regular: regular, inset: 0),
            );
          }
          return _regular(
            size: constraints.biggest,
            beside: constraints.maxWidth >= GlassTabScaffold.sidebarBesideFrom,
            selected: selected,
            searching: searching,
            background: background,
            tabs: tabs,
          );
        },
      ),
    );
  }

  Widget _regular({
    required Size size,
    required bool beside,
    required int selected,
    required bool searching,
    required Color background,
    required Widget Function({required bool regular, required double inset})
    tabs,
  }) {
    final controller = _controller;
    if (_beside != null && _beside != beside) controller._forgetSidebar();
    _beside = beside;
    final shown = controller.sidebarShown ?? beside;
    final content = tabs(
      regular: true,
      inset: beside && shown ? GlassTabScaffold.sidebarWidth : 0,
    );
    final search = widget.searchController;
    final count = widget.tabs.length;
    final quiet =
        !searching &&
        selected >= 0 &&
        widget.tabs[selected].detailPlaceholder != null &&
        _splitOf(selected).isShowing(GlassSplitViewColumn.primary);
    return _RegularChrome(
      size: size,
      items: [
        for (final tab in widget.tabs) tab.destination,
        if (search != null)
          GlassTabDestination(
            icon: const GlassSearchIcon(),
            label: Text(GlassLocalizations.of(context).searchLabel),
          ),
      ],
      selected: searching ? count : (selected < 0 ? null : selected),
      iconOnly: search == null ? null : count,
      onSelected: (index) {
        if (index == count) {
          search?.openView();
          return;
        }
        if (search?.isOpen ?? false) search!.closeView();
        _select(index);
      },
      beside: beside,
      sidebarShown: shown,
      onSidebar: (value) => controller.sidebarShown = value,
      quiet: quiet,
      look: widget.style,
      semanticLabel: widget.semanticLabel,
      accessory: widget.bottomAccessory,
      action: widget.action,
      background: background,
      child: content,
    );
  }
}

class _RootPage extends Page<void> {
  const _RootPage({required this.child})
    : super(key: const ValueKey(_RootPage));

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => GlassPageRoute<void>(
    settings: this,
    builder: (context) => (ModalRoute.settingsOf(context)! as _RootPage).child,
  );
}

class _EntryPage extends Page<void> {
  _EntryPage({required this.entry, required this.child})
    : super(key: ValueKey(entry));

  final GlassTabPage entry;
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => GlassPageRoute<void>(
    settings: this,
    title: entry.title,
    builder: (context) => (ModalRoute.settingsOf(context)! as _EntryPage).child,
  );
}

// The detail column swaps the page standing first in it in place, as
// UIKit's split view replaces its secondary column; a page pushed on that
// page slides in and goes back as in any stack.
class _DetailTransitions extends TransitionDelegate<void> {
  const _DetailTransitions();

  static const _slides = DefaultTransitionDelegate<void>();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
    pageRouteToPagelessRoutes,
  }) {
    final swaps =
        newPageRouteHistory.isEmpty ||
        newPageRouteHistory.first.isWaitingForEnteringDecision;
    if (!swaps) {
      return _slides.resolve(
        newPageRouteHistory: newPageRouteHistory,
        locationToExitingPageRoute: locationToExitingPageRoute,
        pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
      );
    }
    final results = <RouteTransitionRecord>[];
    void leave(RouteTransitionRecord? location) {
      final exiting = locationToExitingPageRoute[location];
      if (exiting == null) return;
      if (exiting.isWaitingForExitingDecision) {
        exiting.markForComplete(exiting.route.currentResult);
        for (final pageless
            in pageRouteToPagelessRoutes[exiting] ??
                const <RouteTransitionRecord>[]) {
          if (pageless.isWaitingForExitingDecision) {
            pageless.markForComplete(pageless.route.currentResult);
          }
        }
      }
      results.add(exiting);
      leave(exiting);
    }

    leave(null);
    for (final page in newPageRouteHistory) {
      if (page.isWaitingForEnteringDecision) page.markForAdd();
      results.add(page);
      leave(page);
    }
    return results;
  }
}
