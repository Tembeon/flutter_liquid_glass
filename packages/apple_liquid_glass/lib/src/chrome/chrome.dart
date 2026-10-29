import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How a [GlassContentScroll] separates its content where it passes under
/// a bar.
///
/// UIKit: `UIScrollEdgeEffect.Style`. SwiftUI: `ScrollEdgeEffectStyle`.
enum GlassScrollEdgeEffect {
  /// What UIKit picks for the bar at the edge: hard under a navigation
  /// bar, none under a floating toolbar or tab bar, soft under any other
  /// bar or the status bar.
  automatic,

  /// A light blur over a band reaching 40 points past the bar, fading into
  /// the background along it.
  soft,

  /// The thin film of a navigation bar: a blur with raised saturation over
  /// the bar's own band and a hairline at its edge.
  hard,

  /// None.
  hidden,
}

/// The edge effects of the top and bottom edges of a [GlassContentScroll].
///
/// SwiftUI: `scrollEdgeEffectStyle(_:for:)`.
@immutable
final class GlassScrollEdgeEffects {
  /// Creates the effects of both edges.
  const GlassScrollEdgeEffects({
    this.top = GlassScrollEdgeEffect.automatic,
    this.bottom = GlassScrollEdgeEffect.automatic,
  });

  /// The effect at the top edge.
  final GlassScrollEdgeEffect top;

  /// The effect at the bottom edge.
  final GlassScrollEdgeEffect bottom;

  @override
  bool operator ==(Object other) =>
      other is GlassScrollEdgeEffects &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);
}

/// The kind of bar at an edge of a page, which picks the automatic edge
/// effect.
@internal
enum ChromeBar {
  /// No bar.
  none,

  /// A navigation bar.
  navigation,

  /// A floating toolbar or tab bar.
  floating,

  /// Any other bar.
  custom,
}

/// A bar that tells the page's chrome what it is.
@internal
abstract interface class ChromeBarWidget implements PreferredSizeWidget {
  /// The kind of bar.
  ChromeBar get chromeBar;

  /// How far the content scrolls before it passes under the bar: the
  /// height of a large title the content scrolls away first.
  double get scrolledUnderAfter;
}

/// What a page's chrome tells the scroll views and bars under it.
@internal
@immutable
final class ChromeEdges {
  /// Describes the edges of a page.
  const ChromeEdges({
    required this.top,
    required this.topExtent,
    required this.scrolledUnderAfter,
    required this.bottom,
    required this.bottomExtent,
    required this.background,
  });

  /// The bar at the top.
  final ChromeBar top;

  /// The distance from the page's top to the top bar's far edge.
  final double topExtent;

  /// How far the content scrolls before it passes under the top bar.
  final double scrolledUnderAfter;

  /// The bar at the bottom.
  final ChromeBar bottom;

  /// The distance from the page's bottom to the bottom bar's far edge.
  final double bottomExtent;

  /// The page's background, resolved.
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is ChromeEdges &&
      other.top == top &&
      other.topExtent == topExtent &&
      other.scrolledUnderAfter == scrolledUnderAfter &&
      other.bottom == bottom &&
      other.bottomExtent == bottomExtent &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
    top,
    topExtent,
    scrolledUnderAfter,
    bottom,
    bottomExtent,
    background,
  );
}

/// The chrome of a page: its edges, and the scroll view its bars follow,
/// the latest onstage [GlassContentScroll] to claim it.
@internal
class GlassChrome extends InheritedWidget {
  /// Creates the chrome scope.
  const GlassChrome({
    required this.edges,
    required this.active,
    required super.child,
    super.key,
  });

  /// The page's edges.
  final ChromeEdges edges;

  /// The scroll view the bars follow, or null for none.
  final ValueNotifier<MotionScrollObserver?> active;

  /// The nearest chrome, or null outside a page.
  static GlassChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassChrome>();

  @override
  bool updateShouldNotify(GlassChrome oldWidget) =>
      edges != oldWidget.edges || active != oldWidget.active;
}

/// Marks the scroll view the bars of its page follow, and draws its edge
/// effects where its content passes under them.
///
/// UIKit: a `UIScrollView` whose edge a bar observes
/// (`contentScrollView(for:)`). SwiftUI: the scroll view a `NavigationStack`
/// or `TabView` finds. Flutter: `PrimaryScrollController`, without the
/// controller.
///
/// Wrap the page's main scroll view in it: the navigation bar fades its
/// title and the tab bar minimizes from it, through its notifications, so
/// any scrollable works without a controller. [notificationPredicate]
/// selects the scroll view among nested ones (depth 0 by default). Each
/// page of a `PageView` has its own; the bars follow the latest one shown.
/// Inside a [GlassPageScaffold] the content scrolls under the bars, and
/// each edge effect fades in, on UIKit's 0.35 s spring, once content lies
/// under its bar (navigation bar passport).
class GlassContentScroll extends StatefulWidget {
  /// Marks [child] as the page's scroll view.
  const GlassContentScroll({
    required this.child,
    this.edgeEffects = const GlassScrollEdgeEffects(),
    this.notificationPredicate = defaultScrollNotificationPredicate,
    super.key,
  });

