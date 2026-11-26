part of 'package:apple_liquid_glass/src/widgets/navigation/tab_scaffold.dart';

/// A tab of a [GlassTabScaffold]: what its bar and sidebar show and the
/// page it starts from.
///
/// UIKit: `UITab`. SwiftUI: `Tab`. Flutter: `NavigationDestination` with
/// the page it selects.
///
/// [builder] builds the tab's root page, the bottom of its stack. With a
/// [detailPlaceholder], the tab is a list and the pages it opens: on a
/// regular width the root stands in a column beside the page pushed on it,
/// and the placeholder fills that place while nothing is pushed; on a
/// compact width the pages cover the list as any stack does.
@immutable
final class GlassTab {
  /// Creates a tab showing [icon] and [label] whose root page [builder]
  /// builds.
  const GlassTab({
    required this.icon,
    required this.label,
    required this.builder,
    this.detailPlaceholder,
    this.showsListButton = true,
    this.selectedIcon,
    this.badge,
    this.enabled = true,
    this.semanticLabel,
    this.id,
    this.onReselect,
    this.atSidebarEnd = false,
  });

  /// The tab's glyph, 24 points by default.
  final Widget icon;

  /// The tab's title.
  final Widget label;

  /// Builds the tab's root page.
  final WidgetBuilder builder;

  /// Builds what the detail column shows while nothing is pushed on the
  /// root, or null for a tab that is one stack at every width. It stands
  /// on a page with an empty navigation bar, which holds the split view's
  /// sidebar button while the root's column is hidden.
  final WidgetBuilder? detailPlaceholder;

  /// Whether the list column beside the pages has its button, the split
  /// view's sidebar button, which hides and shows it
  /// ([GlassSplitView.showsSidebarButton]). Without it the column always
  /// shows, and a drag of its edge stops at its minimum.
  final bool showsListButton;

  /// The glyph the tab shows while selected, or null for [icon].
  final Widget? selectedIcon;

  /// A mark at the top trailing corner of the glyph, usually a
  /// [GlassBadge].
  final Widget? badge;

  /// Whether the tab can be selected.
  final bool enabled;

  /// What accessibility reads for the tab; null reads the text of its
  /// label.
  final String? semanticLabel;

  /// What tells the tab apart across changes of the tabs, or null to tell
  /// it by its position.
  final Object? id;

  /// Called when the user selects the tab already selected, from its bar
  /// or its sidebar row, as an app scrolls the tab's page to its top; null
  /// pops the tab's stack to its root page, as UIKit does.
  final VoidCallback? onReselect;

  /// Whether the tab's row stands at the end of the tab sidebar, below the
  /// others, as an account tab stands
  /// ([GlassTabDestination.atSidebarEnd]); the bars keep the tabs' order.
  final bool atSidebarEnd;

  /// The tab as its bar shows it.
  GlassTabDestination get destination => GlassTabDestination(
    icon: icon,
    label: label,
    selectedIcon: selectedIcon,
    badge: badge,
    enabled: enabled,
    semanticLabel: semanticLabel,
    id: id,
    atSidebarEnd: atSidebarEnd,
  );
}

/// A page on the stack of a tab of a [GlassTabScaffold], above the tab's
/// root page.
///
/// The page keeps its state wherever the scaffold shows it: as a page
/// covering the tab on a compact width, or in the detail column on a
/// regular one. Each push makes a page of its own, so the same [child]
/// pushed twice makes two pages.
final class GlassTabPage {
  /// Creates a page showing [child].
  GlassTabPage({required this.child, this.title});

  /// The page's content, usually a [GlassPageScaffold].
  final Widget child;

  /// The page's name, as [GlassPageRoute.title] has it: what screen
  /// readers announce and what the back button of the page above shows
  /// when this page's navigation bar has no text title.
  final String? title;

  final GlobalKey _key = GlobalKey(debugLabel: 'GlassTabPage');
}

/// The selected tab and the stack of pages on each tab of a
/// [GlassTabScaffold].
///
/// UIKit: `UITabBarController.selectedTab` with each tab's
/// `UINavigationController.viewControllers`. Flutter: `TabController`.
///
/// The scaffold makes one when it is given none. An app that opens a tab
/// and its pages from outside, from a link or a notification, or keeps
/// them across launches gives its own and sets [index] and [setPages].
/// The scaffold writes here too: a tap on the bar selects, a back swipe
/// pops, so listeners hear what the hand did.
class GlassTabController extends ChangeNotifier {
  /// Creates a controller with the tab at [initialIndex] selected.
  GlassTabController({int initialIndex = 0})
    : assert(initialIndex >= 0, 'a tab index'),
      _index = initialIndex;

  int _index;
  final Map<int, List<GlassTabPage>> _stacks = {};
  bool? _sidebarShown;
  double? _sidebarWidth;
  bool _sidebarRail = false;
  bool _remembersSidebar = false;
  bool _restoring = false;
  final Map<int, GlassSplitViewController> _splits = {};

