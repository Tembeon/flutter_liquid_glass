import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/tab_bar.dart';
import 'package:flutter/widgets.dart';
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
/// lays itself out and at the middle; a bar with a search tab lays itself
/// out over the whole of [child], whose bottom its field rises from. The
/// media query padding of [child] grows at the bottom to clear the bar and
/// its bottom accessory, so content scrolls clear of the bar, and a
/// `GlassPageScaffold` or a `GlassContentScroll` under it sees the floating
/// bar at its bottom edge: the scroll edge under the bar and the bar's
/// minimizing follow the onstage content scroll. It draws nothing of its
/// own.
///
/// Fidelity. The bar's 21 point inset is measured on iOS 27.
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

  /// The space between the sides and bottom of [child] and the bar.
  static const double inset = TabBarLayout.screenInset;

  @override
  State<GlassFloatingTabBar> createState() => _GlassFloatingTabBarState();
}

class _GlassFloatingTabBarState extends State<GlassFloatingTabBar> {
  final _active = ValueNotifier<MotionScroll?>(null);

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const inset = GlassFloatingTabBar.inset;
    final media = MediaQuery.of(context);
    final bar = widget.tabBar;
    final bottom = math.max(
      media.padding.bottom,
      inset + GlassTabBar.groupHeight(accessory: bar.bottomAccessory != null),
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: bottom),
            ),
            child: widget.child,
          ),
          if (bar.searchController != null)
            Positioned.fill(child: bar)
          else
            Positioned(
              left: inset,
              right: inset,
              bottom: inset,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: bar,
              ),
            ),
        ],
      ),
    );
  }
}