  /// The scroll view.
  final Widget child;

  /// The effects at its top and bottom edges.
  final GlassScrollEdgeEffects edgeEffects;

  /// Which scroll notifications come from the page's scroll view.
  final ScrollNotificationPredicate notificationPredicate;

  /// The spring an edge effect fades on (fitted 0.34 - 0.35 s, critically
  /// damped; UIKit's `_UIBarScrollAwaySpec.duration` is 0.35).
  static const edgeSpring = Spring.response(0.35);

  @override
  State<GlassContentScroll> createState() => _GlassContentScrollState();
}

class _GlassContentScrollState extends State<GlassContentScroll> {
  late MotionScrollObserver _observer = _observe();
  final _top = MotionValue<double>(
    0,
    spring: GlassContentScroll.edgeSpring,
    restDistance: GlassRest.opacity,
  );
  final _bottom = MotionValue<double>(
    0,
    spring: GlassContentScroll.edgeSpring,
    restDistance: GlassRest.opacity,
  );
  GlassChrome? _chrome;
  ChromeEdges? _edges;
  bool _reduceMotion = false;
  bool _laidOut = false;

  MotionScrollObserver _observe() {
    final observer = MotionScrollObserver(
      predicate: widget.notificationPredicate,
    );
    observer.addListener(_scrolled);
    return observer;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = GlassChrome.maybeOf(context);
    if (!identical(chrome, _chrome)) _release();
    _chrome = chrome;
    _edges = chrome?.edges;
    _reduceMotion = GlassTraits.of(context).reduceMotion;
    _scrolled();
    if (TickerMode.valuesOf(context).enabled) _claim();
  }

