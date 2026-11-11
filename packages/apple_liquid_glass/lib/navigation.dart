/// The scaffolding of an app: the navigation bar, the toolbar, the tab bar
/// with its tab scaffold, the page scaffold with what scrolls under the
/// bars (large titles, scroll edge effects), the page route with its zoom
/// transition, and search in the bars.
///
/// For the app developer: `GlassNavigationBar`, `GlassToolbar`,
/// `GlassTabBar`, `GlassTabScaffold`, `GlassPageScaffold`, `GlassPageRoute`
/// and the bar items they hold (`GlassBarItem`, `GlassBarSpacer`).
///
/// It promises that a bar moves by the measured laws of `motions` and
/// works with every renderer.
library;

export 'src/navigation/bar_entry.dart'
    show
        GlassBackButtonDisplayMode,
        GlassBarEntry,
        GlassBarItem,
        GlassBarItemStyle,
        GlassBarSpacer;
export 'src/navigation/chrome.dart'
    show
        GlassContentScroll,
        GlassPageScaffold,
        GlassScrollEdgeEffect,
        GlassScrollEdgeEffects;
export 'src/navigation/navigation_bar.dart'
    show GlassNavigationBar, GlassNavigationBarStyle;
export 'src/navigation/page_route.dart' show GlassPageRoute, GlassZoomSource;
export 'src/navigation/tab_bar.dart'
    show
        GlassTabAccessoryPlacement,
        GlassTabBar,
        GlassTabBarStyle,
        GlassTabDestination;
export 'src/navigation/tab_scaffold.dart' show GlassTabScaffold;
export 'src/navigation/toolbar.dart' show GlassToolbar, GlassToolbarStyle;
