import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/badge.dart';
import 'package:apple_liquid_glass/src/widgets/controls/button.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_field.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_room.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/column_divider.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/floating_tab_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/page_route.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/sidebar_glyph.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/split_view.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_layout.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
/// The [layout] policy decides how the tabs stand for the environment and
/// the size ([GlassTabLayoutPolicy.automatic], UIKit's, by default). With
/// the tabs at the bottom ([GlassTabPlacement.bottom]), as on a phone and
/// in a window compact across, they are a tab bar floating over the bottom,
/// as a [GlassFloatingTabBar] floats it: 21 points from the screen's sides
/// and bottom, or the wide bar 20 above the bottom where the window is
/// regular across or short ([GlassTabBar.metricsOf]), with the media query
/// padding of the pages grown to clear it.
/// Where the layout stands a list beside its pages ([GlassTabLayout.list]),
/// a tab with a [GlassTab.detailPlaceholder] shows its root page as a
/// column beside the page pushed on it, as a [GlassSplitView] lays out its
/// columns; a page pushed from the root takes the place of the one beside
/// it, and a page pushed from that page goes on top of it in the detail
/// column. Elsewhere every tab is one stack of pages. The root's column has
/// a navigator of its own, so a route pushed with `Navigator.of(context)`
/// from it stays in the column, and the split view's sidebar button hides
/// and shows it ([GlassTab.showsListButton]). With [resizable] a hand drags
/// the column's edge within the layout's [GlassTabLayout.listWidth], and
/// past its minimum hides it where the button shows. The column's width
/// and whether it shows stay across a change of layout and a change of tab
/// ([GlassTabController.splitOf]).
///
/// [GlassTab.builder] builds a tab the first time it is selected; a tab
/// left keeps its state, offstage, with its tickers muted and its focus
/// kept apart, the focus going to the tab shown as `CupertinoTabScaffold`
/// moves it. Selecting the selected tab again calls its
/// [GlassTab.onReselect], or without one takes its pages off, down to the
/// root, as UIKit's tab bar controller does. A scaffold pushed as a
/// page gives the first page of each tab a back button to the page under
/// it. While the search of a
/// [searchController] is open, [searchBuilder]'s page shows instead of the
/// selected tab, kept the same way once built. Every page below reads the
/// search with [GlassSearchController.of], as SwiftUI's `isSearching` and
/// `dismissSearch`.
///
/// The scaffold draws no glass of its own: it fills the background with
/// [backgroundColor] on every renderer. The bar draws as [GlassTabBar]
/// says, as glass on the liquid and fake renderers and flat on the flat
/// renderer and with no `GlassScope` above.
///
/// With the tabs in a sidebar ([GlassTabPlacement.sidebar]), as on an iPad,
/// they are a tab sidebar, 280 points wide by default
/// ([GlassTabLayout.sidebarWidth]), or its button alone where the sidebar
/// hides: the button shows the sidebar, the sidebar's hides it. Where the
/// layout stands the sidebar beside the content
/// ([GlassTabLayout.sidebarBeside]) it shows by itself, and the content
/// gets its width as its leading safe area, a list tab's column running
/// under it, the sidebar's width wider; elsewhere it covers the content,
/// dimmed, until a tap on the content or its button hides it. The button
/// alone stands where the first item of the content's navigation bar would
/// stand, the content's bars starting past it as they start past the window
/// buttons, and keeps the content's safe area; a page that hides the tab
/// bar leaves the button in place. [GlassTabController.sidebarShown] keeps
/// what the buttons chose.
///
/// The sidebar stands on the layout's [GlassTabLayout.sidebarPanel]:
/// UIKit's glass to the window's edges by default; part of the window, an
/// opaque fill with a hairline on the content's side that the button's
/// glass fades into as it grows ([GlassTabSidebarPanel.flush]); or glass
/// [GlassTabLayout.sidebarMargin] from the window's edges, the content
/// beside it past the margin ([GlassTabSidebarPanel.floating]). A sidebar
/// over the content floats on every panel but UIKit's.
/// [GlassTabSidebarStyle.backgroundColor] fills a flush panel and tints a
/// glass one apart from the button.
///
/// With [resizable], a hand drags the sidebar's edge within the layout's
/// [GlassTabLayout.sidebarWidth], the content keeping its
/// [GlassTabLayout.minimumContentWidth] beside it and following the edge.
/// 50 points past the minimum the sidebar folds into a rail of its tabs'
/// icons [GlassTabLayout.railWidth] wide, which stands beside the content
/// in either layout, and 50 points past the rail the rail hides, the bar at
/// the top, or the button alone, coming back; the same drag brings them
/// back, the sidebar at the
/// width it had. A layout that does not fold the sidebar or hide it
/// ([GlassTabLayout.sidebarFolds], [GlassTabLayout.sidebarHides]) leaves
/// that form out, and the sidebar's button then folds it into the rail and
/// back. The arrow keys on the edge step it the same way, and a double tap
/// on it brings back the sidebar at its preferred width.
/// [GlassTabController.sidebarWidth] and [GlassTabController.sidebarRail]
/// keep what the hand chose; the bar's button shows the form chosen last,
/// and [GlassTabController.layoutState] keeps it all across launches. The
/// sidebar stops short of a hinge, or a fold half open, that splits the
/// window from top to bottom.
///
/// The search tab is a tab of the bar and a row of the
/// sidebar, and its page's navigation bar holds the field; the bottom
/// accessory floats in its own glass at the bottom of
/// the content; the action is a circle beside the bar and a row of the
/// sidebar after the tabs, or before them with
/// [GlassTabBarAction.atSidebarStart], its [GlassTabBarAction.semanticLabel]
/// for a title; beside the sidebar's button alone the bar and the action's
/// circle are gone, the search tab and the action reached through the
/// sidebar. [sidebarHeader] stands above the sidebar's rows and
/// [sidebarFooter] at its bottom, under the tabs with
/// [GlassTab.atSidebarEnd], [sidebarTopBackground] fills the band above
/// them, [sidebarStyle] sets the rows' look and [sidebarRowBuilder] draws
/// them an app's own way. The sidebar is a [GlassTabSidebar] and its edge
/// a [GlassColumnDivider], which a shell of an app's own can use.
///
/// While the focus is in the scaffold, [GlassToggleSidebarIntent],
/// control-command-S by default ([shortcuts]), shows and hides the list
/// column of the selected tab where its button shows, else the tab sidebar
/// where the layout lets it hide or fold, as its buttons do; a
/// [GlassSelectTabIntent] selects a tab.
///
/// Fidelity. The bar's 21 point inset is measured on iOS 27, the sidebar on
/// the 11 inch iPad Pro (iOS 27.2 simulator, tab sidebar passport); a 1210
/// wide landscape puts it beside the content, and the automatic policy
/// stands it beside from 1024 points wide in landscape. Where UIKit puts a
/// bar of the tabs at the top (834 and 1032 point wide portraits), this
/// scaffold keeps the bottom bar, laid out wide; the bar at the top is left
/// out on purpose, as it takes the content's first row. Not measured: the
/// dimming, how the button's and the sidebar's content fade as the glass
/// morphs, the press of a row, and whether UIKit's tab sidebar resizes: its
/// edge, its rail and their numbers are this package's own, as are the
/// flush and floating panels, their margin and the sidebar's button alone;
/// what UIKit draws where its sidebar's glass meets the window's edges is
/// not measured. The sidebar has no Edit mode, groups, swipes or menus.
/// The glass morphs between the button and the sidebar on the springs
/// UIKit's bar at the top morphs on, fitted to that passport's frames; the
/// content's safe area takes the sidebar's
/// width at once, where UIKit moves the content beside it with the
/// sidebar. The search page's bar stacks its field under the titles where
/// UIKit puts a search button at the bar's end. An iPhone Duo keeps the
/// bottom bar here
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
    this.sidebarHeader,
    this.sidebarTopBackground,
    this.sidebarFooter,
    this.sidebarRowBuilder,
    this.sidebarStyle,
    this.minimizeBehavior = GlassTabBarMinimizeBehavior.automatic,
    this.style,
    this.semanticLabel,
    this.backgroundColor,
    this.resizable = true,
    this.layout = const GlassTabLayoutPolicy.automatic(),
    this.shortcuts = GlassToggleSidebarIntent.defaultShortcuts,
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
  /// The bar at the bottom holds the search field; under the bar at the
  /// top the page's [GlassNavigationBar] stacks one on [searchController]
  /// when it has none of its own.
  final WidgetBuilder? searchBuilder;

  /// The content of the glass accessory above the bar
  /// ([GlassTabBar.bottomAccessory]), or null.
  final Widget? bottomAccessory;

  /// The action of a glass circle beside the bar ([GlassTabBar.action]),
  /// or null.
  final GlassTabBarAction? action;

  /// What stands above the rows of the tab sidebar, such as the app's
  /// name ([GlassTabSidebar.header]), or null.
  final Widget? sidebarHeader;

  /// What stands at the bottom of the tab sidebar, such as the account
  /// ([GlassTabSidebar.footer]), or null.
  final Widget? sidebarFooter;

  /// What fills the band at the top of the tab sidebar, under its button,
  /// such as an app's area that drags its window
  /// ([GlassTabSidebar.topBackground]), or null.
  final Widget? sidebarTopBackground;

  /// Draws the rows of the tab sidebar an app's own way
  /// ([GlassTabSidebar.rowBuilder]), or null for [GlassTabSidebarRow]s.
  final GlassTabSidebarRowBuilder? sidebarRowBuilder;

  /// The look of the tab sidebar's rows ([GlassTabSidebar.style]), over the
  /// theme's [GlassTabSidebarStyle].
  final GlassTabSidebarStyle? sidebarStyle;

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

  /// Whether a hand resizes the tab sidebar and a list tab's column by
  /// their edges: the sidebar folds into a rail of icons past its minimum
  /// and hides past the rail as the layout allows
  /// ([GlassTabController.sidebarWidth], [GlassTabController.sidebarRail]),
  /// the column hides past its minimum where its button shows
  /// ([GlassTabController.splitOf]).
  final bool resizable;

  /// Decides where the tabs stand and how a list tab shows its list for
  /// the environment and the scaffold's size.
  final GlassTabLayoutPolicy layout;

  /// The keys the scaffold binds while the focus is in it: by default
  /// control-command-S to [GlassToggleSidebarIntent]. A desktop app adds
  /// [GlassSelectTabIntent.numberShortcuts]; an empty map binds none.
  final Map<ShortcutActivator, Intent> shortcuts;

  @override
  State<GlassTabScaffold> createState() => _GlassTabScaffoldState();
}