  @override
  void didUpdateWidget(GlassContentScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationPredicate != widget.notificationPredicate) {
      _release();
      _observer.dispose();
      _observer = _observe();
      _claim();
    }
  }

  @override
  void dispose() {
    _release();
    _observer.dispose();
    super.dispose();
  }

  // The bars rebuild when the scroll view they follow changes, so the
  // claim waits for the end of the frame that built this one.
  void _claim() {
    final chrome = _chrome;
    if (chrome == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(chrome, _chrome)) {
        chrome.active.value = _observer;
      }
    });
  }

  void _release() {
    final active = _chrome?.active;
    if (active != null && identical(active.value, _observer)) {
      active.value = null;
    }
  }

  void _scrolled() {
    final after = _edges?.scrolledUnderAfter ?? 0;
    final metrics = _observer.metrics;
    final laidOut = metrics != null && metrics.hasContentDimensions;
    // Content under a bar when the page appears shows its effect at once.
    final appears = laidOut && !_laidOut;
    _laidOut = laidOut;
    _show(_top, laidOut && metrics.extentBefore > after + 0.5, appears);
    _show(_bottom, laidOut && metrics.extentAfter > 0.5, appears);
  }

  void _show(MotionValue<double> presence, bool shown, bool appears) {
    final target = shown ? 1.0 : 0.0;
    if (presence.target == target) return;
    final now = MotionClock.instance.now;
    if (_reduceMotion || appears) {
      presence.snap(now, target);
    } else {
      presence.retarget(now, target);
    }
  }

  bool? _hard(GlassScrollEdgeEffect style, ChromeBar bar) =>
      switch ((style, bar)) {
        (GlassScrollEdgeEffect.hidden, _) => null,
        (GlassScrollEdgeEffect.soft, _) => false,
        (GlassScrollEdgeEffect.hard, _) => true,
        (_, ChromeBar.navigation) => true,
        (_, ChromeBar.floating) => null,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final renderer = GlassTheme.rendererOf(context);
    final edges = _edges;
    final top = _hard(
      widget.edgeEffects.top,
      edges?.top ?? ChromeBar.none,
    );
    final bottom = _hard(
      widget.edgeEffects.bottom,
      edges?.bottom ?? ChromeBar.none,
    );
    final background =
        edges?.background ??
        GlassDynamicColor.resolve(GlassColors.systemBackground, context);
    final padding = MediaQuery.paddingOf(context);
    final topExtent = edges?.topExtent ?? padding.top;
    final bottomExtent = edges?.bottomExtent ?? padding.bottom;
    return NotificationListener<Notification>(
      onNotification: _observer.handle,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (top != null && topExtent > 0)
            Positioned.fill(
              child: renderer.buildScrollEdge(
                context,
                GlassScrollEdgeDetails(
                  edge: AxisDirection.up,
                  hard: top,
                  extent: topExtent,
                  presence: _top,
                  background: background,
                ),
              ),
            ),
          if (bottom != null && bottomExtent > 0)
            Positioned.fill(
              child: renderer.buildScrollEdge(
                context,
                GlassScrollEdgeDetails(
                  edge: AxisDirection.down,
                  hard: bottom,
                  extent: bottomExtent,
                  presence: _bottom,
                  background: background,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An iOS 27 page: its content scrolls under a navigation bar at the top
/// and a toolbar at the bottom.
///
/// UIKit: a `UIViewController`'s view with its navigation bar and toolbar.
/// SwiftUI: a view with `navigationTitle` and `toolbar` in a
/// `NavigationStack`. Flutter: `CupertinoPageScaffold`.
///
/// The bars float over [child]; the media query padding below them grows
/// by their extents, so a scroll view's content starts under the
/// navigation bar and can scroll clear of the toolbar, and a
/// [GlassContentScroll] in [child] draws its edge effects under them. A
/// tap on the status bar scrolls the content the bars follow to its
/// start, as `CupertinoPageScaffold` does it (500 ms, linear to ease out,
/// not measured).
class GlassPageScaffold extends StatefulWidget {
  /// Creates a page.
  const GlassPageScaffold({
    required this.child,
    this.navigationBar,
    this.toolbar,
    this.backgroundColor,
    super.key,
  });

  /// The bar at the top, below the status bar.
  final PreferredSizeWidget? navigationBar;

  /// The bar at the bottom.
  final PreferredSizeWidget? toolbar;

  /// The page's background; [GlassColors.systemBackground] by default.
  final Color? backgroundColor;

  /// The page's content.
  final Widget child;

  @override
  State<GlassPageScaffold> createState() => _GlassPageScaffoldState();
}

class _GlassPageScaffoldState extends State<GlassPageScaffold>
    with WidgetsBindingObserver {
  final _active = ValueNotifier<MotionScrollObserver?>(null);
  final _statusBar = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active.dispose();
    super.dispose();
  }

  @override
  void handleStatusBarTap() {
    final position = _active.value?.position;
    if (position == null || !position.hasPixels || !_foreground()) return;
    position
        .animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.linearToEaseOut,
        )
        .ignore();
  }

  // Only the page in front takes the tap: its status bar is what a touch
  // at the top of the screen hits.
  bool _foreground() {
    final box = _statusBar.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      box.localToGlobal(box.size.center(Offset.zero)),
      View.of(context).viewId,
    );
    return result.path.any((entry) => identical(entry.target, box));
  }

  static ChromeBar _kind(PreferredSizeWidget? bar, ChromeBar fallback) =>
      switch (bar) {
        null => ChromeBar.none,
        ChromeBarWidget(:final chromeBar) => chromeBar,
        _ => fallback,
      };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navigationBar = widget.navigationBar;
    final toolbar = widget.toolbar;
    final top = navigationBar == null
        ? media.padding.top
        : media.padding.top + navigationBar.preferredSize.height;
    final bottom = toolbar == null
        ? media.padding.bottom
        : media.padding.bottom + toolbar.preferredSize.height;
    final background = GlassDynamicColor.resolve(
      widget.backgroundColor ?? GlassColors.systemBackground,
      context,
    );
    final edges = ChromeEdges(
      top: _kind(navigationBar, ChromeBar.custom),
      topExtent: top,
      scrolledUnderAfter: switch (navigationBar) {
        ChromeBarWidget(:final scrolledUnderAfter) => scrolledUnderAfter,
        _ => 0,
      },
      bottom: _kind(toolbar, ChromeBar.custom),
      bottomExtent: bottom,
      background: background,
    );
    return GlassChrome(
      edges: edges,
      active: _active,
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(top: top, bottom: bottom),
              ),
              child: widget.child,
            ),
            if (navigationBar != null)
              Positioned(
                top: media.padding.top,
                left: 0,
                right: 0,
                child: navigationBar,
              ),
            if (toolbar != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: media.padding.bottom,
                child: toolbar,
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: media.padding.top,
              child: MetaData(
                key: _statusBar,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