  /// The selected tab.
  int get index => _index;
  set index(int value) {
    assert(value >= 0, 'a tab index');
    if (value == _index) return;
    _index = value;
    notifyListeners();
  }

  /// Whether the tab sidebar shows, as a sidebar or as [sidebarRail] has it,
  /// or null for what the layout shows by itself: the rail, the sidebar
  /// where it stands beside the content, its button alone where the
  /// sidebar would cover the content. A layout whose sidebar cannot hide
  /// shows it whatever this says.
  ///
  /// The sidebar buttons, a tap on the content the sidebar dims and a drag
  /// of the sidebar's edge write here. Unless the scaffold's
  /// [GlassTabLayoutPolicy.remembersSidebar], a change between those two
  /// layouts, such as a rotation, sets it back to null without telling the
  /// listeners, as UIKit shows the sidebar by itself on a rotation to
  /// landscape; a rail stays as it is, as it looks the same in both.
  bool? get sidebarShown => _sidebarShown;
  set sidebarShown(bool? value) {
    if (value == _sidebarShown) return;
    _sidebarShown = value;
    notifyListeners();
  }

  /// The width a hand gave the tab sidebar, or null for the layout's
  /// preferred width ([GlassTabLayout.sidebarWidth]).
  ///
  /// The scaffold draws it within the layout's limits, leaving the content
  /// [GlassTabLayout.minimumContentWidth]: a narrower window draws the
  /// sidebar narrower and keeps this width. A drag of the sidebar's edge
  /// writes here when the hand lets go, its arrow keys at once, and a
  /// double tap on it sets it back to null.
  double? get sidebarWidth => _sidebarWidth;
  set sidebarWidth(double? value) {
    if (value == _sidebarWidth) return;
    _sidebarWidth = value;
    notifyListeners();
  }

  /// Whether the tab sidebar shows as a rail of its tabs' icons,
  /// [GlassTabLayout.railWidth] wide and beside the content in either
  /// layout, where [sidebarShown] shows it and the layout folds the
  /// sidebar ([GlassTabLayout.sidebarFolds]).
  ///
  /// A drag of the sidebar's edge past its minimum folds it into the rail,
  /// and past the rail hides it; a drag back out of the rail unfolds it,
  /// as do the arrow keys on its edge. The bar's sidebar button shows the
  /// sidebar in the form chosen last, and a double tap on the edge sets
  /// this back to false.
  bool get sidebarRail => _sidebarRail;
  set sidebarRail(bool value) {
    if (value == _sidebarRail) return;
    _sidebarRail = value;
    notifyListeners();
  }

  void _forgetSidebar() {
    if (!_sidebarRail) _sidebarShown = null;
  }

  // Shows the sidebar in the form [rail] says, as a hand folding it into
  // the rail or out of it does.
  void _showSidebar({required bool rail}) {
    if ((_sidebarShown ?? false) && _sidebarRail == rail) return;
    _sidebarShown = true;
    _sidebarRail = rail;
    notifyListeners();
  }

  void _resetSidebar() {
    if (_sidebarWidth == null && !_sidebarRail) return;
    _sidebarWidth = null;
    _sidebarRail = false;
    notifyListeners();
  }

  /// The split view controller of the tab at [tab] where it shows its list
  /// column beside its pages ([GlassTab.detailPlaceholder]): the width a
  /// hand gave the column and whether it shows, kept across a change of
  /// tab and of width as the tab's pages are. This controller makes it the
  /// first time it is asked, its listeners hear its changes, and it goes
  /// with the tab.
  GlassSplitViewController splitOf(int tab) =>
      _splits[tab] ??= GlassSplitViewController()..addListener(_splitChanged);

  void _splitChanged() {
    if (!_restoring) notifyListeners();
  }

  /// What the user chose of the layout, to keep across launches: the
  /// sidebar's width and form, each list's width and whether it shows, and
  /// whether the sidebar shows where the scaffold's policy remembers it
  /// ([GlassTabLayoutPolicy.remembersSidebar]).
  ///
  /// ```dart
  /// controller.layoutState = GlassTabLayoutState.fromJson(saved);
  /// controller.addListener(() => store(controller.layoutState.toJson()));
  /// ```
  ///
  /// Setting it replaces every choice and tells the listeners once.
  GlassTabLayoutState get layoutState => GlassTabLayoutState(
    sidebarShown: _remembersSidebar ? _sidebarShown : null,
    sidebarWidth: _sidebarWidth,
    sidebarRail: _sidebarRail,
    lists: {
      for (final MapEntry(key: tab, value: split) in _splits.entries)
        if (split.primaryWidth != null || split.showsPrimary != null)
          tab: GlassTabListState(
            width: split.primaryWidth,
            shown: split.showsPrimary,
          ),
    },
  );
  set layoutState(GlassTabLayoutState state) {
    _restoring = true;
    for (final tab in {..._splits.keys, ...state.lists.keys}) {
      final list = state.lists[tab];
      splitOf(tab)
        ..primaryWidth = list?.width
        ..showsPrimary = list?.shown;
    }
    _restoring = false;
    _sidebarShown = state.sidebarShown;
    _sidebarWidth = state.sidebarWidth;
    _sidebarRail = state.sidebarRail;
    notifyListeners();
  }

