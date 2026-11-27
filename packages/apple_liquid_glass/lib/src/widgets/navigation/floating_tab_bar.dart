import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_room.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_bar.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// A [GlassTabBar] floating over the bottom of [child], which gets the room
/// the bar takes as its bottom padding.
///
/// UIKit: the tab bar of a `UITabBarController`. SwiftUI: the bar of a
/// `TabView`.
///
/// It is a `GlassTabScaffold` without the tabs' pages, for an app that
/// keeps them itself, with a navigation stack per tab or a rail on a wide
/// window, and switches them on the bar's `onDestinationSelected`.
///
/// ```dart
/// GlassFloatingTabBar(
///   tabBar: GlassTabBar(
///     destinations: destinations,
///     selectedIndex: tab,
///     onDestinationSelected: (index) => setState(() => tab = index),
///   ),
///   child: IndexedStack(index: tab, children: pages),
/// )
/// ```
///
/// The bar stands 21 points from the sides and the bottom, as wide as it
/// lays itself out and at the middle; a wide bar ([GlassTabBar.metricsOf])
/// 20 points above the bottom and at least 38 from the sides. A bar with a
/// search tab lays itself out over the whole of [child], whose bottom its
/// field rises from. The
/// media query padding of [child] grows at the bottom to clear the bar and
/// its bottom accessory, so content scrolls clear of the bar, and a
/// `GlassPageScaffold` or a `GlassContentScroll` under it sees the floating
/// bar at its bottom edge: the scroll edge under the bar and the bar's
/// minimizing follow the onstage content scroll. It draws nothing of its
/// own. The bar fades away in place while a page under it with
/// [GlassPageScaffold.hidesTabBar] shows, taking no touches, and the
/// padding of [child] gives its room back on the same curve.
///
/// Fidelity. The bar's 21 point inset is measured on iOS 27, the wide bar's
/// 20 on the iOS 27.2 simulator in landscape, which reads 38 at the sides
/// from UIKit; a landscape capture after a rotation that put the bar 39
/// above the bottom is taken for a layout that had not settled.
class GlassFloatingTabBar extends StatefulWidget {
  /// Floats [tabBar] over [child].
  const GlassFloatingTabBar({
    required this.tabBar,
    required this.child,
    this.backgroundColor,
    super.key,
  });

  /// The tab bar.
  final GlassTabBar tabBar;

  /// What the bar floats over: the selected tab's page.
  final Widget child;

  /// The color of the pages under the bar, which the scroll edge under it
  /// fades into; [GlassColors.systemBackground] by default. It is not
  /// painted.
  final Color? backgroundColor;

  @override
  State<GlassFloatingTabBar> createState() => _GlassFloatingTabBarState();
}

class _GlassFloatingTabBarState extends State<GlassFloatingTabBar> {
  final _active = ValueNotifier<MotionScroll?>(null);
  late final _hiding = GlassTabBarHiding(clock: MotionClockScope.of(context));
  late final _takesTouches = MotionSelection(
    () => _hiding.shown.target == 1,
    clock: MotionClockScope.of(context),
  );

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = GlassTabBar.metricsOf(context);
    final inset = metrics.bottomInset;
    final media = MediaQuery.of(context);
    final bar = widget.tabBar;
    final group = GlassTabBar.groupHeight(
      metrics,
      accessory: bar.bottomAccessory != null,
    );
    final bottom = math.max(media.padding.bottom, inset + group);
    final sides = BarRoom.sidesOf(context, inset: metrics.sideInset);
    Widget hiding(Widget bar) => MotionTransition(
      opacity: _hiding.shown,
      child: MotionVisibility(
        visible: _takesTouches,
        maintainPaint: true,
        child: bar,
      ),
    );
    return GlassChrome(
      edges: ChromeEdges(
        top: ChromeBar.none,
        topExtent: media.padding.top,
        scrolledUnderAfter: 0,
        bottom: ChromeBar.floating,
        bottomExtent: bottom,
        background: GlassDynamicColor.resolve(
          widget.backgroundColor ?? GlassColors.systemBackground,
          context,
        ),
      ),
      active: _active,
      outer: GlassChrome.maybeOf(context),
      tabBar: _hiding,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: _hiding.shown,
            builder: (context, child) => MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(
                  bottom: lerpDouble(
                    media.padding.bottom,
                    bottom,
                    _hiding.shown.value.clamp(0.0, 1.0),
                  ),
                ),
              ),
              child: child!,
            ),
            child: widget.child,
          ),
          if (bar.searchController != null)
            Positioned.fill(
              left: sides.left - metrics.sideInset,
              right: sides.right - metrics.sideInset,
              child: hiding(bar),
            )
          else
            Positioned(
              left: sides.left,
              right: sides.right,
              bottom: inset,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: hiding(bar),
              ),
            ),
        ],
      ),
    );
  }
}