class _GlassTabScaffoldState extends State<GlassTabScaffold> {
  GlassTabController? _own;
  final _built = <int>{};
  final _focus = <_TabFocus>[];
  final _roots = <GlobalKey>[];
  final _stacks = <GlobalKey<NavigatorState>>[];
  final _columns = <GlobalKey<NavigatorState>>[];
  final _details = <GlobalKey<NavigatorState>>[];
  final _content = GlobalKey(debugLabel: 'GlassTabScaffold tabs');
  bool? _beside;
  final _searchFocus = _TabFocus('GlassTabScaffold search');
  bool _searchBuilt = false;
  bool _searching = false;
  (int, bool)? _shown;
  VoidCallback? _toggle;
  late final _toggleAction = CallbackAction<GlassToggleSidebarIntent>(
    onInvoke: (_) {
      _toggle?.call();
      return null;
    },
  );
  late final _selectAction = _SelectTab(this);

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
    if (count < oldWidget.tabs.length) _controller._forgetFrom(count);
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
    if (index != controller.index) {
      controller.index = index;
    } else if (widget.tabs[index].onReselect case final reselect?) {
      reselect();
    } else {
      controller.popToRoot(index);
    }
  }

  // Shows the tab at [index], closing the search over it, without the
  // reselect of a tap on the tab selected.
  void _show(int index) {
    final search = widget.searchController;
    if (search?.isOpen ?? false) search!.closeView();
    _controller.index = index;
  }

  // Moves the focus left in a tab or the search no longer shown to the tab
  // shown, as CupertinoTabScaffold does, so the keys reach the tab on
  // screen. The search keeps the focus its field takes.
  void _focusShown() {
    final shown = _shown;
    final focus = FocusManager.instance.primaryFocus;
    if (!mounted || shown == null || shown.$2 || focus == null) return;
    final tab = _focusOf(shown.$1);
    for (final node in [..._focus, _searchFocus]) {
      if (identical(node, tab)) continue;
      if (identical(focus, node) || focus.ancestors.contains(node)) {
        tab.take();
        return;
      }
    }
  }

  _TabFocus _focusOf(int index) {
    while (_focus.length <= index) {
      _focus.add(_TabFocus('GlassTabScaffold tab ${_focus.length}'));
    }
    return _focus[index];
  }

  T _keyOf<T extends GlobalKey>(List<T> keys, int index, T Function() make) {
    while (keys.length <= index) {
      keys.add(make());
    }
    return keys[index];
  }

  // Whether the list of the tab at [index] shows beside its pages in
  // [layout] until a hand or code shows or hides it: always without its
  // button.
  bool _listByDefault(int index, GlassTabLayout layout) =>
      layout.list == GlassTabListMode.beside ||
      !widget.tabs[index].showsListButton;

  // Whether the tab at [index] stands its list beside its pages in
  // [layout], as a split view, rather than as one stack.
  bool _split(int index, GlassTabLayout layout) =>
      layout.list != GlassTabListMode.stacked &&
      widget.tabs[index].detailPlaceholder != null;

  // What the sidebar button of the list column of the tab at [index] does
  // in [layout], or null where the tab shows no column with a button.
  VoidCallback? _listToggle(int index, GlassTabLayout layout) {
    if (!_split(index, layout) || !widget.tabs[index].showsListButton) {
      return null;
    }
    final split = _controller.splitOf(index);
    return () => split.isShowing(GlassSplitViewColumn.primary)
        ? split.hide(GlassSplitViewColumn.primary)
        : split.show(GlassSplitViewColumn.primary);
  }

  // [child] with the intents the scaffold handles: [toggle] for
  // [GlassToggleSidebarIntent] where something can toggle, and the tabs.
  Widget _keys({required VoidCallback? toggle, required Widget child}) {
    _toggle = toggle;
    return InputCommands(
      shortcuts: widget.shortcuts,
      actions: {
        if (toggle != null) GlassToggleSidebarIntent: _toggleAction,
        GlassSelectTabIntent: _selectAction,
      },
      child: child,
    );
  }

  Widget _tab(
    int index, {
    required GlassTabLayout layout,
    required double inset,
    required bool live,
  }) {
    final tab = widget.tabs[index];
    final controller = _controller;
    final pages = controller.pagesOf(index);
    final root = GlassMovableSubtree(
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
    if (placeholder == null || !_split(index, layout)) {
      final stack = _keyOf(
        _stacks,
        index,
        () => GlobalKey<NavigatorState>(debugLabel: 'tab $index stack'),
      );
      final child = GlassNestedPop(
        navigator: stack,
        child: Navigator(
          key: stack,
          pages: [
            _RootPage(child: root),
            ...entries,
          ],
          onDidRemovePage: removed,
        ),
      );
      return _TabInset(
        settled: inset,
        live: live,
        child: _Beside(inset: inset, child: child),
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
    final primary = GlassNestedPop(
      navigator: column,
      active: entries.isEmpty,
      child: Navigator(
        key: column,
        pages: [_RootPage(child: root)],
        onDidRemovePage: removed,
      ),
    );
    final secondary = entries.isEmpty
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
          );
    return _TabInset(
      settled: inset,
      live: live,
      child: GlassSplitView(
        controller: controller.splitOf(index),
        collapsed: false,
        leadingInset: inset,
        resizable: widget.resizable,
        shortcuts: const {},
        showsSidebarButton: tab.showsListButton,
        showsPrimaryByDefault: _listByDefault(index, layout),
        preferredPrimaryWidth: layout.listWidth.preferred,
        minimumPrimaryWidth: layout.listWidth.minimum,
        maximumPrimaryWidth: layout.listWidth.maximum,
        primary: primary,
        secondary: secondary,
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
    final shown = (selected, searching);
    if (shown != _shown) {
      final first = _shown == null;
      _shown = shown;
      if (!first) {
        // After the frame: a tab built in this frame attaches its focus
        // scope in it, and where the focus lies draws nothing.
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusShown());
      }
    }
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
    _controller._remembersSidebar = widget.layout.remembersSidebar;
    Widget tabs({
      required GlassTabLayout layout,
      required double inset,
      required bool pageSearch,
    }) => GlassBarSupplement(
      leading: outer?.leading,
      trailing: outer?.trailing,
      beforeBack: outer?.beforeBack,
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
                        child: _tab(
                          i,
                          layout: layout,
                          inset: inset,
                          live: !searching && i == selected,
                        ),
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
                      child: _TabInset(
                        settled: inset,
                        live: searching,
                        child: _Beside(
                          inset: inset,
                          child: GlassSearchSupplement(
                            field: pageSearch
                                ? GlassSearchField(
                                    controller: widget.searchController,
                                  )
                                : null,
                            child: Builder(builder: searchBuilder),
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
    final scaffold = ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final layout = widget.layout.resolve(
            GlassEnvironment.of(context),
            size,
          );
          final list = searching || selected < 0
              ? null
              : _listToggle(selected, layout);
          if (layout.placement == GlassTabPlacement.bottom) {
            return _keys(
              toggle: list,
              child: GlassFloatingTabBar(
                tabBar: bar,
                backgroundColor: background,
                child: tabs(layout: layout, inset: 0, pageSearch: false),
              ),
            );
          }
          return _regular(
            size: size,
            layout: layout,
            selected: selected,
            searching: searching,
            background: background,
            listToggle: list,
            tabs: tabs,
          );
        },
      ),
    );
    return GlassSearchScope(
      controller: widget.searchController,
      child: scaffold,
    );
  }

  Widget _regular({
    required Size size,
    required GlassTabLayout layout,
    required int selected,
    required bool searching,
    required Color background,
    required VoidCallback? listToggle,
    required Widget Function({
      required GlassTabLayout layout,
      required double inset,
      required bool pageSearch,
    })
    tabs,
  }) {
    final controller = _controller;
    final beside = layout.sidebarBeside;
    if (_beside != null &&
        _beside != beside &&
        !widget.layout.remembersSidebar) {
      controller._forgetSidebar();
    }
    _beside = beside;
    final rail = layout.sidebarFolds && controller.sidebarRail;
    final shown =
        !layout.sidebarHides || (controller.sidebarShown ?? (beside || rail));
    final panel = layout.sidebarPanel;
    final margin =
        panel == GlassTabSidebarPanel.floating ||
            (panel == GlassTabSidebarPanel.flush && !beside)
        ? layout.sidebarMargin
        : 0.0;
    final range = layout.sidebarWidth;
    final band = MediaQuery.of(context).verticalBand;
    final widest = math.max(
      range.minimum,
      math.min(
        range.maximum,
        size.width - layout.minimumContentWidth - 2 * margin,
      ),
    );
    final maxWidth = band == null
        ? widest
        : math.min(
            widest,
            (Directionality.of(context) == TextDirection.ltr
                    ? band.left
                    : size.width - band.right) -
                2 * margin,
          );
    final minWidth = math.min(range.minimum, maxWidth);
    final width = (controller.sidebarWidth ?? range.preferred).clamp(
      minWidth,
      maxWidth,
    );
    final content = tabs(
      layout: layout,
      inset: !shown
          ? 0
          : rail
          ? layout.railWidth + 2 * margin
          : beside
          ? width + 2 * margin
          : 0,
      pageSearch: true,
    );
    final search = widget.searchController;
    final count = widget.tabs.length;
    final quiet =
        !searching &&
        selected >= 0 &&
        _split(selected, layout) &&
        (controller.splitOf(selected).showsPrimary ??
            _listByDefault(selected, layout));
    final strings = GlassLocalizations.of(context);
    final sideToggle = layout.sidebarHides
        ? (
            onPressed: () => controller.sidebarShown = false,
            semanticLabel: strings.hideSidebarLabel,
          )
        : layout.sidebarFolds
        ? (
            onPressed: () => controller._showSidebar(rail: !rail),
            semanticLabel: rail
                ? strings.showSidebarLabel
                : strings.hideSidebarLabel,
          )
        : null;
    return _keys(
      toggle:
          listToggle ??
          (shown
              ? sideToggle?.onPressed
              : () => controller.sidebarShown = true),
      child: _RegularChrome(
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
        onSelected: (index) {
          if (index == count) {
            search?.openView();
          } else if (search?.isOpen ?? false) {
            _show(index);
          } else {
            _select(index);
          }
        },
        beside: beside,
        sidebarShown: shown,
        onSidebar: (value) => controller.sidebarShown = value,
        rail: rail,
        onRail: (value) => controller._showSidebar(rail: value),
        toggle: sideToggle,
        sidebarWidth: width,
        minSidebarWidth: minWidth,
        maxSidebarWidth: maxWidth,
        railWidth: layout.railWidth,
        hides: layout.sidebarHides,
        folds: layout.sidebarFolds,
        onSidebarWidth: (value) => controller.sidebarWidth = value,
        onSidebarReset: controller._resetSidebar,
        resizable: widget.resizable,
        margin: margin,
        opaque: panel == GlassTabSidebarPanel.flush && beside,
        quiet: quiet,
        look: widget.style,
        semanticLabel: widget.semanticLabel,
        accessory: widget.bottomAccessory,
        action: widget.action,
        header: widget.sidebarHeader,
        footer: widget.sidebarFooter,
        topBackground: widget.sidebarTopBackground,
        rowBuilder: widget.sidebarRowBuilder,
        sidebarStyle: widget.sidebarStyle,
        background: background,
        child: content,
      ),
    );
  }
}

// Selects a tab for [GlassSelectTabIntent] while it can be selected.
// The focus scope of a tab or of the search. Tab goes on from its last
// control to the sidebar and the bars, as it does from a nested route's.
// A navigator asks its scope for the focus as it adds a page, whatever
// holds it: while a control outside the scope holds it, such as a sidebar
// row the keyboard selects tabs with, the tab built for it leaves it there.
class _TabFocus extends FocusScopeNode {
  _TabFocus(String debugLabel)
    : super(
        debugLabel: debugLabel,
        traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      );

  @override
  void requestFocus([FocusNode? node]) {
    final held = FocusManager.instance.primaryFocus;
    if (node == null &&
        held != null &&
        held is! FocusScopeNode &&
        !held.ancestors.contains(this)) {
      return;
    }
    super.requestFocus(node);
  }

  void take() => super.requestFocus();
}

class _SelectTab extends Action<GlassSelectTabIntent> {
  _SelectTab(this._state);

  final _GlassTabScaffoldState _state;

  @override
  bool isEnabled(GlassSelectTabIntent intent) {
    final tabs = _state.widget.tabs;
    return intent.index >= 0 &&
        intent.index < tabs.length &&
        tabs[intent.index].enabled;
  }

  @override
  void invoke(GlassSelectTabIntent intent) => _state._show(intent.index);
}

/// Selects the tab at [index] of the closest [GlassTabScaffold], as a tap on
/// its bar or its sidebar row does, but a selected tab stays as it is.
///
/// UIKit: none; an app binds command-1 to command-9 itself. Flutter: an
/// [Intent] that [Shortcuts] map keys to.
///
/// The scaffold selects only a tab it has and that is enabled, and closes
/// its search first.
class GlassSelectTabIntent extends Intent {
  /// Creates the intent of selecting the tab at [index].
  const GlassSelectTabIntent(this.index);

  /// The position of the tab in [GlassTabScaffold.tabs].
  final int index;

  /// Command-1 to command-9 to the first nine tabs, as a desktop app binds
  /// them, for [GlassTabScaffold.shortcuts].
  static const Map<ShortcutActivator, Intent> numberShortcuts = {
    SingleActivator(LogicalKeyboardKey.digit1, meta: true):
        GlassSelectTabIntent(0),
    SingleActivator(LogicalKeyboardKey.digit2, meta: true):
        GlassSelectTabIntent(1),
    SingleActivator(LogicalKeyboardKey.digit3, meta: true):
        GlassSelectTabIntent(2),
    SingleActivator(LogicalKeyboardKey.digit4, meta: true):
        GlassSelectTabIntent(3),
    SingleActivator(LogicalKeyboardKey.digit5, meta: true):
        GlassSelectTabIntent(4),
    SingleActivator(LogicalKeyboardKey.digit6, meta: true):
        GlassSelectTabIntent(5),
    SingleActivator(LogicalKeyboardKey.digit7, meta: true):
        GlassSelectTabIntent(6),
    SingleActivator(LogicalKeyboardKey.digit8, meta: true):
        GlassSelectTabIntent(7),
    SingleActivator(LogicalKeyboardKey.digit9, meta: true):
        GlassSelectTabIntent(8),
  };
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