  /// The pages pushed on the root of the tab at [tab], bottom first.
  List<GlassTabPage> pagesOf(int tab) =>
      List.unmodifiable(_stacks[tab] ?? const <GlassTabPage>[]);

  /// Puts [pages] on the root of the tab at [tab], in place of what it
  /// had; an empty list leaves the root alone.
  void setPages(int tab, List<GlassTabPage> pages) {
    final old = _stacks[tab] ?? const <GlassTabPage>[];
    if (listEquals(old, pages)) return;
    if (pages.isEmpty) {
      _stacks.remove(tab);
    } else {
      _stacks[tab] = List.of(pages);
    }
    notifyListeners();
  }

  /// Pushes [page] on top of the tab at [tab].
  void push(int tab, GlassTabPage page) =>
      setPages(tab, [...pagesOf(tab), page]);

  /// Takes the top page off the tab at [tab]; the root stays.
  void pop(int tab) {
    final pages = pagesOf(tab);
    if (pages.isEmpty) return;
    setPages(tab, pages.sublist(0, pages.length - 1));
  }

  /// Takes every page off the tab at [tab], down to its root.
  void popToRoot(int tab) => setPages(tab, const []);

  /// Keeps the pages of the tab at [tab] up to [depth], the root being 0,
  /// and puts [page] above them.
  void _pushAbove(int tab, int depth, GlassTabPage page) {
    final pages = pagesOf(tab);
    setPages(tab, [...pages.take(depth), page]);
  }

  void _remove(int tab, GlassTabPage page) {
    final pages = pagesOf(tab);
    final at = pages.indexOf(page);
    if (at < 0) return;
    setPages(tab, pages.sublist(0, at));
  }

  void _forgetFrom(int count) {
    final splits = [
      for (final tab in _splits.keys.where((tab) => tab >= count).toList())
        ?_splits.remove(tab),
    ];
    if (splits.isNotEmpty) {
      // After the frame: the split views of the removed tabs listen to
      // their controllers until they unmount in it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final split in splits) {
          split.dispose();
        }
      });
    }
    final gone = _stacks.keys.where((tab) => tab >= count).toList();
    if (gone.isEmpty) return;
    gone.forEach(_stacks.remove);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final split in _splits.values) {
      split.dispose();
    }
    super.dispose();
  }
}

/// The stack of a tab of a [GlassTabScaffold] as a page on it sees it.
///
/// ```dart
/// onTap: () => GlassTabStack.of(context).push(MessagePage(message)),
/// ```
///
/// [push] puts a page right above the page that calls it, dropping what was
/// above: a row of the root list opens its page in the detail column on a
/// regular width, in place of the one open there, and a page pushes the
/// next one on top. A compact width shows the same stack as pages covering
/// each other, so the app makes the same call at every width.
@immutable
final class GlassTabStack {
  const GlassTabStack._(this._controller, this.tab, this.depth);

  /// The stack the page at [context] stands on.
  ///
  /// It is an error to call this outside a tab of a [GlassTabScaffold].
  static GlassTabStack of(BuildContext context) {
    final stack = maybeOf(context);
    assert(stack != null, 'No GlassTabScaffold tab above this context.');
    return stack!;
  }

  /// The stack the page at [context] stands on, or null outside a tab of a
  /// [GlassTabScaffold].
  static GlassTabStack? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassTabStackScope>()?.stack;

  final GlassTabController _controller;

  /// The tab whose stack this is.
  final int tab;

  /// Where the page stands on the stack: 0 for the tab's root page, 1 for
  /// the first page pushed on it.
  final int depth;

  /// Shows [page] right above this page, in place of the pages that were
  /// above it.
  void push(Widget page, {String? title}) => _controller._pushAbove(
    tab,
    depth,
    GlassTabPage(child: page, title: title),
  );

  /// Takes this page off the stack with the pages above it; the root page
  /// stays.
  void pop() {
    if (depth == 0) return;
    _controller.setPages(
      tab,
      _controller.pagesOf(tab).sublist(0, depth - 1),
    );
  }

  /// Takes every page off the stack, down to the root page.
  void popToRoot() => _controller.popToRoot(tab);

  @override
  bool operator ==(Object other) =>
      other is GlassTabStack &&
      identical(other._controller, _controller) &&
      other.tab == tab &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(_controller, tab, depth);
}

class _GlassTabStackScope extends InheritedWidget {
  _GlassTabStackScope({
    required GlassTabController controller,
    required int tab,
    required int depth,
    required super.child,
  }) : stack = GlassTabStack._(controller, tab, depth);

  final GlassTabStack stack;

  @override
  bool updateShouldNotify(_GlassTabStackScope oldWidget) =>
      stack != oldWidget.stack;
}
